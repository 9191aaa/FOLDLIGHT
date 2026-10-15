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
	next_scene_button.queue_free()
	await process_frame
	print("FOLDLIGHT_DEFERRED_UI_FOCUS: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)
