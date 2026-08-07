class_name FoldlightPixelPlayableArenaFx
extends Node2D

var game: Node


func bind_game(game_node: Node) -> void:
	game = game_node
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_draw_room_terrain_feedback()
	_draw_fold_field()
	_draw_boss_cage()
	_draw_exit_gate()
	_draw_target_marker()


func _draw_room_terrain_feedback() -> void:
	if int(game.room_index) != 1:
		return
	var pulse := 0.55 + sin(float(game.elapsed_time) * 2.4) * 0.16
	# These overlays follow environmental landmarks already painted into room one.
	draw_arc(Vector2(217, 361), 72.0, 0.0, TAU, 48, Color(0.22, 0.96, 0.88, 0.34 * pulse), 3.0, false)
	draw_arc(Vector2(1090, 337), 116.0, -PI * 0.9, PI * 0.85, 44, Color(1.0, 0.24, 0.16, 0.27 * pulse), 4.0, false)


func _draw_fold_field() -> void:
	if not bool(game.folding) or not is_instance_valid(game.player):
		return
	var center: Vector2 = game.player.global_position
	var radius: float = float(game.get_fold_radius())
	var pulse := sin(float(game.elapsed_time) * 8.0) * 3.0
	for ring in 3:
		var ring_radius := radius - float(ring) * 9.0 + pulse * (1.0 - float(ring) * 0.22)
		draw_arc(center, ring_radius, 0.0, TAU, 72, Color(0.34, 0.98, 0.89, 0.56 - float(ring) * 0.12), 3.0, false)
	for slot in int(game.capture_capacity):
		var angle := -PI * 0.5 + TAU * float(slot) / float(maxi(1, int(game.capture_capacity)))
		var point := center + Vector2.from_angle(angle) * (radius + 12.0)
		var filled := slot < int(game.captured_count)
		var color := Color("ffd36c") if filled else Color(0.16, 0.42, 0.45, 0.72)
		var diamond := PackedVector2Array([point + Vector2(0, -5), point + Vector2(5, 0), point + Vector2(0, 5), point + Vector2(-5, 0)])
		draw_colored_polygon(diamond, color)


func _draw_boss_cage() -> void:
	if int(game.room_index) != 2 or float(game.arena_radius) >= 900.0:
		return
	var center: Vector2 = game.arena_center
	var radius: float = float(game.arena_radius)
	var pulse := 0.72 + sin(float(game.elapsed_time) * 4.0) * 0.18
	draw_arc(center, radius, 0.0, TAU, 96, Color(1.0, 0.25, 0.16, 0.62 * pulse), 5.0, false)
	for index in 28:
		var angle := TAU * float(index) / 28.0
		var radial := Vector2.from_angle(angle)
		var base := center + radial * radius
		var tangent := radial.orthogonal()
		var spike := PackedVector2Array([
			base - tangent * 6.0,
			base + tangent * 6.0,
			base - radial * (19.0 + float(index % 3) * 4.0),
		])
		draw_colored_polygon(spike, Color(0.96, 0.18 + float(index % 2) * 0.08, 0.11, 0.82))


func _draw_exit_gate() -> void:
	if not bool(game.gate_open):
		return
	var center: Vector2 = game.gate_position
	var pulse := 0.5 + sin(float(game.elapsed_time) * 5.0) * 0.5
	for ring in 4:
		draw_arc(center, 28.0 + float(ring) * 8.0 + pulse * 3.0, -PI * 0.7, PI * 0.7, 28, Color(0.25, 0.96, 0.85, 0.75 - float(ring) * 0.13), 4.0, false)
	draw_string(ThemeDB.fallback_font, center + Vector2(-58, 70), "进入 Boss 房", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color("f7e7b4"))


func _draw_target_marker() -> void:
	if not is_instance_valid(game.current_target):
		return
	var center: Vector2 = game.current_target.global_position
	var radius := 26.0 + sin(float(game.elapsed_time) * 6.0) * 2.0
	var color := Color(0.98, 0.76, 0.30, 0.74)
	for quarter in 4:
		var start := float(quarter) * PI * 0.5 + 0.16
		draw_arc(center, radius, start, start + 0.56, 7, color, 2.0, false)

