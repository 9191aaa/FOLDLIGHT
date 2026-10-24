extends RefCounted
## Compile a static paper drawing to one ordered, vertex-colored triangle surface.
## Alpha is kept per vertex; a thin transparent fringe replaces Canvas AA lines.
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _transform := Transform2D.IDENTITY


func draw_set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_transform = Transform2D(rotation, scale, 0.0, position)


func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		push_error("Paper ground contains an invalid polygon")
		return
	var offset := _vertices.size()
	for point in points:
		_vertex(point, color)
	for index in triangles:
		_indices.append(offset + index)


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, width, antialiased)


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	draw_polyline(PackedVector2Array([from, to]), color, width, antialiased)


func draw_multiline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	for pair in int(points.size() / 2):
		draw_line(points[pair * 2], points[pair * 2 + 1], color, width, antialiased)


func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	if points.size() < 2:
		return
	var offset := _vertices.size()
	var half_width := maxf(0.5, width * 0.5)
	var fringe := 0.6 if antialiased else 0.0
	var outer_color := Color(color, 0.0) if antialiased else color
	var closed := points.size() > 2 and points[0].is_equal_approx(points[-1])
	for index in points.size():
		var previous := points[maxi(0, index - 1)]
		var following := points[mini(points.size() - 1, index + 1)]
		if closed and index in [0, points.size() - 1]:
			previous = points[-2]
			following = points[1]
		var before := (points[index] - previous).normalized()
		var after := (following - points[index]).normalized()
		if before.is_zero_approx(): before = after
		if after.is_zero_approx(): after = before
		var normal := (before.orthogonal() + after.orthogonal()).normalized()
		var miter := normal / maxf(0.35, absf(normal.dot(after.orthogonal())))
		_vertex(points[index] + miter * (half_width + fringe), outer_color)
		_vertex(points[index] + miter * half_width, color)
		_vertex(points[index] - miter * half_width, color)
		_vertex(points[index] - miter * (half_width + fringe), outer_color)
	for segment in points.size() - 1:
		var a := offset + segment * 4
		var b := a + 4
		for band in 3:
			_indices.append_array(PackedInt32Array([a + band, b + band, b + band + 1, a + band, b + band + 1, a + band + 1]))


func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _vertex(point: Vector2, color: Color) -> void:
	var transformed := _transform * point
	_vertices.append(Vector3(transformed.x, transformed.y, 0.0))
	_colors.append(color)
