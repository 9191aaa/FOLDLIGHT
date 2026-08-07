class_name FoldlightRogueBossDefinition
extends FoldlightRogueContentDefinition

@export_range(100.0, 10000.0, 10.0) var base_health: float = 900.0
@export var phase_thresholds: PackedFloat32Array = PackedFloat32Array([0.68, 0.34])
@export var arena_rule: StringName = &""
@export_range(0.02, 1.0, 0.01) var return_window_fraction: float = 0.14
@export_range(0.1, 10.0, 0.1) var return_window_seconds: float = 1.2
@export_range(0.1, 1.0, 0.05) var return_damage_outside_stagger: float = 0.25
@export_range(120.0, 600.0, 1.0) var target_duration: float = 240.0
@export var pattern_ids: Array[StringName] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if base_health <= 0.0 or target_duration <= 0.0:
		errors.append("boss %s has invalid duration or health" % content_id)
	if phase_thresholds.size() < 2:
		errors.append("boss %s needs at least three explicit phases" % content_id)
	if arena_rule.is_empty():
		errors.append("boss %s needs an arena rule" % content_id)
	if pattern_ids.is_empty():
		errors.append("boss %s needs attack patterns" % content_id)
	return errors
