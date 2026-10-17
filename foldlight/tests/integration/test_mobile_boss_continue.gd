extends SceneTree

const Banner = preload("res://scripts/roguelite/ui/boss_clear_banner.gd")
var failures: Array[String] = []
var continued: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var banner := Banner.new()
	root.add_child(banner)
	await process_frame
	banner.continue_requested.connect(func() -> void: continued += 1)
	banner.set_touch_layout(false)
	_check(banner._continue_button.custom_minimum_size.y == 54.0, "desktop continuation retains its authored size")
	banner.set_touch_layout(true)
	var down := InputEventScreenTouch.new()
	down.index = 8
	down.pressed = true
	banner._input_guard._input(down)
	banner.present("倒悬档案官", "无名日庭")
	await process_frame
	await process_frame
	var panel: Rect2 = banner._panel.get_global_rect()
	_check(panel.position.y >= 180 and panel.end.y <= 1050 and panel.position.x >= 0 and panel.end.x <= 1920, "mobile victory panel fits below browser controls and inside the game")
	_check(banner._continue_button.size.y * 360.0 / 1080.0 >= 44.0, "continue target is at least 44 CSS pixels on a 360-high phone")
	for step in 21:
		banner._input_guard._process(0.1)
	banner._continue_button.pressed.emit()
	_check(continued == 0, "touch mode cannot skip the 2.2-second Boss aftermath")
	for step in 4:
		banner._input_guard._process(0.1)
	_check(not banner.can_continue() and banner._hint.text.contains("手指"), "held combat touch remains blocked after Boss reading time")
	var up := InputEventScreenTouch.new()
	up.index = 8
	up.pressed = false
	banner._input_guard._input(up)
	_check(continued == 0, "old touch release never advances the voyage")
	for step in 2:
		banner._input_guard._process(0.1)
	_check(banner.can_continue() and banner._hint.text.contains("轻触"), "released touch enables the mobile continue prompt")
	banner._continue_button.pressed.emit()
	banner._continue_button.pressed.emit()
	_check(continued == 1, "a deliberate continue remains single-use on mobile")
	banner.dismiss()
	banner.set_touch_layout(false)
	_check(banner._continue_button.custom_minimum_size.y == 54.0 and banner._title.get_theme_font_size("font_size") == 30, "desktop fonts and buttons restore after device-layout change")
	banner.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await create_timer(0.5).timeout
	print("FOLDLIGHT_MOBILE_BOSS_CONTINUE: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
	print(("[PASS] " if condition else "[FAIL] ") + description)
