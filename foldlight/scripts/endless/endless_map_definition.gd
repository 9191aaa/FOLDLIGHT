class_name FoldlightEndlessMapDefinition
extends Resource

@export_group("Identity")
@export var map_id: StringName = &"folded_delta"
@export var title: String = "折叠三角洲"
@export var authored_version: StringName = &"handcrafted_1_0"
@export var region_style: StringName = &"paper_reef"

@export_group("World")
@export var bounds := Rect2(Vector2.ZERO, Vector2(6144.0, 4096.0))
@export var player_spawn := Vector2(3072.0, 3008.0)

@export_group("Submerged Landmark Art")
@export var landmark_kind: StringName = &"reef_steps"
@export var landmark_center := Vector2(3072.0, 2650.0)
@export var landmark_size := Vector2(1120.0, 760.0)

@export_group("Districts")
@export var district_names := PackedStringArray()
@export var district_rects: Array[Rect2] = []
@export var district_colors := PackedColorArray()
@export var district_styles: Array[StringName] = []

@export_group("Timed Sea Closures")
@export var closure_zone_ids: Array[StringName] = []
@export var closure_zone_names := PackedStringArray()
@export var closure_zone_rects: Array[Rect2] = []
@export var safe_corridors: Array[Rect2] = []
@export var refuge_points := PackedVector2Array()

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
	if landmark_kind not in [&"reef_steps", &"archive_tower", &"broken_sun"]:
		errors.append("endless landmark must use an authored paper silhouette")
	if landmark_size.x < 240.0 or landmark_size.y < 240.0 or not bounds.encloses(Rect2(landmark_center - landmark_size * 0.5, landmark_size)):
		errors.append("submerged landmark art must fit inside map bounds")
	if closure_zone_ids.size() < 4 or closure_zone_names.size() != closure_zone_ids.size() or closure_zone_rects.size() != closure_zone_ids.size():
		errors.append("endless map needs at least four named closure zones")
	if safe_corridors.is_empty() or refuge_points.size() < 3:
		errors.append("endless map needs permanent corridors and at least three refuges")
	var seen_ids: Array[StringName] = []
	for index in closure_zone_ids.size():
		if closure_zone_ids[index] == &"" or closure_zone_ids[index] in seen_ids:
			errors.append("closure zone ids must be unique and nonempty")
		seen_ids.append(closure_zone_ids[index])
	for index in closure_zone_rects.size():
		var rect := closure_zone_rects[index]
		if not bounds.encloses(rect) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			errors.append("closure zone rectangles must be inside the battlefield")
		for previous in index:
			if rect.intersects(closure_zone_rects[previous]):
				errors.append("closure zone rectangles must not overlap")
	for corridor in safe_corridors:
		if not bounds.encloses(corridor) or minf(corridor.size.x, corridor.size.y) < 200.0:
			errors.append("permanent safe corridors must be inside bounds and traversable")
	for refuge in refuge_points:
		if not is_permanent_safe(refuge, 34.0):
			errors.append("every refuge must lie inside a permanent safe corridor")
	if not is_permanent_safe(player_spawn, 34.0):
		errors.append("the starting harbor must be permanently safe")
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
		"closure_zone_count": closure_zone_ids.size(),
		"permanent_safe_corridors": safe_corridors.duplicate(),
		"refuge_points": refuge_points,
		"landmark_kind": landmark_kind,
		"landmark_center": landmark_center,
		"landmark_size": landmark_size,
		"landmark_has_collision": false,
	}


func is_permanent_safe(point: Vector2, clearance: float = 0.0) -> bool:
	for corridor in safe_corridors:
		var inner := corridor.grow(-maxf(clearance, 0.0))
		if inner.size.x > 0.0 and inner.size.y > 0.0 and inner.has_point(point):
			return true
	return false


## Shared by task placement, environmental damage, navigation and world paint.
## Safe corridors always win, even if a future authored zone overlaps them.
static func is_point_reserved_in_snapshot(point: Vector2, snapshot: Dictionary, clearance: float = 0.0, closed_only: bool = false) -> bool:
	for corridor: Rect2 in snapshot.get("safe_corridors", []):
		var inner := corridor.grow(-maxf(clearance, 0.0))
		if inner.size.x > 0.0 and inner.size.y > 0.0 and inner.has_point(point):
			return false
	for zone: Dictionary in snapshot.get("zones", []):
		var state := StringName(zone.get("state", &"open"))
		if state != &"closed" and (closed_only or state != &"warning"):
			continue
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.grow(maxf(clearance, 0.0)).has_point(point):
			return true
	return false


## Exact axis-aligned mask subtraction; the world tint never covers safe water.
static func zone_fragments(rect: Rect2, corridors: Array) -> Array[Rect2]:
	var fragments: Array[Rect2] = [rect]
	for corridor: Rect2 in corridors:
		var next: Array[Rect2] = []
		for fragment in fragments:
			var overlap := fragment.intersection(corridor)
			if not overlap.has_area():
				next.append(fragment)
				continue
			if overlap.position.y > fragment.position.y:
				next.append(Rect2(fragment.position, Vector2(fragment.size.x, overlap.position.y - fragment.position.y)))
			if overlap.end.y < fragment.end.y:
				next.append(Rect2(Vector2(fragment.position.x, overlap.end.y), Vector2(fragment.size.x, fragment.end.y - overlap.end.y)))
			if overlap.position.x > fragment.position.x:
				next.append(Rect2(Vector2(fragment.position.x, overlap.position.y), Vector2(overlap.position.x - fragment.position.x, overlap.size.y)))
			if overlap.end.x < fragment.end.x:
				next.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(fragment.end.x - overlap.end.x, overlap.size.y)))
		fragments = next
	return fragments
