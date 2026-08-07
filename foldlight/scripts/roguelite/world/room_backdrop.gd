class_name FoldlightRoomBackdrop
extends Node2D

var world_size: Vector2 = Vector2(2880.0, 1620.0)
var accent: Color = Color(0.28, 0.84, 0.83)
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
			return {"style": style_id, "motifs": [&"inverted_skyline", &"hanging_bridges", &"seal_windows"], "base": Color(0.026, 0.028, 0.060)}
		&"sun_court":
			return {"style": style_id, "motifs": [&"eclipse_disc", &"radial_mosaic", &"processional_rays"], "base": Color(0.060, 0.040, 0.038)}
		_:
			return {"style": &"paper_reef", "motifs": [&"layered_tide_wash", &"folded_reef_silhouette", &"paper_moon", &"foam_stitches"], "base": Color("0d2630")}


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
	draw_rect(Rect2(Vector2(28, 28), world_size - Vector2(56, 56)), Color(accent.r, accent.g, accent.b, 0.28), false, 3.0, true)
	draw_rect(Rect2(Vector2(42, 42), world_size - Vector2(84, 84)), Color(1.0, 0.78, 0.38, 0.08), false, 1.0, true)


func _draw_paper_reef() -> void:
	# Broad layered paper washes keep the original 2.0 colour language while
	# removing the blocky prototype look.
	var tide_bands: Array[Color] = [
		Color("0d2630"), Color("102f38"), Color("12343d"),
		Color("143a42"), Color("12343d"), Color("102f38"),
	]
	draw_rect(Rect2(Vector2.ZERO, world_size), tide_bands[0], true)
	var band_height := world_size.y / float(tide_bands.size())
	for band_index in tide_bands.size():
		var top := float(band_index) * band_height
		var slant := 34.0 if band_index % 2 == 0 else -46.0
		# Generous vertical overlap prevents sub-pixel wedges from exposing the
		# canvas when neighbouring bands lean in opposite directions.
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, top + slant - 64.0),
			Vector2(world_size.x, top - slant - 64.0),
			Vector2(world_size.x, top + band_height - slant + 72.0),
			Vector2(0, top + band_height + slant + 72.0),
		]), tide_bands[band_index])

	# A paper moon and stepped reefs give the room a readable regional identity
	# without competing with cyan and black-gold projectile silhouettes.
	var moon := Vector2(world_size.x * (0.73 + float(absi(String(room_id).hash()) % 9) * 0.012), world_size.y * 0.21)
	draw_circle(moon + Vector2(18, 20), 104.0, Color(0.03, 0.08, 0.10, 0.54))
	draw_circle(moon, 92.0, Color("bcae88"))
	draw_circle(moon - Vector2(16, 14), 72.0, Color("f4e8c7"))
	# Close the entire contour. The previous partial highlight read as a missing
	# triangular sector at gameplay zoom even though the fill itself was intact.
	draw_arc(moon, 99.0, 0.0, TAU, 96, Color(0.55, 0.86, 0.80, 0.28), 3.0, true)
	for moon_fold in 4:
		var y := moon.y - 48.0 + moon_fold * 26.0
		var half_width := sqrt(maxf(0.0, 84.0 * 84.0 - pow(y - moon.y, 2.0)))
		draw_line(Vector2(moon.x - half_width, y), Vector2(moon.x + half_width, y), Color(0.42, 0.48, 0.42, 0.08), 2.0, true)
	var reef_width := world_size.x / 5.0
	for reef_index in 5:
		var reef_x := float(reef_index) * reef_width - 34.0 + float((reef_index % 2) * 22)
		var reef_height := 150.0 + float((reef_index * 37) % 86)
		_draw_folded_reef(Vector2(reef_x, 300.0 + float(reef_index % 2) * 38.0), reef_width + 90.0, reef_height, Color("142e37"), Color("3d5a60"))
		_draw_folded_reef(Vector2(reef_x - 70.0, world_size.y - 66.0), reef_width + 140.0, 180.0 + float(reef_index % 3) * 36.0, Color("0a2027"), Color("315957"))

	# Short foam stitches imply motion without turning the background into a grid.
	for stitch in 68:
		var p := _seeded_point(stitch, 251, 173, 76.0).round()
		var length := 10.0 + float(stitch % 5) * 8.0
		var alpha := 0.055 + float(stitch % 3) * 0.025
		draw_line(p, p + Vector2(length, sin(float(stitch)) * 4.0), Color(0.56, 0.86, 0.80, alpha), 2.0 + float(stitch % 2), true)

	# Torn paper seams replace continuous neon contours.
	for seam in 5:
		var y := world_size.y * (0.36 + float(seam) * 0.105)
		for tile in 18:
			if (tile + seam * 3) % 5 == 0:
				continue
			var x := float(tile) * world_size.x / 18.0 + float((seam % 2) * 26)
			draw_rect(Rect2(Vector2(x, y + float((tile * 11 + seam * 7) % 15)), Vector2(86.0 + float(tile % 3) * 24.0, 4.0)), Color(0.31, 0.63, 0.61, 0.075), true)


func _draw_folded_reef(origin: Vector2, width: float, height: float, fill: Color, edge: Color) -> void:
	var base_y := origin.y
	var reef := PackedVector2Array([
		Vector2(origin.x, base_y),
		Vector2(origin.x + width * 0.08, base_y - height * 0.34),
		Vector2(origin.x + width * 0.18, base_y - height * 0.48),
		Vector2(origin.x + width * 0.28, base_y - height * 0.92),
		Vector2(origin.x + width * 0.40, base_y - height * 0.57),
		Vector2(origin.x + width * 0.55, base_y - height),
		Vector2(origin.x + width * 0.68, base_y - height * 0.52),
		Vector2(origin.x + width * 0.84, base_y - height * 0.76),
		Vector2(origin.x + width, base_y),
	])
	draw_colored_polygon(reef, fill)
	for facet in 4:
		var x := origin.x + width * (0.18 + float(facet) * 0.19)
		draw_rect(Rect2(Vector2(x, base_y - 28.0 - float(facet % 2) * 18.0), Vector2(width * 0.10, 8.0)), Color(edge, 0.58), true)


func _draw_block_disc(center: Vector2, radius: int, color: Color, step: int) -> void:
	for y in range(-radius, radius + 1, step):
		var half_width := sqrt(maxf(0.0, float(radius * radius - y * y)))
		var snapped_width := floorf(half_width / float(step)) * float(step)
		draw_rect(Rect2(Vector2(center.x - snapped_width, center.y + float(y)), Vector2(snapped_width * 2.0, float(step))), color, true)


func _draw_ink_city() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.026, 0.028, 0.060), true)
	# The city hangs upside-down from the top edge: roofs, bridges and windows
	# form a strong vertical composition unique to region two.
	for tower in 13:
		var width := 120.0 + float(tower % 4) * 42.0
		var x := float(tower) * world_size.x / 12.0 - width * 0.5
		var height := 180.0 + float((tower * 71) % 430)
		var rect := Rect2(Vector2(x, 0), Vector2(width, height))
		draw_rect(rect, Color(0.052, 0.048, 0.090, 0.80), true)
		var roof_y := height
		var roof := PackedVector2Array([Vector2(x - 34, roof_y), Vector2(x + width + 34, roof_y), Vector2(x + width * 0.78, roof_y + 42), Vector2(x + width * 0.22, roof_y + 42)])
		draw_colored_polygon(roof, Color(0.12, 0.09, 0.17, 0.54))
		draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[0]]), Color(0.58, 0.45, 0.72, 0.16), 2.0, true)
		for window in maxi(1, int(height / 86.0)):
			var wy := 48.0 + window * 72.0
			draw_rect(Rect2(Vector2(x + width * 0.33, wy), Vector2(width * 0.34, 18)), Color(0.68, 0.52, 0.68, 0.10), true)
	for bridge in 5:
		var y := 310.0 + bridge * 205.0
		var points := PackedVector2Array()
		for segment in 17:
			var x := world_size.x * float(segment) / 16.0
			points.append(Vector2(x, y + absf(sin(segment * 0.42 + bridge)) * 42.0))
		draw_polyline(points, Color(0.42, 0.35, 0.58, 0.10), 18.0, true)
		draw_polyline(points, Color(0.68, 0.58, 0.74, 0.14), 2.0, true)
	for column in 8:
		var x := 180.0 + column * (world_size.x - 360.0) / 7.0
		draw_line(Vector2(x, 0), Vector2(x + sin(column) * 90.0, world_size.y), Color(0.40, 0.36, 0.58, 0.035), 46.0, true)
	for seal in 34:
		var p := _seeded_point(seal, 421, 277, 90.0)
		var size := 8.0 + seal % 3 * 5.0
		draw_rect(Rect2(p - Vector2.ONE * size, Vector2.ONE * size * 2.0), Color(0.70, 0.55, 0.72, 0.08), false, 2.0, true)


func _draw_sun_court() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.060, 0.040, 0.038), true)
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
	for fleck in 72:
		var x := float(posmod(fleck * 347 + room_hash, maxi(1, int(world_size.x - 100.0)))) + 50.0
		var y := float(posmod(fleck * 193 + room_hash / 7, maxi(1, int(world_size.y - 100.0)))) + 50.0
		var color := Color(accent.r, accent.g, accent.b, 0.025 + float(fleck % 4) * 0.009)
		draw_line(Vector2(x - 5.0, y), Vector2(x + 5.0, y + float(fleck % 3) - 1.0), color, 1.0, true)


func _seeded_point(index: int, x_stride: int, y_stride: int, margin: float) -> Vector2:
	var room_hash := absi(String(room_id).hash())
	return Vector2(
		float(posmod(index * x_stride + room_hash, maxi(1, int(world_size.x - margin * 2.0)))) + margin,
		float(posmod(index * y_stride + room_hash / 11, maxi(1, int(world_size.y - margin * 2.0)))) + margin
	)
