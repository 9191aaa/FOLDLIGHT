extends SceneTree

var _failures: Array[String] = []
var _waves: Array[Dictionary] = []
var _completed_kinds: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/endless/endless_survival_controller.tscn") as PackedScene
	var controller := packed.instantiate() as FoldlightEndlessSurvivalController if packed != null else null
	_check(controller != null, "endless controller scene loads")
	if controller == null:
		_finish()
		return
	root.add_child(controller)
	await process_frame
	controller.enemy_wave_requested.connect(func(request: Dictionary) -> void: _waves.append(request))
	controller.objective_completed.connect(func(snapshot: Dictionary) -> void: _completed_kinds.append(StringName(snapshot.get("kind", &""))))

	_check(controller.config.validation_errors().is_empty(), "endless config validates")
	_check(controller.map_definition.validation_errors().is_empty(), "handcrafted map validates")
	var map_contract := controller.map_runtime.get_map_contract()
	_check(StringName(map_contract.get("authored_version", &"")) == &"handcrafted_1_0", "map declares a handcrafted layout contract")
	_check(not bool(map_contract.get("runtime_random_terrain", true)), "map terrain is never generated at runtime")
	_check((map_contract.get("bounds", Rect2()) as Rect2).size == Vector2(6144.0, 4096.0), "map is a 6144 by 4096 survival battlefield")
	_check(int(map_contract.get("district_count", 0)) >= 6, "map has six readable districts")
	_check(int(map_contract.get("wall_count", 0)) >= 28, "map has dense authored cover")
	_check(int(map_contract.get("capture_site_count", 0)) >= 3, "map has authored capture sites")
	_check(int(map_contract.get("flag_site_count", 0)) >= 4, "map has authored flag sites")
	_check(int(map_contract.get("captain_site_count", 0)) >= 6, "map has authored captain sites")

	var route_from := Vector2(300.0, 1080.0)
	var route_to := Vector2(1320.0, 1080.0)
	_check(not controller.map_runtime.has_line_of_sight(route_from, route_to, 16.0), "cover blocks the direct return-light line")
	var route := controller.map_runtime.find_cover_route(route_from, route_to, 24.0)
	_check(route.size() >= 2 and route[route.size() - 1].is_equal_approx(route_to), "cover routing supplies a wall-bypassing return path")
	var route_cursor := route_from
	var route_segments_clear := not route.is_empty()
	for waypoint in route:
		if not controller.map_runtime.has_line_of_sight(route_cursor, waypoint, 2.0):
			route_segments_clear = false
		route_cursor = waypoint
	_check(route_segments_clear, "every authored return-route segment stays clear of cover")

	var start_snapshot := controller.start_run(3)
	_check(not start_snapshot.has("errors") and controller.active, "endless run starts through the public API")
	_check(StringName(controller.objectives.get_snapshot().get("kind", &"")) == &"capture_point", "objective cycle starts on capture for deterministic seed 3")

	controller.advance_simulation(46.0, controller.map_definition.player_spawn)
	var after_time := controller.evolution.get_snapshot()
	_check(int((after_time.enemy as Dictionary).get("stage", 0)) == 1, "survival time evolves enemies")
	_check(int((after_time.player as Dictionary).get("stage", 0)) == 0 and int((after_time.player as Dictionary).get("absorbed_total", -1)) == 0, "time evolution does not leak into player absorption")
	var survival_before_absorb := float((after_time.enemy as Dictionary).get("survival_seconds", 0.0))
	controller.report_projectiles_absorbed(24)
	var after_absorb := controller.evolution.get_snapshot()
	_check(int((after_absorb.player as Dictionary).get("stage", 0)) == 1, "real absorbed projectile count evolves the player")
	_check(int((after_absorb.enemy as Dictionary).get("stage", 0)) == 1 and is_equal_approx(float((after_absorb.enemy as Dictionary).get("survival_seconds", 0.0)), survival_before_absorb), "absorption evolution does not leak into the survival-time axis")

	var wave := controller.force_next_wave()
	var entries: Array = wave.get("entries", [])
	_check(not entries.is_empty(), "pressure director requests a populated enemy wave")
	var all_classic := true
	var shooter_uses_authored_center := false
	for entry_variant: Variant in entries:
		var entry := entry_variant as Dictionary
		var enemy_id := StringName(entry.get("enemy_id", &""))
		if enemy_id not in controller.config.classic_enemy_ids:
			all_classic = false
		if StringName(entry.get("spawn_role", &"")) == &"shooter":
			shooter_uses_authored_center = Vector2(entry.get("position", Vector2.ZERO)) in controller.map_definition.shooter_spawn_positions
	_check(all_classic, "waves reuse the complete 2.0 enemy identifiers instead of copying enemy logic")
	_check(shooter_uses_authored_center, "shooters use authored central cover positions")

	# Capture objective.
	var objective := controller.objectives.get_snapshot()
	var capture_position := Vector2(objective.get("target_position", Vector2.ZERO))
	controller.advance_simulation(controller.config.capture_hold_seconds + 0.1, capture_position)
	_check(_completed_kinds.has(&"capture_point"), "capture-point objective completes by holding its authored site")
	_check(controller.get_pending_mission_rewards().size() == 3, "capture objective offers three mission evolutions")
	var first_reward := controller.get_pending_mission_rewards()[0]
	_check(not controller.claim_mission_reward(StringName(first_reward.get("id", &""))).is_empty(), "mission evolution can be claimed through the public API")

	# Captain objective.
	controller.advance_simulation(controller.config.objective_intermission + 0.1, Vector2.ZERO)
	objective = controller.objectives.get_snapshot()
	_check(StringName(objective.get("kind", &"")) == &"defeat_captain", "task rotation advances to enemy captain")
	var captain_wave := controller.force_next_wave()
	var captain_found := false
	var captain_candidates: Array[Dictionary] = _waves.duplicate(true)
	captain_candidates.append(captain_wave)
	for request in captain_candidates:
		for entry_variant: Variant in request.get("entries", []):
			var entry := entry_variant as Dictionary
			if bool(entry.get("is_captain", false)) and StringName(entry.get("captain_id", &"")) == StringName(objective.get("target_id", &"")):
				captain_found = true
	_check(captain_found, "captain task injects a marked captain into the next wave")
	_check(controller.report_captain_defeated(StringName(objective.get("target_id", &""))), "captain defeat completes the second task")
	_check(_completed_kinds.has(&"defeat_captain"), "captain objective emits completion")
	var captain_options := controller.get_pending_mission_rewards()
	controller.claim_mission_reward(StringName(captain_options[0].get("id", &"")))

	# Flag objective.
	controller.advance_simulation(controller.config.objective_intermission + 0.1, Vector2.ZERO)
	objective = controller.objectives.get_snapshot()
	_check(StringName(objective.get("kind", &"")) == &"destroy_flag", "task rotation advances to flag demolition")
	_check(controller.report_flag_destroyed(StringName(objective.get("target_id", &""))), "flag destruction completes the third task")
	_check(_completed_kinds.has(&"destroy_flag"), "flag objective emits completion")
	_check(controller.get_pending_mission_rewards().size() == 3, "flag objective also offers mission evolution")
	_check(int(controller.evolution.get_mission_snapshot().get("reward_levels", {}).size()) >= 1, "mission rewards are tracked on a third, explicit progression ledger")

	var integration := controller.get_integration_contract()
	_check(not bool(integration.get("copies_classic_enemy_logic", true)), "integration contract delegates combat behavior to existing 2.0 actors")
	_check(not bool(integration.get("terrain_runtime_randomized", true)), "integration contract keeps the handcrafted map fixed")
	var stopped := controller.exit_mode(&"test_return_to_title")
	_check(not controller.active and not controller.visible and StringName(stopped.get("stop_reason", &"")) == &"test_return_to_title", "exit_mode stops ticking and hides the endless world for a safe title return")

	controller.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ENDLESS_SURVIVAL_FOUNDATION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_SURVIVAL_FOUNDATION: FAIL - %s" % ", ".join(_failures))
		quit(1)
