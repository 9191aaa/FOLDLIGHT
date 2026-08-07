class_name FoldlightPixelPlayableVfx
extends Node2D

var bursts: Array[Dictionary] = []
var banner_text: String = ""
var banner_color := Color.WHITE
var banner_time: float = 0.0


func _process(delta: float) -> void:
	for index in range(bursts.size() - 1, -1, -1):
		var burst := bursts[index]
		burst.life = float(burst.get("life", 0.0)) - delta
		bursts[index] = burst
		if float(burst.life) <= 0.0:
			bursts.remove_at(index)
	banner_time = maxf(0.0, banner_time - delta)
	queue_redraw()


func add_hit(position: Vector2, color: Color = Color("f4d27a"), strength: float = 1.0) -> void:
	bursts.append({"position": position, "life": 0.28, "duration": 0.28, "color": color, "strength": strength, "kind": &"hit"})


func add_explosion(position: Vector2, color: Color = Color("ff7650"), strength: float = 1.0) -> void:
	bursts.append({"position": position, "life": 0.72, "duration": 0.72, "color": color, "strength": strength, "kind": &"explosion"})


func add_capture(position: Vector2) -> void:
	bursts.append({"position": position, "life": 0.42, "duration": 0.42, "color": Color("51f2d6"), "strength": 1.0, "kind": &"capture"})


func show_banner(text_value: String, color: Color = Color.WHITE, duration: float = 1.8) -> void:
	banner_text = text_value
	banner_color = color
	banner_time = duration


func _draw() -> void:
	for burst in bursts:
		_draw_burst(burst)
	if banner_time > 0.0 and not banner_text.is_empty():
		var alpha := clampf(banner_time / 0.35, 0.0, 1.0)
		var text_size := ThemeDB.fallback_font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
		var origin := Vector2(627.0 - text_size.x * 0.5, 132.0)
		draw_rect(Rect2(origin - Vector2(18, 31), text_size + Vector2(36, 44)), Color(0.01, 0.025, 0.035, 0.72 * alpha))
		draw_string(ThemeDB.fallback_font, origin, banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color(banner_color, alpha))


func _draw_burst(burst: Dictionary) -> void:
	var position := burst.get("position", Vector2.ZERO) as Vector2
	var life := float(burst.get("life", 0.0))
	var duration := maxf(0.01, float(burst.get("duration", 1.0)))
	var ratio := clampf(life / duration, 0.0, 1.0)
	var progress := 1.0 - ratio
	var color := burst.get("color", Color.WHITE) as Color
	var strength := float(burst.get("strength", 1.0))
	var kind := burst.get("kind", &"hit") as StringName
	var particle_count := 12 if kind == &"explosion" else 7
	var reach := (72.0 if kind == &"explosion" else 34.0) * strength
	for index in particle_count:
		var angle := float(index) * TAU / float(particle_count) + float(index % 3) * 0.21
		var point := position + Vector2.from_angle(angle) * reach * ease(progress, 0.55)
		var size := maxi(2, int(lerpf(8.0, 2.0, progress) * strength))
		var particle_color := Color(color, ratio)
		if kind == &"capture":
			var diamond := PackedVector2Array([point + Vector2(0, -size), point + Vector2(size, 0), point + Vector2(0, size), point + Vector2(-size, 0)])
			draw_colored_polygon(diamond, particle_color)
		else:
			draw_rect(Rect2(point - Vector2(size, size) * 0.5, Vector2(size, size)), particle_color)
	draw_circle(position, lerpf(7.0, reach * 0.8, progress), Color(color.r, color.g, color.b, ratio * 0.12))

