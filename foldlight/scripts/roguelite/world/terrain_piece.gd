class_name FoldlightTerrainPiece
extends Node2D

const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const BENEFIT_COLOR := Color("95e5c7")
const INK_COLOR := Color("c1a0e8")
const HAZARD_COLOR := Color("f58b73")
const CURRENT_COLOR := Color("90c9ee")

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
var _motion_active: bool = true
var _observer: Node2D
var _presence: float = 0.0
var _proximity: float = 0.0
var _redraw_remaining: float = 0.0


func _process(delta: float) -> void:
	if not _motion_active or kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
		return
	_visual_time += delta
	var inside := false
	var proximity := 0.0
	if is_instance_valid(_observer):
		var local_point := to_local(_observer.global_position)
		var outside := (local_point.abs() - piece_size * 0.5).max(Vector2.ZERO)
		proximity = 1.0 - clampf(outside.length() / 150.0, 0.0, 1.0)
		inside = contains_world_point(_observer.global_position)
	_presence = move_toward(_presence, 1.0 if inside else 0.0, delta * 4.5)
	_proximity = move_toward(_proximity, proximity, delta * 5.0)
	_redraw_remaining -= delta
	if _redraw_remaining <= 0.0:
		_redraw_remaining = 1.0 / 30.0
		queue_redraw()


func bind_observer(player: Node2D) -> void:
	_observer = player


func set_motion_active(value: bool) -> void:
	_motion_active = value
	set_process(value)


func get_readability() -> Dictionary:
	# Meaning stays constant across biomes. Regional materials never recolor
	# a benefit as a hazard, and wet ink must not promise a movement slow.
	match kind:
		FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH:
			return {"polarity": &"benefit", "label": "日纹", "detail": "回息↑ · 移速↑", "color": BENEFIT_COLOR, "pattern": &"inward_light"}
		FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL:
			return {"polarity": &"debuff", "label": "湿墨", "detail": "折息恢复降低", "color": INK_COLOR, "pattern": &"draining_ink"}
		FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER:
			return {"polarity": &"hazard", "label": "刺纸", "detail": "接触受伤", "color": HAZARD_COLOR, "pattern": &"barbed_hatching"}
		FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE:
			return {"polarity": &"directional", "label": "潮流", "detail": "沿箭头推移", "color": CURRENT_COLOR, "pattern": &"flowing_chevrons"}
	return {"polarity": &"solid", "label": "纸礁", "detail": "阻挡通行", "color": _regional_paper(), "pattern": &"folded_solid"}


func configure(placement: Dictionary) -> void:
	placement_id = StringName(placement.get("id", &"terrain"))
	kind = int(placement.get("kind", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL))
	position = Vector2(placement.get("position", Vector2.ZERO))
	rotation = float(placement.get("rotation", 0.0))
	piece_size = Vector2(placement.get("size", Vector2(200.0, 80.0))).abs()
	effect_strength = maxf(0.0, float(placement.get("strength", 1.0)))
	effect_direction = Vector2(placement.get("direction", Vector2.RIGHT)).normalized()
	visual_style = StringName(placement.get("visual_style", &"paper_reef"))
	_visual_time = 0.0
	_presence = 0.0
	_proximity = 0.0
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
	_draw_zone_sheet(rect, Color("30283f"), INK_COLOR)
	# Sunlight gathers inward; wet ink visibly drains down in broken bands.
	# The dashed inner seam and hollow lantern survive a grayscale reading.
	_draw_dashed_frame(rect.grow(-8.0), Color(INK_COLOR, 0.65), 2.0, 12.0)
	var bands := maxi(3, int(piece_size.y / 30.0))
	for band in bands:
		var points := PackedVector2Array()
		for step in 17:
			var x := lerpf(rect.position.x + 15.0, rect.end.x - 15.0, float(step) / 16.0)
			var progress := fposmod(float(band) / float(bands) + _visual_time * 0.055, 1.0)
			var y := lerpf(rect.position.y + 15.0, rect.end.y - 15.0, progress)
			y += sin(float(step) * 0.7 + float(band) * 1.1) * minf(4.0, piece_size.y * 0.025)
			points.append(Vector2(x, y))
		draw_polyline(points, Color(INK_COLOR, 0.15 + float(band % 2) * 0.06), 2.0, true)
	var size := minf(27.0, minf(piece_size.x, piece_size.y) * 0.22)
	_draw_symbol_backing(size, Color("30283f"))
	var drop := PackedVector2Array([Vector2(0, -size), Vector2(size * 0.65, size * 0.15), Vector2(size * 0.42, size * 0.65), Vector2(0, size * 0.82), Vector2(-size * 0.42, size * 0.65), Vector2(-size * 0.65, size * 0.15)])
	draw_colored_polygon(drop, Color(INK_COLOR, 0.10))
	draw_polyline(_closed(drop), Color(INK_COLOR, 0.95), 2.5, true)
	draw_line(Vector2(-size * 0.25, 0), Vector2(size * 0.25, 0), Color(INK_COLOR, 0.95), 3.0, true)
	for side in [-1.0, 1.0]:
		var center := Vector2(side * (size + 17.0), sin(_visual_time * 2.0) * 2.0)
		draw_polyline(PackedVector2Array([center + Vector2(-6, -3), center + Vector2(0, 4), center + Vector2(6, -3)]), Color(INK_COLOR, 0.8), 2.5, true)


func _draw_current_lane() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	_draw_zone_sheet(rect, Color("183544"), CURRENT_COLOR)
	var direction := effect_direction
	var tangent := direction.orthogonal()
	var inset := rect.grow(-12.0)
	var reach := piece_size.length() * 0.5
	var size := minf(15.0, minf(piece_size.x, piece_size.y) * 0.17)
	var travel := fposmod(_visual_time * 33.0, 62.0)
	# Use the effect's actual local direction, including vertical/diagonal lanes.
	# Draw only complete chevrons inside the real rectangular footprint.
	for row in range(-int(reach / 46.0), int(reach / 46.0) + 1):
		for column in range(-int(reach / 62.0) - 1, int(reach / 62.0) + 2):
			var center := direction * (float(column) * 62.0 + travel) + tangent * float(row) * 46.0
			var tip := center + direction * size * 0.65
			var left := center - direction * size * 0.55 - tangent * size * 0.65
			var right := center - direction * size * 0.55 + tangent * size * 0.65
			if not inset.has_point(tip) or not inset.has_point(left) or not inset.has_point(right):
				continue
			var alpha := 0.62 if row == 0 else 0.25
			draw_polyline(PackedVector2Array([left, tip, right]), Color(CURRENT_COLOR, alpha + _presence * 0.12), 3.0 if row == 0 else 1.8, true)


func _draw_sun_patch() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	_draw_zone_sheet(rect, Color("1d423b"), BENEFIT_COLOR)
	var pulse := 0.76 + sin(_visual_time * 1.6) * 0.10
	var inset := rect.grow(-9.0)
	draw_rect(inset, Color(BENEFIT_COLOR, 0.42), false, 1.3, true)
	# Two inward-folding paper leaves on each side are the benefit silhouette.
	for side in [-1.0, 1.0]:
		for column in [-1.0, 1.0]:
			var base := Vector2(column * (piece_size.x * 0.5 - 19.0), side * (piece_size.y * 0.5 - 19.0))
			var tip := base - Vector2(column * 22.0, side * 15.0)
			draw_colored_polygon(PackedVector2Array([base, base - Vector2(column * 24.0, 0), tip]), Color(BENEFIT_COLOR, 0.28))
			draw_line(base, tip, Color(BENEFIT_COLOR, 0.8), 2.0, true)
	var size := minf(28.0, minf(piece_size.x, piece_size.y) * 0.22)
	for mote in 8:
		var progress := fposmod(_visual_time * 0.22 + float(mote) / 8.0, 1.0)
		var angle := float(mote) * TAU / 8.0
		var edge := Vector2.from_angle(angle) * Vector2(piece_size.x * 0.40, piece_size.y * 0.34)
		var point := edge.lerp(Vector2.from_angle(angle) * size * 1.55, progress)
		var alpha := sin(progress * PI) * 0.48
		draw_circle(point, 2.0 + progress, Color(BENEFIT_COLOR.lerp(PaperArt.PAPER, 0.45), alpha))
	_draw_symbol_backing(size, Color("1d423b"))
	draw_arc(Vector2.ZERO, size * 1.3, 0.0, TAU, 36, Color(BENEFIT_COLOR, 0.28 + _presence * 0.24), 1.7, true)
	_draw_lantern(Vector2.ZERO, size, BENEFIT_COLOR, 1.0)
	for ray in 8:
		var direction := Vector2.from_angle(float(ray) * TAU / 8.0)
		draw_line(direction * size * 1.55, direction * size * (1.80 + pulse * 0.15), Color(BENEFIT_COLOR, 0.55), 2.4, true)


func _draw_thorn_paper() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	_draw_zone_sheet(rect, Color("432c33"), HAZARD_COLOR)
	var inset := rect.grow(-13.0)
	_draw_clipped_hatching(inset, Color(HAZARD_COLOR, 0.13), 29.0)
	# Barbs point into the hazardous area, never outside its collision boundary.
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for edge in 4:
		var start: Vector2 = corners[edge]
		var end: Vector2 = corners[(edge + 1) % 4]
		var direction := start.direction_to(end)
		var inward := Vector2(-direction.y, direction.x)
		var count := maxi(1, int(start.distance_to(end) / 40.0))
		for index in count:
			var center := start.lerp(end, (float(index) + 0.5) / float(count))
			var tooth := PackedVector2Array([center - direction * 7.0, center + inward * 11.0, center + direction * 7.0])
			draw_colored_polygon(tooth, Color(HAZARD_COLOR, 0.72))
	var size := minf(28.0, minf(piece_size.x, piece_size.y) * 0.22)
	_draw_symbol_backing(size, Color("432c33"))
	var triangle := PackedVector2Array([Vector2(0, -size), Vector2(size, size * 0.76), Vector2(-size, size * 0.76)])
	draw_colored_polygon(triangle, Color(HAZARD_COLOR, 0.08))
	draw_polyline(_closed(triangle), Color(HAZARD_COLOR, 0.96), 3.0, true)
	draw_line(Vector2(0, -size * 0.34), Vector2(0, size * 0.15), Color("ffe2d0"), 3.5, true)
	draw_circle(Vector2(0, size * 0.43), 2.1, Color("ffe2d0"))
	var thorn_count := maxi(2, int(piece_size.x / 78.0))
	for thorn in thorn_count:
		var x := lerpf(inset.position.x, inset.end.x, (float(thorn) + 0.5) / float(thorn_count))
		if absf(x) < size * 1.8:
			continue
		var tip := Vector2(x, -piece_size.y * 0.20)
		var base := Vector2(x + 6.0, piece_size.y * 0.22)
		draw_colored_polygon(PackedVector2Array([base - Vector2(12, 0), tip, base + Vector2(12, 0)]), Color(HAZARD_COLOR, 0.46))
		draw_line(base - Vector2(12, 0), tip, Color("ffe2d0", 0.55), 1.6, true)


func _draw_zone_sheet(rect: Rect2, fill: Color, accent: Color) -> void:
	# Opaque paper separates interactive ground from decorative sea washes.
	# Every bright boundary is centered on the same rectangle as the effect.
	var material := fill.lerp(_regional_paper(), 0.07)
	draw_rect(rect, material.lightened(_presence * 0.07), true)
	draw_rect(rect, Color(PaperArt.INK, 0.82), false, 9.0, true)
	draw_rect(rect, Color(accent, 0.76 + _proximity * 0.16), false, 2.8 + _presence * 0.8, true)
	var seam := rect.grow(-3.0)
	draw_line(seam.position, Vector2(seam.end.x, seam.position.y), Color(accent, 0.18), 1.0, true)
	if _presence > 0.01:
		var pulse := (0.5 + 0.5 * sin(_visual_time * 2.8)) * _presence
		draw_rect(rect.grow(-4.0), Color(accent, 0.12 + pulse * 0.24), false, 2.0, true)


func _draw_symbol_backing(size: float, fill: Color) -> void:
	var shape := PackedVector2Array()
	for vertex in 8:
		shape.append(Vector2.from_angle(float(vertex) * TAU / 8.0 + PI / 8.0) * size * 1.48)
	draw_colored_polygon(shape, Color(fill, 0.97))


func _draw_dashed_frame(rect: Rect2, color: Color, width: float, dash: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for edge in 4:
		draw_dashed_line(corners[edge], corners[(edge + 1) % 4], color, width, dash, true)


func _draw_clipped_hatching(rect: Rect2, color: Color, spacing: float) -> void:
	# Clip the diagonal pattern analytically instead of letting decorative
	# hatch marks imply damage outside the authored rectangle.
	var offset := -rect.size.y
	while offset < rect.size.x:
		var begin := maxf(0.0, -offset)
		var end := minf(rect.size.y, rect.size.x - offset)
		if end > begin:
			draw_line(rect.position + Vector2(offset + begin, begin), rect.position + Vector2(offset + end, end), color, 2.0, true)
		offset += spacing


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


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
