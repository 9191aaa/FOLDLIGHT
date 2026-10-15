class_name FoldlightEndlessHandcraftedMap
extends Node2D

const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const Seascape = preload("res://scripts/visuals/paper_seascape.gd")

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
var _ground_canvas: Node2D
var _static_draw_count: int = 0


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
	if not is_instance_valid(_ground_canvas):
		_ground_canvas = Node2D.new()
		_ground_canvas.name = "CachedPaperGround"
		_ground_canvas.show_behind_parent = true
		_ground_canvas.draw.connect(_draw_static_ground)
		add_child(_ground_canvas)
	_ground_canvas.queue_redraw()
	queue_redraw()
	return errors


func set_active_objective(snapshot: Dictionary) -> void:
	_active_objective = snapshot.duplicate(true)
	queue_redraw()


func get_map_contract() -> Dictionary:
	if map_definition == null:
		return {}
	var contract := map_definition.get_contract()
	contract["cached_ground"] = true
	contract["static_draw_count"] = _static_draw_count
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
	if map_definition != null:
		_draw_active_objective()


func _draw_static_ground() -> void:
	if map_definition == null or not is_instance_valid(_ground_canvas):
		return
	_static_draw_count += 1
	var canvas := _ground_canvas
	var bounds := map_definition.bounds
	Seascape.draw_region(canvas, bounds, &"paper_reef", 6144)
	var styles: Array[StringName] = [&"paper_reef", &"paper_reef", &"sun_court", &"paper_reef", &"ink_city", &"paper_reef"]
	for index in map_definition.district_rects.size():
		var district := map_definition.district_rects[index]
		var style := styles[index % styles.size()]
		Seascape.draw_district(canvas, district, style, 104 + index * 23)
		canvas.draw_string(ThemeDB.fallback_font, district.position + Vector2(68, 94), map_definition.district_names[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(PaperArt.PAPER, 0.24))
	# Narrow inlaid waymarks are pass-through floor marks, never raised walls.
	var hubs := map_definition.rally_positions
	for index in hubs.size():
		var a := hubs[index]
		var b := hubs[(index + 1) % hubs.size()]
		canvas.draw_line(a, b, Color(PaperArt.INK, 0.16), 36.0, true)
		canvas.draw_dashed_line(a, b, Color(PaperArt.GOLD, 0.12), 1.4, 23.0, true)
	var foundations: Array[Dictionary] = []
	for index in map_definition.walls.size():
		var wall := map_definition.walls[index]
		foundations.append({"kind": 0, "position": wall.get_center(), "size": wall.size})
		if draw_cover_visuals:
			_draw_cover(canvas, wall, index)
	Seascape.draw_foundations(canvas, foundations, &"paper_reef")
	for point in map_definition.capture_points:
		# A quiet engraved anchor; the active capture boundary is drawn separately.
		for side in 4:
			var direction := Vector2.from_angle(float(side) * PI * 0.5)
			var at := point + direction * 58.0
			var tangent := direction.orthogonal()
			canvas.draw_polyline(PackedVector2Array([at + tangent * 12, at + direction * 9, at - tangent * 12]), Color(PaperArt.FOLD, 0.26), 2.0, true)
		canvas.draw_circle(point, 6.0, Color(PaperArt.GOLD, 0.48))
	for index in map_definition.flag_positions.size():
		_draw_flag(canvas, map_definition.flag_positions[index], index)


func _draw_cover(canvas: CanvasItem, rect: Rect2, index: int) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(7, 9), rect.size), Color(PaperArt.INK, 0.62))
	var base := Color("354b49") if index % 3 != 1 else Color("46534d")
	canvas.draw_rect(rect, base)
	canvas.draw_rect(rect.grow(-5.0), Color(base.lightened(0.15), 0.66), false, 1.5)
	var vertical := rect.size.y > rect.size.x
	var length := rect.size.y if vertical else rect.size.x
	var units := maxi(1, int(length / 110.0))
	for unit in units:
		var u := (float(unit) + 0.5) / float(units)
		var center := rect.position + rect.size * (Vector2(0.5, u) if vertical else Vector2(u, 0.5))
		var delta := Vector2(rect.size.x * 0.35, length / float(units) * 0.28) if vertical else Vector2(length / float(units) * 0.28, rect.size.y * 0.35)
		canvas.draw_line(center - delta, center + delta, Color(PaperArt.PAPER, 0.19), 1.2, true)
		canvas.draw_line(center, center + Vector2(-delta.x, delta.y), Color(PaperArt.INK, 0.38), 2.0, true)


func _draw_flag(canvas: CanvasItem, position: Vector2, index: int) -> void:
	canvas.draw_line(position + Vector2(0, 48), position - Vector2(0, 60), Color(PaperArt.GOLD, 0.52), 3.0, true)
	var sway := 12.0 if index % 2 == 0 else -8.0
	canvas.draw_colored_polygon(PackedVector2Array([position - Vector2(0, 58), position + Vector2(68 + sway, -39), position + Vector2(14, -10)]), Color(PaperArt.DANGER, 0.42))


func _draw_active_objective() -> void:
	if _active_objective.is_empty() or bool(_active_objective.get("completed", false)) or bool(_active_objective.get("failed", false)):
		return
	var position := Vector2(_active_objective.get("target_position", Vector2.ZERO))
	var kind := StringName(_active_objective.get("kind", &""))
	var color := PaperArt.GOLD
	var radius := float(_active_objective.get("capture_radius", 170.0)) if kind == &"capture_point" else 94.0
	draw_circle(position, radius, Color(color, 0.08))
	draw_arc(position, radius, -PI * 0.5, PI * 1.5, 64, Color(color, 0.86), 3.5, true)
	draw_arc(position, radius + 21.0, 0.0, TAU, 48, Color(PaperArt.FOLD, 0.30), 1.5, true)
