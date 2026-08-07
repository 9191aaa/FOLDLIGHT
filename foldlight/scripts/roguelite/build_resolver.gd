class_name FoldlightBuildResolver
extends RefCounted

## Upgrade definitions stay immutable. This resolver aggregates their current
## ID + stack snapshot only when gameplay or UI asks for effective values.

const MULTIPLIER_DEFAULTS: Array[StringName] = [
	&"weapon_interval_multiplier",
	&"weapon_damage_multiplier",
	&"projectile_speed_multiplier",
	&"return_speed_multiplier",
	&"dash_cooldown_multiplier",
	&"dash_speed_multiplier",
	&"fold_cooldown_multiplier",
	&"move_speed_multiplier",
	&"body_size_multiplier",
	&"glimmer_gain_multiplier",
]

const SUPPORTED_STAT_KEYS: Array[StringName] = [
	&"weapon_interval_multiplier", &"weapon_damage_multiplier", &"weapon_volley_add", &"critical_chance",
	&"return_damage_multiplier", &"return_speed_multiplier", &"return_chain_add", &"projectile_echo_chance", &"execute_damage_multiplier", &"projectile_pierce_add",
	&"projectile_size_multiplier", &"capture_capacity", &"fold_cooldown_multiplier", &"fold_radius_multiplier",
	&"cleanse_on_full_release", &"release_shield_threshold", &"release_shield_layers", &"fold_move_speed_add",
	&"full_release_damage_multiplier", &"full_release_cooldown_refund", &"dash_cooldown_multiplier", &"dash_charge_add",
	&"dash_duration_add", &"dash_speed_multiplier", &"dash_trail_damage", &"dash_refund_on_release",
	&"dash_refund_on_damage", &"dash_invulnerability_add", &"dash_weapon_haste", &"dash_weapon_haste_duration",
	&"body_size_multiplier", &"max_health_add", &"instant_heal", &"clear_heal_progress", &"fatal_guard_count",
	&"move_speed_multiplier", &"region_shield_per_ten_glimmer", &"glimmer_gain_multiplier", &"ink_slow_multiplier",
	&"damage_grace_add",
]


static func aggregate_stats(upgrade_levels: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for multiplier_name in MULTIPLIER_DEFAULTS:
		result[multiplier_name] = 1.0
	for id_variant: Variant in upgrade_levels.keys():
		var content_id := StringName(id_variant)
		var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
		if definition == null:
			continue
		var level := clampi(int(upgrade_levels.get(id_variant, 0)), 0, definition.max_stacks)
		if level <= 0:
			continue
		for stat_variant: Variant in definition.stat_modifiers.keys():
			var stat_name := StringName(stat_variant)
			var value: Variant = definition.stat_modifiers.get(stat_variant)
			if value is bool:
				result[stat_name] = bool(result.get(stat_name, false)) or bool(value)
			elif value is int or value is float:
				if String(stat_name).ends_with("_multiplier"):
					result[stat_name] = float(result.get(stat_name, 1.0)) * pow(float(value), level)
				else:
					result[stat_name] = float(result.get(stat_name, 0.0)) + float(value) * float(level)
	result["body_size_multiplier"] = clampf(float(result.get("body_size_multiplier", 1.0)), 0.72, 1.32)
	return result


static func apply_player_stats(player: FoldlightPlayer, upgrade_levels: Dictionary) -> Dictionary:
	var stats := aggregate_stats(upgrade_levels)
	if player != null:
		player.set_body_size_multiplier(float(stats.get("body_size_multiplier", 1.0)))
	return stats


static func modifier_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for definition in FoldlightRogueContentCatalog.UPGRADES:
		for stat_variant: Variant in definition.stat_modifiers.keys():
			var stat_name := StringName(stat_variant)
			if not SUPPORTED_STAT_KEYS.has(stat_name):
				errors.append("upgrade %s uses unsupported runtime modifier %s" % [definition.content_id, stat_name])
	return errors
