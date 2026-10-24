extends SceneTree

## Archived campaign/challenge data survives removal of their old play modes.
## Current gameplay continues to use the shared player and run-local growth.
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var archived_campaign := {"unlocked_missions": ["c1m1", "c1m2"], "completed": {"c1m1": {"clears": 2}}, "active_checkpoint": {"mission_id": "c1m2", "score": 810}, "campaign_seconds": 460.0}
	var archived_challenge := {"runs": 3, "best_time": 196.0, "best_score": 18420, "best_tier": 5, "total_events": 7}
	var migrated := profile._migrate_profile({"version": 4, "meta_upgrades": {"crease_rebuke": 1}, "campaign": archived_campaign, "challenge": archived_challenge, "tutorial_complete": true})
	_check(int(migrated.get("version", 0)) == FoldlightProfileManager.PROFILE_VERSION and migrated.has("roguelite"), "legacy saves gain the current run schema without requiring a story scene")
	_check((migrated["campaign"] as Dictionary).get("active_checkpoint") == archived_campaign["active_checkpoint"] and (migrated["campaign"] as Dictionary).get("completed") == archived_campaign["completed"], "removing story gameplay preserves historical checkpoints and completions")
	_check(migrated["challenge"] == archived_challenge and bool(migrated["tutorial_complete"]), "old challenge records and completed onboarding remain intact")
	profile.profile = migrated
	_check(profile.get_meta_level(&"crease_rebuke") == 1, "existing permanent purchases remain readable in old profiles")
	profile.profile["meta_upgrades"]["crease_rebuke"] = 0
	profile.profile["glimmer"] = 8
	_check(profile.purchase_meta_upgrade(&"crease_rebuke", false) and profile.get_meta_level(&"crease_rebuke") == 1, "shared profile upgrade data remains compatible with existing purchases")

	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(player)
	player.configure_roguelite_combat(true)
	var base_capacity: int = player.get_capture_capacity()
	player.apply_roguelite_stats(FoldlightBuildResolver.aggregate_stats({"thick_paper": 1}))
	_check(player.max_health > player.MAX_HEALTH, "the shared player still receives current run-local growth")
	player.reset_player()
	player.configure_roguelite_combat(true)
	_check(player.max_health == player.MAX_HEALTH and player.get_capture_capacity() == base_capacity, "a fresh mode restores the base player instead of carrying prior run growth or archived purchases")
	player.queue_free()
	await process_frame
	print("FOLDLIGHT_LEGACY_PROFILE_COMPATIBILITY: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
