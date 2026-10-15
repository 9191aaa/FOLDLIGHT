extends SceneTree
## Real renderer, scenes, terrain and navigation. Clock/position fixtures are
## solely for visual QA; this capture does not measure survival balance.
const OUTPUT := "res://captures/endless_navigation"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var game := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for seed in 3:
		game.start_slice(seed)
		game.controller.advance_simulation(72.0, game.player.global_position)
		game.combat_runtime.set_active(false)
		for zone: Dictionary in game.controller.zones.get_snapshot().zones:
			if zone.state != &"closed": continue
			var point := (zone.rect as Rect2).get_center()
			if game.controller.map_runtime.is_point_blocked(point, 20): point += Vector2(180, 180)
			game.player.global_position = point
			break
		game.camera.configure(game.player, game.controller.map_definition.bounds)
		game._refresh_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("map_%d_closed.png" % seed))
		game._navigation.call("_toggle_map")
		game._refresh_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join("map_%d_expanded.png" % seed))
		game._navigation.call("_toggle_map")
	game.queue_free()
	await process_frame
	print("ENDLESS_NAVIGATION_CAPTURE: PASS")
	quit()
