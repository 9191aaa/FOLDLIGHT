class_name FoldlightEndlessInversionField
extends Node2D
## A fixed, telegraphed late-run control hazard. Only horizontal input changes;
## entering/exiting never alters an already-running dash or stored projectiles.

const WARNING_SECONDS := 3.0
const ACTIVE_SECONDS := 14.0
const RADIUS := 330.0
const COLOR := Color(0.63, 0.52, 0.73)
var _map: FoldlightEndlessMapDefinition
var _routes: FoldlightEndlessHandcraftedMap
var _seed := 0
var _cycle := 0
var _state: StringName = &"rest"
var _remaining := 0.0
var _next_at := 0.0
var _center := Vector2.ZERO
var _inside := false


func configure(definition: FoldlightEndlessMapDefinition, routes: FoldlightEndlessHandcraftedMap, run_seed: int) -> void:
	_map = definition
	_routes = routes
	_seed = run_seed
	_cycle = 0
	_next_at = 0.0
	_state = &"rest"
	_remaining = 0.0
	_inside = false
	z_index = 7
	queue_redraw()


func advance(delta: float, combat_seconds: float, level: int, player_position: Vector2, protected_points: PackedVector2Array) -> bool:
	if _map == null or not is_finite(delta) or delta <= 0.0:
		return _inside
	var step := minf(delta, 0.1)
	var changed := false
	if _state == &"rest":
		if (level >= 18 or combat_seconds >= 720.0) and combat_seconds >= _next_at:
			if _select_position(player_position, protected_points):
				_state = &"warning"
				_remaining = WARNING_SECONDS
				_cycle += 1
				changed = true
			else:
				_next_at = combat_seconds + 8.0
	else:
		_remaining = maxf(0.0, _remaining - step)
		if _remaining <= 0.00001:
			if _state == &"warning":
				_state = &"active"
				_remaining = ACTIVE_SECONDS
			else:
				_state = &"rest"
				_next_at = combat_seconds + maxf(24.0, 55.0 - maxf(0.0, level - 18) * 1.4)
			changed = true
	_inside = _state == &"active" and player_position.distance_squared_to(_center) <= RADIUS * RADIUS
	if changed:
		queue_redraw()
	return _inside


func cancel() -> void:
	_state = &"rest"
	_remaining = 0.0
	_inside = false
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {"state": _state, "position": _center, "radius": RADIUS,
		"remaining": _remaining, "inside": _inside, "cycle": _cycle, "axis": &"horizontal"}


func _select_position(player_position: Vector2, protected_points: PackedVector2Array) -> bool:
	for index in 25:
		var angle := TAU * float(posmod(_seed + _cycle * 11 + index * 7, 24)) / 24.0
		var candidate := player_position if index == 0 else player_position + Vector2.from_angle(angle) * (410.0 + (index % 3) * 100.0)
		if not _map.bounds.grow(-RADIUS).has_point(candidate) or _routes.is_point_blocked(candidate, 32.0):
			continue
		var protected := false
		for point in protected_points:
			if candidate.distance_squared_to(point) < pow(RADIUS + 300.0, 2.0):
				protected = true
				break
		if protected:
			continue
		_center = candidate
		return true
	return false


func _draw() -> void:
	if _state == &"rest":
		return
	var warning := _state == &"warning"
	draw_circle(_center, RADIUS, Color(COLOR, 0.07 if warning else 0.12))
	draw_arc(_center, RADIUS, 0.0, TAU, 48, Color(COLOR, 0.8), 4.0, true)
	# Static lanes and opposing arrows communicate inversion without a pulse,
	# screen flash, camera flip, or visual distortion over the enemy bullets.
	for index in 9:
		var y := float(index - 4) * 63.0
		var half_width := sqrt(maxf(0.0, RADIUS * RADIUS - y * y))
		draw_line(_center + Vector2(-half_width, y), _center + Vector2(half_width, y), Color(COLOR, 0.17 if warning else 0.28), 2.0, true)
	for sign_value in [-1.0, 1.0]:
		var origin := _center + Vector2(0, sign_value * 45)
		var tip := origin + Vector2(sign_value * 130, 0)
		draw_line(origin - Vector2(sign_value * 130, 0), tip, COLOR, 4.0, true)
		draw_polyline(PackedVector2Array([tip + Vector2(-sign_value * 30, -22), tip, tip + Vector2(-sign_value * 30, 22)]), COLOR, 4.0, true)
