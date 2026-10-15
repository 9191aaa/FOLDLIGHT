extends SceneTree

const CONTRACT = preload("res://scripts/ui/input_contract.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var trajectories: Array[Vector2] = []
	for kind in ["wasd", "arrow", "dpad", "other_pad", "stick"]:
		_prepare(player)
		_send_move(kind, true)
		check(CONTRACT.movement_vector().is_equal_approx(Vector2.RIGHT), "%s reaches the shared combat movement action" % kind)
		player._physics_process(0.10)
		trajectories.append(player.global_position)
		_send_move(kind, false)
		check(CONTRACT.movement_vector().is_zero_approx(), "%s movement releases without sticking" % kind)
	for point in trajectories:
		check(point.is_equal_approx(trajectories[0]), "keyboard, arrow, D-pad and stick preserve identical full-strength movement")
	_prepare(player)
	_key(KEY_W, true)
	_key(KEY_D, true)
	check(is_equal_approx(CONTRACT.movement_vector().length(), 1.0), "diagonal input preserves normalized movement speed")
	_key(KEY_W, false)
	_key(KEY_D, false)
	Input.action_press(&"ui_right")
	check(CONTRACT.movement_vector().is_zero_approx(), "UI-only action polling cannot move the combat player")
	Input.action_release(&"ui_right")

	player.last_input_device = &"keyboard"
	_axis(0.08)
	check(player.last_input_device == &"keyboard" and CONTRACT.movement_vector().is_zero_approx(), "idle stick drift neither moves the player nor steals keyboard prompts")
	_axis(0.75)
	check(player.last_input_device == &"gamepad", "deliberate stick movement selects controller prompts")
	_axis(0.0)
	_key(KEY_D, true)
	check(player.last_input_device == &"keyboard", "a fresh keyboard input restores keyboard prompts")
	_key(KEY_D, false)

	for kind in ["space", "e", "gamepad"]:
		_prepare(player)
		var starts: Array[int] = [0]
		var releases: Array[int] = [0]
		var start_callback := func() -> void: starts[0] += 1
		var release_callback := func(_count: int, _charge: float) -> void: releases[0] += 1
		player.fold_started.connect(start_callback)
		player.fold_released.connect(release_callback)
		_fold(kind, true)
		check(player.folding and starts[0] == 1, "%s press opens the shared Fold once" % kind)
		if kind != "gamepad":
			_key(KEY_SPACE if kind == "space" else KEY_E, true, true)
			check(starts[0] == 1, "%s key repeat cannot reopen Fold" % kind)
		player.captured = 3
		_fold(kind, false)
		check(not player.folding and releases[0] == 1 and is_equal_approx(player.get_fold_cooldown_remaining(), 1.5), "%s release emits one return and the unchanged Fold cooldown" % kind)
		player.fold_started.disconnect(start_callback)
		player.fold_released.disconnect(release_callback)

	for gamepad in [false, true]:
		_prepare(player)
		_send_move("dpad" if gamepad else "arrow", true)
		if gamepad:
			_joy(JOY_BUTTON_B, true)
		else:
			_key(KEY_SHIFT, true)
		player._physics_process(0.02)
		check(player.dash_component.is_dashing() and player.velocity.x > 0.0, "dash uses the same held movement direction for both device families")
		_send_move("dpad" if gamepad else "arrow", false)
		if gamepad:
			_joy(JOY_BUTTON_B, false)
		else:
			_key(KEY_SHIFT, false)
		var uses: Array[int] = [0]
		var callback := func(_item: StringName) -> void: uses[0] += 1
		player.active_item_used.connect(callback)
		if gamepad:
			_joy(JOY_BUTTON_X, true)
			_joy(JOY_BUTTON_X, false)
		else:
			_key(KEY_Q, true)
			_key(KEY_Q, true, true)
			_key(KEY_Q, false)
		check(uses[0] == 1, "Q or X activates the equipped single slot once")
		player.active_item_used.disconnect(callback)

	_prepare(player)
	var shots: Array[int] = [0]
	player.weapon_mount.shot_requested.connect(func(_snapshot: Dictionary) -> void: shots[0] += 1)
	player.tick_automatic_weapons(1.0, false)
	check(shots[0] == 0, "automatic weapons wait for a real target")
	player.tick_automatic_weapons(0.01, true)
	check(shots[0] == 1, "a valid target fires automatically without a mouse or attack key")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	check(not player.folding and shots[0] == 1 and player.velocity.is_zero_approx(), "mouse clicks keep their UI role without creating a second combat control scheme")
	var mouse_release := mouse.duplicate() as InputEventMouseButton
	mouse_release.pressed = false
	Input.parse_input_event(mouse_release)
	Input.flush_buffered_events()

	player.set_play_enabled(false)
	_key(KEY_SPACE, true)
	_key(KEY_SHIFT, true)
	_key(KEY_Q, true)
	player._physics_process(0.25)
	check(not player.folding and not player.dash_component.is_dashing() and player.velocity.is_zero_approx(), "suspended gameplay rejects Fold, dash and movement input")
	for key in [KEY_SPACE, KEY_SHIFT, KEY_Q]:
		_key(key, false)
	check(CONTRACT.navigation_step(_key_event(KEY_UP, true)) == -1 and CONTRACT.navigation_step(_key_event(KEY_DOWN, true)) == 1, "the same physical arrows navigate shared menus")
	check(CONTRACT.navigation_step(_key_event(KEY_D, true), false) == 0, "vertical-only settings navigation leaves horizontal adjustment to its owner")
	check("SPACE / E" in CONTRACT.combat_hint() and "十字键" in CONTRACT.combat_hint(true), "shared help exposes the actual alternate controls")
	player.queue_free()
	await process_frame
	print("FOLDLIGHT_SHARED_COMBAT_INPUTS: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _prepare(player: FoldlightPlayer) -> void:
	player.reset_player()
	player.configure_roguelite_combat(true)
	player.play_bounds = Rect2(Vector2.ZERO, Vector2(3360, 1920))
	player.global_position = Vector2(800, 500)
	player.set_play_enabled(true)


func _send_move(kind: String, pressed: bool) -> void:
	match kind:
		"wasd": _key(KEY_D, pressed)
		"arrow": _key(KEY_RIGHT, pressed)
		"dpad": _joy(JOY_BUTTON_DPAD_RIGHT, pressed)
		"other_pad": _joy(JOY_BUTTON_DPAD_RIGHT, pressed, 2)
		"stick": _axis(1.0 if pressed else 0.0)


func _fold(kind: String, pressed: bool) -> void:
	if kind == "gamepad":
		_joy(JOY_BUTTON_A, pressed)
	else:
		_key(KEY_SPACE if kind == "space" else KEY_E, pressed)


func _key_event(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	Input.parse_input_event(_key_event(code, pressed, echo))
	Input.flush_buffered_events()


func _joy(button: JoyButton, pressed: bool, device: int = 0) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
