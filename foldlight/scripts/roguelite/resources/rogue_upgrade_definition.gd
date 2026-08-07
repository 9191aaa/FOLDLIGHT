class_name FoldlightRogueUpgradeDefinition
extends FoldlightRogueContentDefinition

enum UpgradeFamily { WEAPON, FOLD, DASH, SURVIVAL }
enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY, CURSED }

@export var family: UpgradeFamily = UpgradeFamily.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export_range(1, 8, 1) var max_stacks: int = 1
@export var prerequisites: Array[StringName] = []
@export var exclusions: Array[StringName] = []
@export var stat_modifiers: Dictionary = {}


func validation_errors() -> Array[String]:
	var errors: Array[String] = super.validation_errors()
	if max_stacks <= 0:
		errors.append("upgrade %s needs at least one stack" % content_id)
	if stat_modifiers.is_empty():
		errors.append("upgrade %s needs at least one explicit modifier" % content_id)
	for prerequisite in prerequisites:
		if exclusions.has(prerequisite):
			errors.append("upgrade %s both requires and excludes %s" % [content_id, prerequisite])
	return errors
