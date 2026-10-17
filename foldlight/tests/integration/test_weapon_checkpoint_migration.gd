extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := FoldlightRogueRunState.new()
	var legacy := {
		"version": 1,
		"seed": 313013,
		"route": {"regions": [{"start_id": "r1_start"}]},
		"current_node_id": "r1_forge",
		"room_count": 3,
		"health": 3,
		"weapon_ids": ["needle_orbit", "needle_orbit", "returning_gull", "not_a_weapon", 17, {}],
		"weapon_levels": {"needle_orbit": 5},
	}
	_check(state.restore_checkpoint(legacy), "version-one run checkpoint remains loadable")
	_check(state.weapon_ids == [&"needle_orbit", &"returning_gull"] and state.weapon_levels == {"needle_orbit": 1, "returning_gull": 1}, "legacy weapon IDs migrate once to rank one and ignore invalid or duplicate entries")
	state.acquire_weapon(&"tide_bell")
	state.acquire_weapon(&"tide_bell")
	state.acquire_weapon(&"tide_bell")
	var saved := state.make_checkpoint()
	_check(int(saved["version"]) == 2 and int((saved["weapon_levels"] as Dictionary)["tide_bell"]) == 3, "new checkpoints record every weapon rank with a migrated schema")
	var serialized: Variant = JSON.parse_string(JSON.stringify(saved))
	var restored := FoldlightRogueRunState.new()
	_check(serialized is Dictionary and restored.restore_checkpoint(serialized as Dictionary), "ranked inventory survives the actual JSON save representation")
	_check(restored.weapon_ids == state.weapon_ids and restored.weapon_levels == state.weapon_levels and restored.health == 3, "reload restores the full arsenal and health without replacing weapons")
	(saved["weapon_levels"] as Dictionary)["tide_bell"] = 99
	((saved["route"] as Dictionary)["regions"] as Array)[0]["start_id"] = "changed"
	_check(state.get_weapon_level(&"tide_bell") == 3 and restored.get_weapon_level(&"tide_bell") == 3 and String(((state.route["regions"] as Array)[0] as Dictionary)["start_id"]) == "r1_start", "checkpoint data owns its inventory and route copies")

	var malformed := state.make_checkpoint()
	malformed["weapon_ids"] = ["crease_lantern", "prism_fan", "prism_fan", "bad", [], null]
	malformed["weapon_levels"] = {"crease_lantern": 99, "needle_orbit": -2, "returning_gull": "wrong", "sun_thread": 3.0, "bad": 5}
	_check(restored.restore_checkpoint(malformed), "malformed inventory entries are sanitized without discarding a valid run")
	_check(restored.weapon_levels == {"crease_lantern": 5, "needle_orbit": 1, "sun_thread": 3, "prism_fan": 1}, "numeric ranks clamp safely, unknown IDs disappear, and legacy-only IDs remain equipped")
	var empty := state.make_checkpoint()
	empty["weapon_ids"] = [false, {}, "bad"]
	empty["weapon_levels"] = {"crease_lantern": NAN, "sun_thread": INF}
	_check(restored.restore_checkpoint(empty) and restored.weapon_levels == {"crease_lantern": 1}, "an empty or unusable arsenal recovers a playable starter")
	var unchanged := restored.make_checkpoint()
	var future := unchanged.duplicate(true)
	future["version"] = 99
	future["health"] = 1
	_check(not restored.restore_checkpoint(future) and restored.make_checkpoint() == unchanged, "unknown future saves fail without mutating the current run")
	var invalid_position := unchanged.duplicate(true)
	invalid_position["current_node_id"] = []
	_check(not restored.restore_checkpoint(invalid_position) and restored.make_checkpoint() == unchanged, "invalid checkpoint identity fails before any live state changes")

	var compatibility := FoldlightRogueRunState.new()
	compatibility.begin_run(313013, {"regions": [{"start_id": "r1_start"}]})
	compatibility.weapon_ids = [&"crease_lantern", &"needle_orbit"]
	var compatible_save := compatibility.make_checkpoint()
	_check(int((compatible_save["weapon_levels"] as Dictionary).get("needle_orbit", 0)) == 1, "legacy direct weapon_ids callers retain their equipment on the next save")
	await _test_session_continue_without_starter()
	state.free()
	restored.free()
	compatibility.free()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	if _failures.is_empty():
		print("FOLDLIGHT_WEAPON_CHECKPOINT_MIGRATION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_WEAPON_CHECKPOINT_MIGRATION: FAIL — %s" % ", ".join(_failures))
		quit(1)


func _test_session_continue_without_starter() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	var legacy := session.run_controller.run_state.make_checkpoint()
	legacy["version"] = 1
	legacy["weapon_ids"] = ["needle_orbit", "returning_gull"]
	legacy.erase("weapon_levels")
	legacy["session_phase"] = "room"
	session.enter_title()
	# Simulate the previously persisted v1 profile, bypassing the v2 write API.
	(profile.profile["roguelite"] as Dictionary)["active_run"] = legacy
	session.continue_run()
	await process_frame
	var mounted := session.player.weapon_mount.get_inventory_snapshot()
	_check(mounted.size() == 2 and mounted.all(func(item: Dictionary) -> bool: return item.id in [&"needle_orbit", &"returning_gull"] and int(item.level) == 1), "actual session continue removes the default starter absent from the legacy save")
	_check(session.run_controller.run_state.weapon_ids.size() == mounted.size(), "continued live arsenal exactly matches the migrated checkpoint")
	var mount := session.player.weapon_mount
	mount.tick(0.1, false)
	var remaining := float(mount._timers["needle_orbit"])
	mount.set_weapon_levels({"needle_orbit": 1, "returning_gull": 1, "tide_bell": 1})
	_check(is_equal_approx(float(mount._timers["needle_orbit"]), remaining), "exact inventory synchronization preserves retained weapon cadence")
	game.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
