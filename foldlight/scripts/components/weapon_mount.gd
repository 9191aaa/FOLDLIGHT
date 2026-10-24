class_name FoldlightWeaponMount
extends Node

signal fire_requested(definition: FoldlightRogueWeaponDefinition)
signal shot_requested(snapshot: Dictionary)

const RESONANCE_REQUIRED: int = 8
const RESONANCE_DURATION: float = 3.0

var enabled: bool = false
var definitions: Array[FoldlightRogueWeaponDefinition] = []
var _timers: Dictionary = {}
var _build_stats: Dictionary = {}
var _weapon_levels: Dictionary = {}
var _resonance_charge: int = 0
var _resonance_remaining: float = 0.0

func equip(definition: FoldlightRogueWeaponDefinition, level: int = 1) -> bool:
	if definition == null or not definition.validation_errors().is_empty():
		return false
	var key := String(definition.content_id)
	var next_level := clampi(level, 1, FoldlightWeaponProgression.MAX_LEVEL)
	for existing in definitions:
		if existing.content_id == definition.content_id:
			if next_level <= int(_weapon_levels.get(key, 1)):
				return false
			var old_interval := _effective_interval(existing)
			_weapon_levels[key] = next_level
			_timers[key] = float(_timers.get(key, old_interval)) * _effective_interval(existing) / old_interval
			return true
	definitions.append(definition)
	_weapon_levels[key] = next_level
	_timers[key] = _effective_interval(definition)
	return true


func unequip_all() -> void:
	definitions.clear()
	_timers.clear()
	_weapon_levels.clear()
	reset_resonance()


func set_weapon_levels(levels: Dictionary) -> void:
	var desired := FoldlightWeaponProgression.sanitize_levels(levels)
	# A restored pre-array save may have replaced its starter. Synchronize the
	# exact saved inventory while preserving cadence for retained weapons.
	for definition in definitions.duplicate():
		var key := String(definition.content_id)
		if not desired.has(key):
			definitions.erase(definition)
			_timers.erase(key)
			_weapon_levels.erase(key)
	for key: String in desired:
		var definition := FoldlightRogueContentCatalog.weapon_by_id(StringName(key))
		var next_level := int(desired[key])
		if int(_weapon_levels.get(key, 0)) > next_level:
			var old_interval := _effective_interval(definition)
			_weapon_levels[key] = next_level
			_timers[key] = float(_timers.get(key, old_interval)) * _effective_interval(definition) / old_interval
		else:
			equip(definition, next_level)


func get_inventory_snapshot() -> Array[Dictionary]:
	if definitions.is_empty():
		return []
	return FoldlightWeaponProgression.inventory_snapshot(_weapon_levels)


func get_resonance_snapshot() -> Dictionary:
	return {"charge": _resonance_charge, "required": RESONANCE_REQUIRED, "remaining": _resonance_remaining, "duration": RESONANCE_DURATION, "active": _resonance_remaining > 0.0}


func register_returned_light(captured_count: int) -> bool:
	if not enabled or captured_count <= 0 or _resonance_remaining > 0.0:
		return false
	_resonance_charge = mini(RESONANCE_REQUIRED, _resonance_charge + captured_count)
	if _resonance_charge < RESONANCE_REQUIRED:
		return false
	_resonance_charge = 0
	_resonance_remaining = RESONANCE_DURATION
	return true


func advance_resonance(delta: float) -> void:
	if enabled:
		_resonance_remaining = maxf(0.0, _resonance_remaining - maxf(0.0, delta))


func reset_resonance() -> void:
	_resonance_charge = 0
	_resonance_remaining = 0.0


func tick(delta: float, has_valid_target: bool) -> void:
	if not enabled:
		return
	for definition in definitions:
		var key := String(definition.content_id)
		var cadence_scale := 1.2 if _resonance_remaining > 0.0 else 1.0
		var remaining := float(_timers[key]) if _timers.has(key) else _effective_interval(definition)
		var timer := maxf(0.0, remaining - maxf(0.0, delta) * cadence_scale)
		if timer <= 0.0 and has_valid_target:
			shot_requested.emit(make_shot_snapshot(definition))
			fire_requested.emit(definition)
			timer = _effective_interval(definition)
		_timers[key] = timer


func reset_cadence() -> void:
	for definition in definitions:
		_timers[String(definition.content_id)] = _effective_interval(definition)


func configure_build(stats: Dictionary) -> void:
	var old_intervals: Dictionary = {}
	for definition in definitions:
		old_intervals[String(definition.content_id)] = _effective_interval(definition)
	_build_stats = stats.duplicate(true)
	for definition in definitions:
		var key := String(definition.content_id)
		var old_interval := float(old_intervals[key])
		_timers[key] = float(_timers.get(key, old_interval)) * _effective_interval(definition) / old_interval


func make_shot_snapshot(definition: FoldlightRogueWeaponDefinition) -> Dictionary:
	if definition == null:
		return {}
	var level := int(_weapon_levels.get(String(definition.content_id), 1))
	var progression := FoldlightWeaponProgression.level_stats(definition.content_id, level)
	return {
		"weapon_id": definition.content_id,
		"weapon_level": level,
		"color": definition.accent,
		"targeting": definition.targeting,
		"targeting_range": definition.targeting_range * float(progression.get("range_multiplier", 1.0)),
		"fire_interval": _effective_interval(definition),
		"damage": definition.base_damage * float(_build_stats.get("weapon_damage_multiplier", 1.0)) * float(progression.get("damage_multiplier", 1.0)) * (1.2 if _resonance_remaining > 0.0 else 1.0),
		"projectile_speed": definition.projectile_speed * float(_build_stats.get("projectile_speed_multiplier", 1.0)),
		"volley_count": clampi(definition.volley_count + int(round(float(_build_stats.get("weapon_volley_add", 0.0)))) + int(progression.get("volley_bonus", 0)), 1, 8),
		"pierce": clampi(definition.pierce + int(round(float(_build_stats.get("projectile_pierce_add", 0.0)))) + int(progression.get("pierce_bonus", 0)), 0, 12),
		"projectile_style": definition.projectile_style,
		"projectile_size_multiplier": float(_build_stats.get("projectile_size_multiplier", 1.0)),
		"critical_chance": clampf(float(_build_stats.get("critical_chance", 0.0)), 0.0, 0.75),
		"projectile_echo_chance": clampf(float(_build_stats.get("projectile_echo_chance", 0.0)), 0.0, 0.75),
		"execute_damage_multiplier": maxf(1.0, float(_build_stats.get("execute_damage_multiplier", 1.0))) * float(progression.get("execute_multiplier", 1.0)),
		"area_radius_multiplier": float(progression.get("area_radius_multiplier", 1.0)),
		"return_damage_multiplier": float(progression.get("return_damage_multiplier", 1.0)),
	}


func _effective_interval(definition: FoldlightRogueWeaponDefinition) -> float:
	var progression := FoldlightWeaponProgression.level_stats(definition.content_id, int(_weapon_levels.get(String(definition.content_id), 1)))
	return maxf(0.16, definition.fire_interval * float(_build_stats.get("weapon_interval_multiplier", 1.0)) * float(progression.get("interval_multiplier", 1.0)))
