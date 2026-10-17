extends SceneTree

const Seraph = preload("res://scripts/roguelite/enemies/shutter_seraph.gd")
const Definition = preload("res://resources/roguelite/enemies/shutter_seraph.tres")
var failures: Array[String] = []
var volleys: Array[Dictionary] = []
var impacts: Array[StringName] = []
var damaged_count: int = 0
var defeated_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"seraph_contract", Vector2(2880, 1620), [], Color.WHITE, 40101)
	world.activate()
	world.set_physics_process(false)
	player.set_physics_process(false)
	var combat := world.combat_runtime
	combat.set_physics_process(false)
	var actor := FoldlightRogueEnemyFactory.create(Definition, &"seraph_test") as Seraph
	combat.room.enemy_container.add_child(actor)
	actor.global_position = Vector2(1200, 800)
	actor.set_meta("counts_for_room", false)
	combat.enemies.append(actor)
	actor.volley_requested.connect(func(snapshot: Dictionary) -> void:
		volleys.append(snapshot.duplicate(true))
		combat.spawn_hostile_volley(snapshot))
	actor.damaged.connect(func(_amount: float, _health: float) -> void: damaged_count += 1)
	actor.defeated.connect(func(_enemy: Node2D) -> void: defeated_count += 1)
	actor.defeated.connect(combat._on_enemy_defeated)
	combat.impact_confirmed.connect(func(kind: StringName, _weight: float) -> void: impacts.append(kind))
	player.global_position = actor.global_position + Vector2(220, 0)
	check(actor != null and Definition.role == FoldlightRogueEnemyDefinition.EnemyRole.ELITE and Definition.base_health == 14.0, "factory creates the independent 14 HP elite instead of a generic enemy")
	check(Definition.minimum_region == 2 and Definition.max_simultaneous == 1 and Definition.threat_cost == 6, "definition restricts the elite to later regions with a bounded threat quota")
	check(Definition.validation_errors().is_empty(), "elite definition satisfies the content resource contract")
	var health_before := actor.health
	var random_before: int = combat._rng.state
	var shot := _shot(combat, actor.global_position, &"crease_petal", 2.0)
	shot.echo_chance = 1.0
	combat._resolve_friendly_collision(shot)
	check(actor.health == health_before and damaged_count == 0 and impacts.is_empty(), "closed wings reject a real weapon collision without damage or successful impact sound")
	check(actor.get_phase_snapshot()["shield_flash"] > 0.0 and actor.get_hit_feedback_snapshot()["flash"] == 0.0, "blocked contact flashes the shield without showing an exposed-core hit")
	check(combat.projectiles.is_empty() and combat._rng.state == random_before, "blocked weapon contact consumes its projectile without minting an echo or consuming proc RNG")
	check(player.feedback_budget._pending_count == 0, "an immune contact cannot register a successful impact reward")
	_clear_projectiles(combat)
	var other := combat._spawn_enemy_from_entry({"enemy_id": &"fan", "spawn_position": actor.global_position + Vector2(700, 0)}, false)
	var returned := _shot(combat, actor.global_position, &"return_light", 4.0)
	returned.return_chain_remaining = 2
	combat._resolve_friendly_collision(returned)
	check(actor.health == health_before and not combat.projectiles.has(returned) and returned.return_chain_remaining == 2, "immune return contact cannot trigger a chain toward another live enemy")
	combat.enemies.erase(other)
	other.queue_free()
	_clear_projectiles(combat)
	var blast := FoldlightRogueActiveItemDefinition.new()
	blast.content_id = &"seraph_test_blast"
	blast.effect_id = &"radial_push"
	blast.power = 3.0
	blast.duration = 0.3
	combat._on_active_item_used(blast)
	combat.damage_all_enemies(100.0)
	check(actor.health == health_before and damaged_count == 0, "active radial damage and universal damage both respect closed immunity")
	var bell := _shot(combat, actor.global_position, &"tide_bell", 2.0)
	bell.echo_chance = 1.0
	player.feedback_budget.reset()
	random_before = combat._rng.state
	combat._resolve_friendly_collision(bell)
	check(actor.health == health_before and combat.projectiles.is_empty() and combat._rng.state == random_before and player.feedback_budget._pending_count == 0, "area weapon blocked by the only target also produces no proc or fake impact")
	_clear_projectiles(combat)
	var before_phase := actor.get_phase_snapshot()
	combat.set_active(false)
	combat._physics_process(10.0)
	check(actor.get_phase_snapshot() == before_phase and volleys.is_empty(), "combat pause freezes phase time, visuals and firing")
	combat.set_active(true)
	combat._update_enemies(0.1)
	check(float(actor.get_phase_snapshot()["remaining"]) < float(before_phase["remaining"]), "the shared combat runtime advances the new elite after resume")
	actor.configure(Definition, &"seraph_test")
	actor.advance_simulation(90.0, player.global_position)
	check(actor.phase == Seraph.Phase.CLOSED and volleys.is_empty() and actor._phase_remaining >= 2.29, "a huge delta cannot skip the warning or emit a catch-up burst")
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	var old_motion: float = float(profile.get_setting(&"screen_shake", 1.0))
	profile.set_setting(&"screen_shake", 0.0)
	actor.set_simulation_active(true)
	var quiet_before := actor.get_phase_snapshot()
	actor.advance_simulation(0.1, player.global_position)
	check(actor._motion_scale == 0.0 and actor._visual_time == quiet_before["visual_time"] and actor._phase_remaining < quiet_before["remaining"], "zero motion disables cosmetic movement while the fair combat phase clock still advances")
	profile.set_setting(&"screen_shake", old_motion)
	actor.set_simulation_active(true)
	actor.configure(Definition, &"seraph_test")
	_step(actor, 2.4, player.global_position)
	check(actor.phase == Seraph.Phase.CHARGING and volleys.is_empty(), "closed drift lasts 2.4 seconds before the visible charge")
	actor.take_projectile_damage(50.0, Vector2.LEFT, &"return_light")
	_step(actor, 0.78, player.global_position)
	check(actor.health == health_before and actor.phase == Seraph.Phase.CHARGING and volleys.is_empty(), "the full 0.8 second charge remains immune and emits no bullets early")
	_step(actor, 0.02, player.global_position)
	check(actor.phase == Seraph.Phase.FIRING and actor.is_damageable() and volleys.size() == 1 and combat.projectiles.size() == 5, "opening the core begins vulnerability and the first five-shot volley together")
	var first_direction: Vector2 = volleys[0]["direction"]
	var opposite_target := actor.global_position - first_direction * 500.0
	_step(actor, 0.60, opposite_target)
	var fixed_group := true
	for index in mini(5, volleys.size()):
		fixed_group = fixed_group and Vector2(volleys[index]["direction"]).is_equal_approx(first_direction)
	check(fixed_group and volleys.size() == 6 and absf(first_direction.angle_to(volleys[5]["direction"])) <= Seraph.MAX_GROUP_TURN + 0.001, "five volleys keep one aim lane and the next group turns at most 0.24 radians")
	var firing_before := actor.get_phase_snapshot()
	combat.set_active(false)
	combat._physics_process(5.0)
	check(actor.get_phase_snapshot() == firing_before and volleys.size() == 6, "pausing during the exposed fire window preserves both vulnerability time and volley count")
	combat.set_active(true)
	_step(actor, 1.80, opposite_target)
	check(actor.phase == Seraph.Phase.CLOSING and volleys.size() == 20 and combat.projectiles.size() == 100, "a 2.4 second fire window emits exactly 20 volleys and 100 bullets at the authored cadence")
	var all_captureable := true
	for bullet in combat.projectiles:
		all_captureable = all_captureable and bullet.hostile and bullet.reflectable and is_equal_approx(bullet.velocity.length(), 245.0) and is_equal_approx(bullet.radius, 5.5)
	check(all_captureable, "the dense volley keeps its bounded speed, small radius and captureable status")
	actor.take_damage(100.0)
	check(actor.health == health_before and not actor.is_damageable(), "closing wings immediately restore full immunity")
	_step(actor, 0.4, player.global_position)
	check(actor.phase == Seraph.Phase.CLOSED, "closing returns to the readable drift phase without lingering vulnerability")
	var captured_before := player.captured
	player.folding = true
	for bullet in combat.projectiles:
		bullet.global_position = player.global_position + Vector2(0, 700)
	combat.projectiles[0].global_position = player.global_position + Vector2(0, 40)
	combat._update_projectiles(0.0)
	check(player.captured > captured_before and player.captured <= player.get_capture_capacity(), "real volley bullets can enter the player fold and obey storage capacity")
	player.folding = false
	_clear_projectiles(combat)
	for index in 60:
		combat.spawn_hostile_volley(volleys[0])
	check(combat.projectiles.size() == FoldlightRogueCombatRuntime.MAX_PROJECTILES, "repeated elite volleys obey the existing global projectile budget")
	_clear_projectiles(combat)
	_step(actor, 3.2, player.global_position)
	check(actor.is_damageable(), "the next natural cycle reopens a usable damage window")
	_clear_projectiles(combat)
	impacts.clear()
	combat._impact_cooldowns.clear()
	player.global_position = actor.global_position + Vector2(220, 0)
	combat._resolve_friendly_collision(_shot(combat, actor.global_position, &"crease_petal", 1.0))
	combat._resolve_friendly_collision(_shot(combat, actor.global_position, &"return_light", 2.0))
	combat._on_active_item_used(blast)
	check(is_equal_approx(actor.health, 8.0) and damaged_count == 3 and impacts.has(&"weapon") and impacts.has(&"return"), "weapon, return and real active AOE damage all work during firing")
	check(actor.get_hit_feedback_snapshot()["flash"] > 0.0 and actor.get_hit_feedback_snapshot()["punch"] > 0.0, "exposed-core damage supplies the existing hit feedback contract")
	combat._resolve_friendly_collision(_shot(combat, actor.global_position, &"return_light", 20.0))
	actor.take_damage(20.0)
	check(defeated_count == 1 and actor.is_queued_for_deletion() and combat.enemies.is_empty(), "a real lethal return removes the elite and reports defeat exactly once")
	world.queue_free()
	player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_SHUTTER_SERAPH: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _step(actor: Seraph, seconds: float, target: Vector2) -> void:
	for index in int(round(seconds / 0.02)):
		actor.advance_simulation(0.02, target)


func _shot(combat: FoldlightRogueCombatRuntime, origin: Vector2, style: StringName, damage: float) -> FoldlightRogueProjectile:
	return combat._spawn_projectile({"origin": origin, "velocity": Vector2.LEFT * 500, "hostile": false, "damage": damage, "style": style})


func _clear_projectiles(combat: FoldlightRogueCombatRuntime) -> void:
	for projectile in combat.projectiles.duplicate():
		combat._remove_projectile(projectile)


func check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
