class_name FoldlightBossArenaController
extends Node2D

enum TideState { REST, TELEGRAPH, SURGE }

const TIDE_TELEGRAPH_DURATION: float = 1.4
const TIDE_SURGE_DURATION: float = 1.30

var rule_id: StringName = &""
var room_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(2880, 1620))
var safe_rect: Rect2 = Rect2(Vector2(690, 400), Vector2(1500, 820))
var phase_index: int = 0
var elapsed: float = 0.0
var lane_angle: float = 0.0
var tide_state: TideState = TideState.REST
var tide_remaining: float = 3.8
var pulse_radius: float = 0.0
var pulse_progress: float = 0.0
var tide_gap_angle: float = -PI * 0.5


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = -3


func configure(new_rule_id: StringName, bounds: Rect2) -> void:
	rule_id = new_rule_id
	room_bounds = bounds
	phase_index = 0
	elapsed = 0.0
	lane_angle = 0.0
	tide_state = TideState.REST
	tide_remaining = 3.8
	pulse_radius = 0.0
	pulse_progress = 0.0
	tide_gap_angle = -PI * 0.5
	_update_rule()
	queue_redraw()


func set_phase(new_phase_index: int) -> void:
	phase_index = clampi(new_phase_index, 0, 2)
	if rule_id == &"reef_tide_pulse" and tide_state == TideState.REST:
		tide_remaining = minf(tide_remaining, 2.4)
	_update_rule()
	queue_redraw()


func advance_simulation(delta: float, _player_position: Vector2) -> void:
	var safe_delta := maxf(0.0, delta)
	elapsed += safe_delta
	if rule_id == &"reef_tide_pulse":
		_advance_tide(safe_delta)
		queue_redraw()
		return
	lane_angle = fmod(elapsed * (0.22 + float(phase_index) * 0.07), TAU)
	_update_rule()
	queue_redraw()


func is_player_safe(player_position: Vector2) -> bool:
	if rule_id == &"moving_safe_frame":
		return safe_rect.has_point(player_position)
	if rule_id == &"ink_partitions" and phase_index >= 1:
		var vertical_bar := Rect2(Vector2(room_bounds.get_center().x - 78.0, room_bounds.position.y), Vector2(156.0, room_bounds.size.y))
		return not vertical_bar.has_point(player_position)
	if rule_id == &"reef_tide_pulse":
		if tide_state != TideState.SURGE:
			return true
		var distance_to_center := player_position.distance_to(room_bounds.get_center())
		var dangerous_half_width := 58.0 + float(phase_index) * 8.0
		var relative := player_position - room_bounds.get_center()
		if not relative.is_zero_approx() and absf(wrapf(relative.angle() - tide_gap_angle, -PI, PI)) <= _tide_gap_half_angle():
			return true
		return absf(distance_to_center - pulse_radius) > dangerous_half_width
	if rule_id == &"rotating_lanes":
		var center := room_bounds.get_center()
		var lane_count := 2 + phase_index
		for lane in lane_count:
			var direction := Vector2.from_angle(lane_angle + float(lane) / float(lane_count) * PI)
			var lateral_distance := absf((player_position - center).dot(direction.orthogonal()))
			if lateral_distance <= 43.0:
				return false
		return true
	return room_bounds.grow(-54.0).has_point(player_position)


func get_rule_snapshot() -> Dictionary:
	return {
		"rule_id": rule_id,
		"phase": phase_index,
		"safe_rect": safe_rect,
		"lane_angle": lane_angle,
		"hazard_state": _tide_state_name(),
		"state_remaining": tide_remaining,
		"pulse_radius": pulse_radius,
		"pulse_progress": pulse_progress,
		"safe_gap_angle": tide_gap_angle,
		"safe_gap_half_angle": _tide_gap_half_angle(),
		"safe_gap_visible": rule_id == &"reef_tide_pulse" and tide_state != TideState.REST,
		"telegraph_message": "沿青色缺口穿过潮波" if rule_id == &"reef_tide_pulse" else "",
	}


func _update_rule() -> void:
	if rule_id != &"moving_safe_frame":
		safe_rect = room_bounds.grow(-90.0)
		return
	var sizes := [Vector2(1540, 860), Vector2(1260, 720), Vector2(980, 590)]
	var size: Vector2 = sizes[phase_index]
	var center := room_bounds.get_center()
	if phase_index >= 1:
		center.x += sin(elapsed * 0.58) * (180.0 + float(phase_index) * 70.0)
	if phase_index >= 2:
		center.y += sin(elapsed * 0.83 + 0.7) * 170.0
	var proposed := Rect2(center - size * 0.5, size)
	proposed.position.x = clampf(proposed.position.x, room_bounds.position.x + 70.0, room_bounds.end.x - 70.0 - size.x)
	proposed.position.y = clampf(proposed.position.y, room_bounds.position.y + 70.0, room_bounds.end.y - 70.0 - size.y)
	safe_rect = proposed


func _advance_tide(delta: float) -> void:
	var unspent := delta
	var guard := 0
	while unspent > 0.0001 and guard < 6:
		guard += 1
		var step := minf(unspent, tide_remaining)
		tide_remaining = maxf(0.0, tide_remaining - step)
		unspent -= step
		if tide_state == TideState.SURGE:
			pulse_progress = clampf(1.0 - tide_remaining / TIDE_SURGE_DURATION, 0.0, 1.0)
			pulse_radius = lerpf(120.0, _maximum_tide_radius(), pulse_progress)
		if tide_remaining > 0.0001:
			break
		match tide_state:
			TideState.REST:
				tide_state = TideState.TELEGRAPH
				tide_remaining = TIDE_TELEGRAPH_DURATION
				pulse_progress = 0.0
				pulse_radius = 120.0
				tide_gap_angle = wrapf(-PI * 0.5 + elapsed * 0.23 + float(phase_index) * 0.61, -PI, PI)
			TideState.TELEGRAPH:
				tide_state = TideState.SURGE
				tide_remaining = TIDE_SURGE_DURATION
				pulse_progress = 0.0
				pulse_radius = 120.0
			TideState.SURGE:
				tide_state = TideState.REST
				tide_remaining = [6.2, 5.4, 4.8][phase_index]
				pulse_progress = 0.0
				pulse_radius = 0.0


func _maximum_tide_radius() -> float:
	return room_bounds.get_center().distance_to(room_bounds.position) + 140.0


func _tide_gap_half_angle() -> float:
	return [0.62, 0.54, 0.48][phase_index]


func _tide_state_name() -> StringName:
	match tide_state:
		TideState.TELEGRAPH:
			return &"telegraph"
		TideState.SURGE:
			return &"surge"
		_:
			return &"rest"


func _draw() -> void:
	if rule_id == &"moving_safe_frame":
		var frame_pulse := 0.72 + sin(elapsed * 5.2) * 0.16
		var shade := Color(0.12, 0.055, 0.065, 0.30)
		draw_rect(Rect2(room_bounds.position, Vector2(room_bounds.size.x, safe_rect.position.y - room_bounds.position.y)), shade, true)
		draw_rect(Rect2(Vector2(room_bounds.position.x, safe_rect.end.y), Vector2(room_bounds.size.x, room_bounds.end.y - safe_rect.end.y)), shade, true)
		draw_rect(Rect2(Vector2(room_bounds.position.x, safe_rect.position.y), Vector2(safe_rect.position.x - room_bounds.position.x, safe_rect.size.y)), shade, true)
		draw_rect(Rect2(Vector2(safe_rect.end.x, safe_rect.position.y), Vector2(room_bounds.end.x - safe_rect.end.x, safe_rect.size.y)), shade, true)
		draw_rect(safe_rect.grow(12.0), Color(0.08, 0.015, 0.03, 0.56), false, 18.0, true)
		draw_rect(safe_rect, Color(0.86, 0.59, 0.30, frame_pulse), false, 7.0, true)
		draw_rect(safe_rect.grow(-16.0), Color(0.95, 0.77, 0.45, 0.16 + frame_pulse * 0.16), false, 2.0, true)
		for corner in [safe_rect.position, Vector2(safe_rect.end.x, safe_rect.position.y), safe_rect.end, Vector2(safe_rect.position.x, safe_rect.end.y)]:
			draw_circle(corner, 11.0 + frame_pulse * 3.0, Color(1, 0.82, 0.43, 0.92))
			var corner_point := Vector2(corner)
			var inward: Vector2 = corner_point.direction_to(safe_rect.get_center())
			draw_line(corner, corner + inward * 70.0, Color(1.0, 0.66, 0.22, 0.78), 5.0, true)
			draw_line(corner, corner + inward.orthogonal() * 34.0, Color(1.0, 0.40, 0.20, 0.42), 3.0, true)
		for mote in 8:
			var unit := fposmod(float(mote) / 8.0 + elapsed * 0.055, 1.0)
			var point: Vector2 = Vector2(lerpf(safe_rect.position.x, safe_rect.end.x, unit), safe_rect.position.y if mote % 2 == 0 else safe_rect.end.y)
			draw_colored_polygon(PackedVector2Array([point + Vector2(0,-6), point + Vector2(6,0), point + Vector2(0,6), point + Vector2(-6,0)]), Color(1.0, 0.72, 0.28, 0.44))
		for seal in 6:
			var angle := elapsed * (0.34 + phase_index * 0.05) + float(seal) * TAU / 6.0
			var radius := minf(safe_rect.size.x, safe_rect.size.y) * (0.30 + 0.03 * sin(elapsed * 1.7 + seal))
			var point := safe_rect.get_center() + Vector2.from_angle(angle) * radius
			var diamond := PackedVector2Array([point + Vector2(0,-12), point + Vector2(9,0), point + Vector2(0,12), point + Vector2(-9,0)])
			draw_colored_polygon(diamond, Color(0.96, 0.74, 0.38, 0.16 + frame_pulse * 0.16))
	elif rule_id == &"ink_partitions" and phase_index >= 1:
		var x := room_bounds.get_center().x
		draw_rect(Rect2(Vector2(x - 78, room_bounds.position.y), Vector2(156, room_bounds.size.y)), Color(0.22, 0.16, 0.34, 0.20), true)
		draw_line(Vector2(x - 78, room_bounds.position.y), Vector2(x - 78, room_bounds.end.y), Color(0.60, 0.48, 0.76, 0.58), 4.0, true)
		draw_line(Vector2(x + 78, room_bounds.position.y), Vector2(x + 78, room_bounds.end.y), Color(0.60, 0.48, 0.76, 0.58), 4.0, true)
	elif rule_id == &"reef_tide_pulse":
		var center := room_bounds.get_center()
		var gap_half := _tide_gap_half_angle()
		var arc_start := tide_gap_angle + gap_half
		var arc_end := tide_gap_angle + TAU - gap_half
		var gap_reach := _maximum_tide_radius()
		var gap_left := Vector2.from_angle(tide_gap_angle - gap_half)
		var gap_right := Vector2.from_angle(tide_gap_angle + gap_half)
		if tide_state == TideState.TELEGRAPH:
			var warning_progress := clampf(1.0 - tide_remaining / TIDE_TELEGRAPH_DURATION, 0.0, 1.0)
			var warning_color := Color(0.86, 0.48, 0.24, 0.88)
			var safe_color := Color(0.34, 0.86, 0.77, 0.10 + warning_progress * 0.08)
			draw_colored_polygon(PackedVector2Array([center, center + gap_left * gap_reach, center + gap_right * gap_reach]), safe_color)
			draw_line(center + gap_left * 100.0, center + gap_left * gap_reach, Color(0.44, 0.94, 0.82, 0.62), 5.0, true)
			draw_line(center + gap_right * 100.0, center + gap_right * gap_reach, Color(0.44, 0.94, 0.82, 0.62), 5.0, true)
			for echo_index in 4:
				var echo_radius := lerpf(220.0, _maximum_tide_radius() * 0.76, float(echo_index) / 3.0)
				draw_arc(center, echo_radius, arc_start, arc_end, 112, Color(warning_color, 0.15 + warning_progress * 0.18), 12.0 if echo_index == 0 else 5.0, false)
			var gap_direction := Vector2.from_angle(tide_gap_angle)
			for arrow_index in 3:
				var arrow_center := center + gap_direction * (210.0 + arrow_index * 150.0)
				var side := gap_direction.orthogonal() * 22.0
				draw_polyline(PackedVector2Array([arrow_center - gap_direction * 24.0 - side, arrow_center + gap_direction * 16.0, arrow_center - gap_direction * 24.0 + side]), Color(0.72, 1.0, 0.90, 0.72 + warning_progress * 0.20), 7.0, true)
		elif tide_state == TideState.SURGE:
			var surge_color := Color(0.30, 0.96, 0.92, 0.96)
			var dangerous_half_width := 58.0 + float(phase_index) * 8.0
			draw_arc(center, pulse_radius, arc_start, arc_end, 128, Color(0.02, 0.12, 0.18, 0.54), dangerous_half_width * 2.0, false)
			draw_arc(center, pulse_radius, arc_start, arc_end, 128, surge_color, 12.0, false)
			draw_arc(center, maxf(0.0, pulse_radius - dangerous_half_width * 0.72), arc_start, arc_end, 128, Color(surge_color, 0.42), 4.0, false)
			draw_line(center + gap_left * maxf(90.0, pulse_radius - 92.0), center + gap_left * (pulse_radius + 92.0), Color(1.0, 0.78, 0.34, 0.88), 8.0, true)
			draw_line(center + gap_right * maxf(90.0, pulse_radius - 92.0), center + gap_right * (pulse_radius + 92.0), Color(1.0, 0.78, 0.34, 0.88), 8.0, true)
	elif rule_id == &"rotating_lanes":
		var center := room_bounds.get_center()
		var lane_count := 2 + phase_index
		for lane in lane_count:
			var direction := Vector2.from_angle(lane_angle + float(lane) / float(lane_count) * PI)
			draw_line(center - direction * 1800.0, center + direction * 1800.0, Color(0.72, 0.31, 0.25, 0.09), 82.0, true)
			draw_line(center - direction * 1800.0, center + direction * 1800.0, Color(0.87, 0.63, 0.34, 0.38), 3.0, true)
