class_name FoldlightRogueVisualCanvas
extends Control

var screen_kind: StringName = &"title"
var accent: Color = FoldlightRogueUITheme.FOLD
var route_snapshot: Dictionary = {}
var current_node_id: StringName = &""
var _time: float = 0.0
var _damage_flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_damage_flash = maxf(0.0, _damage_flash - maxf(0.0, delta) * 4.8)
	queue_redraw()


func configure(kind: StringName, new_accent: Color = FoldlightRogueUITheme.FOLD) -> void:
	screen_kind = kind
	accent = FoldlightRogueUITheme.comfort_accent(new_accent)
	queue_redraw()


func flash_player_damage() -> void:
	_damage_flash = 1.0
	queue_redraw()


func get_damage_flash_strength() -> float:
	return _damage_flash


func configure_route(region_snapshot: Dictionary, selected_node_id: StringName) -> void:
	route_snapshot = region_snapshot.duplicate(true)
	current_node_id = selected_node_id
	queue_redraw()


func _draw() -> void:
	var viewport_size := size
	if screen_kind in [&"title", &"result", &"prologue_result"]:
		_draw_full_bleed(viewport_size)
	elif screen_kind in [&"reward", &"route", &"pause", &"mechanic_intro"]:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.006, 0.013, 0.032, 0.88), true)
		_draw_edge_folds(viewport_size, 0.34)
	else:
		_draw_hud_frame(viewport_size)
	if screen_kind == &"route":
		_draw_route(viewport_size)
	if _damage_flash > 0.0:
		_draw_damage_flash(viewport_size)


func _draw_damage_flash(viewport_size: Vector2) -> void:
	# A short edge-weighted red response keeps the playfield readable while the
	# entire screen still registers the hit immediately.
	var strength := _damage_flash * _damage_flash
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.55, 0.035, 0.025, 0.035 * strength), true)
	for inset in 6:
		var margin := float(inset) * 14.0
		var alpha := strength * (0.13 - float(inset) * 0.016)
		draw_rect(Rect2(Vector2(margin, margin), viewport_size - Vector2.ONE * margin * 2.0), Color(0.82, 0.08, 0.045, maxf(0.0, alpha)), false, 12.0, true)


func _draw_full_bleed(viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.008, 0.016, 0.043, 1.0), true)
	for band in 12:
		var y := viewport_size.y * (0.05 + float(band) * 0.085)
		var points := PackedVector2Array()
		for segment in 33:
			var x := viewport_size.x * float(segment) / 32.0
			var wave := sin(float(segment) * 0.51 + float(band) * 1.37 + _time * (0.10 + band * 0.007)) * (10.0 + float(band % 4) * 6.0)
			points.append(Vector2(x, y + wave))
		draw_polyline(points, Color(accent.r, accent.g, accent.b, 0.035 + float(band % 3) * 0.012), 2.0, true)
	var fold_a := PackedVector2Array([
		Vector2(viewport_size.x * 0.54, -40.0),
		Vector2(viewport_size.x * 0.72, viewport_size.y * 0.42),
		Vector2(viewport_size.x * 0.61, viewport_size.y + 40.0),
	])
	draw_polyline(fold_a, Color(accent.r, accent.g, accent.b, 0.34), 3.0, true)
	draw_polyline(fold_a, Color(accent.r, accent.g, accent.b, 0.07), 22.0, true)
	var moth_center := Vector2(viewport_size.x * 0.33, viewport_size.y * 0.49)
	for ring in range(8, 0, -1):
		draw_circle(moth_center, 72.0 + float(ring) * 28.0, Color(accent.r, accent.g, accent.b, 0.008 * float(9 - ring)))
	for wing in [-1.0, 1.0]:
		var flap := 0.34 + sin(_time * 1.4) * 0.045
		var angle: float = float(wing) * (1.02 + flap)
		var center := moth_center + Vector2.from_angle(angle) * 76.0
		var shape := _diamond(center, angle, 118.0, 48.0)
		draw_colored_polygon(shape, Color(0.035, 0.13, 0.14, 0.92))
		draw_polyline(_closed(shape), Color(accent.r, accent.g, accent.b, 0.75), 3.0, true)
	draw_circle(moth_center, 28.0, Color(0.04, 0.20, 0.19, 1.0))
	draw_circle(moth_center, 7.0, FoldlightRogueUITheme.GOLD)
	_draw_edge_folds(viewport_size, 0.28)


func _draw_edge_folds(viewport_size: Vector2, alpha: float) -> void:
	draw_line(Vector2(0, 78), Vector2(viewport_size.x * 0.40, 0), Color(accent.r, accent.g, accent.b, alpha), 2.0, true)
	draw_line(Vector2(viewport_size.x, viewport_size.y - 96), Vector2(viewport_size.x * 0.63, viewport_size.y), Color(accent.r, accent.g, accent.b, alpha), 2.0, true)
	draw_circle(Vector2(viewport_size.x - 72, 72), 7.0 + sin(_time * 2.0) * 2.0, Color(accent.r, accent.g, accent.b, 0.65))


func _draw_hud_frame(viewport_size: Vector2) -> void:
	var color := Color(accent.r, accent.g, accent.b, 0.38)
	draw_line(Vector2(34, 34), Vector2(360, 34), color, 2.0, true)
	draw_line(Vector2(34, 34), Vector2(34, 130), color, 2.0, true)
	draw_line(Vector2(viewport_size.x - 34, viewport_size.y - 34), Vector2(viewport_size.x - 390, viewport_size.y - 34), color, 2.0, true)
	draw_line(Vector2(viewport_size.x - 34, viewport_size.y - 34), Vector2(viewport_size.x - 34, viewport_size.y - 132), color, 2.0, true)


func _draw_route(viewport_size: Vector2) -> void:
	var nodes_variant: Variant = route_snapshot.get("nodes", [])
	if not nodes_variant is Array:
		return
	var nodes := nodes_variant as Array
	if nodes.is_empty():
		return
	var max_depth := 1
	var by_id: Dictionary = {}
	for node_variant: Variant in nodes:
		if node_variant is Dictionary:
			var node := node_variant as Dictionary
			max_depth = maxi(max_depth, int(node.get("depth", 0)))
			by_id[String(node.get("id", ""))] = node
	var map_rect := Rect2(viewport_size.x * 0.13, viewport_size.y * 0.24, viewport_size.x * 0.74, viewport_size.y * 0.43)
	for node_variant: Variant in nodes:
		if not node_variant is Dictionary:
			continue
		var node := node_variant as Dictionary
		var from_pos := _route_node_position(node, nodes, map_rect, max_depth)
		for exit_variant: Variant in node.get("exits", []):
			var destination: Dictionary = by_id.get(String(exit_variant), {})
			if destination.is_empty():
				continue
			var to_pos := _route_node_position(destination, nodes, map_rect, max_depth)
			var visited := StringName(node.get("id", &"")) == current_node_id or int(node.get("depth", 0)) < int(_current_depth(nodes))
			draw_line(from_pos, to_pos, Color(accent.r, accent.g, accent.b, 0.46 if visited else 0.13), 4.0 if visited else 2.0, true)
	for node_variant: Variant in nodes:
		if not node_variant is Dictionary:
			continue
		var node := node_variant as Dictionary
		var node_pos := _route_node_position(node, nodes, map_rect, max_depth)
		var category := StringName(node.get("category", &"combat"))
		var radius := 22.0 if category != &"boss" else 34.0
		var is_current := StringName(node.get("id", &"")) == current_node_id
		var node_color := FoldlightRogueUITheme.GOLD if category == &"boss" else accent
		if is_current:
			draw_circle(node_pos, radius + 10.0 + sin(_time * 3.0) * 3.0, Color(node_color.r, node_color.g, node_color.b, 0.14))
		draw_circle(node_pos, radius, Color(0.018, 0.045, 0.078, 0.98))
		draw_circle(node_pos, radius, Color(node_color.r, node_color.g, node_color.b, 0.86 if is_current else 0.46), false, 3.0, true)
		_draw_category_mark(node_pos, category, node_color)


func _route_node_position(node: Dictionary, nodes: Array, map_rect: Rect2, max_depth: int) -> Vector2:
	var depth := int(node.get("depth", 0))
	var same_depth: Array[Dictionary] = []
	for candidate_variant: Variant in nodes:
		if candidate_variant is Dictionary and int((candidate_variant as Dictionary).get("depth", 0)) == depth:
			same_depth.append(candidate_variant as Dictionary)
	same_depth.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	var branch_index := same_depth.find(node)
	var branch_y := 0.5 if same_depth.size() <= 1 else lerpf(0.26, 0.74, float(branch_index) / float(same_depth.size() - 1))
	return Vector2(map_rect.position.x + map_rect.size.x * float(depth) / float(max_depth), map_rect.position.y + map_rect.size.y * branch_y)


func _current_depth(nodes: Array) -> int:
	for node_variant: Variant in nodes:
		if node_variant is Dictionary and StringName((node_variant as Dictionary).get("id", &"")) == current_node_id:
			return int((node_variant as Dictionary).get("depth", 0))
	return 0


func _draw_category_mark(center: Vector2, category: StringName, color: Color) -> void:
	match category:
		&"boss":
			for spoke in 6:
				var angle := float(spoke) * TAU / 6.0
				draw_line(center + Vector2.from_angle(angle) * 8.0, center + Vector2.from_angle(angle) * 21.0, color, 2.0, true)
		&"rest":
			draw_arc(center, 11.0, -PI * 0.75, PI * 0.75, 18, color, 3.0, true)
		&"shop", &"forge":
			draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), color, false, 3.0, true)
		&"cache", &"event":
			draw_colored_polygon(_diamond(center, 0.0, 12.0, 8.0), color)
		_:
			draw_circle(center, 7.0, color)


func _diamond(center: Vector2, angle: float, length: float, width: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle)
	var side := forward.rotated(PI * 0.5)
	return PackedVector2Array([center + forward * length, center + side * width, center - forward * length, center - side * width])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result
