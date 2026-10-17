class_name FoldlightMechanicPreviewCanvas
extends Control

const BossPaperPuppet = preload("res://scripts/visuals/boss_paper_puppet.gd")

## A lightweight, deterministic combat vignette used by first-encounter and
## boss briefings.  It deliberately redraws the game's authored silhouettes
## instead of instantiating live combat actors inside the UI.

var preview_kind: StringName = &"enemy"
var preview_id: StringName = &"unknown"
var attack_style: StringName = &"radial"
var accent: Color = FoldlightRogueUITheme.GOLD
var _time: float = 0.0
var _motion_scale: float = 1.0


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
		"cycle_progress": _cycle_progress(),
		"shows_actor": true,
		"shows_attack": true,
	}


func _process(delta: float) -> void:
	var profile := get_node_or_null("/root/ProfileManager")
	_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0
	_time += maxf(0.0, delta) * _motion_scale
	queue_redraw()


func _cycle_progress() -> float:
	var duration := 6.0 if preview_id == &"shutter_seraph" else 3.6
	return fmod(_time, duration) / duration


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
	var cycle := _cycle_progress()
	_draw_attack(actor_center, player_center, cycle)
	_draw_actor(actor_center, cycle)
	_draw_player_marker(player_center, cycle)
	_draw_timeline(cycle)
	draw_rect(bounds.grow(-1.5), Color(accent, 0.42), false, 2.0, true)


func _draw_attack(origin: Vector2, target: Vector2, cycle: float) -> void:
	match attack_style:
		&"anchored_blast":
			_draw_anchored_blast(origin, cycle)
		&"poison_trail":
			_draw_poison_trail(origin, cycle)
		&"command_swarm":
			_draw_command_swarm(origin, target, cycle)
		&"relentless_charge":
			_draw_relentless_charge(origin, target, cycle)
		&"exposure_barrage":
			_draw_exposure_barrage(origin, target, cycle)
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
		&"woven_lanes", &"locked_dash", &"paired_gaps":
			_draw_new_boss_attack(origin, target, cycle)
		_:
			_draw_radial(origin, cycle)


func _draw_anchored_blast(origin: Vector2, cycle: float) -> void:
	var charge := clampf(cycle / 0.78, 0.0, 1.0)
	var danger := Color("f17665")
	draw_circle(origin, 83.0, Color(danger, 0.09))
	draw_arc(origin, 83.0, 0, TAU, 48, Color(danger, 0.78), 2.0, true)
	draw_arc(origin, 77.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, accent, 4.0, true)
	if cycle >= 0.78:
		var blast := (cycle - 0.78) / 0.22
		draw_arc(origin, lerpf(24.0, 83.0, blast), 0, TAU, 48, Color(danger, 1.0 - blast), 8.0, true)


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
	if preview_kind == &"boss":
		if attack_style == &"relentless_charge":
			var dash_cycle := fposmod(cycle * 3.0, 1.0)
			var dash_index := mini(2, int(cycle * 3.0))
			var destination := Vector2(size.x * 0.79, size.y * 0.62 + float(dash_index - 1) * minf(38.0, size.y * 0.10))
			center = center.lerp(destination, clampf((dash_cycle - 0.48) / 0.34, 0.0, 1.0))
		var bounds: Rect2 = BossPaperPuppet.get_visual_bounds(preview_id)
		var charging := attack_style == &"relentless_charge"
		var fit := minf(size.x * (0.32 if charging else 0.46) / bounds.size.x, size.y * (0.48 if charging else 0.66) / bounds.size.y)
		draw_set_transform(center, 0.0, Vector2.ONE * fit)
		BossPaperPuppet.draw_puppet(self, preview_id, {
			"time": _time, "intro": 1.0, "phase": 0,
			"motion_scale": _motion_scale,
			"charge": clampf(cycle / 0.42, 0.0, 1.0) if cycle < 0.42 else 0.0,
			"recoil": clampf(1.0 - (cycle - 0.42) / 0.10, 0.0, 1.0) if cycle >= 0.42 else 0.0,
		})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var breathe := sin(_time * (2.6 if preview_kind == &"boss" else 3.4))
	var scale_value := (1.25 if preview_kind == &"boss" else 1.0) * (1.0 + breathe * 0.025)
	draw_set_transform(center + Vector2(0.0, breathe * 3.0), breathe * 0.025, Vector2.ONE * scale_value)
	match preview_id:
		&"miasma_wraith": _draw_miasma_body()
		&"cinder_mine": _draw_cinder_mine_body(cycle)
		&"shutter_seraph": _draw_seraph_body(cycle)
		&"paper_turret": _draw_turret_body(cycle)
		&"brood_lantern": _draw_lantern_body()
		&"bell_binder": _draw_bell_body()
		&"ink_warden": _draw_warden_body()
		&"prism_bulwark": _draw_bulwark_body()
		&"shear_scribe": _draw_scribe_body()
		_: _draw_generic_body()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cinder_mine_body(cycle: float) -> void:
	for side in [-1.0, 1.0]:
		var fin := PackedVector2Array([Vector2(side * 15, -21), Vector2(side * 40, -6), Vector2(side * 25, 27), Vector2(side * 9, 14)])
		draw_colored_polygon(fin, Color("503b3e"))
		draw_polyline(PackedVector2Array(Array(fin) + [fin[0]]), accent, 2.0, true)
	var body := PackedVector2Array([Vector2(0, -34), Vector2(24, 0), Vector2(0, 35), Vector2(-24, 0)])
	draw_colored_polygon(body, Color("382f3b"))
	draw_polyline(PackedVector2Array(Array(body) + [body[0]]), accent, 2.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(9, 1), Vector2(0, 16), Vector2(-9, 1)]), Color("f17665"))
	for index in 3:
		var live := cycle < 0.78 * float(3 - index) / 3.0
		draw_line(Vector2(-9 + index * 9, -41), Vector2(-9 + index * 9, -35), accent if live else Color("55454b"), 3.0, true)


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


func _draw_exposure_barrage(origin: Vector2, target: Vector2, cycle: float) -> void:
	var seconds := cycle * 6.0
	var direction := origin.direction_to(target)
	if seconds >= 2.4 and seconds < 3.2:
		draw_dashed_line(origin + direction * 48.0, target, Color(0.92, 0.66, 0.36, 0.65), 2.0, 9.0, true)
	if seconds < 3.2 or seconds >= 5.6:
		return
	for row in 6:
		var flight := fmod((seconds - 3.2) * 1.3 + row * 0.16, 1.0)
		for column in 5:
			var ray := direction.rotated(float(column - 2) * 0.15)
			_draw_projectile(origin + ray * lerpf(48.0, origin.distance_to(target) + 42.0, flight), ray.angle(), true)


func _draw_seraph_body(cycle: float) -> void:
	var seconds := cycle * 6.0
	var firing := seconds >= 3.2 and seconds < 5.6
	var opening := 1.0 if firing else (clampf((6.0 - seconds) / 0.4, 0.0, 1.0) if seconds >= 5.6 else 0.0)
	for side in [-1.0, 1.0]:
		for layer in 3:
			var reach := lerpf(19.0, 66.0 + layer * 6.0, opening)
			var wing := PackedVector2Array([Vector2(side * 4.0, -28.0 + layer * 14.0), Vector2(side * reach, -42.0 + layer * 26.0), Vector2(side * (reach - 10.0), 18.0 + layer * 15.0), Vector2(side * 5.0, 31.0)])
			draw_colored_polygon(wing, Color(0.13 + layer * 0.03, 0.22 + layer * 0.025, 0.28 + layer * 0.02))
			wing.append(wing[0])
			draw_polyline(wing, Color(0.68, 0.71, 0.65), 2.0, true)
	if firing:
		draw_circle(Vector2.ZERO, 14.0, Color(0.97, 0.80, 0.48))
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.95, 0.76))
	else:
		draw_line(Vector2(0.0, -24.0), Vector2(0.0, 29.0), Color(0.49, 0.77, 0.80), 4.0, true)
		draw_arc(Vector2.ZERO, 42.0, -PI * 0.7, PI * 0.7, 26, Color(0.49, 0.77, 0.80, 0.7), 2.0, true)


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
	if attack_style == &"exposure_barrage":
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * 3.2 / 6.0, -2.0), Vector2(rect.size.x * 2.4 / 6.0, 8.0)), Color(0.92, 0.67, 0.34, 0.54), true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * cycle, rect.size.y)), accent, true)
	var marker_x := rect.position.x + rect.size.x * (3.2 / 6.0 if attack_style == &"exposure_barrage" else 0.42)
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
	return &"boss" if FoldlightRogueContentCatalog.boss_by_id(id) != null else &"enemy"


func _default_attack_style(id: StringName) -> StringName:
	return {
		&"miasma_wraith": &"poison_trail",
		&"cinder_mine": &"anchored_blast",
		&"shutter_seraph": &"exposure_barrage",
		&"paper_turret": &"aimed_volley",
		&"brood_lantern": &"summon",
		&"bell_binder": &"tether",
		&"ink_warden": &"zone",
		&"prism_bulwark": &"shield",
		&"shear_scribe": &"cross_cut",
		&"reef_crown_battery": &"tide_gap",
		&"inverted_archivist": &"partitions",
		&"origami_judge": &"shrinking_frame",
		&"tide_loom_mother": &"command_swarm",
		&"torn_page_executioner": &"relentless_charge",
		&"eclipse_twin_bells": &"paired_gaps",
	}.get(id, &"radial")


func _draw_miasma_body() -> void:
	var paper := Color("a9b58c")
	var mantle := PackedVector2Array([Vector2(0, -39), Vector2(31, -9), Vector2(23, 29), Vector2(9, 18), Vector2(0, 40), Vector2(-13, 20), Vector2(-27, 31), Vector2(-32, -7)])
	draw_colored_polygon(mantle, Color("243a34"))
	draw_polyline(PackedVector2Array(Array(mantle) + [mantle[0]]), paper, 2.5, true)
	draw_line(Vector2(0, -33), Vector2(0, 30), Color(paper, 0.45), 1.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -24), Vector2(12, -6), Vector2(0, 5), Vector2(-12, -6)]), Color("101f23"))
	draw_line(Vector2(-7, -8), Vector2(-2, -6), paper, 2.5, true)
	draw_line(Vector2(2, -6), Vector2(7, -8), paper, 2.5, true)


func _draw_poison_trail(origin: Vector2, cycle: float) -> void:
	var ink := Color("a9b58c")
	for index in 3:
		var center := origin + Vector2(44.0 + index * 52.0, 44.0 - index * 18.0)
		var warning := cycle < 0.24 + index * 0.13
		var cloud_radius := 33.0
		draw_circle(center, cloud_radius, Color(ink, 0.05 if warning else 0.12))
		if warning:
			for segment in 8:
				var angle := segment * TAU / 8.0
				draw_arc(center, cloud_radius, angle, angle + 0.50, 6, Color(ink, 0.75), 2.0, true)
		else:
			draw_arc(center, cloud_radius, 0.0, TAU, 24, ink, 2.4, true)
			for ray in 3:
				var direction := Vector2.from_angle(-PI * 0.5 + ray * TAU / 3.0)
				draw_line(center + direction * 3.0, center + direction * 12.0, Color(ink, 0.65), 3.5, true)


func _draw_command_swarm(origin: Vector2, target: Vector2, cycle: float) -> void:
	var command_ink := Color("baa784")
	var aura_radius := minf(102.0, size.y * 0.29)
	draw_circle(origin, aura_radius, Color(command_ink, 0.035))
	draw_arc(origin, aura_radius, 0.0, TAU, 48, Color(command_ink, 0.48), 1.8, true)
	for index in 3:
		var center := origin + Vector2.from_angle(-0.85 + index * 0.82) * (aura_radius - 12.0)
		draw_line(origin, center, Color(command_ink, 0.55), 1.7, true)
		_draw_petal_enemy(center, 0.78)
		# The fixed chevron denotes a buff even with animation disabled.
		draw_polyline(PackedVector2Array([center + Vector2(-7, -24), center + Vector2(0, -30), center + Vector2(7, -24)]), command_ink, 2.2, true)
		var aim := center.direction_to(target)
		for shot in 3:
			var flight := fposmod(cycle * 2.0 + shot * 0.27, 1.0)
			_draw_projectile(center + aim * lerpf(22.0, center.distance_to(target), flight), aim.angle(), true)


func _draw_relentless_charge(origin: Vector2, target: Vector2, cycle: float) -> void:
	var dash_cycle := fposmod(cycle * 3.0, 1.0)
	var dash_index := mini(2, int(cycle * 3.0))
	var destination := target + Vector2(0.0, float(dash_index - 1) * minf(38.0, size.y * 0.10))
	var aim := origin.direction_to(destination)
	var side := aim.orthogonal() * 19.0
	var ink := Color("c3a788")
	draw_line(origin, destination, Color("362d32"), 38.0, true)
	draw_dashed_line(origin + side, destination + side, ink, 2.0, 10.0, true)
	draw_dashed_line(origin - side, destination - side, ink, 2.0, 10.0, true)
	for index in 3:
		var x := size.x * 0.35 + float(index - 1) * 20.0
		var active_mark := index == dash_index
		draw_rect(Rect2(x - 5.0, 20.0, 10.0, 5.0), ink if active_mark else Color(ink, 0.25))
	if dash_cycle < 0.48:
		var tip := origin.lerp(destination, dash_cycle / 0.48)
		draw_polyline(PackedVector2Array([tip - aim * 10.0 + side * 0.40, tip, tip - aim * 10.0 - side * 0.40]), ink, 2.3, true)


func _draw_new_boss_attack(origin: Vector2, target: Vector2, cycle: float) -> void:
	var aim := origin.direction_to(target)
	var travel := clampf((cycle - 0.42) / 0.38, 0.0, 1.0)
	var distance := origin.distance_to(target) + 35.0
	var gold := Color(0.95,0.67,0.32,0.65)
	if attack_style == &"woven_lanes":
		for lane in 5:
			var start := origin + aim.orthogonal()*float(lane-2)*23.0
			if lane == 2:
				draw_line(start+aim*65.0,start+aim*distance,Color(0.47,0.94,0.82,0.28),13.0,true)
				continue
			draw_dashed_line(start,start+aim*distance,Color(accent,0.42),2.0,12.0,true)
			if cycle >= 0.42:
				_draw_projectile(start+aim*lerpf(35.0,distance,travel),aim.angle(),true)
	elif attack_style == &"locked_dash":
		var side := aim.orthogonal()*20.0
		draw_line(origin,target+aim*35.0,Color(0.12,0.07,0.10,0.48),40.0,true)
		draw_dashed_line(origin+side,target+side+aim*35.0,gold,2.0,12.0,true)
		draw_dashed_line(origin-side,target-side+aim*35.0,gold,2.0,12.0,true)
		if cycle >= 0.42:
			_draw_blade(origin+aim*distance*travel,aim.angle())
	else:
		for index in 2:
			var side := -1.0 if index == 0 else 1.0
			var bell := origin+Vector2(side*36.0,7.0)
			var gap_angle := aim.angle()+side*0.36
			draw_arc(bell,50.0,gap_angle-0.78,gap_angle+0.78,18,Color(0.47,0.94,0.82,0.72),3.0,true)
			var pulse := clampf((cycle-0.42-float(index)*0.145)/0.34,0.0,1.0)
			if pulse <= 0.0: continue
			for ray in 10:
				var angle := gap_angle+float(ray)*TAU/10.0
				if absf(wrapf(angle-gap_angle,-PI,PI)) < 0.78: continue
				_draw_projectile(bell+Vector2.from_angle(angle)*lerpf(23.0,106.0,pulse),angle,true)
