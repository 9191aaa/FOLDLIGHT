extends SceneTree

## Production room/player/camera/HUD and live enemy simulation. Debug immunity
## keeps the unattended capture alive; it is visual QA, not a balance measure.
const OUTPUT := "res://captures/boss_playable"
const IDS: Array[StringName] = [&"reef_crown_battery", &"inverted_archivist", &"origami_judge"]
var game: FoldlightGame
var errors: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.profile["roguelite"]["prologue_complete"] = true
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	if OS.get_cmdline_user_args().has("--preview-only"):
		var tracker := FoldlightMechanicIntroductionTracker.new()
		for boss_id in IDS:
			session.presentation.show_mechanic_card(tracker.request_boss_introduction(FoldlightRogueContentCatalog.boss_by_id(boss_id)))
			await create_timer(0.7).timeout
			await _save("intro_"+String(boss_id))
			print("INTRO_PREVIEW %s size=%s" % [boss_id,str(session.presentation._mechanic_intro_preview.size)])
		tracker.free()
		game.queue_free()
		await process_frame
		print("FOLDLIGHT_BOSS_PREVIEW_CAPTURE: "+("PASS" if errors==0 else "FAIL"))
		quit(0 if errors==0 else 1)
		return
	for index in 3:
		session.start_new_run()
		await process_frame
		_dismiss(session)
		session.run_controller.run_state.current_region = index
		var regions: Array = session.run_controller.run_state.route.get("regions", [])
		var region: Dictionary = regions[index]
		session._on_room_requested({"id":"paper_model_boss_%d"%index,"category":"boss","depth":7,"risk":index+4,"boss_id":IDS[index],"exits":[]},region)
		game.player.set_debug_invincible(true)
		game.player.weapon_mount.enabled = false
		var found: FoldlightRogueBossActor
		var deadline := Time.get_ticks_msec()+6000
		while found == null and Time.get_ticks_msec() < deadline:
			for enemy in session.world.combat_runtime.enemies:
				if enemy is FoldlightRogueBossActor:
					found = enemy as FoldlightRogueBossActor
			if found == null:
				_dismiss(session)
				await create_timer(0.05).timeout
		if found == null:
			errors += 1
			push_error("Missing live boss " + String(IDS[index]))
			continue
		if session.presentation.screen_kind == &"mechanic_intro":
			await create_timer(0.7).timeout
			await _save("intro_"+String(IDS[index]))
			print("INTRO_PREVIEW %s size=%s" % [IDS[index],str(session.presentation._mechanic_intro_preview.size)])
		_dismiss(session)
		await _live_wait(session,4.5)
		await _save("combat_"+String(IDS[index]))
		print("LIVE_BOSS %s enemies=%d projectiles=%d zoom=%s player=%s boss=%s" % [IDS[index],session.world.combat_runtime.enemies.size(),session.world.combat_runtime.projectiles.size(),str(session.world.camera.zoom),str(game.player.global_position),str(found.global_position)])
	# Same production factory and projectile runtime, with no artificial shots.
	session.world.combat_runtime.clear_combat()
	await process_frame
	var elite: Node2D = session.world.combat_runtime._spawn_enemy_from_entry({"enemy_id":&"shutter_seraph","spawn_position":game.player.global_position+Vector2(320,-230)},false)
	if elite != null:
		_dismiss(session)
		await _live_wait(session,0.35)
		await _save_absolute("res://captures/shutter_seraph_closed.png")
		var deadline := Time.get_ticks_msec()+6000
		while int(elite.get("phase")) != 2 and Time.get_ticks_msec()<deadline:
			_dismiss(session)
			await create_timer(0.05).timeout
		await _live_wait(session,0.65)
		await _save_absolute("res://captures/shutter_seraph_firing.png")
		print("LIVE_ELITE phase=%d projectiles=%d" % [int(elite.get("phase")),session.world.combat_runtime.projectiles.size()])
	else:
		errors += 1
		push_error("Missing real shutter seraph factory actor")
	game.queue_free()
	await process_frame
	print("FOLDLIGHT_BOSS_PLAYABLE_CAPTURE: "+("PASS" if errors==0 else "FAIL"))
	quit(0 if errors==0 else 1)

func _live_wait(session: FoldlightRogueSessionController, seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		_dismiss(session)
		await create_timer(0.05).timeout

func _dismiss(session: FoldlightRogueSessionController) -> void:
	while session._mechanic_intro_active:
		session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)

func _save(name: String) -> void:
	await _save_absolute(OUTPUT.path_join(name+".png"))

func _save_absolute(resource_path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(resource_path)
	if root.get_texture().get_image().save_png(path)!=OK:
		errors += 1
		push_error("Failed capture "+path)
	print("CAPTURED "+path)
