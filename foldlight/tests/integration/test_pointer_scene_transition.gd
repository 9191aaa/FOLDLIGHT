extends SceneTree

## Dispatch both halves of a touchscreen tap: its emulated mouse click and
## the original touch. The old Control must survive until both are delivered.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	root.size = Vector2i(1920, 1080)
	root.get_node("TouchControls")._set_touch_mode(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	current_scene = game
	await _frames(5)
	var session := game.rogue_session
	var entry: Button = session.presentation._title_screen.focus_buttons[2]
	_check(entry.is_visible_in_tree() and not entry.disabled, "the actual mobile title exposes its endless button")
	var old_game: WeakRef = weakref(game)
	_tap(entry, 0)
	_check(session.is_inside_tree() and session._scene_transitioning, "a title tap locks departure while retaining its Controls for the remaining input dispatch")
	session._on_endless_requested()
	session.presentation.endless_requested.emit()
	await _frames(5)
	_check(current_scene is FoldlightEndlessSliceRuntime and old_game.get_ref() == null, "the completed tap replaces the title with exactly one live endless scene")
	if current_scene is FoldlightEndlessSliceRuntime:
		var endless := current_scene as FoldlightEndlessSliceRuntime
		_check(endless.player.play_enabled and endless.combat_runtime.active, "deferred entry still starts playable endless combat")
		endless._finish_run()
		for frame in 16:
			endless.presentation._result_input_guard._process(0.1)
		await _frames(3)
		var leave: Button = endless.presentation._focus_groups[&"result"][1]
		_check(not leave.disabled and leave.is_visible_in_tree(), "the actual result return action is armed before its tap")
		var old_endless: WeakRef = weakref(endless)
		_tap(leave, 1)
		_check(endless.is_inside_tree() and endless._transitioning_to_title, "a result tap freezes combat while retaining its Controls until dispatch completes")
		_check(not endless.player.play_enabled and not endless.combat_runtime.active, "pending return cannot advance the old combat world")
		endless._return_to_title()
		await _frames(5)
		_check(current_scene is FoldlightGame and old_endless.get_ref() == null, "duplicate return requests yield one clean title after the pointer release")
	if current_scene != null:
		current_scene.queue_free()
	await _frames(2)
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_POINTER_SCENE_TRANSITION: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _tap(button: Button, index: int) -> void:
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		# Godot Web converts the primary touch into a mouse button event, then
		# also dispatches the raw touch to its saved GUI touch-focus Control.
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mouse.pressed = pressed
		mouse.position = point
		mouse.global_position = point
		root.push_input(mouse, true)
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = pressed
		touch.position = point
		root.push_input(touch, true)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _check(ok: bool, message: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + message)
	if not ok:
		failures.append(message)
