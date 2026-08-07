class_name FoldlightTerrainPiece
extends Node2D

signal terrain_effect_entered(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D, strength: float, direction: Vector2)
signal terrain_effect_exited(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D)

var placement_id: StringName = &""
var kind: FoldlightRogueTerrainDefinition.TerrainKind = FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL
var piece_size: Vector2 = Vector2(200.0, 80.0)
var effect_strength: float = 1.0
var effect_direction: Vector2 = Vector2.RIGHT
var visual_style: StringName = &"paper_reef"
var _collision_object: CollisionObject2D
var _collision_shape: CollisionShape2D
var _visual_time: float = 0.0


func _process(delta: float) -> void:
	if kind in [FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER]:
		_visual_time += delta
		queue_redraw()


func configure(placement: Dictionary) -> void:
	placement_id = StringName(placement.get("id", &"terrain"))
	kind = int(placement.get("kind", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL))
	position = Vector2(placement.get("position", Vector2.ZERO))
	rotation = float(placement.get("rotation", 0.0))
	piece_size = Vector2(placement.get("size", Vector2(200.0, 80.0))).abs()
	effect_strength = maxf(0.0, float(placement.get("strength", 1.0)))
	effect_direction = Vector2(placement.get("direction", Vector2.RIGHT)).normalized()
	visual_style = StringName(placement.get("visual_style", &"paper_reef"))
	if effect_direction.is_zero_approx():
		effect_direction = Vector2.RIGHT
	_build_collision()
	queue_redraw()


func get_collision_object() -> CollisionObject2D:
	return _collision_object


func get_collision_shape() -> CollisionShape2D:
	return _collision_shape


func get_visual_signature() -> Dictionary:
	var motif: StringName = StringName({
		&"paper_reef": &"sea_glass_reef",
		&"ink_city": &"lacquer_seal_architecture",
		&"sun_court": &"ceremonial_sun_mosaic",
	}.get(visual_style, &"sea_glass_reef"))
	return {"style": visual_style, "motif": motif, "kind": kind, "collision_size": piece_size}


func get_world_bounds(extra_margin: float = 0.0) -> Rect2:
	var c := absf(cos(rotation))
	var s := absf(sin(rotation))
	var rotated_size := Vector2(piece_size.x * c + piece_size.y * s, piece_size.x * s + piece_size.y * c)
	return Rect2(position - rotated_size * 0.5, rotated_size).grow(extra_margin)


func contains_world_point(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	if kind == FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR:
		return local_point.length() <= minf(piece_size.x, piece_size.y) * 0.5
	return Rect2(-piece_size * 0.5, piece_size).has_point(local_point)


func _build_collision() -> void:
	if _collision_object != null:
		remove_child(_collision_object)
		_collision_object.queue_free()
	var is_solid := kind == FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL or kind == FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR
	if is_solid:
		var body := StaticBody2D.new()
		body.name = "SolidBody"
		body.collision_layer = 1 << 2
		body.collision_mask = 0
		_collision_object = body
	else:
		var area := Area2D.new()
		area.name = "EffectArea"
		area.collision_layer = 1 << 5
		area.collision_mask = (1 << 0) | (1 << 1)
		area.monitoring = true
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
		_collision_object = area
	add_child(_collision_object)
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	_collision_shape.scale = Vector2.ONE
	if kind == FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR:
		var circle := CircleShape2D.new()
		circle.radius = minf(piece_size.x, piece_size.y) * 0.5
		_collision_shape.shape = circle
	else:
		var rectangle := RectangleShape2D.new()
		rectangle.size = piece_size
		_collision_shape.shape = rectangle
	_collision_object.add_child(_collision_shape)


func _on_body_entered(body: Node2D) -> void:
	terrain_effect_entered.emit(kind, body, effect_strength, effect_direction.rotated(rotation))


func _on_body_exited(body: Node2D) -> void:
	terrain_effect_exited.emit(kind, body)


func _draw() -> void:
	match kind:
		FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL:
			_draw_wall()
		FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR:
			_draw_pillar()
		FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL:
			_draw_ink_pool()
		FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE:
			_draw_current_lane()
		FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH:
			_draw_sun_patch()
		FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER:
			_draw_thorn_paper()


func _draw_wall() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	if visual_style == &"ink_city":
		draw_rect(rect.grow(12.0), Color(0.025, 0.008, 0.055, 0.62), true)
		draw_rect(rect, Color(0.075, 0.025, 0.11, 0.98), true)
		var roof := PackedVector2Array([Vector2(rect.position.x - 26, rect.position.y + 8), Vector2(rect.end.x + 26, rect.position.y + 8), Vector2(rect.end.x - 20, rect.position.y - 24), Vector2(rect.position.x + 20, rect.position.y - 24)])
		draw_colored_polygon(roof, Color(0.28, 0.08, 0.30, 0.94))
		draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[0]]), Color(0.94, 0.42, 0.78, 0.56), 2.4, true)
		for window in maxi(2, int(piece_size.x / 84.0)):
			var x := lerpf(rect.position.x + 28.0, rect.end.x - 28.0, float(window) / float(maxi(1, int(piece_size.x / 84.0) - 1)))
			draw_rect(Rect2(Vector2(x - 12, -10), Vector2(24, 20)), Color(0.82, 0.38, 0.76, 0.28), false, 2.0, true)
		return
	if visual_style == &"sun_court":
		draw_rect(rect.grow(11.0), Color(0.28, 0.07, 0.035, 0.50), true)
		draw_rect(rect, Color(0.43, 0.18, 0.07, 0.96), true)
		draw_rect(rect.grow(-6.0), Color(1.0, 0.70, 0.28, 0.50), false, 3.0, true)
		var panels := maxi(2, int(piece_size.x / 92.0))
		for panel in panels:
			var x := lerpf(rect.position.x, rect.end.x, (float(panel) + 0.5) / float(panels))
			draw_line(Vector2(x, rect.position.y + 7), Vector2(x, rect.end.y - 7), Color(1.0, 0.78, 0.38, 0.24), 2.0, true)
			draw_circle(Vector2(x, 0), minf(13.0, piece_size.y * 0.22), Color(1.0, 0.62, 0.18, 0.18))
		return
	# Paper-reef walls are solid folded rock, not translucent neon panels.
	draw_rect(rect.grow(12.0), Color("081b22"), true)
	draw_rect(rect, Color("53645f"), true)
	var top_shelf := PackedVector2Array([
		Vector2(rect.position.x, rect.position.y + 12.0),
		Vector2(rect.position.x + piece_size.x * 0.18, rect.position.y - 10.0),
		Vector2(rect.position.x + piece_size.x * 0.46, rect.position.y + 5.0),
		Vector2(rect.position.x + piece_size.x * 0.72, rect.position.y - 14.0),
		Vector2(rect.end.x, rect.position.y + 10.0),
		Vector2(rect.end.x, rect.position.y + 28.0),
		Vector2(rect.position.x, rect.position.y + 28.0),
	])
	draw_colored_polygon(top_shelf, Color("829078"))
	for facet in maxi(2, int(piece_size.x / 82.0)):
		var facet_x := lerpf(rect.position.x + 18.0, rect.end.x - 54.0, float(facet) / float(maxi(1, int(piece_size.x / 82.0) - 1)))
		var shade := Color("405451") if facet % 2 == 0 else Color("65746a")
		draw_colored_polygon(PackedVector2Array([
			Vector2(facet_x, rect.position.y + 30.0), Vector2(facet_x + 42.0, rect.position.y + 22.0),
			Vector2(facet_x + 56.0, rect.end.y - 9.0), Vector2(facet_x + 10.0, rect.end.y - 4.0),
		]), shade)
	for clasp_x in [rect.position.x + 16.0, rect.end.x - 28.0]:
		draw_rect(Rect2(Vector2(clasp_x, -7.0), Vector2(12.0, 14.0)), Color("f4bd58"), true)


func _draw_pillar() -> void:
	var radius := minf(piece_size.x, piece_size.y) * 0.5
	if visual_style == &"ink_city":
		for glow in range(4, 0, -1):
			draw_circle(Vector2.ZERO, radius + glow * 7.0, Color(0.76, 0.26, 0.86, 0.022 * float(5 - glow)))
		draw_circle(Vector2.ZERO, radius, Color(0.035, 0.012, 0.075, 0.98))
		var seal := Rect2(Vector2.ONE * -radius * 0.68, Vector2.ONE * radius * 1.36)
		draw_rect(seal, Color(0.72, 0.24, 0.74, 0.24), true)
		draw_rect(seal, Color(0.96, 0.48, 0.80, 0.72), false, 3.0, true)
		draw_line(Vector2(-radius * 0.48, 0), Vector2(radius * 0.48, 0), Color(1.0, 0.68, 0.30, 0.68), 3.0, true)
		draw_line(Vector2(0, -radius * 0.48), Vector2(0, radius * 0.48), Color(1.0, 0.68, 0.30, 0.68), 3.0, true)
		return
	if visual_style == &"sun_court":
		for ray in 12:
			var direction := Vector2.from_angle(float(ray) * TAU / 12.0)
			draw_line(direction * radius * 0.72, direction * (radius + 18.0), Color(1.0, 0.62, 0.18, 0.54), 4.0, true)
		draw_circle(Vector2.ZERO, radius, Color(0.38, 0.13, 0.045, 0.98))
		draw_circle(Vector2.ZERO, radius * 0.70, Color(1.0, 0.52, 0.12, 0.18))
		draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 48, Color(1.0, 0.82, 0.43, 0.82), 3.0, true)
		draw_circle(Vector2.ZERO, radius * 0.22, Color(0.02, 0.015, 0.03, 0.95))
		return
	var shadow := PackedVector2Array([Vector2(0, -radius - 12.0), Vector2(radius + 12.0, 0), Vector2(0, radius + 12.0), Vector2(-radius - 12.0, 0)])
	draw_colored_polygon(shadow, Color("081b22"))
	var diamond := PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
	draw_colored_polygon(diamond, Color("829078"))
	var inset := radius * 0.64
	draw_colored_polygon(PackedVector2Array([Vector2(0, -inset), Vector2(inset, 0), Vector2(0, inset), Vector2(-inset, 0)]), Color("17424a"))
	draw_rect(Rect2(Vector2(-7.0, -radius * 0.48), Vector2(14.0, radius * 0.96)), Color("f4bd58"), true)
	draw_rect(Rect2(Vector2(-radius * 0.48, -7.0), Vector2(radius * 0.96, 14.0)), Color("f4bd58"), true)


func _draw_ink_pool() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	if visual_style == &"ink_city":
		draw_rect(rect, Color(0.015, 0.008, 0.035, 0.72), true)
		for stroke in 9:
			var y := lerpf(rect.position.y + 12.0, rect.end.y - 12.0, float(stroke) / 8.0)
			var inset := absf(sin(stroke * 1.7)) * 54.0
			draw_line(Vector2(rect.position.x + inset, y), Vector2(rect.end.x - inset * 0.55, y - 13.0), Color(0.68, 0.22, 0.78, 0.12 + stroke % 2 * 0.06), 9.0, true)
		draw_rect(rect.grow(-4.0), Color(0.92, 0.38, 0.82, 0.44), false, 3.0, true)
		return
	if visual_style == &"sun_court":
		draw_rect(rect, Color(0.15, 0.025, 0.035, 0.64), true)
		var eclipse_radius := minf(piece_size.x, piece_size.y) * 0.36
		draw_circle(Vector2.ZERO, eclipse_radius, Color(0.008, 0.008, 0.018, 0.92))
		draw_arc(Vector2.ZERO, eclipse_radius + 10.0, -PI * 0.8, PI * 0.74, 48, Color(1.0, 0.46, 0.16, 0.62), 5.0, true)
		draw_rect(rect.grow(-5.0), Color(0.92, 0.30, 0.18, 0.38), false, 3.0, true)
		return
	draw_rect(rect.grow(8.0), Color("190e20"), true)
	draw_rect(rect, Color("2b1725"), true)
	draw_rect(Rect2(rect.position + Vector2(8.0, 8.0), Vector2(piece_size.x - 16.0, 7.0)), Color("d96c3f"), true)
	var tooth_count := maxi(4, int(piece_size.x / 48.0))
	for tooth in tooth_count:
		var x := lerpf(rect.position.x + 18.0, rect.end.x - 18.0, float(tooth) / float(maxi(1, tooth_count - 1)))
		var triangle := PackedVector2Array([Vector2(x - 12.0, rect.position.y + 27.0), Vector2(x + 12.0, rect.position.y + 27.0), Vector2(x, rect.position.y + 52.0)])
		draw_colored_polygon(triangle, Color("ff654f"))
	for stripe in 5:
		var y := lerpf(rect.get_center().y, rect.end.y - 12.0, float(stripe) / 4.0)
		draw_rect(Rect2(Vector2(rect.position.x + 16.0 + float(stripe % 2) * 22.0, y), Vector2(piece_size.x - 48.0, 4.0)), Color(0.37, 0.15, 0.19, 0.64), true)


func _draw_current_lane() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	if visual_style == &"ink_city":
		draw_rect(rect, Color(0.34, 0.09, 0.48, 0.20), true)
		draw_rect(rect, Color(0.86, 0.38, 0.82, 0.48), false, 2.5, true)
		var sign_x := -1.0 if effect_direction.x < 0.0 else 1.0
		for ribbon in 3:
			var y := lerpf(rect.position.y + 22.0, rect.end.y - 22.0, float(ribbon) / 2.0)
			var points := PackedVector2Array()
			for step in 13:
				var x := lerpf(rect.position.x + 18.0, rect.end.x - 18.0, float(step) / 12.0)
				points.append(Vector2(x, y + sin(step * 0.8 + _visual_time * 2.0) * 9.0))
			draw_polyline(points, Color(0.94, 0.54, 0.86, 0.24), 3.0, true)
		for mark in 6:
			var x := lerpf(rect.position.x + 34.0, rect.end.x - 34.0, float(mark) / 5.0)
			draw_line(Vector2(x - 13 * sign_x, -10), Vector2(x, 0), Color(1.0, 0.70, 0.32, 0.58), 3.0, true)
			draw_line(Vector2(x, 0), Vector2(x - 13 * sign_x, 10), Color(1.0, 0.70, 0.32, 0.58), 3.0, true)
		return
	if visual_style == &"sun_court":
		draw_rect(rect, Color(0.70, 0.29, 0.06, 0.20), true)
		draw_rect(rect, Color(1.0, 0.68, 0.22, 0.54), false, 3.0, true)
		var sign_x := -1.0 if effect_direction.x < 0.0 else 1.0
		for chevron in 8:
			var x := lerpf(rect.position.x + 28.0, rect.end.x - 28.0, float(chevron) / 7.0)
			var points := PackedVector2Array([Vector2(x - 20 * sign_x, -22), Vector2(x + 8 * sign_x, 0), Vector2(x - 20 * sign_x, 22)])
			draw_polyline(points, Color(1.0, 0.86, 0.44, 0.40 + sin(_visual_time * 3.4 + chevron) * 0.12), 5.0, true)
		return
	draw_rect(rect, Color("124f51"), true)
	draw_rect(Rect2(rect.position + Vector2(5.0, 5.0), piece_size - Vector2(10.0, 10.0)), Color("176968"), true)
	var pulse := 0.5 + sin(_visual_time * 3.4) * 0.18
	var sign_x := -1.0 if effect_direction.x < 0.0 else 1.0
	for arrow in 7:
		var x := lerpf(rect.position.x + 30.0, rect.end.x - 30.0, float(arrow) / 6.0)
		var center := Vector2(x, 0.0)
		var arrow_color := Color(0.35, 0.94, 0.82, pulse)
		draw_rect(Rect2(center + Vector2(-9.0 * sign_x, -5.0), Vector2(18.0 * sign_x, 10.0)).abs(), arrow_color, true)
		draw_colored_polygon(PackedVector2Array([center + Vector2(16.0 * sign_x, 0), center + Vector2(2.0 * sign_x, -15.0), center + Vector2(2.0 * sign_x, 15.0)]), arrow_color)


func _draw_sun_patch() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var pulse := 0.72 + sin(_visual_time * 2.6) * 0.12
	if visual_style == &"paper_reef":
		draw_rect(rect.grow(6.0), Color("0b3438"), true)
		draw_rect(rect, Color("124f51"), true)
		draw_rect(Rect2(rect.position + Vector2(8.0, 8.0), piece_size - Vector2(16.0, 16.0)), Color("176968"), true)
		var plus_color := Color(0.35, 0.94, 0.82, pulse)
		var arm := minf(piece_size.x, piece_size.y) * 0.34
		draw_rect(Rect2(Vector2(-7.0, -arm), Vector2(14.0, arm * 2.0)), plus_color, true)
		draw_rect(Rect2(Vector2(-arm, -7.0), Vector2(arm * 2.0, 14.0)), plus_color, true)
		for mote in [Vector2(-piece_size.x * 0.34, -piece_size.y * 0.28), Vector2(piece_size.x * 0.31, -piece_size.y * 0.24), Vector2(-piece_size.x * 0.29, piece_size.y * 0.27), Vector2(piece_size.x * 0.34, piece_size.y * 0.25)]:
			draw_rect(Rect2(mote - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color("8ed9ca"), true)
		return
	if visual_style == &"ink_city":
		draw_rect(rect, Color(0.40, 0.14, 0.46, 0.18), true)
		draw_rect(rect.grow(-5.0), Color(0.92, 0.52, 0.82, 0.48 * pulse), false, 3.0, true)
		var window := Rect2(-piece_size * 0.22, piece_size * 0.44)
		draw_rect(window, Color(1.0, 0.72, 0.34, 0.10 * pulse), true)
		draw_line(Vector2(window.get_center().x, window.position.y), Vector2(window.get_center().x, window.end.y), Color(1.0, 0.74, 0.40, 0.52), 2.0, true)
		draw_line(Vector2(window.position.x, window.get_center().y), Vector2(window.end.x, window.get_center().y), Color(1.0, 0.74, 0.40, 0.52), 2.0, true)
		return
	draw_rect(rect, Color(0.72, 0.38, 0.06, 0.18), true)
	draw_rect(rect.grow(-5.0), Color(1.0, 0.72, 0.26, 0.50 * pulse), false, 3.0, true)
	for ray in 9:
		var x := lerpf(rect.position.x + 24.0, rect.end.x - 24.0, float(ray) / 8.0)
		draw_line(Vector2(x - 24.0, rect.end.y - 10.0), Vector2(x + 24.0, rect.position.y + 10.0), Color(1.0, 0.90, 0.52, 0.10 + pulse * 0.14), 5.0, true)
	var center_radius := minf(piece_size.x, piece_size.y) * 0.20
	draw_circle(Vector2.ZERO, center_radius, Color(1.0, 0.74, 0.27, 0.12 * pulse))
	draw_arc(Vector2.ZERO, center_radius + 8.0, 0.0, TAU, 28, Color(1.0, 0.92, 0.62, 0.62), 2.5, true)


func _draw_thorn_paper() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var pulse := 0.75 + sin(_visual_time * 4.2) * 0.15
	if visual_style == &"ink_city":
		draw_rect(rect, Color(0.22, 0.015, 0.12, 0.42), true)
		draw_rect(rect, Color(1.0, 0.28, 0.50, 0.58 * pulse), false, 3.0, true)
		for seal in 5:
			var x := lerpf(rect.position.x + 24.0, rect.end.x - 24.0, float(seal) / 4.0)
			draw_line(Vector2(x - 16, -22), Vector2(x + 16, 22), Color(1.0, 0.45, 0.62, 0.72), 5.0, true)
			draw_line(Vector2(x + 16, -22), Vector2(x - 16, 22), Color(0.08, 0.01, 0.05, 0.90), 3.0, true)
		return
	if visual_style == &"sun_court":
		draw_rect(rect, Color(0.32, 0.035, 0.025, 0.42), true)
		draw_rect(rect, Color(1.0, 0.36, 0.16, 0.62 * pulse), false, 3.0, true)
		var blade_count := maxi(5, int(piece_size.x / 42.0))
		for blade in blade_count:
			var x := lerpf(rect.position.x + 16.0, rect.end.x - 16.0, float(blade) / float(maxi(1, blade_count - 1)))
			var blade_shape := PackedVector2Array([Vector2(x - 12, 24), Vector2(x + 12, 24), Vector2(x, -36)])
			draw_colored_polygon(blade_shape, Color(1.0, 0.54, 0.18, 0.48 + pulse * 0.15))
			draw_polyline(PackedVector2Array([blade_shape[0], blade_shape[1], blade_shape[2], blade_shape[0]]), Color(1.0, 0.84, 0.38, 0.76), 1.8, true)
		return
	draw_rect(rect.grow(7.0), Color("190e20"), true)
	draw_rect(rect, Color("3d1b27"), true)
	draw_rect(Rect2(rect.position + Vector2(6.0, 6.0), Vector2(piece_size.x - 12.0, 6.0)), Color(0.85, 0.42, 0.25, pulse), true)
	var thorn_count := maxi(4, int(piece_size.x / 46.0))
	for thorn in thorn_count:
		var x := lerpf(rect.position.x + 18.0, rect.end.x - 18.0, float(thorn) / float(maxi(1, thorn_count - 1)))
		var triangle := PackedVector2Array([Vector2(x - 15.0, rect.end.y - 12.0), Vector2(x + 15.0, rect.end.y - 12.0), Vector2(x, rect.position.y + 21.0 + float(thorn % 2) * 13.0)])
		draw_colored_polygon(triangle, Color(1.0, 0.40, 0.31, 0.62 + pulse * 0.18))
