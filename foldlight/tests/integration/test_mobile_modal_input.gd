extends SceneTree

const Guard = preload("res://scripts/ui/reward_input_guard.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var surface := Control.new()
	root.add_child(surface)
	var guard := Guard.new()
	root.add_child(guard)
	await process_frame
	_touch(guard, 4, true)
	_touch(guard, 9, true)
	guard.begin(surface)
	_tick(guard, 16)
	_check(not guard.can_select(), "two combat fingers held across a modal cannot select it")
	_touch(guard, 4, false)
	_tick(guard, 4)
	_check(not guard.can_select(), "releasing only the movement finger still waits for Fold release")
	_touch(guard, 9, false)
	_check(not guard.can_select(), "final touch release cannot itself confirm a new modal")
	_tick(guard, 2)
	_check(guard.can_select(), "fully released input unlocks a deliberate new choice")
	guard.cancel()
	_touch(guard, 12, true)
	guard.begin(surface)
	_tick(guard, 15)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_tick(guard, 2)
	_check(guard.can_select(), "backgrounding clears a touch whose release never reached the game")
	guard.cancel()
	_touch(guard, 15, true)
	guard.begin(surface)
	_tick(guard, 15)
	_touch(guard, 15, true, true)
	_tick(guard, 2)
	_check(guard.can_select(), "OS cancellation takes precedence over the touch pressed flag")
	guard.cancel()
	_touch(guard, 18, true)
	guard.begin(surface)
	_tick(guard, 4)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_tick(guard, 2)
	_check(not guard.can_select(), "lost focus cannot skip the minimum reading period")
	_tick(guard, 8)
	_check(guard.can_select(), "reading resumes after focus cancellation without a stuck finger")
	guard.cancel()
	Input.action_press(&"move_left")
	guard.begin(surface)
	_tick(guard, 15)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_tick(guard, 3)
	_check(not guard.can_select() and Input.is_action_pressed(&"move_left"), "touch cleanup neither releases nor bypasses held desktop input")
	Input.action_release(&"move_left")
	_tick(guard, 2)
	_check(guard.can_select(), "desktop neutral guard remains usable after touch cancellation")
	guard.cancel()
	var earlier := Guard.new()
	var later := Guard.new()
	root.add_child(earlier)
	root.add_child(later)
	# Both guards see the combat press. The later guard then consumes release
	# through real viewport dispatch, so the earlier local cache misses it.
	_touch_tree(24, true)
	later.begin(surface)
	_touch_tree(24, false)
	later.cancel()
	earlier.begin(surface)
	_tick(earlier, 16)
	_check(earlier.can_select(), "a prior modal guard unlocks after another guard consumed the real touch release")
	earlier.cancel()
	earlier.queue_free()
	later.queue_free()
	guard.queue_free()
	surface.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await create_timer(0.5).timeout
	print("FOLDLIGHT_MOBILE_MODAL_INPUT: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _touch(guard: Node, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	guard._input(event)

func _tick(guard: Node, frames: int) -> void:
	for frame in frames:
		guard._process(0.1)

func _touch_tree(index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = Vector2(100, 100)
	root.push_input(event, true)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
	print(("[PASS] " if condition else "[FAIL] ") + description)

