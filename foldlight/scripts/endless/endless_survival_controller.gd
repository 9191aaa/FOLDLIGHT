class_name FoldlightEndlessSurvivalController
extends Node2D

signal run_started(snapshot: Dictionary)
signal run_stopped(snapshot: Dictionary)
signal enemy_wave_requested(request: Dictionary)
signal enemy_evolution_changed(snapshot: Dictionary)
signal player_evolution_changed(snapshot: Dictionary)
signal objective_started(snapshot: Dictionary)
signal objective_progressed(snapshot: Dictionary)
signal objective_completed(snapshot: Dictionary)
signal objective_failed(snapshot: Dictionary)
signal mission_reward_offered(options: Array[Dictionary], objective_snapshot: Dictionary)
signal mission_reward_claimed(reward: Dictionary)

const THREAT_COSTS := {
	&"drifter": 1,
	&"fan": 2,
	&"ram": 3,
	&"bloomer": 3,
	&"weaver": 4,
	&"leech": 4,
	&"mirror": 5,
	&"rewinder": 6,
}

@export var config: FoldlightEndlessSurvivalConfig
@export var map_definition: FoldlightEndlessMapDefinition
@export var automatic_tick: bool = false
@export var auto_claim_mission_reward: bool = false
@export var hide_when_inactive: bool = true

var active: bool = false
var run_seed: int = 0
var wave_sequence: int = 0
var defeated_total: int = 0
var _spawn_clock: float = 0.0
var _last_player_position := Vector2.ZERO
var _external_player: Node2D
var _pending_mission_rewards: Array[Dictionary] = []
var _captain_spawned_for_objective: StringName = &""

@onready var map_runtime: FoldlightEndlessHandcraftedMap = $HandcraftedMap
@onready var evolution: FoldlightEndlessEvolutionDirector = $EvolutionDirector
@onready var objectives: FoldlightEndlessObjectiveDirector = $ObjectiveDirector


func _ready() -> void:
	if hide_when_inactive:
		hide()
	set_process(false)
	evolution.enemy_evolution_changed.connect(_on_enemy_evolution_changed)
	evolution.player_evolution_changed.connect(_on_player_evolution_changed)
	objectives.objective_started.connect(_on_objective_started)
	objectives.objective_progressed.connect(_on_objective_progressed)
	objectives.objective_completed.connect(_on_objective_completed)
	objectives.objective_failed.connect(_on_objective_failed)


func _process(delta: float) -> void:
	if not active or not automatic_tick:
		return
	if _external_player != null and is_instance_valid(_external_player):
		_last_player_position = _external_player.global_position
	advance_simulation(delta, _last_player_position)


func bind_external_player(player: Node2D) -> void:
	_external_player = player
	if _external_player != null:
		_last_player_position = _external_player.global_position


func enter_mode(seed: int = 1, player: Node2D = null) -> Dictionary:
	bind_external_player(player)
	return start_run(seed)


func exit_mode(reason: StringName = &"mode_switch") -> Dictionary:
	return stop_run(reason)


func start_run(seed: int = 1) -> Dictionary:
	if config == null or map_definition == null:
		push_error("EndlessSurvival: config or map definition is missing")
		return {}
	var errors: Array[String] = []
	errors.append_array(config.validation_errors())
	errors.append_array(map_runtime.configure(map_definition))
	if not errors.is_empty():
		push_error("EndlessSurvival: invalid authored content: %s" % "; ".join(errors))
		return {"errors": errors}
	run_seed = seed
	wave_sequence = 0
	defeated_total = 0
	_spawn_clock = 1.2
	_last_player_position = map_definition.player_spawn
	_pending_mission_rewards.clear()
	_captain_spawned_for_objective = &""
	evolution.reset(config)
	objectives.reset(config, map_definition, seed)
	active = true
	show()
	set_process(automatic_tick)
	var snapshot := get_snapshot()
	run_started.emit(snapshot)
	return snapshot


func stop_run(reason: StringName = &"stopped") -> Dictionary:
	if not active:
		return get_snapshot()
	active = false
	set_process(false)
	var snapshot := get_snapshot()
	snapshot["stop_reason"] = reason
	_external_player = null
	_pending_mission_rewards.clear()
	if hide_when_inactive:
		hide()
	run_stopped.emit(snapshot)
	return snapshot


func advance_simulation(delta: float, player_position: Vector2) -> void:
	if not active or delta <= 0.0:
		return
	_last_player_position = player_position
	evolution.advance_survival(delta)
	objectives.advance(delta, player_position)
	map_runtime.set_active_objective(objectives.get_snapshot())
	_spawn_clock -= delta
	if _spawn_clock <= 0.0:
		_emit_next_wave()
		_spawn_clock += float(evolution.get_enemy_snapshot().get("spawn_interval", config.base_spawn_interval))


func report_projectiles_absorbed(projectile_count: int) -> void:
	if not active or projectile_count <= 0:
		return
	evolution.record_absorbed(projectile_count)


func report_enemy_defeated(enemy_snapshot: Dictionary) -> void:
	if not active:
		return
	defeated_total += 1
	if bool(enemy_snapshot.get("is_captain", false)):
		report_captain_defeated(StringName(enemy_snapshot.get("captain_id", &"")))


func report_captain_defeated(captain_id: StringName = &"") -> bool:
	if not active:
		return false
	return objectives.report_captain_defeated(captain_id)


func report_flag_damage(flag_id: StringName, damage: float) -> bool:
	if not active:
		return false
	return objectives.report_flag_damage(flag_id, damage)


func report_flag_destroyed(flag_id: StringName = &"") -> bool:
	if not active:
		return false
	return objectives.report_flag_destroyed(flag_id)


func get_pending_mission_rewards() -> Array[Dictionary]:
	return _pending_mission_rewards.duplicate(true)


func claim_mission_reward(reward_id: StringName) -> Dictionary:
	var legal := false
	for option in _pending_mission_rewards:
		if StringName(option.get("id", &"")) == reward_id:
			legal = true
			break
	if not legal:
		return {}
	var applied := evolution.apply_mission_reward(reward_id)
	if applied.is_empty():
		return {}
	_pending_mission_rewards.clear()
	mission_reward_claimed.emit(applied)
	return applied


func force_next_wave() -> Dictionary:
	if not active:
		return {}
	return _emit_next_wave()


func get_snapshot() -> Dictionary:
	return {
		"mode_id": config.mode_id if config != null else &"classic_2_0_endless",
		"rules_version": config.rules_version if config != null else &"endless_1_0",
		"active": active,
		"seed": run_seed,
		"wave_sequence": wave_sequence,
		"defeated_total": defeated_total,
		"map": map_runtime.get_map_contract() if is_instance_valid(map_runtime) else {},
		"evolution": evolution.get_snapshot() if is_instance_valid(evolution) else {},
		"objective": objectives.get_snapshot() if is_instance_valid(objectives) else {},
		"pending_mission_rewards": _pending_mission_rewards.duplicate(true),
	}


func get_integration_contract() -> Dictionary:
	return {
		"version": &"endless_adapter_1_0",
		"controller_scene": "res://scenes/endless/endless_survival_controller.tscn",
		"playable_slice_scene": "res://scenes/endless/endless_survival_slice.tscn",
		"classic_enemy_ids": config.classic_enemy_ids.duplicate() if config != null else [],
		"input_reports": [
			&"enter_mode",
			&"exit_mode",
			&"report_projectiles_absorbed",
			&"report_enemy_defeated",
			&"report_captain_defeated",
			&"report_flag_damage",
			&"report_flag_destroyed",
		],
		"output_signals": [
			&"enemy_wave_requested",
			&"enemy_evolution_changed",
			&"player_evolution_changed",
			&"objective_started",
			&"mission_reward_offered",
			&"mission_reward_claimed",
		],
		"copies_classic_enemy_logic": false,
		"terrain_runtime_randomized": false,
	}


func _emit_next_wave() -> Dictionary:
	wave_sequence += 1
	var enemy_state := evolution.get_enemy_snapshot()
	var budget := int(enemy_state.get("wave_budget", config.base_wave_budget))
	var entries: Array[Dictionary] = []
	var objective := objectives.get_snapshot()
	var objective_kind := StringName(objective.get("kind", &""))
	var objective_id := StringName(objective.get("target_id", &""))
	if objective_kind == &"defeat_captain" and objective_id != &"" and objective_id != _captain_spawned_for_objective:
		entries.append(_make_captain_entry(objective, enemy_state))
		_captain_spawned_for_objective = objective_id
		budget = maxi(1, budget - 5)
	var unlocked_count := mini(config.classic_enemy_ids.size(), 2 + int(enemy_state.get("stage", 0)))
	var guard := 0
	while budget > 0 and guard < 64:
		guard += 1
		var enemy_index := posmod(run_seed + wave_sequence * 5 + guard * 3, unlocked_count)
		var enemy_id := config.classic_enemy_ids[enemy_index]
		var cost := int(THREAT_COSTS.get(enemy_id, 1))
		if cost > budget and not entries.is_empty():
			enemy_id = &"drifter"
			cost = 1
		var role := &"shooter" if enemy_id in config.shooter_enemy_ids else &"melee"
		entries.append({
			"enemy_id": enemy_id,
			"spawn_role": role,
			"position": map_runtime.select_spawn_point(role, wave_sequence * 17 + guard, _last_player_position),
			"health_multiplier": enemy_state.get("health_multiplier", 1.0),
			"projectile_multiplier": enemy_state.get("projectile_multiplier", 1.0),
			"endless_stage": enemy_state.get("stage", 0),
			"is_captain": false,
		})
		budget -= cost
	var request := {
		"sequence": wave_sequence,
		"entries": entries,
		"enemy_evolution": enemy_state,
		"objective": objective,
		"authored_spawn_sites": true,
		"shooter_spawn_policy": &"central_cover_lane",
	}
	enemy_wave_requested.emit(request)
	return request


func _make_captain_entry(objective: Dictionary, enemy_state: Dictionary) -> Dictionary:
	var stage := int(enemy_state.get("stage", 0))
	var captain_enemy := config.classic_enemy_ids[mini(config.classic_enemy_ids.size() - 1, 3 + stage)]
	return {
		"enemy_id": captain_enemy,
		"spawn_role": &"captain",
		"position": objective.get("target_position", map_definition.player_spawn),
		"health_multiplier": float(enemy_state.get("health_multiplier", 1.0)) * 2.2,
		"projectile_multiplier": float(enemy_state.get("projectile_multiplier", 1.0)) * 1.2,
		"endless_stage": stage,
		"is_captain": true,
		"captain_id": objective.get("target_id", &""),
	}


func _on_enemy_evolution_changed(snapshot: Dictionary) -> void:
	enemy_evolution_changed.emit(snapshot)


func _on_player_evolution_changed(snapshot: Dictionary) -> void:
	player_evolution_changed.emit(snapshot)


func _on_objective_started(snapshot: Dictionary) -> void:
	_captain_spawned_for_objective = &""
	map_runtime.set_active_objective(snapshot)
	objective_started.emit(snapshot)


func _on_objective_progressed(snapshot: Dictionary) -> void:
	map_runtime.set_active_objective(snapshot)
	objective_progressed.emit(snapshot)


func _on_objective_completed(snapshot: Dictionary) -> void:
	map_runtime.set_active_objective(snapshot)
	_pending_mission_rewards = evolution.get_mission_reward_options(int(snapshot.get("completion_count", 1)) - 1)
	objective_completed.emit(snapshot)
	mission_reward_offered.emit(_pending_mission_rewards.duplicate(true), snapshot)
	if auto_claim_mission_reward and not _pending_mission_rewards.is_empty():
		claim_mission_reward(StringName(_pending_mission_rewards[0].get("id", &"")))


func _on_objective_failed(snapshot: Dictionary) -> void:
	map_runtime.set_active_objective(snapshot)
	objective_failed.emit(snapshot)
