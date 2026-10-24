class_name FoldlightEndlessBossLockdown
extends Node2D
## One fixed arena per acknowledged encounter. Time advances only through the
## adapter's combat clock; rewards, solo host suspension and pauses freeze it.
const APPROACH_SECONDS := 90.0
const WARNING_SECONDS := 8.0
const GRACE_SECONDS := 2.0
const DAMAGE_INTERVAL := 2.0
const BASE_RADIUS := 1800.0
const COLOR := Color(0.76, 0.44, 0.36)
var _wave := -1
var _state: StringName = &"idle"
var _elapsed := 0.0
var _remaining := 0.0
var _exposure := 0.0
var _next_hit := GRACE_SECONDS
var _center := Vector2.ZERO
var _radius := BASE_RADIUS
var _outside := false
var _return_distance := 0.0
var _return_goal := Vector2.ZERO
var _return_route_valid := false


func advance(delta: float, director: Dictionary, bosses: Array[Dictionary], player_position: Vector2) -> bool:
	if StringName(director.get("state", &"waiting")) != &"active" or bosses.is_empty():
		cancel()
		return false
	if not is_finite(delta) or delta <= 0.0:
		return false
	var wave := int(director.get("wave_index", 0))
	if wave != _wave:
		cancel()
		_wave = wave
		_state = &"approach"
		_remaining = APPROACH_SECONDS
	var step := minf(delta, 0.1)
	_elapsed += step
	if _state == &"approach":
		_remaining = maxf(0.0, APPROACH_SECONDS - _elapsed)
		if _remaining <= 0.00001:
			_center = Vector2.ZERO
			for boss in bosses:
				_center += Vector2(boss.get("position", player_position))
			_center /= float(bosses.size())
			_radius = BASE_RADIUS + (bosses.size() - 1) * 120.0
			for boss in bosses:
				_radius = maxf(_radius, _center.distance_to(Vector2(boss.get("position", _center))) + 650.0)
			# Allow a distant explorer to return before damage starts. The warning
			# stays finite and never tracks the fleeing player or a moving boss.
			_remaining = maxf(WARNING_SECONDS, minf(30.0, (_center.distance_to(player_position) - _radius) / 280.0 + 3.0))
			_state = &"warning"
			queue_redraw()
	elif _state == &"warning":
		_remaining = maxf(0.0, _remaining - step)
		if _remaining <= 0.00001:
			_state = &"active"
			queue_redraw()
	_outside = _state in [&"warning", &"active"] and player_position.distance_squared_to(_center) > _radius * _radius
	if _state != &"active" or not _outside:
		_exposure = 0.0
		_next_hit = GRACE_SECONDS
		return false
	_exposure += step
	if _exposure + 0.00001 >= _next_hit:
		_next_hit += DAMAGE_INTERVAL
		return true
	return false


func cancel() -> void:
	if _state == &"idle":
		return
	_wave = -1
	_state = &"idle"
	_elapsed = 0.0
	_remaining = 0.0
	_exposure = 0.0
	_next_hit = GRACE_SECONDS
	_outside = false
	_return_distance = 0.0
	_return_route_valid = false
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {"state": _state, "wave_index": _wave, "elapsed": _elapsed,
		"position": _center, "radius": _radius, "outside": _outside,
		"remaining": _remaining, "seconds_until_damage": maxf(0.0, _next_hit - _exposure),
		"return_distance": _return_distance, "return_goal": _return_goal, "return_route_valid": _return_route_valid,
		"damage": 1, "damage_interval": DAMAGE_INTERVAL}


func return_waypoint(player_position: Vector2, routes: FoldlightEndlessHandcraftedMap, zones: FoldlightEndlessZoneDirector = null) -> Vector2:
	var candidates := PackedVector2Array()
	var map := routes.map_definition
	for refuge in map.refuge_points:
		if refuge.distance_to(_center) < _radius - 100.0: candidates.append(refuge)
	for corridor in map.safe_corridors:
		var inner := corridor.grow(-45.0)
		for point in [player_position.clamp(inner.position, inner.end), _center.clamp(inner.position, inner.end), inner.get_center()]:
			if Vector2(point).distance_to(_center) < _radius - 100.0: candidates.append(point)
	# Prefer actual permanent refuges inside the circle. Geometric samples are
	# fallback only; a blocked or closed point is never advertised as a refuge.
	var toward := (_center - player_position).normalized()
	var include_fallback := candidates.is_empty()
	for index in 25:
		var point := _center if index == 24 else _center + (-toward).rotated(float(index) * TAU / 24.0) * (_radius - 150.0)
		if map.is_permanent_safe(point, 40.0) or include_fallback: candidates.append(point)
	var sorted: Array[Vector2] = []
	for point in candidates:
		if map.bounds.grow(-40.0).has_point(point) and not routes.is_point_blocked(point, 40.0) and (zones == null or (not zones.is_point_closed(point) and not zones.is_point_reserved(point))):
			sorted.append(point)
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return player_position.distance_squared_to(a) < player_position.distance_squared_to(b))
	var best_route := PackedVector2Array()
	var best_cost := INF
	_return_route_valid = false
	_return_distance = 0.0
	for index in mini(10, sorted.size()):
		var path := routes.find_cover_route(player_position, sorted[index], 32.0)
		if path.is_empty(): continue
		var cursor := player_position
		var length := 0.0
		var penalty := 0.0
		for point in path:
			var segment := cursor.distance_to(point)
			length += segment
			if zones != null:
				var samples := maxi(1, ceili(segment / 120.0))
				for sample in samples:
					var along := cursor.lerp(point, (float(sample) + 0.5) / float(samples))
					if zones.is_point_closed(along) or zones.is_point_reserved(along): penalty += segment / float(samples) * 4.0
			cursor = point
		if length + penalty < best_cost:
			best_cost = length + penalty
			best_route = path
			_return_distance = length
			_return_goal = sorted[index]
			_return_route_valid = true
	for point in best_route:
		if player_position.distance_squared_to(point) > 48.0 * 48.0:
			return point
	return player_position


func extend_return_warning() -> void:
	if _state == &"warning" and _outside and _return_route_valid:
		_remaining = maxf(_remaining, _return_distance / 280.0 + 3.0)


func _draw() -> void:
	if _state not in [&"warning", &"active"]:
		return
	# A dark-backed static perimeter keeps the arena legible without filling the
	# screen or competing with projectile telegraphs.
	draw_arc(_center, _radius, 0, TAU, 144, Color(0.06, 0.09, 0.12, 0.92), 18.0, true)
	draw_arc(_center, _radius, 0, TAU, 144, Color(COLOR, 0.65 if _state == &"warning" else 0.95), 5.0, true)
	for index in 48:
		var direction := Vector2.from_angle(float(index) * TAU / 48.0)
		var tip := _center + direction * (_radius - 28.0)
		var side := direction.orthogonal() * 13.0
		draw_polyline(PackedVector2Array([tip + direction * 23.0 + side, tip, tip + direction * 23.0 - side]), COLOR, 3.0, true)
