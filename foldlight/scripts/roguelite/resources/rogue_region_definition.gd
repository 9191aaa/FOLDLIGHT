class_name FoldlightRogueRegionDefinition
extends FoldlightRogueContentDefinition

@export_range(5, 10, 1) var depth_count: int = 7
@export_range(1, 64, 1) var base_threat_budget: int = 8
@export var room_ids: Array[StringName] = []
@export var encounter_ids: Array[StringName] = []
@export var boss_ids: Array[StringName] = []
@export var backdrop_style: StringName = &"paper_reef"


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if depth_count < 5:
		errors.append("region %s must sustain at least five room depths" % content_id)
	if base_threat_budget <= 0:
		errors.append("region %s needs a positive threat budget" % content_id)
	if boss_ids.is_empty():
		errors.append("region %s needs at least one boss" % content_id)
	return errors

