class_name FoldlightEndlessZoneDirector
extends RefCounted
## Uses only the authoritative active-combat clock. No wall clock, player damage,
## physics, global RNG or automatic processing lives in this scheduler.

const MapDefinition = preload("res://scripts/endless/endless_map_definition.gd")
const DEFAULT_RULES := {
	"first_warning_seconds": 60.0,
	"warning_seconds": 12.0,
	"closed_seconds": 24.0,
	"rest_seconds": 10.0,
	"two_zone_after_seconds": 180.0,
	"entry_grace_seconds": 2.0,
	"damage_interval": 2.0,
	"damage": 1,
}

var _map: FoldlightEndlessMapDefinition
var _seed: int = 0
var _rules: Dictionary = DEFAULT_RULES.duplicate()
var _clock: float = 0.0
var _cycle: int = -1
var _phase: StringName = &"rest"
var _remaining: float = 60.0
var _selected: Array[int] = []


func reset(definition: FoldlightEndlessMapDefinition, run_seed: int, options: Dictionary = {}) -> Dictionary:
	_map = definition
	_seed = run_seed
	_rules = DEFAULT_RULES.duplicate()
	for key: String in DEFAULT_RULES:
		if options.has(key):
			_rules[key] = maxf(0.01, float(options[key]))
	_rules["damage"] = maxi(1, int(_rules["damage"]))
	_clock = 0.0
	_cycle = -1
	_phase = &"rest"
	_remaining = float(_rules["first_warning_seconds"])
	_selected.clear()
	return get_snapshot()


func advance_to(combat_seconds: float, protected_points: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	# A stale callback must not rewind a live closure. Reset is the only rewind.
	if not is_finite(combat_seconds):
		return get_snapshot()
	_clock = maxf(_clock, maxf(combat_seconds, 0.0))
	var first := float(_rules["first_warning_seconds"])
	if _clock < first:
		_remaining = first - _clock
		return get_snapshot()
	var warning := float(_rules["warning_seconds"])
	var closed := float(_rules["closed_seconds"])
	var period := warning + closed + float(_rules["rest_seconds"])
	var next_cycle := int(floor((_clock - first) / period))
	var phase_time := fposmod(_clock - first, period)
	if next_cycle != _cycle:
		_cycle = next_cycle
		_select_zones(first + float(_cycle) * period, protected_points)
	if phase_time < warning:
		_phase = &"warning"
		_remaining = warning - phase_time
	elif phase_time < warning + closed:
		_phase = &"closed"
		_remaining = warning + closed - phase_time
	else:
		_phase = &"rest"
		_remaining = period - phase_time
	return get_snapshot()


func get_snapshot() -> Dictionary:
	var zones: Array[Dictionary] = []
	var warning_ids: Array[StringName] = []
	var closed_ids: Array[StringName] = []
	if _map != null:
		for index in _map.closure_zone_rects.size():
			var state: StringName = _phase if index in _selected and _phase != &"rest" else &"open"
			var id: StringName = _map.closure_zone_ids[index]
			zones.append({"id": id, "title": _map.closure_zone_names[index], "rect": _map.closure_zone_rects[index], "state": state, "seconds_remaining": _remaining if state != &"open" else 0.0})
			if state == &"warning":
				warning_ids.append(id)
			elif state == &"closed":
				closed_ids.append(id)
	return {
		"map_id": _map.map_id if _map != null else &"",
		"phase": _phase, "cycle": _cycle, "remaining": _remaining, "combat_time": _clock,
		"zones": zones, "warning_ids": warning_ids, "closed_ids": closed_ids,
		"safe_corridors": _map.safe_corridors.duplicate() if _map != null else [],
		"refuges": _map.refuge_points if _map != null else PackedVector2Array(),
		"rules": _rules.duplicate(),
	}


func is_point_closed(point: Vector2) -> bool:
	return MapDefinition.is_point_reserved_in_snapshot(point, get_snapshot(), 0.0, true)


func is_point_reserved(point: Vector2, clearance: float = 0.0) -> bool:
	return MapDefinition.is_point_reserved_in_snapshot(point, get_snapshot(), clearance)


func get_nearest_safe_position(point: Vector2, route_provider: Object = null, clearance: float = 13.0) -> Vector2:
	# Real play passes the configured map runtime so the arrow follows cover.
	if is_instance_valid(route_provider) and route_provider.has_method("get_nearest_safe_position"):
		return Vector2(route_provider.call("get_nearest_safe_position", point, clearance))
	if _map == null or _map.refuge_points.is_empty():
		return point
	var nearest := _map.refuge_points[0]
	for refuge in _map.refuge_points:
		if refuge.distance_squared_to(point) < nearest.distance_squared_to(point):
			nearest = refuge
	return nearest


func _select_zones(warning_start: float, protected_points: PackedVector2Array) -> void:
	_selected.clear()
	if _map == null:
		return
	# Independent per-cycle RNG makes skipped ticks and unrelated combat random
	# calls irrelevant. Active objective protection is an explicit input.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("foldlight-sea/%d/%d/%s" % [_seed, _cycle, _map.map_id])
	var available: Array[int] = []
	for index in _map.closure_zone_rects.size():
		var blocked := false
		var rect := _map.closure_zone_rects[index].grow(260.0)
		for point in protected_points:
			if rect.has_point(point):
				blocked = true
				break
		if not blocked:
			available.append(index)
	var maximum := 2 if warning_start >= float(_rules["two_zone_after_seconds"]) else 1
	while not available.is_empty() and _selected.size() < maximum:
		var slot := rng.randi_range(0, available.size() - 1)
		_selected.append(available[slot])
		available.remove_at(slot)
