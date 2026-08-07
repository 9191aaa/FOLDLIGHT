class_name FoldlightRogueContentDefinition
extends Resource

@export var content_id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var accent: Color = Color(0.30, 0.88, 0.86)
@export var tags: Array[StringName] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if content_id.is_empty():
		errors.append("content_id is required")
	if title.strip_edges().is_empty():
		errors.append("title is required for %s" % content_id)
	return errors

