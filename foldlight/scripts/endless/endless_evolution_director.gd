class_name FoldlightEndlessEvolutionDirector
extends Node

signal enemy_evolution_changed(snapshot: Dictionary)
signal player_evolution_changed(snapshot: Dictionary)
signal mission_evolution_changed(snapshot: Dictionary)

const ABSORB_PERKS: Array[Dictionary] = [
	{"id": &"wider_fold", "title": "折域延展", "capture_capacity": 2, "fold_radius_multiplier": 0.08},
	{"id": &"bright_return", "title": "返航增压", "return_damage_multiplier": 0.18, "return_speed_multiplier": 0.08},
	{"id": &"steady_breath", "title": "长息", "fold_move_speed_multiplier": 0.12, "damage_grace_add": 0.07},
	{"id": &"chain_light", "title": "连光", "return_chain": 1, "return_damage_multiplier": 0.12},
	{"id": &"deep_pocket", "title": "深层收纳", "capture_capacity": 3, "fold_radius_multiplier": 0.06},
	{"id": &"perfect_orbit", "title": "完美轨道", "return_speed_multiplier": 0.16, "return_chain": 1},
]

const MISSION_REWARD_LANES: Array[Dictionary] = [
	{
		"id": &"power",
		"title": "火力",
		"reward_ids": [&"surge_return", &"crosswind"],
	},
	{
		"id": &"fold_mobility",
		"title": "折域机动",
		"reward_ids": [&"wide_fold", &"kinetic_paper"],
	},
	{
		"id": &"sustain",
		"title": "续航",
		"reward_ids": [&"steady_lantern", &"clear_current"],
	},
]

const MISSION_REWARDS: Array[Dictionary] = [
	{
		"id": &"surge_return",
		"title": "潮返",
		"description": "返航伤害 +15%，返航速度 +8%。",
		"modifiers": {"return_damage_multiplier": 0.15, "return_speed_multiplier": 0.08},
	},
	{
		"id": &"wide_fold",
		"title": "开阔折域",
		"description": "折域半径 +7%，基础收纳上限 +1。",
		"modifiers": {"fold_radius_multiplier": 0.07, "capture_capacity": 1},
	},
	{
		"id": &"kinetic_paper",
		"title": "动纸",
		"description": "移动速度 +6%，冲刺冷却 -5%。",
		"modifiers": {"move_speed_multiplier": 0.06, "dash_cooldown_multiplier": -0.05},
	},
	{
		"id": &"steady_lantern",
		"title": "定灯",
		"description": "最大生命 +1，并立即回复 1 点生命。",
		"modifiers": {"max_health": 1, "heal": 1},
	},
	{
		"id": &"crosswind",
		"title": "横风",
		"description": "自动武器射速 +10%，子弹穿透 +1。",
		"modifiers": {"weapon_rate_multiplier": 0.10, "weapon_pierce": 1},
	},
	{
		"id": &"clear_current",
		"title": "清流",
		"description": "展开折域时移动速度 +10%，受击保护时间 +0.08 秒。",
		"modifiers": {"fold_move_speed_multiplier": 0.10, "damage_grace_add": 0.08},
	},
]

var config: FoldlightEndlessSurvivalConfig
var survival_seconds: float = 0.0
var absorbed_total: int = 0
var enemy_stage: int = 0
var player_absorb_stage: int = 0
var mission_reward_levels: Dictionary = {}
var mission_modifiers: Dictionary = {}


func reset(run_config: FoldlightEndlessSurvivalConfig) -> void:
	config = run_config
	survival_seconds = 0.0
	absorbed_total = 0
	enemy_stage = 0
	player_absorb_stage = 0
	mission_reward_levels.clear()
	mission_modifiers = _empty_modifier_snapshot()
	enemy_evolution_changed.emit(get_enemy_snapshot())
	player_evolution_changed.emit(get_player_snapshot())
	mission_evolution_changed.emit(get_mission_snapshot())


func advance_survival(delta: float) -> void:
	if config == null or delta <= 0.0:
		return
	survival_seconds += delta
	var previous := enemy_stage
	while enemy_stage < config.enemy_stage_times.size() and survival_seconds >= config.enemy_stage_times[enemy_stage]:
		enemy_stage += 1
	if enemy_stage != previous:
		enemy_evolution_changed.emit(get_enemy_snapshot())


func record_absorbed(projectile_count: int) -> void:
	if config == null or projectile_count <= 0:
		return
	absorbed_total += projectile_count
	var previous := player_absorb_stage
	while player_absorb_stage < config.player_absorb_thresholds.size() and absorbed_total >= config.player_absorb_thresholds[player_absorb_stage]:
		player_absorb_stage += 1
	if player_absorb_stage != previous:
		player_evolution_changed.emit(get_player_snapshot())


func get_mission_reward_options(completion_count: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var reward_tier := posmod(maxi(0, completion_count), 2)
	for lane: Dictionary in MISSION_REWARD_LANES:
		var reward_ids := lane.get("reward_ids", []) as Array
		if reward_tier >= reward_ids.size():
			continue
		var reward_id := StringName(reward_ids[reward_tier])
		var option := _decorate_mission_reward(_mission_reward_by_id(reward_id), lane)
		if option.is_empty():
			continue
		option["next_level"] = int(mission_reward_levels.get(reward_id, 0)) + 1
		options.append(option)
	return options


func apply_mission_reward(reward_id: StringName) -> Dictionary:
	var reward := _mission_reward_by_id(reward_id)
	if reward.is_empty():
		return {}
	reward = _decorate_mission_reward(reward, _mission_lane_for_reward(reward_id))
	mission_reward_levels[reward_id] = int(mission_reward_levels.get(reward_id, 0)) + 1
	var modifiers := reward.get("modifiers", {}) as Dictionary
	for key: Variant in modifiers:
		mission_modifiers[key] = float(mission_modifiers.get(key, 0.0)) + float(modifiers[key])
	var result := reward.duplicate(true)
	result["level"] = int(mission_reward_levels[reward_id])
	result["total_modifiers"] = mission_modifiers.duplicate(true)
	mission_evolution_changed.emit(get_mission_snapshot())
	return result


func get_enemy_snapshot() -> Dictionary:
	if config == null:
		return {}
	var stage_power := float(enemy_stage)
	var next_time := -1.0
	if enemy_stage < config.enemy_stage_times.size():
		next_time = config.enemy_stage_times[enemy_stage]
	return {
		"axis": &"survival_time",
		"stage": enemy_stage,
		"survival_seconds": survival_seconds,
		"next_stage_at": next_time,
		"health_multiplier": pow(config.health_growth_per_stage, stage_power),
		"projectile_multiplier": pow(config.projectile_growth_per_stage, stage_power),
		"wave_budget": mini(config.maximum_wave_budget, config.base_wave_budget + enemy_stage * 3),
		"spawn_interval": maxf(config.minimum_spawn_interval, config.base_spawn_interval - stage_power * 0.62),
		"captain_frequency": maxi(5 - enemy_stage / 2, 2),
	}


func get_player_snapshot() -> Dictionary:
	if config == null:
		return {}
	var next_threshold := -1
	if player_absorb_stage < config.player_absorb_thresholds.size():
		next_threshold = config.player_absorb_thresholds[player_absorb_stage]
	var totals := _empty_modifier_snapshot()
	var unlocked: Array[Dictionary] = []
	for index in mini(player_absorb_stage, ABSORB_PERKS.size()):
		var perk := ABSORB_PERKS[index]
		unlocked.append(perk.duplicate(true))
		for key: Variant in perk:
			if key in [&"id", &"title"]:
				continue
			totals[key] = float(totals.get(key, 0.0)) + float(perk[key])
	return {
		"axis": &"absorbed_projectiles",
		"stage": player_absorb_stage,
		"absorbed_total": absorbed_total,
		"next_absorb_threshold": next_threshold,
		"unlocked_perks": unlocked,
		"total_modifiers": totals,
	}


func get_mission_snapshot() -> Dictionary:
	return {
		"axis": &"mission_rewards",
		"reward_levels": mission_reward_levels.duplicate(true),
		"total_modifiers": mission_modifiers.duplicate(true),
	}


func get_snapshot() -> Dictionary:
	return {
		"enemy": get_enemy_snapshot(),
		"player": get_player_snapshot(),
		"missions": get_mission_snapshot(),
		"axes_are_independent": true,
	}


func _mission_reward_by_id(reward_id: StringName) -> Dictionary:
	for reward in MISSION_REWARDS:
		if StringName(reward.get("id", &"")) == reward_id:
			return reward.duplicate(true)
	return {}


func _mission_lane_for_reward(reward_id: StringName) -> Dictionary:
	for lane: Dictionary in MISSION_REWARD_LANES:
		var reward_ids := lane.get("reward_ids", []) as Array
		if reward_id in reward_ids:
			return lane
	return {}


func _decorate_mission_reward(reward: Dictionary, lane: Dictionary) -> Dictionary:
	if reward.is_empty() or lane.is_empty():
		return {}
	var decorated := reward.duplicate(true)
	decorated["lane_id"] = StringName(lane.get("id", &""))
	decorated["lane_title"] = String(lane.get("title", "成长"))
	return decorated


func _empty_modifier_snapshot() -> Dictionary:
	return {
		"capture_capacity": 0.0,
		"fold_radius_multiplier": 0.0,
		"return_damage_multiplier": 0.0,
		"return_speed_multiplier": 0.0,
		"return_chain": 0.0,
		"fold_move_speed_multiplier": 0.0,
		"move_speed_multiplier": 0.0,
		"dash_cooldown_multiplier": 0.0,
		"max_health": 0.0,
		"heal": 0.0,
		"weapon_rate_multiplier": 0.0,
		"weapon_pierce": 0.0,
		"damage_grace_add": 0.0,
	}
