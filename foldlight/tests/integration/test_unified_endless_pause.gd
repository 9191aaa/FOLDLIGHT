extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	_check_mute_context(slice, "combat")
	slice.player.set_debug_invincible(true)
	slice.player.captured = 4
	slice.player.dash_component.cooldown_remaining = 1.5
	slice.player.fold_component.cooldown_remaining = 1.2
	slice.player.active_item_slot.cooldown_remaining = 3.0
	var pause_event := InputEventAction.new()
	pause_event.action = &"pause_game"
	pause_event.pressed = true
	slice._unhandled_input(pause_event)
	_check(slice.get_slice_snapshot().modal_kind == &"pause", "Esc opens pause instead of ending the run")
	_check_mute_context(slice, "pause")
	_check(slice.controller.active and not slice.combat_runtime.active, "pause keeps the run and suspends combat")
	_check(not slice.player.play_enabled and slice.player.captured == 4, "pause preserves captured light and freezes player controls")
	var before_time := slice.controller.evolution.survival_seconds
	var before_position := slice.player.global_position
	var enemy_positions: Array[Vector2] = []
	for enemy in slice.combat_runtime.enemies:
		enemy_positions.append(enemy.global_position)
	for frame in 12:
		await physics_frame
	_check(is_equal_approx(before_time, slice.controller.evolution.survival_seconds), "survival and objectives do not tick while paused")
	_check(slice.player.global_position == before_position, "player remains stationary while paused")
	_check(is_equal_approx(slice.player.dash_component.cooldown_remaining, 1.5), "dash cooldown stays frozen while paused")
	_check(is_equal_approx(slice.player.fold_component.cooldown_remaining, 1.2), "Fold cooldown stays frozen while paused")
	_check(is_equal_approx(slice.player.active_item_slot.cooldown_remaining, 3.0), "active item cannot recharge in a pause menu")
	for index in enemy_positions.size():
		_check(slice.combat_runtime.enemies[index].global_position == enemy_positions[index], "enemy position is frozen")
	slice._unhandled_input(pause_event)
	_check(slice.get_slice_snapshot().modal_kind == &"" and slice.combat_runtime.active, "Esc resumes the paused run")
	_check(slice.player.play_enabled and slice.player.captured == 4, "resume restores controls without discarding captured light")
	slice._unhandled_input(pause_event)
	(slice.presentation._focus_groups[&"pause"][1] as Button).grab_focus()
	_check(root.gui_get_focus_owner() == slice.presentation._focus_groups[&"pause"][1], "native GUI focus synchronizes the action selected by Fold/E")
	(slice.presentation._focus_groups[&"pause"][0] as Button).grab_focus()
	(slice.presentation._focus_groups[&"pause"][0] as Button).pressed.emit()
	_check(slice.get_slice_snapshot().modal_kind == &"", "continue button resumes the same run")
	var options := slice.controller.evolution.get_mission_reward_options(0)
	slice._on_mission_reward_offered(options, {"title": "折光任务"})
	_check_mute_context(slice, "reward")
	slice._unhandled_input(pause_event)
	_check(slice.get_slice_snapshot().modal_kind == &"reward", "Esc cannot dismiss a pending reward or resume combat behind it")
	slice.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOLDLIGHT_UNIFIED_ENDLESS_PAUSE: PASS")
		quit(0)
	else:
		push_error("FOLDLIGHT_UNIFIED_ENDLESS_PAUSE: FAIL - %s" % "; ".join(_failures))
		quit(1)


func _check_mute_context(slice: FoldlightEndlessSliceRuntime, context: String) -> void:
	var audio := slice.audio_director
	var previous := audio.is_muted()
	var previous_modal := slice._modal_kind
	var previous_options := slice._modal_options.duplicate(true)
	var previous_time := slice.controller.evolution.survival_seconds
	_send_mute(true)
	_check(audio.is_muted() != previous and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) == audio.is_muted(), "M toggles the actual master bus once during " + context)
	_send_mute(true, true)
	_check(audio.is_muted() != previous, "holding M does not repeat-toggle during " + context)
	_send_mute(false)
	_check(audio.is_muted() != previous, "releasing M does not toggle during " + context)
	_send_mute(true)
	_send_mute(false)
	_check(audio.is_muted() == previous, "a second M press restores audio during " + context)
	_check(slice._modal_kind == previous_modal and slice._modal_options == previous_options and is_equal_approx(slice.controller.evolution.survival_seconds, previous_time), "mute leaves modal choices and effective survival time unchanged during " + context)


func _send_mute(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_M
	event.keycode = KEY_M
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
	print("[%s] %s" % ["PASS" if condition else "FAIL", message])
