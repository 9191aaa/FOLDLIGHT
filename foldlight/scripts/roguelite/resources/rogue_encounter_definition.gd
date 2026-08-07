class_name FoldlightRogueEncounterDefinition
extends FoldlightRogueContentDefinition

@export_range(1, 64, 1) var threat_budget: int = 8
@export_range(1, 6, 1) var wave_count: int = 2
@export_range(4, 36, 1) var minimum_enemy_count: int = 12
@export_range(30.0, 180.0, 1.0) var target_duration: float = 80.0
@export_range(0, 3, 1) var controller_quota: int = 1
@export_range(0, 3, 1) var buffer_quota: int = 1
@export_range(0, 6, 1) var turret_quota: int = 2
@export_range(0.0, 1.0, 0.05) var minimum_fodder_ratio: float = 0.45
@export var enemy_ids: Array[StringName] = []
@export var room_tags: Array[StringName] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if threat_budget <= 0:
		errors.append("encounter %s needs a positive threat budget" % content_id)
	if enemy_ids.is_empty():
		errors.append("encounter %s needs an enemy pool" % content_id)
	if minimum_enemy_count < wave_count:
		errors.append("encounter %s needs at least one enemy per wave" % content_id)
	if minimum_fodder_ratio < 0.0 or minimum_fodder_ratio > 1.0:
		errors.append("encounter %s has an invalid fodder ratio" % content_id)
	return errors
