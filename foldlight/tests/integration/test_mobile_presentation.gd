extends SceneTree
## Same production presentation at phone scale; no replacement UI or game rules.
var failures := 0
var _captures := false
var _pauses := 0
var _adjustments: Array[int] = []
var _departures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_captures = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(844, 390)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	await _settle()
	ui.show_title({"prologue_complete": true, "active_run": {"seed": 1}})
	await _settle()
	var desktop_size := ui._title_primary.custom_minimum_size
	_check(not ui._touch_layout, "a small desktop window alone does not enable touch layout")
	var touch := root.get_node("TouchControls")
	touch._safe_insets = Vector4(0, 160, 0, 0)
	touch._set_touch_mode(true)
	await _settle()
	_check(ui._touch_layout and ui._title_primary.custom_minimum_size.y == 120, "actual touch capability activates large controls")
	_check(ui._title_primary.get_global_rect().position.y >= 184, "title clears the actual host safe area plus spacing")
	_targets(ui, "title")
	await _save("title")
	ui.show_settings(root.get_node("ProfileManager").settings, &"title")
	ui.setting_adjust_requested.connect(func(_key: StringName, direction: int) -> void: _adjustments.append(direction))
	await _settle()
	_targets(ui, "settings")
	_check(ui._settings_grid.columns == 2 and ui._settings_minus[0].visible, "phone settings use two columns with a real decrease action")
	ui._settings_minus[0].pressed.emit()
	ui._settings_buttons[0].pressed.emit()
	_check(_adjustments == [-1, 1], "touch can reduce and increase the existing setting through its original contract")
	await _save("settings")
	ui.show_pause()
	await _settle()
	_targets(ui, "pause")
	await _save("pause")
	ui.show_leave_confirmation()
	await _settle()
	await _save("leave")
	var choices: Array[Dictionary] = []
	for i in 3:
		choices.append({"content_id": StringName("test_%d" % i), "title": ["双层折翼", "流光回响", "纸灯守护"][i], "description": "收纳容量增加，返光命中后获得短暂的折息恢复。", "next_level": 1, "maximum_level": 3})
	ui.show_reward(choices, "纸礁浅海")
	await _settle()
	_check(ui._reward_buttons[0].disabled, "mobile cards retain the entry reading guard")
	await create_timer(1.2).timeout
	_targets(ui, "reward")
	_check(ui._reward_buttons[0].size.x >= 550 and ui._reward_buttons[0].size.y >= 660, "horizontal cards keep readable text while leaving room for the collection entry")
	_check(ui._reward_buttons[0].description_label.get_theme_font_size("font_size") == 34, "reward descriptions remain legible at phone scale")
	await _save("reward")
	var region := {"id": "paper_reef", "title": "纸礁浅海", "nodes": [
		{"id": "start", "depth": 0, "category": "entry", "exits": ["reef", "haven", "forge"]},
		{"id": "reef", "depth": 1, "category": "combat", "risk": 2, "exits": ["boss"]},
		{"id": "haven", "depth": 1, "category": "rest", "risk": 1, "exits": ["boss"]},
		{"id": "forge", "depth": 1, "category": "forge", "risk": 2, "exits": ["boss"]},
		{"id": "boss", "depth": 2, "category": "boss", "risk": 4, "exits": []}]}
	var exits: Array[String] = ["reef", "haven", "forge"]
	ui.route_chosen.connect(func(_id: StringName) -> void: _departures += 1)
	ui.show_route(region, &"start", exits)
	await create_timer(1.2).timeout
	_targets(ui, "route")
	var atlas: Control = ui._route_atlas
	var point: Vector2 = atlas.get_node_screen_position(&"haven")
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 3
		event.position = atlas.global_position + point
		event.pressed = pressed
		root.push_input(event, true)
	_check(atlas.selected_node_id == &"haven" and _departures == 0, "raw touch previews the intended island without departing")
	await _save("route")
	ui.show_boss_card({"content_id": &"reef_crown_battery", "title": "礁冠炮台", "rule": "预警后朝锁定方向射击。", "counterplay": "提前离开预警，抓住回息空档。"})
	await _settle()
	_targets(ui, "mechanic")
	await _save("mechanic")
	ui.show_prologue_step(1, 3, "", "")
	await _settle()
	_check(ui._quick_tutorial.controls_label.text.contains("摇杆"), "the playable tutorial teaches touch controls")
	_check(not ui._quick_tutorial.card.get_global_rect().intersects(ui._mobile_hud.pause_button.get_global_rect()), "the playable tutorial keeps the pause target unobstructed")
	_targets(ui, "tutorial")
	await _save("tutorial")
	ui.hide_prologue_step()
	ui.show_hud()
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(player)
	player.set_physics_process(false)
	player.set_play_enabled(true)
	ui.update_hud(player, {"room_count": 2, "glimmer": 12}, {"category": &"combat"}, "纸礁浅海", "第 2 / 3 波")
	_check(touch.get_debug_snapshot()["active"], "the shared HUD binds the actual playable player to touch controls")
	await _save("hud")
	ui.pause_requested.connect(func() -> void:
		_pauses += 1
		ui.show_pause())
	var pause_touch := InputEventScreenTouch.new()
	pause_touch.index = 2
	pause_touch.pressed = true
	pause_touch.position = ui._mobile_hud.pause_button.get_global_rect().get_center()
	pause_touch.canceled = true
	root.push_input(pause_touch, true)
	_check(_pauses == 0 and ui.screen_kind == &"hud", "a canceled touch over Pause cannot open a modal even when pressed is true")
	pause_touch.canceled = false
	root.push_input(pause_touch, true)
	_check(_pauses == 1, "a second raw touch can pause independently of the mouse finger")
	_check(not touch.get_debug_snapshot()["active"] and ui.screen_kind == &"pause", "entering a modal immediately disables the shared combat touch context")
	pause_touch.pressed = false
	root.push_input(pause_touch, true)
	_check(not ui._desktop_hud.visible, "phone combat hides the desktop bottom ability strip")
	ui.show_result({"victory": false, "rooms": 7, "kills": 25})
	await _settle()
	await _save("result")
	touch._set_touch_mode(false)
	ui.show_title({"prologue_complete": true, "active_run": {"seed": 1}})
	await _settle()
	_check(ui._title_primary.custom_minimum_size == desktop_size and ui._settings_grid.columns == 1 and not ui._settings_minus[0].visible, "leaving touch mode restores original desktop sizes and settings layout")
	_check(ui._reward_buttons[0].custom_minimum_size == Vector2(420, 520), "desktop reward cards retain their original dimensions")
	ui.queue_free()
	player.queue_free()
	await process_frame
	_check(touch._owner() == null, "presentation destruction releases the touch context")
	root.get_node("AudioDirector").shutdown()
	print("MOBILE_PRESENTATION: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _targets(ui: Node, screen: String) -> void:
	for entry: Dictionary in ui.get_touch_debug_buttons():
		_check(float(entry.height) >= 120 and float(entry.width) >= 120, screen + " touch target: " + str(entry.text))
		_check(float(entry.x) >= 0 and float(entry.y) >= 0 and float(entry.x) + float(entry.width) <= 1921 and float(entry.y) + float(entry.height) <= 1081, screen + " fits viewport: " + str(entry.text))

func _settle() -> void:
	for frame in 4: await process_frame

func _save(name: String) -> void:
	if not _captures: return
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://build/test-runtime/mobile-ui/captures")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(name + ".png"))

func _check(value: bool, description: String) -> void:
	if value: print("PASS " + description)
	else:
		failures += 1
		push_error("FAIL " + description)
