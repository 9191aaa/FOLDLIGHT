class_name FoldlightEndlessHandcraftedMap
extends Node2D

const WALL_COLLISION_LAYER := 1
const WALL_COLLISION_MASK := 0
const COVER_CLEARANCE := 34.0
const ROUTE_CELL_SIZE := 96.0

@export var map_definition: FoldlightEndlessMapDefinition
@export var build_physics_walls: bool = true
@export var draw_cover_visuals: bool = true

var _active_objective: Dictionary = {}
var _wall_container: Node2D
var _route_grid: AStarGrid2D


func _ready() -> void:
	z_index = -20
	if map_definition != null:
		configure(map_definition)


func configure(definition: FoldlightEndlessMapDefinition) -> Array[String]:
	map_definition = definition
	var errors: Array[String] = []
	if map_definition == null:
		errors.append("handcrafted endless map definition is missing")
		return errors
	errors.assign(map_definition.validation_errors())
	_rebuild_route_grid()
	if build_physics_walls:
		_rebuild_wall_bodies()
	elif _wall_container != null and is_instance_valid(_wall_container):
		remove_child(_wall_container)
		_wall_container.queue_free()
		_wall_container = null
	queue_redraw()
	return errors


func set_active_objective(snapshot: Dictionary) -> void:
	_active_objective = snapshot.duplicate(true)
	queue_redraw()


func get_map_contract() -> Dictionary:
	if map_definition == null:
		return {}
	var contract := map_definition.get_contract()
	contract["cover_routing"] = true
	contract["fixed_objective_sites"] = true
	contract["fixed_spawn_sites"] = true
	return contract


func has_line_of_sight(from: Vector2, to: Vector2, clearance: float = 4.0) -> bool:
	if map_definition == null:
		return true
	for wall in map_definition.walls:
		if _segment_hits_rect(from, to, wall.grow(clearance)):
			return false
	return true


func is_point_blocked(point: Vector2, clearance: float = 0.0) -> bool:
	if map_definition == null:
		return false
	if not map_definition.bounds.grow(-clearance).has_point(point):
		return true
	for wall in map_definition.walls:
		if wall.grow(clearance).has_point(point):
			return true
	return false


func find_cover_route(from: Vector2, to: Vector2, clearance: float = COVER_CLEARANCE) -> PackedVector2Array:
	var route := PackedVector2Array()
	if map_definition == null or has_line_of_sight(from, to, clearance):
		route.append(to)
		return route
	if _route_grid == null:
		return PackedVector2Array()
	var start_cell := _nearest_walkable_cell(_world_to_route_cell(from))
	var target_cell := _nearest_walkable_cell(_world_to_route_cell(to))
	if start_cell == Vector2i(-1, -1) or target_cell == Vector2i(-1, -1):
		return PackedVector2Array()
	var cell_path := _route_grid.get_id_path(start_cell, target_cell)
	if cell_path.is_empty():
		return PackedVector2Array()
	var candidates := PackedVector2Array()
	for cell in cell_path:
		candidates.append(_route_grid.get_point_position(cell))
	candidates.append(to)
	var cursor := from
	var candidate_index := 0
	while candidate_index < candidates.size():
		var farthest_visible := -1
		for search_index in range(candidates.size() - 1, candidate_index - 1, -1):
			if has_line_of_sight(cursor, candidates[search_index], clearance):
				farthest_visible = search_index
				break
		if farthest_visible < 0:
			return PackedVector2Array()
		var waypoint := candidates[farthest_visible]
		if cursor.distance_squared_to(waypoint) > 4.0:
			route.append(waypoint)
		cursor = waypoint
		candidate_index = farthest_visible + 1
	if route.is_empty() or not route[route.size() - 1].is_equal_approx(to):
		return PackedVector2Array()
	return route


func select_spawn_point(role: StringName, sequence: int, player_position: Vector2) -> Vector2:
	if map_definition == null:
		return Vector2.ZERO
	var positions := map_definition.shooter_spawn_positions if role == &"shooter" else map_definition.melee_spawn_positions
	if positions.is_empty():
		return map_definition.player_spawn
	for offset in positions.size():
		var index := posmod(sequence * 3 + offset, positions.size())
		var candidate := positions[index]
		if candidate.distance_to(player_position) >= 620.0 and not is_point_blocked(candidate, 40.0):
			return candidate
	return positions[posmod(sequence, positions.size())]


func objective_position(kind: StringName, sequence: int) -> Vector2:
	if map_definition == null:
		return Vector2.ZERO
	var points := map_definition.capture_points
	match kind:
		&"defeat_captain":
			points = map_definition.captain_spawn_positions
		&"destroy_flag":
			points = map_definition.flag_positions
	if points.is_empty():
		return map_definition.player_spawn
	return points[posmod(sequence, points.size())]


func _rebuild_wall_bodies() -> void:
	if _wall_container != null and is_instance_valid(_wall_container):
		remove_child(_wall_container)
		_wall_container.queue_free()
	_wall_container = Node2D.new()
	_wall_container.name = "AuthoredCoverCollision"
	add_child(_wall_container)
	for index in map_definition.walls.size():
		var wall := map_definition.walls[index]
		var body := StaticBody2D.new()
		body.name = "Cover_%02d" % index
		body.position = wall.get_center()
		body.collision_layer = WALL_COLLISION_LAYER
		body.collision_mask = WALL_COLLISION_MASK
		body.set_meta(&"endless_cover", true)
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = wall.size
		collision.shape = shape
		body.add_child(collision)
		_wall_container.add_child(body)
	_build_boundary_body()


func _build_boundary_body() -> void:
	var bounds := map_definition.bounds
	var thickness := 96.0
	var boundary_rects: Array[Rect2] = [
		Rect2(bounds.position - Vector2(thickness, thickness), Vector2(bounds.size.x + thickness * 2.0, thickness)),
		Rect2(Vector2(bounds.position.x - thickness, bounds.end.y), Vector2(bounds.size.x + thickness * 2.0, thickness)),
		Rect2(bounds.position - Vector2(thickness, 0.0), Vector2(thickness, bounds.size.y)),
		Rect2(Vector2(bounds.end.x, bounds.position.y), Vector2(thickness, bounds.size.y)),
	]
	for index in boundary_rects.size():
		var rect := boundary_rects[index]
		var body := StaticBody2D.new()
		body.name = "Boundary_%d" % index
		body.position = rect.get_center()
		body.collision_layer = WALL_COLLISION_LAYER
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		body.add_child(collision)
		_wall_container.add_child(body)


func _rebuild_route_grid() -> void:
	_route_grid = AStarGrid2D.new()
	var grid_size := Vector2i(
		int(ceil(map_definition.bounds.size.x / ROUTE_CELL_SIZE)),
		int(ceil(map_definition.bounds.size.y / ROUTE_CELL_SIZE))
	)
	_route_grid.region = Rect2i(Vector2i.ZERO, grid_size)
	_route_grid.cell_size = Vector2.ONE * ROUTE_CELL_SIZE
	_route_grid.offset = map_definition.bounds.position + Vector2.ONE * ROUTE_CELL_SIZE * 0.5
	_route_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_route_grid.update()
	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var center := _route_grid.get_point_position(cell)
			for wall in map_definition.walls:
				if wall.grow(COVER_CLEARANCE + ROUTE_CELL_SIZE * 0.28).has_point(center):
					_route_grid.set_point_solid(cell, true)
					break


func _world_to_route_cell(point: Vector2) -> Vector2i:
	var local := point - map_definition.bounds.position
	return Vector2i(
		clampi(int(floor(local.x / ROUTE_CELL_SIZE)), 0, _route_grid.region.size.x - 1),
		clampi(int(floor(local.y / ROUTE_CELL_SIZE)), 0, _route_grid.region.size.y - 1)
	)


func _nearest_walkable_cell(origin: Vector2i) -> Vector2i:
	if _route_grid.is_in_boundsv(origin) and not _route_grid.is_point_solid(origin):
		return origin
	for radius in range(1, 8):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if abs(x - origin.x) != radius and abs(y - origin.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if _route_grid.is_in_boundsv(candidate) and not _route_grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	for index in 4:
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false


func _draw() -> void:
	if map_definition == null:
		return
	var bounds := map_definition.bounds
	draw_rect(bounds, Color("071920"), true)
	_draw_water_grid(bounds)
	for index in map_definition.district_rects.size():
		var district := map_definition.district_rects[index]
		var color := map_definition.district_colors[index]
		draw_rect(district, color, true)
		draw_rect(district.grow(-12.0), color.lightened(0.08), false, 5.0)
		draw_string(ThemeDB.fallback_font, district.position + Vector2(42.0, 70.0), map_definition.district_names[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(0.84, 0.91, 0.84, 0.5))
	_draw_authored_paths()
	if draw_cover_visuals:
		for index in map_definition.walls.size():
			_draw_cover(map_definition.walls[index], index)
	for index in map_definition.capture_points.size():
		var point := map_definition.capture_points[index]
		draw_circle(point, 84.0, Color(0.15, 0.50, 0.49, 0.12))
		draw_arc(point, 84.0, 0.0, TAU, 48, Color(0.43, 0.78, 0.69, 0.62), 5.0, true)
		draw_circle(point, 13.0, Color(0.87, 0.72, 0.34, 0.86))
	for index in map_definition.flag_positions.size():
		_draw_flag(map_definition.flag_positions[index], index)
	_draw_active_objective()
	draw_rect(bounds, Color(0.50, 0.75, 0.69, 0.48), false, 12.0)


func _draw_water_grid(bounds: Rect2) -> void:
	for x in range(128, int(bounds.size.x), 256):
		var alpha := 0.035 if int(x / 256) % 2 == 0 else 0.022
		draw_line(Vector2(x, 0.0), Vector2(x - 320.0, bounds.size.y), Color(0.31, 0.68, 0.68, alpha), 3.0)
	for y in range(192, int(bounds.size.y), 320):
		draw_line(Vector2(0.0, y), Vector2(bounds.size.x, y + 110.0), Color(0.78, 0.72, 0.51, 0.026), 4.0)


func _draw_authored_paths() -> void:
	var hubs := map_definition.rally_positions
	if hubs.size() < 2:
		return
	for index in hubs.size():
		var a := hubs[index]
		var b := hubs[(index + 1) % hubs.size()]
		draw_line(a, b, Color(0.39, 0.62, 0.57, 0.12), 76.0, true)
		draw_line(a, b, Color(0.80, 0.70, 0.42, 0.18), 5.0, true)


func _draw_cover(rect: Rect2, index: int) -> void:
	draw_rect(Rect2(rect.position + Vector2(15.0, 19.0), rect.size), Color(0.01, 0.05, 0.06, 0.42), true)
	var base := Color("173b3a") if index % 3 != 1 else Color("3f4a3b")
	draw_rect(rect, base, true)
	draw_rect(rect.grow(-8.0), base.lightened(0.16), false, 5.0)
	var ridge_y := rect.position.y + rect.size.y * 0.34
	draw_line(Vector2(rect.position.x + 12.0, ridge_y), Vector2(rect.end.x - 12.0, ridge_y + 6.0), Color(0.76, 0.70, 0.45, 0.26), 4.0, true)
	for notch in range(1, maxi(2, int(rect.size.x / 120.0))):
		var px := rect.position.x + rect.size.x * float(notch) / float(maxi(2, int(rect.size.x / 120.0)))
		draw_line(Vector2(px, rect.position.y + 10.0), Vector2(px - 18.0, rect.end.y - 10.0), Color(0.04, 0.15, 0.16, 0.38), 3.0)


func _draw_flag(position: Vector2, index: int) -> void:
	draw_line(position + Vector2(0.0, 48.0), position - Vector2(0.0, 60.0), Color(0.79, 0.69, 0.40, 0.52), 7.0, true)
	var sway := 12.0 if index % 2 == 0 else -8.0
	draw_colored_polygon(PackedVector2Array([
		position - Vector2(0.0, 58.0),
		position + Vector2(68.0 + sway, -39.0),
		position + Vector2(14.0, -10.0),
	]), Color(0.72, 0.29, 0.22, 0.42))


func _draw_active_objective() -> void:
	if _active_objective.is_empty() or bool(_active_objective.get("completed", false)) or bool(_active_objective.get("failed", false)):
		return
	var position := Vector2(_active_objective.get("target_position", Vector2.ZERO))
	var kind := StringName(_active_objective.get("kind", &""))
	var color := Color("efc45c")
	var radius := 122.0 if kind == &"capture_point" else 94.0
	draw_circle(position, radius, Color(color, 0.08))
	draw_arc(position, radius, -PI * 0.5, PI * 1.5, 64, Color(color, 0.82), 8.0, true)
	draw_arc(position, radius + 21.0, 0.0, TAU, 48, Color(0.37, 0.79, 0.72, 0.38), 3.0, true)
