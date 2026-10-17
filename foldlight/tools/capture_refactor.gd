extends SceneTree

var _output := "res://captures/refactor"
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	await _save("title")
	session.presentation.show_title({"prologue_complete": true, "active_run": {"room_count": 4}, "runs": 3, "best_region": 2})
	await _save("title_continue")
	session.presentation.show_settings(profile.settings, &"title")
	await _save("settings")
	session.start_new_run()
	game.player.set_debug_invincible(true)
	await create_timer(0.8).timeout
	if session.presentation.screen_kind == &"mechanic_intro":
		await _save("enemy_intro")
	while session._mechanic_intro_active:
		session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
	await _save("gameplay")
	session._pause_game()
	await _save("pause")
	var choices: Array[Dictionary] = []
	for content_id in [&"tiny_silhouette", &"double_step", &"large_burden"]:
		var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
		choices.append({"content_id": content_id, "title": definition.title, "description": definition.description, "rarity": definition.rarity, "accent": definition.accent, "next_level": 1, "maximum_level": definition.max_stacks})
	session.presentation.show_reward(choices, "纸礁浅海")
	await _save("reward")
	game.queue_free()
	await process_frame
	var endless := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(endless)
	await process_frame
	await process_frame
	endless.player.set_debug_invincible(true)
	await _save("endless")
	endless._pause_game()
	await _save("endless_pause")
	endless.queue_free()
	await process_frame
	quit(0 if _errors == 0 else 1)


func _save(filename: String) -> void:
	await create_timer(0.55).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(_output)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := directory.path_join(filename + ".png")
	var error := root.get_texture().get_image().save_png(file)
	if error != OK:
		_errors += 1
		push_error("Capture failed: %s" % error_string(error))
	else:
		print("CAPTURED %s" % file)
