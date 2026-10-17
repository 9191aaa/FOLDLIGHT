extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.world.process_mode = Node.PROCESS_MODE_DISABLED
	slice.player.set_physics_process(false)
	var map_ids: Array[StringName] = []
	for seed in [0, 1, 2]:
		slice.start_slice(seed)
		map_ids.append(slice.controller.map_definition.map_id)
		check(slice.world.room_runtime.room_bounds.size == slice.controller.map_definition.bounds.size, "seed %d uses the chosen map's real combat bounds" % seed)
		check(slice.world.room_runtime.get_terrain_pieces().size() == slice.controller.map_definition.walls.size(), "seed %d builds the chosen map's physical walls" % seed)
	check(map_ids[0] != map_ids[1] and map_ids[1] != map_ids[2] and map_ids[0] != map_ids[2], "three seeds reach three distinct playable maps")
	var target := slice._objective_target
	check(is_instance_valid(target), "destroy flag task creates a real shared-combat target")
	if is_instance_valid(target):
		var before := float(slice.controller.objectives.get_snapshot().progress)
		slice.player.global_position = target.global_position + Vector2(100, 0)
		slice.controller.advance_simulation(2.0, slice.player.global_position)
		check(is_equal_approx(float(slice.controller.objectives.get_snapshot().progress), before), "proximity without a weapon hit cannot damage a flag")
		var health_before := float(target.health)
		var shot := slice.combat_runtime._spawn_projectile({"origin": target.global_position, "velocity": Vector2.RIGHT, "hostile": false, "damage": 3.0, "style": &"crease_petal"})
		slice.combat_runtime._resolve_friendly_collision(shot)
		check(float(target.health) < health_before and float(slice.controller.objectives.get_snapshot().progress) > before, "real friendly projectile hit advances flag health and task progress together")
		var kills_before := slice.controller.defeated_total
		slice.controller.objectives.advance(100.0, Vector2.ZERO)
		check(not slice.combat_runtime.enemies.has(target), "failed flag is unregistered from shared targeting")
		check(slice.controller.defeated_total == kills_before, "retiring a failed task target does not award a kill")

	slice.start_slice(1)
	slice._clear_pending_spawns()
	slice.combat_runtime.clear_combat()
	slice.controller._captain_spawned_for_objective = &""
	var population_limit := int(slice.controller.evolution.get_enemy_snapshot().population_limit)
	var crowd: Array[Dictionary] = []
	for index in population_limit:
		crowd.append({"enemy_id": &"drifter", "spawn_position": slice.controller.map_definition.player_spawn + Vector2(index * 3, -400)})
	slice.combat_runtime.spawn_directed_wave(crowd)
	slice._report_population()
	slice.controller.force_next_wave()
	check(slice.controller._captain_spawned_for_objective.is_empty(), "full enemy capacity cannot falsely acknowledge a task captain")
	# Opening population 28 and threat 32 leave only five threat after removing
	# one drifter. A real captain costs six, so release two ordinary slots.
	for index in 2:
		var removed: Node2D = slice.combat_runtime.enemies.pop_back()
		removed.queue_free()
	slice._report_population()
	slice.controller.force_next_wave()
	check(slice.controller._captain_spawned_for_objective.is_empty() and slice._pending_spawns.size() == 1 and bool(slice._pending_spawns[0].get("is_captain", false)), "opening both population and six threat queues the captain warning without acknowledging an actor early")
	_flush_arrivals(slice)
	check(slice.controller._captain_spawned_for_objective == StringName(slice.controller.objectives.get_snapshot().target_id), "captain retries and is acknowledged once a real actor slot opens")
	var captain_count := 0
	for enemy in slice.combat_runtime.enemies:
		if bool(enemy.get_meta("directed_spawn_entry", {}).get("is_captain", false)):
			captain_count += 1
	slice._report_population()
	slice.controller.force_next_wave()
	_flush_arrivals(slice)
	check(captain_count == 1 and slice.combat_runtime.enemies.size() == population_limit - 1, "acknowledged captain is not duplicated after its full threat budget leaves one actor slot unused")

	slice.start_slice(0)
	slice._clear_pending_spawns()
	slice.controller.objectives.rotation_index = 4
	slice.controller.objectives._start_current_objective()
	var storm := slice.controller.objectives.get_snapshot()
	slice.player.global_position = storm.target_position
	var enemies_before := slice.combat_runtime.enemies.size()
	slice._ensure_storm_support(1.0)
	_flush_arrivals(slice)
	check(slice.combat_runtime.enemies.size() > enemies_before and slice._storm_support_count <= 2, "near-field capture task supplies real limited shooter support on approach")
	var support_count := slice.combat_runtime.enemies.size()
	slice._ensure_storm_support(1.0)
	check(slice.combat_runtime.enemies.size() == support_count and float(slice.controller.objectives.get_snapshot().progress) == 0.0, "support cannot repeat without limit or fabricate capture progress")
	for enemy in slice.combat_runtime.enemies.duplicate():
		if enemy.get_meta("directed_spawn_entry", {}).get("objective_support", &"") == storm.id:
			slice.combat_runtime.enemies.erase(enemy)
			enemy.queue_free()
	slice._ensure_storm_support(4.0)
	_flush_arrivals(slice)
	check(slice._storm_support_count == 2 and slice.combat_runtime.enemies.size() == support_count, "defeated support is replenished after cooldown without exceeding two live shooters")

	slice.start_slice(0)
	slice.controller.advance_simulation(72.0, slice.player.global_position)
	var zone_snapshot := slice.controller.zones.get_snapshot()
	var closed_point := Vector2.ZERO
	for zone: Dictionary in zone_snapshot.zones:
		if zone.state == &"closed":
			# New central closure rectangles contain the permanent narrow lane;
			# sample the actually painted hazard, never the exempt lane at center.
			var fragments := FoldlightEndlessMapDefinition.zone_fragments(zone.rect, zone_snapshot.safe_corridors)
			closed_point = fragments[0].get_center()
			break
	check(slice.controller.zones.is_point_closed(closed_point), "live closure has a visible hazardous area")
	slice.player.global_position = closed_point
	slice.player.invulnerability = 0.0
	var health := slice.player.health
	slice._update_zone_exposure(1.9)
	check(slice.player.health == health, "closed area honors evacuation grace in the real player adapter")
	slice._update_zone_exposure(0.1)
	check(slice.player.health == health - 1, "closed area takes one health through the shared hit pipeline")
	var clock := slice.controller.evolution.survival_seconds
	var exposure := slice._zone_exposure.exposure_seconds
	slice._pause_game()
	slice._physics_process(5.0)
	check(slice.controller.evolution.survival_seconds == clock and slice._zone_exposure.exposure_seconds == exposure, "pause freezes closure clock and damage grace together")
	check(not slice._navigation.is_visible_in_tree(), "navigation obeys the shared pause modal")
	slice._resume_game()
	slice._refresh_hud()
	check(slice._navigation.is_visible_in_tree(), "navigation returns with the shared combat HUD")
	var clock_before_map := slice.controller.evolution.survival_seconds
	slice._navigation.call("_toggle_map")
	check(slice._modal_kind.is_empty() and slice.combat_runtime.active, "expanded map keeps live combat active")
	slice._physics_process(0.1)
	check(slice.controller.evolution.survival_seconds > clock_before_map, "expanded map does not pause the effective survival clock")
	slice.start_slice(0)
	slice.controller._spawn_clock = 0.0
	var wave_before_reward := slice.controller.wave_sequence
	var capture_point := Vector2(slice.controller.objectives.get_snapshot().target_position)
	slice.controller.advance_simulation(12.0, capture_point)
	check(slice._modal_kind == &"objective_complete" and slice.controller.wave_sequence == wave_before_reward and not slice.combat_runtime.active, "task completion freezes the battlefield before any due wave can spawn")
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	check(slice._modal_kind == &"reward" and slice.controller.wave_sequence == wave_before_reward, "facility completion unfolds before reward without spawning the pending wave")
	slice.queue_free()
	await process_frame
	print("FOLDLIGHT_ENDLESS_NAVIGATION_INTEGRATION: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _flush_arrivals(slice: FoldlightEndlessSliceRuntime) -> void:
	for warning_step in 12:
		slice._advance_spawn_queue(0.1)


func check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
