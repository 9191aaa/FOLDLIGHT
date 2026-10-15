extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var next_scene_button := Button.new()
	next_scene_button.text = "New scene"
	root.add_child(next_scene_button)
	next_scene_button.grab_focus()
	var ui := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	ui.show_title({})
	# SceneTree removes the old scene immediately, but its deferred calls may
	# run before its nodes are freed. Reproduce those two queued title requests.
	root.remove_child(ui)
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "detached title cannot grab focus from the new scene")
	root.add_child(ui)
	ui.show_title({})
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == ui._title_primary, "live title still receives initial keyboard focus")
	ui.show_title({})
	ui.show_hud()
	next_scene_button.grab_focus()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "changing to HUD invalidates a queued menu focus request")
	ui.show_title({})
	ui.hide()
	next_scene_button.grab_focus()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "hidden presentation cannot reclaim keyboard focus")
	ui.queue_free()
	await process_frame
	var tutorial := (load("res://scenes/roguelite/ui/quick_tutorial_overlay.tscn") as PackedScene).instantiate() as FoldlightQuickTutorialOverlay
	tutorial.manual_advance_enabled = true
	root.add_child(tutorial)
	tutorial.begin()
	root.remove_child(tutorial)
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "detached tutorial cannot execute its queued continue focus")
	root.add_child(tutorial)
	tutorial.begin()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == tutorial.continue_button, "live manual tutorial still focuses Continue")
	tutorial.begin()
	tutorial.dismiss()
	next_scene_button.grab_focus()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "dismissed tutorial cannot steal focus after its deferred request")
	tutorial.queue_free()
	await _test_boss_banner_lifecycle(next_scene_button)
	next_scene_button.queue_free()
	await process_frame
	print("FOLDLIGHT_DEFERRED_UI_FOCUS: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_boss_banner_lifecycle(next_scene_button: Button) -> void:
	var banner := (load("res://scripts/roguelite/ui/boss_clear_banner.gd") as Script).new() as Control
	var continuations: Array[int] = [0]
	banner.continue_requested.connect(func() -> void: continuations[0] += 1)
	root.add_child(banner)
	banner.present("礁冠炮城", "倒悬墨城")
	for step in 24:
		banner._input_guard._process(0.1)
	# Web's direct endless entry removes the old scene before its reset calls.
	# Leave a deferred Continue focus queued as that old banner is detached.
	root.remove_child(banner)
	next_scene_button.grab_focus()
	banner.dismiss()
	banner.dismiss()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == next_scene_button, "detached boss dismissal cannot release or steal the new scene focus")
	_check(not banner.visible and not banner._input_guard._active and not banner.can_continue(), "detached boss dismissal is repeatable and cancels its input gate")
	banner._confirm()
	_check(continuations[0] == 0, "detached boss acknowledgement cannot advance the voyage")
	root.add_child(banner)
	banner.present("礁冠炮城", "倒悬墨城")
	_check(not banner.can_continue(), "reattached boss banner starts a fresh reading period")
	for step in 24:
		banner._input_guard._process(0.1)
	await process_frame
	await process_frame
	_check(banner.can_continue() and root.gui_get_focus_owner() == banner._continue_button, "reattached boss banner can arm and focus Continue normally")
	banner._confirm()
	banner._confirm()
	_check(continuations[0] == 1, "reattached boss confirmation advances exactly once")
	next_scene_button.grab_focus()
	banner.dismiss()
	_check(root.gui_get_focus_owner() == next_scene_button, "live boss dismissal preserves another control's focus")
	banner.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
