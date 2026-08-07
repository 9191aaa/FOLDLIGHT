class_name FoldlightRogueEnemyDefinition
extends FoldlightRogueContentDefinition

enum EnemyRole { FODDER, SHOOTER, CHARGER, TURRET, BUFFER, CONTROLLER, ELITE, BOSS }

@export var role: EnemyRole = EnemyRole.FODDER
@export_range(1, 16, 1) var threat_cost: int = 1
@export_range(1, 3, 1) var minimum_region: int = 1
@export_range(1, 8, 1) var max_simultaneous: int = 4
@export_range(1.0, 1000.0, 1.0) var base_health: float = 4.0
@export_range(0.0, 600.0, 1.0) var move_speed: float = 120.0
@export_range(0.1, 10.0, 0.05) var attack_interval: float = 1.5
@export var stationary: bool = false
@export var quota_group: StringName = &"ordinary"
@export_multiline var mechanic_rule: String = ""
@export_multiline var counterplay: String = ""


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if threat_cost <= 0 or base_health <= 0.0 or attack_interval <= 0.0:
		errors.append("enemy %s has invalid combat values" % content_id)
	if role == EnemyRole.TURRET and not stationary:
		errors.append("turret %s must be stationary" % content_id)
	if role in [EnemyRole.TURRET, EnemyRole.BUFFER, EnemyRole.CONTROLLER]:
		if mechanic_rule.strip_edges().is_empty() or counterplay.strip_edges().is_empty():
			errors.append("mechanic enemy %s needs a one-rule introduction and counterplay" % content_id)
	return errors
