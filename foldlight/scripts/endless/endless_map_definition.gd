class_name FoldlightEndlessMapDefinition
extends Resource

@export_group("Identity")
@export var map_id: StringName = &"folded_delta"
@export var title: String = "折叠三角洲"
@export var authored_version: StringName = &"handcrafted_1_0"

@export_group("World")
@export var bounds := Rect2(Vector2.ZERO, Vector2(6144.0, 4096.0))
@export var player_spawn := Vector2(3072.0, 3008.0)

@export_group("Districts")
@export var district_names := PackedStringArray()
@export var district_rects: Array[Rect2] = []
@export var district_colors := PackedColorArray()

@export_group("Authored Cover")
@export var walls: Array[Rect2] = []

@export_group("Objective Sites")
@export var capture_points := PackedVector2Array()
@export var flag_positions := PackedVector2Array()
@export var captain_spawn_positions := PackedVector2Array()

@export_group("Combat Spawns")
@export var shooter_spawn_positions := PackedVector2Array()
@export var melee_spawn_positions := PackedVector2Array()
@export var rally_positions := PackedVector2Array()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if map_id == &"" or title.strip_edges().is_empty():
		errors.append("endless map needs an id and title")
	if bounds.size.x < 5000.0 or bounds.size.y < 3200.0:
		errors.append("endless map must remain a genuinely large authored battlefield")
	if district_names.size() < 5 or district_rects.size() != district_names.size():
		errors.append("endless map needs at least five named districts with matching rectangles")
	if district_colors.size() != district_names.size():
		errors.append("every district needs a readable palette color")
	if walls.size() < 20:
		errors.append("endless map needs at least twenty authored cover groups")
	if capture_points.size() < 3:
		errors.append("endless map needs at least three capture sites")
	if flag_positions.size() < 3:
		errors.append("endless map needs at least three flag sites")
	if captain_spawn_positions.size() < 4:
		errors.append("endless map needs at least four captain sites")
	if shooter_spawn_positions.size() < 8:
		errors.append("endless map needs enough central shooter positions")
	if melee_spawn_positions.size() < 12:
		errors.append("endless map needs enough perimeter pressure positions")
	if not bounds.has_point(player_spawn):
		errors.append("player spawn must be inside map bounds")
	return errors


func get_contract() -> Dictionary:
	return {
		"map_id": map_id,
		"title": title,
		"authored_version": authored_version,
		"runtime_random_terrain": false,
		"bounds": bounds,
		"player_spawn": player_spawn,
		"district_count": district_names.size(),
		"wall_count": walls.size(),
		"capture_site_count": capture_points.size(),
		"flag_site_count": flag_positions.size(),
		"captain_site_count": captain_spawn_positions.size(),
		"shooter_spawn_count": shooter_spawn_positions.size(),
		"melee_spawn_count": melee_spawn_positions.size(),
	}
