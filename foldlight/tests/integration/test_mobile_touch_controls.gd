extends SceneTree

const CONTRACT = preload("res://scripts/ui/input_contract.gd")
var failures: Array[String] = []
var releases: int = 0
var active_uses: int = 0

class HudContext extends CanvasLayer:
	var screen_kind: StringName = &"hud"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var controls: Node = root.get_node("TouchControls")
	var hud := HudContext.new()
	root.add_child(hud)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.fold_released.connect(func(_count: int, _ratio: float) -> void: releases += 1)
	player.active_item_used.connect(func(_id: StringName) -> void: active_uses += 1)
	_prepare(player, controls, hud)
	check(not controls.is_touch_mode() and not controls.get_debug_snapshot()["active"], "desktop keyboard/mouse launch keeps touch controls hidden")
	var mouse := InputEventMouseButton.new()
	mouse.position = Vector2(100, 100)
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	check(not controls.is_touch_mode(), "a real desktop mouse never activates the mobile layout")
	var layout: Dictionary = controls.get_layout_snapshot()
	var stick: Vector2 = layout["move"]
	var fold: Vector2 = layout["fold"]
	var dash: Vector2 = layout["dash"]
	var skill: Vector2 = layout["active"]
	_touch(10, stick, true)
	_drag(10, stick + Vector2(100, 0))
	_touch(11, fold, true)
	var before := player.global_position
	player._physics_process(0.05)
	check(controls.is_touch_mode() and controls.get_debug_snapshot()["active"], "a real touch activates the dedicated controls only in a playable HUD")
	check(player.global_position.x > before.x and player.folding and controls.get_held_touch_count() == 2, "two distinct fingers move the real player while holding Fold")
	check(not Input.is_action_pressed(&"move_right") and not Input.is_action_pressed(&"fold"), "virtual controls leave the global keyboard/controller action state untouched")
	controls.set_context(hud, player, true)
	check(player.folding and controls.get_debug_snapshot()["owned_touch_count"] == 2, "repeated HUD updates do not reset owned fingers")
	_touch(12, skill, true)
	_touch(12, skill, true)
	check(active_uses == 1 and player.folding and controls.get_held_touch_count() == 3, "a third finger uses the active skill once without losing movement or Fold")
	_touch(12, skill, false)
	player.captured = 3
	_touch(11, fold + Vector2(280, 0), false)
	check(releases == 1 and not player.folding and controls.get_held_touch_count() == 1, "releasing the owned Fold finger outside its circle emits exactly one return")
	player._physics_process(0.05)
	check(player.velocity.x > 0.0, "releasing the right finger does not stop the left joystick")
	_touch(10, stick, false)
	check(not controls.has_held_touches() and player._touch_movement.is_zero_approx(), "releasing the joystick clears only its independent movement state")
	_prepare(player, controls, hud)
	_touch(20, stick, true)
	_drag(20, stick + Vector2(100, 0))
	_touch(21, dash, true)
	player._physics_process(0.02)
	check(player.dash_component.is_dashing() and player.velocity.x > 0.0, "a second finger starts a real dash along the held joystick direction")
	_touch(21, dash, false)
	_touch(20, stick, false)
	_prepare(player, controls, hud)
	_key(KEY_D, true)
	_touch(30, stick, true)
	_drag(30, stick - Vector2(100, 0))
	controls.cancel_all(&"focus_lost", true)
	check(Input.is_action_pressed(&"move_right") and CONTRACT.movement_vector(player._touch_movement).is_equal_approx(Vector2.RIGHT), "canceling touch never releases a held physical movement key")
	_key(KEY_D, false)
	_key(KEY_SPACE, true)
	_touch(31, fold, true)
	_touch(31, fold, false)
	check(player.folding and Input.is_action_pressed(&"fold"), "a touch release cannot end a Fold still held by the physical keyboard")
	_key(KEY_SPACE, false)
	check(not player.folding, "the final physical release still ends the shared Fold normally")
	_prepare(player, controls, hud)
	_key(KEY_SPACE, true)
	_touch(32, fold, true)
	_key(KEY_SPACE, false)
	check(player.folding, "a physical release cannot end a Fold still owned by a touch finger")
	_touch(32, fold, false)
	check(not player.folding, "the final touch release ends that mixed-device Fold once")
	_prepare(player, controls, hud)
	_joy(JOY_BUTTON_A, true)
	_touch(33, fold, true)
	controls.cancel_all(&"controller_mix", true)
	check(player.folding and Input.is_action_pressed(&"fold"), "touch cancellation preserves a real gamepad A hold and its Fold")
	_joy(JOY_BUTTON_A, false)
	check(not player.folding, "gamepad release remains responsible for its own final Fold release")
	_prepare(player, controls, hud)
	_touch(40, fold, true)
	player.captured = 4
	var release_before := releases
	var epoch: int = controls.get_cancel_epoch()
	controls.set_context(hud, player, false)
	check(not player.folding and player.captured == 4 and releases == release_before, "opening a modal safely cancels Fold without returning or discarding captured light")
	check(controls.has_held_touches() and controls.get_cancel_epoch() == epoch and not controls.get_debug_snapshot()["active"], "modal cancellation keeps physical fingers held for the reward guard without advancing cancel epoch")
	_touch(40, fold, false)
	check(not controls.has_held_touches() and releases == release_before, "lifting the old combat finger inside a modal cannot release light")
	controls.set_context(hud, player, true)
	check(not player.folding, "returning to the HUD requires a fresh touch press")
	_prepare(player, controls, hud)
	_touch(41, fold, true)
	player.captured = 2
	release_before = releases
	epoch = controls.get_cancel_epoch()
	_touch(41, fold, true, true)
	check(not player.folding and player.captured == 2 and releases == release_before and not controls.has_held_touches() and controls.get_cancel_epoch() > epoch, "canceled takes precedence over pressed and never becomes a release attack")
	_touch(42, fold, true)
	epoch = controls.get_cancel_epoch()
	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not player.folding and releases == release_before and not controls.has_held_touches() and controls.get_cancel_epoch() > epoch, "application blur clears touch and preserves capture without firing")
	controls.apply_host_state({"enabled": true, "cancelEpoch": 1, "suspended": false})
	_touch(43, fold, true)
	controls.apply_host_state({"enabled": true, "cancelEpoch": 2, "suspended": true, "safeArea": {"left": 12, "top": 48, "bottom": 10}, "viewport": {"width": 960, "height": 540}})
	check(not player.folding and releases == release_before and not controls.get_debug_snapshot()["active"] and is_equal_approx(Engine.time_scale, 1.0), "host cancellation and portrait suspension disable input without changing the simulation clock")
	check(controls.get_layout_snapshot()["safe_insets"] == Vector4(24, 96, 0, 20), "CSS safe-area pixels map to the game's logical viewport")
	controls.apply_host_state({"enabled": true, "cancelEpoch": 2, "suspended": false})
	_touch(44, fold, true)
	player.set_play_enabled(false)
	check(not player.folding and releases == release_before and not controls.get_debug_snapshot()["active"], "player suspension immediately retires touch even before the next HUD update")
	_touch(44, fold, false)
	_prepare(player, controls, hud)
	var synthetic := InputEventMouseButton.new()
	synthetic.device = InputEvent.DEVICE_ID_EMULATION
	synthetic.pressed = true
	check(CONTRACT.device_for_event(synthetic, &"touch") == &"touch", "touch-emulated mouse events cannot replace touch prompts with desktop prompts")
	_touch(45, Vector2(960, 430), true)
	check(controls.get_debug_snapshot()["owned_touch_count"] == 0 and controls.has_held_touches(), "world and menu-area touches are observed but never claimed as combat controls")
	_touch(45, Vector2(960, 430), false)
	_touch(46, fold, true)
	root.remove_child(hud)
	check(not controls.get_debug_snapshot()["active"] and not player.folding and releases == release_before, "detaching a presentation clears its touch ownership without a release attack")
	hud.free()
	player.queue_free()
	await process_frame
	check(not controls.get_debug_snapshot()["active"], "freeing the old player leaves no stale active touch context")
	controls.cancel_all(&"test_end", true)
	print("FOLDLIGHT_MOBILE_TOUCH_CONTROLS: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _prepare(player: FoldlightPlayer, controls: Node, hud: Node) -> void:
	controls.cancel_all(&"fixture", true)
	player.reset_player()
	player.configure_roguelite_combat(true)
	player.global_position = Vector2(800, 500)
	player.play_bounds = Rect2(0, 0, 3360, 1920)
	player.set_play_enabled(true)
	controls.set_context(hud, player, true)


func _touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
