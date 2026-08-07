class_name FoldlightEncounterDirector
extends Node

## Produces a deterministic, serializable encounter plan. It never spawns nodes
## itself: room runtime owns telegraphs and actor lifetime.

# This caps the authored room total. Overlapping waves keep the actual live
# count much lower while preserving a sustained, ammunition-rich fight.
const MAX_LIVE_ENEMIES: int = 32
const MIN_PLAYER_SPAWN_DISTANCE: float = 180.0
const MIN_TERRAIN_SPAWN_DISTANCE: float = 100.0


func compose_encounter(
	definition: FoldlightRogueEncounterDefinition,
	enemy_catalog: Array[FoldlightRogueEnemyDefinition],
	seed: int,
	region_number: int,
	spawn_slots: Array[Dictionary],
	player_position: Vector2,
	blocked_bounds: Array[Rect2] = [],
	introduction_role: int = -1
) -> Dictionary:
	var errors: Array[String] = []
	if definition == null:
		return {"seed": seed, "spent": 0, "entries": [], "role_counts": {}, "errors": ["encounter definition is missing"]}
	var safe_slots := _safe_spawn_slots(spawn_slots, player_position, blocked_bounds)
	var ground_slots := _slots_of_kind(safe_slots, &"ground")
	var ranged_slots := _slots_of_kind(safe_slots, &"ranged")
	var turret_slots := _slots_of_kind(safe_slots, &"turret")
	if ground_slots.is_empty():
		errors.append("room has no safe ground spawn slots")

	var pool := _eligible_pool(definition, enemy_catalog, region_number)
	var fodder := _definitions_with_role(pool, FoldlightRogueEnemyDefinition.EnemyRole.FODDER)
	if fodder.is_empty():
		errors.append("encounter has no eligible fodder definition")
	if not errors.is_empty():
		return {"seed": seed, "spent": 0, "entries": [], "role_counts": {}, "errors": errors}

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var picks: Array[FoldlightRogueEnemyDefinition] = []
	var role_counts: Dictionary = {}
	var definition_counts: Dictionary = {}
	var spent := 0
	var fodder_target := int(ceil(float(definition.threat_budget) * definition.minimum_fodder_ratio))
	while spent < fodder_target and picks.size() < MAX_LIVE_ENEMIES:
		var choice := _choose_affordable(fodder, definition.threat_budget - spent, definition_counts, rng)
		if choice == null:
			break
		_append_pick(choice, picks, role_counts, definition_counts)
		spent += choice.threat_cost

	if introduction_role >= 0:
		var introduction_pool := _definitions_with_role(pool, introduction_role)
		var mechanic := _choose_affordable(introduction_pool, definition.threat_budget - spent, definition_counts, rng)
		if mechanic == null or not _role_has_capacity(mechanic.role, role_counts, definition, turret_slots.size()):
			errors.append("requested introduction mechanic cannot fit this encounter")
		else:
			_append_pick(mechanic, picks, role_counts, definition_counts)
			spent += mechanic.threat_cost
	else:
		var mechanics := _mechanic_pool(pool)
		_shuffle_definitions(mechanics, rng)
		for mechanic in mechanics:
			if picks.size() >= MAX_LIVE_ENEMIES:
				break
			if mechanic.threat_cost > definition.threat_budget - spent:
				continue
			if not _role_has_capacity(mechanic.role, role_counts, definition, turret_slots.size()):
				continue
			_append_pick(mechanic, picks, role_counts, definition_counts)
			spent += mechanic.threat_cost

	var ordinary := _ordinary_pool(pool)
	# Body density is a separate feel target from abstract threat. Fill the
	# readable body floor with the cheapest legal ordinary actors first so a
	# high-cost mechanic never turns a room into three lonely health bars.
	while picks.size() < mini(definition.minimum_enemy_count, MAX_LIVE_ENEMIES):
		var remaining := definition.threat_budget - spent
		if remaining <= 0:
			break
		var choice := _choose_cheapest_affordable(ordinary, remaining, definition_counts)
		if choice == null:
			break
		_append_pick(choice, picks, role_counts, definition_counts)
		spent += choice.threat_cost
	while picks.size() < MAX_LIVE_ENEMIES:
		var remaining := definition.threat_budget - spent
		if remaining <= 0:
			break
		var choice := _choose_affordable(ordinary, remaining, definition_counts, rng)
		if choice == null:
			break
		_append_pick(choice, picks, role_counts, definition_counts)
		spent += choice.threat_cost

	var entries := _assign_spawn_slots(picks, definition.wave_count, ground_slots, ranged_slots, turret_slots, rng, errors)
	if entries.size() != picks.size():
		errors.append("safe spawn capacity is lower than the composed encounter")
		spent = 0
		role_counts.clear()
		for entry_variant: Variant in entries:
			var entry := entry_variant as Dictionary
			spent += int(entry.get("threat_cost", 0))
			var role := int(entry.get("role", -1))
			role_counts[role] = int(role_counts.get(role, 0)) + 1
	return {
		"seed": seed,
		"encounter_id": definition.content_id,
		"budget": definition.threat_budget,
		"spent": spent,
		"entries": entries,
		"role_counts": role_counts.duplicate(true),
		"errors": errors,
	}


static func distance_to_rect(point: Vector2, rect: Rect2) -> float:
	if rect.has_point(point):
		return 0.0
	var nearest := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)
	return point.distance_to(nearest)


func _safe_spawn_slots(slots: Array[Dictionary], player_position: Vector2, blocked_bounds: Array[Rect2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot in slots:
		var slot_id := StringName(slot.get("id", &""))
		var slot_position := Vector2(slot.get("position", Vector2.ZERO))
		if slot_id.is_empty() or seen.has(slot_id):
			continue
		seen[slot_id] = true
		if slot_position.distance_to(player_position) < MIN_PLAYER_SPAWN_DISTANCE:
			continue
		var clear := true
		for blocker in blocked_bounds:
			if distance_to_rect(slot_position, blocker) < MIN_TERRAIN_SPAWN_DISTANCE:
				clear = false
				break
		if clear:
			result.append(slot.duplicate(true))
	return result


func _eligible_pool(definition: FoldlightRogueEncounterDefinition, catalog: Array[FoldlightRogueEnemyDefinition], region_number: int) -> Array[FoldlightRogueEnemyDefinition]:
	var allowed_ids: Dictionary = {}
	for content_id in definition.enemy_ids:
		allowed_ids[String(content_id)] = true
	var result: Array[FoldlightRogueEnemyDefinition] = []
	for enemy in catalog:
		if allowed_ids.has(String(enemy.content_id)) and enemy.minimum_region <= region_number and enemy.role != FoldlightRogueEnemyDefinition.EnemyRole.BOSS:
			result.append(enemy)
	return result


func _definitions_with_role(pool: Array[FoldlightRogueEnemyDefinition], role: int) -> Array[FoldlightRogueEnemyDefinition]:
	var result: Array[FoldlightRogueEnemyDefinition] = []
	for definition in pool:
		if definition.role == role:
			result.append(definition)
	return result


func _mechanic_pool(pool: Array[FoldlightRogueEnemyDefinition]) -> Array[FoldlightRogueEnemyDefinition]:
	var result: Array[FoldlightRogueEnemyDefinition] = []
	for definition in pool:
		if definition.role in [
			FoldlightRogueEnemyDefinition.EnemyRole.TURRET,
			FoldlightRogueEnemyDefinition.EnemyRole.BUFFER,
			FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER,
		]:
			result.append(definition)
	return result


func _ordinary_pool(pool: Array[FoldlightRogueEnemyDefinition]) -> Array[FoldlightRogueEnemyDefinition]:
	var result: Array[FoldlightRogueEnemyDefinition] = []
	for definition in pool:
		if definition.role in [
			FoldlightRogueEnemyDefinition.EnemyRole.FODDER,
			FoldlightRogueEnemyDefinition.EnemyRole.SHOOTER,
			FoldlightRogueEnemyDefinition.EnemyRole.CHARGER,
		]:
			result.append(definition)
	return result


func _choose_affordable(pool: Array[FoldlightRogueEnemyDefinition], remaining: int, counts: Dictionary, rng: RandomNumberGenerator) -> FoldlightRogueEnemyDefinition:
	var affordable: Array[FoldlightRogueEnemyDefinition] = []
	for definition in pool:
		if definition.threat_cost <= remaining and int(counts.get(definition.content_id, 0)) < definition.max_simultaneous:
			affordable.append(definition)
	if affordable.is_empty():
		return null
	return affordable[rng.randi_range(0, affordable.size() - 1)]


func _choose_cheapest_affordable(pool: Array[FoldlightRogueEnemyDefinition], remaining: int, counts: Dictionary) -> FoldlightRogueEnemyDefinition:
	var result: FoldlightRogueEnemyDefinition
	for definition in pool:
		if definition.threat_cost > remaining or int(counts.get(definition.content_id, 0)) >= definition.max_simultaneous:
			continue
		if result == null or definition.threat_cost < result.threat_cost:
			result = definition
	return result


func _append_pick(definition: FoldlightRogueEnemyDefinition, picks: Array[FoldlightRogueEnemyDefinition], role_counts: Dictionary, definition_counts: Dictionary) -> void:
	picks.append(definition)
	role_counts[definition.role] = int(role_counts.get(definition.role, 0)) + 1
	definition_counts[definition.content_id] = int(definition_counts.get(definition.content_id, 0)) + 1


func _role_has_capacity(role: int, role_counts: Dictionary, encounter: FoldlightRogueEncounterDefinition, turret_slot_count: int) -> bool:
	var current := int(role_counts.get(role, 0))
	match role:
		FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER:
			return current < encounter.controller_quota
		FoldlightRogueEnemyDefinition.EnemyRole.BUFFER:
			return current < encounter.buffer_quota
		FoldlightRogueEnemyDefinition.EnemyRole.TURRET:
			return current < mini(encounter.turret_quota, turret_slot_count)
	return true


func _slots_of_kind(slots: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in slots:
		if StringName(slot.get("kind", &"ground")) == kind:
			result.append(slot)
	return result


func _assign_spawn_slots(picks: Array[FoldlightRogueEnemyDefinition], wave_count: int, ground_slots: Array[Dictionary], ranged_slots: Array[Dictionary], turret_slots: Array[Dictionary], rng: RandomNumberGenerator, errors: Array[String]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var used_by_wave: Dictionary = {}
	var safe_wave_count := maxi(1, wave_count)
	for index in picks.size():
		var definition := picks[index]
		var wave := _weighted_wave_for_index(index, safe_wave_count)
		var candidates := ground_slots
		if definition.role == FoldlightRogueEnemyDefinition.EnemyRole.TURRET:
			candidates = turret_slots
		elif definition.role == FoldlightRogueEnemyDefinition.EnemyRole.SHOOTER and not ranged_slots.is_empty():
			# Shooter volleys are easiest to understand when their source is inside
			# the room composition instead of hidden against a distant screen edge.
			candidates = ranged_slots
		var available: Array[Dictionary] = []
		for slot in candidates:
			var key := "%d:%s" % [wave, String(slot.get("id", &""))]
			if not used_by_wave.has(key):
				available.append(slot)
		if available.is_empty():
			errors.append("wave %d has no unique safe slot for %s" % [wave + 1, definition.content_id])
			continue
		var slot := available[rng.randi_range(0, available.size() - 1)]
		var used_key := "%d:%s" % [wave, String(slot.get("id", &""))]
		used_by_wave[used_key] = true
		entries.append({
			"enemy_id": definition.content_id,
			"role": definition.role,
			"threat_cost": definition.threat_cost,
			"wave": wave,
			"spawn_slot": StringName(slot.get("id", &"")),
			"spawn_position": Vector2(slot.get("position", Vector2.ZERO)),
		})
	return entries


func _weighted_wave_for_index(index: int, wave_count: int) -> int:
	# A large room needs an immediately satisfying target field. Region one uses
	# a deliberately heavy opener; later four-wave rooms still front-load enough
	# bodies to read as a battle without dumping every mechanic at once.
	if wave_count == 3:
		var three_wave_pattern := PackedInt32Array([0, 1, 0, 2, 0, 1, 0, 2])
		return three_wave_pattern[index % three_wave_pattern.size()]
	if wave_count == 4:
		var four_wave_pattern := PackedInt32Array([0, 1, 0, 2, 3, 1, 0, 2, 3, 1, 0, 2])
		return four_wave_pattern[index % four_wave_pattern.size()]
	return index % maxi(1, wave_count)


func _shuffle_definitions(values: Array[FoldlightRogueEnemyDefinition], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
