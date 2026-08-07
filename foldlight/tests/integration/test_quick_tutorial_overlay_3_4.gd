extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/roguelite/ui/quick_tutorial_overlay.tscn") as PackedScene
	var overlay := packed.instantiate() as FoldlightQuickTutorialOverlay if packed != null else null
	_check(overlay != null, "quick tutorial scene instantiates through its public type")
	if overlay == null:
		_finish()
		return
	root.add_child(overlay)
	await process_frame

	var completed := [0]
	var skipped := [0]
	overlay.tutorial_completed.connect(func() -> void: completed[0] += 1)
	overlay.tutorial_skipped.connect(func() -> void: skipped[0] += 1)
	overlay.begin(false)
	_check(overlay.visible and overlay.get_step_count() == 3 and overlay.get_current_step() == 0, "tutorial opens as a compact three-step sequence")
	_check("2.0" in overlay.title_label.text + overlay.body_label.text, "movement lesson states the exact two-second dash cooldown")

	overlay.show_step(1)
	_check("SPACE" in overlay.controls_label.text and "8" in overlay.body_label.text and "1.5" in overlay.warning_label.text, "Fold lesson explains keyboard hold/release, capacity, and cooldown")
	overlay.set_input_mode(true)
	_check(overlay.is_gamepad_mode() and "A" in overlay.controls_label.text, "the same lesson swaps to controller prompts")

	overlay.show_step(2)
	_check("自动武器" in overlay.controls_label.text and "X" in overlay.controls_label.text, "final lesson covers automatic fire and the controller active skill")
	_check("不可反射" in overlay.warning_label.text and "地形" in overlay.warning_label.text, "final warning names unreflectable bullets and terrain effects")
	overlay.advance()
	_check(completed[0] == 1 and skipped[0] == 0, "advancing beyond the final page reports completion once")

	await process_frame
	overlay.begin(false)
	overlay.skip()
	_check(skipped[0] == 1 and completed[0] == 1, "skip reports separately from completion")

	overlay.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_QUICK_TUTORIAL_OVERLAY_3_4: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_QUICK_TUTORIAL_OVERLAY_3_4: FAIL — %s" % ", ".join(_failures))
		quit(1)
