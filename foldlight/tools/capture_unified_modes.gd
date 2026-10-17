extends SceneTree

## Actual scene/UI captures. Invulnerability only keeps unattended combat alive;
## reward and result screens are entered through their live controller paths.
const OUTPUT := "res://captures/unified_modes"
var errors: int = 0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.profile["roguelite"]["prologue_complete"] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _settle()
	var game := current_scene as FoldlightGame
	var session := game.rogue_session
	session.persist_profile = false
	await _save("01_title")
	session.presentation._title_primary.pressed.emit()
	await _settle()
	game.player.set_debug_invincible(true)
	for step in 18:
		while session._mechanic_intro_active:
			session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
		await create_timer(0.10).timeout
	await _save("02_voyage_hud")
	session._pause_game()
	await _save("03_voyage_pause")
	session._on_settings_requested()
	await _save("04_voyage_settings")
	session._on_settings_back_requested(&"pause")
	session._resume_game()
	var guard: int = 0
	while session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and guard < 100:
		guard += 1
		while session._mechanic_intro_active:
			session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
		session.world.room_runtime.advance_encounter(2.0)
		for enemy in session.world.combat_runtime.enemies.duplicate():
			if is_instance_valid(enemy):
				enemy.take_damage(100000.0)
		await process_frame
	if session.presentation.screen_kind == &"reward":
		await _save("05_voyage_reward")
	else:
		errors += 1
		push_error("The real voyage encounter did not reach its reward")
	game.return_to_main_menu()
	await _settle()
	session.presentation.endless_requested.emit()
	await _settle()
	var slice := current_scene as FoldlightEndlessSliceRuntime
	slice.player.set_debug_invincible(true)
	await create_timer(1.8).timeout
	await _save("06_endless_hud")
	slice._pause_game()
	await _save("07_endless_pause")
	slice._on_settings_requested()
	await _save("08_endless_settings")
	slice._on_settings_back_requested(&"pause")
	slice._resume_game()
	slice.controller._on_objective_completed({"completion_count": 1, "title": "潮汐驻守"})
	await _save("09_endless_reward")
	var deadline: int = Time.get_ticks_msec() + 3000
	while slice.presentation._reward_buttons[0].disabled and Time.get_ticks_msec() < deadline:
		await process_frame
	slice.presentation._reward_buttons[0].pressed.emit()
	await create_timer(0.30).timeout
	slice.player.set_debug_invincible(false)
	slice.player.health = 1
	slice.player.invulnerability = 0.0
	slice.combat_runtime._try_hit_player(Vector2.LEFT)
	await _save("10_endless_result")
	slice._return_to_title()
	await _settle()
	print("FOLDLIGHT_UNIFIED_MODES_CAPTURE: " + ("PASS" if errors == 0 else "FAIL"))
	quit(0 if errors == 0 else 1)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _save(name: String) -> void:
	await create_timer(0.60).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var destination := ProjectSettings.globalize_path(OUTPUT).path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(destination)
	if error != OK:
		errors += 1
		push_error("Capture failed: " + destination)
	else:
		print("CAPTURED " + destination)
