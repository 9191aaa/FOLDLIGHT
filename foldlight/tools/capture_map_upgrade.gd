extends SceneTree
## Actual gameplay scenes; invulnerability only prevents unattended capture death.
const OUTPUT := "res://captures/map_upgrade"
const Seascape = preload("res://scripts/visuals/paper_seascape.gd")
var _errors: int = 0
var _records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	for index in 3:
		session.start_new_run()
		await process_frame
		session.run_controller.run_state.current_region = index
		var regions: Array = session.run_controller.run_state.route.get("regions", [])
		var region: Dictionary = regions[index]
		var node := {"id": "capture_region_%d" % (index + 1), "category": "combat", "depth": 4, "risk": index + 3, "exits": []}
		session._on_room_requested(node, region)
		session.world.camera.zoom = Vector2.ONE
		session.world.camera.force_follow()
		game.player.set_debug_invincible(true)
		await _wait_live(session, 3.2)
		await _save("region_%d_default" % (index + 1), session.world)
		session.world.combat_runtime.set_active(false)
		var camera := session.world.camera
		camera.target = null
		camera.position = session.world.room_runtime.room_bounds.get_center()
		camera.zoom = Vector2.ONE * 0.56
		camera.set_process(false)
		camera.force_update_scroll()
		await _save("region_%d_overview" % (index + 1), session.world)
		camera.set_process(true)
	# Real boss AI and warning sequence, no fabricated projectiles.
	session.start_new_run()
	await process_frame
	var boss_region: Dictionary = session.run_controller.run_state.route.get("regions", [])[0]
	session._on_room_requested({"id": "capture_boss", "category": "boss", "depth": 7, "risk": 4, "boss_id": &"reef_crown_battery", "exits": []}, boss_region)
	session.world.camera.zoom = Vector2.ONE
	session.world.camera.force_follow()
	game.player.set_debug_invincible(true)
	await _wait_live(session, 3.0)
	await _save("boss_default", session.world)
	game.queue_free()
	await process_frame
	var endless := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(endless)
	await process_frame
	await process_frame
	endless.player.set_debug_invincible(true)
	await create_timer(3.2).timeout
	await _save("endless_default", endless.world)
	# Inspect the actual objective site through the unchanged gameplay camera.
	endless.player.global_position = Vector2(endless.controller.objectives.current.get("target_position", endless.player.global_position))
	endless.player.reset_physics_interpolation()
	endless.camera.force_follow()
	endless.controller.force_next_wave()
	await create_timer(4.0).timeout
	await _check_mesh_retention(endless.world.room_runtime.backdrop, endless.controller.map_runtime.get_node("CachedPaperGround"))
	await _save("endless_objective_default", endless.world)
	var map := endless.controller.map_runtime
	var static_before := int(map.get_map_contract().get("static_draw_count", -1))
	await create_timer(0.6).timeout
	var static_after := int(map.get_map_contract().get("static_draw_count", -2))
	_check(static_before == static_after and static_before > 0, "Endless objective ticks retain cached ground")
	var backdrop := endless.world.room_runtime.backdrop
	var motion := backdrop.get_node("LocalSeaMotion")
	var motion_before := float(motion.get("phase"))
	await create_timer(0.2).timeout
	_check(float(motion.get("phase")) > motion_before, "Live sea motion advances on the gameplay scene")
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.settings["screen_shake"] = 0.0
	motion_before = float(motion.get("phase"))
	await create_timer(0.2).timeout
	_check(is_equal_approx(float(motion.get("phase")), motion_before), "Zero motion freezes the ambient layer")
	profile.settings["screen_shake"] = 1.0
	endless.world.combat_runtime.set_active(false)
	motion_before = float(motion.get("phase"))
	await create_timer(0.2).timeout
	_check(is_equal_approx(float(motion.get("phase")), motion_before), "Suspended combat freezes the ambient layer")
	var motion_id := motion.get_instance_id()
	backdrop.configure(backdrop.room_id, backdrop.world_size, backdrop.accent, backdrop.style_id)
	_check(backdrop.get_node("LocalSeaMotion").get_instance_id() == motion_id and is_zero_approx(backdrop._ambient_time), "Room reconfiguration resets and reuses one ambient canvas")
	endless.camera.target = null
	endless.camera.position = endless.controller.map_definition.bounds.get_center()
	endless.camera.zoom = Vector2.ONE * 0.26
	endless.camera.set_process(false)
	endless.camera.force_update_scroll()
	await _save("endless_overview", endless.world)
	endless.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	var report := FileAccess.open(OUTPUT.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures": _records, "errors": _errors}, "\t"))
	report.close()
	print("MAP_UPGRADE_CAPTURE: %s" % ("PASS" if _errors == 0 else "FAIL"))
	quit(0 if _errors == 0 else 1)

func _wait_live(session: FoldlightRogueSessionController, seconds: float) -> void:
	for tick in int(seconds * 10.0):
		while session._mechanic_intro_active:
			session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
		await create_timer(0.1).timeout

func _save(filename: String, world: FoldlightRogueWorld) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var before := int(world.room_runtime.backdrop.get_visual_contract().get("static_draw_count", -1))
	await create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename + ".png")))
	_check(error == OK, "Save " + filename)
	_check(before == int(world.room_runtime.backdrop.get_visual_contract().get("static_draw_count", -2)), "Ambient ticks retain static ground: " + filename)
	_records.append({"name": filename, "debug_invincible": true, "enemies": world.combat_runtime.enemies.size(), "projectiles": world.combat_runtime.projectiles.size(), "camera_zoom": world.camera.zoom, "static_draw_count": before})
	print("CAPTURED " + filename)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_errors += 1
		push_error(description)

func _check_mesh_retention(backdrop: CanvasItem, ground: CanvasItem) -> void:
	var live_meshes: Array[WeakRef] = []
	for canvas in [backdrop, ground]:
		var retained: Array = canvas.get_meta(Seascape.CANVAS_MESH_REFS, [])
		_check(retained.size() >= 2, "Static canvas retains its own ground and foundation mesh resources")
		for mesh: ArrayMesh in retained:
			live_meshes.append(weakref(mesh))
	for index in Seascape.MAX_CACHED_MESHES + 1:
		Seascape._remember_mesh("capture_eviction_%d" % index, ArrayMesh.new())
	await process_frame
	_check(Seascape._mesh_cache.size() <= Seascape.MAX_CACHED_MESHES, "Shared mesh cache stays bounded")
	_check(live_meshes.all(func(reference: WeakRef) -> bool: return reference.get_ref() != null), "Displayed ground resources survive cache eviction without a redraw")
