extends SceneTree

## Fast product-level proof for the authored 7,080-second campaign graph.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog_errors := FoldlightCampaignCatalog.validate_catalog()
	_check(catalog_errors.is_empty(), "campaign catalog validates every authored mission")
	_check(FoldlightCampaignCatalog.mission_count() == 12, "campaign contains three chapters and twelve missions")
	var configured_seconds := 0
	var mission_ids: Dictionary = {}
	var objective_ids: Dictionary = {}
	var boss_ids: Dictionary = {}
	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		configured_seconds += mission.expected_seconds
		mission_ids[String(mission.mission_id)] = true
		boss_ids[String(mission.boss_id)] = true
		for objective_id in mission.objective_ids:
			objective_ids[String(objective_id)] = true
	_check(configured_seconds == 7080, "authored active route is exactly 7,080 seconds")
	_check(mission_ids.size() == 12, "all mission identifiers are unique")
	_check(objective_ids.size() >= 8, "campaign uses at least eight real objective families")
	_check(boss_ids.size() == 12, "every mission has an authored finale identity")

	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "campaign combat scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	_reset_profile(game.profile_manager)

	game.open_campaign_map()
	_check(game.mode == FoldlightGame.RunMode.CAMPAIGN_MAP, "title can enter the one-hand campaign map")
	var map_snapshots := game._campaign_map_snapshots()
	_check(map_snapshots.size() == 12 and not bool(map_snapshots[0]["locked"]) and bool(map_snapshots[1]["locked"]), "fresh route exposes only the first mission")

	game.start_campaign_mission(5)
	_dismiss_briefings(game)
	game.act = 3
	game.run_time = 1934.5
	game.score = 17200
	game.total_captures = 84
	game.total_kills = 31
	game.player.health = 3
	game.player.focus = 0.72
	game._chosen_path = 1
	game._path_step = 2
	game.doctrine_stacks = {"swift_return": 1, "bright_edge": 1}
	game.owned_doctrines = [
		game._doctrine_by_id(&"swift_return").to_snapshot(1),
		game._doctrine_by_id(&"bright_edge").to_snapshot(1),
	]
	_check(game._commit_campaign_checkpoint(), "tide-boundary checkpoint commits")
	var checkpoint := game.profile_manager.get_active_checkpoint()
	_check(String(checkpoint.get("mission_id", "")) == "c2m2" and int(checkpoint.get("tide", 0)) == 3, "checkpoint stores stable mission and tide IDs")
	game.start_campaign_mission(5, checkpoint)
	_dismiss_briefings(game)
	_check(game.act == 3 and game.player.health == 3 and is_equal_approx(game.player.focus, 0.72), "checkpoint restores tide, health and focus")
	_check(game._chosen_path == 1 and game._path_step == 2 and game.owned_doctrines.size() == 2, "checkpoint rebuilds the saved doctrine path")
	_check(game.hostile_shots.is_empty() and game.enemies.is_empty(), "checkpoint resumes at an empty safe tide boundary")

	var tracker := game.objective_tracker
	tracker.begin(&"return_quota", 8, "返还八枚花瓣", 60.0)
	tracker.report(&"return_hit", 5.0)
	tracker.report(&"return_hit", 3.0)
	var settled := tracker.snapshot()
	_check(StringName(settled.get("state_name", &"")) == &"success" and is_equal_approx(float(settled.get("ratio", 0.0)), 1.0), "objective tracker reaches success exactly once")
	tracker.report(&"return_hit", 50.0)
	_check(is_equal_approx(float(tracker.snapshot().get("current", 0.0)), 8.0), "settled objective cannot pay progress twice")

	game.enemies.clear()
	for enemy_type in [FoldlightGame.EnemyType.CARVER, FoldlightGame.EnemyType.BELL, FoldlightGame.EnemyType.THIEF, FoldlightGame.EnemyType.MOTH]:
		game._spawn_enemy(enemy_type, true)
		var dossier := game._enemy_tip_data(enemy_type)
		_check(not dossier.is_empty() and not str(dossier.get("counter", "")).is_empty(), "new enemy %d has explicit counterplay" % enemy_type)
	_check(game.enemies.size() == 4, "four new enemy archetypes instantiate")

	for mission_index in FoldlightCampaignCatalog.mission_count():
		game.current_mission_index = mission_index
		game.current_mission = FoldlightCampaignCatalog.mission_at(mission_index)
		game.enemies.clear()
		game.hostile_shots.clear()
		game._boss_spawned = false
		game._spawn_boss()
		var boss := game.enemies[0]
		_check(StringName(boss.get("boss_id", &"")) == game.current_mission.boss_id, "mission %02d spawns its authored finale" % (mission_index + 1))
		game._briefing_queue.clear()
		game._briefing_current.clear()

	_reset_profile(game.profile_manager)
	var total_reward := 0
	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		_check(game.profile_manager.is_mission_unlocked(mission.mission_id), "mission %02d unlocks in route order" % (mission_index + 1))
		total_reward += game.profile_manager.record_campaign_mission(mission.mission_id, {"rank": "B", "score": 10000 + mission_index, "time": mission.expected_seconds, "captures": 40, "kills": 20}, false)
	var campaign := game.profile_manager.get_campaign_snapshot()
	_check((campaign.get("completed", {}) as Dictionary).size() == 12 and bool(campaign.get("campaign_complete", false)), "fast campaign graph reaches the final ending")
	_check(is_equal_approx(float(campaign.get("campaign_seconds", 0.0)), 7080.0), "campaign graph records the full authored duration")
	var repeat_reward := game.profile_manager.record_campaign_mission(&"c1m1", {"rank": "S", "score": 99999, "time": 300.0}, false)
	_check(repeat_reward == 0 and (campaign.get("reward_grants", []) as Array).size() == 12, "first-clear rewards are idempotent")
	_check(total_reward > 0, "campaign first clears award Foldlight Court currency")

	var migrated := game.profile_manager._migrate_profile({
		"version": 3,
		"chapter_one_complete": true,
		"best_rank": "A",
		"best_score": 28000,
		"best_time": 620.0,
		"victories": 2,
		"meta_upgrades": {},
	})
	var migrated_campaign: Dictionary = migrated.get("campaign", {})
	_check(int(migrated.get("version", 0)) == FoldlightProfileManager.PROFILE_VERSION, "version-three profile migrates through the roguelite schema")
	_check((migrated_campaign.get("completed", {}) as Dictionary).has("c1m1") and (migrated_campaign.get("unlocked_missions", []) as Array).has("c1m2"), "legacy Chapter I clear maps to the first campaign mission")

	game.queue_free()
	await process_frame
	_finish()


func _reset_profile(profile_manager: FoldlightProfileManager) -> void:
	profile_manager.profile["version"] = FoldlightProfileManager.PROFILE_VERSION
	profile_manager.profile["tutorial_complete"] = false
	profile_manager.profile["challenge"] = {"runs": 0, "best_time": 0.0, "best_score": 0, "best_tier": 0, "total_events": 0}
	profile_manager.profile["glimmer"] = 0
	profile_manager.profile["total_runs"] = 0
	profile_manager.profile["victories"] = 0
	profile_manager.profile["total_captures"] = 0
	profile_manager.profile["total_kills"] = 0
	profile_manager.profile["story_flags"] = {}
	profile_manager.profile["acknowledged_intros"] = []
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
		print("FOLDLIGHT_TWO_HOUR_CAMPAIGN: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_TWO_HOUR_CAMPAIGN: FAIL — %s" % ", ".join(_failures))
		quit(1)
