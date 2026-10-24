extends RefCounted
## Shared cut-paper silhouette for the title illustration and the playable moth.
## Geometry is kept in local coordinates so gameplay hitboxes remain independent.

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const INK := Palette.INK
const SEA := Palette.SURFACE
const PAPER := Palette.PAPER
const FOLD := Palette.FOLD
const GOLD := Palette.GOLD
const DANGER := Palette.DANGER


static func draw_moth(canvas: CanvasItem, origin: Vector2, scale_factor: float, wing: float = 1.0, flash: float = 0.0, detailed: bool = false) -> void:
	var paper := PAPER.lerp(Color.WHITE, flash * 0.75)
	var teal := FOLD.lerp(Color.WHITE, flash * 0.8)
	var shadow_offset := Vector2(2.6, 5.0) * scale_factor
	for side in [-1.0, 1.0]:
		var root := Vector2(side * 4.0, -12.0)
		var tip := Vector2(side * 57.0 * wing, -44.0)
		var elbow := Vector2(side * 45.0 * wing, -3.0)
		var lower := Vector2(side * 29.0 * wing, 20.0)
		var inner := Vector2(side * 7.0, 15.0)
		var fold := Vector2(side * 22.0 * wing, -11.0)
		var hind := PackedVector2Array([inner, Vector2(side * 32.0 * wing, 10.0), Vector2(side * 20.0 * wing, 39.0), Vector2(side * 10.0, 29.0), Vector2(0.0, 17.0)])
		var fore := PackedVector2Array([root, tip, elbow, lower, inner])
		_polygon(canvas, hind, origin + shadow_offset, scale_factor, Color(INK, 0.48))
		_polygon(canvas, fore, origin + shadow_offset, scale_factor, Color(INK, 0.52))
		_polygon(canvas, hind, origin, scale_factor, teal.darkened(0.22 if side < 0.0 else 0.38))
		_polygon(canvas, PackedVector2Array([hind[0], hind[2], hind[3]]), origin, scale_factor, paper.darkened(0.20))
		_polygon(canvas, fore, origin, scale_factor, paper.darkened(0.04 if side < 0.0 else 0.12))
		_polygon(canvas, PackedVector2Array([root, tip, fold]), origin, scale_factor, paper)
		_polygon(canvas, PackedVector2Array([tip, elbow, fold]), origin, scale_factor, teal.darkened(0.12 if side < 0.0 else 0.24))
		_polygon(canvas, PackedVector2Array([elbow, lower, fold]), origin, scale_factor, Color("a5bbb1").lerp(Color.WHITE, flash * 0.65))
		_polygon(canvas, PackedVector2Array([lower, inner, fold]), origin, scale_factor, paper.darkened(0.24))
		_line(canvas, root, tip, origin, scale_factor, Color(PAPER, 0.78), 0.28)
		_line(canvas, tip, fold, origin, scale_factor, Color(INK, 0.45), 0.32)
		_line(canvas, fold, inner, origin, scale_factor, Color(INK, 0.35), 0.32)
		_line(canvas, fold, lower, origin, scale_factor, Color(PAPER, 0.44), 0.24)
		_line(canvas, hind[0], hind[2], origin, scale_factor, Color(INK, 0.48), 0.32)
		if detailed:
			# Inset foil seams make large illustrations feel printed and folded.
			_line(canvas, root.lerp(tip, 0.20) + Vector2(0, 2.8), tip.lerp(fold, 0.12), origin, scale_factor, Color(GOLD, 0.70), 0.17)
			_line(canvas, elbow.lerp(tip, 0.18), fold.lerp(tip, 0.18), origin, scale_factor, Color(PAPER, 0.35), 0.17)
			for mark in 3:
				var point := fold.lerp(lower, 0.24 + float(mark) * 0.18)
				_line(canvas, point, point + Vector2(side * 3.0, -0.8), origin, scale_factor, Color(INK, 0.22), 0.15)
		var antenna := PackedVector2Array([Vector2(side * 2.5, -23.0), Vector2(side * 7.0, -33.0), Vector2(side * 11.0, -35.0)])
		canvas.draw_polyline(_transform(antenna, origin, scale_factor), Color(GOLD, 0.9), maxf(0.8, scale_factor * 0.4), true)
	var body := PackedVector2Array([Vector2(0, -28), Vector2(7, -9), Vector2(0, 31), Vector2(-7, -9)])
	_polygon(canvas, body, origin, scale_factor, teal)
	_polygon(canvas, PackedVector2Array([body[0], body[1], body[2]]), origin, scale_factor, paper)
	_line(canvas, body[0], body[2], origin, scale_factor, Color(INK, 0.55), 0.38)
	canvas.draw_circle(origin + Vector2(0, -10) * scale_factor, maxf(2.2, 2.2 * scale_factor), GOLD)


static func draw_tide(canvas: CanvasItem, bounds: Vector2, time: float, layers: int = 5, contrast: float = 1.0) -> void:
	# Each contour is a closed, overlapping sheet. Fine edge shadows give depth
	# without bright bands behind the bullets or gradients that mask silhouettes.
	for layer in layers:
		var contour := PackedVector2Array()
		var depth := float(layer) / float(maxi(layers - 1, 1))
		for step in 25:
			var x := bounds.x * float(step) / 24.0
			var wave := sin(float(step) * 0.23 + float(layer) * 0.75 + time * 0.025) * bounds.y * 0.045
			var ripple := sin(float(step) * 0.61 + float(layer) * 1.8) * bounds.y * 0.012
			var y := bounds.y * (0.61 + depth * 0.32) + wave + ripple - pow(float(step) / 24.0, 2.0) * bounds.y * 0.18
			contour.append(Vector2(x, y))
		var sheet := contour.duplicate()
		sheet.append(bounds + Vector2(12, 12))
		sheet.append(Vector2(-12, bounds.y + 12))
		var tint := SEA.lerp(INK, depth * 0.72)
		canvas.draw_colored_polygon(sheet, Color(tint, contrast))
		canvas.draw_polyline(contour, Color(INK, 0.38 * contrast), 7.0, true)
		canvas.draw_polyline(contour, Color(FOLD, (0.035 + depth * 0.018) * contrast), 1.0, true)


static func _polygon(canvas: CanvasItem, points: PackedVector2Array, origin: Vector2, scale_factor: float, color: Color) -> void:
	canvas.draw_colored_polygon(_transform(points, origin, scale_factor), color)


static func _line(canvas: CanvasItem, start: Vector2, end: Vector2, origin: Vector2, scale_factor: float, color: Color, width: float) -> void:
	canvas.draw_line(origin + start * scale_factor, origin + end * scale_factor, color, maxf(0.8, scale_factor * width), true)


static func _transform(points: PackedVector2Array, origin: Vector2, scale_factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(origin + point * scale_factor)
	return result
