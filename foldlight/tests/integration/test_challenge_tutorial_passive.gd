extends SceneTree

## Product-level proof for the 2.1 challenge, onboarding, and Fold-boundary passive.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := FoldlightChallengeDirector.new()
	root.add_child(director)
	var draft_signals := [0]
	director.draft_requested.connect(func() -> void: draft_signals[0] += 1)
	director.start(424242)
	var start_bounds := director.get_arena_bounds()
	_check(start_bounds.is_equal_approx(FoldlightChallengeDirector.START_BOUNDS), "challenge starts in the compact authored arena")
	director.tick(20.1)
	_check(director.events_seen == 1 and not director.current_event.is_empty(), "first signed random event begins at twenty seconds")
	_check([&"positive", &"negative"].has(StringName(director.current_event.get("polarity", &""))), "challenge event declares positive or negative polarity")
	director.tick(55.0)
	_check(director.tier == 2 and draft_signals[0] == 1, "difficulty tier and first roguelite draft advance on schedule")
	_check(director.get_arena_bounds().size.x > start_bounds.size.x, "arena expands continuously as the run advances")
	director.complete_draft()
	director.elapsed = FoldlightChallengeDirector.EXPANSION_SECONDS
	_check(director.get_arena_bounds().is_equal_approx(FoldlightChallengeDirector.FULL_BOUNDS), "arena reaches but does not exceed the full map at ten minutes")
	director.queue_free()

	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "2.1 game scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	_reset_profile(game.profile_manager)

	game.start_challenge_run(98765)
	_check(game._challenge_active and not game._tutorial_active and game.mode == FoldlightGame.RunMode.PLAYING, "title flow can start an isolated endless challenge")
	_check(game.profile_manager.get_active_checkpoint().is_empty(), "challenge start never writes a campaign checkpoint")
	_check(game.player.play_bounds.size.x < FoldlightChallengeDirector.FULL_BOUNDS.size.x, "challenge player clamp uses the compact runtime boundary")
	game.challenge_director.tick(75.1)
	_check(game.mode == FoldlightGame.RunMode.UPGRADE and game._challenge_draft_pending, "seventy-five seconds opens the roguelite Fold draft")
	_check(game._seal_options.size() == 3, "challenge draft presents exactly three choices")
	var option_ids: Dictionary = {}
	for doctrine in game._seal_options:
		option_ids[String(doctrine.doctrine_id)] = true
	_check(option_ids.size() == 3, "challenge draft choices are unique")
	game._apply_selected_doctrine()
	_check(game.mode == FoldlightGame.RunMode.PLAYING and game._challenge_drafts == 1 and game.owned_doctrines.size() == 1, "chosen challenge Fold stacks for the current run and resumes play")

	game.hostile_shots.clear()
	game._on_challenge_event_started({"id": &"lantern_rain", "title": "灯雨", "detail": "测试", "accent": Color.GOLD})
	_check(game.hostile_shots.size() == 18, "positive lantern event creates a readable capturable reward ring")
	game.enemies.clear()
	game._on_challenge_event_started({"id": &"elite_hunt", "title": "双煞", "detail": "测试", "accent": Color.CRIMSON})
	_check(game.enemies.size() == 2 and bool(game.enemies[0].get("elite", false)) and bool(game.enemies[1].get("elite", false)), "negative hunt event creates two elite threats")
	game.challenge_director.elapsed = 600.0
	game._apply_challenge_runtime(0.0)
	_check(game.player.play_bounds.size.x <= FoldlightChallengeDirector.FULL_BOUNDS.grow(-44.0).size.x + 0.01, "expanded challenge clamp remains inside the authored full arena")

	game.run_time = 196.0
	game.score = 18420
	game.total_kills = 37
	game.challenge_director.tier = 5
	game.challenge_director.events_seen = 7
	game._lose_run()
	var challenge_record := game.profile_manager.get_challenge_snapshot()
	_check(game.mode == FoldlightGame.RunMode.GAME_OVER and bool(game._mission_result.get("challenge", false)), "challenge defeat opens its own result flow")
	_check(int(challenge_record.get("runs", 0)) == 1 and int(challenge_record.get("best_score", 0)) == 18420 and int(challenge_record.get("best_tier", 0)) == 5, "challenge result persists runs, best score, and best tier")
	_check(game._last_glimmer_reward > 0, "challenge result awards persistent Glimmer")

	game.start_tutorial()
	_check(game._tutorial_active and game.mode == FoldlightGame.RunMode.PLAYING, "short onboarding launches independently from campaign")
	game._update_tutorial(3.1)
	_check(game._tutorial_step == FoldlightGame.TutorialStep.MOVE, "tutorial introduces movement first")
	game.player.position += Vector2(200.0, 0.0)
	game._update_tutorial(0.1)
	_check(game._tutorial_step == FoldlightGame.TutorialStep.CAPTURE, "tutorial advances after a small movement sample")
	game.player.captured = 3
	game._update_tutorial(0.1)
	_check(game._tutorial_step == FoldlightGame.TutorialStep.RELEASE, "tutorial requires three captured petals before release lesson")
	game._tutorial_release_success = true
	game._update_tutorial(0.1)
	_check(game._tutorial_step == FoldlightGame.TutorialStep.PRACTICE, "successful release opens a short free-practice window")
	game._tutorial_total_time = 32.0
	game._tutorial_step_time = 6.0
	game._update_tutorial(0.1)
	_check(game._tutorial_step == FoldlightGame.TutorialStep.COMPLETE, "tutorial cannot finish before the thirty-second floor")
	game._tutorial_step_time = 3.0
	game._update_tutorial(0.1)
	_check(game.mode == FoldlightGame.RunMode.TITLE and bool(game.profile_manager.profile.get("tutorial_complete", false)), "tutorial completes in the 30–60 second target and saves completion")

	_reset_profile(game.profile_manager)
	game.profile_manager.profile["glimmer"] = 8
	_check(game.profile_manager.purchase_meta_upgrade(&"crease_rebuke", false), "Fold-boundary passive can be bought in the meta archive")
	_check(game.profile_manager.get_meta_level(&"crease_rebuke") == 1, "Fold-boundary passive purchase is permanent profile state")
	game.start_campaign_mission(0)
	_dismiss_briefings(game)
	game._crease_rebuke = true
	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.RAM, false)
	game.enemies[0]["position"] = game.player.position + Vector2(300.0, 0.0)
	game.enemies[0]["velocity"] = Vector2(260.0, 0.0)
	game.enemies[0]["ram_state"] = int(FoldlightGame.RamState.CHARGE)
	var ram_health := int(game.enemies[0]["health"])
	game._on_fold_released(0, 1.0)
	_check(int(game.enemies[0]["health"]) < ram_health and int(game.enemies[0]["ram_state"]) == FoldlightGame.RamState.RECOVER, "charged Ram crossing the released circle is damaged and exposed")

	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.RAM, false)
	game.enemies[0]["position"] = game.player.position + Vector2(300.0, 0.0)
	game.enemies[0]["velocity"] = Vector2(260.0, 0.0)
	game.enemies[0]["ram_state"] = int(FoldlightGame.RamState.STALK)
	ram_health = int(game.enemies[0]["health"])
	game._on_fold_released(0, 1.0)
	_check(int(game.enemies[0]["health"]) == ram_health and int(game.enemies[0]["ram_state"]) == FoldlightGame.RamState.STALK, "non-charging enemies are immune to Fold-boundary passive")

	game.enemies.clear()
	game._spawn_enemy(FoldlightGame.EnemyType.REWINDER, false)
	game.enemies[0]["position"] = game.player.position + Vector2(304.0, 0.0)
	game.enemies[0]["velocity"] = Vector2(220.0, 0.0)
	game.enemies[0]["rewind_state"] = int(FoldlightGame.RewindState.REWIND)
	var rewind_health := int(game.enemies[0]["health"])
	game._on_fold_released(0, 1.0)
	_check(int(game.enemies[0]["health"]) < rewind_health and int(game.enemies[0]["rewind_state"]) == FoldlightGame.RewindState.RECOVER, "rewinding enemy uses the same high-speed Fold-boundary counterplay")

	var migrated := game.profile_manager._migrate_profile({"version": 4, "meta_upgrades": {}})
	_check(int(migrated.get("version", 0)) == FoldlightProfileManager.PROFILE_VERSION and migrated.has("challenge") and migrated.has("tutorial_complete") and migrated.has("roguelite"), "version-four saves migrate safely through the 3.0 schema")

	game.queue_free()
	await process_frame
	_finish()


func _reset_profile(profile_manager: FoldlightProfileManager) -> void:
	profile_manager.profile["version"] = FoldlightProfileManager.PROFILE_VERSION
	profile_manager.profile["glimmer"] = 0
	profile_manager.profile["meta_upgrades"] = {
		"lantern_frame": 0,
		"wide_memory": 0,
		"deep_reservoir": 0,
		"return_edge": 0,
		"crease_rebuke": 0,
	}
	profile_manager.profile["tutorial_complete"] = false
	profile_manager.profile["challenge"] = {"runs": 0, "best_time": 0.0, "best_score": 0, "best_tier": 0, "total_events": 0}
	profile_manager.profile["achievements"] = {}
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
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_CHALLENGE_TUTORIAL_PASSIVE: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_CHALLENGE_TUTORIAL_PASSIVE: FAIL — %s" % ", ".join(_failures))
		quit(1)
