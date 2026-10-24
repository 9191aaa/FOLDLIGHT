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
@export var region_id: StringName = &""
## Zero keeps the original three bosses' authored phase timings unchanged.
@export_range(0.0, 3.0, 0.05) var telegraph_seconds: float = 0.0
@export_range(0.0, 3.0, 0.05) var recovery_seconds: float = 0.0
@export var active_pattern_seconds: Dictionary = {}
## Only the executioner's body-charge pattern reads these values.
@export_range(1, 8, 1) var charge_chain_count: int = 4
@export_range(0.35, 1.5, 0.05) var charge_chain_warning: float = 0.60
@export_range(0.2, 0.8, 0.01) var charge_chain_duration: float = 0.29
@export_range(300.0, 1200.0, 10.0) var charge_chain_distance: float = 820.0
## Commander multipliers are copied to actor instances, never to Resources.
@export_range(200.0, 1200.0, 10.0) var command_radius: float = 700.0


func get_charge_settings(phase: int, intensity: int) -> Dictionary:
	var tier := clampi(intensity, 0, 5)
	return {"count": clampi(charge_chain_count + phase + tier / 2, 1, 8),
		"warning": maxf(0.42, charge_chain_warning - phase * 0.035 - tier * 0.025),
		"duration": maxf(0.20, charge_chain_duration - phase * 0.02 - tier * 0.012),
		"distance": minf(1120.0, charge_chain_distance + phase * 60.0 + tier * 36.0)}


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
	for pattern: Variant in active_pattern_seconds:
		if not pattern_ids.has(StringName(pattern)) or not is_finite(float(active_pattern_seconds[pattern])) or float(active_pattern_seconds[pattern]) <= 0.0 or float(active_pattern_seconds[pattern]) > 2.0:
			errors.append("boss %s has invalid active pattern timing" % content_id)
	return errors


func get_active_seconds(pattern_id: StringName) -> float:
	return clampf(float(active_pattern_seconds.get(pattern_id, 0.0)), 0.0, 2.0)
