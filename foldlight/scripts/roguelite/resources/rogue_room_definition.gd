class_name FoldlightRogueRoomDefinition
extends FoldlightRogueContentDefinition

enum RoomCategory { COMBAT, ELITE, CACHE, SHOP, EVENT, FORGE, REST, BOSS, PROLOGUE }

@export var category: RoomCategory = RoomCategory.COMBAT
@export var world_size: Vector2 = Vector2(2880.0, 1620.0)
@export_range(30.0, 240.0, 1.0) var target_duration: float = 80.0
@export var terrain_ids: Array[StringName] = []
@export var encounter_ids: Array[StringName] = []
@export var spawn_slots: Array[Vector2] = []
@export var turret_slots: Array[Vector2] = []
@export var door_slots: Array[Vector2] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if world_size.x < 1920.0 or world_size.y < 1080.0:
		errors.append("room %s cannot be smaller than the design viewport" % content_id)
	if target_duration <= 0.0:
		errors.append("room %s needs a positive target duration" % content_id)
	if category != RoomCategory.SHOP and category != RoomCategory.REST and door_slots.is_empty():
		errors.append("room %s needs at least one authored door slot" % content_id)
	return errors

