extends SceneTree

## The extracted title must preserve onboarding, save entry and controller input.
var _failures: int = 0
var _actions: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene := load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene
	_check(scene != null, "presentation scene loads")
	if scene == null:
		quit(1)
		return
	var ui := scene.instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	await process_frame
	ui.new_run_requested.connect(func() -> void: _actions.append(&"new_run"))
	ui.continue_requested.connect(func() -> void: _actions.append(&"continue"))
	ui.classic_requested.connect(func() -> void: _actions.append(&"story"))
	ui.endless_requested.connect(func() -> void: _actions.append(&"endless"))
	ui.prologue_requested.connect(func() -> void: _actions.append(&"tutorial"))
	ui.settings_requested.connect(func() -> void: _actions.append(&"settings"))

	ui.show_title({})
	await process_frame
	await process_frame
	_check(ui._title_primary.text.begins_with("开始迷航") and ui._title_primary.text.contains("教学"), "first launch leads with a run and explains included teaching")
	_check(not ui._title_continue.visible and not ui._title_prologue.visible, "first launch has one onboarding entry and no empty continue action")
	_check(root.gui_get_focus_owner() == ui._title_primary, "first launch focuses the primary run action")
	_press(ui, &"fold")
	_check(_actions == [&"new_run"], "confirm forwards the new-run request exactly once")

	ui.show_title({"prologue_complete": true, "runs": 3, "victories": 1, "best_region": 2})
	await process_frame
	_check(ui._title_primary.text == "开始迷航" and ui._title_prologue.visible, "learned players can start directly or replay teaching")
	_check(ui._title_stats.text.contains("3") and ui._title_stats.text.contains("2"), "voyage record reflects the supplied profile")
	_press(ui, &"move_down")
	var selected := root.gui_get_focus_owner() as Button
	_check(selected != null and selected.text == "故事航路", "controller navigation moves from main run to story mode")
	_press(ui, &"fold")
	_check(_actions.back() == &"story", "story navigation keeps the legacy campaign signal")
	_press(ui, &"move_down")
	_press(ui, &"fold")
	_check(_actions.back() == &"endless", "endless remains a selectable secondary mode")
	_press(ui, &"move_down")
	_press(ui, &"fold")
	_check(_actions.back() == &"tutorial", "replay teaching emits its own request")

	ui.show_title({"prologue_complete": true, "active_run": {"seed": 82}})
	await process_frame
	_check(ui._title_continue.visible and root.gui_get_focus_owner() == ui._title_continue, "a saved run becomes the focused primary action")
	_press(ui, &"fold")
	_check(_actions.back() == &"continue", "continue forwards without starting a new run")
	_check(ui._title_primary.visible, "a saved run still permits starting a new voyage")
	_press(ui, &"move_up")
	selected = root.gui_get_focus_owner() as Button
	_check(selected != null and selected.text == "退出游戏", "controller navigation wraps around visible title actions")
	var bounds := ui._title_screen.get_global_rect()
	for button: Button in ui._title_screen.focus_buttons:
		if button.visible:
			_check(bounds.encloses(button.get_global_rect()), "title action fits the canvas: %s" % button.name)
			_check(button.size.y >= 52.0, "title action retains the 52-pixel target: %s" % button.name)

	ui.show_pause()
	await process_frame
	_check(not ui._title_primary.is_visible_in_tree(), "pause owns the screen and hides title controls")
	ui.show_settings({"master_volume": 0.5, "music_volume": 0.4, "sfx_volume": 0.8, "screen_shake": 0.5, "vibration": true, "high_contrast": false, "fullscreen": false}, &"pause")
	await process_frame
	_check(ui.screen_kind == &"settings" and ui._settings_buttons.size() == 8, "shared settings retain seven adjustments and a return action")
	_check(ui._settings_buttons[0].text.contains("50%"), "settings render values from the supplied state")
	ui.show_hud()
	await process_frame
	_check((ui._focus_groups[&"active"] as Array).is_empty(), "combat clears menu navigation ownership")
	_check(ui._hud_health_bar != null and ui._hud_dash_bar != null and ui._hud_active_bar != null, "compact HUD preserves health and cooldown feedback")
	ui.queue_free()
	await process_frame
	print("Unified presentation: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _press(ui: FoldlightRoguePresentation, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	ui._unhandled_input(event)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
