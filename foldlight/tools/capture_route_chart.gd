extends SceneTree
## Render the real chart at a normal 1280 × 720 web display size, while keeping
## the game's authored 1920 × 1080 coordinates. Uses seeded catalogue routes.

const OUTPUT := "res://build/route-chart"
var _ui: FoldlightRoguePresentation


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_ui = load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate()
	root.add_child(_ui)
	await process_frame
	var generator := FoldlightRogueRouteGenerator.new()
	var route := generator.generate_route(52015, FoldlightRogueContentCatalog.REGIONS)
	for state in [
		{"file": "early-1280", "region": 0, "depth": 0, "rooms": 1, "motion": 1.0},
		{"file": "middle-1280", "region": 1, "depth": 3, "rooms": 11, "motion": 1.0},
		{"file": "boss-1280", "region": 2, "depth": 6, "rooms": 21, "motion": 1.0},
		{"file": "still-1280", "region": 0, "depth": 2, "rooms": 3, "motion": 0.0},
	]:
		var region: Dictionary = (route["regions"] as Array)[int(state["region"])].duplicate(true)
		var cleared: Array[StringName] = []
		var current: Dictionary = {}
		var visited_depths: Array[int] = []
		for node: Dictionary in region["nodes"]:
			var depth := int(node["depth"])
			if depth <= int(state["depth"]) and not visited_depths.has(depth):
				visited_depths.append(depth)
				cleared.append(StringName(node["id"]))
				if depth == int(state["depth"]): current = node
		region["cleared_node_ids"] = cleared
		region["context"] = {"health": 3, "max_health": 6, "glimmer": 27 + int(state["region"]) * 22, "room_count": int(state["rooms"]), "region_count": 3, "active_item_id": "" if int(state["rooms"]) == 1 else "paper_burst", "motion_scale": state["motion"]}
		var exits: Array[String] = []
		for destination: Variant in current.get("exits", []): exits.append(String(destination))
		_ui.show_route(region, StringName(current["id"]), exits)
		await create_timer(1.35).timeout
		await _save(str(state["file"]))
		if int(state["region"]) == 1:
			_ui._route_atlas.recenter()
			await process_frame
			await _save("overview-1280")
			_ui._on_atlas_node_selected(StringName(region["boss_node_id"]))
			await create_timer(0.45).timeout
			await _save("future-preview-1280")
	_ui.queue_free()
	generator.free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	quit()


func _save(name_value: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var captured := root.get_texture().get_image()
	var error := captured.save_png("%s/%s.png" % [OUTPUT, name_value])
	print("CHART_CAPTURE %s %s error=%s" % [name_value, captured.get_size(), error])
