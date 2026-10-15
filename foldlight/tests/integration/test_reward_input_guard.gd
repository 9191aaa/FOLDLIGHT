extends SceneTree

## Real viewport input: native Button ui_accept/mouse dispatch and the custom
## Fold path must all require a released input after opening either reward UI.
var _failures: Array[String] = []
var _chosen: Array[StringName] = []
var _endless_claims: int = 0
const CHOICES: Array[Dictionary] = [
	{"content_id": &"tiny_silhouette", "title": "小纸身", "description": "缩小命中体。"},
	{"content_id": &"double_step", "title": "双页步", "description": "增加冲刺储能。"},
	{"content_id": &"large_burden", "title": "巨页契", "description": "体型增大，提升伤害。"},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var ui := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	await process_frame
	ui.reward_chosen.connect(func(id: StringName) -> void: _chosen.append(id))
	# Let containers lay out their real mouse hit targets before testing.
	ui.show_reward(CHOICES, "输入保护")
	await process_frame
	await process_frame
	for input_kind in ["space", "fold_key", "enter", "gamepad", "mouse"]:
		ui.show_hud()
		var before := _chosen.size()
		var point := ui._reward_buttons[0].get_global_rect().get_center()
		_send(input_kind, true, point)
		ui.show_reward(CHOICES, "输入保护")
		ui._reward_buttons[0].pressed.emit()
		await create_timer(1.16).timeout
		_check(_chosen.size() == before and ui._reward_buttons[0].disabled, "%s held before opening cannot select after reading time" % input_kind)
		_send(input_kind, false, point)
		await process_frame
		_check(_chosen.size() == before, "%s release does not become a reward selection" % input_kind)
		await _wait_ready(ui._reward_buttons)
		_check(not ui._reward_buttons[0].disabled, "%s neutral input enables the reward cards" % input_kind)
		_send(input_kind, true, point)
		_send(input_kind, false, point)
		await process_frame
		_check(bool(ui._reward_buttons[0].get_presentation_snapshot()["confirming"]), "%s fresh viewport input starts confirmation" % input_kind)
		ui._reward_buttons[0].pressed.emit()
		ui._reward_buttons[1].pressed.emit()
		await create_timer(0.28).timeout
		_check(_chosen.size() == before + 1 and _chosen.back() == &"tiny_silhouette", "%s fresh selection grants one reward despite repeated signals" % input_kind)

	ui.show_hud()
	Input.action_press(&"fold")
	ui.show_reward(CHOICES, "合成输入同样保护")
	await create_timer(1.16).timeout
	_check(ui._reward_buttons[0].disabled, "held action polling is guarded alongside raw device events")
	Input.action_release(&"fold")
	await _wait_ready(ui._reward_buttons)
	_check(not ui._reward_buttons[0].disabled, "releasing a synthetic held action permits a new choice")

	ui.show_hud()
	_axis(0.8)
	ui.show_reward(CHOICES, "摇杆回中")
	await create_timer(1.16).timeout
	_check(ui._reward_buttons[0].disabled, "movement stick held across combat cannot navigate a fresh reward")
	for frame in 20:
		_axis(0.08 if frame % 2 == 0 else 0.10)
		await process_frame
	_check(not ui._reward_buttons[0].disabled, "continuous stick drift inside the authored deadzone does not prevent selection")
	_axis(0.0)

	var before_cancel := _chosen.size()
	ui.show_reward(CHOICES, "阅读保护")
	_send("enter", true)
	_send("enter", false)
	ui._reward_buttons[0].pressed.emit()
	await create_timer(0.64).timeout
	_check(_chosen.size() == before_cancel and ui._reward_buttons[0].disabled, "quick taps and direct pressed signals cannot skip the one-second reading period")
	ui.show_title({"prologue_complete": true})
	await create_timer(0.60).timeout
	_check(ui.screen_kind == &"title" and _chosen.size() == before_cancel and ui._reward_buttons[0].disabled, "leaving during entry cancels delayed focus and input arming")
	ui.show_reward(CHOICES, "隐藏取消")
	await _wait_ready(ui._reward_buttons)
	ui._reward_buttons[0].pressed.emit()
	_check(bool(ui._reward_buttons[0].get_presentation_snapshot()["confirming"]), "hide cancellation starts from an actual pending confirmation")
	ui.hide()
	await create_timer(0.28).timeout
	_check(_chosen.size() == before_cancel, "hiding the presentation cancels a pending confirmation")
	ui.show()
	ui.show_reward(CHOICES, "连续奖励")
	await _wait_ready(ui._reward_buttons)
	var next_stage := func(_id: StringName) -> void: ui.show_reward([CHOICES[1]], "第二道折痕")
	ui.reward_chosen.connect(next_stage, CONNECT_ONE_SHOT)
	_send("fold_key", true)
	_check(bool(ui._reward_buttons[0].get_presentation_snapshot()["confirming"]), "a fresh fold key begins the first stage before testing held input")
	await create_timer(1.50).timeout
	_check(_chosen.size() == before_cancel + 1 and ui._reward_buttons[0].get_meta("upgrade_id") == &"double_step" and ui._reward_buttons[0].disabled, "a held confirmation cannot carry into the following reward stage")
	_send("fold_key", false)
	await _wait_ready(ui._reward_buttons)
	_send("enter", true)
	_send("enter", false)
	await create_timer(0.28).timeout
	_check(_chosen.size() == before_cancel + 2 and _chosen.back() == &"double_step", "the following reward accepts a separate released and pressed choice")
	ui.queue_free()
	await process_frame
	await _test_endless()
	_finish()


func _test_endless() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.controller.mission_reward_claimed.connect(func(_reward: Dictionary) -> void: _endless_claims += 1)
	var completion := 0
	for input_kind in ["space", "fold_key", "enter", "gamepad", "mouse"]:
		var point := slice.presentation._reward_buttons[0].get_global_rect().get_center()
		_send(input_kind, true, point)
		completion += 1
		slice.controller._on_objective_completed({"completion_count": completion, "title": "输入保护"})
		if completion == 1:
			slice._pause_game()
			_check(slice._modal_kind == &"reward" and slice.presentation._reward_buttons[0].disabled, "a rejected pause request cannot cancel a pending reward's input protection")
		slice.presentation._reward_buttons[0].pressed.emit()
		await create_timer(1.16).timeout
		_check(_endless_claims == completion - 1 and slice._modal_kind == &"reward" and not slice.combat_runtime.active, "endless %s holds the reward and frozen combat while old input remains down" % input_kind)
		_send(input_kind, false, point)
		await process_frame
		_check(_endless_claims == completion - 1, "endless %s release cannot claim the reward" % input_kind)
		await _wait_ready(slice.presentation._reward_buttons)
		_send(input_kind, true, point)
		_send(input_kind, false, point)
		await create_timer(0.28).timeout
		_check(_endless_claims == completion, "endless %s fresh viewport input reaches the reward controller" % input_kind)
		slice.presentation._reward_buttons[0].pressed.emit()
		_check(_endless_claims == completion and slice._modal_kind.is_empty() and slice.combat_runtime.active, "endless %s fresh input claims once and resumes combat" % input_kind)
		slice.combat_runtime.set_active(false)
		slice.player.set_play_enabled(false)
	slice.controller._on_objective_completed({"completion_count": completion + 1, "title": "重启取消"})
	slice.start_slice(44101)
	slice.set_physics_process(false)
	await create_timer(1.16).timeout
	_check(slice._modal_kind.is_empty() and _endless_claims == completion and slice.presentation.screen_kind == &"hud", "endless restart cancels the old reward guard and delayed focus")
	slice._pause_game()
	_check(slice._modal_kind == &"pause" and not (slice.presentation._focus_groups[&"pause"][0] as Button).disabled, "ordinary pause buttons remain immediately usable after reward cancellation")
	(slice.presentation._focus_groups[&"pause"][0] as Button).pressed.emit()
	_check(slice._modal_kind.is_empty(), "ordinary pause can still resume")
	slice.queue_free()
	await process_frame


func _wait_ready(buttons: Array[Button]) -> void:
	# Headless idle frames can run faster than 120 Hz; a frame count is not a
	# one-second reading interval. Require the real UI state and deferred focus.
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if not buttons[0].disabled and root.gui_get_focus_owner() == buttons[0]:
			return
		await process_frame
	_check(false, "reward cards become enabled and focused within the readiness deadline")


func _send(kind: String, pressed: bool, point: Vector2 = Vector2.ZERO) -> void:
	var event: InputEvent
	if kind == "mouse":
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = pressed
		event = mouse
	elif kind == "gamepad":
		var joy := InputEventJoypadButton.new()
		joy.device = 0
		joy.button_index = JOY_BUTTON_A
		joy.pressed = pressed
		event = joy
	else:
		var key := InputEventKey.new()
		key.keycode = KEY_E if kind == "fold_key" else (KEY_ENTER if kind == "enter" else KEY_SPACE)
		key.physical_keycode = key.keycode
		key.pressed = pressed
		event = key
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _finish() -> void:
	print("FOLDLIGHT_REWARD_INPUT_GUARD: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
