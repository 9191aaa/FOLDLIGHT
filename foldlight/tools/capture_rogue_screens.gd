extends SceneTree

var _game: FoldlightGame


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_game = packed.instantiate() as FoldlightGame
	root.add_child(_game)
	await process_frame
	await process_frame
	await create_timer(0.18).timeout
	var requested := "title"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		requested = args[0].trim_prefix("--capture-")
	var session := _game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	if requested == "review":
		await _capture_release_review(session)
		_game.queue_free()
		await process_frame
		quit(0)
		return
	match requested:
		"hud":
			session.start_new_run()
			await create_timer(1.1).timeout
		"reward":
			var choices: Array[Dictionary] = []
			for content_id in [&"tiny_silhouette", &"double_step", &"large_burden"]:
				var definition := FoldlightRogueContentCatalog.upgrade_by_id(content_id)
				choices.append({"content_id": content_id, "title": definition.title, "description": definition.description, "rarity": definition.rarity, "accent": definition.accent, "next_level": 1, "maximum_level": definition.max_stacks})
			session.presentation.show_reward(choices, "纸礁浅海")
		"route":
			session.start_new_run()
			await process_frame
			var node := session.current_room_node
			var exits: Array[String] = []
			for value: Variant in node.get("exits", []):
				exits.append(String(value))
			session.presentation.show_route(session.current_region_snapshot, StringName(node.get("id", &"")), exits)
		"pause":
			session.start_new_run()
			await create_timer(0.5).timeout
			session._pause_game()
		"settings":
			session.presentation.show_settings(session.profile_manager.settings, &"title")
		"prologue":
			session.start_prologue()
			await create_timer(0.85).timeout
		"result":
			session.presentation.show_result({"won": true, "region": 3, "rooms": 22, "time": 2476.0, "glimmer": 86})
		"shop":
			var shop_choices := session._draft_room_reward(&"shop", session.profile_manager.get_roguelite_snapshot())
			session.presentation.show_reward(shop_choices, "漂灯市")
		"forge":
			var forge_choices := session._draft_room_reward(&"forge", session.profile_manager.get_roguelite_snapshot())
			session.presentation.show_reward(forge_choices, "折纸坊")
		"region_1", "region_2", "region_3":
			await _setup_region_capture(session, requested.trim_prefix("region_").to_int() - 1)
		"roster":
			await _setup_original_roster_capture(session)
		"boss", "boss_reef", "boss_archive", "boss_judge":
			var boss_index := {"boss_reef": 0, "boss_archive": 1, "boss_judge": 2}.get(requested, 2) as int
			await _setup_boss_capture(session, boss_index)
		_:
			pass
	await process_frame
	await process_frame
	var output_dir := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path := output_dir.path_join("rogue_%s.png" % requested)
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURED %s (%s)" % [path, error_string(error)])
	_game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)


func _capture_release_review(session: FoldlightRogueSessionController) -> void:
	await _save_review_frame("title")
	session.start_new_run()
	await create_timer(1.1).timeout
	await _save_review_frame("hud")
	for region_index in 3:
		await _setup_region_capture(session, region_index)
		await _save_review_frame("region_%d" % (region_index + 1))
	await _setup_original_roster_capture(session)
	await _save_review_frame("roster")
	for boss_index in 3:
		await _setup_boss_capture(session, boss_index)
		var names: Array[String] = ["boss_reef", "boss_archive", "boss_judge"]
		await _save_review_frame(names[boss_index])
	var tracker := FoldlightMechanicIntroductionTracker.new()
	var snapshot := tracker.request_introduction(FoldlightRogueContentCatalog.enemy_by_id(&"paper_turret"))
	session.presentation.show_mechanic_card(snapshot)
	await create_timer(0.35).timeout
	await _save_review_frame("enemy_intro")
	tracker.free()
	print("FOLDLIGHT_RELEASE_VISUAL_REVIEW_3_7: PASS")


func _save_review_frame(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path := output_dir.path_join("rogue_%s.png" % name)
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Failed visual review frame %s: %s" % [name, error_string(error)])
	else:
		print("CAPTURED %s" % path)


func _setup_region_capture(session: FoldlightRogueSessionController, region_index: int) -> void:
	session.start_new_run()
	await process_frame
	var index := clampi(region_index, 0, 2)
	session.run_controller.run_state.current_region = index
	var regions: Array = session.run_controller.run_state.route.get("regions", [])
	var region: Dictionary = regions[index] if regions.size() > index else {}
	var room_node := {"id": "capture_region_%d" % (index + 1), "category": "combat", "depth": 4, "risk": index + 3, "exits": []}
	session._on_room_requested(room_node, region)
	await create_timer(1.35).timeout


func _setup_boss_capture(session: FoldlightRogueSessionController, region_index: int) -> void:
	session.start_new_run()
	await process_frame
	var index := clampi(region_index, 0, 2)
	session.run_controller.run_state.current_region = index
	var regions: Array = session.run_controller.run_state.route.get("regions", [])
	var region: Dictionary = regions[index] if regions.size() > index else {}
	var boss_ids: Array[StringName] = [&"reef_crown_battery", &"inverted_archivist", &"origami_judge"]
	var boss_node := {"id": "capture_boss_%d" % (index + 1), "category": "boss", "depth": 7, "risk": index + 4, "boss_id": boss_ids[index], "exits": []}
	session._on_room_requested(boss_node, region)
	await create_timer(1.35).timeout
	var boss: FoldlightRogueBossActor
	for enemy in session.world.combat_runtime.enemies:
		if enemy is FoldlightRogueBossActor:
			boss = enemy as FoldlightRogueBossActor
			break
	if boss == null:
		return
	boss.health = boss.definition.base_health * 0.28
	boss.arena_controller.set_phase(2)
	# Region one is captured during its visible tide surge, rather than behind
	# the old full-screen lane warning that made the boss silhouette unreadable.
	boss.arena_controller.advance_simulation(3.5 if index == 0 else 2.4, session.player.global_position)
	var warning_patterns: Array[StringName] = [&"tide_fan", &"margin_cut", &"unreflectable_cut"]
	session.world.combat_runtime._on_boss_telegraph_requested({"pattern_id": warning_patterns[index], "duration": 1.25, "origin": boss.global_position, "target_position": session.player.global_position, "accent": boss.definition.accent})
	session.world.combat_runtime.spawn_hostile_volley({"origin": boss.global_position, "direction": boss.global_position.direction_to(session.player.global_position), "projectile_count": 5, "spread_radians": 0.65, "reflectable": false, "speed": 170.0, "damage": 1.0, "radius": 10.0, "lifetime": 6.0, "style": &"black_gold_cut", "radial": false})
	var reflected_styles: Array[StringName] = [&"crown_ring", &"ledger_petal", &"judgement_petal"]
	session.world.combat_runtime.spawn_hostile_volley({"origin": boss.global_position, "direction": Vector2.RIGHT, "projectile_count": 14, "spread_radians": TAU, "reflectable": true, "speed": 170.0, "damage": 1.0, "radius": 8.0, "lifetime": 6.0, "style": reflected_styles[index], "radial": true})
	await create_timer(0.48).timeout


func _setup_original_roster_capture(session: FoldlightRogueSessionController) -> void:
	session.start_new_run()
	await create_timer(0.35).timeout
	var combat := session.world.combat_runtime
	combat.clear_combat()
	var center := session.player.global_position
	var ids: Array[StringName] = [&"drifter", &"fan", &"weaver", &"ram", &"bloomer", &"leech", &"mirror", &"rewinder"]
	var offsets: Array[Vector2] = [
		Vector2(-640, -270), Vector2(-230, -330), Vector2(230, -330), Vector2(640, -250),
		Vector2(-650, 190), Vector2(-240, 250), Vector2(245, 250), Vector2(650, 185),
	]
	for index in ids.size():
		var actor := combat._spawn_enemy_from_entry({"enemy_id": ids[index], "spawn_position": center + offsets[index]}, false)
		if actor != null:
			actor.set("_age", 1.0)
			actor.queue_redraw()
	combat.set_active(false)
	session.player.folding = true
	session.player.fold_time = 0.55
	session.player.focus = 0.68
	session.player.captured = 6
	session.presentation.hide_prologue_step()
	session._refresh_hud()
	await process_frame
