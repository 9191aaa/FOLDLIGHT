extends SceneTree

var _failures: Array[String] = []
var _notifications: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller := (load("res://scenes/endless/endless_survival_controller.tscn") as PackedScene).instantiate() as FoldlightEndlessSurvivalController
	root.add_child(controller)
	await process_frame
	controller.reward_available.connect(func(snapshot: Dictionary) -> void: _notifications.append(snapshot))
	_test_credit_and_independent_axes(controller)
	_test_simultaneous_task_and_level(controller)
	_test_recovery_and_token_lifecycle(controller)
	_test_population_and_spawn_safety(controller)
	controller.queue_free()
	await process_frame
	await _test_real_shared_kills()
	if _failures.is_empty():
		print("FOLDLIGHT_ENDLESS_GROWTH_3_16: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_GROWTH_3_16: FAIL - %s" % ", ".join(_failures))
		quit(1)


func _test_credit_and_independent_axes(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	var enemy_before := controller.evolution.get_enemy_snapshot()
	var absorb_before := controller.evolution.get_player_snapshot()
	var missions_before := controller.evolution.get_mission_snapshot()
	_report(controller, 1, &"drifter")
	_report(controller, 2, &"ram")
	_report(controller, 3, &"shutter_seraph")
	_check(int(controller.get_snapshot().experience.total_xp) == 13, "ordinary, heavy and elite kills grant exactly 2 / 3 / 8 experience")
	_report(controller, 3, &"shutter_seraph")
	_report(controller, 2, &"drifter")
	_check(controller.defeated_total == 3 and int(controller.get_snapshot().experience.total_xp) == 13, "duplicate and out-of-order defeat callbacks cannot farm kills or experience")
	controller.report_enemy_defeated({"enemy_id": &"cinder_mine", "defeat_serial": 4, "defeat_reason": &"self_detonation", "grants_kill_credit": false})
	controller.report_enemy_defeated({"enemy_id": &"drifter", "defeat_serial": 5, "defeat_reason": &"retired"})
	controller.report_enemy_defeated({"enemy_id": &"flag", "defeat_serial": 6, "defeat_reason": &"player", "is_objective_target": true})
	_check(controller.defeated_total == 3 and int(controller.get_snapshot().experience.total_xp) == 13, "self detonation, retirement and task props grant neither kills nor XP")
	controller.report_enemy_defeated({"enemy_id": &"drifter", "actor_id": &"legacy"})
	_check(controller.defeated_total == 4 and int(controller.get_snapshot().experience.total_xp) == 13, "legacy unnumbered reports retain task compatibility without granting XP")
	_check(controller.evolution.get_enemy_snapshot() == enemy_before and controller.evolution.get_player_snapshot() == absorb_before and controller.evolution.get_mission_snapshot() == missions_before, "kill experience leaves time pressure, absorption and mission-growth ledgers independent")
	controller.report_projectiles_absorbed(60)
	_check(int(controller.get_snapshot().experience.total_xp) == 13, "absorbing bullets does not award kill experience")
	_check(controller.evolution.experience_required(1) == 42 and controller.evolution.experience_required(2) == 60 and controller.evolution.experience_required(4) == 108, "experience thresholds rise gradually rather than resetting to a flat kill quota")


func _test_simultaneous_task_and_level(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(4)
	_notifications.clear()
	for index in 17:
		_report(controller, index + 1, &"drifter")
	var objective := controller.objectives.get_snapshot()
	_check(StringName(objective.kind) == &"defeat_captain", "fixture uses an actual live captain objective")
	controller.report_enemy_defeated({
		"enemy_id": &"bloomer", "is_captain": true, "captain_id": objective.target_id,
		"defeat_serial": 18, "defeat_reason": &"player",
	})
	var first := controller.peek_pending_reward()
	_check(int(controller.get_snapshot().pending_reward_count) == 2 and int(controller.get_snapshot().experience.level) == 2, "one captain kill queues both the completed task and the earned level")
	_check(StringName(first.source) == &"mission" and int(first.heal_on_claim) == 1 and _notifications.size() == 1, "task reward is presented first with recovery and only one head notification")
	_check((first.options as Array).size() == 3 and StringName(first.options[0].choice_kind) == &"weapon", "the task keeps its existing weapon supply even when the same kill earns a level")
	var task_token := StringName(first.reward_token)
	var task_id := StringName(first.options[0].id)
	var task_result := controller.claim_pending_reward(task_token, task_id)
	var second := controller.peek_pending_reward()
	_check(not task_result.is_empty() and StringName(second.source) == &"kill_level" and int(second.level) == 2, "claiming the task advances to the level reward instead of dropping it")
	_check(controller.claim_pending_reward(task_token, StringName(second.options[0].id)).is_empty(), "a stale task token cannot consume the next level reward even with a legal card ID")
	var level_result := controller.claim_pending_reward(StringName(second.reward_token), StringName(second.options[0].id))
	_check(int(level_result.heal_on_claim) == 0 and controller.peek_pending_reward().is_empty(), "level two grants one upgrade and no interval recovery")
	_check((controller.evolution.get_mission_snapshot().reward_levels as Dictionary).is_empty() and not (controller.evolution.get_experience_snapshot().reward_levels as Dictionary).is_empty(), "experience upgrades have their own modifier ledger without spending the task sequence")
	_check(_notifications.size() == 2 and int(controller.get_snapshot().experience.pending_levels) == 0, "each queued reward is announced once and all level entitlements are consumed")
	controller._on_objective_completed(objective.merged({"completion_count": 1}, true))
	_check(controller.peek_pending_reward().is_empty(), "replaying the same task completion cannot reopen rewards or recovery")


func _test_recovery_and_token_lifecycle(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	for index in 51:
		_report(controller, index + 1, &"drifter")
	var level_two := controller.peek_pending_reward()
	controller.claim_pending_reward(StringName(level_two.reward_token), StringName(level_two.options[0].id))
	var level_three := controller.peek_pending_reward()
	_check(int(level_three.level) == 3 and int(level_three.heal_on_claim) == 1, "every third reached level advertises exactly one recovery point")
	var stale_token := StringName(level_three.reward_token)
	var stale_choice := StringName(level_three.options[0].id)
	var claimed := controller.claim_pending_reward(stale_token, stale_choice)
	_check(int(claimed.heal_on_claim) == 1 and controller.claim_pending_reward(stale_token, stale_choice).is_empty(), "recovery is included exactly once in the claimed reward")
	controller._on_objective_completed({"completion_count": 1, "title": "旧航行"})
	var old_run_token := StringName(controller.peek_pending_reward().reward_token)
	controller.start_run(3)
	controller._on_objective_completed({"completion_count": 1, "title": "新航行"})
	var fresh := controller.peek_pending_reward()
	_check(old_run_token != StringName(fresh.reward_token) and controller.claim_pending_reward(old_run_token, StringName(fresh.options[0].id)).is_empty(), "restarting the same seed invalidates delayed reward callbacks from the old run")
	_check(int(controller.get_snapshot().experience.level) == 1 and int(controller.get_snapshot().experience.total_xp) == 0, "restart resets all kill experience and level rewards")
	controller.stop_run()
	_check(controller.peek_pending_reward().is_empty(), "leaving the mode discards every pending reward")


func _test_population_and_spawn_safety(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	for wave in 30:
		controller.force_next_wave()
	var population := controller.get_population_snapshot()
	_check(int(population.pending_count) <= 24 and int(population.pending_threat) <= 32, "uninstantiated waves reserve both population and threat instead of accumulating beyond the cap")
	controller.report_population({"alive_count": 23, "pending_count": 1, "threat_total": 24})
	_check((controller.force_next_wave().entries as Array).is_empty(), "alive plus pending actors obey the hard population cap")
	controller.report_population({"alive_count": 4, "threat_total": 26, "pending_threat": 6})
	_check((controller.force_next_wave().entries as Array).is_empty(), "pending threat counts even when the actor cap has free space")
	controller.report_population({})
	var safe := true
	for map_seed in range(3):
		controller.select_map_for_seed(map_seed)
		controller.start_run(3)
		for position: Vector2 in controller.map_definition.shooter_spawn_positions:
			controller.report_population({})
			controller._last_player_position = position
			var wave := controller.force_next_wave()
			for entry: Dictionary in wave.entries:
				if Vector2(entry.position).distance_to(position) < 620.0 or controller.map_runtime.is_point_blocked(Vector2(entry.position), 40.0):
					safe = false
	_check(safe, "all three maps keep regular spawn points outside the player safety circle and authored cover")
	controller.start_run(3)
	controller.evolution.advance_survival(600.0)
	controller.report_population({})
	controller.wave_sequence = 0
	var full_wave := controller.force_next_wave()
	controller.report_population({})
	var breathing := controller.force_next_wave()
	_check(not bool(full_wave.breathing_wave) and bool(breathing.breathing_wave) and _wave_threat(breathing) <= _wave_threat(full_wave) * 0.75 + 1, "the pressure rhythm alternates a full wave with a smaller breathing wave")
	_check(int(controller.get_population_snapshot().population_limit) == 42 and int(controller.get_population_snapshot().threat_limit) == 86, "late time pressure uses bounded population and threat limits before XP adds further pressure")
	controller.start_run(3)
	controller.advance_simulation(100.0, controller.map_definition.player_spawn)
	var sequence := controller.wave_sequence
	controller.advance_simulation(0.01, controller.map_definition.player_spawn)
	_check(controller.wave_sequence == sequence, "a long frame cannot create a rapid backlog of overdue spawn waves")


func _test_real_shared_kills() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.start_slice(3)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	var initial_xp := int(slice.controller.evolution.get_experience_snapshot().total_xp)
	var ids: Array[StringName] = [&"drifter", &"paper_drifter", &"ram", &"cinder_mine"]
	var totals: Array[int] = [2, 4, 7, 10]
	for index in ids.size():
		var entries: Array[Dictionary] = [{"enemy_id": ids[index], "spawn_position": slice.player.global_position + Vector2(700.0, 0.0)}]
		var actors := slice.combat_runtime.spawn_directed_wave(entries)
		_check(actors.size() == 1, "shared factory creates real %s for kill-credit integration" % ids[index])
		if actors.is_empty():
			continue
		actors[0].call("take_damage", 999.0)
		_check(int(slice.controller.evolution.get_experience_snapshot().total_xp) - initial_xp == totals[index], "real %s defeat signal awards natural-kill experience through runtime" % ids[index])
		await process_frame
	var retired_entries: Array[Dictionary] = [{"enemy_id": &"drifter", "spawn_position": slice.player.global_position + Vector2(900.0, 0.0)}]
	var retired := slice.combat_runtime.spawn_directed_wave(retired_entries)
	var before_retirement := int(slice.controller.evolution.get_experience_snapshot().total_xp)
	if not retired.is_empty():
		slice.combat_runtime.retire_directed_enemy(retired[0])
	_check(int(slice.controller.evolution.get_experience_snapshot().total_xp) == before_retirement, "shared population retirement removes actors without issuing kill XP")
	var bomber_entries: Array[Dictionary] = [{"enemy_id": &"cinder_mine", "spawn_position": slice.player.global_position + Vector2(700.0, 0.0)}]
	var bombers := slice.combat_runtime.spawn_directed_wave(bomber_entries)
	var kills_before := slice.controller.defeated_total
	if not bombers.is_empty():
		var bomber: Node2D = bombers[0]
		for step in 40:
			if float(bomber.get("health")) <= 0.0:
				break
			bomber.call("advance_simulation", 0.1, bomber.global_position)
	_check(slice.controller.defeated_total == kills_before and int(slice.controller.evolution.get_experience_snapshot().total_xp) == before_retirement, "a real bomber's fuse expiration grants neither kill count nor XP")
	slice.queue_free()
	await process_frame


func _report(controller: FoldlightEndlessSurvivalController, serial: int, enemy_id: StringName) -> void:
	controller.report_enemy_defeated({"enemy_id": enemy_id, "actor_id": StringName("enemy-%d" % serial), "defeat_serial": serial, "defeat_reason": &"player"})


func _wave_threat(wave: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in wave.entries:
		total += int(entry.threat_cost)
	return total


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
