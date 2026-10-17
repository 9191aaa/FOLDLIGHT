extends SceneTree

const Landmark = preload("res://scripts/endless/endless_map_landmarks.gd")
const MAPS := [
	"res://resources/endless/maps/folded_delta.tres",
	"res://resources/endless/maps/inverted_canals.tres",
	"res://resources/endless/maps/solar_archipelago.tres",
]
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var component := Landmark.new()
	root.add_child(component)
	var geometry_hashes: Dictionary = {}
	var retained_meshes: Dictionary = {}
	var definitions: Array[FoldlightEndlessMapDefinition] = []
	var gameplay_before: Dictionary = {}
	for path in MAPS:
		var definition := load(path) as FoldlightEndlessMapDefinition
		definitions.append(definition)
		gameplay_before[definition.map_id] = _gameplay_geometry(definition)
		_check(definition.validation_errors().is_empty(), "%s preserves the valid authored battlefield" % definition.map_id)
		component.configure(definition)
		var snapshot: Dictionary = component.get_visual_contract()
		geometry_hashes[snapshot["geometry_hash"]] = true
		retained_meshes[definition.map_id] = snapshot["mesh_id"]
		_check(snapshot["region_style"] == definition.region_style and snapshot["motif"] == definition.landmark_kind, "%s uses its actual authored regional motif" % definition.map_id)
		_check(int(snapshot["vertex_count"]) > 150 and int(snapshot["vertex_count"]) < 12000 and int(snapshot["triangle_count"]) < 8000, "%s has a nonempty bounded static paper mesh" % definition.map_id)
		_check(definition.bounds.encloses(snapshot["world_bounds"]), "%s visual geometry remains inside the battlefield" % definition.map_id)
		_check(component.z_index < 0 and not component.is_processing() and not component.is_physics_processing(), "%s stays below live map warnings with no animation clock" % definition.map_id)
		_check(_has_no_physics(component), "%s adds no hidden collision or obstructing body" % definition.map_id)
		var mesh := component.get_node("RetainedSubmergedRelief") as MeshInstance2D
		var notifier := component.get_node("LandmarkVisibility") as VisibleOnScreenNotifier2D
		_check(mesh.get_child_count() == 0 and notifier.rect.has_area() and notifier.rect.encloses(Rect2((snapshot["world_bounds"] as Rect2).position - component.position, (snapshot["world_bounds"] as Rect2).size)), "%s visibility bounds contain the whole retained drawing" % definition.map_id)
		# Exercise the same signal callbacks that the renderer uses; actual GPU
		# visibility is separately inspected in the native screenshot fixture.
		notifier.screen_exited.emit()
		_check(not mesh.visible and notifier.visible, "%s hides only its mesh while retaining its visibility sensor" % definition.map_id)
		notifier.screen_entered.emit()
		_check(mesh.visible, "%s reappears without rebuilding its mesh" % definition.map_id)
	_check(geometry_hashes.size() == 3, "reef terraces, archive tower and broken solar sectors have different geometry")
	for cycle in 10:
		for definition in definitions:
			component.configure(definition)
			var snapshot: Dictionary = component.get_visual_contract()
			_check(snapshot["mesh_id"] == retained_meshes[definition.map_id], "%s cycle %d reuses its exact compiled mesh" % [definition.map_id, cycle])
	_check(component.get_child_count() == 2 and int(component.get_visual_contract()["cached_mesh_count"]) == 3 and int(component.get_visual_contract()["geometry_builds"]) == 3, "thirty map reconfigurations retain only three meshes and two nodes")
	for definition in definitions:
		_check(_gameplay_geometry(definition) == gameplay_before[definition.map_id], "%s landmarks never mutate walls, task sites, closures or spawn geometry" % definition.map_id)
	component.configure(null)
	_check(component.get_visual_contract().is_empty() and not component.visible and (component.get_node("RetainedSubmergedRelief") as MeshInstance2D).mesh == null, "resetting a map releases the visible mesh and cannot leave a stale landmark")
	component.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_LANDMARKS: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _gameplay_geometry(definition: FoldlightEndlessMapDefinition) -> Dictionary:
	return {"bounds": definition.bounds, "spawn": definition.player_spawn, "walls": definition.walls.duplicate(), "zones": definition.closure_zone_rects.duplicate(), "corridors": definition.safe_corridors.duplicate(), "capture": definition.capture_points.duplicate(), "flags": definition.flag_positions.duplicate(), "captains": definition.captain_spawn_positions.duplicate(), "shooters": definition.shooter_spawn_positions.duplicate(), "melee": definition.melee_spawn_positions.duplicate()}


func _has_no_physics(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is NavigationRegion2D:
		return false
	for child in node.get_children():
		if not _has_no_physics(child):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
	print(("[PASS] " if condition else "[FAIL] ") + label)
