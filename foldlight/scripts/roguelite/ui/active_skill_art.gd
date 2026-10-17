extends RefCounted
## The same six folded silhouettes identify skills on cards, the collection,
## and the single combat action. No timers, textures, or gameplay state.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")

static func draw_icon(canvas: CanvasItem, id: StringName, center: Vector2, radius: float, accent: Color, opacity: float = 1.0) -> void:
	var paper := Palette.PAPER.lerp(accent, 0.12)
	var shadow := accent.darkened(0.48)
	match id:
		&"paper_burst":
			for index in 6:
				var angle := float(index) * TAU / 6.0
				var direction := Vector2.from_angle(angle)
				_facet(canvas, center, radius, PackedVector2Array([direction * 0.24, direction * 1.0, direction * 0.57 + direction.orthogonal() * 0.26]), paper if index % 2 == 0 else accent, opacity)
		&"mirror_step":
			for side in [-1.0, 1.0]:
				_facet(canvas, center, radius, PackedVector2Array([Vector2(side * 0.1, -0.65), Vector2(side * 1.0, -0.95), Vector2(side * 0.62, 0.26), Vector2(side * 0.13, 0.70)]), paper if side < 0 else shadow, opacity)
				_facet(canvas, center, radius, PackedVector2Array([Vector2(side * 0.13, 0.70), Vector2(side * 0.62, 0.26), Vector2(side * 0.84, 0.85)]), accent, opacity)
		&"ink_wash":
			_facet(canvas, center, radius, PackedVector2Array([Vector2(0, -1), Vector2(-0.73, 0.15), Vector2(-0.4, 0.85), Vector2(0, 1), Vector2(0.7, 0.2)]), accent, opacity)
			_facet(canvas, center, radius, PackedVector2Array([Vector2(0, -1), Vector2(0.7, 0.2), Vector2(0, 1)]), paper, opacity)
			canvas.draw_line(center + Vector2(-0.6, 0.3) * radius, center + Vector2(0.4, 0.3) * radius, Color(shadow, opacity), maxf(1, radius * 0.06), true)
		&"crease_anchor":
			_facet(canvas, center, radius, PackedVector2Array([Vector2(-0.17, -0.9), Vector2(0.17, -0.9), Vector2(0.17, 0.2), Vector2(0.88, -0.05), Vector2(0, 1), Vector2(-0.88, -0.05), Vector2(-0.17, 0.2)]), accent, opacity)
			_facet(canvas, center, radius, PackedVector2Array([Vector2(0, -0.9), Vector2(0.17, -0.9), Vector2(0.17, 0.2), Vector2(0.88, -0.05), Vector2(0, 1)]), paper, opacity)
		&"tide_clock":
			for side in [-1.0, 1.0]:
				_facet(canvas, center, radius, PackedVector2Array([Vector2(-0.65, side * 0.9), Vector2(0.65, side * 0.9), Vector2(0, 0)]), paper if side < 0 else shadow, opacity)
			canvas.draw_line(center + Vector2(-0.74, -0.95) * radius, center + Vector2(0.74, -0.95) * radius, Color(accent, opacity), maxf(1, radius * 0.08), true)
			canvas.draw_line(center + Vector2(-0.74, 0.95) * radius, center + Vector2(0.74, 0.95) * radius, Color(accent, opacity), maxf(1, radius * 0.08), true)
		&"sun_stamp":
			for index in 8:
				var angle := float(index) * TAU / 8.0
				var direction := Vector2.from_angle(angle)
				_facet(canvas, center, radius, PackedVector2Array([direction * 0.64 - direction.orthogonal() * 0.16, direction, direction * 0.64 + direction.orthogonal() * 0.16]), accent, opacity)
			_facet(canvas, center, radius, PackedVector2Array([Vector2(0, -0.55), Vector2(0.55, 0), Vector2(0, 0.55), Vector2(-0.55, 0)]), paper, opacity)
		_:
			canvas.draw_arc(center, radius * 0.7, 0, TAU, 24, Color(Palette.MUTED, opacity * 0.6), 1.5, true)

static func _facet(canvas: CanvasItem, center: Vector2, radius: float, points: PackedVector2Array, color: Color, opacity: float) -> void:
	var transformed := PackedVector2Array()
	for point in points: transformed.append(center + point * radius)
	canvas.draw_colored_polygon(transformed, Color(color, opacity))
