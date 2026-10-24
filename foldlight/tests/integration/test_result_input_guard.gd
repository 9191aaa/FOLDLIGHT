extends SceneTree

var failures: Array[String] = []
var exits: int = 0
var retries: int = 0
var abandons: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var ui := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	ui.title_requested.connect(func() -> void: exits += 1)
	ui.retry_requested.connect(func() -> void: retries += 1)
	ui.abandon_requested.connect(func() -> void: abandons += 1)
	await process_frame
	for code: Key in [KEY_SPACE, KEY_E, KEY_ENTER, KEY_ESCAPE]:
		ui.show_hud()
		_send_key(code, true)
		ui.show_result({"won": false})
		var before := exits + retries
		await create_timer(1.12).timeout
		_send_key(code, true, true)
		_send_key(code, false)
		await process_frame
		_check(exits + retries == before, "holding/releasing %s across a result cannot exit or restart" % OS.get_keycode_string(code))
		await create_timer(0.18).timeout
		_send_key(code, true)
		_send_key(code, false)
		_check(exits + retries == before + 1, "fresh %s works after result input is neutral" % OS.get_keycode_string(code))
		_send_key(code, true)
		_send_key(code, false)
		_check(exits + retries == before + 1, "result %s emits at most one transition" % OS.get_keycode_string(code))
	for code: Key in [KEY_ESCAPE, KEY_ENTER, KEY_E, KEY_SPACE]:
		ui.show_result({"won": false})
		await process_frame
		await process_frame
		var before := exits + retries
		_send_key(code, true)
		_send_key(code, false)
		_check(exits + retries == before, "a quick %s during result entry cannot trigger a transition" % OS.get_keycode_string(code))
		ui.show_hud()
	for code: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]:
		ui.show_hud()
		_send_joy(code, true)
		ui.show_result({"won": false})
		var before := exits + retries
		await create_timer(1.12).timeout
		_check(not ui.is_result_ready(), "held gamepad button %d keeps result actions locked" % code)
		_send_joy(code, false)
		await process_frame
		_check(exits + retries == before, "gamepad button %d release cannot select a result action" % code)
		await create_timer(0.18).timeout
		_send_joy(code, true)
		_send_joy(code, false)
		_check(exits + retries == before + 1, "fresh gamepad button %d selects once after neutral input" % code)
	# Direct native button signals must obey the same guard, including hidden
	# actions in a friend-race result; disabled appearance alone is insufficient.
	ui.show_result({"won": false})
	var before := exits + retries
	for button: Button in ui._focus_groups[&"result"]:
		button.pressed.emit()
	_check(exits + retries == before, "result entry guard also rejects direct native button signals")
	ui.show_result({"allow_retry": false, "allow_title": false})
	before = exits + retries
	await create_timer(1.20).timeout
	_send_key(KEY_ESCAPE, true)
	_send_key(KEY_ESCAPE, false)
	for button: Button in ui._focus_groups[&"result"]:
		button.pressed.emit()
	_check(exits + retries == before, "friend-race result remains owned by its webpage after entry delay")
	ui.show_pause()
	(ui._focus_groups[&"pause"][2] as Button).pressed.emit()
	_check(ui.screen_kind == &"leave_confirmation" and abandons == 0, "pause End opens confirmation without ending the voyage")
	(ui._focus_groups[&"leave_confirmation"][1] as Button).pressed.emit()
	_check(abandons == 0, "direct pressed signal cannot bypass leave confirmation input protection")
	_send_key(KEY_ESCAPE, true)
	_send_key(KEY_ESCAPE, false)
	_check(ui.screen_kind == &"pause" and abandons == 0, "Escape can cancel leave confirmation during its entry delay")
	for code: JoyButton in [JOY_BUTTON_B, JOY_BUTTON_START]:
		ui.show_leave_confirmation()
		_send_joy(code, true)
		_send_joy(code, false)
		_check(ui.screen_kind == &"pause" and abandons == 0, "gamepad button %d can cancel leave confirmation during its entry delay" % code)
	ui.show_leave_confirmation()
	await create_timer(1.16).timeout
	await process_frame
	_check(root.gui_get_focus_owner() == ui._focus_groups[&"leave_confirmation"][0], "leave confirmation defaults to Cancel after opening")
	_send_key(KEY_ENTER, true)
	_send_key(KEY_ENTER, false)
	_check(ui.screen_kind == &"pause" and abandons == 0, "default Enter cancels ending and stays paused")
	ui.show_leave_confirmation()
	await create_timer(1.16).timeout
	await process_frame
	_send_key(KEY_DOWN, true)
	_send_key(KEY_DOWN, false)
	_send_key(KEY_ENTER, true)
	_send_key(KEY_ENTER, false)
	(ui._focus_groups[&"leave_confirmation"][1] as Button).pressed.emit()
	_check(abandons == 1 and ui.screen_kind == &"leave_confirmation", "explicit End emits once while preserving the owner's confirmation source gate")
	# Pending entry focus must not return after the owner changes screen.
	ui.show_result({"won": false})
	ui.show_hud()
	await create_timer(1.16).timeout
	_check(ui.screen_kind == &"hud" and not ui._result_input_guard.can_select(), "leaving result during entry cancels its future action/focus activation")
	ui.queue_free()
	await process_frame
	await _test_endless_confirmation()
	print("FOLDLIGHT_RESULT_INPUT_GUARD: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _send_key(code: Key, down: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_joy(code: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_endless_confirmation() -> void:
	_check(change_scene_to_file("res://scenes/endless/endless_survival_slice.tscn") == OK, "real endless scene loads for the exit confirmation path")
	for frame in 5:
		await process_frame
	var slice := current_scene as FoldlightEndlessSliceRuntime
	if slice == null:
		_check(false, "endless scene exists")
		return
	slice._pause_game()
	var ui := slice.presentation
	(ui._focus_groups[&"pause"][2] as Button).pressed.emit()
	var seconds := slice.controller.evolution.survival_seconds
	await create_timer(1.16).timeout
	_check(not slice.run_ended and slice._modal_kind == &"pause" and not slice.combat_runtime.active and slice.controller.evolution.survival_seconds == seconds, "leave confirmation keeps endless combat and its survival clock paused")
	_send_key(KEY_DOWN, true)
	_send_key(KEY_DOWN, false)
	_send_key(KEY_ENTER, true)
	_send_key(KEY_ENTER, false)
	_check(slice.run_ended and slice._modal_kind == &"game_over" and ui.screen_kind == &"result", "explicit confirmation ends endless into the protected shared result")
	_send_key(KEY_ESCAPE, true)
	_send_key(KEY_ESCAPE, false)
	_check(current_scene == slice and ui.screen_kind == &"result", "Escape immediately after ending a voyage cannot carry through to title")


func _check(ok: bool, description: String) -> void:
	if ok:
		print("[PASS] " + description)
	else:
		failures.append(description)
		push_error("[FAIL] " + description)
