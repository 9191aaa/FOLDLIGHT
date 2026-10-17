extends RefCounted

const Palette = preload("res://scripts/ui/foldlight_theme.gd")


static func color_for(category: StringName) -> Color:
	if category in [&"combat", &"elite"]: return Palette.DANGER
	if category in [&"boss", &"shop", &"cache"]: return Palette.GOLD
	if category == &"event": return Palette.PAPER
	return Palette.FOLD


static func draw(canvas: CanvasItem, center: Vector2, category: StringName, unit: float, opacity: float = 1.0) -> void:
	var color := color_for(category)
	var ink := Color(Palette.INK, opacity)
	var bright := Color(color.lerp(Palette.PAPER, 0.28), opacity)
	var middle := Color(color.darkened(0.26), opacity)
	var shade := Color(Palette.SURFACE_SOFT.lerp(color, 0.18), opacity)
	match category:
		&"combat", &"elite":
			for index in (4 if category == &"elite" else 3):
				var x := (float(index) - (1.5 if category == &"elite" else 1.0)) * 22.0
				var height := 54.0 if index == 1 else (39.0 if index % 2 == 0 else 31.0)
				var origin := center + Vector2(x, 12) * unit
				_facet(canvas, origin, unit, [Vector2(-15, 0), Vector2(3, -height), Vector2(2, 4)], middle)
				_facet(canvas, origin, unit, [Vector2(3, -height), Vector2(19, -1), Vector2(2, 4)], bright)
				canvas.draw_line(origin + Vector2(3, -height) * unit, origin + Vector2(2, 4) * unit, Color(Palette.PAPER, opacity * 0.55), 1.2, true)
		&"boss":
			var core := center - Vector2(0, 14) * unit
			canvas.draw_circle(core, 33 * unit, ink)
			for index in 8:
				var ray := Vector2.from_angle(float(index) * TAU / 8.0)
				canvas.draw_colored_polygon(PackedVector2Array([core + ray * 36 * unit, core + ray.rotated(0.11) * 48 * unit, core + ray * 58 * unit, core + ray.rotated(-0.11) * 48 * unit]), middle if index % 2 else bright)
			canvas.draw_arc(core, 33 * unit, 0, TAU, 48, bright, 2.3, true)
			canvas.draw_arc(core, 24 * unit, -PI * 0.7, PI * 0.35, 28, Color(color, opacity * 0.4), 1.0, true)
			_facet(canvas, center + Vector2(0, 31) * unit, unit, [Vector2(-44, 0), Vector2(0, -12), Vector2(44, 0), Vector2(0, 7)], shade)
		&"shop", &"forge":
			_facet(canvas, center, unit, [Vector2(-33, -5), Vector2(0, -39), Vector2(36, -5)], bright)
			_facet(canvas, center, unit, [Vector2(-33, -5), Vector2(-3, -16), Vector2(0, -39)], middle)
			_facet(canvas, center, unit, [Vector2(-24, -4), Vector2(25, -4), Vector2(25, 22), Vector2(-24, 22)], shade)
			canvas.draw_line(center + Vector2(-24, -4) * unit, center + Vector2(-24, 22) * unit, bright, 1.5, true)
			canvas.draw_line(center + Vector2(25, -4) * unit, center + Vector2(25, 22) * unit, bright, 1.5, true)
			if category == &"forge":
				_facet(canvas, center, unit, [Vector2(-16, 5), Vector2(19, 5), Vector2(11, 12), Vector2(-12, 12)], bright)
				canvas.draw_line(center + Vector2(0, 10) * unit, center + Vector2(0, 24) * unit, middle, 5 * unit, true)
			else:
				for index in 3:
					var lamp := center + Vector2(-15 + index * 15, 7) * unit
					canvas.draw_line(lamp - Vector2(0, 12) * unit, lamp, middle, 1.2, true)
					canvas.draw_circle(lamp, 3 * unit, bright)
		&"cache":
			_facet(canvas, center, unit, [Vector2(-28, -12), Vector2(0, -28), Vector2(29, -12), Vector2(0, 4)], bright)
			_facet(canvas, center, unit, [Vector2(-28, -12), Vector2(0, 4), Vector2(0, 30), Vector2(-28, 12)], middle)
			_facet(canvas, center, unit, [Vector2(0, 4), Vector2(29, -12), Vector2(29, 12), Vector2(0, 30)], shade)
			canvas.draw_line(center + Vector2(0, -28) * unit, center + Vector2(0, 30) * unit, Color(Palette.PAPER, opacity * 0.75), 1.5, true)
		&"event":
			var core := center - Vector2(0, 8) * unit
			canvas.draw_arc(core, 29 * unit, -PI * 0.85, PI * 0.65, 36, bright, 2.2, true)
			canvas.draw_arc(core, 37 * unit, -PI * 0.28, PI * 0.53, 24, middle, 2.5, true)
			_facet(canvas, core, unit, [Vector2(-26, 25), Vector2(7, -20), Vector2(2, 5)], bright)
			_facet(canvas, core, unit, [Vector2(-26, 25), Vector2(2, 5), Vector2(29, -21)], middle)
			canvas.draw_circle(core, 3.5 * unit, Color(Palette.GOLD, opacity))
		_:
			_facet(canvas, center, unit, [Vector2(0, -46), Vector2(-20, -15), Vector2(-14, 20), Vector2(0, 34)], shade)
			_facet(canvas, center, unit, [Vector2(0, -46), Vector2(20, -15), Vector2(14, 20), Vector2(0, 34)], middle)
			_facet(canvas, center, unit, [Vector2(0, -24), Vector2(-8, -7), Vector2(0, 16), Vector2(8, -7)], bright)
			canvas.draw_line(center + Vector2(0, -46) * unit, center + Vector2(0, 34) * unit, Color(Palette.PAPER, opacity * 0.55), 1.1, true)
			canvas.draw_line(center + Vector2(-14, 20) * unit, center + Vector2(14, 20) * unit, bright, 1.5, true)


static func _facet(canvas: CanvasItem, center: Vector2, unit: float, points: Array[Vector2], color: Color) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(center + point * unit)
	canvas.draw_colored_polygon(polygon, color)
