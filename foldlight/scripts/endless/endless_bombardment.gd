class_name FoldlightEndlessBombardment
extends Node2D
## The warning, painted landing sites and single damage edge share one bounded
## visible clock. No Timer/tween can finish an attack behind a reward or pause.

const WARNING_SECONDS := 3.2
const IMPACT_SECONDS := 0.55
const BOSS_ARRIVAL_DELAY := 4.0
const BOSS_REST_SECONDS := 14.0
const DEEP_BOSS_REST_SECONDS := 8.0
const RenderRedraw = preload("res://scripts/visuals/render_redraw.gd")
var _seed: int = 0
var _cycle: int = 0
var _state: StringName = &"rest"
var _remaining: float = 0.0
var _next_at: float = 90.0
var _zones: Array[Dictionary] = []
var _map: FoldlightEndlessMapDefinition
var _map_runtime: FoldlightEndlessHandcraftedMap
var _paint_clock: float = 0.0
var _previous_boss_count: int = 0
var _enabled: bool = false


func configure(definition: FoldlightEndlessMapDefinition, route_provider: FoldlightEndlessHandcraftedMap, run_seed: int) -> void:
	_map = definition
	_map_runtime = route_provider
	_seed = run_seed
	_cycle = 0
	_state = &"rest"
	_remaining = 0.0
	_next_at = 90.0
	_zones.clear()
	_paint_clock = 0.0
	_previous_boss_count = 0
	_enabled = true
	z_index = 8
	RenderRedraw.request(self)


func advance(delta: float, combat_seconds: float, player_position: Vector2, protected_points: PackedVector2Array, boss_count: int = 0) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	if not _enabled or _map == null or not is_finite(delta) or delta <= 0.0:
		return impacts
	var step := minf(delta, 0.1)
	var state_before := _state
	var bosses := maxi(0, boss_count)
	if _state == &"rest":
		# Arrival accelerates only rest. An announced site stays locked until
		# impact, including if more bosses arrive while the player is dodging.
		if bosses > 0 and _previous_boss_count == 0:
			_next_at = minf(_next_at, combat_seconds + BOSS_ARRIVAL_DELAY)
		if combat_seconds >= _next_at:
			_select_sites(player_position, protected_points, bosses, combat_seconds)
			_cycle += 1
			if not _zones.is_empty():
				_state = &"warning"
				_remaining = WARNING_SECONDS
			else:
				_next_at = combat_seconds + 8.0
	elif _state == &"warning":
		_remaining = maxf(0.0, _remaining - step)
		if _remaining <= 0.00001:
			_state = &"impact"
			_remaining = IMPACT_SECONDS
			impacts = _zones.duplicate(true)
	elif _state == &"impact":
		_remaining = maxf(0.0, _remaining - step)
		if _remaining <= 0.00001:
			_state = &"rest"
			_zones.clear()
			_next_at = combat_seconds + rest_interval(combat_seconds, bosses)
	_previous_boss_count = bosses
	if _state != &"rest":
		_paint_clock += step
	if state_before != _state or _paint_clock >= 0.05:
		_paint_clock = 0.0
		RenderRedraw.request(self)
	return impacts


func rest_interval(combat_seconds: float, boss_count: int) -> float:
	if boss_count > 0:
		return maxf(DEEP_BOSS_REST_SECONDS, BOSS_REST_SECONDS - maxf(0.0, combat_seconds - 90.0) / 90.0)
	return maxf(18.0, 30.0 - combat_seconds / 90.0)


func get_snapshot() -> Dictionary:
	return {"state": _state, "warning_remaining": _remaining if _state == &"warning" else 0.0, "remaining": _remaining, "cycle": _cycle, "zones": _zones.duplicate(true), "damage": 1, "next_at": _next_at, "boss_pressure": _previous_boss_count > 0}


func cancel() -> void:
	_state = &"rest"
	_zones.clear()
	_remaining = 0.0
	_previous_boss_count = 0
	_enabled = false
	RenderRedraw.request(self)


func _select_sites(player_position: Vector2, protected_points: PackedVector2Array, boss_count: int, combat_seconds: float) -> void:
	_zones.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("foldlight-bombard/%d/%d" % [_seed, _cycle])
	var count := 2 if boss_count > 0 else mini(5, 3 + int(combat_seconds / 300.0))
	var radius := minf(145.0, 110.0 + combat_seconds / 40.0)
	for index in 32:
		var point := player_position if index == 0 else player_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(240.0, 660.0)
		if not _map.bounds.grow(-radius).has_point(point) or _map_runtime.is_point_blocked(point, 26.0):
			continue
		var protected := false
		for safe_point in protected_points:
			if point.distance_squared_to(safe_point) < pow(radius + 300.0, 2.0):
				protected = true
				break
		for zone in _zones:
			if point.distance_squared_to(Vector2(zone.position)) < pow(radius * 2.0 + 70.0, 2.0):
				protected = true
		if protected:
			continue
		_zones.append({"position": point, "radius": radius})
		if _zones.size() >= count:
			break


func _draw() -> void:
	for zone in _zones:
		var point := Vector2(zone.position)
		var radius := float(zone.radius)
		if _state == &"warning":
			var progress := 1.0 - _remaining / WARNING_SECONDS
			draw_circle(point, radius, Color(1.0, 0.43, 0.14, 0.14))
			draw_arc(point, radius, 0.0, TAU, 40, Color(1.0, 0.68, 0.25, 0.95), 3.0, true)
			draw_arc(point, radius * (1.0 - progress), 0.0, TAU, 32, Color(1.0, 0.87, 0.52, 0.8), 2.0, true)
			for index in 4:
				var ray := Vector2.from_angle(TAU * float(index) / 4.0 + PI / 4.0)
				draw_line(point + ray * (radius - 16.0), point + ray * (radius + 17.0), Color(1.0, 0.72, 0.3), 4.0, true)
			draw_line(point - Vector2(12, 0), point + Vector2(12, 0), Color(1.0, 0.82, 0.4), 2.0)
			draw_line(point - Vector2(0, 12), point + Vector2(0, 12), Color(1.0, 0.82, 0.4), 2.0)
		elif _state == &"impact":
			var alpha := _remaining / IMPACT_SECONDS
			draw_circle(point, radius, Color(1.0, 0.58, 0.22, 0.38 * alpha))
			draw_arc(point, radius * (1.15 - alpha * 0.15), 0.0, TAU, 32, Color(1.0, 0.88, 0.58, alpha), 5.0, true)
