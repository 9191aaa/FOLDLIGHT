class_name FoldlightEndlessObjectiveDirector
extends Node

signal objective_started(snapshot: Dictionary)
signal objective_progressed(snapshot: Dictionary)
signal objective_completed(snapshot: Dictionary)
signal objective_failed(snapshot: Dictionary)

const MapRules = preload("res://scripts/endless/endless_map_definition.gd")
const OBJECTIVE_ROTATION: Array[StringName] = [
	&"capture_point", &"defeat_captain", &"destroy_flag",
	&"relay_route", &"capture_storm", &"clear_swarm",
	&"escort",
]
const OPENING_TASK_COUNT: int = 6
const ESCORT_RADIUS: float = 280.0
const ESCORT_SPEED: float = 110.0
const ESCORT_CONTESTED_SPEED: float = 0.35
const CAPTURE_RADIUS: float = 170.0
const RETURN_CHARGE_REQUIRED: int = 4
const RETURN_BOOST_SECONDS: float = 2.0
const RETURN_BOOST_MAX_SECONDS: float = 6.0
const RELAY_RADIUS: float = 90.0
const RELAY_HOLD_SECONDS: float = 1.2
const RELAY_COUNT: int = 3
const STORM_RADIUS: float = 240.0
const STORM_REQUIRED: int = 12
const SWARM_REQUIRED: int = 10

var config: FoldlightEndlessSurvivalConfig
var map_definition: FoldlightEndlessMapDefinition
var current: Dictionary = {}
var rotation_index: int = 0
var completion_count: int = 0
var failure_count: int = 0
var _intermission_remaining: float = 0.0
var _progress_emit_clock: float = 0.0
var _run_generation: int = 0
var _task_serial: int = 0
var _district_access: Dictionary = {}
var _site_cursors: Dictionary = {}
var _defeated_ids: Dictionary = {}
var _last_return_release_id: int = 0
var _rng := RandomNumberGenerator.new()
var _progression: Dictionary = {}
var _last_player_position := Vector2.ZERO
var _route_provider: Callable
var _task_bag: Array[StringName] = []


func reset(run_config: FoldlightEndlessSurvivalConfig, definition: FoldlightEndlessMapDefinition, seed: int, progression: Dictionary = {}) -> void:
	config = run_config
	map_definition = definition
	# Retain the original three opening tasks for existing seeds.
	rotation_index = posmod(seed, 3)
	_run_generation += 1
	_task_serial = 0
	_progression = progression.duplicate(true)
	_last_player_position = map_definition.player_spawn
	_task_bag.clear()
	_rng.seed = seed
	_site_cursors.clear()
	for kind in OBJECTIVE_ROTATION:
		_site_cursors[kind] = _rng.randi_range(0, maxi(0, _sites_for(kind).size() - 1))
	completion_count = 0
	failure_count = 0
	_intermission_remaining = 0.0
	_progress_emit_clock = 0.0
	_start_current_objective()


func bind_route_provider(provider: Callable) -> void:
	_route_provider = provider


func set_progression_context(snapshot: Dictionary, player_position: Vector2) -> void:
	# Only a future task reads this context. Active targets, health and deadlines
	# are immutable snapshots, even if the player levels up midway through one.
	_progression = snapshot.duplicate(true)
	if player_position.is_finite():
		_last_player_position = player_position


func set_district_access(snapshot: Dictionary) -> void:
	# Only new tasks consult this mask. A live task is protected by the caller.
	_district_access = snapshot.duplicate(true)


func advance(delta: float, player_position: Vector2) -> void:
	if config == null or map_definition == null or not is_finite(delta) or delta <= 0.0 or not player_position.is_finite():
		return
	if not current.is_empty():
		current["player_position"] = player_position
		current["occupied"] = _is_active() and player_position.distance_to(Vector2(current["target_position"])) <= float(current["capture_radius"])
	_last_player_position = player_position
	if not _is_active():
		if current.is_empty():
			return
		_intermission_remaining = maxf(0.0, _intermission_remaining - delta)
		if _intermission_remaining <= 0.0:
			rotation_index += 1
			_start_current_objective()
		return
	# Residence outside the deadline must not rescue an expired task.
	var step := minf(delta, float(current["time_remaining"]))
	current["time_remaining"] = maxf(0.0, float(current["time_remaining"]) - step)
	var kind := StringName(current["kind"])
	if kind == &"capture_point":
		var progress := float(current["progress"])
		if player_position.distance_to(Vector2(current["target_position"])) <= CAPTURE_RADIUS:
			progress += step
		else:
			progress = maxf(0.0, progress - step * 0.35)
		current["progress"] = minf(progress, float(current["required"]))
		if progress >= float(current["required"]):
			_complete_current()
			return
	elif kind == &"relay_route":
		var hold := float(current.get("waypoint_hold", 0.0))
		if player_position.distance_to(Vector2(current["target_position"])) <= RELAY_RADIUS:
			hold += step
		else:
			hold = 0.0
		current["waypoint_hold"] = minf(hold, RELAY_HOLD_SECONDS)
		if hold >= RELAY_HOLD_SECONDS:
			current["progress"] = float(current["progress"]) + 1.0
			current["waypoint_hold"] = 0.0
			if float(current["progress"]) >= float(current["required"]):
				_complete_current()
				return
			current["target_position"] = (current["route_points"] as PackedVector2Array)[int(current["progress"])]
	elif kind == &"escort":
		_advance_escort(step, player_position)
		if not _is_active():
			return
	_progress_emit_clock -= step
	if float(current["time_remaining"]) <= 0.0:
		_fail_current()
	elif _progress_emit_clock <= 0.0:
		_progress_emit_clock = 0.2
		objective_progressed.emit(get_snapshot())


func report_captain_defeated(captain_id: StringName = &"") -> bool:
	if not _matches_target(&"defeat_captain", captain_id):
		return false
	current["progress"] = 1.0
	_complete_current()
	return true


func report_escort_pressure(enemy_count: int) -> void:
	if _is_active() and StringName(current["kind"]) == &"escort":
		current["escort_threat_count"] = clampi(enemy_count, 0, 48)


func _advance_escort(delta: float, player_position: Vector2) -> void:
	var position := Vector2(current["escort_position"])
	var nearby := position.distance_to(player_position) <= ESCORT_RADIUS
	var contested := int(current.get("escort_threat_count", 0)) > 0
	current["occupied"] = nearby
	current["escort_state"] = &"waiting_player" if not nearby else (&"contested" if contested else &"moving")
	current["escort_moving"] = nearby
	if not nearby:
		return
	var remaining := ESCORT_SPEED * delta * (ESCORT_CONTESTED_SPEED if contested else 1.0)
	var route: PackedVector2Array = current["escort_route"]
	var index := int(current["escort_waypoint_index"])
	while remaining > 0.001 and index < route.size():
		var offset := route[index] - position
		var distance := offset.length()
		if distance <= 0.01:
			index += 1
			continue
		var direction := offset / distance
		# Even a long simulation frame cannot carry the boat outside the
		# player's escort circle. Solve the forward circle exit distance.
		var player_offset := position - player_position
		var projection := player_offset.dot(direction)
		var radius_exit := maxf(0.0, -projection + sqrt(maxf(0.0, projection * projection + ESCORT_RADIUS * ESCORT_RADIUS - player_offset.length_squared())))
		var travel := minf(minf(distance, remaining), radius_exit)
		position += direction * travel
		remaining -= travel
		current["progress"] = minf(float(current["required"]), float(current["progress"]) + travel)
		if travel < distance - 0.01:
			break
		index += 1
	current["escort_waypoint_index"] = index
	current["escort_position"] = position
	current["target_position"] = position
	current["escort_progress"] = clampf(float(current["progress"]) / float(current["required"]), 0.0, 1.0)
	if index >= route.size():
		current["escort_progress"] = 1.0
		current["escort_moving"] = false
		_complete_current()


func report_enemy_defeated(target_id: StringName, is_captain: bool = false) -> bool:
	if not _is_active() or target_id == &"":
		return false
	if StringName(current["kind"]) == &"defeat_captain":
		return report_captain_defeated(target_id) if is_captain else false
	if StringName(current["kind"]) != &"clear_swarm" or _defeated_ids.has(target_id):
		return false
	_defeated_ids[target_id] = true
	return _add_progress(1.0)


func report_projectiles_absorbed(count: int, player_position: Vector2) -> bool:
	if not _is_active() or StringName(current["kind"]) != &"capture_storm" or count <= 0 or not player_position.is_finite():
		return false
	if player_position.distance_to(Vector2(current["target_position"])) > STORM_RADIUS:
		return false
	return _add_progress(float(count))


func report_returned_light(count: int, player_position: Vector2, objective_id: StringName, release_id: int) -> bool:
	# A release belongs to the task that was active when Fold began. Identity
	# and a consumed release serial reject delayed callbacks and duplicate events.
	if not _matches_target(&"capture_point", objective_id) or count <= 0 or release_id <= 0 or not player_position.is_finite():
		return false
	if float(current["time_remaining"]) <= 0.0 or release_id <= _last_return_release_id:
		return false
	# Release serials increase monotonically. Consume even an outside release so
	# walking into the circle cannot replay it, without retaining an event list.
	_last_return_release_id = release_id
	if player_position.distance_to(Vector2(current["target_position"])) > CAPTURE_RADIUS:
		return false
	var previous_boost := float(current.get("return_boost_seconds", 0.0))
	if previous_boost >= RETURN_BOOST_MAX_SECONDS:
		return false
	current["player_position"] = player_position
	current["occupied"] = true
	var maximum_count := int(RETURN_BOOST_MAX_SECONDS / RETURN_BOOST_SECONDS) * RETURN_CHARGE_REQUIRED
	current["return_charge_count"] = mini(maximum_count, int(current.get("return_charge_count", 0)) + mini(count, maximum_count))
	var next_boost := minf(RETURN_BOOST_MAX_SECONDS, floorf(float(current["return_charge_count"]) / float(RETURN_CHARGE_REQUIRED)) * RETURN_BOOST_SECONDS)
	current["return_boost_seconds"] = next_boost
	if next_boost > previous_boost:
		return _add_progress(next_boost - previous_boost)
	objective_progressed.emit(get_snapshot())
	return true


func report_flag_damage(flag_id: StringName, damage: float) -> bool:
	if not _matches_target(&"destroy_flag", flag_id) or not is_finite(damage) or damage <= 0.0:
		return false
	return _add_progress(damage)


func report_flag_destroyed(flag_id: StringName = &"") -> bool:
	if not _matches_target(&"destroy_flag", flag_id):
		return false
	return report_flag_damage(flag_id, float(current["required"]) - float(current["progress"]))


func update_target_position(target_id: StringName, position: Vector2) -> bool:
	if not _matches_target(&"defeat_captain", target_id) or not position.is_finite():
		return false
	current["target_position"] = position
	return true


func get_snapshot() -> Dictionary:
	var snapshot := current.duplicate(true)
	snapshot["rotation_index"] = rotation_index
	snapshot["completion_count"] = completion_count
	snapshot["failure_count"] = failure_count
	snapshot["intermission_remaining"] = _intermission_remaining
	if current.is_empty():
		return snapshot
	var required := maxf(0.001, float(current["required"]))
	snapshot["progress_ratio"] = clampf(float(current["progress"]) / required, 0.0, 1.0)
	if StringName(current["kind"]) == &"escort":
		var route: PackedVector2Array = current["escort_route"]
		var index := mini(int(current["escort_waypoint_index"]), route.size() - 1)
		snapshot["escort_next_position"] = route[index]
		snapshot["escort_direction"] = Vector2(current["escort_position"]).direction_to(route[index])
	var spatial := StringName(current["kind"]) != &"clear_swarm"
	snapshot["target_active"] = _is_active() and spatial
	var protected_points := PackedVector2Array()
	var targets: Array[Dictionary] = []
	if spatial and StringName(current["kind"]) == &"escort":
		var route: PackedVector2Array = current["escort_route"]
		var position := Vector2(current["escort_position"])
		targets.append({"id": current["target_id"], "position": position, "kind": &"escort", "role": &"boat", "active": _is_active(), "completed": bool(current["completed"])})
		targets.append({"id": current["target_id"], "position": current["escort_destination"], "kind": &"escort", "role": &"destination", "active": _is_active(), "completed": bool(current["completed"])})
		if _is_active():
			protected_points.append(position)
			for index in range(int(current["escort_waypoint_index"]), route.size()):
				_append_segment_samples(protected_points, position, route[index])
				position = route[index]
	elif spatial:
		var points: PackedVector2Array = current.get("route_points", PackedVector2Array([Vector2(current["target_position"])]))
		for index in points.size():
			var done := StringName(current["kind"]) == &"relay_route" and index < int(current["progress"])
			targets.append({
				"id": current["target_id"], "position": points[index], "kind": current["kind"],
				"active": _is_active() and not done, "completed": done or bool(current["completed"]),
			})
			if _is_active() and not done:
				protected_points.append(points[index])
		if _is_active() and StringName(current["kind"]) == &"defeat_captain":
			var origin := Vector2(current["spawn_position"])
			if not protected_points.has(origin):
				protected_points.append(origin)
	snapshot["targets"] = targets
	snapshot["protected_points"] = protected_points
	snapshot["progress_text"] = _progress_text()
	return snapshot


func _is_active() -> bool:
	return not current.is_empty() and StringName(current.get("status", &"")) == &"active"


func _matches_target(kind: StringName, target_id: StringName) -> bool:
	return _is_active() and StringName(current["kind"]) == kind and target_id != &"" and target_id == StringName(current["target_id"])


func _add_progress(amount: float) -> bool:
	current["progress"] = minf(float(current["required"]), float(current["progress"]) + amount)
	if float(current["progress"]) >= float(current["required"]):
		_complete_current()
	else:
		objective_progressed.emit(get_snapshot())
	return true


func _start_current_objective() -> void:
	var kind := _next_kind()
	var tier := clampi(int(_progression.get("objective_tier", 0)), 0, 8)
	var relay_count := RELAY_COUNT + mini(2, tier / 3)
	var points := _select_sites(kind, relay_count if kind == &"relay_route" else 1)
	var escort_route := PackedVector2Array()
	if kind == &"escort" and not points.is_empty():
		escort_route = _build_escort_route(points[0], tier)
		if escort_route.is_empty():
			points.clear()
	# District closures may leave only three or four legal stops. Preserve a
	# real relay where possible, never repeat a stop to inflate the count.
	while kind == &"relay_route" and points.is_empty() and relay_count > RELAY_COUNT:
		relay_count -= 1
		points = _select_sites(kind, relay_count)
	if kind != &"clear_swarm" and points.is_empty():
		# All authored sites may be temporarily closed. Keep the task achievable.
		kind = &"clear_swarm"
	_task_serial += 1
	var target_id := StringName("endless_task_%d_%d_%s" % [_run_generation, _task_serial, String(kind)])
	var target_position := points[0] if not points.is_empty() else map_definition.player_spawn
	var required := _required_for(kind, tier)
	if kind == &"relay_route":
		required = float(points.size())
	elif kind == &"escort":
		required = _route_length(target_position, escort_route)
	var deadline := _deadline_for(kind, tier, points, required)
	var enemy_stage := clampi(int(_progression.get("stage", 0)), 0, 10)
	current = {
		"id": target_id, "kind": kind, "target_id": target_id,
		"target_position": target_position, "spawn_position": target_position,
		"progress": 0.0, "required": required,
		"time_remaining": deadline, "time_limit": deadline,
		"difficulty_tier": tier, "difficulty_label": "基础任务" if tier == 0 else "挑战 %d 阶" % tier,
		"difficulty_enemy_stage": enemy_stage,
		"captain_health_multiplier": pow(config.health_growth_per_stage, float(enemy_stage)) * 2.2 * (1.0 + 0.18 * tier),
		"captain_projectile_multiplier": pow(config.projectile_growth_per_stage, float(enemy_stage)) * 1.2,
		"capture_radius": _radius_for(kind), "completed": false, "failed": false,
		"occupied": false, "player_position": map_definition.player_spawn,
		"return_charge_count": 0, "return_boost_seconds": 0.0,
		"status": &"active", "title": _title_for(kind), "instruction": _instruction_for(kind, required),
	}
	if kind == &"relay_route":
		current["route_points"] = points
		current["required"] = float(points.size())
		current["waypoint_hold"] = 0.0
	elif kind == &"escort":
		current.merge({
			"escort_position": target_position, "escort_destination": escort_route[escort_route.size() - 1],
			"destination_position": escort_route[escort_route.size() - 1], "escort_route": escort_route,
			"escort_progress": 0.0, "escort_waypoint_index": 0, "escort_radius": ESCORT_RADIUS,
			"escort_speed": ESCORT_SPEED, "escort_state": &"waiting_player", "escort_moving": false,
			"escort_threat_count": 0,
		})
	_defeated_ids.clear()
	_last_return_release_id = 0
	_progress_emit_clock = 0.0
	objective_started.emit(get_snapshot())


func _next_kind() -> StringName:
	# The first tour teaches every interaction in its familiar order. Later
	# tours shuffle a full bag. The original six openings keep their seed order;
	# the first escort follows that familiar tour, independent of starting kind.
	if _task_serial < OPENING_TASK_COUNT:
		return OBJECTIVE_ROTATION[posmod(rotation_index, OPENING_TASK_COUNT)]
	if _task_serial == OPENING_TASK_COUNT:
		return &"escort"
	if _task_bag.is_empty():
		_task_bag.assign(OBJECTIVE_ROTATION)
		for index in range(_task_bag.size() - 1, 0, -1):
			var other := _rng.randi_range(0, index)
			var temporary := _task_bag[index]
			_task_bag[index] = _task_bag[other]
			_task_bag[other] = temporary
		if _task_bag[0] == StringName(current.get("kind", &"")):
			var temporary := _task_bag[0]
			_task_bag[0] = _task_bag[1]
			_task_bag[1] = temporary
	return _task_bag.pop_front()


func _deadline_for(kind: StringName, tier: int, points: PackedVector2Array, required: float) -> float:
	# Authored short deadlines remain available to isolated contract fixtures.
	if config.objective_time_limit < 10.0:
		return config.objective_time_limit
	var deadline := config.objective_time_limit + 5.0 * tier
	if kind == &"relay_route":
		deadline += maxf(0.0, float(points.size() - RELAY_COUNT)) * 12.0
	var distance := 0.0
	var cursor := _last_player_position
	for point in points:
		var route := PackedVector2Array()
		if _route_provider.is_valid():
			route = _route_provider.call(cursor, point, 24.0)
		if route.is_empty():
			distance += cursor.distance_to(point) * 1.5
		else:
			var waypoint_cursor := cursor
			for waypoint in route:
				distance += waypoint_cursor.distance_to(waypoint)
				waypoint_cursor = waypoint
		cursor = point
	var work_seconds := required if kind == &"capture_point" else (required * RELAY_HOLD_SECONDS if kind == &"relay_route" else 24.0)
	if kind == &"escort":
		work_seconds = required / (ESCORT_SPEED * 0.65)
	# 160 px/s is slower than folded flight (235), leaving combat/detour room.
	return minf(180.0, maxf(deadline, distance / 160.0 + work_seconds + 25.0))


func _complete_current() -> void:
	if not _is_active():
		return
	current["status"] = &"completed"
	current["completed"] = true
	current["progress"] = current["required"]
	completion_count += 1
	_intermission_remaining = config.objective_intermission
	objective_completed.emit(get_snapshot())


func _fail_current() -> void:
	if not _is_active():
		return
	current["status"] = &"failed"
	current["failed"] = true
	failure_count += 1
	_intermission_remaining = maxf(1.5, config.objective_intermission * 0.65)
	objective_failed.emit(get_snapshot())


func _sites_for(kind: StringName) -> PackedVector2Array:
	if map_definition == null:
		return PackedVector2Array()
	match kind:
		&"capture_point", &"capture_storm": return map_definition.capture_points
		&"defeat_captain": return map_definition.captain_spawn_positions
		&"destroy_flag": return map_definition.flag_positions
		&"relay_route", &"escort": return map_definition.rally_positions
	return PackedVector2Array()


func _select_sites(kind: StringName, amount: int) -> PackedVector2Array:
	var sites := _sites_for(kind)
	var chosen := PackedVector2Array()
	if sites.is_empty():
		return chosen
	var start := posmod(int(_site_cursors.get(kind, 0)), sites.size())
	for offset in sites.size():
		var index := posmod(start + offset, sites.size())
		var point := sites[index]
		if not _site_is_available(point, _radius_for(kind)) or chosen.has(point):
			continue
		chosen.append(point)
		_site_cursors[kind] = index + 1
		if chosen.size() >= amount:
			break
	# Every requested stop must be distinct; the caller can shorten a late relay.
	if chosen.size() < amount:
		chosen.clear()
	return chosen


func _site_is_available(point: Vector2, radius: float) -> bool:
	if not map_definition.bounds.grow(-maxf(radius, 44.0)).has_point(point):
		return false
	for wall in map_definition.walls:
		if wall.grow(44.0).has_point(point):
			return false
	return not MapRules.is_point_reserved_in_snapshot(point, _district_access, radius)


func _required_for(kind: StringName, tier: int = 0) -> float:
	match kind:
		&"capture_point": return minf(28.0, config.capture_hold_seconds + 2.0 * tier)
		&"destroy_flag": return minf(540.0, roundf(config.flag_health * (1.0 + 0.30 * tier + 0.06 * tier * tier)))
		&"relay_route": return float(RELAY_COUNT + mini(2, tier / 3))
		&"capture_storm": return float(mini(44, STORM_REQUIRED + 4 * tier))
		&"clear_swarm": return float(mini(42, SWARM_REQUIRED + 4 * tier))
	return 1.0


func _radius_for(kind: StringName) -> float:
	match kind:
		&"capture_point": return CAPTURE_RADIUS
		&"capture_storm": return STORM_RADIUS
		&"relay_route": return RELAY_RADIUS
		&"escort": return ESCORT_RADIUS
	return 44.0


func _progress_text() -> String:
	var progress := float(current["progress"])
	var required := float(current["required"])
	match StringName(current["kind"]):
		&"capture_point": return "%.1f / %.0f 秒 · 返光助燃 +%.0f 秒" % [progress, required, float(current.get("return_boost_seconds", 0.0))]
		&"destroy_flag": return "%.0f / %.0f 伤害" % [progress, required]
		&"relay_route": return "%d / %d 站 · 当前驻留 %.1f / %.1f 秒" % [int(progress), int(required), float(current.get("waypoint_hold", 0.0)), RELAY_HOLD_SECONDS]
		&"capture_storm": return "%d / %d 发" % [int(progress), int(required)]
		&"clear_swarm": return "%d / %d 敌人" % [int(progress), int(required)]
		&"escort":
			var state := StringName(current.get("escort_state", &"waiting_player"))
			return "%d%% · %s" % [roundi(progress / maxf(required, 1.0) * 100.0), "靠近纸舟继续护送" if state == &"waiting_player" else ("敌人逼近 · 航速降低" if state == &"contested" else "护送前进中")]
	return "%d / %d" % [int(progress), int(required)]


func _title_for(kind: StringName) -> String:
	match kind:
		&"capture_point": return "守住潮汐信标"
		&"defeat_captain": return "击破敌方队长"
		&"destroy_flag": return "拆掉火力旗"
		&"relay_route": return "连通信标航线"
		&"capture_storm": return "收集风暴之光"
		&"clear_swarm": return "清剿纸潮"
		&"escort": return "护送归航纸舟"
	return "继续存活"


func _instruction_for(kind: StringName, required: float = 0.0) -> String:
	match kind:
		&"capture_point": return "圈内驻守 %.0f 秒；每累计返出 4 发光助燃 2 秒，最多 6 秒。离圈缓慢回退。" % required
		&"defeat_captain": return "追踪金冠队长并击破；普通敌人不计入此任务。"
		&"destroy_flag": return "靠近红金火力旗，以自动武器、返光或主动技能真实命中。"
		&"relay_route": return "按顺序抵达 %d 个信标，每站停留 1.2 秒；离开当前站会重计驻留。" % int(required)
		&"capture_storm": return "进入青色圈内，按住收纳吸收 %d 发敌弹；圈外收弹不计数。" % int(required)
		&"clear_swarm": return "在任意海域击破 %d 名敌人；火力旗不计入。" % int(required)
		&"escort": return "陪伴纸舟驶向终点；离得太远会停航，清理舟边敌人可恢复航速。"
	return ""


func _build_escort_route(start: Vector2, tier: int) -> PackedVector2Array:
	if not _route_provider.is_valid():
		return PackedVector2Array()
	var sites := _sites_for(&"escort")
	var first := posmod(int(_site_cursors.get(&"escort", 0)), maxi(1, sites.size()))
	for offset in sites.size():
		var destination := sites[posmod(first + offset, sites.size())]
		if destination.distance_to(start) < 900.0 or not _site_is_available(destination, 44.0):
			continue
		var route: PackedVector2Array = _route_provider.call(start, destination, 32.0)
		if route.is_empty() or not route[route.size() - 1].is_equal_approx(destination):
			continue
		var limited := PackedVector2Array()
		var cursor := start
		var budget := 2400.0 + tier * 100.0
		var legal := true
		for point in route:
			var distance := cursor.distance_to(point)
			var next := cursor.move_toward(point, minf(budget, distance))
			var samples := PackedVector2Array()
			_append_segment_samples(samples, cursor, next)
			for sample in samples:
				if not _site_is_available(sample, 44.0):
					legal = false
					break
			if not legal:
				break
			limited.append(next)
			budget -= cursor.distance_to(next)
			cursor = next
			if budget <= 0.01:
				break
		if legal and _route_length(start, limited) >= 900.0:
			return limited
	return PackedVector2Array()


func _append_segment_samples(points: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var count := maxi(1, ceili(from.distance_to(to) / 100.0))
	for index in range(1, count + 1):
		points.append(from.lerp(to, float(index) / count))


func _route_length(start: Vector2, route: PackedVector2Array) -> float:
	var length := 0.0
	for point in route:
		length += start.distance_to(point)
		start = point
	return length
