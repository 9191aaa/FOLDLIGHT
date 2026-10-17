extends SceneTree
const Navigation = preload("res://scripts/endless/navigation_overlay.gd")
const MapScene = preload("res://scripts/endless/endless_handcrafted_map.gd")
const Definition = preload("res://resources/endless/maps/solar_archipelago.tres")
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
	root.get_node("ProfileManager").persistence_enabled = false
	var map := MapScene.new()
	map.build_physics_walls = false
	root.add_child(map)
	map.configure(Definition)
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(player)
	player.set_physics_process(false)
	player.configure_roguelite_combat(true)
	player.position = Definition.player_spawn
	player.health = 3
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		player.weapon_mount.equip(definition, 3)
	var camera := Camera2D.new()
	camera.position = player.position
	root.add_child(camera)
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	var nav := Navigation.new()
	ui.attach_navigation_overlay(nav)
	var objective := {"id": &"test_capture", "kind": &"capture_point", "status": &"active", "title": "守住潮汐信标", "target_position": player.position + Vector2(240, -80), "target_active": true, "progress": 8.0, "required": 12.0, "time_remaining": 40.0, "occupied": true, "instruction": "进入金色信标范围持续驻守。"}
	var navigation := {"bounds": Definition.bounds, "map_id": Definition.map_id, "map_title": Definition.title, "player_position": player.position, "camera_rect": Rect2(player.position - Vector2(960, 540), Vector2(1920, 1080)), "objective": objective, "zones": [], "danger": {"state": &"safe"}}
	var experience := {"level": 2, "xp_in_level": 14, "xp_to_next": 26, "total_xp": 32, "pending_levels": 0}
	var context := {"endless_navigation": true, "experience": experience, "region_text": "无尽挑战 / 日轮列岛", "voyage_text": "航行 02:18 · 击破 23"}
	ui.show_hud()
	ui.update_hud(player, {}, {}, "无尽挑战", "威胁 2 · 场上 12\n收纳进化 1", {}, context)
	nav.update_snapshot(navigation)
	map.set_active_objective(objective)
	await _settle()
	var desktop: Dictionary = ui._hud_experience.get_display_snapshot()
	_check(desktop.experience == experience and desktop.title.contains("14 / 26") and desktop.guidance.contains("12 经验"), "desktop reports exact kill experience and the next-level requirement")
	_check(not ui._hud_fold.text.is_empty() and ui._hud_status.text.contains("收纳进化"), "kill growth preserves the separate Fold growth feedback")
	_check(_inside(ui._hud_experience.get_global_rect()) and not ui._hud_experience.get_global_rect().intersects(nav.get_navigation_snapshot().task_rect), "desktop experience stays inside its existing top-row space")
	await _save("desktop-growth")
	var touch := root.get_node("TouchControls")
	touch._safe_insets = Vector4(80, 160, 56, 24)
	touch._set_touch_mode(true)
	for resolution: Vector2i in [Vector2i(844, 390), Vector2i(360, 780)]:
		root.size = resolution
		ui.update_hud(player, {}, {}, "无尽挑战", "威胁 2 · 场上 12", {}, context)
		nav.update_snapshot(navigation)
		await _settle()
		var strip: Control = ui._mobile_hud.experience
		var rect := strip.get_global_rect()
		var projection := nav.get_navigation_snapshot()
		var display: Dictionary = strip.get_display_snapshot()
		_check(display.experience == experience and display.title.contains("14/26") and display.title.contains("击破升级"), "%s mobile strip names kill progression and shows its real amount" % resolution)
		_check(_inside(rect) and not rect.intersects(projection.task_rect) and not rect.intersects(projection.map_rect) and not rect.intersects(ui._mobile_hud.arsenal.get_global_rect()) and not rect.intersects(ui._mobile_hud.pause_button.get_global_rect()), "%s experience clears the task, map, all six weapons and pause target" % resolution)
		var controls: Dictionary = touch.get_layout_snapshot()
		for control in ["move", "fold", "dash", "active"]:
			var radius := float(controls[control + "_radius"])
			var center: Vector2 = controls[control]
			_check(not rect.intersects(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2)), "%s experience clears the %s touch control" % [resolution, control])
		if resolution.x == 844: await _save("mobile-growth")
	root.size = Vector2i(844, 390)
	var feedback := {"source": &"mission", "title": objective.title, "heal_on_claim": 1, "current_health": 3, "max_health": 5}
	context["objective_feedback"] = feedback
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	objective.status = &"completed"
	objective.target_active = false
	objective.progress = 12.0
	objective.completed = true
	map.set_active_objective(objective)
	nav.update_snapshot(navigation)
	await _settle()
	var completed := nav.get_navigation_snapshot()
	_check(completed.task_title.contains("任务完成") and completed.task_title.contains(objective.title) and completed.instruction_text.contains("领奖回复 1 格生命") and not completed.instruction_text.contains("已回复"), "completed task names its objective and promises healing only on claim")
	_check(completed.time_text == "待领奖" and nav._task_instruction.get_minimum_size().y <= nav._task_instruction.size.y + 1, "mobile completion guidance fits the existing two-line task panel")
	await _save("mobile-completion")
	context["objective_feedback"] = {}
	objective.id = &"next_flag"
	objective.title = "拆掉火力旗"
	objective.status = &"active"
	objective.kind = &"destroy_flag"
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	nav.update_snapshot(navigation)
	_check(not nav.get_navigation_snapshot().instruction_text.contains("领奖") and nav.get_navigation_snapshot().task_title.contains("拆掉火力旗"), "next task clears the previous completion feedback without a UI timer")
	context["objective_feedback"] = {"source": &"kill_level", "level": 3, "heal_on_claim": 1}
	ui.update_hud(player, {}, {}, "无尽挑战", "", {}, context)
	_check(nav.get_navigation_snapshot().task_title == "击破升级 · Lv.3" and nav.get_navigation_snapshot().time_text == "待强化" and nav.get_navigation_snapshot().objective_id == &"next_flag", "level-up preparation has its own message while preserving the active task")
	var choices: Array[Dictionary] = [FoldlightWeaponProgression.make_choice(&"crease_lantern", 2), FoldlightWeaponProgression.make_choice(&"needle_orbit", 0), FoldlightWeaponProgression.make_choice(&"tide_bell", 2)]
	ui.show_reward(choices, "守住潮汐信标", feedback)
	_check(ui._reward_title.text.contains("任务补给") and ui._reward_hint.text.contains("领奖回复 1 格生命") and not ui._reward_input_guard.can_select(), "mission reward source and pending heal remain visible during the original reading guard")
	_arm(ui._reward_input_guard)
	await _settle()
	_check(ui._reward_hint.get_minimum_size().y <= ui._reward_hint.size.y + 1, "mobile reward instruction including healing fits without squeezing cards")
	await _save("mobile-task-reward")
	ui.show_reward(choices, "击破成长", {"source": &"kill_level", "level": 3, "heal_on_claim": 1, "current_health": 3, "max_health": 5})
	_arm(ui._reward_input_guard)
	_check(ui._reward_title.text.contains("击破升级") and ui._reward_title.text.contains("Lv.3") and ui._reward_hint.text.contains("领奖回复"), "kill-level reward clearly differs from a task reward")
	await _save("mobile-kill-reward")
	ui.show_reward(choices, "击破成长", {"source": &"kill_level", "level": 6, "heal_on_claim": 1, "current_health": 5, "max_health": 5})
	_check(ui._reward_hint.text.contains("生命已满") and not ui._reward_hint.text.contains("回复 1"), "full health never advertises an actual gain")
	ui.show_reward(choices, "普通航路")
	_arm(ui._reward_input_guard)
	_check(not ui._reward_hint.text.contains("回复") and not ui._reward_title.text.contains("击破升级"), "legacy rogue reward clears previous endless source and healing metadata")
	ui.show_hud()
	ui.update_hud(player, {}, {}, "纸礁浅海")
	_check(not ui._hud_experience.visible and not ui._mobile_hud.experience.visible and ui._mobile_hud.status.visible, "leaving endless hides experience and restores the normal mobile pressure slot")
	ui.queue_free()
	player.queue_free()
	map.queue_free()
	camera.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	await process_frame
	print("ENDLESS_GROWTH_UI_3_16: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)

func _inside(rect: Rect2) -> bool:
	return Rect2(0, 0, 1921, 1081).encloses(rect)

func _arm(guard: Node) -> void:
	for step in 14: guard._process(0.1)

func _settle() -> void:
	for frame in 4: await process_frame

func _save(name: String) -> void:
	if not _captures: return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build/test-runtime/growth-ui-316")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func _check(value: bool, message: String) -> void:
	if value: print("PASS ", message)
	else:
		_failures += 1
		push_error("FAIL " + message)
