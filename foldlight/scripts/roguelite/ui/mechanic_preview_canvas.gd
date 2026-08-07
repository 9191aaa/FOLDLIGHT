class_name FoldlightMechanicPreviewCanvas
extends Control

## A lightweight, deterministic combat vignette used by first-encounter and
## boss briefings.  It deliberately redraws the game's authored silhouettes
## instead of instantiating live combat actors inside the UI.

var preview_kind: StringName = &"enemy"
var preview_id: StringName = &"unknown"
var attack_style: StringName = &"radial"
var accent: Color = FoldlightRogueUITheme.GOLD
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func configure(snapshot: Dictionary) -> void:
	preview_id = StringName(snapshot.get("preview_id", snapshot.get("content_id", &"unknown")))
	preview_kind = StringName(snapshot.get("preview_kind", _infer_preview_kind(preview_id)))
	attack_style = StringName(snapshot.get("attack_style", _default_attack_style(preview_id)))
	accent = FoldlightRogueUITheme.comfort_accent(Color(snapshot.get("accent", FoldlightRogueUITheme.GOLD)))
	_time = 0.0
	queue_redraw()


func get_preview_snapshot() -> Dictionary:
	return {
		"preview_kind": preview_kind,
		"preview_id": preview_id,
		"attack_style": attack_style,
		"animated": is_processing(),
		"cycle_progress": fmod(_time, 3.6) / 3.6,
		"shows_actor": true,
		"shows_attack": true,
	}


func _process(delta: float) -> void:
	_time += maxf(0.0, delta)
	queue_redraw()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.008, 0.020, 0.035, 0.98), true)
	for lane in 5:
		var y := size.y * (0.16 + float(lane) * 0.17)
		draw_line(Vector2(18.0, y), Vector2(size.x - 18.0, y), Color(accent, 0.055), 1.0, true)
	for seam in 4:
		var x := size.x * (0.16 + float(seam) * 0.22)
		draw_line(Vector2(x, 16.0), Vector2(x, size.y - 16.0), Color(0.55, 0.73, 0.72, 0.035), 1.0, true)
	var actor_center := Vector2(size.x * 0.35, size.y * 0.52)
	var player_center := Vector2(size.x * 0.79, size.y * 0.62)
	var cycle := fmod(_time, 3.6) / 3.6
	_draw_attack(actor_center, player_center, cycle)
	_draw_actor(actor_center, cycle)
	_draw_player_marker(player_center, cycle)
	_draw_timeline(cycle)
	draw_rect(bounds.grow(-1.5), Color(accent, 0.42), false, 2.0, true)


func _draw_attack(origin: Vector2, target: Vector2, cycle: float) -> void:
	match attack_style:
		&"aimed_volley", &"line_volley":
			_draw_aimed_volley(origin, target, cycle)
		&"summon", &"brood_summon":
			_draw_summon(origin, cycle)
		&"tether", &"ally_buff":
			_draw_tethers(origin, cycle)
		&"zone", &"ink_zone":
			_draw_zone(origin, target, cycle)
		&"shield", &"prism_shield":
			_draw_shield(origin, target, cycle)
		&"cross_cut", &"shear_cross":
			_draw_cross_cut(origin, target, cycle)
		&"tide_gap", &"reef_tide_pulse":
			_draw_tide_gap(origin, target, cycle)
		&"partitions", &"ink_partitions":
			_draw_partitions(origin, target, cycle)
		&"shrinking_frame", &"moving_safe_frame":
			_draw_shrinking_frame(origin, target, cycle)
		_:
			_draw_radial(origin, cycle)


func _draw_aimed_volley(origin: Vector2, target: Vector2, cycle: float) -> void:
	var direction := origin.direction_to(target)
	var telegraph := clampf(cycle / 0.42, 0.0, 1.0)
	var end := target + direction * 54.0
	draw_line(origin + direction * 42.0, end, Color(0.78, 0.28, 0.24, 0.10 + telegraph * 0.20), 10.0, true)
	draw_line(origin + direction * 42.0, end, Color(0.88, 0.68, 0.42, 0.32 + telegraph * 0.42), 2.0, true)
	if cycle < 0.38:
		return
	var travel := clampf((cycle - 0.38) / 0.48, 0.0, 1.0)
	for projectile in 5:
		var spread := float(projectile - 2) * 0.13
		var shot_direction := direction.rotated(spread)
		var point := origin + shot_direction * lerpf(46.0, origin.distance_to(target) + 80.0, fmod(travel + float(projectile) * 0.08, 1.0))
		_draw_projectile(point, shot_direction.angle(), true)


func _draw_summon(origin: Vector2, cycle: float) -> void:
	var pulse := clampf(cycle / 0.48, 0.0, 1.0)
	draw_arc(origin, 52.0, -PI * 0.5, -PI * 0.5 + TAU * pulse, 32, Color(0.82, 0.52, 0.30, 0.82), 5.0, true)
	var bloom := clampf((cycle - 0.38) / 0.32, 0.0, 1.0)
	for index in 2:
		var angle := PI * (0.22 + float(index) * 0.74)
		var point := origin + Vector2.from_angle(angle) * lerpf(20.0, 105.0, bloom)
		_draw_petal_enemy(point, 0.55 + bloom * 0.25)


func _draw_tethers(origin: Vector2, cycle: float) -> void:
	for index in 2:
		var ally := origin + Vector2(58.0, -82.0 if index == 0 else 84.0)
		draw_dashed_line(origin, ally, Color(0.82, 0.64, 0.31, 0.76), 3.0, 10.0, true)
		draw_circle(ally, 17.0 + sin(_time * 5.0 + index) * 2.0, Color(0.72, 0.48, 0.30, 0.20))
		_draw_petal_enemy(ally, 0.64)
		for chevron in 2:
			var ratio := fmod(cycle * 2.0 + float(chevron) * 0.42, 1.0)
			var point := origin.lerp(ally, ratio)
			draw_circle(point, 4.0, Color(0.92, 0.72, 0.34, 0.92))


func _draw_zone(origin: Vector2, target: Vector2, cycle: float) -> void:
	var telegraph := clampf(cycle / 0.46, 0.0, 1.0)
	draw_dashed_line(origin, target, Color(0.55, 0.48, 0.66, 0.46), 2.0, 10.0, true)
	var radius := lerpf(92.0, 46.0, telegraph)
	draw_circle(target, 58.0, Color(0.33, 0.20, 0.43, 0.08 + clampf((cycle - 0.42) * 2.5, 0.0, 0.18)))
	draw_arc(target, radius, 0.0, TAU, 42, Color(0.54, 0.44, 0.65, 0.72), 4.0, true)
	for mote in 5:
		var angle := float(mote) * TAU / 5.0 - _time * 0.6
		draw_circle(target + Vector2.from_angle(angle) * 37.0, 3.0, Color(0.68, 0.58, 0.76, 0.58))


func _draw_shield(origin: Vector2, target: Vector2, cycle: float) -> void:
	var facing := origin.direction_to(target)
	draw_arc(origin, 47.0, facing.angle() - 1.05, facing.angle() + 1.05, 28, Color(0.45, 0.77, 0.80, 0.92), 7.0, true)
	var return_progress := fmod(cycle * 1.8, 1.0)
	var point := target.lerp(origin + facing * 52.0, return_progress)
	_draw_projectile(point, target.direction_to(origin).angle(), true)
	if return_progress > 0.82:
		draw_arc(origin, 56.0 + (return_progress - 0.82) * 90.0, -PI, PI, 28, Color(0.85, 0.66, 0.34, 0.70), 4.0, true)


func _draw_cross_cut(origin: Vector2, target: Vector2, cycle: float) -> void:
	var direction := origin.direction_to(target)
	var side := direction.orthogonal()
	var telegraph_alpha := 0.22 + clampf(cycle / 0.42, 0.0, 1.0) * 0.48
	for axis: Vector2 in [direction, side]:
		draw_line(target - axis * 155.0, target + axis * 155.0, Color(0.70, 0.24, 0.22, telegraph_alpha * 0.42), 10.0, true)
		draw_line(target - axis * 155.0, target + axis * 155.0, Color(0.82, 0.61, 0.35, telegraph_alpha), 2.0, true)
	if cycle >= 0.42:
		var flight := clampf((cycle - 0.42) / 0.50, 0.0, 1.0)
		for axis: Vector2 in [direction, -direction, side, -side]:
			var point: Vector2 = target + axis * flight * 178.0
			_draw_blade(point, axis.angle())


func _draw_tide_gap(origin: Vector2, target: Vector2, cycle: float) -> void:
	var radius := lerpf(48.0, minf(size.x, size.y) * 0.44, fmod(cycle * 1.25, 1.0))
	var gap_angle := origin.direction_to(target).angle()
	var gap_half := 0.42
	var danger := Color(0.75, 0.45, 0.27, 0.80)
	draw_arc(origin, radius, gap_angle + gap_half, gap_angle + TAU - gap_half, 64, danger, 10.0, true)
	draw_line(origin + Vector2.from_angle(gap_angle - gap_half) * radius, origin + Vector2.from_angle(gap_angle) * (radius + 62.0), Color(0.37, 0.72, 0.68, 0.72), 3.0, true)
	draw_line(origin + Vector2.from_angle(gap_angle + gap_half) * radius, origin + Vector2.from_angle(gap_angle) * (radius + 62.0), Color(0.37, 0.72, 0.68, 0.72), 3.0, true)
	draw_arc(target, 24.0, 0.0, TAU, 24, Color(0.43, 0.83, 0.76, 0.66), 3.0, true)


func _draw_partitions(origin: Vector2, target: Vector2, cycle: float) -> void:
	for index in 3:
		var offset := fmod(cycle + float(index) * 0.33, 1.0)
		var x := lerpf(30.0, size.x - 30.0, offset)
		draw_rect(Rect2(Vector2(x - 7.0, 34.0), Vector2(14.0, size.y - 68.0)), Color(0.38, 0.25, 0.45, 0.28), true)
		draw_line(Vector2(x, 34.0), Vector2(x, size.y - 34.0), Color(0.61, 0.48, 0.66, 0.48), 2.0, true)
	_draw_radial(origin, cycle)
	draw_arc(target, 28.0, 0.0, TAU, 24, Color(0.40, 0.75, 0.70, 0.62), 3.0, true)


func _draw_shrinking_frame(origin: Vector2, target: Vector2, cycle: float) -> void:
	var close := 0.5 - absf(fmod(cycle * 1.6, 1.0) - 0.5)
	var frame_size := Vector2(250.0, 190.0).lerp(Vector2(128.0, 98.0), close * 2.0)
	var frame := Rect2(target - frame_size * 0.5, frame_size)
	draw_rect(frame, Color(0.74, 0.48, 0.27, 0.13), true)
	draw_rect(frame, Color(0.79, 0.58, 0.34, 0.84), false, 5.0, true)
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
		draw_circle(corner, 7.0, Color(0.85, 0.67, 0.40, 0.92))
	_draw_radial(origin, cycle)


func _draw_radial(origin: Vector2, cycle: float) -> void:
	var travel := fmod(cycle * 1.65, 1.0)
	for index in 8:
		var angle := float(index) * TAU / 8.0 + _time * 0.16
		var direction := Vector2.from_angle(angle)
		_draw_projectile(origin + direction * lerpf(46.0, 160.0, travel), angle, true)


func _draw_actor(center: Vector2, cycle: float) -> void:
	var breathe := sin(_time * (2.6 if preview_kind == &"boss" else 3.4))
	var scale_value := (1.25 if preview_kind == &"boss" else 1.0) * (1.0 + breathe * 0.025)
	draw_set_transform(center + Vector2(0.0, breathe * 3.0), breathe * 0.025, Vector2.ONE * scale_value)
	match preview_id:
		&"paper_turret": _draw_turret_body(cycle)
		&"brood_lantern": _draw_lantern_body()
		&"bell_binder": _draw_bell_body()
		&"ink_warden": _draw_warden_body()
		&"prism_bulwark": _draw_bulwark_body()
		&"shear_scribe": _draw_scribe_body()
		&"reef_crown_battery": _draw_reef_boss()
		&"inverted_archivist": _draw_archivist_boss()
		&"origami_judge": _draw_judge_boss()
		_: _draw_generic_body()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_turret_body(cycle: float) -> void:
	var points := PackedVector2Array([Vector2(0, -31), Vector2(34, 0), Vector2(0, 31), Vector2(-34, 0), Vector2(0, -31)])
	draw_colored_polygon(points.slice(0, 4), Color(0.07, 0.10, 0.16, 0.98))
	draw_polyline(points, Color(0.73, 0.36, 0.29), 5.0, true)
	draw_circle(Vector2.ZERO, 10.0 + sin(cycle * TAU) * 2.0, Color(0.86, 0.60, 0.36))


func _draw_lantern_body() -> void:
	var points := PackedVector2Array([Vector2(0, -35), Vector2(29, -7), Vector2(20, 30), Vector2(-20, 30), Vector2(-29, -7), Vector2(0, -35)])
	draw_colored_polygon(points.slice(0, 5), Color(0.11, 0.09, 0.15, 0.98))
	draw_polyline(points, Color(0.77, 0.55, 0.31), 5.0, true)
	draw_circle(Vector2.ZERO, 11.0, Color(0.85, 0.65, 0.34))


func _draw_bell_body() -> void:
	var points := PackedVector2Array([Vector2(-27, 23), Vector2(-18, -15), Vector2(0, -34), Vector2(18, -15), Vector2(27, 23)])
	draw_colored_polygon(points, Color(0.13, 0.12, 0.19, 0.98))
	draw_polyline(points, Color(0.80, 0.63, 0.32), 5.0, true)
	draw_line(Vector2(-30, 24), Vector2(30, 24), Color(0.88, 0.73, 0.42), 5.0, true)
	draw_circle(Vector2(0, 31), 6.0, Color(0.86, 0.60, 0.31))


func _draw_warden_body() -> void:
	var points := PackedVector2Array([Vector2(0, -34), Vector2(29, -10), Vector2(20, 30), Vector2(-20, 30), Vector2(-29, -10), Vector2(0, -34)])
	draw_colored_polygon(points.slice(0, 5), Color(0.10, 0.08, 0.16, 0.98))
	draw_polyline(points, Color(0.56, 0.46, 0.68), 5.0, true)
	draw_circle(Vector2.ZERO, 8.0, Color(0.72, 0.61, 0.78))
	for mote in 3:
		draw_circle(Vector2.from_angle(_time + mote * TAU / 3.0) * 42.0, 3.0, Color(0.67, 0.56, 0.74, 0.72))


func _draw_bulwark_body() -> void:
	var points := PackedVector2Array([Vector2(0, -32), Vector2(28, -15), Vector2(28, 18), Vector2(0, 34), Vector2(-28, 18), Vector2(-28, -15), Vector2(0, -32)])
	draw_colored_polygon(points.slice(0, 6), Color(0.06, 0.12, 0.18, 0.98))
	draw_polyline(points, Color(0.44, 0.76, 0.79), 4.0, true)
	draw_arc(Vector2.ZERO, 48.0, -1.05, 1.05, 24, Color(0.48, 0.79, 0.82), 7.0, true)


func _draw_scribe_body() -> void:
	var points := PackedVector2Array([Vector2(0, -38), Vector2(20, -6), Vector2(10, 34), Vector2(0, 22), Vector2(-10, 34), Vector2(-20, -6), Vector2(0, -38)])
	draw_colored_polygon(points.slice(0, 6), Color(0.08, 0.08, 0.14, 0.98))
	draw_polyline(points, Color(0.66, 0.49, 0.66), 4.0, true)
	draw_line(Vector2(-11, 0), Vector2(11, 0), Color(0.80, 0.58, 0.34), 3.0, true)


func _draw_reef_boss() -> void:
	var crown := PackedVector2Array([Vector2(-74, 34), Vector2(-65, -35), Vector2(-42, -58), Vector2(-20, -23), Vector2(0, -70), Vector2(20, -23), Vector2(43, -61), Vector2(67, -34), Vector2(74, 34)])
	draw_colored_polygon(crown, Color(0.42, 0.36, 0.28, 0.98))
	draw_polyline(crown, Color(0.48, 0.71, 0.68), 6.0, true)
	draw_rect(Rect2(Vector2(-28, -10), Vector2(56, 43)), Color(0.12, 0.08, 0.12), true)
	draw_circle(Vector2.ZERO, 10.0, Color(0.77, 0.57, 0.32))


func _draw_archivist_boss() -> void:
	draw_rect(Rect2(Vector2(-49, -42), Vector2(98, 84)), Color(0.11, 0.08, 0.15, 0.98), true)
	draw_rect(Rect2(Vector2(-49, -42), Vector2(98, 84)), Color(0.54, 0.43, 0.62), false, 6.0, true)
	draw_line(Vector2(0, -40), Vector2(0, 40), Color(0.70, 0.57, 0.75), 4.0, true)
	for page in 4:
		var point := Vector2.from_angle(_time * 0.5 + page * TAU / 4.0) * 68.0
		draw_rect(Rect2(point - Vector2(8, 5), Vector2(16, 10)), Color(0.65, 0.54, 0.70, 0.48), true)


func _draw_judge_boss() -> void:
	var judge := PackedVector2Array([Vector2(0, -56), Vector2(48, -21), Vector2(38, 47), Vector2(0, 29), Vector2(-38, 47), Vector2(-48, -21), Vector2(0, -56)])
	draw_colored_polygon(judge.slice(0, 6), Color(0.16, 0.09, 0.09, 0.98))
	draw_polyline(judge, Color(0.76, 0.51, 0.29), 6.0, true)
	draw_line(Vector2(0, -54), Vector2(0, 29), Color(0.82, 0.64, 0.38, 0.72), 3.0, true)


func _draw_generic_body() -> void:
	var points := PackedVector2Array()
	for index in 12:
		var radius := 34.0 if index % 2 == 0 else 16.0
		points.append(Vector2.from_angle(float(index) * TAU / 12.0) * radius)
	draw_colored_polygon(points, Color(0.10, 0.12, 0.17, 0.98))
	points.append(points[0])
	draw_polyline(points, accent, 4.0, true)
	draw_circle(Vector2.ZERO, 7.0, accent)


func _draw_player_marker(center: Vector2, cycle: float) -> void:
	var dodge := sin(cycle * TAU) * 10.0
	center.y += dodge
	draw_circle(center, 25.0, Color(0.34, 0.78, 0.73, 0.08))
	var moth := PackedVector2Array([center + Vector2(-17, 0), center + Vector2(-4, -12), center, center + Vector2(4, -12), center + Vector2(17, 0), center + Vector2(4, 12), center, center + Vector2(-4, 12)])
	draw_colored_polygon(moth, Color(0.80, 0.86, 0.78, 0.92))
	draw_line(center - Vector2(14, 0), center + Vector2(14, 0), Color(0.30, 0.78, 0.73), 3.0, true)
	draw_circle(center, 3.5, Color(0.81, 0.62, 0.33))


func _draw_timeline(cycle: float) -> void:
	var rect := Rect2(Vector2(22.0, size.y - 24.0), Vector2(size.x - 44.0, 4.0))
	draw_rect(rect, Color(0.25, 0.34, 0.38, 0.36), true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * cycle, rect.size.y)), accent, true)
	var marker_x := rect.position.x + rect.size.x * 0.42
	draw_line(Vector2(marker_x, rect.position.y - 5.0), Vector2(marker_x, rect.end.y + 5.0), Color(0.82, 0.62, 0.34, 0.78), 2.0, true)


func _draw_projectile(point: Vector2, angle: float, reflectable: bool) -> void:
	var direction := Vector2.from_angle(angle)
	var side := direction.orthogonal()
	var points := PackedVector2Array([point + direction * 9.0, point + side * 5.0, point - direction * 9.0, point - side * 5.0])
	draw_colored_polygon(points, Color(0.82, 0.87, 0.75, 0.94) if reflectable else Color(0.12, 0.10, 0.13, 0.98))
	draw_polyline(PackedVector2Array(Array(points) + [points[0]]), Color(0.78, 0.60, 0.34), 2.0, true)


func _draw_blade(point: Vector2, angle: float) -> void:
	var direction := Vector2.from_angle(angle)
	var side := direction.orthogonal()
	var points := PackedVector2Array([point + direction * 13.0, point + side * 4.0, point - direction * 13.0, point - side * 4.0])
	draw_colored_polygon(points, Color(0.07, 0.06, 0.08, 0.98))
	draw_polyline(PackedVector2Array(Array(points) + [points[0]]), Color(0.76, 0.55, 0.32), 2.0, true)


func _draw_petal_enemy(center: Vector2, scale_value: float) -> void:
	var points := PackedVector2Array()
	for index in 8:
		var radius := (16.0 if index % 2 == 0 else 7.0) * scale_value
		points.append(center + Vector2.from_angle(float(index) * TAU / 8.0) * radius)
	draw_colored_polygon(points, Color(0.18, 0.12, 0.20, 0.92))
	points.append(points[0])
	draw_polyline(points, Color(0.65, 0.43, 0.60, 0.78), 2.0, true)


func _infer_preview_kind(id: StringName) -> StringName:
	return &"boss" if id in [&"reef_crown_battery", &"inverted_archivist", &"origami_judge"] else &"enemy"


func _default_attack_style(id: StringName) -> StringName:
	return {
		&"paper_turret": &"aimed_volley",
		&"brood_lantern": &"summon",
		&"bell_binder": &"tether",
		&"ink_warden": &"zone",
		&"prism_bulwark": &"shield",
		&"shear_scribe": &"cross_cut",
		&"reef_crown_battery": &"tide_gap",
		&"inverted_archivist": &"partitions",
		&"origami_judge": &"shrinking_frame",
	}.get(id, &"radial")
