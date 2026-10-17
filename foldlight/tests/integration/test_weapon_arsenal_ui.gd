extends SceneTree
## Real mount snapshots remain readable in both shared combat presentations.
const NAV = preload("res://scripts/endless/navigation_overlay.gd")
var _failures := 0
var _captures := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_captures = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(ui)
	root.add_child(player)
	await _settle()
	player.configure_roguelite_combat(true)
	player.set_physics_process(false)
	player.set_play_enabled(true)
	player.weapon_mount.unequip_all()
	for index in FoldlightRogueContentCatalog.WEAPONS.size():
		player.weapon_mount.equip(FoldlightRogueContentCatalog.WEAPONS[index], mini(index + 1, 5))
	player.weapon_mount.register_returned_light(6)
	ui.show_hud()
	_refresh(ui, player)
	await _settle()
	var actual := player.weapon_mount.get_inventory_snapshot()
	_check(actual.size() == 6 and ui._hud_arsenal.get_display_snapshot().inventory == actual, "desktop shows all six actual weapons and their own ranks")
	_check(ui._hud_weapon_bar.value == 6 and ui._hud_weapon_bar.max_value == 8, "partial return-light charge is visible before resonance activates")
	_check(_inside(ui._hud_arsenal.get_global_rect()), "complete desktop arsenal fits the combat viewport")
	await _save("desktop-hud")
	player.weapon_mount.register_returned_light(2)
	_refresh(ui, player)
	_check(bool(ui._hud_arsenal.get_display_snapshot().resonance.active) and is_equal_approx(ui._hud_weapon_bar.value, 3.0), "eighth returned projectile changes the same meter into the three-second countdown")
	player.weapon_mount.advance_resonance(1.25)
	_refresh(ui, player)
	_check(is_equal_approx(ui._hud_weapon_bar.value, 1.75), "the HUD reports actual resonance time without its own gameplay timer")
	ui.show_pause()
	await _settle()
	_check_pause(ui, actual)
	await _save("desktop-pause")
	var nav := NAV.new()
	ui.attach_navigation_overlay(nav)
	var nav_data := {
		"map_id": &"paper_reef", "map_title": "纸礁环湾", "layout_revision": 1,
		"bounds": Rect2(0, 0, 6144, 4096), "player_position": Vector2(3000, 2000),
		"camera_rect": Rect2(2000, 1400, 1920, 1080), "zones": [],
		"objective": {"kind": &"capture_point", "status": &"active", "title": "守住潮汐信标", "instruction": "进入金色信标范围持续驻守。", "progress": 4.5, "required": 10.0, "progress_text": "驻守 4.5 / 10 秒", "time_remaining": 42.0},
		"danger": {"state": &"safe"},
	}
	var touch := root.get_node("TouchControls")
	touch._safe_insets = Vector4(80, 160, 56, 24)
	touch._set_touch_mode(true)
	for resolution: Vector2i in [Vector2i(844, 390), Vector2i(360, 780)]:
		root.size = resolution
		ui.show_hud()
		_refresh(ui, player, true)
		nav.update_snapshot(nav_data)
		await _settle()
		var arsenal: Control = ui._mobile_hud.arsenal
		var view: Dictionary = arsenal.get_display_snapshot()
		_check(view.inventory == actual and bool(view.mobile), "%s keeps all six weapon identities and ranks on the phone" % resolution)
		var rect := arsenal.get_global_rect()
		var navigation := nav.get_navigation_snapshot()
		_check(_inside(rect) and not rect.intersects(navigation.task_rect) and not rect.intersects(navigation.map_rect), "%s arsenal clears task and minimap even with safe-area insets" % resolution)
		_check(not rect.intersects(ui._mobile_hud.pause_button.get_global_rect()), "%s arsenal clears the pause touch target" % resolution)
		var controls: Dictionary = touch.get_layout_snapshot()
		for control in ["move", "fold", "dash", "active"]:
			var radius := float(controls[control + "_radius"])
			var center: Vector2 = controls[control]
			_check(not rect.intersects(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)), "%s arsenal clears %s touch controls" % [resolution, control])
		await _save("mobile-%dx%d-hud" % [resolution.x, resolution.y])
		ui.show_pause()
		await _settle()
		_check_pause(ui, actual)
		await _save("mobile-%dx%d-pause" % [resolution.x, resolution.y])
		for definition in FoldlightRogueContentCatalog.WEAPONS:
			for current_level in [0, 2, 4]:
				var choice := FoldlightWeaponProgression.make_choice(definition.content_id, current_level)
				ui.show_reward([choice], "武器补给")
				await _settle()
				var card := ui._reward_buttons[0] as FoldlightRewardCard
				_check(card.level_label.text == choice.display_level and card.description_label.text == choice.description, "%s rank %d keeps authored weapon growth copy without duplication" % [definition.content_id, current_level + 1])
				_check(card.description_label.get_minimum_size().y <= card.description_label.size.y + 1.0, "%s rank %d phone description fits its card" % [definition.content_id, current_level + 1])
				card.set_selection_available(true)
				_check(card._action_label.text.contains("同行" if current_level == 0 else "强化"), "weapon action distinguishes acquisition from reinforcement")
		ui.show_reward(_three_choices(), "武器补给")
		await _settle()
		await _save("mobile-%dx%d-reward" % [resolution.x, resolution.y])
	touch._set_touch_mode(false)
	root.size = Vector2i(1280, 720)
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		for current_level in [0, 2, 4]:
			ui.show_reward([FoldlightWeaponProgression.make_choice(definition.content_id, current_level)], "武器补给")
			await _settle()
			var card := ui._reward_buttons[0] as FoldlightRewardCard
			_check(card.description_label.get_minimum_size().y <= card.description_label.size.y + 1.0, "%s rank %d desktop description fits enlarged text area" % [definition.content_id, current_level + 1])
	ui.show_reward(_three_choices(), "武器补给")
	await _settle()
	await _save("desktop-reward")
	ui.show_hud()
	player.weapon_mount.advance_resonance(3.0)
	_refresh(ui, player)
	_check(not bool(ui._hud_resonance.active) and ui._hud_weapon_bar.value == 0, "expired resonance restores a new charge cycle")
	ui.queue_free()
	player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("WEAPON_ARSENAL_UI: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _refresh(ui: FoldlightRoguePresentation, player: FoldlightPlayer, endless: bool = false) -> void:
	ui.update_hud(player, {"room_count": 4, "glimmer": 18}, {"category": &"combat"}, "纸礁浅海", "第 3 / 5 波", {}, {"endless_navigation": endless, "region_text": "无尽挑战" if endless else "纸礁浅海"})


func _three_choices() -> Array[Dictionary]:
	return [FoldlightWeaponProgression.make_choice(&"crease_lantern", 2), FoldlightWeaponProgression.make_choice(&"needle_orbit", 0), FoldlightWeaponProgression.make_choice(&"tide_bell", 4)]


func _check_pause(ui: FoldlightRoguePresentation, expected: Array[Dictionary]) -> void:
	var readable := true
	for index in expected.size():
		var label := ui._pause_weapons[index]
		readable = readable and label.visible and label.text.contains(str(expected[index].title)) and label.text.contains(str(expected[index].role)) and label.text.contains("Lv.%d" % int(expected[index].level))
		readable = readable and _inside(label.get_global_rect()) and label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x + 1.0
	_check(readable, "pause sheet exposes every full weapon name, rank and role without truncation")
	_check(ui._pause_arsenal_hint.text.contains("8") and ui._pause_arsenal_hint.text.contains("20%"), "pause sheet explains how to trigger the shared weapon resonance")


func _inside(rect: Rect2) -> bool:
	return Rect2(0, 0, 1921, 1081).encloses(rect)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _save(file_name: String) -> void:
	if not _captures:
		return
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build/test-runtime/weapon-arsenal-ui/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(file_name + ".png"))


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS " + message)
	else:
		_failures += 1
		push_error("FAIL " + message)
