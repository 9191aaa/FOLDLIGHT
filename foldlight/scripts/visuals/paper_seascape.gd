extends RefCounted
## Submerged paper relief. No collision, gameplay RNG or frame-driven drawing.
const Art = preload("res://scripts/visuals/paper_art.gd")
const DrawBatch = preload("res://scripts/visuals/paper_draw_batch.gd")
const MAX_CACHED_MESHES: int = 12
const CANVAS_MESH_REFS: StringName = &"paper_ground_mesh_refs"
static var _mesh_cache: Dictionary = {}

static func draw_region(canvas: CanvasItem, bounds: Rect2, style: StringName, seed: int = 0) -> void:
	# Canvas drawing commands keep RIDs, not Resource ownership. Begin a fresh
	# retained set on each static redraw; later districts/foundations append to it.
	canvas.set_meta(CANVAS_MESH_REFS, [])
	var key := "region:%s:%s:%d" % [bounds, style, seed]
	var mesh := _mesh_cache.get(key) as ArrayMesh
	if mesh == null:
		var batch := DrawBatch.new()
		_draw_region_commands(batch, bounds, style, seed)
		mesh = _remember_mesh(key, batch.build_mesh())
	canvas.draw_set_transform(Vector2.ZERO)
	_draw_retained(canvas, mesh)

static func draw_landmark(canvas: CanvasItem, center: Vector2, size: Vector2, style: StringName, seed: int = 0) -> void:
	var key := "landmark:%s:%s:%s:%d" % [center, size, style, seed]
	var mesh := _mesh_cache.get(key) as ArrayMesh
	if mesh == null:
		var batch := DrawBatch.new()
		_draw_landmark_commands(batch, center, size, style, seed)
		mesh = _remember_mesh(key, batch.build_mesh())
	_draw_retained(canvas, mesh)

static func draw_foundations(canvas: CanvasItem, placements: Array[Dictionary], style: StringName) -> void:
	var batch := DrawBatch.new()
	_draw_foundation_commands(batch, placements, style)
	var mesh := batch.build_mesh()
	if mesh.get_surface_count() > 0:
		_draw_retained(canvas, mesh)

static func draw_district(canvas: CanvasItem, bounds: Rect2, style: StringName, seed: int = 0) -> void:
	var key := "district:%s:%s:%d" % [bounds, style, seed]
	var mesh := _mesh_cache.get(key) as ArrayMesh
	if mesh == null:
		var batch := DrawBatch.new()
		_draw_district_commands(batch, bounds, style, seed)
		mesh = _remember_mesh(key, batch.build_mesh())
	_draw_retained(canvas, mesh)

static func _draw_retained(canvas: CanvasItem, mesh: ArrayMesh) -> void:
	var retained: Array = canvas.get_meta(CANVAS_MESH_REFS, [])
	retained.append(mesh)
	canvas.set_meta(CANVAS_MESH_REFS, retained)
	canvas.draw_mesh(mesh, null)

static func _remember_mesh(key: String, mesh: ArrayMesh) -> ArrayMesh:
	if _mesh_cache.size() >= MAX_CACHED_MESHES:
		_mesh_cache.erase(_mesh_cache.keys()[0])
	_mesh_cache[key] = mesh
	return mesh


static func canonical_style(style: StringName) -> StringName:
	if style in [&"ink_city", &"inverted_ink_city"]: return &"ink_city"
	if style in [&"sun_court", &"nameless_sun_court"]: return &"sun_court"
	return &"paper_reef"

static func _draw_region_commands(canvas, bounds: Rect2, style: StringName, seed: int = 0) -> void:
	var kind := canonical_style(style)
	var size := bounds.size
	canvas.draw_set_transform(bounds.position)
	var base := Color("0b2029")
	if kind == &"ink_city": base = Color("101e2a")
	elif kind == &"sun_court": base = Color("182426")
	canvas.draw_rect(Rect2(Vector2.ZERO, size), base, true)
	_draw_depth_sheets(canvas, size, kind, seed)
	match kind:
		&"ink_city": _draw_archive_floor(canvas, size, seed)
		&"sun_court": _draw_court_floor(canvas, size, seed)
		_: _draw_reef_floor(canvas, size, seed)
	_draw_fibres(canvas, size, kind, seed)
	_draw_edge_binding(canvas, size, kind)
	canvas.draw_set_transform(Vector2.ZERO)

static func _draw_landmark_commands(canvas, center: Vector2, size: Vector2, style: StringName, seed: int = 0) -> void:
	match canonical_style(style):
		&"ink_city": _archive_imprint(canvas, center, size, seed)
		&"sun_court": _sun_imprint(canvas, center, size, seed)
		_: _reef_imprint(canvas, center, size, seed)

static func _draw_foundation_commands(canvas, placements: Array[Dictionary], style: StringName) -> void:
	var kind := canonical_style(style)
	var tint := Color("4f807b") if kind == &"paper_reef" else Color("75818c")
	if kind == &"sun_court": tint = Color("ad9464")
	for placement in placements:
		var terrain_kind := int(placement.get("kind", -1))
		if terrain_kind not in [0, 1]: continue
		var center := Vector2(placement.get("position", Vector2.ZERO))
		var extent := Vector2(placement.get("size", Vector2.ZERO)) * 0.5
		canvas.draw_set_transform(center, float(placement.get("rotation", 0.0)))
		# Sediment has no hard outside rim which could imply a larger hitbox.
		if terrain_kind == 1:
			var radius := minf(extent.x, extent.y)
			for layer in 3:
				var fan := PackedVector2Array()
				for step in 17:
					var angle := float(step) * TAU / 16.0
					var reach := radius + 28.0 + float(layer) * 16.0 + sin(angle * 3.0) * 9.0
					fan.append(Vector2.from_angle(angle) * Vector2(reach * 1.25, reach * 0.82))
				canvas.draw_polyline(fan, Color(tint, 0.08 - float(layer) * 0.017), 2.0, true)
		else:
			var wash := PackedVector2Array([Vector2(-extent.x - 44, -extent.y - 11), Vector2(extent.x * 0.55, -extent.y - 21), Vector2(extent.x + 52, extent.y + 7), Vector2(extent.x * 0.28, extent.y + 43), Vector2(-extent.x - 14, extent.y + 28)])
			canvas.draw_colored_polygon(wash, Color(tint, 0.045))
			for seam in 3:
				var y := extent.y + 15.0 + float(seam) * 10.0
				canvas.draw_line(Vector2(-extent.x * 0.8, y), Vector2(extent.x * 0.78, y + 8), Color(tint, 0.075 - float(seam) * 0.014), 1.0, true)
	canvas.draw_set_transform(Vector2.ZERO)

static func _draw_district_commands(canvas, bounds: Rect2, style: StringName, seed: int = 0) -> void:
	var tint := Color("426e68")
	var kind := canonical_style(style)
	if kind == &"ink_city": tint = Color("646d83")
	elif kind == &"sun_court": tint = Color("8d7750")
	var center := bounds.get_center()
	# Loose contours join districts without drawing false rectangular walls.
	for layer in 3:
		var contour := PackedVector2Array()
		for point in 24:
			var angle := float(point) * TAU / 24.0
			var wave := 0.86 + sin(angle * 3.0 + float(seed % 19)) * 0.07
			contour.append(center + Vector2.from_angle(angle) * bounds.size * (0.41 + float(layer) * 0.025) * wave)
		canvas.draw_colored_polygon(contour, Color(tint, 0.025))
		contour.append(contour[0])
		canvas.draw_polyline(contour, Color(tint, 0.09), 1.5, true)
	_draw_landmark_commands(canvas, center, bounds.size * Vector2(0.66, 0.73), kind, seed)

static func _draw_depth_sheets(canvas, size: Vector2, kind: StringName, seed: int) -> void:
	var tint := Color("173640") if kind == &"paper_reef" else Color("1e3440")
	if kind == &"sun_court": tint = Color("303b37")
	var shift := float(posmod(seed, 17)) * 0.018
	for layer in 6:
		var contour := PackedVector2Array()
		for step in 35:
			var u := float(step) / 34.0
			var y := size.y * (0.12 + float(layer) * 0.16 + sin(u * 5.0 + float(layer) * 0.6 + shift) * 0.075 - u * 0.065)
			contour.append(Vector2(u * size.x, y))
		var sheet := contour.duplicate()
		sheet.append(size)
		sheet.append(Vector2(0, size.y))
		canvas.draw_colored_polygon(sheet, Color(tint.darkened(float(layer % 3) * 0.10), 0.22))
		canvas.draw_polyline(contour, Color(Art.INK, 0.28), 8.0, true)
		canvas.draw_polyline(contour, Color(tint.lightened(0.20), 0.15), 1.2, true)

static func _draw_reef_floor(canvas, size: Vector2, seed: int) -> void:
	_reef_imprint(canvas, size * Vector2(0.22, 0.45), size * Vector2(0.36, 0.56), seed)
	_reef_imprint(canvas, size * Vector2(0.76, 0.63), size * Vector2(0.36, 0.62), seed + 3)
	for ribbon in 4:
		var points := PackedVector2Array()
		for step in 33:
			var u := float(step) / 32.0
			points.append(Vector2(size.x * (0.05 + u * 0.91), size.y * (0.77 - u * 0.42) + sin(u * 9.0) * 24.0 + float(ribbon) * 14.0))
		canvas.draw_polyline(points, Color("5c8981", 0.065 - float(ribbon) * 0.009), 1.5, true)
	# A broken moon reflection belongs to the far shallows, not a hazard ring.
	var moon := size * Vector2(0.79, 0.17)
	for strip in 9:
		var y := float(strip - 4) * 14.0
		var half_width := sqrt(maxf(0.0, 90.0 * 90.0 - y * y))
		canvas.draw_line(moon + Vector2(-half_width, y), moon + Vector2(half_width * 0.74, y - 4.0), Color("899b86", 0.15 - float(strip % 3) * 0.025), 7.0, true)
	for shore in 6:
		var center := Vector2(size.x * (0.035 if shore % 2 == 0 else 0.965), size.y * (0.16 + float(shore / 2) * 0.34))
		_reef_imprint(canvas, center, Vector2(size.x * 0.19, size.y * 0.36), seed + shore * 7)

static func _reef_imprint(canvas, center: Vector2, size: Vector2, seed: int) -> void:
	var flip := -1.0 if seed % 2 == 0 else 1.0
	var spine := PackedVector2Array()
	for rib in 11:
		var u := float(rib) / 10.0
		spine.append(center + Vector2((u - 0.5) * size.x, sin(u * PI) * size.y * 0.13 * flip))
	# Broad flat folds read as fossils below water, without cast shadows or rims.
	for rib in 9:
		var u := (float(rib) + 0.5) / 9.0
		var root := spine[rib + 1]
		var reach := sin(u * PI) * size.y * 0.49
		for side: float in [-1.0, 1.0]:
			var tip := root + Vector2(size.x * (0.06 + u * 0.04), side * reach)
			var bend := root + Vector2(size.x * 0.11, side * reach * 0.40)
			var tail := root - Vector2(size.x * 0.07, 0)
			canvas.draw_colored_polygon(PackedVector2Array([tail, root, bend, tip]), Color("4d756f", 0.075 + float(rib % 3) * 0.016))
			canvas.draw_colored_polygon(PackedVector2Array([root, tip, bend]), Color("1c4148", 0.40))
			canvas.draw_line(root, tip, Color("71948a", 0.12), 1.5, true)
			canvas.draw_line(tip, bend, Color("88a69a", 0.065), 1.0, true)
	canvas.draw_polyline(spine, Color("0b1c25", 0.36), 9.0, true)
	canvas.draw_polyline(spine, Color("63867e", 0.15), 1.4, true)

static func _draw_archive_floor(canvas, size: Vector2, seed: int) -> void:
	_archive_imprint(canvas, size * Vector2(0.24, 0.39), size * Vector2(0.38, 0.58), seed)
	_archive_imprint(canvas, size * Vector2(0.76, 0.61), size * Vector2(0.38, 0.61), seed + 4)
	var axis_x := size.x * 0.50
	for band in 3:
		var x := axis_x + float(band - 1) * 19.0
		canvas.draw_line(Vector2(x - 80, 85), Vector2(x + 90, size.y - 90), Color("8c8798", 0.045 if band != 1 else 0.085), 1.4, true)
	for stitch in 13:
		var y := 150.0 + float(stitch) * (size.y - 300.0) / 12.0
		var x := axis_x - 80.0 + (y - 85.0) / (size.y - 175.0) * 170.0
		canvas.draw_polyline(PackedVector2Array([Vector2(x - 14, y - 8), Vector2(x + 14, y), Vector2(x - 14, y + 8)]), Color("a69a86", 0.07), 1.0, true)
	for group in 3:
		_archive_imprint(canvas, Vector2(size.x * (0.12 + float(group) * 0.38), size.y * 0.05), Vector2(size.x * 0.22, size.y * 0.33), seed + group + 9)

static func _archive_imprint(canvas, center: Vector2, size: Vector2, seed: int) -> void:
	var lean := -0.13 if seed % 2 == 0 else 0.13
	for page in 7:
		var u := float(page) / 6.0
		var x := center.x + (u - 0.5) * size.x * 0.83
		var height := size.y * (0.54 + sin(u * PI) * 0.34)
		var width := size.x * 0.105
		var top := Vector2(x - width * 0.5, center.y - height * 0.5)
		var drift := Vector2(height * lean, 0)
		var corners := PackedVector2Array([top, top + Vector2(width, 0), top + Vector2(width, height) + drift, top + Vector2(width * 0.5, height + 30) + drift, top + Vector2(0, height) + drift])
		canvas.draw_colored_polygon(corners, Color("627185", 0.075 + float(page % 2) * 0.035))
		canvas.draw_line(corners[0], corners[4], Color("b5a584", 0.10), 1.0, true)
		canvas.draw_line(corners[1], corners[2], Color("0b1723", 0.33), 5.0, true)
		for line in 4:
			var progress := 0.19 + float(line) * 0.14
			var at := top + Vector2(width * 0.22, height * progress) + drift * progress
			canvas.draw_line(at, at + Vector2(width * 0.52, 0), Color("b6ae97", 0.065), 3.0, true)
	for binding in 3:
		var y := center.y + float(binding - 1) * size.y * 0.27
		var points := PackedVector2Array()
		for step in 19:
			var u := float(step) / 18.0
			points.append(Vector2(center.x + (u - 0.5) * size.x, y + sin(u * PI) * size.y * 0.08))
		canvas.draw_polyline(points, Color("070f1b", 0.27), 17.0, true)
		canvas.draw_polyline(points, Color("789495", 0.10), 1.5, true)

static func _draw_court_floor(canvas, size: Vector2, seed: int) -> void:
	_sun_imprint(canvas, size * Vector2(0.60, 0.40), size * Vector2(0.57, 0.90), seed)
	for step in 11:
		var y := size.y * (0.28 + float(step) * 0.061)
		var width := size.x * (0.16 + float(step) * 0.013)
		var x := size.x * 0.36 - float(step) * 6.0
		var slab := PackedVector2Array([Vector2(x - width * 0.5, y), Vector2(x + width * 0.5, y - 24), Vector2(x + width * 0.48, y + 22), Vector2(x - width * 0.53, y + 42)])
		canvas.draw_colored_polygon(slab, Color("95835e", 0.047 + float(step % 2) * 0.018))
		canvas.draw_line(slab[0], slab[1], Color("d1b47d", 0.10), 1.3, true)
		canvas.draw_line(slab[3], slab[2], Color("111c20", 0.28), 4.0, true)
	for panel in 5:
		var top := Vector2(size.x * (0.08 + float(panel) * 0.22), size.y * 0.07)
		canvas.draw_polyline(PackedVector2Array([top + Vector2(-95, 150), top + Vector2(-70, 0), top + Vector2(80, -35), top + Vector2(104, 132)]), Color("aa9467", 0.12), 2.0, true)

static func _sun_imprint(canvas, center: Vector2, size: Vector2, seed: int) -> void:
	var radius := minf(size.x * 0.50, size.y * 0.61)
	var flatten := Vector2(1.0, 0.70)
	# Broken folded rays and missing wedges replace concentric hazard-like rings.
	for wedge in 12:
		if wedge in [2, 7]: continue
		var angle := float(wedge) * TAU / 12.0 + 0.12
		var inner := radius * 0.43
		var outer := radius * (0.90 + float(posmod(seed + wedge, 3)) * 0.045)
		var a := center + Vector2.from_angle(angle - 0.20) * inner * flatten
		var b := center + Vector2.from_angle(angle - 0.18) * outer * flatten
		var c := center + Vector2.from_angle(angle + 0.18) * outer * flatten
		var d := center + Vector2.from_angle(angle + 0.20) * inner * flatten
		var fold := center + Vector2.from_angle(angle) * outer * 0.78 * flatten
		canvas.draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color("a88d56", 0.085 + float(wedge % 3) * 0.016))
		canvas.draw_colored_polygon(PackedVector2Array([a, b, fold, d]), Color("071b23", 0.25))
		canvas.draw_line(b, c, Color("d4b378", 0.16), 1.7, true)
		canvas.draw_line(a, fold, Color("d4b378", 0.095), 1.0, true)
		canvas.draw_line(fold, center + Vector2.from_angle(angle) * radius * 1.16 * flatten, Color("a88d56", 0.07), 1.2, true)
	var iris := PackedVector2Array()
	for corner in 8:
		iris.append(center + Vector2.from_angle(float(corner) * TAU / 8.0 + PI / 8.0) * radius * 0.33 * flatten)
	canvas.draw_colored_polygon(iris, Color("0a1a20", 0.32))
	canvas.draw_polyline(_closed(iris), Color("a88d56", 0.12), 1.3, true)
	canvas.draw_line(iris[0], iris[4], Color("a88d56", 0.09), 1.0, true)

static func _draw_fibres(canvas, size: Vector2, kind: StringName, seed: int) -> void:
	var fibres := PackedVector2Array()
	var dark := PackedVector2Array()
	var count := clampi(int(size.x * size.y / 23000.0), 72, 260)
	for fibre in count:
		var x := float(posmod(fibre * 509 + seed, maxi(1, int(size.x - 100.0)))) + 50.0
		var y := float(posmod(fibre * 307 + seed / 7, maxi(1, int(size.y - 100.0)))) + 50.0
		var length := 12.0 + float(fibre % 5) * 8.0
		fibres.append(Vector2(x, y))
		fibres.append(Vector2(x + length, y - 2.0))
		if fibre % 3 == 0:
			dark.append(Vector2(x + 3, y + 4))
			dark.append(Vector2(x + length * 0.7, y + 3))
	var tint := Color("8ba89d") if kind == &"paper_reef" else Color("a39a89")
	canvas.draw_multiline(fibres, Color(tint, 0.035), 1.0, true)
	canvas.draw_multiline(dark, Color(Art.INK, 0.20), 1.0, true)

static func _draw_edge_binding(canvas, size: Vector2, kind: StringName) -> void:
	var tint := Color("54776e") if kind == &"paper_reef" else Color("857a64")
	for inset: float in [20.0, 27.0, 40.0]:
		canvas.draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), Color(tint, 0.11), false, 1.0, true)
	for side in 2:
		var y := 35.0 if side == 0 else size.y - 35.0
		for stitch in maxi(1, int(size.x / 160.0)):
			var x := 90.0 + float(stitch) * 160.0
			canvas.draw_line(Vector2(x - 6, y - 6), Vector2(x + 6, y + 6), Color(tint, 0.23), 1.3, true)

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not closed.is_empty(): closed.append(closed[0])
	return closed
