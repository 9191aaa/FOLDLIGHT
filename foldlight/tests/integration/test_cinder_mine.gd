extends SceneTree

const Bomber = preload("res://scripts/roguelite/enemies/cinder_mine.gd")
var failures: Array[String] = []
var blasts: Array[Dictionary] = []
var defeats: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	world.load_room(player, &"bomber_test", Vector2(2880, 1620), [], Color.WHITE, 511)
	world.activate()
	world.set_physics_process(false)
	var combat := world.combat_runtime
	combat.set_physics_process(false)
	combat.enemy_defeated.connect(func(_id: StringName) -> void: defeats += 1)
	var actor := _spawn(combat)
	var definition := FoldlightRogueContentCatalog.enemy_by_id(&"cinder_mine")
	_check(actor != null and definition != null and definition.validation_errors().is_empty(), "factory creates the authored bomber and resource validates")
	_check(definition.minimum_region == 2 and definition.max_simultaneous == 2, "bomber is gated to later regions and at most two authored actors")
	player.global_position = actor.global_position + Vector2(80, 0)
	var health_before := player.health
	_step(actor, 0.58, player.global_position)
	_check(actor.phase == Bomber.Phase.APPROACH and blasts.is_empty(), "spawn grace prevents immediate arming")
	_step(actor, 0.02, player.global_position)
	_check(actor.phase == Bomber.Phase.CHARGING and is_equal_approx(actor.get_phase_snapshot()["remaining"], 1.5), "entering range starts a complete 1.5 second countdown")
	var anchor := actor.global_position
	combat._update_enemies(0.0)
	_check(player.health == health_before and not actor.is_contact_dangerous(), "touching the bomber has no hidden early damage")
	_step(actor, 0.5, anchor + Vector2(500, 0))
	_check(actor.global_position.is_equal_approx(anchor) and actor.phase == Bomber.Phase.CHARGING, "charging bomber stays anchored after the player leaves")
	var before_pause := actor.get_phase_snapshot()
	combat.set_active(false)
	combat._physics_process(10.0)
	_check(before_pause == actor.get_phase_snapshot() and blasts.is_empty(), "pause freezes countdown and cosmetic time")
	combat.set_active(true)
	actor.advance_simulation(60.0, player.global_position)
	_check(blasts.is_empty() and actor.get_phase_snapshot()["remaining"] >= 0.89, "stalled frames cannot skip the telegraph")
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.set_setting(&"screen_shake", 0.0)
	actor.set_simulation_active(true)
	var quiet := actor.get_phase_snapshot()
	_step(actor, 0.1, player.global_position)
	_check(actor.get_phase_snapshot()["visual_time"] == quiet["visual_time"] and actor.get_phase_snapshot()["remaining"] < quiet["remaining"], "reduced motion freezes cosmetics while countdown remains functional")
	profile.set_setting(&"screen_shake", 1.0)
	var projectile := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.RIGHT * 500, "hostile": false, "damage": 20.0, "style": &"return_light"})
	combat._resolve_friendly_collision(projectile)
	actor.take_damage(20.0)
	_step(actor, 3.0, player.global_position)
	_check(blasts.is_empty() and defeats == 1 and combat.enemies.is_empty(), "real lethal return disarms a charging bomber and counts defeat exactly once")
	actor = _spawn(combat)
	player.global_position = actor.global_position + Vector2(80, 0)
	player.invulnerability = 0.0
	health_before = player.health
	_step(actor, 0.6, player.global_position)
	_step(actor, 1.48, player.global_position)
	_check(blasts.is_empty() and player.health == health_before, "no blast or damage occurs before the full countdown")
	_step(actor, 0.02, player.global_position)
	_check(blasts.size() == 1 and player.health == health_before - 1 and defeats == 2, "one in-range blast causes exactly one heart via shared damage and one defeat")
	_step(actor, 2.0, player.global_position)
	actor.take_damage(9.0)
	_check(blasts.size() == 1 and defeats == 2 and combat.projectiles.is_empty(), "spent bomber cannot explode again or create runaway projectiles")
	actor = _spawn(combat)
	_step(actor, 0.6, actor.global_position + Vector2(80, 0))
	player.global_position = actor.global_position + Vector2(200, 0)
	player.invulnerability = 0.0
	health_before = player.health
	_step(actor, 1.5, player.global_position)
	_check(player.health == health_before and blasts.size() == 2, "moving outside the 160px circle safely avoids the blast")
	actor = _spawn(combat)
	player.global_position = actor.global_position + Vector2(80, 0)
	player.invulnerability = 0.0
	_step(actor, 0.6, player.global_position)
	_step(actor, 1.4, player.global_position)
	_check(player.request_dash(Vector2.RIGHT), "a ready dash can start during the final fuse window")
	_step(actor, 0.1, player.global_position)
	_check(player.health == health_before, "real dash invulnerability protects against the blast inside its radius")
	actor = _spawn(combat)
	player.global_position = actor.global_position + Vector2(80, 0)
	player.invulnerability = 0.0
	combat._shield_charges = 1
	combat._shield_remaining = 10.0
	_step(actor, 2.1, player.global_position)
	_check(player.health == health_before and combat._shield_charges == 0, "existing shield charges also absorb a bomber blast")
	var first := _spawn(combat)
	var second := _spawn(combat)
	player.global_position = first.global_position + Vector2(80, 0)
	player.invulnerability = 0.0
	_step(first, 2.1, player.global_position)
	_step(second, 2.1, player.global_position)
	_check(player.health == health_before - 1 and defeats == 7, "overlapping blasts respect shared mercy frames without double damage or double defeat")
	var tracker := FoldlightMechanicIntroductionTracker.new()
	root.add_child(tracker)
	var intro := tracker.request_introduction(definition)
	_check(intro.get("attack_style") == &"anchored_blast" and not str(intro.get("counterplay", "")).is_empty(), "first encounter teaches its explosion radius and disarming counterplay")
	_check(tracker.request_introduction(definition).is_empty(), "bomber introduction is shown only once")
	tracker.queue_free()
	world.queue_free()
	player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_CINDER_MINE: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _spawn(combat: FoldlightRogueCombatRuntime) -> Bomber:
	var actor := combat._spawn_enemy_from_entry({"enemy_id": &"cinder_mine", "spawn_position": Vector2(1200, 800)}, false) as Bomber
	actor.blast_requested.connect(func(snapshot: Dictionary) -> void: blasts.append(snapshot.duplicate(true)))
	return actor


func _step(actor: Bomber, seconds: float, target: Vector2) -> void:
	for index in int(round(seconds / 0.02)):
		actor.advance_simulation(0.02, target)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
