extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	_test_theme_transmission(slice)
	_test_live_flag_motion_setting(slice)
	_prepare_capture(slice)
	_test_completion_pause_and_input(slice)
	_test_terminal_lifecycle(slice)
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_ENDLESS_COMPLETION_TRANSITION_3_14: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_theme_transmission(slice: FoldlightEndlessSliceRuntime) -> void:
	var expected_music: Array[StringName] = [&"reef", &"archive", &"eclipse"]
	for index in 3:
		slice.start_slice(314100 + index)
		var style := slice.controller.map_definition.region_style
		_check(slice.world.room_runtime.backdrop.style_id == style, "map %d transmits its authored style to the combat backdrop" % index)
		var terrain := slice._build_room_terrain()
		_check(terrain.all(func(piece: Dictionary) -> bool: return StringName(piece["visual_style"]) == style), "map %d transmits its authored style to every foreground wall" % index)
		_check(StringName(slice.audio_director.get_music_state()["theme"]) == expected_music[index], "map %d preserves the matching 3.12 music theme" % index)


func _test_live_flag_motion_setting(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(314102)
	var flag: Node2D = slice._objective_target
	_check(is_instance_valid(flag), "fire-flag task creates its real target before changing settings")
	if not is_instance_valid(flag):
		return
	var previous_shake := float(slice.profile_manager.get_setting(&"screen_shake", 1.0))
	slice._pause_game()
	slice.profile_manager.set_setting(&"screen_shake", 0.0)
	slice._apply_feedback_settings()
	slice._resume_game()
	var time_before := float(flag.get("_visual_time"))
	flag.advance_simulation(0.25)
	_check(float(flag.get("_visual_time")) == time_before, "existing fire flag stops swaying after reduced motion is changed in pause settings")
	flag.take_damage(5.0)
	_check(float(flag.get("health")) < float(flag.get("maximum_health")), "reduced motion preserves real flag damage feedback")
	slice.profile_manager.set_setting(&"screen_shake", previous_shake)
	slice._apply_feedback_settings()


func _prepare_capture(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(314100)
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.global_position = slice.controller.objectives.get_snapshot()["target_position"]


func _complete_capture(slice: FoldlightEndlessSliceRuntime) -> void:
	var objective := slice.controller.objectives.get_snapshot()
	slice.controller.objectives.advance(float(objective["required"]), objective["target_position"])


func _test_completion_pause_and_input(slice: FoldlightEndlessSliceRuntime) -> void:
	var hostile := slice.combat_runtime._spawn_projectile({"origin": slice.player.global_position + Vector2(150, 0), "velocity": Vector2.LEFT * 120.0, "hostile": true, "reflectable": true, "lifetime": 4.0})
	_complete_capture(slice)
	var frozen_objective := slice.controller.objectives.get_snapshot()
	var time_before := slice.controller.evolution.survival_seconds
	var waves_before := slice.controller.wave_sequence
	var health_before := slice.player.health
	var projectile_before := hostile.global_position
	var options := slice.controller.get_pending_mission_rewards()
	_check(slice._modal_kind == &"objective_complete" and slice.presentation.screen_kind == &"hud", "completed facility remains visible before the reward cards appear")
	_check(not slice.player.play_enabled and not slice.combat_runtime.active and not options.is_empty(), "completion beat freezes combat while preserving the prepared reward")
	var visual := slice.controller.map_runtime.get_objective_visual_snapshot()
	_check(bool(visual["visible"]) and is_equal_approx(float(visual["terminal_remaining"]), 0.5), "the actual completed facility starts a half-second final animation")
	var levels_before := slice.controller.weapon_levels.duplicate(true)
	slice._on_reward_chosen(StringName(options[0]["id"]))
	_check(slice.controller.weapon_levels == levels_before and slice._modal_kind == &"objective_complete", "an early or held-input choice cannot claim during the completion beat")
	slice._physics_process(1.0)
	slice.controller.advance_simulation(1.0, slice.player.global_position)
	slice.combat_runtime._physics_process(1.0)
	_check(slice.controller.evolution.survival_seconds == time_before and slice.controller.wave_sequence == waves_before and slice.controller.objectives.get_snapshot() == frozen_objective, "reward transition advances neither survival score, waves, nor the next task")
	_check(hostile.global_position == projectile_before and slice.player.health == health_before, "projectiles and damage stay frozen during the facility animation")
	var race := slice.get_race_stats()
	_check(bool(race["paused"]) and String(race["pauseReason"]) == "reward", "cross-platform race reports completion time as a reward pause")
	slice._advance_reward_completion(20.0)
	_check(slice._modal_kind == &"objective_complete" and is_equal_approx(slice._reward_completion_remaining, 0.4), "a single long or resumed frame cannot skip the full completion animation")
	_check(float(slice.controller.map_runtime.get_objective_visual_snapshot()["animation_time"]) > float(visual["animation_time"]), "only facility presentation advances during the frozen completion beat")
	slice._pause_game()
	var remaining := slice._reward_completion_remaining
	var paused_visual := slice.controller.map_runtime.get_objective_visual_snapshot()
	slice._advance_reward_completion(0.1)
	slice._process(2.0)
	_check(slice._modal_kind == &"pause" and is_equal_approx(slice._reward_completion_remaining, remaining) and slice.controller.map_runtime.get_objective_visual_snapshot() == paused_visual, "manual pause freezes completion animation without discarding its reward")
	slice._resume_game()
	_check(slice._modal_kind == &"objective_complete" and not slice.player.play_enabled and not slice.combat_runtime.active, "resume returns to the same completion beat instead of enabling combat")
	var touch := root.get_node("TouchControls")
	touch.apply_host_state({"layout": "mobile", "suspended": true, "cancelEpoch": 314, "viewport": {"width": 900, "height": 500}})
	slice._advance_reward_completion(0.1)
	_check(is_equal_approx(slice._reward_completion_remaining, remaining), "portrait or hidden mobile host cannot advance reward entry behind its overlay")
	touch.apply_host_state({"layout": "desktop", "suspended": false, "cancelEpoch": 315, "viewport": {"width": 1280, "height": 720}})
	slice._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	slice._advance_reward_completion(0.1)
	_check(is_equal_approx(slice._reward_completion_remaining, remaining), "application suspension preserves the remaining completion beat")
	slice._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var previous_shake := float(slice.profile_manager.get_setting(&"screen_shake", 1.0))
	slice.profile_manager.set_setting(&"screen_shake", 0.0)
	slice._apply_feedback_settings()
	var reduced_before := slice.controller.map_runtime.get_objective_visual_snapshot()
	slice._advance_reward_completion(0.1)
	var reduced_after := slice.controller.map_runtime.get_objective_visual_snapshot()
	_check(bool(reduced_after["motion_reduced"]) and reduced_after["animation_time"] == reduced_before["animation_time"] and float(reduced_after["terminal_remaining"]) < float(reduced_before["terminal_remaining"]), "reduced motion keeps the readable completion delay without decorative movement")
	slice.profile_manager.set_setting(&"screen_shake", previous_shake)
	slice._apply_feedback_settings()
	for _step in 4:
		slice._advance_reward_completion(0.1)
	_check(slice._modal_kind == &"reward" and slice.presentation.screen_kind == &"reward", "reward cards appear after the completion interval")
	_check(not slice.presentation._reward_input_guard.can_select(), "newly opened reward cards begin their existing one-second read protection")
	for _step in 9:
		slice.presentation._reward_input_guard._process(0.1)
	_check(not slice.presentation._reward_input_guard.can_select(), "the completion beat does not count toward the separate card reading interval")
	for _step in 2:
		slice.presentation._reward_input_guard._process(0.1)
	_check(slice.presentation._reward_input_guard.can_select(), "neutral input becomes selectable only after a full card reading interval")
	slice._on_reward_chosen(StringName(options[0]["id"]))
	_check(slice._modal_kind.is_empty() and slice.combat_runtime.active and slice.player.play_enabled, "legal reward selection resumes the same run after both protection stages")


func _test_terminal_lifecycle(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_capture(slice)
	_complete_capture(slice)
	slice._finish_run()
	for _step in 10:
		slice._advance_reward_completion(0.1)
	_check(slice.run_ended and slice._modal_kind == &"game_over" and slice.presentation.screen_kind == &"result" and slice.controller.get_pending_mission_rewards().is_empty(), "death during completion cancels the delayed reward without reopening cards")
	_prepare_capture(slice)
	_complete_capture(slice)
	slice.start_slice(314100)
	for _step in 10:
		slice._advance_reward_completion(0.1)
	_check(slice._modal_kind.is_empty() and slice.controller.get_pending_mission_rewards().is_empty() and slice.controller.weapon_levels == {"crease_lantern": 1}, "restarting cancels the previous completion and cannot deliver its reward in the new run")
	_complete_capture(slice)
	slice.stop_web_race("finished")
	for _step in 10:
		slice._advance_reward_completion(0.1)
	_check(slice.run_ended and slice._modal_kind == &"race_finished" and not slice.presentation._reward_input_guard.can_select(), "server race completion cancels the facility-to-reward transition")
	_prepare_capture(slice)
	_complete_capture(slice)
	slice._return_to_title()
	slice._advance_reward_completion(1.0)
	_check(slice._transitioning_to_title and not slice.controller.active and slice._reward_completion_remaining == 0.0 and slice.presentation.screen_kind != &"reward", "leaving the mode cancels reward entry before the deferred scene transition")


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		_failures.append(label)
