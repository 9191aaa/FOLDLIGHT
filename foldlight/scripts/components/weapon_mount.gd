class_name FoldlightWeaponMount
extends Node

signal fire_requested(definition: FoldlightRogueWeaponDefinition)
signal shot_requested(snapshot: Dictionary)

var enabled: bool = false
var definitions: Array[FoldlightRogueWeaponDefinition] = []
var _timers: Dictionary = {}
var _build_stats: Dictionary = {}


func equip(definition: FoldlightRogueWeaponDefinition) -> bool:
	if definition == null or not definition.validation_errors().is_empty():
		return false
	for existing in definitions:
		if existing.content_id == definition.content_id:
			return false
	definitions.append(definition)
	_timers[String(definition.content_id)] = _effective_interval(definition)
	return true


func unequip_all() -> void:
	definitions.clear()
	_timers.clear()


func tick(delta: float, has_valid_target: bool) -> void:
	if not enabled:
		return
	for definition in definitions:
		var key := String(definition.content_id)
		var timer := maxf(0.0, float(_timers.get(key, _effective_interval(definition))) - delta)
		if timer <= 0.0 and has_valid_target:
			shot_requested.emit(make_shot_snapshot(definition))
			fire_requested.emit(definition)
			timer = _effective_interval(definition)
		_timers[key] = timer


func reset_cadence() -> void:
	for definition in definitions:
		_timers[String(definition.content_id)] = _effective_interval(definition)


func configure_build(stats: Dictionary) -> void:
	_build_stats = stats.duplicate(true)
	reset_cadence()


func make_shot_snapshot(definition: FoldlightRogueWeaponDefinition) -> Dictionary:
	if definition == null:
		return {}
	return {
		"weapon_id": definition.content_id,
		"targeting": definition.targeting,
		"targeting_range": definition.targeting_range,
		"fire_interval": _effective_interval(definition),
		"damage": definition.base_damage * float(_build_stats.get("weapon_damage_multiplier", 1.0)),
		"projectile_speed": definition.projectile_speed * float(_build_stats.get("projectile_speed_multiplier", 1.0)),
		"volley_count": maxi(1, definition.volley_count + int(round(float(_build_stats.get("weapon_volley_add", 0.0))))),
		"pierce": maxi(0, definition.pierce + int(round(float(_build_stats.get("projectile_pierce_add", 0.0))))),
		"projectile_style": definition.projectile_style,
		"projectile_size_multiplier": float(_build_stats.get("projectile_size_multiplier", 1.0)),
		"critical_chance": clampf(float(_build_stats.get("critical_chance", 0.0)), 0.0, 0.75),
		"projectile_echo_chance": clampf(float(_build_stats.get("projectile_echo_chance", 0.0)), 0.0, 0.75),
		"execute_damage_multiplier": maxf(1.0, float(_build_stats.get("execute_damage_multiplier", 1.0))),
	}


func _effective_interval(definition: FoldlightRogueWeaponDefinition) -> float:
	return maxf(0.08, definition.fire_interval * float(_build_stats.get("weapon_interval_multiplier", 1.0)))
