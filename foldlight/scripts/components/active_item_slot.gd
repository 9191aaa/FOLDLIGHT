class_name FoldlightActiveItemSlot
extends Node

signal item_used(definition: FoldlightRogueActiveItemDefinition)
signal readiness_changed(ready: bool)

var enabled: bool = false
var definition: FoldlightRogueActiveItemDefinition
var cooldown_remaining: float = 0.0


func equip(new_definition: FoldlightRogueActiveItemDefinition) -> bool:
	if new_definition == null or not new_definition.validation_errors().is_empty():
		return false
	definition = new_definition
	cooldown_remaining = 0.0
	readiness_changed.emit(enabled)
	return true


func replace(new_definition: FoldlightRogueActiveItemDefinition) -> FoldlightRogueActiveItemDefinition:
	if new_definition == null or not new_definition.validation_errors().is_empty():
		return null
	var previous := definition
	definition = new_definition
	cooldown_remaining = 0.0
	readiness_changed.emit(enabled)
	return previous


func unequip() -> void:
	definition = null
	cooldown_remaining = 0.0


func request_use() -> bool:
	if not is_ready():
		return false
	cooldown_remaining = definition.cooldown
	item_used.emit(definition)
	readiness_changed.emit(false)
	return true


func tick(delta: float) -> void:
	var was_ready := is_ready()
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if was_ready != is_ready():
		readiness_changed.emit(is_ready())


func is_ready() -> bool:
	return enabled and definition != null and cooldown_remaining <= 0.0


func get_cooldown_ratio() -> float:
	if definition == null or definition.cooldown <= 0.0:
		return 0.0
	return clampf(cooldown_remaining / definition.cooldown, 0.0, 1.0)
