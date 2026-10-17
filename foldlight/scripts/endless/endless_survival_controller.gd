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
signal reward_available(snapshot: Dictionary)
signal experience_changed(snapshot: Dictionary)

const THREAT_COSTS := {
	&"drifter": 1,
	&"fan": 2,
	&"ram": 3,
	&"bloomer": 3,
	&"weaver": 4,
	&"leech": 4,
	&"mirror": 5,
	&"rewinder": 6,
	&"shutter_seraph": 6,
	&"cinder_mine": 3,
}

const BARRAGE_ELITE_START_SECONDS := 105.0
const BARRAGE_ELITE_WAVE_INTERVAL := 4
const BOMBER_START_SECONDS := 150.0
const BOMBER_WAVE_INTERVAL := 3
const MAP_PATHS := [
	"res://resources/endless/maps/folded_delta.tres",
	"res://resources/endless/maps/inverted_canals.tres",
	"res://resources/endless/maps/solar_archipelago.tres",
]

@export var config: FoldlightEndlessSurvivalConfig
@export var map_definition: FoldlightEndlessMapDefinition
@export var automatic_tick: bool = false
@export var auto_claim_mission_reward: bool = false
@export var hide_when_inactive: bool = true

var active: bool = false
var run_seed: int = 0
var wave_sequence: int = 0
var defeated_total: int = 0
var weapon_levels: Dictionary = {"crease_lantern": 1}
var active_item_ids: Array[StringName] = [&"paper_burst"]
var active_item_id: StringName = &"paper_burst"
var active_item_cooldowns: Dictionary = {"paper_burst": 0.0}
var _spawn_clock: float = 0.0
var _last_player_position := Vector2.ZERO
var _external_player: Node2D
var _pending_mission_rewards: Array[Dictionary] = []
var _reward_queue: Array[Dictionary] = []
var _reward_serial: int = 0
var _run_generation: int = 0
var _last_defeat_serial: int = 0
var _reward_transaction: bool = false
var _claiming_pending_reward: bool = false
var _population := {"alive_count": 0, "pending_count": 0, "threat_total": 0, "pending_threat": 0}
var _last_reward_completion: int = 0
var _last_boss_reward_wave: int = 0
var _captain_spawned_for_objective: StringName = &""
var zones := FoldlightEndlessZoneDirector.new()

@onready var map_runtime: FoldlightEndlessHandcraftedMap = $HandcraftedMap
@onready var evolution: FoldlightEndlessEvolutionDirector = $EvolutionDirector
@onready var objectives: FoldlightEndlessObjectiveDirector = $ObjectiveDirector


func _ready() -> void:
	if hide_when_inactive:
		hide()
	set_process(false)
	evolution.enemy_evolution_changed.connect(_on_enemy_evolution_changed)
	evolution.player_evolution_changed.connect(_on_player_evolution_changed)
	evolution.experience_changed.connect(func(snapshot: Dictionary) -> void: experience_changed.emit(snapshot))
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


func select_map_for_seed(seed: int) -> void:
	map_definition = load(MAP_PATHS[posmod(seed, MAP_PATHS.size())]) as FoldlightEndlessMapDefinition


func confirm_captain_spawned(target_id: StringName) -> void:
	if target_id == StringName(objectives.get_snapshot().get("target_id", &"")):
		_captain_spawned_for_objective = target_id


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
	_run_generation += 1
	wave_sequence = 0
	defeated_total = 0
	weapon_levels = {"crease_lantern": 1}
	active_item_ids = [&"paper_burst"]
	active_item_id = &"paper_burst"
	active_item_cooldowns = {"paper_burst": 0.0}
	_spawn_clock = 1.2
	_last_player_position = map_definition.player_spawn
	_pending_mission_rewards.clear()
	_reward_queue.clear()
	_reward_serial = 0
	_last_defeat_serial = 0
	_reward_transaction = false
	_claiming_pending_reward = false
	_population = {"alive_count": 0, "pending_count": 0, "threat_total": 0, "pending_threat": 0}
	_last_reward_completion = 0
	_last_boss_reward_wave = 0
	_captain_spawned_for_objective = &""
	evolution.reset(config)
	zones.reset(map_definition, seed)
	objectives.set_district_access(zones.get_snapshot())
	objectives.bind_route_provider(map_runtime.find_cover_route)
	objectives.reset(config, map_definition, seed, evolution.get_enemy_snapshot())
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
	_reward_queue.clear()
	if hide_when_inactive:
		hide()
	run_stopped.emit(snapshot)
	return snapshot


func advance_simulation(delta: float, player_position: Vector2) -> void:
	if not active or not is_finite(delta) or delta <= 0.0 or not player_position.is_finite() or not _pending_mission_rewards.is_empty():
		return
	advance_presentation(delta)
	_last_player_position = player_position
	evolution.advance_survival(delta)
	var protected_points: PackedVector2Array = objectives.get_snapshot().get("protected_points", PackedVector2Array())
	zones.advance_to(evolution.survival_seconds, protected_points, player_position)
	var zone_snapshot := zones.get_snapshot()
	objectives.set_district_access(zone_snapshot)
	objectives.set_progression_context(evolution.get_enemy_snapshot(), player_position)
	map_runtime.set_zone_snapshot(zone_snapshot)
	objectives.advance(delta, player_position)
	map_runtime.set_active_objective(objectives.get_snapshot())
	if not active or not _pending_mission_rewards.is_empty():
		return
	_spawn_clock -= delta
	if _spawn_clock <= 0.0:
		_emit_next_wave()
		# A delayed frame cannot create a backlog of missed waves.
		_spawn_clock = float(evolution.get_enemy_snapshot().get("spawn_interval", config.base_spawn_interval))


func advance_presentation(delta: float) -> void:
	if active and is_finite(delta) and delta > 0.0:
		map_runtime.advance_presentation(delta)


func report_returned_light(count: int, objective_id: StringName, release_id: int) -> bool:
	if not active or not _pending_mission_rewards.is_empty():
		return false
	var position := _external_player.global_position if is_instance_valid(_external_player) else _last_player_position
	return objectives.report_returned_light(count, position, objective_id, release_id)


func report_projectiles_absorbed(projectile_count: int) -> void:
	if not active or projectile_count <= 0:
		return
	evolution.record_absorbed(projectile_count)
	objectives.report_projectiles_absorbed(projectile_count, _external_player.global_position if is_instance_valid(_external_player) else _last_player_position)


func report_enemy_defeated(enemy_snapshot: Dictionary) -> void:
	if not active or bool(enemy_snapshot.get("is_objective_target", false)):
		return
	var serial := int(enemy_snapshot.get("defeat_serial", 0))
	if serial > 0:
		if serial <= _last_defeat_serial:
			return
		_last_defeat_serial = serial
	if not bool(enemy_snapshot.get("grants_kill_credit", true)) or StringName(enemy_snapshot.get("defeat_reason", &"player")) != &"player":
		return
	defeated_total += 1
	var is_captain := bool(enemy_snapshot.get("is_captain", false))
	var identity := StringName(enemy_snapshot.get("captain_id" if is_captain else "actor_id", &""))
	# A captain kill may finish a task AND reach a level. Publish only after
	# both entitlements exist, so synchronous UI handlers cannot drop either.
	_reward_transaction = true
	objectives.report_enemy_defeated(identity, is_captain)
	if serial > 0 and StringName(enemy_snapshot.get("defeat_reason", &"")) == &"player":
		var amount := _experience_for_enemy(enemy_snapshot)
		for level in evolution.record_kill_experience(amount):
			_enqueue_reward({
				"source": &"kill_level", "title": "击破成长 · Lv.%d" % level,
				"level": level, "objective": {},
				"heal_on_claim": 1 if level % config.recovery_level_interval == 0 else 0,
			})
	_reward_transaction = false
	_publish_reward_head()


func _experience_for_enemy(snapshot: Dictionary) -> int:
	if bool(snapshot.get("is_captain", false)) or bool(snapshot.get("is_elite", false)):
		return 8
	var enemy_id := StringName(snapshot.get("enemy_id", &""))
	if enemy_id == &"shutter_seraph":
		return 8
	var definition := FoldlightRogueContentCatalog.enemy_by_id(enemy_id)
	if definition == null:
		return 0
	return 3 if int(THREAT_COSTS.get(enemy_id, definition.threat_cost)) >= 3 else 2


func report_population(snapshot: Dictionary) -> void:
	for key: String in _population:
		_population[key] = maxi(0, int(snapshot.get(key, 0)))


func report_escort_pressure(enemy_count: int) -> void:
	if active:
		objectives.report_escort_pressure(enemy_count)


func queue_boss_reward(boss_id: StringName, title: String, wave_index: int) -> bool:
	# Runtime reports a cleared whole wave once. Boss rewards have their own
	# sequence and never spend a task completion or combat experience level.
	if not active or boss_id.is_empty() or wave_index <= _last_boss_reward_wave:
		return false
	_last_boss_reward_wave = wave_index
	_enqueue_reward({
		"source": &"boss", "title": title if not title.is_empty() else "深潮首领已击破",
		"boss_id": boss_id, "wave_index": wave_index, "objective": {}, "heal_on_claim": 1,
	})
	_publish_reward_head()
	return true


func get_population_snapshot() -> Dictionary:
	var snapshot := _population.duplicate()
	var pressure := evolution.get_enemy_snapshot()
	snapshot["population_limit"] = pressure.get("population_limit", config.base_population_limit)
	snapshot["threat_limit"] = pressure.get("threat_limit", config.base_threat_limit)
	return snapshot


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
	_prepare_reward_head()
	return _pending_mission_rewards.duplicate(true)


func claim_mission_reward(reward_id: StringName) -> Dictionary:
	var head := peek_pending_reward()
	return claim_pending_reward(StringName(head.get("reward_token", &"")), reward_id)


func peek_pending_reward() -> Dictionary:
	_prepare_reward_head()
	return {} if _reward_queue.is_empty() else _reward_queue[0].duplicate(true)


func claim_pending_reward(reward_token: StringName, reward_id: StringName) -> Dictionary:
	if not active or _claiming_pending_reward or _reward_queue.is_empty():
		return {}
	_prepare_reward_head()
	var head := _reward_queue[0]
	if reward_token.is_empty() or reward_token != StringName(head.get("reward_token", &"")):
		return {}
	var legal := false
	var selected: Dictionary = {}
	for option in _pending_mission_rewards:
		if StringName(option.get("id", &"")) == reward_id:
			legal = true
			selected = option
			break
	if not legal:
		return {}
	_claiming_pending_reward = true
	var applied: Dictionary
	if StringName(selected.get("choice_kind", &"")) == &"weapon":
		var level := int(weapon_levels.get(String(reward_id), 0))
		if FoldlightRogueContentCatalog.weapon_by_id(reward_id) == null or level >= FoldlightWeaponProgression.MAX_LEVEL:
			_claiming_pending_reward = false
			return {}
		weapon_levels[String(reward_id)] = level + 1
		applied = selected.duplicate(true)
		applied["level"] = level + 1
	elif StringName(selected.get("choice_kind", &"")) == &"active":
		if not acquire_active_item(reward_id):
			_claiming_pending_reward = false
			return {}
		applied = selected.duplicate(true)
	else:
		applied = evolution.apply_experience_reward(reward_id) if StringName(head["source"]) == &"kill_level" else evolution.apply_mission_reward(reward_id)
	if applied.is_empty():
		_claiming_pending_reward = false
		return {}
	applied["reward_token"] = reward_token
	applied["reward_source"] = head["source"]
	applied["heal_on_claim"] = int(head.get("heal_on_claim", 0))
	applied["experience_level"] = int(head.get("level", 0))
	_reward_queue.pop_front()
	_pending_mission_rewards.clear()
	mission_reward_claimed.emit(applied)
	_claiming_pending_reward = false
	_publish_reward_head()
	return applied


func _enqueue_reward(reward: Dictionary) -> void:
	_reward_serial += 1
	reward["reward_token"] = StringName("%d:%d:%d:%s" % [run_seed, _run_generation, _reward_serial, str(reward.get("source", "mission"))])
	reward["options"] = []
	reward["notified"] = false
	_reward_queue.append(reward)
	_prepare_reward_head()


func _prepare_reward_head() -> void:
	if _reward_queue.is_empty():
		_pending_mission_rewards.clear()
		return
	var head := _reward_queue[0]
	var options: Array = head.get("options", [])
	if options.is_empty():
		match StringName(head["source"]):
			&"kill_level": options = evolution.get_experience_reward_options(int(head["level"]))
			&"boss": options = _draft_mission_rewards(int(head["wave_index"]) * 2 - 1)
			_: options = _draft_mission_rewards(int(head["completion_count"]))
		head["options"] = options
	_pending_mission_rewards.assign(options)


func _publish_reward_head() -> void:
	if _reward_transaction or _claiming_pending_reward or not active:
		return
	_prepare_reward_head()
	if _reward_queue.is_empty() or bool(_reward_queue[0].get("notified", false)):
		return
	_reward_queue[0]["notified"] = true
	var snapshot := peek_pending_reward()
	reward_available.emit(snapshot)
	if not active or _reward_queue.is_empty() or StringName(_reward_queue[0]["reward_token"]) != StringName(snapshot["reward_token"]):
		return
	var context: Dictionary = (snapshot.get("objective", {}) as Dictionary).duplicate(true)
	for key: String in ["reward_token", "source", "title", "heal_on_claim", "level"]:
		if snapshot.has(key):
			context[key] = snapshot[key]
	mission_reward_offered.emit(_pending_mission_rewards.duplicate(true), context)
	if auto_claim_mission_reward and not _pending_mission_rewards.is_empty():
		claim_pending_reward(StringName(snapshot["reward_token"]), StringName(_pending_mission_rewards[0].get("id", &"")))


func force_next_wave() -> Dictionary:
	if not active:
		return {}
	return _emit_next_wave()


func get_snapshot() -> Dictionary:
	return {
		"mode_id": config.mode_id if config != null else &"classic_2_0_endless",
		"rules_version": config.rules_version if config != null else &"endless_2_0",
		"active": active,
		"seed": run_seed,
		"wave_sequence": wave_sequence,
		"defeated_total": defeated_total,
		"weapon_levels": weapon_levels.duplicate(true),
		"active_item_ids": active_item_ids.duplicate(),
		"active_item_id": active_item_id,
		"active_item_cooldowns": active_item_cooldowns.duplicate(true),
		"map": map_runtime.get_map_contract() if is_instance_valid(map_runtime) else {},
		"evolution": evolution.get_snapshot() if is_instance_valid(evolution) else {},
		"experience": evolution.get_experience_snapshot() if is_instance_valid(evolution) else {},
		"population": get_population_snapshot() if is_instance_valid(evolution) and config != null else {},
		"objective": objectives.get_snapshot() if is_instance_valid(objectives) else {},
		"zones": zones.get_snapshot(),
		"pending_mission_rewards": _pending_mission_rewards.duplicate(true),
		"pending_reward_count": _reward_queue.size(),
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
			&"report_population",
			&"report_escort_pressure",
			&"queue_boss_reward",
			&"peek_pending_reward",
			&"claim_pending_reward",
			&"report_captain_defeated",
			&"report_flag_damage",
			&"report_flag_destroyed",
		],
		"output_signals": [
			&"enemy_wave_requested",
			&"enemy_evolution_changed",
			&"player_evolution_changed",
			&"experience_changed",
			&"reward_available",
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
	var available_count := maxi(0, int(enemy_state["population_limit"]) - int(_population["alive_count"]) - int(_population["pending_count"]))
	var available_threat := maxi(0, int(enemy_state["threat_limit"]) - int(_population["threat_total"]) - int(_population["pending_threat"]))
	var requested_budget := int(enemy_state.get("wave_budget", config.base_wave_budget))
	var is_breathing_wave := wave_sequence % 4 == 2
	if is_breathing_wave:
		requested_budget = maxi(1, floori(requested_budget * config.breathing_wave_ratio))
	var budget := mini(requested_budget, available_threat)
	var entries: Array[Dictionary] = []
	var objective := objectives.get_snapshot()
	var objective_kind := StringName(objective.get("kind", &""))
	var objective_id := StringName(objective.get("target_id", &""))
	if available_count > 0 and available_threat >= 6 and objective_kind == &"defeat_captain" and bool(objective.get("target_active", true)) and objective_id != &"" and objective_id != _captain_spawned_for_objective:
		budget = mini(available_threat, maxi(6, budget))
		var captain := _make_captain_entry(objective, enemy_state)
		captain["threat_cost"] = 6
		entries.append(captain)
		budget -= 6
		available_count -= 1
	if available_count > 0 and evolution.survival_seconds >= BARRAGE_ELITE_START_SECONDS and wave_sequence % BARRAGE_ELITE_WAVE_INTERVAL == 0 and budget >= 6:
		var elite := _make_regular_entry(&"shutter_seraph", &"shooter", wave_sequence * 17, enemy_state)
		if not elite.is_empty():
			elite["is_elite"] = true
			entries.append(elite)
			budget -= 6
			available_count -= 1
	if available_count > 0 and evolution.survival_seconds >= BOMBER_START_SECONDS and wave_sequence % BOMBER_WAVE_INTERVAL == 0 and budget >= 3:
		var bomber := _make_regular_entry(&"cinder_mine", &"melee", wave_sequence * 17 + 67, enemy_state)
		if not bomber.is_empty():
			bomber["projectile_multiplier"] = 1.0
			entries.append(bomber)
			budget -= 3
			available_count -= 1
	var unlocked_count := mini(config.classic_enemy_ids.size(), 2 + int(enemy_state.get("stage", 0)))
	var guard := 0
	while budget > 0 and available_count > 0 and guard < 48:
		guard += 1
		var enemy_index := posmod(run_seed + wave_sequence * 5 + guard * 3, unlocked_count)
		var enemy_id := config.classic_enemy_ids[enemy_index]
		var cost := int(THREAT_COSTS.get(enemy_id, 1))
		if cost > budget:
			enemy_id = &"drifter"
			cost = 1
		var role := &"shooter" if enemy_id in config.shooter_enemy_ids else &"melee"
		var entry := _make_regular_entry(enemy_id, role, wave_sequence * 17 + guard, enemy_state)
		if entry.is_empty():
			continue
		entries.append(entry)
		budget -= cost
		available_count -= 1
	# Reservations are published BEFORE the signal: deferred instantiation and
	# a second wave request in the same frame share the same hard limits.
	var reserved_threat := 0
	for entry: Dictionary in entries:
		reserved_threat += int(entry.get("threat_cost", 1))
	_population["pending_count"] = int(_population["pending_count"]) + entries.size()
	_population["pending_threat"] = int(_population["pending_threat"]) + reserved_threat
	var request := {
		"sequence": wave_sequence,
		"entries": entries,
		"enemy_evolution": enemy_state,
		"objective": objective,
		"authored_spawn_sites": false,
		"shooter_spawn_policy": &"safe_local_reinforcement",
		"breathing_wave": is_breathing_wave,
		"population": get_population_snapshot(),
	}
	enemy_wave_requested.emit(request)
	return request


func _make_regular_entry(enemy_id: StringName, role: StringName, sequence: int, enemy_state: Dictionary) -> Dictionary:
	var spawn_position := _safe_spawn_position(role, sequence)
	if not spawn_position.is_finite():
		return {}
	return {
		"enemy_id": enemy_id, "spawn_role": role, "position": spawn_position,
		"threat_cost": int(THREAT_COSTS.get(enemy_id, 1)),
		"health_multiplier": enemy_state.get("health_multiplier", 1.0),
		"projectile_multiplier": enemy_state.get("projectile_multiplier", 1.0),
		"endless_stage": enemy_state.get("stage", 0), "is_captain": false,
	}


func _safe_spawn_position(role: StringName, sequence: int) -> Vector2:
	var positions := map_definition.shooter_spawn_positions if role == &"shooter" else map_definition.melee_spawn_positions
	var safe_distance_squared := config.spawn_safe_distance * config.spawn_safe_distance
	var local_radius_squared := config.spawn_local_radius * config.spawn_local_radius
	if sequence % 3 == 0:
		for offset in positions.size():
			var authored := positions[posmod(sequence * 3 + offset, positions.size())]
			var distance_squared := authored.distance_squared_to(_last_player_position)
			if distance_squared >= safe_distance_squared and distance_squared <= local_radius_squared and _spawn_site_is_open(authored):
				return authored
	# Fixed angles/radii around the actual player keep a larger map populated
	# near combat. This changes reinforcement placement, never authored terrain.
	for ring in 3:
		var radius := lerpf(config.spawn_safe_distance + 100.0, config.spawn_local_radius - 60.0, float(posmod(sequence + ring, 3)) / 2.0)
		for offset in 32:
			var angle := TAU * float(posmod(run_seed + sequence * 7 + offset, 32)) / 32.0
			var candidate := _last_player_position + Vector2.from_angle(angle) * radius
			if _spawn_site_is_open(candidate):
				return candidate
	return Vector2(INF, INF)


func _spawn_site_is_open(candidate: Vector2) -> bool:
	return map_definition.bounds.grow(-44.0).has_point(candidate) and not map_runtime.is_point_blocked(candidate, 40.0) and not zones.is_point_reserved(candidate, 40.0)


func _make_captain_entry(objective: Dictionary, enemy_state: Dictionary) -> Dictionary:
	var stage := int(objective.get("difficulty_enemy_stage", enemy_state.get("stage", 0)))
	var captain_enemy := config.classic_enemy_ids[mini(config.classic_enemy_ids.size() - 1, 3 + stage)]
	return {
		"enemy_id": captain_enemy,
		"spawn_role": &"captain",
		"position": objective.get("target_position", map_definition.player_spawn),
		"health_multiplier": float(objective.get("captain_health_multiplier", float(enemy_state.get("health_multiplier", 1.0)) * 2.2)),
		"projectile_multiplier": float(objective.get("captain_projectile_multiplier", float(enemy_state.get("projectile_multiplier", 1.0)) * 1.2)),
		"endless_stage": stage,
		"is_captain": true,
		"captain_id": objective.get("target_id", &""),
		"objective_id": objective.get("id", &""),
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
	var completion := maxi(1, int(snapshot.get("completion_count", 1)))
	if not active or completion <= _last_reward_completion:
		return
	_last_reward_completion = completion
	map_runtime.set_active_objective(snapshot)
	_enqueue_reward({
		"source": &"mission", "title": str(snapshot.get("title", "系统任务")),
		"completion_count": completion, "objective": snapshot.duplicate(true),
		"heal_on_claim": config.mission_recovery,
	})
	objective_completed.emit(snapshot)
	_publish_reward_head()


func _draft_mission_rewards(completion: int) -> Array[Dictionary]:
	# Equal starting pool for solo and friends: no account unlocks enter races.
	# Odd completions build the weapon array, even completions retain the three
	# Fold/firepower/sustain lanes. One task still grants exactly one choice.
	var options: Array[Dictionary] = []
	if completion % 2 == 1:
		var ids: Array[StringName] = []
		for definition in FoldlightRogueContentCatalog.WEAPONS:
			ids.append(definition.content_id)
		var weapons := FoldlightWeaponProgression.draft_choices(run_seed, completion, weapon_levels, ids, 3)
		if not weapons.is_empty():
			for choice in weapons:
				choice["id"] = choice.content_id
				choice["lane_id"] = &"power"
				choice["lane_title"] = "武器阵列"
			options = weapons
	if options.is_empty():
		options = evolution.get_mission_reward_options(maxi(0, (completion - 2) / 2))
	# A skill supply occupies one optional card at tasks 3, 7, 11, ...;
	# weapons remain available and collecting the full set restores that card.
	if completion % 4 == 3:
		var candidates: Array[StringName] = []
		for item in FoldlightRogueContentCatalog.ACTIVE_ITEMS:
			if not active_item_ids.has(item.content_id):
				candidates.append(item.content_id)
		if not candidates.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = run_seed ^ completion * 2654435761
			var choice := FoldlightActiveItemSlot.make_choice(candidates[rng.randi_range(0, candidates.size() - 1)])
			choice["lane_id"] = &"active"
			choice["lane_title"] = "主动技能"
			if options.size() >= 3:
				options[2] = choice
			else:
				options.append(choice)
	return options


func acquire_active_item(item_id: StringName) -> bool:
	if FoldlightRogueContentCatalog.active_item_by_id(item_id) == null or active_item_ids.has(item_id):
		return false
	active_item_ids.append(item_id)
	active_item_cooldowns[String(item_id)] = 0.0
	active_item_id = item_id
	return true


func set_active_collection(source: Dictionary) -> void:
	var clean := FoldlightActiveItemSlot.sanitize_collection(source)
	active_item_ids.clear()
	for item_id: String in clean["active_item_ids"]:
		active_item_ids.append(StringName(item_id))
	active_item_id = StringName(clean["active_item_id"])
	active_item_cooldowns = (clean["active_item_cooldowns"] as Dictionary).duplicate(true)


func _on_objective_failed(snapshot: Dictionary) -> void:
	map_runtime.set_active_objective(snapshot)
	objective_failed.emit(snapshot)
