class_name FoldlightBossAttackTelegraph
extends Node2D

var pattern_id: StringName = &""
var duration: float = 0.8
var remaining: float = 0.8
var target_position: Vector2 = Vector2.ZERO
var accent: Color = Color(0.34, 0.88, 0.84)
var unreflectable: bool = false
var spread_radians: float = 0.0
var zone_radius: float = 0.0
var _simulation_active: bool = true
var attack_lanes: Array = []
var safe_gaps: Array = []
var hold_seconds: float = 0.0
var charge_number: int = 0
var charge_total: int = 0


func configure(snapshot: Dictionary) -> void:
	top_level = true
	global_position = Vector2(snapshot.get("origin", Vector2.ZERO))
	target_position = Vector2(snapshot.get("target_position", global_position + Vector2.DOWN))
	pattern_id = StringName(snapshot.get("pattern_id", &""))
	duration = maxf(0.25, float(snapshot.get("duration", 0.8)))
	hold_seconds = clampf(float(snapshot.get("hold_seconds", 0.0)), 0.0, 2.0)
	remaining = duration + hold_seconds
	charge_number = int(snapshot.get("charge_number", 0))
	charge_total = int(snapshot.get("charge_total", 0))
	attack_lanes = snapshot.get("attack_lanes", []).duplicate(true)
	safe_gaps = snapshot.get("safe_gaps", []).duplicate(true)
	accent = Color(snapshot.get("accent", accent))
	unreflectable = pattern_id in [&"black_lane", &"margin_cut", &"unreflectable_cut"]
	if not attack_lanes.is_empty():
		unreflectable = attack_lanes.all(func(lane: Dictionary) -> bool: return not bool(lane.get("reflectable", true)))
	spread_radians = maxf(0.0, float(snapshot.get("spread_radians", 0.0)))
	zone_radius = maxf(0.0, float(snapshot.get("zone_radius", 0.0)))
	z_as_relative = false
	z_index = 2
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	_simulation_active = value
	set_process(value)


func _process(delta: float) -> void:
	if not _simulation_active or not is_finite(delta) or delta <= 0.0:
		return
	# Rendering resumes with one large delta after a stall. Preserve the visible
	# warning instead of deleting its whole lifespan before the next drawn frame.
	remaining = maxf(0.0, remaining - minf(delta, 0.1))
	queue_redraw()
	if remaining <= 0.0:
		queue_free()


func get_visual_contract() -> Dictionary:
	var motif: StringName = {
		&"judgement_petals": &"twelve_seal_crown",
		&"unreflectable_cut": &"black_gold_blade_rail",
		&"shrinking_frame": &"closing_corner_frame",
	}.get(pattern_id, &"classic_warning")
	return {
		"pattern_id": pattern_id,
		"motif": motif,
		"unreflectable": unreflectable,
		"warned_spread": spread_radians,
		"zone_radius": zone_radius,
		"mixed_unreflectable": pattern_id == &"shrinking_frame",
		"authored": not attack_lanes.is_empty() or pattern_id in [&"judgement_petals", &"unreflectable_cut", &"shrinking_frame"],
		"attack_lanes": attack_lanes.duplicate(true),
		"safe_gaps": safe_gaps.duplicate(true),
		"hold_seconds": hold_seconds,
	}


func _draw() -> void:
	var ratio := clampf((remaining - hold_seconds) / duration, 0.0, 1.0)
	var warning_color := Color(1.0, 0.66, 0.20) if unreflectable else accent
	var pulse := 0.62 + sin((duration - remaining) * 18.0) * 0.16
	draw_circle(Vector2.ZERO, 78.0 + ratio * 34.0, Color(warning_color, 0.04 + (1.0 - ratio) * 0.08))
	draw_arc(Vector2.ZERO, 80.0 + ratio * 34.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - ratio), 56, Color(warning_color, 0.84), 5.0, true)
	if not attack_lanes.is_empty():
		_draw_authored_lanes(ratio)
		if charge_number > 0:
			draw_string(FoldlightTheme.body_font(), Vector2(-84, -122), "连冲 %d / %d" % [charge_number, charge_total], HORIZONTAL_ALIGNMENT_CENTER, 168, 24, Color(1.0,0.73,0.34))
		return
	if spread_radians > 0.0:
		_draw_black_gold_spread(pulse)
	if zone_radius > 0.0:
		var zone_center := target_position - global_position
		draw_circle(zone_center, zone_radius, Color(0.88, 0.50, 0.45, 0.045 + (1.0 - ratio) * 0.035))
		draw_arc(zone_center, zone_radius, 0.0, TAU, 64, Color(0.88, 0.50, 0.45, 0.75), 3.0, true)
		draw_arc(zone_center, zone_radius + 12.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - ratio), 64, Color(0.84, 0.69, 0.44, 0.66), 2.0, true)
	if unreflectable:
		var direction := global_position.direction_to(target_position)
		if direction.is_zero_approx():
			direction = Vector2.DOWN
		var local_end := direction * 1700.0
		draw_line(Vector2.ZERO, local_end, Color(0.03, 0.01, 0.01, 0.48), 34.0 if pattern_id == &"unreflectable_cut" else 30.0, true)
		draw_dashed_line(Vector2.ZERO, local_end, Color(warning_color, pulse), 5.0 if pattern_id == &"unreflectable_cut" else 4.0, 26.0, true)
		if pattern_id == &"unreflectable_cut":
			var side := direction.orthogonal()
			for blade_index in 5:
				var distance := 150.0 + float(blade_index) * 190.0
				var blade_center := direction * distance + side * sin(float(blade_index) * 1.9) * 24.0
				var blade_length := 46.0 + (1.0 - ratio) * 32.0
				var blade := PackedVector2Array([blade_center + direction * blade_length, blade_center + side * 12.0, blade_center - direction * blade_length, blade_center - side * 12.0])
				draw_colored_polygon(blade, Color(0.025, 0.008, 0.018, 0.88))
				draw_polyline(_closed(blade), Color(1.0, 0.60, 0.18, 0.66 + pulse * 0.24), 2.4, true)
			draw_line(side * -82.0, side * 82.0, Color(1.0, 0.28, 0.14, 0.30 + pulse * 0.24), 6.0, true)
		for cross in 3:
			var point := direction * (180.0 + float(cross) * 210.0)
			draw_line(point - direction.orthogonal() * 13.0, point + direction.orthogonal() * 13.0, Color(warning_color, 0.74), 3.0, true)
	else:
		match pattern_id:
			&"petal_salvo":
				var aim := global_position.direction_to(target_position)
				if aim.is_zero_approx():
					aim = Vector2.DOWN
				for ray_index in 7:
					var unit := float(ray_index) / 6.0 - 0.5
					var ray := aim.rotated(unit * 0.92)
					draw_dashed_line(ray * 72.0, ray * 560.0, Color(warning_color, 0.18 + pulse * 0.22), 3.0, 24.0, true)
			&"tide_fan":
				for ring_index in 3:
					var ring_radius := 96.0 + float(ring_index) * 42.0 + (1.0 - ratio) * 26.0
					draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 56, Color(warning_color, 0.30 + float(ring_index) * 0.11), 4.0, true)
			&"turret_crown":
				for corner in [Vector2(-92, -70), Vector2(92, -70), Vector2(-92, 70), Vector2(92, 70)]:
					draw_rect(Rect2(corner - Vector2(15, 15), Vector2(30, 30)), Color(warning_color, 0.16 + pulse * 0.22), true)
					draw_rect(Rect2(corner - Vector2(19, 19), Vector2(38, 38)), Color(warning_color, 0.72), false, 3.0)
			&"judgement_petals":
				for petal in 12:
					var angle := float(petal) * TAU / 12.0 + (1.0 - ratio) * 0.42
					var direction := Vector2.from_angle(angle)
					var center := direction * (104.0 + (1.0 - ratio) * 72.0)
					var side := direction.orthogonal()
					var shape := PackedVector2Array([center + direction * 34.0, center + side * 12.0, center - direction * 27.0, center - side * 12.0])
					draw_colored_polygon(shape, Color(0.22, 0.035, 0.045, 0.72))
					draw_polyline(_closed(shape), Color(1.0, 0.66, 0.22, 0.42 + pulse * 0.34), 2.4, true)
				draw_arc(Vector2.ZERO, 188.0 - ratio * 42.0, -PI * 0.94, PI * 0.82, 72, Color(1.0, 0.82, 0.40, 0.48), 4.0, true)
				draw_circle(Vector2.ZERO, 42.0 + (1.0 - ratio) * 20.0, Color(1.0, 0.52, 0.16, 0.08 + pulse * 0.06))
			&"shrinking_frame":
				var frame_size := Vector2(1120.0, 650.0).lerp(Vector2(420.0, 250.0), 1.0 - ratio)
				var frame := Rect2(-frame_size * 0.5, frame_size)
				draw_rect(frame.grow(20.0), Color(0.025, 0.006, 0.016, 0.42), false, 34.0, true)
				draw_rect(frame, Color(1.0, 0.52, 0.17, 0.76 + pulse * 0.18), false, 8.0, true)
				draw_rect(frame.grow(-18.0), Color(1.0, 0.82, 0.42, 0.36), false, 2.0, true)
				for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
					var corner_point := Vector2(corner)
					var inward: Vector2 = corner_point.direction_to(frame.get_center())
					draw_line(corner, corner + inward * 76.0, Color(1.0, 0.72, 0.28, 0.88), 6.0, true)
			_:
				for petal in 6:
					var angle := float(petal) * TAU / 6.0
					draw_line(Vector2.from_angle(angle) * 48.0, Vector2.from_angle(angle) * (92.0 + (1.0 - ratio) * 24.0), Color(warning_color, 0.36), 3.0, true)


func _draw_authored_lanes(ratio: float) -> void:
	# Every segment comes from the same immutable plan as its actual projectile.
	# Mint openings and gold forbidden lanes remain readable with motion disabled.
	for lane: Dictionary in attack_lanes:
		var start: Vector2 = Vector2(lane["origin"]) - global_position
		var end: Vector2 = Vector2(lane["end"]) - global_position
		var width := float(lane.get("width", 22.0))
		var color := accent if bool(lane.get("reflectable", true)) else Color(1.0, 0.66, 0.2)
		var dash := bool(lane.get("dash", false))
		draw_line(start, end, Color(0.03, 0.015, 0.03, 0.35 if dash else 0.16), width, true)
		var side := start.direction_to(end).orthogonal() * width * 0.5
		if dash:
			draw_dashed_line(start + side, end + side, Color(color, 0.82), 2.5, 22.0, true)
			draw_dashed_line(start - side, end - side, Color(color, 0.82), 2.5, 22.0, true)
			draw_arc(end, width * 0.5, 0.0, TAU, 24, Color(color, 0.65), 2.0, true)
		draw_dashed_line(start, end, Color(color, 0.30 + (1.0 - ratio) * 0.30), 2.0, 24.0, true)
	for gap: Dictionary in safe_gaps:
		var start: Vector2 = Vector2(gap["origin"]) - global_position
		var direction: Vector2 = gap["direction"]
		var reach := float(gap["reach"])
		var color := Color(0.47, 0.94, 0.82, 0.62)
		if gap.has("half_angle"):
			var half_angle := float(gap["half_angle"])
			draw_arc(start, 118.0, direction.angle() - half_angle, direction.angle() + half_angle, 20, color, 4.0, true)
			for side in [-1.0, 1.0]:
				draw_dashed_line(start + direction.rotated(side * half_angle) * 90.0, start + direction.rotated(side * half_angle) * reach, Color(color, 0.36), 2.0, 18.0, true)
		else:
			var side := direction.orthogonal() * float(gap["width"]) * 0.5
			for sign_value in [-1.0, 1.0]:
				draw_dashed_line(start + side * sign_value, start + side * sign_value + direction * reach, Color(color, 0.38), 2.0, 24.0, true)
		for index in 3:
			var mark := start + direction * (130.0 + float(index) * 105.0)
			draw_polyline(PackedVector2Array([mark - direction * 11.0 - direction.orthogonal() * 8.0, mark, mark - direction * 11.0 + direction.orthogonal() * 8.0]), color, 2.0, true)


func _draw_black_gold_spread(pulse: float) -> void:
	var direction := global_position.direction_to(target_position)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var left := direction.rotated(-spread_radians * 0.5) * 1700.0
	var right := direction.rotated(spread_radians * 0.5) * 1700.0
	# The entire fan is warned, including the mixed black-gold follow-up on the
	# judge's frame attack. A single thin center rail understated its old width.
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, left, right]), Color(0.88, 0.50, 0.45, 0.035 + pulse * 0.025))
	draw_dashed_line(Vector2.ZERO, left, Color(0.84, 0.69, 0.44, 0.48 + pulse * 0.16), 2.0, 25.0, true)
	draw_dashed_line(Vector2.ZERO, right, Color(0.84, 0.69, 0.44, 0.48 + pulse * 0.16), 2.0, 25.0, true)
	if pattern_id == &"shrinking_frame":
		draw_dashed_line(Vector2.ZERO, direction * 1700.0, Color(0.84, 0.69, 0.44, 0.75), 3.0, 22.0, true)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result
