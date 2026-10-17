extends SceneTree

const MapScene = preload("res://scripts/endless/endless_handcrafted_map.gd")
const Flag = preload("res://scripts/endless/endless_objective_target.gd")
const Definition = preload("res://resources/endless/maps/folded_delta.tres")
const Navigation = preload("res://scripts/endless/navigation_overlay.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	var map := MapScene.new()
	map.build_physics_walls = false
	root.add_child(map)
	map.configure(Definition)
	await process_frame
	await process_frame
	var draws := map._static_draw_count
	var capture := _objective(&"capture_point", 6.0, 12.0)
	capture["capture_radius"] = 170.0
	capture["occupied"] = true
	capture["return_charge_count"] = 5
	capture["return_boost_seconds"] = 2.0
	map.set_active_objective(capture)
	var visual := map.get_objective_visual_snapshot()
	_check(visual.occupied and visual.progress_ratio == 0.5 and visual.return_charge_count == 5 and visual.return_boost_seconds == 2.0, "lighthouse consumes authoritative progress, occupancy and returned-light state")
	_check(map.get_objective_marker_snapshot().radius == 170.0, "lighthouse preserves exact interaction radius")
	for frame in 12:
		map.advance_presentation(1.0 / 20.0)
		await process_frame
	_check(map._static_draw_count == draws, "animated facilities never invalidate cached ground")
	if DisplayServer.get_name() != "headless":
		var facility_draws := int(map.get_objective_visual_snapshot().draw_count)
		for frame in 60:
			# Countdown and player location change every simulation frame. They
			# must not bypass the actual renderer's twenty-Hz redraw cadence.
			capture["time_remaining"] = 90.0 - frame / 60.0
			capture["player_position"] = Vector2(900 + frame, 550)
			map.set_active_objective(capture)
			map.advance_presentation(1.0 / 60.0)
			await process_frame
		var facility_delta := int(map.get_objective_visual_snapshot().draw_count) - facility_draws
		_check(facility_delta > 0 and facility_delta <= 21, "real canvas redraw stays at twenty Hz with sixty changing snapshots")
	map.set_motion_reduced(true)
	var animation_time: float = map.get_objective_visual_snapshot().animation_time
	map.advance_presentation(0.3)
	_check(map.get_objective_visual_snapshot().animation_time == animation_time, "reduced motion freezes ambient rotation and bobbing")
	capture["completed"] = true
	capture["target_active"] = false
	capture["progress"] = 12.0
	capture["progress_ratio"] = 1.0
	map.set_active_objective(capture)
	_check(map.get_objective_marker_snapshot().is_empty() and map.get_objective_visual_snapshot().visible, "completed task drops gameplay marker while final paper fold remains visible")
	for frame in 8:
		await process_frame
	_check(map.get_objective_visual_snapshot().terminal_remaining == 0.5, "paused owner cannot advance completion through a timer or process callback")
	map.advance_presentation(0.2)
	map.set_active_objective(capture)
	_check(is_equal_approx(map.get_objective_visual_snapshot().terminal_remaining, 0.3), "repeated completed snapshots do not restart final animation")
	map.advance_presentation(0.31)
	_check(not map.get_objective_visual_snapshot().visible, "completion disappears after explicit half-second advancement even with reduced motion")
	var storm := _objective(&"capture_storm", 6.0, 12.0)
	storm["capture_radius"] = 240.0
	map.set_active_objective(storm)
	_check(map.get_objective_visual_snapshot().lit_petals == 6 and map.get_objective_marker_snapshot().radius == 240.0, "windmill lights exactly the six genuinely collected petals with unchanged radius")
	storm["progress"] = 12.0
	storm["progress_ratio"] = 1.0
	map.set_active_objective(storm)
	_check(map.get_objective_visual_snapshot().lit_petals == 12, "windmill has twelve bounded collection petals")
	var relay := _objective(&"relay_route", 1.0, 3.0)
	relay["capture_radius"] = 90.0
	relay["route_points"] = PackedVector2Array([Vector2(600, 500), Vector2(1000, 500), Vector2(1400, 500)])
	relay["waypoint_hold"] = 0.6
	map.set_active_objective(relay)
	_check(map.get_objective_visual_snapshot().facility_count == 3 and map.get_objective_marker_snapshot().radius == 90.0, "relay keeps three distinct authored buoys and its exact current radius")
	var swarm := _objective(&"clear_swarm", 0.0, 10.0)
	swarm["target_active"] = false
	swarm["player_position"] = Vector2(700, 600)
	map.set_active_objective(swarm)
	_check(map.get_objective_marker_snapshot().is_empty() and not map.get_objective_visual_snapshot().visible and map.get_objective_visual_snapshot().facility_count == 0, "elimination has no fabricated world destination or idle effect")
	swarm["progress"] = 3.0
	swarm["progress_ratio"] = 0.3
	map.set_active_objective(swarm)
	_check(map.get_objective_visual_snapshot().kill_marks == 3 and map.get_objective_visual_snapshot().visible, "real elimination count briefly lights local player marks")
	map.advance_presentation(0.3)
	map.set_active_objective(swarm)
	map.advance_presentation(0.21)
	_check(not map.get_objective_visual_snapshot().visible, "unchanged elimination snapshot cannot perpetuate local feedback")
	var flag := Flag.new()
	root.add_child(flag)
	flag.configure(_objective(&"destroy_flag", 0.0, 60.0))
	flag.set_simulation_active(true)
	_check(flag.get_art_snapshot().damage_stage == 0, "undamaged fire flag starts with intact paper armour")
	flag.take_damage(20.0)
	_check(flag.get_art_snapshot().damage_stage == 1 and flag.health == 40, "first cracks track real combat damage")
	flag.take_damage(27.0)
	_check(flag.get_art_snapshot().damage_stage == 3 and flag.health == 13, "torn banner and missing armour track low health")
	var collision := flag.get_node("CollisionShape2D") as CollisionShape2D
	_check((collision.shape as CircleShape2D).radius == 42.0 and flag.get_art_snapshot().collision_radius == 42.0, "new paper silhouette does not change objective hitbox")
	flag.configure(_objective(&"destroy_flag", 0.0, 60.0))
	_check(flag.get_art_snapshot().damage_stage == 0 and flag.get_hit_feedback_snapshot().flash == 0.0, "reused flag configuration clears old cracks and hit flash")
	map.set_active_objective(capture)
	map.configure(Definition)
	_check(map.get_objective_marker_snapshot().is_empty() and not map.get_objective_visual_snapshot().visible, "reconfigure clears previous task and lingering visuals")
	map.configure(null)
	_check(not map.get_objective_visual_snapshot().visible, "null configuration cannot retain a stale facility")
	flag.queue_free()
	map.queue_free()
	await process_frame
	await _check_mobile_task_layout()
	root.get_node("AudioDirector").shutdown()
	await process_frame
	print("ENDLESS_OBJECTIVE_FACILITIES: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _check_mobile_task_layout() -> void:
	root.size = Vector2i(844, 390)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var nav := Navigation.new()
	root.add_child(nav)
	nav.set_touch_layout(true, 150.0)
	var names := {&"capture_point": "守住潮汐信标", &"capture_storm": "收集风暴之光", &"relay_route": "连通信标航线", &"destroy_flag": "拆掉火力旗", &"defeat_captain": "击破敌方队长", &"clear_swarm": "清剿纸潮"}
	for kind in names:
		var task := _objective(kind, 6.0, 12.0)
		task["title"] = names[kind]
		task["status"] = &"active"
		task["progress_text"] = "6.0 / 12 秒 · 返光助燃 +6 秒"
		task["time_remaining"] = 90.0
		task["waypoint_hold"] = 1.1
		nav.update_snapshot({"bounds": Definition.bounds, "map_id": Definition.map_id, "map_title": Definition.title, "player_position": Definition.player_spawn, "objective": task, "zones": [], "danger": {"state": &"safe"}})
		await process_frame
		var title_width := nav._task_title.get_theme_font("font").get_string_size(nav._task_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nav._task_title.get_theme_font_size("font_size")).x
		_check(title_width <= nav._task_title.size.x and not nav._task_title.get_rect().intersects(nav._task_time.get_rect()), "%s phone task title and compact count fit before countdown" % kind)
		_check(not nav._task_progress.visible and nav.get_navigation_snapshot().progress_text == task.progress_text and nav._task.size.y == 112.0, "two-line phone layout preserves full director progress in its shared snapshot")
		if kind == &"capture_point":
			_check(nav._task_instruction.text.contains("返4弹") and nav._task_instruction.text.contains("最多6秒"), "mobile beacon guidance explains returned-light ignition and its cap")
	nav.set_touch_layout(false)
	_check(nav._task_progress.visible and nav._task.size.y == 194.0, "desktop task layout keeps its original full progress row")
	nav.queue_free()
	await process_frame


func _objective(kind: StringName, progress: float, required: float) -> Dictionary:
	return {"id": kind, "target_id": kind, "kind": kind, "target_position": Vector2(960, 540), "target_active": true, "progress": progress, "required": required, "progress_ratio": progress / required, "completed": false, "failed": false}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		_failures += 1
		push_error("FAIL " + message)
