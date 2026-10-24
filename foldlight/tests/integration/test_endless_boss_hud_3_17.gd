extends SceneTree
const Navigation = preload("res://scripts/endless/navigation_overlay.gd")
var _failures := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.get_node("ProfileManager").persistence_enabled = false
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(player)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	player.configure_roguelite_combat(true)
	for weapon in FoldlightRogueContentCatalog.WEAPONS: player.weapon_mount.equip(weapon, 3)
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	var nav := Navigation.new()
	ui.attach_navigation_overlay(nav)
	var navigation := {"bounds": Rect2(0,0,6000,4200), "map_title": "折叠三角洲", "player_position": Vector2(3000,2100), "objective": {"id": &"capture", "kind": &"capture_point", "title": "守住潮汐信标", "status": &"active", "target_active": true, "target_position": Vector2(800,1000), "progress": 4, "required": 18, "instruction": "圈内驻守；返光加速点亮。"}, "danger": {"state": &"closed", "safe_position": Vector2(3200,2400)}}
	var director := {"state": &"idle", "difficulty_tier": 2, "next_level": 8, "capacity": 3, "active_count": 0}
	var context := {"endless_navigation": true, "experience": {"level":7,"xp_in_level":50,"xp_to_next":140}, "boss_director":director, "bosses":[]}
	ui.show_hud()
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	nav.update_snapshot(navigation)
	await _settle()
	var rail: Control = ui._endless_boss_status
	_check(rail.get_display_snapshot().header.contains("Lv.8") and rail.get_display_snapshot().header.contains("难度 3"), "next boss level and one-based display of authoritative tier visible before first wave")
	director.state = &"warning"
	director.warning_remaining = 2.7
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	_check(rail.get_display_snapshot().header.contains("2.7秒") and rail.get_display_snapshot().header.contains("保持移动"), "warning states the authoritative countdown and counterplay")
	await create_timer(0.1).timeout
	_check(rail.get_display_snapshot().director.warning_remaining == 2.7, "UI does not advance warning time independently")
	context.bosses = [{"title":"礁冠炮台","health":133.5,"maximum_health":300}, {"title":"倒悬档案官","health":520,"maximum_health":600}, {"title":"折纸裁判","health":75,"maximum_health":850}]
	director.state = &"active"
	director.active_count = 3
	director.next_level = 20
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	await _settle()
	_check(rail.get_display_snapshot().health_values == [Vector2(133.5,300),Vector2(520,600),Vector2(75,850)], "three named bars retain exact independent current and maximum health")
	_check(not rail.get_global_rect().intersects(nav.get_navigation_snapshot().task_rect) and not rail.get_global_rect().intersects(nav.get_navigation_snapshot().map_rect) and not rail.get_global_rect().intersects(nav._danger.get_global_rect()), "desktop bosses clear tasks, map and closed-zone warning")
	nav._toggle_map()
	_check(not rail.get_global_rect().intersects(nav.get_navigation_snapshot().map_rect), "expanded desktop chart keeps all boss health visible")
	nav._toggle_map()
	await _save("desktop-three-bosses")
	var touch := root.get_node("TouchControls")
	touch._safe_insets = Vector4(80,160,56,24)
	touch._set_touch_mode(true)
	for race in [false, true]:
		context.race = race
		for resolution in [Vector2i(844,390),Vector2i(360,780)]:
			root.size = resolution
			ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
			nav.update_snapshot(navigation)
			await _settle()
			var rect := rail.get_global_rect()
			_check(Rect2(0,160,1920,896).encloses(rect), "%s race=%s boss rail clears screen and native insets" % [resolution,race])
			for blocked in [ui._mobile_hud.arsenal.get_global_rect(),ui._mobile_hud.experience.get_global_rect(),ui._mobile_hud.pause_button.get_global_rect(),nav.get_navigation_snapshot().task_rect,nav.get_navigation_snapshot().map_rect,nav._danger.get_global_rect()]:
				_check(not rect.intersects(blocked), "mobile bosses do not cover shared HUD/map/zone warning")
			var layout: Dictionary = touch.get_layout_snapshot()
			for key in ["move","fold","dash","active"]:
				var center: Vector2 = layout[key]
				var radius := float(layout[key+"_radius"])
				_check(not rect.intersects(Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)), "mobile bosses clear "+key+" input")
			_check(not rect.intersects(nav._indicator_text.get_global_rect()), "mobile boss rail clears objective/evacuation arrow label")
			nav._toggle_map()
			_check(not rect.intersects(nav.get_navigation_snapshot().map_rect), "expanded mobile chart clears multi-boss rail even during a race")
			nav._toggle_map()
			if resolution.x == 844: await _save("mobile-three-bosses-race" if race else "mobile-three-bosses")
	ui.show_pause()
	_check(not rail.is_visible_in_tree(), "shared pause hides boss status with combat HUD")
	ui.show_hud()
	context.bosses[1].defeated = true
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	_check(rail.get_display_snapshot().rows == 2 and rail.get_display_snapshot().bosses[1].title == "折纸裁判", "defeated boss removes only its own row")
	context.objective_feedback = {"source":&"boss","title":"首领遭遇 1 · 已击破","heal_on_claim":1,"current_health":3,"max_health":5}
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	_check(nav.get_navigation_snapshot().task_title.contains("首领已击破") and nav.get_navigation_snapshot().instruction_text.contains("领奖回复 1 格生命") and nav.get_navigation_snapshot().time_text == "待领奖", "boss completion explicitly offers loot and heal-on-claim during the transition")
	_check(nav.get_navigation_snapshot().objective_id == &"capture" and nav.get_navigation_snapshot().progress == 4, "boss completion projection preserves the real ongoing mission")
	var choices: Array[Dictionary] = [FoldlightWeaponProgression.make_choice(&"crease_lantern",3),FoldlightWeaponProgression.make_choice(&"needle_orbit",3),FoldlightWeaponProgression.make_choice(&"tide_bell",3)]
	ui.show_reward(choices,"首领遭遇 1 · 已击破",context.objective_feedback)
	_check(ui._reward_title.text.contains("首领战利品") and ui._reward_eyebrow.text.contains("三选一") and ui._reward_hint.text.contains("领奖回复 1 格生命"), "boss reward is a clearly named three-choice loot screen with pending recovery")
	_check(not ui._reward_input_guard.can_select() and ui._reward_buttons[0].disabled, "boss loot retains the original input-reading guard")
	context.objective_feedback.current_health = 5
	ui.show_reward(choices,"首领遭遇 1 · 已击破",context.objective_feedback)
	_check(ui._reward_hint.text.contains("生命已满") and not ui._reward_hint.text.contains("回复 1"), "full-health boss loot never promises a nonexistent heal")
	context.objective_feedback = {}
	ui.show_hud()
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	_check(nav.get_navigation_snapshot().task_title.contains("守住潮汐信标") and not nav.get_navigation_snapshot().instruction_text.contains("战利品"), "leaving boss loot restores the preserved mission guidance")
	ui.update_hud(player, {}, {}, "纸礁浅海", "", {"title":"礁冠炮台","health":20,"maximum_health":100,"phase":2})
	_check(not rail.visible and ui._boss_label.visible and ui._mobile_hud.boss.visible, "legacy rogue single boss remains unchanged and clears endless status")
	ui.queue_free()
	player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("ENDLESS_BOSS_HUD_3_17: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL",_failures])
	quit(0 if _failures == 0 else 1)

func _settle() -> void:
	for frame in 4: await process_frame

func _save(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://build/test-runtime/endless-boss-ui-317")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(label+".png"))

func _check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		_failures += 1
		push_error("FAIL "+label)
