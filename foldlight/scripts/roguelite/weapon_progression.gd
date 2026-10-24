class_name FoldlightWeaponProgression
extends RefCounted

## Per-run ranks are plain data. Authored weapon Resources remain read-only.
const MAX_LEVEL: int = 5
const STARTER_ID: StringName = &"crease_lantern"
const ROLES: Dictionary = {
	"crease_lantern": "追猎 · 稳定点杀",
	"needle_orbit": "护身 · 旋针索敌",
	"returning_gull": "折返 · 往返穿群",
	"tide_bell": "震荡 · 范围清场",
	"prism_fan": "散射 · 贴近爆发",
	"sun_thread": "贯穿 · 残血收割",
}


static func sanitize_levels(source: Dictionary, fallback_ids: Array[StringName] = []) -> Dictionary:
	var result: Dictionary = {}
	for raw_id: Variant in source:
		if not raw_id is String and not raw_id is StringName:
			continue
		var weapon_id := StringName(raw_id)
		if FoldlightRogueContentCatalog.weapon_by_id(weapon_id) == null:
			continue
		var raw_level: Variant = source[raw_id]
		if not raw_level is int and not raw_level is float:
			continue
		if raw_level is float and not is_finite(float(raw_level)):
			continue
		var key := String(weapon_id)
		var level := int(clampf(float(raw_level), 1.0, float(MAX_LEVEL)))
		result[key] = maxi(level, int(result.get(key, 1)))
	for weapon_id in fallback_ids:
		var key := String(weapon_id)
		if not result.has(key) and FoldlightRogueContentCatalog.weapon_by_id(weapon_id) != null:
			result[key] = 1
	if result.is_empty():
		result[String(STARTER_ID)] = 1
	return result


static func level_stats(weapon_id: StringName, level: int) -> Dictionary:
	if FoldlightRogueContentCatalog.weapon_by_id(weapon_id) == null:
		return {}
	var rank := clampi(level, 1, MAX_LEVEL)
	var evolved := rank >= 3
	var mastered := rank >= MAX_LEVEL
	var result := {
		"damage_multiplier": 1.0 + 0.18 * float(rank - 1),
		"interval_multiplier": 1.0 - 0.06 * float(rank - 1),
		"volley_bonus": 0,
		"pierce_bonus": 0,
		"range_multiplier": 1.0,
		"area_radius_multiplier": 1.0,
		"return_damage_multiplier": 1.0,
		"execute_multiplier": 1.0,
	}
	match weapon_id:
		&"crease_lantern":
			result["pierce_bonus"] = 1 if evolved else 0
			result["volley_bonus"] = 1 if mastered else 0
		&"needle_orbit":
			result["volley_bonus"] = 1 if evolved else 0
			result["pierce_bonus"] = 1 if mastered else 0
		&"returning_gull":
			result["return_damage_multiplier"] = 1.35 if evolved else 1.0
			result["volley_bonus"] = 1 if mastered else 0
		&"tide_bell":
			result["area_radius_multiplier"] = 1.5 if mastered else (1.25 if evolved else 1.0)
		&"prism_fan":
			result["volley_bonus"] = 2 if mastered else (1 if evolved else 0)
		&"sun_thread":
			result["execute_multiplier"] = 1.8 if mastered else (1.5 if evolved else 1.35)
			result["pierce_bonus"] = 1 if mastered else 0
	return result


static func make_choice(weapon_id: StringName, current_level: int) -> Dictionary:
	var definition := FoldlightRogueContentCatalog.weapon_by_id(weapon_id)
	if definition == null or current_level >= MAX_LEVEL:
		return {}
	var rank := clampi(current_level, 0, MAX_LEVEL - 1)
	var next_level := rank + 1
	var description := _acquisition_description(weapon_id)
	if rank > 0:
		description = "伤害提升，攻击更快。" + _next_trait_description(weapon_id, next_level)
	else:
		description += " 与已持有武器同时自动攻击。"
	return {
		"content_id": weapon_id,
		"choice_kind": &"weapon",
		"title": definition.title,
		"description": description,
		"accent": definition.accent,
		"current_level": rank,
		"next_level": next_level,
		"maximum_level": MAX_LEVEL,
		"display_rarity": "新增武器" if rank == 0 else ("满阶进化" if next_level == MAX_LEVEL else "武器强化"),
		"display_level": "Lv.1 · 新获" if rank == 0 else "Lv.%d → Lv.%d" % [rank, next_level],
		"offensive": true,
	}


static func draft_choices(run_seed: int, draft_index: int, owned_levels: Dictionary, unlocked_ids: Array, count: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count <= 0:
		return result
	var levels := sanitize_levels(owned_levels)
	var unlocked: Dictionary = {}
	for raw_id: Variant in unlocked_ids:
		if raw_id is String or raw_id is StringName:
			unlocked[String(raw_id)] = true
	var new_ids: Array[StringName] = []
	var upgrade_ids: Array[StringName] = []
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		var key := String(definition.content_id)
		if levels.has(key):
			if int(levels[key]) < MAX_LEVEL:
				upgrade_ids.append(definition.content_id)
		elif unlocked.has(key):
			new_ids.append(definition.content_id)
	# This local stream never consumes combat, encounter, or global randomness.
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ (draft_index * 2654435761) ^ 0x5745504e
	_shuffle_ids(new_ids, rng)
	_shuffle_ids(upgrade_ids, rng)
	var selected: Array[StringName] = []
	if not new_ids.is_empty():
		selected.append(new_ids.pop_back())
	if selected.size() < count and not upgrade_ids.is_empty():
		selected.append(upgrade_ids.pop_back())
	var remaining: Array[StringName] = []
	remaining.append_array(new_ids)
	remaining.append_array(upgrade_ids)
	_shuffle_ids(remaining, rng)
	while selected.size() < count and not remaining.is_empty():
		selected.append(remaining.pop_back())
	for weapon_id in selected:
		result.append(make_choice(weapon_id, int(levels.get(String(weapon_id), 0))))
	return result


static func inventory_snapshot(levels: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sanitized := sanitize_levels(levels)
	for key: String in sanitized:
		var weapon_id := StringName(key)
		var definition := FoldlightRogueContentCatalog.weapon_by_id(weapon_id)
		result.append({
			"id": weapon_id,
			"title": definition.title,
			"level": int(sanitized[key]),
			"accent": definition.accent,
			"role": String(ROLES.get(key, "自动攻击")),
		})
	return result


static func _shuffle_ids(values: Array[StringName], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap]
		values[swap] = held


static func _acquisition_description(weapon_id: StringName) -> String:
	match weapon_id:
		&"crease_lantern": return "折光追击最近的潮兽，稳定点杀。"
		&"needle_orbit": return "细针先环身护航，再飞向敌人。"
		&"returning_gull": return "纸鸥飞出再折返，往返都能命中。"
		&"tide_bell": return "潮钟在敌群中炸开，震伤周围敌人。"
		&"prism_fan": return "展开三束扇光，贴近敌人时集中爆发。"
		&"sun_thread": return "贯穿敌列，优先收割低血量目标。"
	return "自动武器加入当前阵列。"


static func _next_trait_description(weapon_id: StringName, next_level: int) -> String:
	var evolution_level := 3 if next_level <= 3 else MAX_LEVEL
	var prefix := "本阶解锁：" if next_level == evolution_level else "Lv.%d 解锁：" % evolution_level
	match weapon_id:
		&"crease_lantern": return prefix + ("折光额外贯穿 1 个目标。" if evolution_level == 3 else "每轮再发射 1 束折光。")
		&"needle_orbit": return prefix + ("每轮增加 1 枚护身环针。" if evolution_level == 3 else "环针额外贯穿 1 个目标。")
		&"returning_gull": return prefix + ("回程伤害额外提升 35%。" if evolution_level == 3 else "每轮增加 1 只回潮鸥。")
		&"tide_bell": return prefix + ("爆炸半径扩大 25%。" if evolution_level == 3 else "爆炸半径扩大至基础的 150%。")
		&"prism_fan": return prefix + ("扇面由 3 束增至 4 束。" if evolution_level == 3 else "扇面由 4 束增至 5 束。")
		&"sun_thread": return prefix + ("对低血量目标造成 150% 伤害。" if evolution_level == 3 else "收割伤害提高至 180%，额外贯穿 1 个目标。")
	return ""
