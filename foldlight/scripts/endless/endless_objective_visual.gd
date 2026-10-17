extends Node2D
## Presentation only: all progress comes from the director. The simulation owner
## advances this canvas explicitly, so pause/rewards cannot leave timers running.

const Art = preload("res://scripts/visuals/paper_art.gd")
const COMPLETE_SECONDS := 0.5
const DRAW_STEP := 0.05
var _objective: Dictionary = {}
var _terminal_left: float = 0.0
var _feedback_left: float = 0.0
var _clock: float = 0.0
var _draw_clock: float = 0.0
var _reduced: bool = false
var _dirty: bool = false
var _draw_count: int = 0


func reset() -> void:
	_objective.clear()
	_terminal_left = 0.0
	_feedback_left = 0.0
	_clock = 0.0
	_draw_clock = 0.0
	_dirty = false
	queue_redraw()


func set_motion_reduced(value: bool) -> void:
	_reduced = value
	queue_redraw()


func set_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		reset()
		return
	var same_task: bool = not _objective.is_empty() and snapshot.get("id", snapshot.get("kind")) == _objective.get("id", _objective.get("kind"))
	var was_terminal := _is_terminal(_objective)
	var terminal := _is_terminal(snapshot)
	var prior_progress := float(_objective.get("progress", 0.0)) if same_task else 0.0
	if not same_task:
		_terminal_left = 0.0
		_feedback_left = 0.0
		_clock = 0.0
	if terminal and (not same_task or not was_terminal):
		_terminal_left = COMPLETE_SECONDS
	if float(snapshot.get("progress", 0.0)) > prior_progress + 0.001 or float(snapshot.get("return_boost_seconds", 0.0)) > float(_objective.get("return_boost_seconds", 0.0)):
		_feedback_left = 0.5
	var changed := snapshot != _objective
	_objective = snapshot.duplicate(true)
	_dirty = _dirty or changed
	if not same_task or (terminal and not was_terminal):
		_dirty = false
		queue_redraw()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _objective.is_empty():
		return
	var was_visible := _terminal_left > 0.0 or _feedback_left > 0.0
	_terminal_left = maxf(0.0, _terminal_left - delta)
	_feedback_left = maxf(0.0, _feedback_left - delta)
	if not _reduced:
		_clock = fmod(_clock + delta, TAU * 100.0)
	_draw_clock += delta
	if _draw_clock >= DRAW_STEP and (not _reduced or was_visible or _dirty):
		_draw_clock = fmod(_draw_clock, DRAW_STEP)
		_dirty = false
		queue_redraw()


func get_visual_snapshot() -> Dictionary:
	var kind := StringName(_objective.get("kind", &""))
	var terminal := _is_terminal(_objective)
	return {
		"kind": kind, "visible": not _objective.is_empty() and (not terminal or _terminal_left > 0.0) and (kind != &"clear_swarm" or _feedback_left > 0.0),
		"terminal_remaining": _terminal_left, "feedback_remaining": _feedback_left,
		"animation_time": _clock, "motion_reduced": _reduced,
		"draw_count": _draw_count,
		"progress_ratio": clampf(float(_objective.get("progress_ratio", 0.0)), 0.0, 1.0),
		"occupied": bool(_objective.get("occupied", false)),
		"return_charge_count": int(_objective.get("return_charge_count", 0)),
		"return_boost_seconds": float(_objective.get("return_boost_seconds", 0.0)),
		"facility_count": mini(3, (_objective.get("route_points", PackedVector2Array()) as PackedVector2Array).size()) if kind == &"relay_route" else (0 if kind == &"clear_swarm" else 1),
		"lit_petals": clampi(int(_objective.get("progress", 0)), 0, 12) if kind == &"capture_storm" else 0,
		"kill_marks": clampi(int(_objective.get("progress", 0)), 0, 10) if kind == &"clear_swarm" else 0,
	}


func _is_terminal(snapshot: Dictionary) -> bool:
	return bool(snapshot.get("completed", false)) or bool(snapshot.get("failed", false))


func _draw() -> void:
	_draw_count += 1
	if _objective.is_empty() or (_is_terminal(_objective) and _terminal_left <= 0.0):
		return
	var point := Vector2(_objective.get("target_position", Vector2.ZERO))
	var kind := StringName(_objective.get("kind", &""))
	var finished := bool(_objective.get("completed", false))
	var failed := bool(_objective.get("failed", false))
	var alpha := clampf(_terminal_left / 0.18, 0.0, 1.0) if _is_terminal(_objective) else 1.0
	var unfold := (1.0 - _terminal_left / COMPLETE_SECONDS) if finished and not _reduced else 0.0
	var ratio := clampf(float(_objective.get("progress_ratio", 0.0)), 0.0, 1.0)
	var occupied := bool(_objective.get("occupied", false))
	var color: Color = Art.DANGER if failed else (Art.FOLD if kind == &"capture_storm" else Art.GOLD)
	var viewport_inverse := get_global_transform_with_canvas().affine_inverse()
	var view := Rect2(viewport_inverse * get_viewport_rect().position, Vector2.ZERO).expand(viewport_inverse * get_viewport_rect().end).grow(320.0)
	if kind == &"relay_route":
		_draw_relay(view, alpha, unfold, finished)
		return
	if kind == &"clear_swarm":
		if _feedback_left > 0.0 and _objective.has("player_position"):
			_draw_kill_marks(Vector2(_objective.player_position), alpha)
		return
	if not view.has_point(point):
		return
	match kind:
		&"capture_point":
			_draw_boundary(point, float(_objective.get("capture_radius", 170.0)), color, occupied, alpha)
			_draw_lighthouse(point, ratio, occupied, alpha, unfold)
		&"capture_storm":
			_draw_boundary(point, float(_objective.get("capture_radius", 240.0)), color, occupied, alpha)
			_draw_windmill(point, ratio, alpha, unfold)
		&"defeat_captain":
			_draw_crown(point, alpha, unfold)
		&"destroy_flag":
			# The active flag is the real combat actor, never a second fake target.
			# Its actor is retired on defeat; this bounded remnant finishes the fold.
			if finished:
				_draw_flag_remnant(point, alpha, unfold)
	if finished:
		_label(point + Vector2(0, 90), "航标已点亮" if kind in [&"capture_point", &"capture_storm"] else "目标已击破", Art.GOLD, alpha)
	elif failed:
		_label(point + Vector2(0, 90), "信号消散", Art.DANGER, alpha)


func _draw_boundary(point: Vector2, radius: float, color: Color, occupied: bool, alpha: float) -> void:
	# The fine edge is the authoritative interaction radius, never an inflated
	# decorative ring. Four inward stitches make its side readable on a phone.
	draw_circle(point, radius, Color(color, (0.035 if occupied else 0.015) * alpha))
	draw_arc(point, radius, 0.0, TAU, 64, Color(color, (0.48 if occupied else 0.27) * alpha), 1.8, true)
	for side in 4:
		var direction := Vector2.from_angle(float(side) * PI * 0.5)
		var tip := point + direction * radius
		draw_line(tip, tip - direction * 13.0, Color(color, 0.58 * alpha), 2.0, true)


func _draw_lighthouse(point: Vector2, ratio: float, occupied: bool, alpha: float, unfold: float) -> void:
	var at := point + Vector2(0, -4.0 - (sin(_clock * 1.5) * 1.5 if not _reduced and occupied else 0.0))
	_plate(at + Vector2(0, 30), 66.0, 26.0, Art.GOLD, alpha)
	for side in [-1.0, 1.0]:
		var spread := 25.0 + ratio * 20.0 + unfold * 20.0
		_facet(PackedVector2Array([at + Vector2(side * 12, 18), at + Vector2(side * spread, -17), at + Vector2(side * (spread + 9), 20), at + Vector2(side * 19, 32)]), Art.PAPER.darkened(0.36), alpha)
	_facet(PackedVector2Array([at + Vector2(-23, 26), at + Vector2(-16, -58), at + Vector2(0, -74), at + Vector2(19, -55), at + Vector2(25, 26)]), Color("395852"), alpha)
	draw_line(at + Vector2(0, -63), at + Vector2(0, 23), Color(Art.PAPER, 0.44 * alpha), 2.0, true)
	draw_rect(Rect2(at + Vector2(-6, -45), Vector2(12, 59)), Color(Art.INK, 0.9 * alpha))
	draw_rect(Rect2(at + Vector2(-4, 12 - 55 * ratio), Vector2(8, 55 * ratio)), Color(Art.GOLD, 0.88 * alpha))
	var roof := PackedVector2Array([at + Vector2(-34, -57), at + Vector2(0, -94 - unfold * 12), at + Vector2(35, -57), at + Vector2(0, -69)])
	_facet(roof, Art.PAPER.darkened(0.18), alpha)
	draw_circle(at + Vector2(0, -58), 5.0 + 2.0 * ratio, Color(Art.GOLD, (0.45 + ratio * 0.4) * alpha))
	for index in 4:
		var charge := clampi(int(_objective.get("return_charge_count", 0)), 0, 12)
		var charged := index < (4 if charge >= 12 else charge % 4)
		var tick := at + Vector2(-21 + index * 14, 42)
		draw_line(tick, tick + Vector2(0, 6), Color(Art.FOLD if charged else Art.PAPER, (0.82 if charged else 0.22) * alpha), 3.0, true)
	if not _is_terminal(_objective):
		_label(point + Vector2(0, 84), "驻守 %.1f / %.0f" % [float(_objective.get("progress", 0.0)), float(_objective.get("required", 12.0))], Art.GOLD, alpha)
		if float(_objective.get("return_boost_seconds", 0.0)) > 0.0:
			_label(point + Vector2(0, 111), "返光助燃 +%.0f秒" % float(_objective.return_boost_seconds), Art.FOLD, alpha * 0.82, 19)


func _draw_windmill(point: Vector2, ratio: float, alpha: float, unfold: float) -> void:
	_plate(point + Vector2(0, 32), 60.0, 24.0, Art.FOLD, alpha)
	var hub := point + Vector2(0, -20)
	var spin := _clock * 0.12 if not _reduced else 0.0
	for index in 12:
		var angle := float(index) * TAU / 12.0 - PI * 0.5 + spin
		var direction := Vector2.from_angle(angle)
		var tangent := direction.orthogonal()
		var lit := index < clampi(int(_objective.get("progress", 0)), 0, 12)
		var radius := 58.0 + unfold * 16.0
		var blade := PackedVector2Array([hub + direction * 19, hub + direction * radius - tangent * 12, hub + direction * (radius + 4) + tangent * 2, hub + direction * 30 + tangent * 13])
		_facet(blade, Art.FOLD.darkened(0.06) if lit else Color("294947"), alpha)
		draw_line(blade[0], blade[2], Color(Art.PAPER, (0.64 if lit else 0.17) * alpha), 1.2, true)
	_facet(PackedVector2Array([hub + Vector2(0, -20), hub + Vector2(18, 0), hub + Vector2(0, 21), hub + Vector2(-18, 0)]), Art.PAPER.darkened(0.3), alpha)
	draw_circle(hub, 8.0, Color(Art.FOLD, (0.4 + ratio * 0.5) * alpha))
	if _feedback_left > 0.0 and not _reduced:
		for index in 4:
			var direction := Vector2.from_angle(index * PI * 0.5 + 0.4)
			var spark := hub + direction * (90.0 - (1.0 - _feedback_left / 0.5) * 60.0)
			draw_line(spark, spark + direction * 8, Color(Art.FOLD, _feedback_left * alpha), 2.0, true)
	if not _is_terminal(_objective):
		_label(point + Vector2(0, 86), "集光 %d / 12" % int(_objective.get("progress", 0)), Art.FOLD, alpha)


func _draw_relay(view: Rect2, alpha: float, unfold: float, finished: bool) -> void:
	var points: PackedVector2Array = _objective.get("route_points", PackedVector2Array())
	var done := clampi(int(_objective.get("progress", 0)), 0, points.size())
	for index in mini(3, points.size()):
		var point := points[index]
		if not view.has_point(point):
			continue
		var current := index == done and not _is_terminal(_objective)
		var lit := index < done or finished
		var tint: Color = Art.FOLD if lit else Art.GOLD
		var opacity := alpha * (1.0 if current or lit else 0.38)
		if current:
			_draw_boundary(point, float(_objective.get("capture_radius", 90.0)), Art.GOLD, bool(_objective.get("occupied", false)), alpha)
		_plate(point + Vector2(0, 18), 33.0, 16.0, tint, opacity)
		var opening := unfold if finished else clampf(float(_objective.get("waypoint_hold", 0.0)) / 1.2, 0.0, 1.0) if current else (1.0 if lit else 0.0)
		var top := point + Vector2(0, -41 - opening * 10)
		_facet(PackedVector2Array([point + Vector2(-21, 10), top, point + Vector2(21, 10), point + Vector2(0, 25)]), tint.darkened(0.43 if not lit else 0.2), opacity)
		draw_line(top, point + Vector2(0, 24), Color(Art.PAPER, 0.6 * opacity), 1.5, true)
		_label(point + Vector2(0, -60), "%02d" % (index + 1), tint, opacity, 24)
		if current:
			draw_line(point + Vector2(-24, 38), point + Vector2(24, 38), Color(Art.PAPER, 0.2 * alpha), 3.0, true)
			draw_line(point + Vector2(-24, 38), point + Vector2(-24 + 48 * opening, 38), Color(Art.GOLD, 0.8 * alpha), 3.0, true)
			_label(point + Vector2(0, 76), "接力 · 驻留 %.1f / 1.2" % float(_objective.get("waypoint_hold", 0.0)), Art.GOLD, alpha, 21)


func _draw_crown(point: Vector2, alpha: float, unfold: float) -> void:
	var at := point + Vector2(0, -65 - unfold * 12)
	var crown := PackedVector2Array([at + Vector2(-25, 9), at + Vector2(-30, -16), at + Vector2(-13, -5), at + Vector2(0, -28), at + Vector2(14, -5), at + Vector2(30, -16), at + Vector2(24, 9)])
	_facet(crown, Art.GOLD.darkened(0.10), alpha)
	for side in [-1.0, 1.0]:
		var tip := at + Vector2(side * 27, 9)
		_facet(PackedVector2Array([tip, tip + Vector2(side * 10, 22), tip + Vector2(side * 3, 19), tip + Vector2(-side * 3, 28), tip + Vector2(-side * 8, 3)]), Art.DANGER.darkened(0.32), alpha)


func _draw_flag_remnant(point: Vector2, alpha: float, unfold: float) -> void:
	_plate(point + Vector2(0, 20), 38, 21, Art.DANGER, alpha)
	for side in [-1.0, 1.0]:
		var at := point + Vector2(side * (10 + 26 * unfold), 9 + 15 * unfold)
		_facet(PackedVector2Array([at + Vector2(-14, -18), at + Vector2(19, -5), at + Vector2(5, 15)]), Art.DANGER.darkened(0.27), alpha)
	draw_line(point + Vector2(-10, 17), point + Vector2(26 + unfold * 24, -15 + unfold * 24), Color(Art.PAPER, 0.65 * alpha), 3.0, true)


func _draw_kill_marks(point: Vector2, alpha: float) -> void:
	var at := point + Vector2(-49, -76)
	var fade := alpha * clampf(_feedback_left / 0.15, 0.0, 1.0)
	for index in 10:
		var lit := index < int(_objective.get("progress", 0))
		var tick := at + Vector2(index * 11, 0)
		draw_line(tick, tick + Vector2(3, -12), Color(Art.GOLD if lit else Art.PAPER, (0.78 if lit else 0.18) * fade), 2.5, true)


func _plate(at: Vector2, width: float, depth: float, color: Color, alpha: float) -> void:
	var points := PackedVector2Array([at + Vector2(-width, 0), at + Vector2(0, -depth), at + Vector2(width, 0), at + Vector2(0, depth)])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(3, 7))
	draw_colored_polygon(shadow, Color(Art.INK, 0.42 * alpha))
	_facet(points, color.darkened(0.70), alpha)


func _facet(points: PackedVector2Array, color: Color, alpha: float) -> void:
	draw_colored_polygon(points, Color(color, alpha))
	if points.size() >= 4:
		draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2]]), Color(color.lightened(0.13), alpha))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(Art.PAPER, 0.30 * alpha), 1.2, true)


func _label(at: Vector2, value: String, color: Color, alpha: float, size: int = 23) -> void:
	var font := FoldlightTheme.WEB_FONT
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(font, at + Vector2(-width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Color(color, 0.82 * alpha))
