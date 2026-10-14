class_name FoldlightTerrainPiece
extends Node2D

const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const DANGER := PaperArt.DANGER

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


func _regional_paper() -> Color:
	match visual_style:
		&"ink_city": return Color("4b555f")
		&"sun_court": return Color("71634d")
		_: return Color("526b65")


func _regional_foil() -> Color:
	return PaperArt.GOLD if visual_style == &"sun_court" else PaperArt.FOLD


func _draw_wall() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var paper := _regional_paper()
	var bevel := minf(12.0, minf(piece_size.x, piece_size.y) * 0.18)
	var top_left := rect.position
	var top_right := Vector2(rect.end.x, rect.position.y)
	var bottom_left := Vector2(rect.position.x, rect.end.y)
	var bottom_right := rect.end
	var inset := rect.grow(-bevel)
	draw_rect(Rect2(rect.position + Vector2(7, 10), piece_size), Color(PaperArt.INK, 0.70), true)
	# All folded faces stay inside the rectangular collision footprint.
	draw_rect(rect, paper.darkened(0.42), true)
	draw_colored_polygon(PackedVector2Array([top_left, top_right, Vector2(inset.end.x, inset.position.y), inset.position]), paper)
	draw_colored_polygon(PackedVector2Array([top_right, bottom_right, inset.end, Vector2(inset.end.x, inset.position.y)]), paper.darkened(0.36))
	draw_colored_polygon(PackedVector2Array([bottom_left, top_left, inset.position, Vector2(inset.position.x, inset.end.y)]), paper.darkened(0.16))
	draw_rect(inset, paper.darkened(0.21), true)
	var fold_point := Vector2(lerpf(inset.position.x, inset.end.x, 0.58), lerpf(inset.position.y, inset.end.y, 0.45))
	draw_colored_polygon(PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), fold_point]), paper.darkened(0.11))
	draw_colored_polygon(PackedVector2Array([inset.position, fold_point, Vector2(inset.position.x, inset.end.y)]), paper.darkened(0.30))
	draw_line(inset.position, fold_point, Color(PaperArt.PAPER, 0.11), 1.0, true)
	draw_line(fold_point, inset.end, Color(PaperArt.INK, 0.35), 1.0, true)
	draw_rect(rect, Color(paper.lightened(0.18), 0.60), false, 1.5, true)
	if visual_style == &"ink_city":
		# Narrow engraved windows retain the inverted archive architecture.
		var windows := maxi(1, int(piece_size.x / 100.0))
		for index in windows:
			var center := Vector2(lerpf(inset.position.x, inset.end.x, (float(index) + 0.5) / float(windows)), 0)
			var window_size := Vector2(minf(14.0, piece_size.x * 0.08), minf(22.0, piece_size.y * 0.38))
			draw_rect(Rect2(center - window_size * 0.5, window_size), Color(PaperArt.INK, 0.65), true)
			draw_line(center - Vector2(0, window_size.y * 0.36), center + Vector2(0, window_size.y * 0.36), Color(PaperArt.GOLD, 0.40), 1.0, true)
	elif visual_style == &"sun_court":
		var radius := minf(13.0, piece_size.y * 0.22)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(PaperArt.GOLD, 0.48), 1.0, true)
		draw_circle(Vector2.ZERO, radius * 0.30, Color(PaperArt.INK, 0.55))
	else:
		# A thin foil binding is a construction detail, never a bright full face.
		for side in [-1.0, 1.0]:
			var x: float = side * (piece_size.x * 0.5 - bevel * 1.7)
			draw_line(Vector2(x, -piece_size.y * 0.16), Vector2(x, piece_size.y * 0.16), Color(PaperArt.GOLD, 0.60), 1.8, true)


func _draw_pillar() -> void:
	var radius := minf(piece_size.x, piece_size.y) * 0.5
	var paper := _regional_paper()
	var foil := _regional_foil()
	draw_circle(Vector2(5, 8), radius + 3.0, Color(PaperArt.INK, 0.75))
	draw_circle(Vector2.ZERO, radius, paper.darkened(0.40))
	var sides := 8 if visual_style != &"sun_court" else 12
	for facet in sides:
		var start := Vector2.from_angle(float(facet) * TAU / float(sides) - PI * 0.5) * radius
		var end := Vector2.from_angle(float(facet + 1) * TAU / float(sides) - PI * 0.5) * radius
		var inner := Vector2.from_angle((float(facet) + 0.5) * TAU / float(sides) - PI * 0.5) * radius * 0.38
		draw_colored_polygon(PackedVector2Array([start, end, inner]), paper.darkened(0.08 + float(facet % 4) * 0.10))
		draw_line(start, end, Color(PaperArt.PAPER, 0.16), 1.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(paper.lightened(0.24), 0.48), 1.2, true)
	var core := radius * 0.40
	if visual_style == &"ink_city":
		draw_rect(Rect2(Vector2.ONE * -core, Vector2.ONE * core * 2.0), PaperArt.INK, true)
		draw_rect(Rect2(Vector2.ONE * -core, Vector2.ONE * core * 2.0), Color(PaperArt.GOLD, 0.5), false, 1.0, true)
	else:
		draw_circle(Vector2.ZERO, core, PaperArt.INK)
		draw_arc(Vector2.ZERO, core, 0.0, TAU, 32, Color(foil, 0.45), 1.0, true)
	_draw_lantern(Vector2.ZERO, minf(18.0, core * 0.76), foil, 0.90)


func _draw_ink_pool() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	draw_rect(rect, Color("201f2a"), true)
	draw_rect(rect, Color(DANGER, 0.46), false, 1.4, true)
	for band in 4:
		var points := PackedVector2Array()
		for step in 17:
			var x := lerpf(rect.position.x + 8.0, rect.end.x - 8.0, float(step) / 16.0)
			var y := lerpf(rect.position.y, rect.end.y, (float(band) + 0.6) / 4.5)
			y += sin(float(step) * 0.65 + _visual_time * 0.55 + float(band)) * minf(5.0, piece_size.y * 0.04)
			points.append(Vector2(x, y))
		draw_polyline(points, Color(DANGER, 0.10 + float(band % 2) * 0.035), 2.0, true)
	# A small descending drop distinguishes slowing ink from solid terrain.
	var h := minf(16.0, piece_size.y * 0.20)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -h), Vector2(h * 0.55, h * 0.25), Vector2(0, h), Vector2(-h * 0.55, h * 0.25)]), Color(DANGER, 0.58))


func _draw_current_lane() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var foil := _regional_foil()
	draw_rect(rect, Color(foil, 0.065), true)
	draw_rect(rect, Color(foil, 0.28), false, 1.0, true)
	var tangent := effect_direction.rotated(PI * 0.5)
	var marker_size := minf(12.0, minf(piece_size.x, piece_size.y) * 0.16)
	var arrow_count := maxi(2, int(piece_size.x / 62.0))
	for arrow in arrow_count:
		var progress := (float(arrow) + 0.5) / float(arrow_count)
		var center := Vector2(lerpf(rect.position.x + marker_size, rect.end.x - marker_size, progress), 0)
		var points := PackedVector2Array([
			center - effect_direction * marker_size * 0.5 - tangent * marker_size * 0.65,
			center + effect_direction * marker_size * 0.5,
			center - effect_direction * marker_size * 0.5 + tangent * marker_size * 0.65,
		])
		draw_polyline(points, Color(foil, 0.32 + sin(_visual_time * 2.0 - float(arrow) * 0.7) * 0.12), 1.8, true)
	for stream in [-1.0, 1.0]:
		var y: float = stream * piece_size.y * 0.30
		draw_line(Vector2(rect.position.x + 10, y), Vector2(rect.end.x - 10, y), Color(foil, 0.12), 1.0, true)


func _draw_sun_patch() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var pulse := 0.76 + sin(_visual_time * 1.8) * 0.10
	var foil := PaperArt.FOLD if visual_style == &"paper_reef" else PaperArt.GOLD
	draw_rect(rect, Color(foil, 0.075), true)
	draw_rect(rect, Color(foil, 0.38), false, 1.2, true)
	var inset := rect.grow(-7.0)
	draw_line(inset.position, Vector2(inset.end.x, inset.position.y), Color(foil, 0.16), 1.0, true)
	draw_line(Vector2(inset.position.x, inset.end.y), inset.end, Color(foil, 0.16), 1.0, true)
	var size := minf(24.0, minf(piece_size.x, piece_size.y) * 0.22)
	_draw_lantern(Vector2.ZERO, size, foil, pulse)
	for side in [-1.0, 1.0]:
		var x: float = side * piece_size.x * 0.30
		draw_line(Vector2(x - 8, 0), Vector2(x + 8, 0), Color(foil, 0.34), 1.0, true)


func _draw_thorn_paper() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	var pulse := 0.75 + sin(_visual_time * 2.4) * 0.10
	draw_rect(rect, Color("2b252c"), true)
	draw_rect(rect, Color(DANGER, 0.56 * pulse), false, 1.6, true)
	var thorn_count := maxi(3, int(piece_size.x / 48.0))
	var half_width := minf(13.0, piece_size.x / float(thorn_count) * 0.30)
	for thorn in thorn_count:
		var x := lerpf(rect.position.x, rect.end.x, (float(thorn) + 0.5) / float(thorn_count))
		var tip := Vector2(x, rect.position.y + piece_size.y * (0.23 + float(thorn % 2) * 0.15))
		var base_left := Vector2(x - half_width, rect.end.y - piece_size.y * 0.18)
		var base_right := Vector2(x + half_width, base_left.y)
		var crease := Vector2(x, base_left.y)
		draw_colored_polygon(PackedVector2Array([base_left, tip, base_right]), Color(DANGER, 0.45 * pulse))
		draw_colored_polygon(PackedVector2Array([tip, crease, base_right]), Color(DANGER, 0.23))
		draw_line(base_left, tip, Color(PaperArt.PAPER, 0.26), 1.0, true)


func _draw_lantern(center: Vector2, size: float, foil: Color, alpha: float) -> void:
	var lantern := PackedVector2Array([
		center + Vector2(0, -size), center + Vector2(size * 0.60, -size * 0.28),
		center + Vector2(size * 0.43, size * 0.58), center + Vector2(0, size),
		center + Vector2(-size * 0.43, size * 0.58), center + Vector2(-size * 0.60, -size * 0.28),
	])
	draw_colored_polygon(lantern, Color(foil, 0.13 * alpha))
	var outline := lantern.duplicate()
	outline.append(lantern[0])
	draw_polyline(outline, Color(foil, 0.72 * alpha), 1.5, true)
	draw_line(lantern[0], lantern[3], Color(foil, 0.48 * alpha), 1.0, true)
	draw_circle(center, 2.5, Color(PaperArt.PAPER, alpha))
