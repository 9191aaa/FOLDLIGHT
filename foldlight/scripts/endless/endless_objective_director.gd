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
]
const CAPTURE_RADIUS: float = 170.0
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
var _rng := RandomNumberGenerator.new()


func reset(run_config: FoldlightEndlessSurvivalConfig, definition: FoldlightEndlessMapDefinition, seed: int) -> void:
	config = run_config
	map_definition = definition
	# Retain the original three opening tasks for existing seeds.
	rotation_index = posmod(seed, 3)
	_run_generation += 1
	_task_serial = 0
	_rng.seed = seed
	_site_cursors.clear()
	for kind in OBJECTIVE_ROTATION:
		_site_cursors[kind] = _rng.randi_range(0, maxi(0, _sites_for(kind).size() - 1))
	completion_count = 0
	failure_count = 0
	_intermission_remaining = 0.0
	_progress_emit_clock = 0.0
	_start_current_objective()


func set_district_access(snapshot: Dictionary) -> void:
	# Only new tasks consult this mask. A live task is protected by the caller.
	_district_access = snapshot.duplicate(true)


func advance(delta: float, player_position: Vector2) -> void:
	if config == null or map_definition == null or not is_finite(delta) or delta <= 0.0:
		return
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
	var spatial := StringName(current["kind"]) != &"clear_swarm"
	snapshot["target_active"] = _is_active() and spatial
	var protected_points := PackedVector2Array()
	var targets: Array[Dictionary] = []
	if spatial:
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
	var kind := OBJECTIVE_ROTATION[posmod(rotation_index, OBJECTIVE_ROTATION.size())]
	var points := _select_sites(kind, RELAY_COUNT if kind == &"relay_route" else 1)
	if kind != &"clear_swarm" and points.is_empty():
		# All authored sites may be temporarily closed. Keep the task achievable.
		kind = &"clear_swarm"
	_task_serial += 1
	var target_id := StringName("endless_task_%d_%d_%s" % [_run_generation, _task_serial, String(kind)])
	var target_position := points[0] if not points.is_empty() else map_definition.player_spawn
	current = {
		"id": target_id, "kind": kind, "target_id": target_id,
		"target_position": target_position, "spawn_position": target_position,
		"progress": 0.0, "required": _required_for(kind),
		"time_remaining": config.objective_time_limit,
		"capture_radius": _radius_for(kind), "completed": false, "failed": false,
		"status": &"active", "title": _title_for(kind), "instruction": _instruction_for(kind),
	}
	if kind == &"relay_route":
		current["route_points"] = points
		current["required"] = float(points.size())
		current["waypoint_hold"] = 0.0
	_defeated_ids.clear()
	_progress_emit_clock = 0.0
	objective_started.emit(get_snapshot())


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
		&"relay_route": return map_definition.rally_positions
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
	# A relay remains three distinct stops; otherwise use a nonspatial task.
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


func _required_for(kind: StringName) -> float:
	match kind:
		&"capture_point": return config.capture_hold_seconds
		&"destroy_flag": return config.flag_health
		&"relay_route": return float(RELAY_COUNT)
		&"capture_storm": return float(STORM_REQUIRED)
		&"clear_swarm": return float(SWARM_REQUIRED)
	return 1.0


func _radius_for(kind: StringName) -> float:
	match kind:
		&"capture_point": return CAPTURE_RADIUS
		&"capture_storm": return STORM_RADIUS
		&"relay_route": return RELAY_RADIUS
	return 44.0


func _progress_text() -> String:
	var progress := float(current["progress"])
	var required := float(current["required"])
	match StringName(current["kind"]):
		&"capture_point": return "%.1f / %.0f 秒" % [progress, required]
		&"destroy_flag": return "%.0f / %.0f 伤害" % [progress, required]
		&"relay_route": return "%d / %d 站 · 当前驻留 %.1f / %.1f 秒" % [int(progress), int(required), float(current.get("waypoint_hold", 0.0)), RELAY_HOLD_SECONDS]
		&"capture_storm": return "%d / %d 发" % [int(progress), int(required)]
		&"clear_swarm": return "%d / %d 敌人" % [int(progress), int(required)]
	return "%d / %d" % [int(progress), int(required)]


func _title_for(kind: StringName) -> String:
	match kind:
		&"capture_point": return "守住潮汐信标"
		&"defeat_captain": return "击破敌方队长"
		&"destroy_flag": return "拆掉火力旗"
		&"relay_route": return "连通信标航线"
		&"capture_storm": return "收集风暴之光"
		&"clear_swarm": return "清剿纸潮"
	return "继续存活"


func _instruction_for(kind: StringName) -> String:
	match kind:
		&"capture_point": return "进入金色据点持续驻守；离开后进度缓慢回退。"
		&"defeat_captain": return "追踪金冠队长并击破；普通敌人不计入此任务。"
		&"destroy_flag": return "靠近红金火力旗，以自动武器、返光或主动技能真实命中。"
		&"relay_route": return "按顺序抵达三个信标，每站停留 1.2 秒；离开当前站会重计驻留。"
		&"capture_storm": return "进入青色圈内，按住收纳吸收 12 发敌弹；圈外收弹不计数。"
		&"clear_swarm": return "在任意海域击破 10 名敌人；火力旗不计入。"
	return ""
