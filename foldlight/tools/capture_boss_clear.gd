extends SceneTree

## Real scene/actor/confirmation capture; isolated user data is supplied by the runner.
const OUTPUT := "res://captures/boss_clear"
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session._activate_gameplay()
	session.mode = FoldlightRogueSessionController.SessionMode.RUN
	var controller := session.run_controller
	controller.run_state.begin_run(10152026, controller.route_generator.generate_route(10152026, FoldlightRogueContentCatalog.REGIONS))
	var region := controller.get_current_region_snapshot()
	var boss_node: Dictionary = {}
	for node: Dictionary in region.get("nodes", []):
		if StringName(node.get("category", &"")) == &"boss":
			boss_node = node
	controller.run_state.current_node_id = StringName(boss_node.get("id", &""))
	controller.phase = FoldlightRogueRunController.Phase.ENTERING_ROOM
	session._on_room_requested(boss_node, region)
	game.player.set_debug_invincible(true)
	var boss: FoldlightRogueBossActor
	for _frame in 240:
		while session._mechanic_intro_active:
			session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
		await physics_frame
		await process_frame
		for actor in session.world.combat_runtime.enemies:
			if actor is FoldlightRogueBossActor:
				boss = actor
		if is_instance_valid(boss):
			break
	if not is_instance_valid(boss):
		push_error("Boss capture did not enter the authored boss encounter")
		quit(1)
		return
	boss.take_damage(999999.0, &"weapon")
	await create_timer(0.2).timeout
	await _save("clear_020")
	await create_timer(1.0).timeout
	await _save("clear_120")
	await create_timer(1.3).timeout
	await _save("clear_ready")
	if controller.phase != FoldlightRogueRunController.Phase.BOSS_CLEAR or controller.run_state.current_region != 0:
		_errors += 1
		push_error("Boss clear advanced before an explicit confirmation")
	for _frame in 180:
		if session._boss_clear_banner.can_continue():
			break
		await process_frame
	var confirm := InputEventAction.new()
	confirm.action = &"ui_accept"
	confirm.pressed = true
	Input.parse_input_event(confirm)
	await process_frame
	Input.action_release(&"ui_accept")
	await create_timer(0.35).timeout
	await _save("continued_region")
	if controller.run_state.current_region != 1:
		_errors += 1
		push_error("Explicit boss confirmation did not enter the next sea")
	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("BOSS_CLEAR_CAPTURE: %s" % ("PASS" if _errors == 0 else "FAIL"))
	quit(0 if _errors == 0 else 1)


func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename + ".png")))
	if error != OK:
		_errors += 1
		push_error("Could not save boss capture: %s" % filename)
