extends SceneTree

## Product-level integration checks for the ritual run, doctrines, menus, and caps.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene and all resources compile")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false

	_check(FoldlightGame.DOCTRINE_LIBRARY.size() == 18, "eighteen data-driven doctrines load")
	var doctrine_ids: Dictionary = {}
	for doctrine in FoldlightGame.DOCTRINE_LIBRARY:
		doctrine_ids[String(doctrine.doctrine_id)] = true
	_check(doctrine_ids.size() == 18, "doctrine identifiers are unique")
	_check(FoldlightGame.DOCTRINE_PATHS.size() == 3, "three authored technique paths are defined")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "fixed arena preserves its full 16:9 composition on non-widescreen displays")
	for path: Array in FoldlightGame.DOCTRINE_PATHS:
		_check(path.size() == FoldlightGame.COMBAT_TIDE_COUNT, "every technique path has one fixed reward per combat tide")

	# The shipping front end is the roguelite. Enter the explicitly selected
	# classic surface before exercising legacy title shortcuts; those shortcuts
	# are intentionally swallowed while a roguelite modal owns input.
	game._ensure_classic_control()
	_send_action(&"menu_settings", true)
	await process_frame
	_send_action(&"menu_settings", false)
	_check(game.mode == FoldlightGame.RunMode.SETTINGS, "title opens controller-friendly settings")
	_send_action(&"pause_game", true)
	await process_frame
	_send_action(&"pause_game", false)
	_check(game.mode == FoldlightGame.RunMode.TITLE, "settings returns to title")

	_send_action(&"open_archive", true)
	await process_frame
	_send_action(&"open_archive", false)
	_check(game.mode == FoldlightGame.RunMode.ARCHIVE, "title opens persistent archive")
	_send_action(&"pause_game", true)
	await process_frame
	_send_action(&"pause_game", false)
	_check(game.mode == FoldlightGame.RunMode.TITLE, "archive returns to title")

	game.start_new_run()
	game._profile_recorded = true
	_check(game.mode == FoldlightGame.RunMode.BRIEFING and not game.player.play_enabled, "chapter opens on a confirmation-based paused briefing")
	var frozen_time := game.run_time
	var frozen_position := game.player.position
	game.hostile_shots.append({"position": Vector2(420.0, 240.0), "velocity": Vector2(180.0, 0.0), "curve": 0.0, "color": Color.MAGENTA, "kind": 0, "age": 0.0, "life": 2.0, "radius": 10.0, "reflectable": true, "status": &"", "status_duration": 0.0})
	var frozen_shot_position: Vector2 = game.hostile_shots[0]["position"]
	await physics_frame
	await physics_frame
	_check(is_equal_approx(game.run_time, frozen_time) and game.player.position == frozen_position and Vector2(game.hostile_shots[0]["position"]) == frozen_shot_position, "briefing freezes timers, player and combat simulation")
	_dismiss_briefings(game)
	_check(game.mode == FoldlightGame.RunMode.PLAYING and game.player.play_enabled and game.player.invulnerability >= 0.69, "confirming the last briefing resumes play with a safety window")
	game.hostile_shots.clear()
	game._open_technique_seal(2)
	var starter_ids: Array[StringName] = []
	for doctrine in game._seal_options:
		starter_ids.append(doctrine.doctrine_id)
	_check(starter_ids == [&"wide_crease", &"swift_return", &"slipstream"], "first seal offers the three fixed path starters")
	game._seal_selected = 2
	game._apply_selected_doctrine()
	_dismiss_briefings(game)
	game._open_technique_seal(3)
	_check(game._seal_options.size() == 1 and game._seal_options[0].doctrine_id == &"paper_heart", "later seal advances the selected path without randomness")
	game._apply_selected_doctrine()
	var base_radius := game.player.fold_radius_multiplier
	var base_capacity := game.player.capture_capacity
	var base_health := game.player.max_health
	for doctrine_id in doctrine_ids.keys():
		game._apply_doctrine_effect(doctrine_id)
	_check(game.player.fold_radius_multiplier > base_radius, "wide crease expands capture field")
	_check(game.player.capture_capacity == base_capacity + 10, "the expanded fold path adds both capacity doctrines")
	_check(game.player.max_health == base_health + 2, "the expanded body path adds both permanent health doctrines")
	_check(game._return_damage >= 2 and game._return_speed_multiplier > 1.0, "return doctrines improve counterattack")
	_check(game._chain_bloom and game._full_moon and game._golden_seam, "rare doctrines enable build-defining rules")

	game.enemies.clear()
	for enemy_type in [
		FoldlightGame.EnemyType.DRIFTER, FoldlightGame.EnemyType.FAN,
		FoldlightGame.EnemyType.WEAVER, FoldlightGame.EnemyType.RAM,
		FoldlightGame.EnemyType.BLOOMER, FoldlightGame.EnemyType.LEECH,
		FoldlightGame.EnemyType.MIRROR, FoldlightGame.EnemyType.REWINDER,
	]:
		game._spawn_enemy(enemy_type, true)
	_check(game.enemies.size() == 8, "eight regular enemy silhouettes spawn")
	var spawned_types: Dictionary = {}
	for enemy in game.enemies:
		spawned_types[int(enemy["type"])] = true
	_check(spawned_types.size() == 8, "regular enemy roster contains eight distinct behaviors")
	var enemy_tip_ids: Dictionary = {}
	for enemy_type in range(FoldlightGame.EnemyType.BOSS + 1):
		var enemy_tip: Dictionary = game._enemy_tip_data(enemy_type)
		if not enemy_tip.is_empty() and not str(enemy_tip.get("counter", "")).is_empty():
			enemy_tip_ids[String(enemy_tip.get("id", ""))] = true
	_check(enemy_tip_ids.size() == FoldlightGame.EnemyType.BOSS + 1, "every regular, herald and boss enemy has a dedicated counterplay dossier")
	_check("四秒" in str(game._enemy_tip_data(FoldlightGame.EnemyType.REWINDER).get("body", "")), "Rewinder dossier states its exact four-second rule")
	_dismiss_briefings(game)
	var effect_tip_ids: Array[StringName] = [&"wet_ink", &"bound_crease", &"veiled_fold", &"paper_seal", &"crosswind", &"lights_out"]
	var complete_effect_tips := 0
	for effect_tip_id in effect_tip_ids:
		var effect_tip: Dictionary = game._effect_tip_data(effect_tip_id)
		if not effect_tip.is_empty() and not str(effect_tip.get("counter", "")).is_empty():
			complete_effect_tips += 1
	_check(complete_effect_tips == effect_tip_ids.size(), "every status and battlefield effect has a dedicated response card")
	game.tip_queue.reset()
	game._queue_enemy_tip(FoldlightGame.EnemyType.MIRROR)
	game._queue_effect_tip(&"wet_ink")
	game.tip_queue.tick(0.30)
	var active_enemy_tip: Dictionary = game.tip_queue.get_snapshot(&"enemy")
	var active_effect_tip: Dictionary = game.tip_queue.get_snapshot(&"effect")
	_check(StringName(active_enemy_tip.get("id", &"")) == &"mirror" and StringName(active_effect_tip.get("id", &"")) == &"wet_ink" and float(active_enemy_tip.get("alpha", 0.0)) > 0.0, "enemy and effect teaching lanes can remain visible together")
	_check(not game.tip_queue.enqueue_once(&"effect", &"wet_ink", game._effect_tip_data(&"wet_ink")), "teaching queue suppresses duplicate tips within a run")
	game._queue_enemy_tip(FoldlightGame.EnemyType.RAM)
	_check(int(game.tip_queue.get_snapshot(&"enemy").get("queued", 0)) == 1, "a second enemy dossier waits instead of overwriting the active card")
	game.tip_queue.tick(7.0)
	_check(StringName(game.tip_queue.get_snapshot(&"enemy").get("id", &"")) == &"ram", "queued enemy dossier activates after the previous card expires")
	var scene_tags: Dictionary = {}
	for scene_tag in FoldlightGame.ACT_SCENE_TAGS:
		if not scene_tag.is_empty():
			scene_tags[scene_tag] = true
	_check(scene_tags.size() == FoldlightGame.FINAL_ACT, "all six tides and the finale expose distinct scene identities")
	game.tip_queue.reset()

	game.player.clear_statuses()
	_check(game.player.apply_status(&"wet_ink", 5.0), "wet ink status applies")
	_check(game.player.status_effects.get_focus_regen_multiplier() < 1.0, "wet ink reduces focus regeneration")
	game.player.status_effects.cleanse_from_release(6, 0.4)
	_check(not game.player.has_status(&"wet_ink"), "six-light release cleanses wet ink")
	game.player.apply_status(&"bound_crease", 5.0)
	_check(game.player.status_effects.get_move_multiplier() < 1.0, "bound crease reduces movement speed")
	game.player.status_effects.cleanse_from_release(3, 0.4)
	_check(not game.player.has_status(&"bound_crease"), "three-light release cleanses bound crease")
	game.player.apply_status(&"veiled_fold", 5.0)
	_check(game.player.status_effects.get_fold_radius_multiplier() < 1.0, "veiled fold reduces fold radius")
	game.player.status_effects.cleanse_from_release(0, 0.95)
	_check(not game.player.has_status(&"veiled_fold"), "full-charge release cleanses veiled fold")

	game.hostile_shots.clear()
	game.player.captured = 0
	game.player.folding = true
	game.player.fold_time = 1.0
	game._spawn_hostile(game.player.position + Vector2(48.0, 0.0), 0.0, 0.0, 0.0, Color.MAGENTA, 0)
	var sealed_start_x := game.player.position.x + 62.0
	game._spawn_sealed_hostile(Vector2(sealed_start_x, game.player.position.y), 0.0, 100.0)
	game._update_hostile_shots(0.016)
	_check(game.player.captured == 1, "fold captures the ordinary petal")
	_check(game.hostile_shots.size() == 1 and not bool(game.hostile_shots[0]["reflectable"]), "black-gold seal passes through capture and remains in play")
	var sealed_travel := float(game.hostile_shots[0]["position"].x) - sealed_start_x
	_check(sealed_travel > 0.0 and sealed_travel < 1.0, "seal is slowed by the fold field even though it cannot be captured")
	game.player.folding = false
	game.hostile_shots.clear()

	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.WEAVER, false)
	game.enemies[0]["position"] = Vector2(350.0, 250.0)
	game.enemies[0]["special"] = 0.0
	game.enemies[0]["skill_charge"] = 0.0
	game._update_enemies(0.016)
	_check(float(game.enemies[0]["skill_charge"]) > 0.0, "Weaver visibly charges before using its seal skill")
	game.enemies[0]["skill_charge"] = 0.01
	game._update_enemies(0.02)
	var weaver_seals := 0
	for shot in game.hostile_shots:
		if not bool(shot.get("reflectable", true)):
			weaver_seals += 1
	_check(weaver_seals == 3, "Weaver skill fires three unreflectable seal petals")

	game.enemies.clear()
	game.hostile_shots.clear()
	game.act = FoldlightGame.COMBAT_TIDE_COUNT
	game._spawn_herald()
	game.enemies[0]["special"] = 0.0
	game.enemies[0]["skill_charge"] = 0.0
	game._update_enemies(0.016)
	_check(float(game.enemies[0]["skill_charge"]) > 0.0, "final Herald telegraphs its seal skill")
	game.enemies[0]["skill_charge"] = 0.01
	game._update_enemies(0.02)
	var herald_seals := 0
	for shot in game.hostile_shots:
		if not bool(shot.get("reflectable", true)):
			herald_seals += 1
	_check(herald_seals == 6, "final Herald releases a six-seal ring with dodge gaps")

	game.enemies.clear()
	game.return_lights.clear()
	game.hostile_shots.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.MIRROR, false)
	game.enemies[0]["position"] = Vector2(960.0, 420.0)
	game.enemies[0]["mirror_state"] = int(FoldlightGame.MirrorState.FOLD)
	game.enemies[0]["mirror_timer"] = 2.0
	game.return_lights.append({"position": Vector2(960.0, 420.0), "velocity": Vector2.ZERO, "angle": 0.0, "orbit": 0.0, "delay": 0.0, "age": 0.0, "life": 3.0, "power": 1})
	game._update_return_lights(0.016)
	_check(game.return_lights.is_empty() and int(game.enemies[0]["stored_light"]) == 1, "Mirror Folder captures a player return light while folded")
	game.enemies[0]["stored_light"] = 5
	game._release_mirror_volley(game.enemies[0])
	_check(game.hostile_shots.size() == 5 and StringName(game.hostile_shots[0]["status"]) == &"veiled_fold" and bool(game.hostile_shots[0].get("reflectable", false)), "Mirror Folder releases stored light as capturable status petals")

	var pressure_samples: Array[int] = []
	for pressure_act in range(1, FoldlightGame.COMBAT_TIDE_COUNT + 1):
		game.act = pressure_act
		game.act_time = 0.0
		pressure_samples.append(game.get_pressure_level())
		game.act_time = 40.0
		pressure_samples.append(game.get_pressure_level())
	var pressure_sorted := pressure_samples.duplicate()
	pressure_sorted.sort()
	_check(pressure_samples == pressure_sorted, "authored tide pressure rises monotonically")

	for ritual_act in range(1, FoldlightGame.COMBAT_TIDE_COUNT + 1):
		game.act = ritual_act
		game._trigger_ritual_event(false)
		_check(not game._event_message.is_empty(), "tide %d first ritual announces clearly" % ritual_act)
		game._trigger_ritual_event(true)
		_check(game._ritual_event_kind == ritual_act * 2, "tide %d second ritual has authored behavior" % ritual_act)

	var history: Variant = FoldlightGame.PATH_HISTORY_BUFFER_SCRIPT.new(54, 0.08)
	history.reset(Vector2.ZERO, 0.0)
	for history_index in range(1, 71):
		history.sample(0.08, Vector2(float(history_index), 240.0), float(history_index) * 0.08)
	var four_second_path: PackedVector2Array = history.snapshot_since(1.60)
	_check(history.point_count() == 54 and history.history_span() >= 4.20 and history.history_span() <= 4.26, "Rewinder history remains a fixed-capacity four-second ring buffer")
	_check(four_second_path.size() >= 50 and is_equal_approx(four_second_path[0].x, 20.0) and is_equal_approx(four_second_path[-1].x, 70.0), "four-second snapshot preserves chronological positions")

	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.RAM, false)
	_dismiss_briefings(game)
	var ram: Dictionary = game.enemies[0]
	ram["position"] = Vector2(420.0, 420.0)
	ram["velocity"] = Vector2.ZERO
	ram["ram_state"] = int(FoldlightGame.RamState.STALK)
	ram["ram_timer"] = 0.01
	var ram_direction := Vector2(1.0, 0.0)
	game._update_ram_enemy(ram, 0.02, ram_direction, 1.0)
	_check(int(ram["ram_state"]) == FoldlightGame.RamState.TELEGRAPH and not game._enemy_contact_is_dangerous(ram), "Ram enters a harmless telegraph before charging")
	ram["ram_timer"] = 0.60
	ram["charge_direction"] = ram_direction
	game._update_ram_enemy(ram, 0.05, Vector2.DOWN, 1.0)
	_check(Vector2(ram["charge_direction"]).is_equal_approx(ram_direction), "Ram charge line locks before the dash")
	ram["ram_timer"] = 0.01
	var charge_velocity := game._update_ram_enemy(ram, 0.02, Vector2.DOWN, 1.0)
	_check(int(ram["ram_state"]) == FoldlightGame.RamState.CHARGE and charge_velocity.length() >= 839.0 and game._enemy_contact_is_dangerous(ram), "Ram's main attack is a fast, dangerous locked charge")

	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.REWINDER, false)
	_dismiss_briefings(game)
	var rewinder: Dictionary = game.enemies[0]
	var rewind_history: Variant = rewinder["path_buffer"]
	for rewind_index in range(1, 56):
		rewind_history.sample(0.08, Vector2(300.0 + rewind_index * 4.0, 320.0 + sin(rewind_index * 0.2) * 80.0), float(rewind_index) * 0.08)
	rewinder["age"] = 4.40
	rewinder["rewind_timer"] = 0.01
	game._update_rewinder_enemy(rewinder, 0.02, Vector2.RIGHT, 1.0)
	_check(int(rewinder["rewind_state"]) == FoldlightGame.RewindState.TELEGRAPH and PackedVector2Array(rewinder["rewind_path"]).size() >= 45, "Rewinder freezes its recent path into a readable telegraph")
	rewinder["rewind_timer"] = 0.01
	game._update_rewinder_enemy(rewinder, 0.02, Vector2.RIGHT, 1.0)
	_check(int(rewinder["rewind_state"]) == FoldlightGame.RewindState.REWIND and game._enemy_contact_is_dangerous(rewinder), "Rewinder becomes dangerous only while retracing the frozen path")
	game.player.position = Vector2(500.0, 500.0)
	_check(game._segment_hits_player(Vector2(300.0, 500.0), Vector2(700.0, 500.0), 24.0), "high-speed charge collision uses a swept line segment")

	game.hostile_shots.clear()
	for shot_index in FoldlightGame.HOSTILE_CAP + 80:
		game._spawn_hostile(Vector2(960, 200), PI * 0.5, 120.0, 0.0, Color.MAGENTA, 0)
	_check(game.hostile_shots.size() == FoldlightGame.HOSTILE_CAP, "hostile projectile cap is enforced")

	game.enemies.clear()
	game.hostile_shots.clear()
	game._boss_spawned = false
	game._spawn_boss()
	var boss_index := _find_enemy_type(game, FoldlightGame.EnemyType.BOSS)
	_check(boss_index >= 0, "Ink Moon boss spawns")
	if boss_index >= 0:
		var boss: Dictionary = game.enemies[boss_index]
		boss["health"] = int(float(boss["max_health"]) * 0.60)
		game._update_boss_fire(boss)
		_check(int(boss["boss_phase"]) == 2, "Ink Moon crosses into phase two")
		boss["health"] = int(float(boss["max_health"]) * 0.25)
		game._update_boss_fire(boss)
		_check(int(boss["boss_phase"]) == 3, "Ink Moon crosses into phase three")

	var migrated := game.profile_manager._migrate_profile({"version": 0})
	_check(int(migrated.get("version", 0)) == FoldlightProfileManager.PROFILE_VERSION, "legacy profile migration reaches current version")
	_check(migrated.has("achievements") and migrated.has("discovered_enemies") and migrated.has("glimmer") and migrated.has("meta_upgrades") and migrated.has("acknowledged_intros"), "migration restores campaign, teaching and meta-progression fields")
	var profile_snapshot := game.profile_manager.profile.duplicate(true)
	game.profile_manager.profile["glimmer"] = 10
	game.profile_manager.profile["meta_upgrades"] = {"lantern_frame": 0, "wide_memory": 0, "deep_reservoir": 0, "return_edge": 0}
	_check(game.profile_manager.purchase_meta_upgrade(&"wide_memory", false), "Foldlight Court spends Glimmer on an affordable permanent upgrade")
	_check(game.profile_manager.get_meta_level(&"wide_memory") == 1 and int(game.profile_manager.profile["glimmer"]) == 8, "meta purchase updates level and currency atomically in memory")
	game.profile_manager.profile = profile_snapshot

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	_finish()


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _find_enemy_type(game: FoldlightGame, enemy_type: int) -> int:
	for index in game.enemies.size():
		if int(game.enemies[index]["type"]) == enemy_type:
			return index
	return -1


func _dismiss_briefings(game: FoldlightGame) -> void:
	while game.mode == FoldlightGame.RunMode.BRIEFING:
		game._advance_briefing(false)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_STEAM_OVERHAUL: PASS")
		quit(0)
	else:
		printerr("FOLDLIGHT_STEAM_OVERHAUL: FAIL — ", ", ".join(_failures))
		quit(1)
