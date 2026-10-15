extends SceneTree

const Target = preload("res://scripts/endless/endless_objective_target.gd")
const Director = preload("res://scripts/endless/endless_objective_director.gd")
var failures: Array[String] = []
var damage_events: Array[float] = []
var defeat_events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"objective_contract", Vector2(2880, 1620), [], Color.WHITE, 9191)
	world.activate()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector2(700, 600)
	var combat := world.combat_runtime
	combat.enemy_defeated_detailed.connect(func(_id: StringName, entry: Dictionary) -> void: defeat_events.append(entry))
	var director := Director.new()
	root.add_child(director)
	var config := load("res://resources/endless/endless_survival_default.tres") as FoldlightEndlessSurvivalConfig
	var map := load("res://resources/endless/maps/folded_delta.tres") as FoldlightEndlessMapDefinition
	director.reset(config, map, 2)
	var snapshot := director.get_snapshot()
	snapshot["target_position"] = Vector2(1000, 600)
	var actor := Target.new()
	actor.configure(snapshot)
	actor.damage_reported.connect(func(id: StringName, damage: float) -> void:
		damage_events.append(damage)
		director.report_flag_damage(id, damage)
	)
	check(combat.register_objective_target(actor, {"target_id": snapshot["target_id"]}), "real objective registers in shared targeting")
	check(not combat.register_objective_target(actor), "registering the same target cannot duplicate collision or death callbacks")
	check(actor.global_position == Vector2(1000, 600) and actor.get_node("CollisionShape2D").shape is CircleShape2D, "target uses the advertised world position and a real circle hit shape")
	check(not bool(actor.get_meta("counts_for_room", true)), "target cannot advance room enemy completion quotas")
	var initial := actor.health
	for index in 30:
		actor.advance_simulation(0.1, player.global_position)
		director.advance(0.1, actor.global_position)
	check(is_equal_approx(actor.health, initial) and damage_events.is_empty(), "proximity and visual animation never synthesize damage")
	combat._on_player_shot_requested({"damage": 3.0, "projectile_speed": 800.0, "volley_count": 1})
	check(combat.projectiles.size() == 1, "ordinary auto-aim weapon can acquire the registered target")
	for frame in 30:
		combat._update_projectiles(1.0 / 60.0)
	check(is_equal_approx(actor.health, initial - 3.0) and damage_events == [3.0], "a travelling ordinary projectile deals and reports actual damage once")
	var relay_candidate := combat._spawn_enemy_from_entry({"enemy_id": &"fan", "spawn_position": Vector2(1450, 600)}, false)
	var returned := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.RIGHT * 600.0, "hostile": false, "damage": 5.0, "style": &"return_light"})
	combat._resolve_friendly_collision(returned)
	check(is_equal_approx(actor.health, initial - 8.0) and damage_events.back() == 5.0, "returned light damages the same physical target")
	check(not returned.return_relay_used and not combat.projectiles.has(returned), "a nonlethal flag hit cannot trigger the defeat-only return relay")
	combat.enemies.erase(relay_candidate)
	relay_candidate.queue_free()
	combat._damage_enemies_in_radius(actor.global_position, 100.0, 4.0)
	check(is_equal_approx(actor.health, initial - 12.0) and damage_events.back() == 4.0, "active area damage advances actual flag progress")
	check(is_equal_approx(float(director.get_snapshot()["progress"]), 12.0), "director progress agrees exactly with total applied health loss")
	combat.set_active(false)
	var frozen_time: float = actor._visual_time
	var frozen_health := actor.health
	actor.advance_simulation(5.0)
	check(not actor.take_damage(1.0) and actor.health == frozen_health and actor._visual_time == frozen_time, "pause freezes the target and rejects late damage events")
	combat.set_active(true)
	var completed: Array[Dictionary] = []
	director.objective_completed.connect(func(value: Dictionary) -> void:
		completed.append(value)
		combat.set_active(false)
	)
	var fatal := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.RIGHT * 400.0, "hostile": false, "damage": 9999.0, "style": &"crease_petal", "echo_chance": 1.0})
	combat._resolve_friendly_collision(fatal)
	check(completed.size() == 1 and director.get_snapshot()["completed"], "real lethal collision synchronously opens exactly one task reward")
	check(is_equal_approx(damage_events.back(), frozen_health), "overkill reports remaining health instead of nominal projectile damage")
	check(defeat_events.size() == 1 and bool(defeat_events[0].get("is_objective_target", false)), "target death is explicitly classified for kill filtering")
	check(defeat_events[0].get("actor_id", &"") == actor.actor_id, "detailed death carries the stable real actor identity")
	check(not combat.enemies.has(actor), "a killed target is immediately removed from auto-aim even before queued deletion")
	var late := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.RIGHT, "hostile": false, "damage": 4.0, "style": &"crease_petal"})
	combat._resolve_friendly_collision(late)
	check(completed.size() == 1 and defeat_events.size() == 1 and not director.report_flag_damage(snapshot["target_id"], 1.0), "same-frame late projectile and late callback cannot duplicate a paused reward")
	await process_frame
	combat.set_active(true)
	var expired := Target.new()
	expired.configure({"target_id": &"expired_flag", "target_position": Vector2(1200, 600), "required": 10.0})
	combat.register_objective_target(expired)
	check(combat.unregister_objective_target(expired), "timeout unregisters its actual target through one cleanup path")
	check(not expired.visible and not combat.enemies.has(expired) and not expired.take_damage(10.0), "retired target is hidden and cannot receive a stale hit")
	check(defeat_events.size() == 1 and not combat.unregister_objective_target(expired), "retirement is idempotent and awards no kill or task event")
	var enemy := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1500, 600)}, false)
	if enemy == null:
		enemy = combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1500, 600)}, false)
	check(enemy != null, "normal enemy fixture is available")
	if enemy != null:
		var identity := StringName(enemy.get("actor_id"))
		enemy.call("take_damage", 9999.0)
		check(defeat_events.back().get("actor_id", &"") == identity and not bool(defeat_events.back().get("is_objective_target", false)), "normal enemy death preserves its unique identity without target classification")
	var leftover := Target.new()
	leftover.configure({"target_id": &"scene_flag", "target_position": Vector2(1500, 600), "required": 10.0})
	combat.register_objective_target(leftover)
	combat.clear_combat()
	await process_frame
	check(not is_instance_valid(leftover) and combat.enemies.is_empty(), "scene and run cleanup releases objective actors with the ordinary combat lifecycle")
	var damage_contract := Target.new()
	damage_contract.configure({"target_id": &"damage_contract", "required": 2.0})
	root.add_child(damage_contract)
	damage_contract.set_simulation_active(true)
	var nonlethal := damage_contract.take_damage(1.0)
	var lethal := damage_contract.take_damage(1.0)
	check(not nonlethal and lethal, "take_damage returns defeated status, matching the common enemy contract")
	damage_contract.queue_free()
	director.queue_free()
	world.queue_free()
	player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_OBJECTIVE_TARGET: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		failures.append(label)
