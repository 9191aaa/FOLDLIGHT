extends SceneTree

const Touch = preload("res://scripts/autoloads/touch_controls.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# A 20:9 phone has side bars around the 16:9 game. Only the part of a
	# display cutout overlapping real content may move controls inward.
	check(Touch.native_safe_insets(Vector2(2400, 1080), Vector2(1920, 1080), Rect2(80, 0, 2320, 1080)) == Vector4.ZERO, "notch inside letterbox leaves game coordinates unchanged")
	check(Touch.native_safe_insets(Vector2(2400, 1080), Vector2(1920, 1080), Rect2(300, 24, 2100, 1032)) == Vector4(60, 24, 0, 24), "physical safe rectangle accounts for letterbox, status bar and navigation bar")
	check(Touch.native_safe_insets(Vector2(1280, 720), Vector2(1920, 1080), Rect2(32, 0, 1248, 696)).is_equal_approx(Vector4(48, 0, 0, 36)), "safe insets scale into logical viewport")
	check(Touch.native_safe_insets(Vector2.ZERO, Vector2(1920, 1080), Rect2()) == Vector4.ZERO, "unavailable display metrics safely fall back")
	var controls: Node = root.get_node("TouchControls")
	controls._safe_insets = Vector4(72, 0, 80, 36)
	controls._set_touch_mode(true)
	var hud := load("res://scripts/roguelite/ui/mobile_combat_hud.gd").new() as Control
	root.add_child(hud)
	hud.apply_safe_area(controls._safe_insets)
	check(hud.health.position.x == 116.0, "health labels clear native left inset")
	check(hud.pause_button.position.x + hud.pause_button.size.x <= root.get_visible_rect().size.x - 80.0, "pause target clears native right inset")
	check(not hud.voyage.get_rect().intersects(hud.status.get_rect()), "voyage and status have independent rectangles")
	hud.queue_free()
	await process_frame
	print("Android safe area: %d failures" % failures)
	quit(1 if failures else 0)

func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
