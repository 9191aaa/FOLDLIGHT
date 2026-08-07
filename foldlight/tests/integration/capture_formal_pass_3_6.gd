extends SceneTree

const ROOM_CAPTURE := "res://artifacts/formal_room_3_6.png"
const INTRO_CAPTURE := "res://artifacts/formal_enemy_intro_3_6.png"
const JUDGE_CAPTURE_PREFIX := "res://artifacts/formal_judge_"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport(ROOM_CAPTURE)

	session._enter_modal_safety()
	for pattern_id in [&"judgement_petals", &"unreflectable_cut", &"shrinking_frame"]:
		var telegraph := FoldlightBossAttackTelegraph.new()
		session.world.room_runtime.projectile_container.add_child(telegraph)
		telegraph.configure({
			"pattern_id": pattern_id,
			"origin": session.player.global_position,
			"target_position": session.player.global_position + Vector2.UP * 900.0,
			"duration": 1.4,
			"accent": Color(1.0, 0.58, 0.23),
		})
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		_save_viewport("%s%s_3_6.png" % [JUDGE_CAPTURE_PREFIX, String(pattern_id)])
		telegraph.queue_free()
		await process_frame

	var tracker := FoldlightMechanicIntroductionTracker.new()
	var definition := FoldlightRogueContentCatalog.enemy_by_id(&"paper_turret")
	var snapshot := tracker.request_introduction(definition)
	session.presentation.show_mechanic_card(snapshot)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_viewport(INTRO_CAPTURE)
	print("FOLDLIGHT_FORMAL_VISUAL_CAPTURE_3_6: PASS")
	tracker.free()
	game.queue_free()
	for frame in 4:
		await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	quit(0)


func _save_viewport(path: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Failed to save visual capture %s: %s" % [path, error_string(error)])
