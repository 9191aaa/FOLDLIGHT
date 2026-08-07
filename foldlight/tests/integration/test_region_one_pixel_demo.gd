extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/demos/region_one_pixel_demo.tscn") as PackedScene
	_check(scene != null, "pixel vertical-slice demo scene loads")
	if scene == null:
		_finish()
		return

	var demo := scene.instantiate()
	_check(demo != null, "demo instantiates with its public controller type")
	if demo == null:
		_finish()
		return
	root.add_child(demo)
	await process_frame

	var contract: Dictionary = demo.call("get_visual_contract")
	_check(contract.get("base_resolution") == Vector2i(640, 360), "demo preserves the 640x360 pixel-art canvas")
	_check(contract.get("texture_filter") == &"nearest", "demo declares nearest-neighbour presentation")
	_check(bool(contract.get("isolated_demo", false)), "demo is isolated from the production world")
	_check(not bool(contract.get("changes_display_mode", true)), "demo never requests a display-mode change")
	_check((contract.get("states", []) as Array).has(&"standard_room"), "demo exposes the region-one standard room")
	_check((contract.get("states", []) as Array).has(&"boss_room"), "demo exposes the region-one boss room")
	_check(contract.get("art_direction") == &"high_density_handpainted_topdown_rpg_pixel", "demo declares the corrected high-density hand-painted RPG pixel direction")
	_check(contract.get("background_mode") == &"modular_texture_atlas", "room art is assembled from modular texture atlases")
	_check(bool(contract.get("terrain_reproducible", false)), "the demo declares terrain reproduction as a first-class requirement")
	_check(bool(contract.get("shared_terrain_assets", false)), "standard and boss rooms share one terrain asset set")
	_check(not bool(contract.get("legacy_full_frame_backgrounds", true)), "legacy full-frame backgrounds are disabled")
	_check(contract.get("atlas_grid") == Vector2i(3, 2), "terrain and actor atlases use the agreed 3x2 grid")
	_check(contract.get("water_fill") == &"shared_cover_texture", "water keeps its native proportions without visible repeat seams")
	_check((contract.get("layers", []) as Array) == [&"shared_water_base", &"terrain_atlas", &"actor_atlas", &"minimal_hud"], "render stack is shared water, modular terrain, actors, then minimal HUD")
	var modular_assets := contract.get("assets", {}) as Dictionary
	_check(modular_assets.get("water") == "res://assets/demos/pixel/paper_reef_water_tile.png", "water uses the reusable tile texture")
	_check(modular_assets.get("terrain") == "res://assets/demos/pixel/paper_reef_terrain_atlas.png", "both rooms use the shared terrain atlas")
	_check(modular_assets.get("actors") == "res://assets/demos/pixel/paper_reef_actor_atlas.png", "actors and boss use the shared actor atlas")
	var terrain_layouts := contract.get("terrain_layouts", {}) as Dictionary
	var standard_layout := terrain_layouts.get(&"standard_room", []) as Array
	var boss_layout := terrain_layouts.get(&"boss_room", []) as Array
	_check(standard_layout.size() == 6 and boss_layout.size() == 6, "both rooms are composed from all six terrain atlas modules")
	_check(standard_layout != boss_layout, "standard and boss rooms reproduce distinct layouts from the same terrain modules")
	var controls := contract.get("controls", {}) as Dictionary
	_check((controls.get("standard_room", []) as Array).has(&"move_left"), "one-handed A / left action explicitly selects the standard room")
	_check((controls.get("boss_room", []) as Array).has(&"move_right"), "one-handed D / right action explicitly selects the boss room")
	_check((controls.get("toggle_room", []) as Array).has(&"ui_accept"), "keyboard and gamepad confirm can toggle the room preview")
	_check((controls.get("exit_demo", []) as Array).has(&"ui_cancel"), "Escape and gamepad Back/B expose an exit action")
	_check(bool(contract.get("exit_only_when_standalone", false)), "embedded previews cannot close their host scene tree")
	var hd_layout: Dictionary = demo.call("get_integer_layout_for_size", Vector2(1280, 720))
	_check(hd_layout.get("scale") == 2 and hd_layout.get("origin") == Vector2.ZERO, "1280x720 presents the pixel canvas at an exact 2x scale")
	var ultrawide_layout: Dictionary = demo.call("get_integer_layout_for_size", Vector2(2560, 1080))
	_check(ultrawide_layout.get("scale") == 3 and ultrawide_layout.get("origin") == Vector2(320, 0), "ultrawide presentation is integer-scaled and centered without stretching")
	var atlas_cell := demo.call("get_atlas_cell_region_for_size", Vector2(1200, 800), 4) as Rect2
	_check(atlas_cell == Rect2(400, 400, 400, 400), "atlas cell four resolves to the center cell of the second row")
	var invalid_cell := demo.call("get_atlas_cell_region_for_size", Vector2(1200, 800), 6) as Rect2
	_check(not invalid_cell.has_area(), "atlas lookup rejects cells outside the 3x2 grid")

	var state_changes: Array[StringName] = []
	demo.room_state_changed.connect(func(next_state: StringName) -> void: state_changes.append(next_state))
	demo.set_room_state(&"boss_room")
	_check(demo.get_room_state() == &"boss_room", "public API switches to the boss-room composition")
	_check(state_changes == [&"boss_room"], "room-state switch emits exactly one integration signal")
	demo.set_room_state(&"invalid")
	_check(demo.get_room_state() == &"boss_room", "public API rejects unsupported room states")

	var select_standard := InputEventAction.new()
	select_standard.action = &"move_left"
	select_standard.pressed = true
	demo._unhandled_input(select_standard)
	_check(demo.get_room_state() == &"standard_room", "A / left input selects rather than blindly toggles the standard room")
	var select_boss := InputEventAction.new()
	select_boss.action = &"move_right"
	select_boss.pressed = true
	demo._unhandled_input(select_boss)
	_check(demo.get_room_state() == &"boss_room", "D / right input selects the boss room")
	var toggle_room := InputEventAction.new()
	toggle_room.action = &"ui_accept"
	toggle_room.pressed = true
	demo._unhandled_input(toggle_room)
	_check(demo.get_room_state() == &"standard_room", "confirm input provides an intuitive room toggle")
	_check(not demo.auto_cycle, "manual input disables automatic cycling")

	var exits: Array[bool] = []
	demo.exit_requested.connect(func() -> void: exits.append(true))
	var request_exit := InputEventAction.new()
	request_exit.action = &"ui_cancel"
	request_exit.pressed = true
	demo._unhandled_input(request_exit)
	_check(exits.size() == 1, "Escape / gamepad cancel requests a clean standalone-demo exit")

	demo.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_REGION_ONE_PIXEL_DEMO: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REGION_ONE_PIXEL_DEMO: FAIL - %s" % ", ".join(_failures))
		quit(1)
