class_name FoldlightRogueWeaponDefinition
extends FoldlightRogueContentDefinition

enum TargetingMode { NEAREST, LOWEST_HEALTH, FORWARD_CONE, ORBIT, RANDOM }

@export var targeting: TargetingMode = TargetingMode.NEAREST
@export_range(0.05, 10.0, 0.01) var fire_interval: float = 0.55
@export_range(0.1, 100.0, 0.1) var base_damage: float = 1.0
@export_range(50.0, 2400.0, 10.0) var projectile_speed: float = 820.0
@export_range(80.0, 1800.0, 10.0) var targeting_range: float = 900.0
@export_range(1, 16, 1) var volley_count: int = 1
@export_range(0, 8, 1) var pierce: int = 0
@export var projectile_style: StringName = &"crease_petal"


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if fire_interval <= 0.0:
		errors.append("weapon %s needs a positive fire interval" % content_id)
	if base_damage <= 0.0 or projectile_speed <= 0.0 or targeting_range <= 0.0:
		errors.append("weapon %s has invalid combat values" % content_id)
	if volley_count <= 0:
		errors.append("weapon %s must fire at least one projectile" % content_id)
	return errors

