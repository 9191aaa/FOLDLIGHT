class_name FoldlightActiveItemSlot
extends Node

signal item_used(definition: FoldlightRogueActiveItemDefinition)
signal readiness_changed(ready: bool)
signal inventory_changed

var enabled: bool = false
var _owned: Dictionary = {}
var _cooldowns: Dictionary = {}
var _equipped: FoldlightRogueActiveItemDefinition

# Preserve the old writable combat properties without resetting other skills.
var definition: FoldlightRogueActiveItemDefinition:
	get: return _equipped
	set(value):
		if value == null:
			_equipped = null
		else:
			acquire(value)
var cooldown_remaining: float:
	get: return float(_cooldowns.get(String(_equipped.content_id), 0.0)) if _equipped != null else 0.0
	set(value):
		if _equipped != null:
			_cooldowns[String(_equipped.content_id)] = clampf(value, 0.0, _equipped.cooldown) if is_finite(value) else 0.0


func acquire(new_definition: FoldlightRogueActiveItemDefinition, equip_now: bool = true) -> bool:
	if new_definition == null or not new_definition.validation_errors().is_empty():
		return false
	var key := String(new_definition.content_id)
	if not _owned.has(key):
		_owned[key] = new_definition
		_cooldowns[key] = 0.0
	if equip_now or _equipped == null:
		_equipped = _owned[key] as FoldlightRogueActiveItemDefinition
	readiness_changed.emit(is_ready())
	inventory_changed.emit()
	return true


func select(item_id: StringName) -> bool:
	if not _owned.has(String(item_id)):
		return false
	_equipped = _owned[String(item_id)] as FoldlightRogueActiveItemDefinition
	readiness_changed.emit(is_ready())
	inventory_changed.emit()
	return true


func equip(new_definition: FoldlightRogueActiveItemDefinition) -> bool:
	return acquire(new_definition)


func replace(new_definition: FoldlightRogueActiveItemDefinition) -> FoldlightRogueActiveItemDefinition:
	var previous := definition
	return previous if acquire(new_definition) else null


func unequip() -> void:
	# Explicit run reset; ordinary selection uses select/acquire instead.
	_equipped = null
	_owned.clear()
	_cooldowns.clear()
	readiness_changed.emit(false)
	inventory_changed.emit()


func restore_collection(source: Dictionary) -> void:
	var clean := sanitize_collection(source)
	_equipped = null
	_owned.clear()
	_cooldowns = (clean["active_item_cooldowns"] as Dictionary).duplicate(true)
	for item_id: String in clean["active_item_ids"]:
		_owned[item_id] = FoldlightRogueContentCatalog.active_item_by_id(StringName(item_id))
	_equipped = _owned.get(clean["active_item_id"]) as FoldlightRogueActiveItemDefinition
	readiness_changed.emit(is_ready())
	inventory_changed.emit()


func get_save_snapshot() -> Dictionary:
	return {
		"active_item_ids": _owned.keys(),
		"active_item_id": String(_equipped.content_id) if _equipped != null else "",
		"active_item_cooldowns": _cooldowns.duplicate(true),
	}


func get_inventory_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _owned:
		var item := _owned[key] as FoldlightRogueActiveItemDefinition
		result.append({
			"id": item.content_id, "title": item.title, "description": item.description,
			"usage_label": str(item.get("usage_label")), "accent": item.accent,
			"cooldown_remaining": float(_cooldowns.get(key, 0.0)),
			"cooldown_duration": item.cooldown, "equipped": item == _equipped,
		})
	return result


func request_use() -> bool:
	if not is_ready():
		return false
	cooldown_remaining = definition.cooldown
	item_used.emit(definition)
	readiness_changed.emit(false)
	return true


func tick(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	var was_ready := is_ready()
	for key: String in _cooldowns:
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
	if was_ready != is_ready():
		readiness_changed.emit(is_ready())


func is_ready() -> bool:
	return enabled and definition != null and cooldown_remaining <= 0.0


func get_cooldown_ratio() -> float:
	if definition == null or definition.cooldown <= 0.0:
		return 0.0
	return clampf(cooldown_remaining / definition.cooldown, 0.0, 1.0)


static func sanitize_collection(source: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	var raw_ids: Variant = source.get("active_item_ids", [])
	if raw_ids is Array:
		for value: Variant in raw_ids:
			var item_id := _valid_id(value)
			if not item_id.is_empty() and not ids.has(item_id):
				ids.append(item_id)
	# Legacy single-slot saves and direct active_item_id writes share migration.
	var selected := _valid_id(source.get("active_item_id", ""))
	if not selected.is_empty() and not ids.has(selected):
		ids.append(selected)
	if selected.is_empty() and not ids.is_empty():
		selected = ids[0]
	var raw_cooldowns: Variant = source.get("active_item_cooldowns", {})
	var cooldowns: Dictionary = {}
	for item_id: String in ids:
		var value: Variant = raw_cooldowns.get(item_id, 0.0) if raw_cooldowns is Dictionary else 0.0
		var duration := FoldlightRogueContentCatalog.active_item_by_id(StringName(item_id)).cooldown
		cooldowns[item_id] = clampf(float(value), 0.0, duration) if (value is int or value is float) and is_finite(float(value)) else 0.0
	return {"active_item_ids": ids, "active_item_id": selected, "active_item_cooldowns": cooldowns}


static func make_choice(item_id: StringName) -> Dictionary:
	var item := FoldlightRogueContentCatalog.active_item_by_id(item_id)
	if item == null:
		return {}
	return {
		"id": item.content_id, "content_id": item.content_id, "choice_kind": &"active",
		"title": item.title, "description": item.description, "usage_label": str(item.get("usage_label")),
		"rarity": 1, "accent": item.accent, "cooldown_duration": item.cooldown, "next_level": 1, "maximum_level": 1,
		"collected": false, "equipped": false, "selection_action": &"collect",
		"offensive": item.effect_id in [&"radial_push", &"anchor_shield", &"weapon_overdrive"],
	}


static func _valid_id(value: Variant) -> String:
	if not value is String and not value is StringName:
		return ""
	var item_id := StringName(value)
	return String(item_id) if FoldlightRogueContentCatalog.active_item_by_id(item_id) != null else ""
