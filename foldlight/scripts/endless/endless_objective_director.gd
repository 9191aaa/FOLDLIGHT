class_name FoldlightEndlessObjectiveDirector
extends Node

signal objective_started(snapshot: Dictionary)
signal objective_progressed(snapshot: Dictionary)
signal objective_completed(snapshot: Dictionary)
signal objective_failed(snapshot: Dictionary)

const OBJECTIVE_ROTATION: Array[StringName] = [&"capture_point", &"defeat_captain", &"destroy_flag"]

var config: FoldlightEndlessSurvivalConfig
var map_definition: FoldlightEndlessMapDefinition
var current: Dictionary = {}
var rotation_index: int = 0
var completion_count: int = 0
var failure_count: int = 0
var _intermission_remaining: float = 0.0
var _seed_offset: int = 0
var _progress_emit_clock: float = 0.0


func reset(run_config: FoldlightEndlessSurvivalConfig, definition: FoldlightEndlessMapDefinition, seed: int) -> void:
	config = run_config
	map_definition = definition
	rotation_index = posmod(seed, OBJECTIVE_ROTATION.size())
	_seed_offset = posmod(seed / 7, 97)
	completion_count = 0
	failure_count = 0
	_intermission_remaining = 0.0
	_progress_emit_clock = 0.0
	_start_current_objective()


func advance(delta: float, player_position: Vector2) -> void:
	if config == null or map_definition == null or delta <= 0.0:
		return
	if _intermission_remaining > 0.0:
		_intermission_remaining = maxf(0.0, _intermission_remaining - delta)
		if _intermission_remaining <= 0.0:
			rotation_index += 1
			_start_current_objective()
		return
	if current.is_empty() or bool(current.get("completed", false)):
		return
	current["time_remaining"] = maxf(0.0, float(current.get("time_remaining", 0.0)) - delta)
	if StringName(current.get("kind", &"")) == &"capture_point":
		var distance := player_position.distance_to(Vector2(current.get("target_position", Vector2.ZERO)))
		var progress := float(current.get("progress", 0.0))
		if distance <= float(current.get("capture_radius", 170.0)):
			progress += delta
		else:
			progress = maxf(0.0, progress - delta * 0.35)
		current["progress"] = progress
		if progress >= float(current.get("required", config.capture_hold_seconds)):
			_complete_current()
			return
	_progress_emit_clock -= delta
	if _progress_emit_clock <= 0.0:
		_progress_emit_clock = 0.2
		objective_progressed.emit(get_snapshot())
	if float(current.get("time_remaining", 0.0)) <= 0.0:
		_fail_current()


func report_captain_defeated(captain_id: StringName = &"") -> bool:
	if StringName(current.get("kind", &"")) != &"defeat_captain" or _intermission_remaining > 0.0:
		return false
	var target_id := StringName(current.get("target_id", &""))
	if captain_id != &"" and captain_id != target_id:
		return false
	current["progress"] = 1.0
	_complete_current()
	return true


func report_flag_damage(flag_id: StringName, damage: float) -> bool:
	if damage <= 0.0 or StringName(current.get("kind", &"")) != &"destroy_flag" or _intermission_remaining > 0.0:
		return false
	var target_id := StringName(current.get("target_id", &""))
	if flag_id != &"" and flag_id != target_id:
		return false
	current["progress"] = minf(float(current.get("required", config.flag_health)), float(current.get("progress", 0.0)) + damage)
	objective_progressed.emit(get_snapshot())
	if float(current["progress"]) >= float(current.get("required", config.flag_health)):
		_complete_current()
	return true


func report_flag_destroyed(flag_id: StringName = &"") -> bool:
	if StringName(current.get("kind", &"")) != &"destroy_flag":
		return false
	var remaining := float(current.get("required", config.flag_health)) - float(current.get("progress", 0.0))
	return report_flag_damage(flag_id, maxf(remaining, 1.0))


func get_snapshot() -> Dictionary:
	var snapshot := current.duplicate(true)
	snapshot["rotation_index"] = rotation_index
	snapshot["completion_count"] = completion_count
	snapshot["failure_count"] = failure_count
	snapshot["intermission_remaining"] = _intermission_remaining
	if not snapshot.is_empty():
		var required := maxf(0.001, float(snapshot.get("required", 1.0)))
		snapshot["progress_ratio"] = clampf(float(snapshot.get("progress", 0.0)) / required, 0.0, 1.0)
	return snapshot


func _start_current_objective() -> void:
	var kind := OBJECTIVE_ROTATION[posmod(rotation_index, OBJECTIVE_ROTATION.size())]
	var site_index := posmod(rotation_index + _seed_offset, _site_count(kind))
	var target_position := _site_position(kind, site_index)
	var target_id := StringName("%s_%02d" % [String(kind), site_index])
	current = {
		"id": StringName("endless_task_%03d" % rotation_index),
		"kind": kind,
		"target_id": target_id,
		"target_position": target_position,
		"progress": 0.0,
		"required": _required_for(kind),
		"time_remaining": config.objective_time_limit,
		"capture_radius": 170.0,
		"completed": false,
		"title": _title_for(kind),
		"instruction": _instruction_for(kind),
	}
	_progress_emit_clock = 0.0
	objective_started.emit(get_snapshot())


func _complete_current() -> void:
	if current.is_empty() or bool(current.get("completed", false)):
		return
	current["completed"] = true
	current["progress"] = current.get("required", 1.0)
	completion_count += 1
	_intermission_remaining = config.objective_intermission
	objective_completed.emit(get_snapshot())


func _fail_current() -> void:
	failure_count += 1
	current["failed"] = true
	_intermission_remaining = maxf(1.5, config.objective_intermission * 0.65)
	objective_failed.emit(get_snapshot())


func _site_count(kind: StringName) -> int:
	match kind:
		&"capture_point":
			return maxi(1, map_definition.capture_points.size())
		&"defeat_captain":
			return maxi(1, map_definition.captain_spawn_positions.size())
		&"destroy_flag":
			return maxi(1, map_definition.flag_positions.size())
	return 1


func _site_position(kind: StringName, index: int) -> Vector2:
	match kind:
		&"capture_point":
			return map_definition.capture_points[index]
		&"defeat_captain":
			return map_definition.captain_spawn_positions[index]
		&"destroy_flag":
			return map_definition.flag_positions[index]
	return map_definition.player_spawn


func _required_for(kind: StringName) -> float:
	match kind:
		&"capture_point":
			return config.capture_hold_seconds
		&"destroy_flag":
			return config.flag_health
	return 1.0


func _title_for(kind: StringName) -> String:
	match kind:
		&"capture_point":
			return "守住潮汐信标"
		&"defeat_captain":
			return "击破敌方队长"
		&"destroy_flag":
			return "拆掉火力旗"
	return "继续存活"


func _instruction_for(kind: StringName) -> String:
	match kind:
		&"capture_point":
			return "进入金色据点并持续驻守；墙体可以替你挡住外侧弹幕。"
		&"defeat_captain":
			return "找到金冠队长并击破它；普通敌人不必全部清空。"
		&"destroy_flag":
			return "攻击红金火力旗；摧毁后立即获得一次任务进化。"
	return ""
