extends Node2D
## Only this small canvas is redrawn at 20 Hz; the full ground stays cached.
const Art = preload("res://scripts/visuals/paper_art.gd")
var world_size := Vector2(2880, 1620)
var style: StringName = &"paper_reef"
var phase: float = 0.0
var visual_seed: int = 0
var _observer: WeakRef
var redraw_count: int = 0

func configure(size: Vector2, new_style: StringName, seed_value: int) -> void:
	world_size = size
	style = new_style
	visual_seed = seed_value
	phase = 0.0
	queue_redraw()

func bind_observer(observer: Node2D) -> void:
	_observer = weakref(observer) if observer != null else null

func advance_to(time: float) -> void:
	phase = time
	queue_redraw()

func _draw() -> void:
	redraw_count += 1
	var tint := Color("82afa4")
	if style == &"ink_city": tint = Color("aaa6bc")
	elif style == &"sun_court": tint = Art.GOLD
	var camera := get_viewport().get_camera_2d()
	var visible_bounds := Rect2(Vector2.ZERO, world_size)
	if camera != null:
		var view_size := get_viewport_rect().size / camera.zoom
		visible_bounds = Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size).grow(160.0)
	# Long transparent glints cannot resemble bullets or pickups.
	for glint in 24:
		var anchor := Vector2(float(posmod(glint * 613 + visual_seed, maxi(1, int(world_size.x - 220)))) + 110.0, float(posmod(glint * 379 + visual_seed / 9, maxi(1, int(world_size.y - 220)))) + 110.0)
		if not visible_bounds.has_point(anchor): continue
		var travel := fposmod(phase * 0.09 + float(glint) * 0.173, 1.0)
		var alpha := sin(travel * PI) * (0.085 if style != &"sun_court" else 0.065)
		var points := PackedVector2Array()
		for step in 9:
			var u := float(step) / 8.0
			points.append(anchor + Vector2((u - 0.5) * (96 + glint % 4 * 24) + travel * 15.0, sin(u * PI) * 5.0 - travel * 11.0))
		draw_polyline(points, Color(tint, alpha), 1.2, true)
	var observer := _observer.get_ref() as Node2D if _observer != null else null
	if observer is CharacterBody2D:
		var body := observer as CharacterBody2D
		var strength := clampf(body.velocity.length() / 350.0, 0.0, 1.0)
		if strength > 0.1:
			var backward := -body.velocity.normalized()
			var side := backward.orthogonal()
			var origin := to_local(body.global_position)
			for seam in 2:
				var reach := 35.0 + float(seam) * 17.0
				draw_polyline(PackedVector2Array([origin + backward * reach - side * reach * 0.7, origin + backward * (reach + 8), origin + backward * reach + side * reach * 0.7]), Color(tint, strength * 0.055), 1.0, true)
