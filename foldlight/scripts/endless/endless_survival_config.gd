class_name FoldlightEndlessSurvivalConfig
extends Resource

@export_group("Identity")
@export var mode_id: StringName = &"classic_2_0_endless"
@export var rules_version: StringName = &"endless_1_0"

@export_group("Independent Evolution Axes")
@export var enemy_stage_times := PackedFloat32Array([45.0, 105.0, 180.0, 270.0, 375.0, 495.0])
@export var player_absorb_thresholds := PackedInt32Array([24, 60, 112, 184, 280, 400])

@export_group("Pressure Curve")
@export_range(0.5, 20.0, 0.1) var base_spawn_interval: float = 6.5
@export_range(0.25, 10.0, 0.1) var minimum_spawn_interval: float = 2.1
@export_range(1, 30, 1) var base_wave_budget: int = 5
@export_range(1, 60, 1) var maximum_wave_budget: int = 28
@export_range(1.0, 5.0, 0.05) var health_growth_per_stage: float = 1.18
@export_range(1.0, 4.0, 0.05) var projectile_growth_per_stage: float = 1.12

@export_group("Objectives")
@export_range(3.0, 40.0, 0.5) var capture_hold_seconds: float = 12.0
@export_range(10.0, 180.0, 1.0) var objective_time_limit: float = 90.0
@export_range(1.0, 20.0, 0.5) var objective_intermission: float = 4.0
@export_range(5.0, 200.0, 1.0) var flag_health: float = 60.0

@export_group("Classic Compatibility")
@export var classic_enemy_ids: Array[StringName] = [
	&"drifter", &"fan", &"ram", &"bloomer", &"weaver", &"leech", &"mirror", &"rewinder",
]
@export var shooter_enemy_ids: Array[StringName] = [
	&"drifter", &"fan", &"bloomer", &"weaver", &"leech", &"mirror",
]


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if enemy_stage_times.is_empty() or player_absorb_thresholds.is_empty():
		errors.append("both endless evolution axes need thresholds")
	if not _strictly_increasing_floats(enemy_stage_times):
		errors.append("enemy stage times must be strictly increasing")
	if not _strictly_increasing_ints(player_absorb_thresholds):
		errors.append("player absorb thresholds must be strictly increasing")
	if classic_enemy_ids.size() < 8:
		errors.append("the complete 2.0 enemy family must remain available")
	if minimum_spawn_interval > base_spawn_interval:
		errors.append("minimum spawn interval cannot exceed the base interval")
	return errors


func _strictly_increasing_floats(values: PackedFloat32Array) -> bool:
	for index in range(1, values.size()):
		if values[index] <= values[index - 1]:
			return false
	return true


func _strictly_increasing_ints(values: PackedInt32Array) -> bool:
	for index in range(1, values.size()):
		if values[index] <= values[index - 1]:
			return false
	return true
