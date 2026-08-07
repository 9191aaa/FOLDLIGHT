class_name FoldlightRogueActiveItemDefinition
extends FoldlightRogueContentDefinition

@export_range(0.5, 60.0, 0.1) var cooldown: float = 8.0
@export var effect_id: StringName = &""
@export_range(0.0, 100.0, 0.1) var power: float = 1.0
@export_range(0.0, 30.0, 0.1) var duration: float = 0.0


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if cooldown <= 0.0:
		errors.append("active item %s needs a positive cooldown" % content_id)
	if effect_id.is_empty():
		errors.append("active item %s needs an effect_id" % content_id)
	return errors

