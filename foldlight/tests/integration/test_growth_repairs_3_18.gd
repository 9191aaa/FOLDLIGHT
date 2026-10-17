extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	_test_fractional_flag_death(slice)
	_test_capacity(slice)
	_test_stacking_choices(slice)
	_test_movement_and_dash_snapshot(slice)
	_test_density_and_miasma(slice.controller)
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_GROWTH_REPAIRS_3_18: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_fractional_flag_death(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(2)
	var controller := slice.controller
	var flag := slice._objective_target
	_check(is_instance_valid(flag) and StringName(controller.objectives.get_snapshot().kind) == &"destroy_flag", "seed two creates a real shared fire flag")
	if not is_instance_valid(flag):
		return
	var target_id := StringName(flag.target_id)
	slice.player.global_position = flag.global_position + Vector2(1100.0, 0.0)
	slice.player.health = 3
	var completions: Array[Dictionary] = []
	var final_damage_progress: Array[float] = []
	var completion_listener := func(snapshot: Dictionary) -> void: completions.append(snapshot)
	controller.objective_completed.connect(completion_listener)
	flag.damage_reported.connect(func(_id: StringName, _amount: float) -> void:
		if flag.health <= 0.0:
			final_damage_progress.append(float(controller.objectives.get_snapshot().progress))
	)
	for hit in 47:
		flag.take_damage(1.3)
	_check(flag.health == 0.0 and final_damage_progress.size() == 1 and final_damage_progress[0] < 60.0, "real fractional damage reproduces zero HP with a task sum one epsilon below 60")
	_check(completions.size() == 1 and bool(controller.objectives.get_snapshot().completed), "physical flag death completes the task even when the final damage sum rounds down")
	var head := controller.peek_pending_reward()
	_check(not head.is_empty() and StringName(head.source) == &"mission" and head.options.size() == 3 and int(head.heal_on_claim) == 1, "far-away real flag damage retains the three-choice reward and one recovery entitlement")
	_check(controller.defeated_total == 0 and int(controller.evolution.get_experience_snapshot().total_xp) == 0, "destroying a flag does not farm normal kills or XP")
	_check(slice._modal_kind == &"objective_complete", "completion immediately enters its visible feedback phase")
	flag.destroyed.emit(target_id)
	_check(completions.size() == 1 and int(controller.get_snapshot().pending_reward_count) == 1, "duplicate physical death cannot grant a second task reward")
	if not head.is_empty():
		var token := StringName(head.reward_token)
		var choice := StringName(head.options[0].id)
		for step in 6:
			slice._advance_reward_completion(0.1)
		_check(slice._modal_kind == &"reward", "fractional flag death advances from feedback to the actual reward cards")
		slice._on_reward_chosen(choice)
		_check(controller.peek_pending_reward().is_empty() and slice.player.health == 4 and slice._modal_kind == &"", "choosing the flag reward applies reinforcement, heals once and resumes combat")
		_check(controller.claim_pending_reward(token, choice).is_empty() and slice.player.health == 4, "replaying the claimed token cannot heal again")
	controller.objective_completed.disconnect(completion_listener)
	slice.start_slice(2)
	_check(not controller.report_flag_destroyed(target_id) and controller.peek_pending_reward().is_empty(), "a previous run's flag ID cannot complete a new task")


func _test_capacity(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(3)
	var player := slice.player
	player.apply_roguelite_stats({"capture_capacity": 12})
	_check(player.get_capture_capacity() == 20, "the former ceiling is still an ordinary valid capacity")
	player.apply_roguelite_stats({"capture_capacity": 13})
	_check(player.get_capture_capacity() == 21, "the next real upgrade now grows capacity past twenty")
	player.apply_roguelite_stats({"capture_capacity": 1000})
	_check(player.get_capture_capacity() == FoldlightFoldComponent.MAX_CAPACITY and player.fold_component.get_capacity() == 96, "player and component agree on the explicit 96-slot upper bound")
	player.folding = true
	player.captured = 95
	_check(player.capture_one() and not player.capture_one() and is_equal_approx(player.get_capture_ratio(), 1.0), "the displayed capacity accepts exactly 96 real captures without overfill")
	player.cancel_fold()
	var evolution := slice.controller.evolution
	for index in 87:
		evolution.apply_mission_reward(&"wide_fold")
	var before := _find_option(evolution.get_mission_reward_options(0), &"wide_fold")
	_check(int(before.modifiers.capture_capacity) == 1 and String(before.description).contains("+1"), "the final available slot is advertised as one real capacity increase")
	evolution.apply_mission_reward(&"wide_fold")
	var capped := _find_option(evolution.get_mission_reward_options(0), &"wide_fold")
	_check(int(capped.modifiers.capture_capacity) == 0 and String(capped.description).contains("已满 96"), "a capped card no longer advertises an impossible capacity increase")
	var old_radius := float(evolution.mission_modifiers.fold_radius_multiplier)
	var applied := evolution.apply_mission_reward(&"wide_fold")
	slice._refresh_combined_modifiers()
	_check(not applied.is_empty() and float(evolution.mission_modifiers.fold_radius_multiplier) > old_radius and player.get_capture_capacity() == 96, "the capped card still grants its displayed useful radius effect")
	_check(int(slice.get_effective_combat_stats().capture_capacity) == player.get_capture_capacity(), "the runtime UI snapshot reports actual component capacity")


func _test_stacking_choices(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(3)
	var evolution := slice.controller.evolution
	var options := evolution.get_mission_reward_options(2)
	_check(not _find_option(options, &"quiet_hinge").is_empty() and not _find_option(options, &"dash_blast").is_empty(), "the deterministic third tier offers both new gameplay effects")
	var previous_cooldown := 1.5
	for level in range(1, 9):
		var result := evolution.apply_mission_reward(&"quiet_hinge")
		slice._refresh_combined_modifiers()
		slice.player.fold_component.on_release()
		var cooldown := slice.player.get_fold_cooldown_remaining()
		_check(not result.is_empty() and cooldown < previous_cooldown and is_equal_approx(cooldown, 1.5 * pow(0.9, level)), "Fold cooldown stack %d changes the real cooldown without hitting a hidden floor" % level)
		previous_cooldown = cooldown
	_check(evolution.apply_mission_reward(&"quiet_hinge").is_empty() and _find_option(evolution.get_mission_reward_options(2), &"quiet_hinge").is_empty(), "maxed Fold cooldown is rejected and replaced in future drafts")
	evolution.experience_level = 2
	_check(evolution.apply_experience_reward(&"quiet_hinge").is_empty() and evolution.experience_claimed_levels == 0, "the XP ledger cannot bypass the shared eight-stack cap or consume its entitlement on failure")
	for level in range(1, 7):
		evolution.apply_mission_reward(&"dash_blast")
	_check(evolution.apply_mission_reward(&"dash_blast").is_empty() and _find_option(evolution.get_experience_reward_options(4), &"dash_blast").is_empty(), "maxed dash blast cannot reappear as an ineffective XP card")
	slice._refresh_combined_modifiers()
	_check(int(slice.player.rogue_build_stats.dash_blast_level) == 6, "the real endless player receives all six blast stacks")
	var rogue_stats := FoldlightBuildResolver.aggregate_stats({"quiet_hinge": 8, "razor_wake": 6})
	slice.player.apply_roguelite_stats(rogue_stats)
	_check(is_equal_approx(slice.player.fold_component.cooldown_multiplier, pow(0.9, 8)) and int(slice.player.rogue_build_stats.dash_blast_level) == 6, "the roguelite resources resolve to the same cooldown and blast components")
	_check(FoldlightBuildResolver.modifier_validation_errors().is_empty(), "all authored upgrade keys retain a declared runtime owner")


func _test_movement_and_dash_snapshot(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(3)
	var player := slice.player
	player.set_horizontal_input_reversed(true)
	_check(player.transform_movement_input(Vector2(0.6, -0.8)).is_equal_approx(Vector2(-0.6, -0.8)), "inversion transforms only horizontal movement and preserves stick magnitude")
	player.set_touch_movement(Vector2.RIGHT)
	player._physics_process(1.0 / 60.0)
	_check(player._last_direction.x < -0.9, "actual touch movement updates the last direction after inversion")
	player.apply_roguelite_stats({"dash_blast_level": 1})
	var origin := player.global_position
	var ended: Array[Dictionary] = []
	var ended_listener := func() -> void: ended.append(player.get_dash_blast_snapshot())
	player.dash_ended.connect(ended_listener)
	_check(player.request_dash() and player.dash_component.direction.x < -0.9, "a newly requested dash follows the inverted movement direction")
	player.set_horizontal_input_reversed(false)
	_check(player.dash_component.direction.x < -0.9, "leaving the inversion field does not redirect an already moving dash")
	player.global_position += Vector2(-60.0, 0.0)
	player._record_dash_blast_position()
	player.global_position += Vector2(0.0, 45.0)
	player.apply_roguelite_stats({"dash_blast_level": 6})
	player.dash_component.tick(0.3)
	_check(ended.size() == 1 and int(ended[0].damage) == 10 and is_equal_approx(float(ended[0].radius), 110.0), "one dash freezes its blast power when it starts")
	if not ended.is_empty():
		var path: PackedVector2Array = ended[0].path
		_check(path.size() == 3 and path[0] == origin and path[2] == player.global_position, "the blast retains real movement corners and its final position")
	player.dash_component.tick(3.0)
	_check(player.request_dash(Vector2.UP), "the next charged dash can use the strengthened blast")
	player.set_play_enabled(false)
	player._physics_process(1.0)
	_check(ended.size() == 1, "paused gameplay cannot finish a dash or emit an extra explosion")
	player.set_horizontal_input_reversed(true)
	player.reset_player()
	_check(ended.size() == 1 and player.get_dash_blast_snapshot().is_empty() and not player.is_horizontal_input_reversed(), "reset discards unfinished explosions and inversion without a synthetic dash end")
	player.dash_ended.disconnect(ended_listener)


func _test_density_and_miasma(controller: FoldlightEndlessSurvivalController) -> void:
	controller.start_run(3)
	var evolution := controller.evolution
	var expected := {0.0: 28, 375.0: 48, 675.0: 60, 1125.0: 80, 7200.0: 80}
	var previous_time := 0.0
	for seconds: float in expected:
		evolution.advance_survival(seconds - previous_time)
		previous_time = seconds
		var snapshot := evolution.get_enemy_snapshot()
		_check(int(snapshot.population_limit) == int(expected[seconds]) and int(snapshot.threat_limit) <= 160, "population at %.0f seconds grows predictably and remains bounded" % seconds)
	controller.start_run(3)
	evolution.advance_survival(179.0)
	controller.wave_sequence = 3
	controller.report_population({})
	_check(_count_miasma(controller.force_next_wave()) == 0, "poison enemies cannot enter before their combat-time unlock")
	evolution.advance_survival(1.0)
	controller.wave_sequence = 3
	controller.report_population({})
	var first := controller.force_next_wave()
	_check(_count_miasma(first) == 2 and int(controller.get_population_snapshot().miasma_pending_count) == 2, "the first poison pair consumes pending population before either actor exists")
	controller.wave_sequence = 7
	_check(_count_miasma(controller.force_next_wave()) == 0, "a second wave cannot exceed the two-poison cap while the first pair is pending")
	controller.report_population({"miasma_alive_count": 1, "miasma_pending_count": 1})
	controller.wave_sequence = 11
	_check(_count_miasma(controller.force_next_wave()) == 0, "live and warning-stage poison actors share one quota")
	evolution.advance_survival(540.0)
	controller.report_population({"miasma_alive_count": 2})
	controller.wave_sequence = 15
	_check(_count_miasma(controller.force_next_wave()) == 1, "twelve-minute pressure may add only one poison actor to an existing pair")
	controller.report_population({"threat_total": int(evolution.get_enemy_snapshot().threat_limit) - 3})
	controller.wave_sequence = 19
	_check(_count_miasma(controller.force_next_wave()) == 0, "poison reinforcements still require their full four threat units")
	controller.report_population({})
	controller.wave_sequence = 20
	var ordinary := controller.force_next_wave()
	var fodder := 0
	for entry: Dictionary in ordinary.entries:
		if StringName(entry.enemy_id) == &"drifter":
			fodder += 1
	_check(fodder * 2 >= ordinary.entries.size(), "late additional population primarily consists of low-cost readable fodder")


func _find_option(options: Array[Dictionary], id: StringName) -> Dictionary:
	for option: Dictionary in options:
		if StringName(option.id) == id:
			return option
	return {}


func _count_miasma(wave: Dictionary) -> int:
	var count := 0
	for entry: Dictionary in wave.entries:
		if StringName(entry.enemy_id) == &"miasma_wraith":
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		failures.append(label)
