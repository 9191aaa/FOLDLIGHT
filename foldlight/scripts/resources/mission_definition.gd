class_name FoldMissionDefinition
extends Resource

const TIDE_COUNT: int = 6

@export var mission_id: StringName = &""
@export_range(1, 99, 1) var revision: int = 1
@export_range(1, 3, 1) var chapter: int = 1
@export_range(1, 4, 1) var mission_number: int = 1
@export var chapter_title: String = ""
@export var title: String = ""
@export var subtitle: String = ""
@export var location: String = ""
@export_multiline var synopsis: String = ""
@export_range(60, 1800, 1) var expected_seconds: int = 420
@export_range(30.0, 180.0, 1.0) var tide_duration: float = 55.0
@export_range(60, 300, 1) var boss_budget_seconds: int = 90
@export_range(0.75, 2.5, 0.01) var difficulty: float = 1.0
@export var scene_theme: StringName = &"still_water"
@export var accent: Color = Color(0.30, 0.88, 0.86)
@export var tide_names: Array[String] = []
@export var tide_scene_tags: Array[String] = []
@export var tide_objective_labels: Array[String] = []
@export var objective_ids: Array[StringName] = []
@export var objective_targets: Array[int] = []
@export var modifier_ids: Array[StringName] = []
@export var enemy_rosters: Array[String] = []
@export var ritual_event_pairs: Array[String] = []
@export var boss_id: StringName = &"ink_moon"
@export var boss_title: String = ""
@export var boss_subtitle: String = ""
@export var opening_speaker: String = "引灯人 · 岑"
@export var opening_title: String = ""
@export_multiline var opening_body: String = ""
@export var ending_speaker: String = "引灯人 · 岑"
@export var ending_title: String = ""
@export_multiline var ending_body: String = ""
@export_range(1, 40, 1) var base_glimmer_reward: int = 6
@export var chapter_finale: bool = false
@export var campaign_finale: bool = false


func configured_seconds() -> int:
	return int(round(tide_duration * float(TIDE_COUNT))) + boss_budget_seconds


func tide_value(values: Array, tide_index: int, fallback: Variant) -> Variant:
	if tide_index < 0 or tide_index >= values.size():
		return fallback
	return values[tide_index]


func to_map_snapshot(locked: bool, completed_record: Dictionary = {}) -> Dictionary:
	return {
		"id": mission_id,
		"chapter": chapter,
		"mission_number": mission_number,
		"chapter_title": chapter_title,
		"title": title,
		"subtitle": subtitle,
		"location": location,
		"synopsis": synopsis,
		"expected_seconds": expected_seconds,
		"accent": accent,
		"locked": locked,
		"completed": not completed_record.is_empty(),
		"best_rank": str(completed_record.get("rank", "—")),
		"best_time": float(completed_record.get("best_time", 0.0)),
		"boss_title": boss_title,
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if mission_id.is_empty():
		errors.append("mission_id is empty")
	if title.is_empty():
		errors.append("title is empty")
	if expected_seconds != configured_seconds():
		errors.append("expected_seconds %d != configured %d" % [expected_seconds, configured_seconds()])
	var authored_arrays: Array = [
		tide_names, tide_scene_tags, tide_objective_labels, objective_ids,
		objective_targets, modifier_ids, enemy_rosters, ritual_event_pairs,
	]
	for values in authored_arrays:
		if values.size() != TIDE_COUNT:
			errors.append("authored tide array has %d entries, expected %d" % [values.size(), TIDE_COUNT])
	if boss_id.is_empty() or boss_title.is_empty():
		errors.append("boss identity is incomplete")
	return errors
