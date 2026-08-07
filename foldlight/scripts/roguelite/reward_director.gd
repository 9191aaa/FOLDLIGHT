class_name FoldlightRewardDirector
extends Node

const RARITY_WEIGHTS: Dictionary = {
	FoldlightRogueUpgradeDefinition.Rarity.COMMON: 60.0,
	FoldlightRogueUpgradeDefinition.Rarity.UNCOMMON: 30.0,
	FoldlightRogueUpgradeDefinition.Rarity.RARE: 13.0,
	FoldlightRogueUpgradeDefinition.Rarity.LEGENDARY: 4.0,
	FoldlightRogueUpgradeDefinition.Rarity.CURSED: 8.0,
}


func draft_upgrades(run_seed: int, room_index: int, owned_levels: Dictionary, unlocked_ids: Array[StringName], choice_count: int = 3) -> Array[Dictionary]:
	var legal_ids := legal_upgrade_ids(owned_levels, unlocked_ids)
	var candidates: Array[FoldlightRogueUpgradeDefinition] = []
	for content_id in legal_ids:
		var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
		if definition != null:
			candidates.append(definition)
	candidates.sort_custom(func(a: FoldlightRogueUpgradeDefinition, b: FoldlightRogueUpgradeDefinition) -> bool: return String(a.content_id) < String(b.content_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ (room_index + 1) * 1_103_515_245
	var result: Array[Dictionary] = []
	# Every ordinary room draft opens with one concrete firepower card. The
	# family check is data-driven, so later weapon upgrades inherit the rule
	# without maintaining another ID list.
	var offense_index := _weighted_offense_index(candidates, owned_levels, rng)
	if offense_index >= 0 and result.size() < maxi(0, choice_count):
		var offense := candidates[offense_index]
		candidates.remove_at(offense_index)
		result.append(_choice_snapshot(offense, int(owned_levels.get(String(offense.content_id), owned_levels.get(offense.content_id, 0))) + 1))
	while not candidates.is_empty() and result.size() < maxi(0, choice_count):
		# If no firepower card was legal, preserve the original breadth rule.
		var selected_index := _weighted_unowned_index(candidates, owned_levels, rng) if result.is_empty() else _weighted_index(candidates, rng)
		var selected := candidates[selected_index]
		candidates.remove_at(selected_index)
		result.append(_choice_snapshot(selected, int(owned_levels.get(String(selected.content_id), owned_levels.get(selected.content_id, 0))) + 1))
	return result


func _weighted_offense_index(candidates: Array[FoldlightRogueUpgradeDefinition], owned_levels: Dictionary, rng: RandomNumberGenerator) -> int:
	var offense_indices: Array[int] = []
	var offense_candidates: Array[FoldlightRogueUpgradeDefinition] = []
	for index in candidates.size():
		var definition := candidates[index]
		if definition.family != FoldlightRogueUpgradeDefinition.UpgradeFamily.WEAPON:
			continue
		offense_indices.append(index)
		offense_candidates.append(definition)
	if offense_indices.is_empty():
		return -1
	return offense_indices[_weighted_unowned_index(offense_candidates, owned_levels, rng)]


func _weighted_unowned_index(candidates: Array[FoldlightRogueUpgradeDefinition], owned_levels: Dictionary, rng: RandomNumberGenerator) -> int:
	var unowned_indices: Array[int] = []
	var unowned_candidates: Array[FoldlightRogueUpgradeDefinition] = []
	for index in candidates.size():
		var definition := candidates[index]
		if int(owned_levels.get(String(definition.content_id), owned_levels.get(definition.content_id, 0))) > 0:
			continue
		unowned_indices.append(index)
		unowned_candidates.append(definition)
	if unowned_indices.is_empty():
		return _weighted_index(candidates, rng)
	return unowned_indices[_weighted_index(unowned_candidates, rng)]


func legal_upgrade_ids(owned_levels: Dictionary, unlocked_ids: Array[StringName]) -> Array[StringName]:
	var unlocked: Dictionary = {}
	for content_id in unlocked_ids:
		unlocked[String(content_id)] = true
	var result: Array[StringName] = []
	for definition in FoldlightRogueContentCatalog.UPGRADES:
		if not unlocked.has(String(definition.content_id)):
			continue
		if int(owned_levels.get(String(definition.content_id), owned_levels.get(definition.content_id, 0))) >= definition.max_stacks:
			continue
		if not _prerequisites_met(definition, owned_levels):
			continue
		if _has_exclusion(definition, owned_levels):
			continue
		result.append(definition.content_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


func apply_upgrade_choice(run_state: FoldlightRogueRunState, content_id: StringName) -> bool:
	if run_state == null:
		return false
	var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
	if definition == null:
		return false
	var current := run_state.get_upgrade_level(content_id)
	if current >= definition.max_stacks:
		return false
	run_state.apply_upgrade(content_id, definition.max_stacks)
	return true


func _prerequisites_met(definition: FoldlightRogueUpgradeDefinition, owned_levels: Dictionary) -> bool:
	for prerequisite in definition.prerequisites:
		if int(owned_levels.get(String(prerequisite), owned_levels.get(prerequisite, 0))) <= 0:
			return false
	return true


func _has_exclusion(definition: FoldlightRogueUpgradeDefinition, owned_levels: Dictionary) -> bool:
	for exclusion in definition.exclusions:
		if int(owned_levels.get(String(exclusion), owned_levels.get(exclusion, 0))) > 0:
			return true
	for owned_variant: Variant in owned_levels.keys():
		if int(owned_levels.get(owned_variant, 0)) <= 0:
			continue
		var owned_definition := FoldlightRogueContentCatalog.upgrade_by_id(StringName(owned_variant))
		if owned_definition != null and owned_definition.exclusions.has(definition.content_id):
			return true
	return false


func _weighted_index(candidates: Array[FoldlightRogueUpgradeDefinition], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for definition in candidates:
		total += float(RARITY_WEIGHTS.get(definition.rarity, 1.0))
	var roll := rng.randf() * total
	for index in candidates.size():
		roll -= float(RARITY_WEIGHTS.get(candidates[index].rarity, 1.0))
		if roll <= 0.0:
			return index
	return candidates.size() - 1


func _choice_snapshot(definition: FoldlightRogueUpgradeDefinition, next_level: int) -> Dictionary:
	return {
		"content_id": definition.content_id,
		"title": definition.title,
		"description": definition.description,
		"accent": definition.accent,
		"family": definition.family,
		"rarity": definition.rarity,
		"offensive": definition.family == FoldlightRogueUpgradeDefinition.UpgradeFamily.WEAPON,
		"next_level": next_level,
		"maximum_level": definition.max_stacks,
		"stat_modifiers": definition.stat_modifiers.duplicate(true),
		"tags": definition.tags.duplicate(),
	}
