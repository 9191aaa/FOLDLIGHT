extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var controller := (load("res://scenes/endless/endless_survival_controller.tscn") as PackedScene).instantiate() as FoldlightEndlessSurvivalController
	root.add_child(controller)
	await process_frame
	_test_experience(controller)
	_test_density(controller)
	_test_task_difficulty(controller)
	_test_escort(controller)
	_test_boss_rewards(controller)
	controller.queue_free()
	await process_frame
	await _test_runtime_escort()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_BALANCE_3_17: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_experience(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	var evolution := controller.evolution
	_check(evolution.experience_required(1) == 42 and evolution.experience_required(2) == 60 and evolution.experience_required(7) == 210, "kill XP starts at 42 and grows with linear plus quadratic cost")
	var to_eight := 0
	for level in range(1, 8):
		to_eight += evolution.experience_required(level)
	_check(to_eight == 812, "Lv8 needs 812 XP rather than the former 304 XP")
	_check(evolution.record_kill_experience(18).is_empty() and evolution.experience_level == 1, "the former nine ordinary kill quota no longer opens the first card")
	evolution.record_kill_experience(to_eight - 19)
	_check(evolution.experience_level == 7, "one XP short of the Lv8 threshold cannot trigger the boss tier")
	evolution.record_kill_experience(1)
	_check(evolution.experience_level == 8 and evolution.get_enemy_snapshot().stage == 3 and evolution.get_enemy_snapshot().time_stage == 0, "XP pressure advances while the combat-time ledger remains independent")
	evolution.advance_survival(600.0)
	_check(evolution.get_enemy_snapshot().stage >= 6 and evolution.get_enemy_snapshot().objective_tier >= 5, "late time and combat level jointly increase task difficulty")
	var estimated_fast := float(to_eight) / (2.8 * 1.2)
	var estimated_slow := float(to_eight) / (2.8 * 0.6)
	_check(estimated_fast > 240.0 and estimated_slow < 490.0, "explicit 0.6-1.2 kill/s model places Lv8 around four to eight minutes; this is a model, not a playtest")


func _test_density(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	var early := controller.evolution.get_enemy_snapshot()
	_check(early.population_limit == 24 and early.threat_limit == 32 and is_equal_approx(early.spawn_interval, 4.4), "opening reinforcement is denser with 24 actors, 32 threat and 4.4-second cadence")
	var requested := 0
	for wave in 5:
		controller.report_population({})
		requested += (controller.force_next_wave().entries as Array).size()
	_check(requested >= 18, "five uncongested opening waves request at least eighteen nearby enemies")
	controller.evolution.record_kill_experience(100000)
	var late := controller.evolution.get_enemy_snapshot()
	_check(late.population_limit == 48 and late.threat_limit == 104 and late.spawn_interval >= 1.9, "late reinforcement has bounded actor, threat and minimum interval budgets")
	controller.report_population({})
	for wave in 40:
		controller.force_next_wave()
	var population := controller.get_population_snapshot()
	_check(population.pending_count <= 48 and population.pending_threat <= 104, "uncreated reinforcements reserve both limits without an unlimited queue")
	controller.report_population({"alive_count": 46, "pending_count": 2})
	_check((controller.force_next_wave().entries as Array).is_empty(), "48 live plus warned actors block further waves")
	controller.report_population({"threat_total": 98, "pending_threat": 6})
	_check((controller.force_next_wave().entries as Array).is_empty(), "pending boss or captain threat participates in the full threat budget")
	var legal := true
	var present := true
	for map_index in 3:
		controller.select_map_for_seed(map_index)
		controller.start_run(3)
		for point in controller.map_definition.rally_positions:
			controller._last_player_position = point
			controller.report_population({})
			var wave := controller.force_next_wave()
			present = present and not (wave.entries as Array).is_empty()
			for entry: Dictionary in wave.entries:
				var position := Vector2(entry.position)
				var distance := point.distance_to(position)
				legal = legal and distance >= controller.config.spawn_safe_distance and distance <= controller.config.spawn_local_radius and not controller.map_runtime.is_point_blocked(position, 40.0) and not controller.zones.is_point_reserved(position, 40.0)
	_check(legal and present, "all three maps reinforce within the local 620-1250 ring while respecting terrain and closures")


func _test_task_difficulty(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	var director := controller.objectives
	var expected := {&"capture_point": 24.0, &"destroy_flag": 298.0, &"relay_route": 5.0, &"capture_storm": 36.0, &"clear_swarm": 34.0}
	for index in 6:
		_force_kind(director, index, {"objective_tier": 6, "stage": 7})
		var snapshot := director.get_snapshot()
		if expected.has(snapshot.kind):
			_check(is_equal_approx(float(snapshot.required), expected[snapshot.kind]), "tier six scales %s to its reachable required amount" % snapshot.kind)
		_check(snapshot.time_limit >= 120.0 and snapshot.time_limit <= 180.0, "tier six %s keeps an extended bounded deadline" % snapshot.kind)
		var required := float(snapshot.required)
		var deadline := float(snapshot.time_limit)
		var captain_health := float(snapshot.captain_health_multiplier)
		director.set_progression_context({"objective_tier": 8, "stage": 10}, Vector2.ZERO)
		director.advance(0.1, Vector2.ZERO)
		var after := director.get_snapshot()
		_check(float(after.required) == required and float(after.time_limit) == deadline and float(after.captain_health_multiplier) == captain_health, "leveling during %s never moves its existing goalposts" % snapshot.kind)
	controller.start_run(3)
	var bag: Dictionary = {}
	var sequence: Array[StringName] = []
	var previous := &""
	var adjacent_repeat := false
	for task in 28:
		var snapshot := director.get_snapshot()
		var kind := StringName(snapshot.kind)
		sequence.append(kind)
		if task >= 7:
			bag[kind] = true
			adjacent_repeat = adjacent_repeat or kind == previous
		if task >= 7 and task % 7 == 6:
			_check(bag.size() == 7, "each shuffled task bag contains all seven interactions")
			bag.clear()
		previous = kind
		director._complete_current()
		director.advance(controller.config.objective_intermission + 0.1, controller.map_definition.player_spawn)
	_check(not adjacent_repeat, "shuffled task bags avoid repeating the just-finished kind")
	controller.start_run(3)
	var same := true
	for task in sequence.size():
		same = same and StringName(director.get_snapshot().kind) == sequence[task]
		director._complete_current()
		director.advance(controller.config.objective_intermission + 0.1, controller.map_definition.player_spawn)
	_check(same, "same seed and progression replay the entire shuffled schedule")


func _test_escort(controller: FoldlightEndlessSurvivalController) -> void:
	for map_index in 3:
		controller.select_map_for_seed(map_index)
		controller.start_run(3)
		var reachable := true
		for sites in [controller.map_definition.capture_points, controller.map_definition.flag_positions, controller.map_definition.captain_spawn_positions, controller.map_definition.rally_positions]:
			for point: Vector2 in sites:
				var route := controller.map_runtime.find_cover_route(controller.map_definition.player_spawn, point, 24.0)
				reachable = reachable and not route.is_empty() and route[route.size() - 1].is_equal_approx(point)
		_check(reachable, "every old and expanded task site on map %d is reachable from the starting refuge" % map_index)
		var all_seeds_have_route := true
		for seed in 24:
			controller.start_run(seed)
			_force_kind(controller.objectives, 6, {"objective_tier": 3, "stage": 3})
			all_seeds_have_route = all_seeds_have_route and controller.objectives.get_snapshot().kind == &"escort"
		_check(all_seeds_have_route, "all 24 opening route seeds on map %d can provide a legal escort" % map_index)
		controller.start_run(3)
		var director := controller.objectives
		_force_kind(director, 6, {"objective_tier": 3, "stage": 3})
		var initial := director.get_snapshot()
		_check(initial.kind == &"escort", "map %d provides a real navigable escort route" % map_index)
		if initial.kind != &"escort":
			continue
		var cursor := Vector2(initial.escort_position)
		var legal := true
		for point in initial.escort_route:
			legal = legal and controller.map_runtime.has_line_of_sight(cursor, point, 30.0)
			cursor = point
		_check(legal and initial.required >= 900.0 and initial.required <= 2701.0, "escort on map %d follows bounded cover-safe segments" % map_index)
		director.advance(1.0, Vector2(initial.escort_position) + Vector2(600, 0))
		_check(is_zero_approx(float(director.get_snapshot().progress)) and director.get_snapshot().escort_state == &"waiting_player", "leaving the boat pauses escort progress and requests the player's return")
		director.report_escort_pressure(1)
		director.advance(1.0, initial.escort_position)
		_check(is_equal_approx(float(director.get_snapshot().progress), 38.5) and director.get_snapshot().escort_state == &"contested", "nearby enemies slow the boat to 35 percent without hidden escort HP")
		director.report_escort_pressure(0)
		var previous := float(director.get_snapshot().progress)
		director.advance(1.0, director.get_snapshot().escort_position)
		_check(is_equal_approx(float(director.get_snapshot().progress) - previous, 110.0), "clearing nearby enemies restores the authored escort speed")
		for step in 500:
			var snapshot := director.get_snapshot()
			if snapshot.status != &"active":
				break
			director.advance(0.1, snapshot.escort_position)
		var completed := director.get_snapshot()
		_check(completed.completed and completed.escort_position.is_equal_approx(completed.escort_destination), "following the actual route reaches the real destination once")
		var reward := controller.peek_pending_reward()
		_check(reward.source == &"mission" and reward.options.size() == 3 and reward.heal_on_claim == 1, "completed escort retains the normal reinforcement and one recovery point")
		director._complete_current()
		_check(controller.get_snapshot().pending_reward_count == 1, "late escort completion cannot duplicate its reward")
	controller.start_run(3)
	controller.objectives.bind_route_provider(func(_from: Vector2, _to: Vector2, _clearance: float) -> PackedVector2Array: return PackedVector2Array())
	_force_kind(controller.objectives, 6, {})
	_check(controller.objectives.get_snapshot().kind == &"clear_swarm", "an unavailable navigation route never becomes a boat that travels through walls")


func _test_boss_rewards(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	controller.objectives._complete_current()
	var task_token := StringName(controller.peek_pending_reward().reward_token)
	_check(controller.queue_boss_reward(&"boss_wave_1", "深潮首领", 1), "a cleared boss wave adds an independent reward behind the current task")
	_check(not controller.queue_boss_reward(&"boss_wave_1", "重复", 1) and not controller.queue_boss_reward(&"", "空", 2), "duplicate or unidentified boss-wave reports cannot farm rewards")
	var task := controller.peek_pending_reward()
	controller.claim_pending_reward(task_token, StringName(task.options[0].id))
	var boss := controller.peek_pending_reward()
	_check(boss.source == &"boss" and boss.options.size() == 3 and boss.heal_on_claim == 1, "boss clears offer three reinforcements with one recovery point")
	_check(controller.objectives.completion_count == 1 and controller.evolution.experience_level == 1 and controller.evolution.experience_total == 0, "boss entitlement consumes neither the task sequence nor a kill level")
	_check(controller.claim_pending_reward(task_token, StringName(boss.options[0].id)).is_empty(), "a stale task token cannot claim the following boss reward")
	var result := controller.claim_pending_reward(StringName(boss.reward_token), StringName(boss.options[0].id))
	_check(result.reward_source == &"boss" and result.heal_on_claim == 1 and controller.peek_pending_reward().is_empty(), "the independent boss entitlement can be claimed exactly once")
	controller.queue_boss_reward(&"boss_wave_2", "双首领", 2)
	controller.stop_run()
	_check(controller.peek_pending_reward().is_empty(), "leaving a run cancels unclaimed boss rewards")
	controller.start_run(3)
	_check(controller.queue_boss_reward(&"boss_wave_1", "新航行", 1), "a new run resets the boss-wave entitlement ledger")


func _test_runtime_escort() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	slice.start_slice(3)
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice._clear_pending_spawns()
	slice.combat_runtime.clear_combat()
	slice.combat_runtime.set_active(true)
	_force_kind(slice.controller.objectives, 6, {})
	var objective := slice.controller.objectives.get_snapshot()
	_check(objective.kind == &"escort", "real runtime accepts the escort objective snapshot")
	if objective.kind == &"escort":
		slice.player.global_position = objective.escort_position
		var actor := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(objective.escort_position) + Vector2(100, 0)}, false)
		_check(is_instance_valid(actor), "escort pressure fixture contains a real shared enemy")
		if is_instance_valid(actor):
			slice._report_escort_pressure()
			slice.controller.advance_simulation(1.0, slice.player.global_position)
			_check(slice.controller.objectives.get_snapshot().escort_threat_count == 1 and is_equal_approx(float(slice.controller.objectives.get_snapshot().progress), 38.5), "runtime nearby-enemy scan slows the authoritative escort movement")
			actor.take_damage(9999.0)
			slice._report_escort_pressure()
			_check(slice.controller.objectives.get_snapshot().escort_threat_count == 0, "a defeated shared enemy no longer obstructs the boat before its node is freed")
		for step in 500:
			objective = slice.controller.objectives.get_snapshot()
			if objective.status != &"active":
				break
			slice.player.global_position = objective.escort_position
			slice.controller.advance_simulation(0.1, slice.player.global_position)
		_check(slice._modal_kind == &"objective_complete" and not slice.combat_runtime.active, "finishing escort enters the protected completion presentation and freezes combat")
		for frame in 6:
			slice._process(0.1)
		_check(slice.presentation.screen_kind == &"reward" and slice._modal_options.size() == 3, "escort completion reaches the actual three-choice reward UI")
		if not slice._modal_options.is_empty():
			slice.player.health = 1
			var choice := StringName(slice._modal_options[0].id)
			slice._on_reward_chosen(choice)
			_check(slice.player.health == 2 and slice.combat_runtime.active and slice.controller.peek_pending_reward().is_empty(), "claiming the real escort upgrade heals once and resumes the run")
	slice.queue_free()
	await process_frame


func _force_kind(director: FoldlightEndlessObjectiveDirector, index: int, difficulty: Dictionary) -> void:
	director.set_progression_context(difficulty, director.map_definition.player_spawn)
	director.rotation_index = index
	director._task_serial = 6 if index == 6 else 0
	director._start_current_objective()


func _check(ok: bool, message: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + message)
	if not ok:
		failures.append(message)
