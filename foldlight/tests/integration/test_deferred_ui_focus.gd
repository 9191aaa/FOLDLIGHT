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
	await _test_scene_switch_input(next_scene_button)
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


func _test_scene_switch_input(next_scene_button: Button) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var ui := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate() as FoldlightRoguePresentation
	viewport.add_child(ui)
	await process_frame
	await process_frame
	var endless_button: BaseButton
	for candidate: Button in ui._focus_groups[&"title"]:
		if candidate.text.contains("无尽"):
			endless_button = candidate
	_check(endless_button != null, "scene-switch probe finds the real endless title action")
	if endless_button == null:
		viewport.queue_free()
		return
	endless_button.grab_focus()
	var presses: Array[int] = [0]
	var consumed_before_switch: Array[bool] = [false]
	ui.endless_requested.connect(func() -> void:
		presses[0] += 1
		consumed_before_switch[0] = viewport.is_input_handled()
		root.remove_child(viewport)
		next_scene_button.grab_focus()
	)
	var event := InputEventAction.new()
	event.action = &"fold"
	event.pressed = true
	ui._unhandled_input(event)
	_check(presses[0] == 1 and consumed_before_switch[0], "keyboard activation consumes its event before a synchronous endless scene switch")
	_check(not viewport.is_inside_tree() and root.gui_get_focus_owner() == next_scene_button, "scene-switch input leaves the detached viewport alone and preserves the next scene focus")
	ui._unhandled_input(event)
	_check(presses[0] == 1, "a detached presentation ignores a late input event")
	viewport.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
