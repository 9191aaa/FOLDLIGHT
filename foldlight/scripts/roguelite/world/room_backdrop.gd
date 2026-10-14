class_name FoldlightRoomBackdrop
extends Node2D

const PaperArt = preload("res://scripts/visuals/paper_art.gd")

var world_size: Vector2 = Vector2(2880.0, 1620.0)
var accent: Color = PaperArt.FOLD
var room_id: StringName = &""
var style_id: StringName = &"paper_reef"


func configure(new_room_id: StringName, new_size: Vector2, new_accent: Color, new_style_id: StringName = &"") -> void:
	room_id = new_room_id
	world_size = new_size
	accent = new_accent
	style_id = new_style_id if not new_style_id.is_empty() else _infer_style(new_room_id)
	queue_redraw()


func get_visual_contract() -> Dictionary:
	match style_id:
		&"ink_city":
			return {"style": style_id, "motifs": [&"inverted_skyline", &"hanging_bridges", &"seal_windows"], "base": Color("101f2b")}
		&"sun_court":
			return {"style": style_id, "motifs": [&"eclipse_disc", &"radial_mosaic", &"processional_rays"], "base": Color("1b2427")}
		_:
			return {"style": &"paper_reef", "motifs": [&"layered_tide_wash", &"folded_reef_silhouette", &"paper_moon", &"foam_stitches"], "base": PaperArt.INK}


func _infer_style(value: StringName) -> StringName:
	var text := String(value)
	if "city" in text or text.begins_with("r2"):
		return &"ink_city"
	if "sun" in text or text.begins_with("r3"):
		return &"sun_court"
	return &"paper_reef"


func _draw() -> void:
	match style_id:
		&"ink_city": _draw_ink_city()
		&"sun_court": _draw_sun_court()
		_: _draw_paper_reef()
	_draw_paper_grain()
	draw_rect(Rect2(Vector2(28, 28), world_size - Vector2(56, 56)), Color(PaperArt.FOLD, 0.12), false, 2.0, true)
	draw_rect(Rect2(Vector2(42, 42), world_size - Vector2(84, 84)), Color(PaperArt.GOLD, 0.05), false, 1.0, true)


func _draw_paper_reef() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), PaperArt.INK, true)
	# Broad unbroken paper washes leave the active combat plane quiet. Texture
	# and recognizable landforms live at the arena edges, below all actors.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, world_size.y * 0.12), Vector2(world_size.x, 0),
		world_size, Vector2(0, world_size.y),
	]), Color("0e242d"))
	PaperArt.draw_tide(self, world_size, 0.0, 5, 0.68)
	var moon := Vector2(world_size.x * (0.77 + float(absi(String(room_id).hash()) % 6) * 0.008), world_size.y * 0.115)
	draw_circle(moon + Vector2(10, 12), 83.0, Color(PaperArt.INK, 0.70))
	draw_circle(moon, 78.0, Color("384a48"))
	draw_circle(moon - Vector2(8, 5), 70.0, Color("41534e"))
	draw_arc(moon, 81.0, -PI * 0.85, PI * 0.25, 64, Color(PaperArt.GOLD, 0.14), 1.3, true)
	draw_line(moon + Vector2(-57, -45), moon + Vector2(62, 38), Color(PaperArt.INK, 0.20), 1.5, true)
	var reef_width := world_size.x / 5.0
	for reef_index in 5:
		var reef_x := float(reef_index) * reef_width - 40.0
		var height := 115.0 + float((reef_index * 37) % 72)
		_draw_folded_reef(Vector2(reef_x, 190.0), reef_width + 80.0, height, Color("132d35"), Color("27454a"))
		_draw_folded_reef(Vector2(reef_x - 80.0, world_size.y + 28.0), reef_width + 130.0, height * 1.22, Color("0a1b23"), Color("1d363d"))
	# A few foam stitches suggest a current; their contrast stays below terrain.
	for stitch in 24:
		var p := _seeded_point(stitch, 251, 173, 76.0).round()
		var length := 12.0 + float(stitch % 5) * 10.0
		draw_line(p, p + Vector2(length, -2.0), Color(PaperArt.FOLD, 0.035), 1.0, true)


func _draw_folded_reef(origin: Vector2, width: float, height: float, fill: Color, edge: Color) -> void:
	var ridge := PackedVector2Array([
		Vector2(origin.x, origin.y),
		Vector2(origin.x + width * 0.18, origin.y - height * 0.45),
		Vector2(origin.x + width * 0.34, origin.y - height),
		Vector2(origin.x + width * 0.53, origin.y - height * 0.44),
		Vector2(origin.x + width * 0.70, origin.y - height * 0.72),
		Vector2(origin.x + width, origin.y),
	])
	draw_colored_polygon(ridge, fill)
	var valley := origin + Vector2(width * 0.42, 0)
	draw_colored_polygon(PackedVector2Array([ridge[1], ridge[2], valley]), fill.lerp(edge, 0.30))
	draw_colored_polygon(PackedVector2Array([ridge[2], ridge[3], valley]), fill.darkened(0.16))
	draw_colored_polygon(PackedVector2Array([ridge[3], ridge[4], ridge[5]]), fill.lerp(edge, 0.18))
	draw_polyline(ridge, Color(edge, 0.28), 1.0, true)
	draw_line(ridge[2], valley, Color(edge, 0.35), 1.0, true)


func _draw_block_disc(center: Vector2, radius: int, color: Color, step: int) -> void:
	for y in range(-radius, radius + 1, step):
		var half_width := sqrt(maxf(0.0, float(radius * radius - y * y)))
		var snapped_width := floorf(half_width / float(step)) * float(step)
		draw_rect(Rect2(Vector2(center.x - snapped_width, center.y + float(y)), Vector2(snapped_width * 2.0, float(step))), color, true)


func _draw_ink_city() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color("101f2b"), true)
	# The city hangs upside-down from the top edge: roofs, bridges and windows
	# form a strong vertical composition unique to region two.
	for tower in 13:
		var width := 120.0 + float(tower % 4) * 42.0
		var x := float(tower) * world_size.x / 12.0 - width * 0.5
		var height := 180.0 + float((tower * 71) % 430)
		var rect := Rect2(Vector2(x, 0), Vector2(width, height))
		draw_rect(rect, Color("152d36"), true)
		var roof_y := height
		var roof := PackedVector2Array([Vector2(x - 34, roof_y), Vector2(x + width + 34, roof_y), Vector2(x + width * 0.78, roof_y + 42), Vector2(x + width * 0.22, roof_y + 42)])
		draw_colored_polygon(roof, Color("203940"))
		draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[0]]), Color(PaperArt.FOLD, 0.09), 2.0, true)
		for window in maxi(1, int(height / 86.0)):
			var wy := 48.0 + window * 72.0
			draw_rect(Rect2(Vector2(x + width * 0.33, wy), Vector2(width * 0.34, 18)), Color(PaperArt.GOLD, 0.08), true)
	for bridge in 5:
		var y := 310.0 + bridge * 205.0
		var points := PackedVector2Array()
		for segment in 17:
			var x := world_size.x * float(segment) / 16.0
			points.append(Vector2(x, y + absf(sin(segment * 0.42 + bridge)) * 42.0))
		draw_polyline(points, Color(PaperArt.FOLD, 0.025), 18.0, true)
		draw_polyline(points, Color(PaperArt.PAPER, 0.05), 2.0, true)
	for column in 8:
		var x := 180.0 + column * (world_size.x - 360.0) / 7.0
		draw_line(Vector2(x, 0), Vector2(x + sin(column) * 90.0, world_size.y), Color(PaperArt.FOLD, 0.015), 46.0, true)
	for seal in 34:
		var p := _seeded_point(seal, 421, 277, 90.0)
		var size := 8.0 + seal % 3 * 5.0
		draw_rect(Rect2(p - Vector2.ONE * size, Vector2.ONE * size * 2.0), Color(PaperArt.GOLD, 0.035), false, 2.0, true)


func _draw_sun_court() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color("1b2427"), true)
	var sun_center := Vector2(world_size.x * 0.5, world_size.y * 0.40)
	for ray in 32:
		var angle := float(ray) * TAU / 32.0
		var inner := 260.0 + float(ray % 3) * 20.0
		var outer := 1320.0
		var half_width := 0.018 + float(ray % 2) * 0.008
		var shape := PackedVector2Array([
			sun_center + Vector2.from_angle(angle - half_width) * inner,
			sun_center + Vector2.from_angle(angle - half_width * 0.35) * outer,
			sun_center + Vector2.from_angle(angle + half_width * 0.35) * outer,
			sun_center + Vector2.from_angle(angle + half_width) * inner,
		])
		draw_colored_polygon(shape, Color(0.86, 0.54 + float(ray % 3) * 0.04, 0.26, 0.020 + float(ray % 2) * 0.014))
	for ring in range(8, 0, -1):
		var radius := 150.0 + ring * 65.0
		draw_circle(sun_center, radius, Color(0.34, 0.14, 0.12, 0.018 + float(8 - ring) * 0.006))
		draw_arc(sun_center, radius, -PI + ring * 0.24, PI * 0.72 + ring * 0.24, 96, Color(0.88, 0.60, 0.32, 0.045 + ring * 0.005), 3.0, true)
	draw_circle(sun_center, 128.0, Color(0.008, 0.012, 0.026, 0.94))
	draw_arc(sun_center, 132.0, 0.0, TAU, 96, Color(0.88, 0.64, 0.34, 0.30), 5.0, true)
	for row in 5:
		for column in 10:
			var center := Vector2((column + 0.5) * world_size.x / 10.0, world_size.y * 0.70 + row * world_size.y * 0.30 / 5.0)
			var tile := PackedVector2Array([center + Vector2(-112,-54), center + Vector2(96,-68), center + Vector2(118,48), center + Vector2(-92,62)])
			draw_colored_polygon(tile, Color(0.58, 0.30, 0.16, 0.045 + float((row + column) % 2) * 0.014))
			draw_polyline(PackedVector2Array([tile[0], tile[1], tile[2], tile[3], tile[0]]), Color(0.86, 0.65, 0.34, 0.065), 1.4, true)


func _draw_paper_grain() -> void:
	var room_hash := absi(String(room_id).hash())
	for fleck in 48:
		var x := float(posmod(fleck * 347 + room_hash, maxi(1, int(world_size.x - 100.0)))) + 50.0
		var y := float(posmod(fleck * 193 + room_hash / 7, maxi(1, int(world_size.y - 100.0)))) + 50.0
		var color := Color(accent.r, accent.g, accent.b, 0.018 + float(fleck % 4) * 0.003)
		draw_line(Vector2(x - 5.0, y), Vector2(x + 5.0, y + float(fleck % 3) - 1.0), color, 1.0, true)


func _seeded_point(index: int, x_stride: int, y_stride: int, margin: float) -> Vector2:
	var room_hash := absi(String(room_id).hash())
	return Vector2(
		float(posmod(index * x_stride + room_hash, maxi(1, int(world_size.x - margin * 2.0)))) + margin,
		float(posmod(index * y_stride + room_hash / 11, maxi(1, int(world_size.y - margin * 2.0)))) + margin
	)
