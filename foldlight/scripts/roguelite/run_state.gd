class_name FoldlightRogueRunState
extends Node

const SNAPSHOT_VERSION: int = 3

var seed: int = 0
var route: Dictionary = {}
var current_region: int = 0
var current_node_id: StringName = &""
var room_count: int = 0
var elapsed: float = 0.0
var glimmer: int = 0
var health: int = 5
var max_health: int = 5
var weapon_ids: Array[StringName] = []
var weapon_levels: Dictionary = {}
var active_item_id: StringName = &""
var active_item_ids: Array[StringName] = []
var active_item_cooldowns: Dictionary = {}
var upgrade_levels: Dictionary = {}
var cleared_node_ids: Array[StringName] = []


func begin_run(run_seed: int, route_snapshot: Dictionary) -> void:
	seed = run_seed
	route = route_snapshot.duplicate(true)
	current_region = 0
	current_node_id = _first_node_id(route)
	room_count = 0
	elapsed = 0.0
	glimmer = 0
	health = 5
	max_health = 5
	weapon_ids = [&"crease_lantern"]
	weapon_levels = {"crease_lantern": 1}
	# The second cleared room teaches active items as a deliberate reward. The
	# HUD starts with an empty slot instead of silently gifting an unexplained Q.
	active_item_id = &""
	active_item_ids.clear()
	active_item_cooldowns.clear()
	upgrade_levels.clear()
	cleared_node_ids.clear()


func apply_upgrade(upgrade_id: StringName, maximum: int = 8) -> int:
	if upgrade_id.is_empty():
		return 0
	var key := String(upgrade_id)
	var level := mini(maximum, int(upgrade_levels.get(key, 0)) + 1)
	upgrade_levels[key] = level
	return level


func get_upgrade_level(upgrade_id: StringName) -> int:
	return int(upgrade_levels.get(String(upgrade_id), 0))


func acquire_weapon(weapon_id: StringName) -> bool:
	if FoldlightRogueContentCatalog.weapon_by_id(weapon_id) == null:
		return false
	_sync_weapon_inventory()
	var key := String(weapon_id)
	var current_level := int(weapon_levels.get(key, 0))
	if current_level >= FoldlightWeaponProgression.MAX_LEVEL:
		return false
	weapon_levels[key] = current_level + 1
	if not weapon_ids.has(weapon_id):
		weapon_ids.append(weapon_id)
	return true


func get_weapon_level(weapon_id: StringName) -> int:
	if FoldlightRogueContentCatalog.weapon_by_id(weapon_id) == null:
		return 0
	return clampi(int(weapon_levels.get(String(weapon_id), 1 if weapon_ids.has(weapon_id) else 0)), 0, FoldlightWeaponProgression.MAX_LEVEL)


func mark_room_cleared(node_id: StringName) -> void:
	if not cleared_node_ids.has(node_id):
		cleared_node_ids.append(node_id)
	room_count += 1


func acquire_active_item(item_id: StringName) -> bool:
	set_active_collection(get_active_collection())
	if FoldlightRogueContentCatalog.active_item_by_id(item_id) == null or active_item_ids.has(item_id):
		return false
	active_item_ids.append(item_id)
	active_item_cooldowns[String(item_id)] = 0.0
	active_item_id = item_id
	return true


func select_active_item(item_id: StringName) -> bool:
	if not active_item_ids.has(item_id):
		return false
	active_item_id = item_id
	return true


func get_active_collection() -> Dictionary:
	return FoldlightActiveItemSlot.sanitize_collection({
		"active_item_ids": active_item_ids, "active_item_id": active_item_id,
		"active_item_cooldowns": active_item_cooldowns,
	})


func set_active_collection(source: Dictionary) -> void:
	var clean := FoldlightActiveItemSlot.sanitize_collection(source)
	active_item_ids = _name_array(clean["active_item_ids"])
	active_item_id = StringName(clean["active_item_id"])
	active_item_cooldowns = (clean["active_item_cooldowns"] as Dictionary).duplicate(true)


func make_checkpoint() -> Dictionary:
	_sync_weapon_inventory()
	set_active_collection(get_active_collection())
	return {
		"version": SNAPSHOT_VERSION,
		"seed": seed,
		"route": route.duplicate(true),
		"current_region": current_region,
		"current_node_id": String(current_node_id),
		"room_count": room_count,
		"elapsed": elapsed,
		"glimmer": glimmer,
		"health": health,
		"max_health": max_health,
		"weapon_ids": _string_array(weapon_ids),
		"weapon_levels": weapon_levels.duplicate(true),
		"active_item_id": String(active_item_id),
		"active_item_ids": _string_array(active_item_ids),
		"active_item_cooldowns": active_item_cooldowns.duplicate(true),
		"upgrade_levels": upgrade_levels.duplicate(true),
		"cleared_node_ids": _string_array(cleared_node_ids),
	}


func restore_checkpoint(source: Dictionary) -> bool:
	var version := int(source.get("version", 0))
	if version < 1 or version > SNAPSHOT_VERSION:
		return false
	var source_route: Variant = source.get("route", {})
	if not source_route is Dictionary or (source_route as Dictionary).is_empty():
		return false
	var restored_seed := int(source.get("seed", 0))
	var restored_node: Variant = source.get("current_node_id", &"")
	if restored_seed == 0 or (not restored_node is String and not restored_node is StringName) or String(restored_node).is_empty():
		return false
	seed = restored_seed
	route = (source_route as Dictionary).duplicate(true)
	current_region = maxi(0, int(source.get("current_region", 0)))
	current_node_id = StringName(restored_node)
	room_count = maxi(0, int(source.get("room_count", 0)))
	elapsed = maxf(0.0, float(source.get("elapsed", 0.0)))
	glimmer = maxi(0, int(source.get("glimmer", 0)))
	max_health = maxi(1, int(source.get("max_health", 5)))
	health = clampi(int(source.get("health", max_health)), 0, max_health)
	weapon_ids = _name_array(source.get("weapon_ids", []))
	var source_levels: Variant = source.get("weapon_levels", {}) if version >= 2 else {}
	weapon_levels = FoldlightWeaponProgression.sanitize_levels(source_levels if source_levels is Dictionary else {}, weapon_ids)
	_sync_weapon_inventory()
	set_active_collection(source if version >= 3 else {"active_item_id": source.get("active_item_id", "")})
	var source_upgrades: Variant = source.get("upgrade_levels", {})
	upgrade_levels = (source_upgrades as Dictionary).duplicate(true) if source_upgrades is Dictionary else {}
	cleared_node_ids = _name_array(source.get("cleared_node_ids", []))
	return true


func _sync_weapon_inventory() -> void:
	weapon_levels = FoldlightWeaponProgression.sanitize_levels(weapon_levels, weapon_ids)
	weapon_ids.clear()
	for key: String in weapon_levels:
		weapon_ids.append(StringName(key))


func _first_node_id(route_snapshot: Dictionary) -> StringName:
	var regions_variant: Variant = route_snapshot.get("regions", [])
	if not regions_variant is Array or (regions_variant as Array).is_empty():
		return &""
	var first_variant: Variant = (regions_variant as Array)[0]
	if not first_variant is Dictionary:
		return &""
	return StringName((first_variant as Dictionary).get("start_id", &""))


func _string_array(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


func _name_array(source: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if source is Array:
		for value: Variant in source:
			if not value is String and not value is StringName:
				continue
			var name := StringName(value)
			if not name.is_empty() and not result.has(name):
				result.append(name)
	return result
