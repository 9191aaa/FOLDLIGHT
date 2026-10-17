extends RefCounted
## One immutable cast plan drives both visible lanes and actual shots. No RNG,
## scene references, timers or shared mutable Resource state live here.

const NEW_IDS: Array[StringName] = [&"tide_loom_mother", &"torn_page_executioner", &"eclipse_twin_bells"]
const REACH: float = 1100.0


static func build(pattern: StringName, origin: Vector2, target: Vector2, phase: int, cast_index: int, legal_bounds: Rect2) -> Dictionary:
	var aim := origin.direction_to(target)
	if aim.is_zero_approx():
		aim = Vector2.DOWN
	var plan := {"volleys": [], "lanes": [], "gaps": [], "dash_end": origin}
	match pattern:
		&"loom_shuttle":
			_comb(plan, origin, aim, 0.0, 7, 3, 2, 275.0 + phase * 12.0)
			_comb(plan, origin, aim, 0.42, 7, 3, 2, 275.0 + phase * 12.0, false)
		&"loom_crossweave":
			_comb(plan, origin, aim.rotated(-0.46), 0.0, 5, 2, 1, 260.0)
			_comb(plan, origin, aim.rotated(0.46), 0.48, 5, 2, 1, 260.0)
		&"loom_needle":
			for side in [-1.0, 1.0]:
				_fan(plan, origin + aim.orthogonal() * side * 146.0, aim, 3, 0.16, 365.0, false, 0.0)
		&"execution_dash":
			var distance := clampf(origin.distance_to(target) + 90.0, 180.0, 560.0)
			var end := (origin + aim * distance).clamp(legal_bounds.position, legal_bounds.end)
			plan["dash_end"] = end
			(plan["lanes"] as Array).append({"origin": origin, "end": end, "width": 112.0, "reflectable": false, "dash": true})
		&"execution_rake":
			_fan(plan, origin, aim, 5 + phase, 0.78, 390.0, false, 0.0)
		&"execution_counterfold":
			_ring(plan, origin, aim.angle(), 0.74, 12, 285.0, 0.0)
		&"bell_alternation", &"eclipse_procession":
			var order := -1.0 if cast_index % 2 == 0 else 1.0
			for index in 2:
				var side := order if index == 0 else -order
				var bell_origin := origin + Vector2(side * 106.0, 10.0)
				var turn := side * (0.36 if pattern == &"bell_alternation" else 0.62)
				_ring(plan, bell_origin, aim.angle() + turn, 0.78, 10 + phase, 245.0 + phase * 10.0, float(index) * 0.52)
		&"eclipse_chime_cut":
			for side in [-1.0, 1.0]:
				var bell_origin := origin + Vector2(side * 106.0, 10.0)
				_fan(plan, bell_origin, bell_origin.direction_to(target), 4, 0.54, 325.0, true, 0.0)
	return plan


static func _comb(plan: Dictionary, origin: Vector2, aim: Vector2, at: float, count: int, gap_start: int, gap_count: int, speed: float, warn: bool = true) -> void:
	var side := aim.orthogonal()
	for index in count:
		if index >= gap_start and index < gap_start + gap_count:
			continue
		var lane_origin := origin + side * (float(index) - float(count - 1) * 0.5) * 58.0
		_fan(plan, lane_origin, aim, 1, 0.0, speed, true, at, warn)
	if warn:
		var gap_center := origin + side * (float(gap_start) + float(gap_count - 1) * 0.5 - float(count - 1) * 0.5) * 58.0
		(plan["gaps"] as Array).append({"origin": gap_center, "direction": aim, "width": float(gap_count) * 58.0 - 20.0, "reach": REACH})


static func _fan(plan: Dictionary, origin: Vector2, aim: Vector2, count: int, spread: float, speed: float, reflectable: bool, at: float, warn: bool = true) -> void:
	if aim.is_zero_approx():
		aim = Vector2.DOWN
	var snapshot := _snapshot(origin, aim, speed, reflectable)
	snapshot["projectile_count"] = count
	snapshot["spread_radians"] = spread
	(plan["volleys"] as Array).append({"at": at, "snapshot": snapshot})
	if warn:
		for index in count:
			var unit := 0.0 if count == 1 else float(index) / float(count - 1) - 0.5
			(plan["lanes"] as Array).append({"origin": origin, "end": origin + aim.rotated(unit * spread) * REACH, "width": 22.0, "reflectable": reflectable})


static func _ring(plan: Dictionary, origin: Vector2, gap_angle: float, gap_half: float, count: int, speed: float, at: float) -> void:
	var snapshot := _snapshot(origin, Vector2.from_angle(gap_angle), speed, true)
	var shots: Array[Dictionary] = []
	for index in count:
		var angle := gap_angle + float(index) * TAU / float(count)
		if absf(wrapf(angle - gap_angle, -PI, PI)) < gap_half:
			continue
		var direction := Vector2.from_angle(angle)
		shots.append({"direction": direction, "speed": speed})
		(plan["lanes"] as Array).append({"origin": origin, "end": origin + direction * REACH, "width": 22.0, "reflectable": true})
	snapshot["projectiles"] = shots
	snapshot["projectile_count"] = shots.size()
	(plan["volleys"] as Array).append({"at": at, "snapshot": snapshot})
	(plan["gaps"] as Array).append({"origin": origin, "direction": Vector2.from_angle(gap_angle), "half_angle": gap_half, "reach": 360.0})


static func _snapshot(origin: Vector2, direction: Vector2, speed: float, reflectable: bool) -> Dictionary:
	return {"origin": origin, "direction": direction, "speed": speed, "reflectable": reflectable, "damage": 1.0, "radius": 8.0 if reflectable else 10.0, "lifetime": 4.0, "radial": false, "style": &"reef_petal" if reflectable else &"black_gold_cut", "burst_count": 1}
