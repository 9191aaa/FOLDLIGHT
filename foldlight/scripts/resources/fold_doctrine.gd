class_name FoldDoctrine
extends Resource

enum Family { CREASE, RETURN, VESSEL }

@export var doctrine_id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var family: Family = Family.CREASE
@export_range(1, 3, 1) var rarity: int = 1
@export_range(1, 5, 1) var max_stacks: int = 1
@export var tags: Array[StringName] = []


func to_snapshot(current_stacks: int = 0) -> Dictionary:
	return {
		"id": doctrine_id,
		"title": title,
		"description": description,
		"family": int(family),
		"rarity": rarity,
		"max_stacks": max_stacks,
		"stacks": current_stacks,
	}
