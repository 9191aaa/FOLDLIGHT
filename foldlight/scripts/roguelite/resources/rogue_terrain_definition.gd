class_name FoldlightRogueTerrainDefinition
extends FoldlightRogueContentDefinition

enum TerrainKind { PAPER_WALL, REFRACTION_PILLAR, INK_POOL, CURRENT_LANE, SUN_PATCH, THORN_PAPER }

@export var kind: TerrainKind = TerrainKind.PAPER_WALL
@export var size: Vector2 = Vector2(240.0, 96.0)
@export_range(0.0, 4.0, 0.05) var effect_strength: float = 1.0
@export var direction: Vector2 = Vector2.RIGHT
@export var blocks_actors: bool = true
@export var blocks_projectiles: bool = true


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if size.x <= 0.0 or size.y <= 0.0:
		errors.append("terrain %s needs positive dimensions" % content_id)
	if kind == TerrainKind.CURRENT_LANE and direction.is_zero_approx():
		errors.append("current lane %s needs a direction" % content_id)
	return errors
