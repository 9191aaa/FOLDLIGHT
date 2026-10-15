class_name FoldlightRogueVisualCanvas
extends Control

const PaperArt = preload("res://scripts/visuals/paper_art.gd")

var screen_kind: StringName = &"title"
var accent: Color = FoldlightRogueUITheme.FOLD
var _time: float = 0.0
var _damage_flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_damage_flash = maxf(0.0, _damage_flash - maxf(0.0, delta) * 4.8)
	queue_redraw()


func configure(kind: StringName, new_accent: Color = FoldlightRogueUITheme.FOLD) -> void:
	screen_kind = kind
	accent = FoldlightRogueUITheme.comfort_accent(new_accent)
	queue_redraw()


func flash_player_damage() -> void:
	_damage_flash = 1.0
	queue_redraw()


func get_damage_flash_strength() -> float:
	return _damage_flash


func _draw() -> void:
	var viewport_size := size
	if screen_kind in [&"title", &"result", &"prologue_result"]:
		_draw_full_bleed(viewport_size)
	elif screen_kind in [&"reward", &"route", &"pause", &"mechanic_intro"]:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(PaperArt.INK, 0.94), true)
		_draw_edge_folds(viewport_size, 0.34)
	else:
		_draw_hud_frame(viewport_size)
	if _damage_flash > 0.0:
		_draw_damage_flash(viewport_size)


func _draw_damage_flash(viewport_size: Vector2) -> void:
	# Coral stays on the screen edge; the playfield and hazard colors stay clear.
	var strength := _damage_flash * _damage_flash
	for inset in 6:
		var margin := float(inset) * 14.0
		var alpha := strength * (0.30 - float(inset) * 0.045)
		draw_rect(Rect2(Vector2(margin, margin), viewport_size - Vector2.ONE * margin * 2.0), Color(PaperArt.DANGER, maxf(0.0, alpha)), false, 12.0, true)


func _draw_full_bleed(viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), PaperArt.INK, true)
	var unit := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	var center := Vector2(viewport_size.x * 0.717, viewport_size.y * 0.456)
	var moon_radius := 248.0 * unit
	# A dark, layered aperture holds the illustration. Its thin rim is quieter
	# than the paper itself and stays entirely outside the menu's reading column.
	draw_circle(center + Vector2(16, 20) * unit, moon_radius + 17.0 * unit, Color(0.016, 0.052, 0.068, 0.55))
	draw_circle(center, moon_radius, Color("102a34"))
	draw_circle(center - Vector2(13, 10) * unit, moon_radius - 19.0 * unit, Color("132e37"))
	draw_arc(center, moon_radius + 7.0 * unit, -PI * 0.86, PI * 0.28, 80, Color(PaperArt.GOLD, 0.22), 1.0, true)
	draw_arc(center, moon_radius + 22.0 * unit, PI * 0.35, PI * 0.96, 48, Color(PaperArt.FOLD, 0.12), 1.0, true)
	PaperArt.draw_tide(self, viewport_size, _time, 7)
	_draw_chart_routes(viewport_size, unit)
	# The same folded silhouette is used at player scale in combat.
	var bob := sin(_time * 0.72) * 7.0 * unit
	PaperArt.draw_moth(self, center + Vector2(0, bob), 5.5 * unit, 1.0 + sin(_time * 0.58) * 0.018, 0.0, true)
	# Sparse paper shards carry the eye toward the sea without a particle veil.
	for index in 5:
		var p := Vector2(viewport_size.x * (0.66 + float(index) * 0.035), viewport_size.y * (0.73 + float(index % 3) * 0.043))
		p.y += sin(_time * 0.45 + float(index)) * 6.0 * unit
		var length := (7.0 + float(index % 3) * 4.0) * unit
		var shard := _diamond(p, -0.48 + float(index) * 0.32, length, length * 0.23)
		draw_colored_polygon(shard, Color(PaperArt.PAPER, 0.16 + float(index % 2) * 0.14))
	# Flat ink over the left gives every title/menu state a stable contrast floor.
	var fade_start := viewport_size.x * 0.39
	var fade_end := viewport_size.x * 0.516
	draw_polygon(PackedVector2Array([
		Vector2(fade_start, 0), Vector2(fade_end, 0),
		Vector2(fade_end, viewport_size.y), Vector2(fade_start, viewport_size.y),
	]), PackedColorArray([
		Color(PaperArt.INK, 0.70), Color(PaperArt.INK, 0.0),
		Color(PaperArt.INK, 0.0), Color(PaperArt.INK, 0.70),
	]))
	draw_rect(Rect2(Vector2.ZERO, Vector2(viewport_size.x * 0.39, viewport_size.y)), Color(PaperArt.INK, 0.70), true)
	_draw_edge_folds(viewport_size, 0.13)


func _draw_chart_routes(viewport_size: Vector2, unit: float) -> void:
	var route := PackedVector2Array([
		Vector2(viewport_size.x * 0.56, viewport_size.y * 0.92),
		Vector2(viewport_size.x * 0.64, viewport_size.y * 0.80),
		Vector2(viewport_size.x * 0.83, viewport_size.y * 0.73),
		Vector2(viewport_size.x * 0.87, viewport_size.y * 0.54),
		Vector2(viewport_size.x * 0.93, viewport_size.y * 0.40),
		Vector2(viewport_size.x * 0.89, viewport_size.y * 0.17),
	])
	draw_polyline(route, Color(PaperArt.GOLD, 0.23), 1.0, true)
	for index in route.size():
		var p := route[index]
		draw_circle(p, 4.5 * unit, PaperArt.INK)
		draw_circle(p, 4.5 * unit, Color(PaperArt.GOLD, 0.46), false, 1.0, true)
		if index == 2 or index == 4:
			draw_circle(p, 1.8 * unit, Color(PaperArt.PAPER, 0.70))


func _draw_edge_folds(viewport_size: Vector2, alpha: float) -> void:
	draw_line(Vector2(44, 44), Vector2(100, 44), Color(accent, alpha), 1.0, true)
	draw_line(Vector2(44, 44), Vector2(44, 94), Color(accent, alpha), 1.0, true)
	draw_line(Vector2(viewport_size.x - 44, viewport_size.y - 44), Vector2(viewport_size.x - 100, viewport_size.y - 44), Color(accent, alpha), 1.0, true)
	draw_line(Vector2(viewport_size.x - 44, viewport_size.y - 44), Vector2(viewport_size.x - 44, viewport_size.y - 94), Color(accent, alpha), 1.0, true)


func _draw_hud_frame(viewport_size: Vector2) -> void:
	var color := Color(accent.r, accent.g, accent.b, 0.38)
	draw_line(Vector2(34, 34), Vector2(360, 34), color, 2.0, true)
	draw_line(Vector2(34, 34), Vector2(34, 130), color, 2.0, true)
	draw_line(Vector2(viewport_size.x - 34, viewport_size.y - 34), Vector2(viewport_size.x - 390, viewport_size.y - 34), color, 2.0, true)
	draw_line(Vector2(viewport_size.x - 34, viewport_size.y - 34), Vector2(viewport_size.x - 34, viewport_size.y - 132), color, 2.0, true)


func _diamond(center: Vector2, angle: float, length: float, width: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle)
	var side := forward.rotated(PI * 0.5)
	return PackedVector2Array([center + forward * length, center + side * width, center - forward * length, center - side * width])
