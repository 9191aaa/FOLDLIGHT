extends SceneTree

const BOSS = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
const STEP := 1.0 / 60.0
const WORLD := Rect2(0, 0, 4800, 3200)
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	await _test_charge_chain(0, 0, 4)
	await _test_charge_chain(2, 5, 8)
	_test_warning_stall()
	await _test_charge_cancellation()
	await _test_charge_wall_and_contact()
	await _test_command_field()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_PRESSURE_3_18: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _boss(id: StringName, tier: int = 0) -> FoldlightRogueBossActor:
	var actor := BOSS.instantiate() as FoldlightRogueBossActor
	root.add_child(actor)
	actor.configure(FoldlightRogueContentCatalog.boss_by_id(id), WORLD, 31801, {"endless_roam": true, "arena_pressure": false, "intensity_tier": tier})
	actor.position = Vector2(1600, 1200)
	return actor


func _test_charge_chain(phase: int, tier: int, expected_count: int) -> void:
	var actor := _boss(&"torn_page_executioner", tier)
	if phase == 2: actor.health = actor.maximum_health * 0.3
	var warnings: Array[Dictionary] = []
	actor.telegraph_requested.connect(func(value: Dictionary) -> void:
		if value.get("pattern_id") == &"execution_dash": warnings.append(value.duplicate(true))
	)
	var target := actor.position + Vector2(500, 0)
	var started := false
	var stationary_warnings := true
	var first_locked := true
	for tick in 1800:
		var before := actor.position
		var stage := actor._charge_stage
		actor.advance_simulation(STEP, target)
		if not warnings.is_empty() and not started:
			started = true
			target = Vector2(warnings[0]["origin"]) + Vector2(-300, 650)
		if stage == &"warning" and actor._charge_stage == &"warning":
			stationary_warnings = stationary_warnings and before.is_equal_approx(actor.position)
		if actor._charge_number == 1 and actor._charge_stage == &"dash":
			first_locked = first_locked and absf(actor.position.y - Vector2(warnings[0]["origin"]).y) < 0.1
		if started and actor._charge_number > 0 and actor._charge_stage.is_empty() and actor.phase_controller.state == FoldlightBossPhaseController.State.RECOVERY: break
	_check(started and warnings.size() == expected_count and actor._charge_left == 0, "phase %d tier %d completes %d real individually warned charges" % [phase, tier, expected_count])
	_check(stationary_warnings and first_locked, "chain locks each aim and stops the body during intervening warnings")
	var numbered := true
	for index in warnings.size():
		var event := warnings[index]
		numbered = numbered and int(event.get("charge_number", 0)) == index + 1 and int(event.get("charge_total", 0)) == expected_count
		numbered = numbered and float(event["duration"]) >= 0.42 and float(event["hold_seconds"]) >= 0.20
		if index > 0: numbered = numbered and Vector2(event["target_position"]).is_equal_approx(target)
	_check(numbered, "every charge publishes a bounded warning, active hold and fresh locked target")
	_check(not actor.is_contact_dangerous() or not actor.get_contact_sweep().is_empty(), "recovery only retains the just-completed actual contact sweep")
	actor.queue_free()
	await process_frame


func _test_charge_cancellation() -> void:
	for reason in [&"stagger", &"death", &"timeout"]:
		var actor := _boss(&"torn_page_executioner")
		var target := actor.position + Vector2(500, 0)
		for tick in 240:
			actor.advance_simulation(STEP, target)
			if actor._charge_stage == &"dash": break
		_check(actor._charge_stage == &"dash", "%s fixture reaches the actual charge" % reason)
		actor.set_simulation_active(false)
		var before := actor.get_combat_snapshot()
		var remaining := actor.phase_controller._remaining
		actor.advance_simulation(8.0, target)
		_check(actor.get_combat_snapshot() == before and actor.phase_controller._remaining == remaining, "pause freezes chain position, stage and controller clock")
		actor.set_simulation_active(true)
		match reason:
			&"stagger": actor.take_damage(22.4, &"return")
			&"death": actor.take_damage(actor.maximum_health * 2.0)
			&"timeout": actor.advance_simulation(20.0, target)
		_check(actor._charge_stage.is_empty() and actor._charge_left == 0 and actor.get_contact_sweep().is_empty(), "%s discards all pending chain movement and damage" % reason)
		actor.queue_free()
		await process_frame


func _test_warning_stall() -> void:
	var marker := FoldlightBossAttackTelegraph.new()
	root.add_child(marker)
	marker.configure({"pattern_id": &"execution_dash", "duration": 0.42, "hold_seconds": 0.24,
		"origin": Vector2(600,600), "target_position": Vector2(1000,600), "charge_number": 2, "charge_total": 6,
		"attack_lanes": [{"origin": Vector2(600,600), "end": Vector2(1000,600), "width": 128.0, "reflectable": false, "dash": true}]})
	marker._process(4.0)
	_check(not marker.is_queued_for_deletion() and is_equal_approx(marker.remaining, 0.56), "one stalled render frame cannot consume the short charge warning and active marker")
	marker.set_simulation_active(false)
	marker._process(4.0)
	_check(is_equal_approx(marker.remaining, 0.56), "paused charge warning remains fully frozen after a render stall")
	marker.queue_free()


func _test_charge_wall_and_contact() -> void:
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"charge_collision", Vector2(2880,1620), [], Color.WHITE, 318)
	world.activate()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.position = Vector2(1100,600)
	var combat := world.combat_runtime
	var actor := combat._spawn_enemy_from_entry({"boss_id": &"torn_page_executioner", "spawn_position": Vector2(600,600), "boss_options": {"arena_pressure": false}}, false) as FoldlightRogueBossActor
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var wall := StaticBody2D.new()
	wall.collision_layer = 1 << 2
	wall.collision_mask = 0
	wall.position = Vector2(900,600)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(40,1200)
	shape.shape = rectangle
	wall.add_child(shape)
	root.add_child(wall)
	await physics_frame
	_check(PhysicsServer2D.body_get_space(actor.get_rid()).is_valid(), "manual-step fixture retains the real physics body while automatic timers are disabled")
	var health := player.health
	for tick in 240:
		combat._update_enemies(STEP)
		if actor._charge_number == 2: break
	_check(actor._charge_number == 2 and actor.position.x < 840 and player.health == health, "actual charge collides with terrain and never damages across the wall")
	wall.queue_free()
	combat.clear_combat()
	await physics_frame
	actor = combat._spawn_enemy_from_entry({"boss_id": &"torn_page_executioner", "spawn_position": Vector2(600,600), "boss_options": {"arena_pressure": false}}, false) as FoldlightRogueBossActor
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.position = Vector2(800,600)
	player.invulnerability = 0.0
	await physics_frame
	for tick in 200:
		combat._update_enemies(STEP)
		if player.health < health: break
	_check(player.health == health - 1 and actor._charge_number == 1, "shared runtime applies one real swept body hit during the warned charge")
	actor.phase_controller.enter_stagger(2.0)
	player.invulnerability = 0.0
	player.position = actor.position
	combat._update_enemies(STEP)
	_check(player.health == health - 1, "staggered executioner contact cannot deal hidden charge damage")
	world.queue_free()
	player.queue_free()
	await process_frame


func _test_command_field() -> void:
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"command_field", Vector2(4800,3200), [], Color.WHITE, 318)
	world.activate()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.position = Vector2(4000,2600)
	var combat := world.combat_runtime
	var normal := combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1600,1200)}, false) as FoldlightRogueEnemyActor
	normal.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var original_health := normal.definition.base_health
	var original_speed := normal.definition.move_speed
	var early := combat._spawn_enemy_from_entry({"boss_id": &"tide_loom_mother", "spawn_position": Vector2(1500,1200), "boss_options": {"arena_pressure": false}}, false) as FoldlightRogueBossActor
	var late := combat._spawn_enemy_from_entry({"boss_id": &"tide_loom_mother", "spawn_position": Vector2(1500,1100), "boss_options": {"arena_pressure": false, "intensity_tier": 5}}, false) as FoldlightRogueBossActor
	early.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	late.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	early.advance_simulation(1.4, player.position)
	late.health = late.maximum_health * 0.3
	late.advance_simulation(STEP, player.position)
	var stronger := late.get_command_aura_snapshot()
	var weaker := early.get_command_aura_snapshot()
	_check(float(stronger.radius) > float(weaker.radius) and float(stronger.move_multiplier) > float(weaker.move_multiplier) and float(stronger.attack_interval_multiplier) < float(weaker.attack_interval_multiplier), "later phases expand command reach and independently accelerate movement and attacks")
	for index in 120: combat._update_command_links()
	var applied := normal.get_command_buff_snapshot()
	_check(is_equal_approx(float(applied.move_multiplier), float(stronger.move_multiplier)) and is_equal_approx(float(applied.attack_interval_multiplier), float(stronger.attack_interval_multiplier)), "overlapping commanders choose the strongest effects without repeated multiplication")
	var attacks: Array[Dictionary] = []
	normal.attack_requested.connect(func(value: Dictionary) -> void: attacks.append(value))
	normal._attack_remaining = 0.001
	normal.advance_simulation(STEP, Vector2(2600,1200))
	_check(attacks.size() == 1 and is_equal_approx(float(attacks[0]["projectiles"][0]["speed"]), 160.0 * float(stronger.projectile_speed_multiplier)), "commanded ordinary enemy emits physically faster bullets")
	for tick in 240: normal.advance_simulation(STEP, Vector2(3600,1200))
	_check(normal.velocity.length() < (original_speed + 35.0) * 2.21 and normal.definition.base_health == original_health and normal.definition.move_speed == original_speed, "long buff exposure stays bounded and never edits the shared enemy resource")
	normal.position = Vector2(4500,2800)
	combat._update_command_links()
	_check(normal.get_command_buff_snapshot() == {"move_multiplier": 1.0, "projectile_speed_multiplier": 1.0, "attack_interval_multiplier": 1.0}, "leaving every drawn command circle immediately restores original stats")
	normal.position = Vector2(1600,1200)
	combat._update_command_links()
	late.phase_controller.enter_stagger(2.0)
	_check(is_equal_approx(normal.command_move_multiplier, float(weaker.move_multiplier)), "stagger instantly removes that commander while preserving another live field")
	early.take_damage(early.maximum_health * 2.0)
	_check(is_equal_approx(normal.command_move_multiplier, 1.0) and is_equal_approx(normal.support_attack_multiplier, 1.0), "killing the remaining commander clears its buffs synchronously")
	for minion in combat.enemies.duplicate():
		if StringName(minion.get_meta("spawned_by", &"")) == late.actor_id:
			combat.retire_directed_enemy(minion)
	combat.directed_spawn_allowance = 2
	combat.directed_threat_allowance = 20
	var population := combat.enemies.size()
	late.request_opening_support()
	late.request_opening_support()
	_check(combat.enemies.size() == population + 2, "loom replenishment obeys the shared live allowance even after repeated requests")
	world.queue_free()
	player.queue_free()
	await process_frame


func _check(value: bool, label: String) -> void:
	checks += 1
	print(("[PASS] " if value else "[FAIL] ") + label)
	if not value: failures.append(label)
