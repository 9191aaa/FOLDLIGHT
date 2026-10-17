extends SceneTree

var _output := "res://captures/interactive_maps"
var _errors := 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var ignore_file := FileAccess.open(_output.path_join(".gdignore"), FileAccess.WRITE)
	ignore_file.close()
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	game.player.set_debug_invincible(true)
	while session._mechanic_intro_active:
		session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
	await create_timer(0.6).timeout
	await _save("battlefield")
	session._pause_game()
	var exits: Array[String] = []
	for destination: Variant in session.current_room_node.get("exits", []):
		exits.append(String(destination))
	session.presentation.show_route(session.current_region_snapshot, StringName(session.current_room_node.get("id", &"")), exits)
	await _sequence("atlas", session.presentation)
	await _save("atlas")
	var choices: Array[Dictionary] = []
	for content_id in [&"tiny_silhouette", &"double_step", &"large_burden"]:
		var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
		choices.append({"content_id": content_id, "title": definition.title, "description": definition.description, "rarity": definition.rarity, "accent": definition.accent, "next_level": 1, "maximum_level": definition.max_stacks})
	session.presentation.show_reward(choices, "纸礁浅海")
	await _sequence("reward", session.presentation)
	await _save("reward")
	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	quit(0 if _errors == 0 else 1)


func _sequence(kind: String, ui: FoldlightRoguePresentation) -> void:
	for frame in 72:
		if kind == "atlas":
			if frame == 20:
				ui._route_atlas.zoom_by(1.28)
			if frame == 38 and ui._route_buttons[1].visible:
				ui._route_buttons[1].grab_focus()
			if frame == 54:
				ui._route_atlas.recenter()
		elif kind == "reward":
			if frame == 26:
				ui._reward_buttons[1].grab_focus()
			if frame == 50:
				ui._reward_buttons[2].grab_focus()
		await create_timer(0.05).timeout
		await _save("%s/frame_%03d" % [kind, frame])


func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_output).path_join(filename + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var captured := root.get_texture().get_image()
	var error := captured.save_png(path)
	if filename in ["atlas", "reward"]:
		var review_path := ProjectSettings.globalize_path("res://../screenshots/interactive_%s.jpg" % filename)
		captured.save_jpg(review_path, 0.90)
	if error != OK:
		_errors += 1
		push_error("Capture failed: %s" % path)
