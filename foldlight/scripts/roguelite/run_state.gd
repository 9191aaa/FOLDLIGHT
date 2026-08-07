class_name FoldlightRogueRunState
extends Node

const SNAPSHOT_VERSION: int = 1

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
var active_item_id: StringName = &""
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
	# The second cleared room teaches active items as a deliberate reward. The
	# HUD starts with an empty slot instead of silently gifting an unexplained Q.
	active_item_id = &""
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


func mark_room_cleared(node_id: StringName) -> void:
	if not cleared_node_ids.has(node_id):
		cleared_node_ids.append(node_id)
	room_count += 1


func make_checkpoint() -> Dictionary:
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
		"active_item_id": String(active_item_id),
		"upgrade_levels": upgrade_levels.duplicate(true),
		"cleared_node_ids": _string_array(cleared_node_ids),
	}


func restore_checkpoint(source: Dictionary) -> bool:
	if int(source.get("version", 0)) != SNAPSHOT_VERSION:
		return false
	var source_route: Variant = source.get("route", {})
	if not source_route is Dictionary or (source_route as Dictionary).is_empty():
		return false
	seed = int(source.get("seed", 0))
	route = (source_route as Dictionary).duplicate(true)
	current_region = maxi(0, int(source.get("current_region", 0)))
	current_node_id = StringName(source.get("current_node_id", &""))
	room_count = maxi(0, int(source.get("room_count", 0)))
	elapsed = maxf(0.0, float(source.get("elapsed", 0.0)))
	glimmer = maxi(0, int(source.get("glimmer", 0)))
	max_health = maxi(1, int(source.get("max_health", 5)))
	health = clampi(int(source.get("health", max_health)), 0, max_health)
	weapon_ids = _name_array(source.get("weapon_ids", []))
	active_item_id = StringName(source.get("active_item_id", &""))
	var source_upgrades: Variant = source.get("upgrade_levels", {})
	upgrade_levels = (source_upgrades as Dictionary).duplicate(true) if source_upgrades is Dictionary else {}
	cleared_node_ids = _name_array(source.get("cleared_node_ids", []))
	return seed != 0 and not current_node_id.is_empty()


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
			var name := StringName(value)
			if not name.is_empty():
				result.append(name)
	return result
