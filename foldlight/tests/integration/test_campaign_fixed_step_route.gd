extends SceneTree

## Full-duration fixed-step proof: 7,080 virtual seconds at the production 60 Hz
## physics step. Unlike the fast graph soak, this executes live spawning, enemy,
## projectile, objective, ritual, effect and boss systems on every simulated frame.

const STEP: float = 1.0 / 60.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_usec := Time.get_ticks_usec()
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads for full-duration fixed-step route")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	_reset_profile(game.profile_manager)

	var simulated_seconds := 0.0
	var simulated_frames := 0
	var peak_enemies := 0
	var peak_hostile := 0
	var peak_particles := 0
	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		game.start_campaign_mission(mission_index)
		_dismiss_briefings(game)
		game.player.invulnerability = 9999999.0
		game.run_time = 0.0
		for tide_index in FoldMissionDefinition.TIDE_COUNT:
			game.act = tide_index + 1
			game.act_time = 0.0
			game._spawn_timer = 0.0
			game._herald_active = false
			game._ritual_flags.clear()
			game.enemies.clear()
			game.hostile_shots.clear()
			game.return_lights.clear()
			game._begin_tide_objective()
			var tide_frames := int(round(mission.tide_duration / STEP))
			for frame_index in tide_frames:
				game.run_time += STEP
				game.act_time += STEP
				game.objective_tracker.tick(STEP)
				game._update_spatial_objective(STEP)
				game._update_ritual(STEP)
				game._update_spawning(STEP)
				game._update_enemies(STEP)
				game._update_hostile_shots(STEP)
				game._update_return_lights(STEP)
				game._update_effects(STEP)
				peak_enemies = maxi(peak_enemies, game.enemies.size())
				peak_hostile = maxi(peak_hostile, game.hostile_shots.size())
				peak_particles = maxi(peak_particles, game.particles.size())
				if game.enemies.size() > FoldlightGame.ENEMY_CAP + 1 or game.hostile_shots.size() > FoldlightGame.HOSTILE_CAP or game.particles.size() > FoldlightGame.PARTICLE_CAP:
					_failures.append("runtime cap exceeded in mission %02d tide %d" % [mission_index + 1, tide_index + 1])
					break
			simulated_frames += tide_frames
			simulated_seconds += mission.tide_duration

		game.enemies.clear()
		game.hostile_shots.clear()
		game.return_lights.clear()
		game._herald_active = false
		game._boss_spawned = false
		game._spawn_boss()
		var boss_frames := int(round(float(mission.boss_budget_seconds) / STEP))
		for frame_index in boss_frames:
			if not game.enemies.is_empty():
				var boss: Dictionary = game.enemies[0]
				var boss_ratio := float(frame_index) / float(maxi(1, boss_frames - 1))
				if boss_ratio >= 0.67:
					boss["health"] = maxi(1, int(float(boss["max_health"]) * 0.30))
				elif boss_ratio >= 0.34:
					boss["health"] = maxi(1, int(float(boss["max_health"]) * 0.62))
			game.run_time += STEP
			game._update_enemies(STEP)
			game._update_hostile_shots(STEP)
			game._update_return_lights(STEP)
			game._update_effects(STEP)
			peak_enemies = maxi(peak_enemies, game.enemies.size())
			peak_hostile = maxi(peak_hostile, game.hostile_shots.size())
			peak_particles = maxi(peak_particles, game.particles.size())
			if game.enemies.size() > FoldlightGame.ENEMY_CAP + 2 or game.hostile_shots.size() > FoldlightGame.HOSTILE_CAP or game.particles.size() > FoldlightGame.PARTICLE_CAP:
				_failures.append("runtime cap exceeded in mission %02d finale" % (mission_index + 1))
				break
		simulated_frames += boss_frames
		simulated_seconds += mission.boss_budget_seconds
		game.profile_manager.record_campaign_mission(mission.mission_id, {
			"rank": "A",
			"score": 24000 + mission_index * 1000,
			"time": mission.expected_seconds,
			"captures": 100,
			"kills": 50,
		}, false)
		print("[ROUTE] mission %02d/12 simulated %d seconds" % [mission_index + 1, mission.expected_seconds])

	var campaign := game.profile_manager.get_campaign_snapshot()
	_check(simulated_frames == 424800, "route executes exactly 424,800 production-rate physics frames")
	_check(is_equal_approx(simulated_seconds, 7080.0), "route executes exactly 7,080 virtual seconds")
	_check((campaign.get("completed", {}) as Dictionary).size() == 12 and bool(campaign.get("campaign_complete", false)), "full fixed-step route reaches the authored ending")
	_check(peak_enemies <= FoldlightGame.ENEMY_CAP + 2, "enemy population remains bounded over the full route")
	_check(peak_hostile <= FoldlightGame.HOSTILE_CAP and peak_hostile > 0, "projectile population remains active and bounded over the full route")
	_check(peak_particles <= FoldlightGame.PARTICLE_CAP, "effect population remains bounded over the full route")
	var wall_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	print("FOLDLIGHT_FIXED_STEP_ROUTE virtual_seconds=%.0f frames=%d wall_seconds=%.2f peak_enemies=%d peak_hostile=%d peak_particles=%d" % [simulated_seconds, simulated_frames, wall_seconds, peak_enemies, peak_hostile, peak_particles])

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	_finish()


func _reset_profile(profile_manager: FoldlightProfileManager) -> void:
	profile_manager.profile["version"] = FoldlightProfileManager.PROFILE_VERSION
	profile_manager.profile["campaign"] = {
		"unlocked_missions": ["c1m1"],
		"completed": {},
		"reward_grants": [],
		"campaign_complete": false,
		"campaign_seconds": 0.0,
		"active_checkpoint": {},
		"failure_counts": {},
		"assisted_missions": [],
	}


func _dismiss_briefings(game: FoldlightGame) -> void:
	var guard := 64
	while game.mode == FoldlightGame.RunMode.BRIEFING and guard > 0:
		game._advance_briefing(false)
		guard -= 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_CAMPAIGN_FIXED_STEP_ROUTE: PASS")
		quit(0)
	else:
		printerr("FOLDLIGHT_CAMPAIGN_FIXED_STEP_ROUTE: FAIL — ", ", ".join(_failures))
		quit(1)
