extends SceneTree

const Runtime = preload("res://scripts/endless/endless_handcrafted_map.gd")
const Director = preload("res://scripts/endless/endless_zone_director.gd")
const MAP_PATHS := ["res://resources/endless/maps/folded_delta.tres", "res://resources/endless/maps/inverted_canals.tres", "res://resources/endless/maps/solar_archipelago.tres"]
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layouts: Dictionary = {}
	for path in MAP_PATHS:
		var definition: FoldlightEndlessMapDefinition = load(path)
		var map := Runtime.new()
		map.build_physics_walls = false
		root.add_child(map)
		var errors: Array[String] = map.configure(definition)
		_check(errors.is_empty(), "%s validates: %s" % [definition.title, errors])
		layouts[definition.map_id] = definition.walls
		var all_points := PackedVector2Array([definition.player_spawn])
		for points in [definition.capture_points, definition.flag_positions, definition.captain_spawn_positions, definition.shooter_spawn_positions, definition.melee_spawn_positions, definition.rally_positions, definition.refuge_points]:
			all_points.append_array(points)
		var blocked: Array[String] = []
		var unreachable: Array[String] = []
		for point in all_points:
			if map.is_point_blocked(point, 34.0):
				blocked.append(str(point))
			var route: PackedVector2Array = map.find_cover_route(point, definition.player_spawn)
			if route.is_empty() or not _route_clear(map, point, route):
				unreachable.append(str(point))
		_check(blocked.is_empty(), "%s every authored spawn, task and refuge clears real walls: %s" % [definition.title, blocked])
		_check(unreachable.is_empty(), "%s every authored site reaches the permanent starting harbor: %s" % [definition.title, unreachable])
		var director := Director.new()
		director.reset(definition, 901)
		map.set_zone_snapshot(director.advance_to(210.0))
		var refuges_safe := true
		for point in definition.refuge_points:
			refuges_safe = refuges_safe and definition.is_permanent_safe(point, 34.0) and not director.is_point_closed(point)
		_check(refuges_safe, "%s retains all reachable permanent refuges during late two-zone closure" % definition.title)
		var escape_failures: Array[String] = []
		for rect in definition.closure_zone_rects:
			for fraction in [Vector2(0.18, 0.18), Vector2(0.5, 0.5), Vector2(0.82, 0.82)]:
				var point: Vector2 = rect.position + rect.size * fraction
				if map.is_point_blocked(point, 60.0):
					continue
				var waypoint: Vector2 = director.get_nearest_safe_position(point, map)
				if point.is_equal_approx(waypoint) or not map.has_line_of_sight(point, waypoint, 13.0):
					escape_failures.append(str(point))
		_check(escape_failures.is_empty(), "%s evacuation guidance starts with a real wall-clear segment: %s" % [definition.title, escape_failures])
		# Navigate an actual multi-corner escape using only the API exposed to HUD.
		var origin := Vector2(300, 1080) if definition.map_id == &"folded_delta" else Vector2(900, 1120)
		var cursor := origin
		var complete := false
		for step in 40:
			if definition.is_permanent_safe(cursor, 13.0):
				complete = true
				break
			var waypoint: Vector2 = map.get_nearest_safe_position(cursor)
			if waypoint.is_equal_approx(cursor) or not map.has_line_of_sight(cursor, waypoint, 13.0):
				break
			cursor = waypoint
		_check(complete, "%s following evacuation waypoints reaches permanent safe water" % definition.title)
		# The moth can stand closer to a wall than the projectile-routing margin.
		# Escape guidance must remain valid at its real collision radius.
		var cover: Rect2 = definition.walls[0]
		var hugging := Vector2(cover.position.x - 15.0, cover.get_center().y)
		var first_step: Vector2 = map.get_nearest_safe_position(hugging, 13.0)
		_check(not map.is_point_blocked(hugging, 13.0) and map.is_point_blocked(hugging, 34.0) and not first_step.is_equal_approx(hugging) and map.has_line_of_sight(hugging, first_step, 13.0), "%s wall-hugging player receives a reachable evacuation step at the real radius" % definition.title)
		var larger_body := Vector2(cover.position.x - 23.0, cover.get_center().y)
		var larger_step: Vector2 = map.get_nearest_safe_position(larger_body, 21.0)
		_check(not larger_step.is_equal_approx(larger_body) and map.has_line_of_sight(larger_body, larger_step, 21.0), "%s evacuation cache respects a changed player collision radius" % definition.title)
		await process_frame
		var ground_draws: int = map.get_map_contract().static_draw_count
		for frame in 4:
			map.set_zone_snapshot(director.advance_to(210.1 + frame * 0.1))
			await process_frame
		_check(map.get_map_contract().static_draw_count == ground_draws, "%s countdown updates keep the static paper ground cached" % definition.title)
		_check(map.get_node_or_null("AuthoredCoverCollision") == null, "%s closure paint never adds parallel or invisible collision" % definition.title)
		map.set_active_objective({"kind": &"capture_storm", "target_active": true, "target_position": definition.capture_points[0], "capture_radius": 240.0})
		var marker: Dictionary = map.get_objective_marker_snapshot()
		_check(is_equal_approx(float(marker.radius), 240.0) and marker.color == FoldlightTheme.FOLD, "%s storm marker uses the real 240 radius and cyan collection color" % definition.title)
		map.set_active_objective({"kind": &"relay_route", "target_active": true, "target_position": definition.rally_positions[0], "capture_radius": 90.0})
		_check(is_equal_approx(float(map.get_objective_marker_snapshot().radius), 90.0), "%s relay marker uses the real 90 radius" % definition.title)
		map.set_active_objective({"kind": &"clear_swarm", "target_active": false, "target_position": definition.player_spawn})
		_check(map.get_objective_marker_snapshot().is_empty(), "%s nonspatial elimination task does not paint a misleading destination" % definition.title)
		map.queue_free()
		await process_frame
	_check(layouts.size() == 3 and layouts.values()[0] != layouts.values()[1] and layouts.values()[1] != layouts.values()[2], "three map ids have separately authored cover layouts")
	print("FOLDLIGHT_ENDLESS_MAP_VARIANTS: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _route_clear(map: FoldlightEndlessHandcraftedMap, origin: Vector2, route: PackedVector2Array) -> bool:
	var cursor := origin
	for waypoint in route:
		if map.is_point_blocked(waypoint, 34.0) or not map.has_line_of_sight(cursor, waypoint, 34.0):
			return false
		cursor = waypoint
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
