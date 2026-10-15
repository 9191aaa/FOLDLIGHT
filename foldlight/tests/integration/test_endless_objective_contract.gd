extends SceneTree

const Director = preload("res://scripts/endless/endless_objective_director.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var config := load("res://resources/endless/endless_survival_default.tres") as FoldlightEndlessSurvivalConfig
	var map := load("res://resources/endless/maps/folded_delta.tres") as FoldlightEndlessMapDefinition
	var director := Director.new()
	root.add_child(director)
	director.reset(config, map, 3)
	var seen_ids: Dictionary = {}
	var capture_sites: Dictionary = {}
	var kinds: Dictionary = {}
	var unique := true
	for cycle in 13:
		var objective := director.get_snapshot()
		var kind := StringName(objective.get("kind", &""))
		kinds[kind] = true
		var target := StringName(objective.get("target_id", &""))
		unique = unique and not seen_ids.has(target)
		seen_ids[target] = true
		if kind == &"capture_point": capture_sites[Vector2(objective["target_position"])] = true
		if kind == &"defeat_captain":
			_check(not director.report_captain_defeated(), "an empty captain id cannot complete the active task")
		_complete(director)
		_check(bool(director.get_snapshot().get("completed", false)), "task %d (%s) completes through its own interaction" % [cycle, kind])
		director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	_check(unique, "task instances never reuse target identities across completed rotations")
	_check(capture_sites.size() >= 3, "successive capture tasks visit all three authored sites rather than one fixed site")
	_check(kinds.size() == 6, "one deterministic schedule exposes six genuinely different objective kinds")
	_test_identity_and_terminal(director, config, map)
	_test_capture_deadline(director, config, map)
	_test_six_interactions(director, config, map)
	_test_placement(director, config, map)
	director.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_OBJECTIVE_CONTRACT: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _complete(director: Node) -> void:
	var objective: Dictionary = director.get_snapshot()
	match StringName(objective.get("kind", &"")):
		&"capture_point": director.advance(float(objective["required"]) + 0.01, objective["target_position"])
		&"defeat_captain": director.report_captain_defeated(objective["target_id"])
		&"destroy_flag": director.report_flag_damage(objective["target_id"], 1000.0)
		&"relay_route":
			for step in 3: director.advance(1.3, director.get_snapshot()["target_position"])
		&"capture_storm": director.call("report_projectiles_absorbed", 12, objective["target_position"])
		&"clear_swarm":
			for index in 10: director.call("report_enemy_defeated", StringName("enemy_%s_%d" % [objective["id"], index]), false)


func _test_identity_and_terminal(director: Node, config: Resource, map: Resource) -> void:
	director.set_district_access({})
	director.reset(config, map, 2)
	var old_id := StringName(director.get_snapshot()["target_id"])
	_check(not director.report_flag_damage(&"", 2.0), "blank flag id is rejected")
	_check(not director.report_flag_damage(&"unrelated", 2.0), "unrelated flag cannot progress this task")
	_check(not director.report_flag_damage(old_id, INF) and not director.report_flag_damage(old_id, NAN), "nonfinite damage cannot satisfy a task")
	director.advance(5.0, director.get_snapshot()["target_position"])
	_check(is_zero_approx(float(director.get_snapshot()["progress"])), "proximity alone never damages a flag")
	director.reset(config, map, 2)
	var id := StringName(director.get_snapshot()["target_id"])
	_check(old_id != id and not director.report_flag_destroyed(old_id), "restarted run rejects the previous run's live target id")
	var completions: Array[Dictionary] = []
	var failures_seen: Array[Dictionary] = []
	var completed_callback := func(snapshot: Dictionary) -> void: completions.append(snapshot)
	var failed_callback := func(snapshot: Dictionary) -> void: failures_seen.append(snapshot)
	director.objective_completed.connect(completed_callback)
	director.objective_failed.connect(failed_callback)
	_check(director.report_flag_damage(id, 9999.0), "valid damage completes the exact active flag")
	_check(not director.report_flag_damage(id, 1.0) and not director.report_flag_destroyed(id), "same-frame and reward-paused late flag reports are ignored")
	director.call("_fail_current")
	_check(completions.size() == 1 and failures_seen.is_empty(), "a completed task cannot also time out in the same frame")
	_check(float(director.get_snapshot()["progress"]) == float(director.get_snapshot()["required"]), "overkill progress clamps to real required damage")
	director.reset(config, map, 2)
	id = StringName(director.get_snapshot()["target_id"])
	director.advance(config.objective_time_limit + 1.0, Vector2.ZERO)
	_check(not director.report_flag_damage(id, 9999.0), "a projectile arriving after timeout cannot award a reward")
	director.call("_fail_current")
	director.call("_complete_current")
	_check(failures_seen.size() == 1 and completions.size() == 1, "failed task is terminal and its failure signal is emitted once")
	_check(not director.get_snapshot()["target_active"] and director.get_snapshot()["protected_points"].is_empty(), "terminal task releases navigation and district protection")
	director.objective_completed.disconnect(completed_callback)
	director.objective_failed.disconnect(failed_callback)


func _test_capture_deadline(director: Node, config: Resource, map: Resource) -> void:
	var short_config: Resource = config.duplicate()
	short_config.objective_time_limit = 0.5
	short_config.capture_hold_seconds = 12.0
	director.reset(short_config, map, 0)
	director.advance(20.0, director.get_snapshot()["target_position"])
	var result: Dictionary = director.get_snapshot()
	_check(result["status"] == &"failed" and is_equal_approx(float(result["progress"]), 0.5), "large delta cannot add residence beyond the task deadline")
	director.reset(config, map, 0)
	var point := Vector2(director.get_snapshot()["target_position"])
	director.advance(3.0, point)
	director.advance(1.0, point + Vector2(500, 0))
	_check(is_equal_approx(float(director.get_snapshot()["progress"]), 2.65), "leaving a capture point preserves its intended gradual decay")
	var copy: Dictionary = director.get_snapshot()
	copy["targets"][0]["position"] = Vector2.ZERO
	_check(Vector2(director.get_snapshot()["targets"][0]["position"]) == point, "navigation snapshot edits cannot mutate live objective state")


func _test_six_interactions(director: Node, config: Resource, map: Resource) -> void:
	director.reset(config, map, 1)
	var captain := StringName(director.get_snapshot()["target_id"])
	_check(not director.report_enemy_defeated(captain, false), "a normal enemy event cannot masquerade as the task captain")
	var origin := Vector2(director.get_snapshot()["target_position"])
	var moved := origin + Vector2(80, 0)
	_check(director.update_target_position(captain, moved), "live captain reports its actual moving position")
	var protection: PackedVector2Array = director.get_snapshot()["protected_points"]
	_check(protection.has(origin) and protection.has(moved), "captain navigation moves while its original safe spawn remains protected")
	_check(director.report_enemy_defeated(captain, true), "real matching captain defeat completes the captain task")
	director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	_complete(director)
	director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	var route: Dictionary = director.get_snapshot()
	_check(route["kind"] == &"relay_route" and route["targets"].size() == 3, "relay exposes three real ordered destinations")
	_check(route["protected_points"].size() == 3, "all pending relay stops are protected before a closure starts")
	director.advance(1.3, route["targets"][1]["position"])
	_check(is_zero_approx(float(director.get_snapshot()["progress"])), "visiting a future relay stop cannot skip the first stop")
	director.advance(0.7, route["target_position"])
	director.advance(0.1, Vector2.ZERO)
	director.advance(0.6, route["target_position"])
	_check(is_zero_approx(float(director.get_snapshot()["progress"])), "leaving a relay point resets only its unfinished hold")
	_complete(director)
	director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	var storm: Dictionary = director.get_snapshot()
	_check(storm["kind"] == &"capture_storm", "relay rotates to the capture-skill task")
	_check(not director.report_projectiles_absorbed(12, Vector2(storm["target_position"]) + Vector2(241, 0)), "outside captures cannot advance the storm task")
	_check(not director.report_projectiles_absorbed(0, storm["target_position"]), "empty capture report awards no progress")
	director.report_projectiles_absorbed(4, storm["target_position"])
	_check(float(director.get_snapshot()["progress"]) == 4.0, "storm counts actually absorbed bullets rather than input presses")
	director.report_projectiles_absorbed(8, storm["target_position"])
	_check(not director.report_projectiles_absorbed(1, storm["target_position"]), "late captures cannot repeat a completed reward")
	director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	_check(director.get_snapshot()["kind"] == &"clear_swarm" and not director.get_snapshot()["target_active"], "global kill task has no fabricated map destination")
	_check(not director.report_enemy_defeated(&"", false), "anonymous kills cannot satisfy the kill task")
	_check(director.report_enemy_defeated(&"first", false) and not director.report_enemy_defeated(&"first", false), "one physical enemy can only be counted once")
	_check(float(director.get_snapshot()["progress"]) == 1.0, "duplicate defeat leaves kill progress unchanged")
	for index in 9:
		director.report_enemy_defeated(StringName("remaining_%d" % index), false)
	_check(director.get_snapshot()["completed"], "ten unique enemy defeats complete clear swarm")


func _test_placement(director: Node, config: Resource, map: Resource) -> void:
	var fixture: Resource = map.duplicate()
	fixture.walls.clear()
	fixture.capture_points = PackedVector2Array([Vector2(800, 800), Vector2(2000, 800), Vector2(3200, 800)])
	var access := {"zones": [
		{"state": &"warning", "rect": Rect2(500, 500, 600, 600)},
		{"state": &"closed", "rect": Rect2(1700, 500, 600, 600)},
	], "safe_corridors": []}
	director.set_district_access(access)
	director.reset(config, fixture, 0)
	_check(Vector2(director.get_snapshot()["target_position"]) == Vector2(3200, 800), "new tasks skip both warning and closed districts")
	access["zones"].append({"state": &"closed", "rect": fixture.bounds})
	director.set_district_access(access)
	_check(Vector2(director.get_snapshot()["target_position"]) == Vector2(3200, 800), "district updates never teleport an already active task")
	director.reset(config, fixture, 0)
	_check(director.get_snapshot()["kind"] == &"clear_swarm", "all sites blocked falls back to an achievable nonspatial task")
	access["safe_corridors"] = [Rect2(500, 500, 600, 600)]
	director.set_district_access(access)
	director.reset(config, fixture, 0)
	_check(director.get_snapshot()["kind"] == &"capture_point" and Vector2(director.get_snapshot()["target_position"]) == Vector2(800, 800), "permanent safe corridor wins over an overlapping closure")
	access["safe_corridors"] = [Rect2(760, 760, 80, 80)]
	director.set_district_access(access)
	director.reset(config, fixture, 0)
	_check(director.get_snapshot()["kind"] == &"clear_swarm", "tiny safe sliver cannot hide a task whose playable circle is unsafe")
	director.set_district_access({})
	director.reset(config, map, 771)
	var other := Director.new()
	root.add_child(other)
	other.reset(config, map, 771)
	var deterministic := true
	for index in 12:
		var a: Dictionary = director.get_snapshot()
		var b: Dictionary = other.get_snapshot()
		deterministic = deterministic and a["kind"] == b["kind"] and a["target_position"] == b["target_position"] and a["targets"].size() == b["targets"].size()
		# IDs intentionally include reset generation. Compare spatial data only.
		if a["targets"].size() == b["targets"].size():
			for target_index in a["targets"].size():
				deterministic = deterministic and a["targets"][target_index]["position"] == b["targets"][target_index]["position"]
		_complete(director)
		_complete(other)
		director.advance(config.objective_intermission + 0.1, Vector2.ZERO)
		other.advance(config.objective_intermission + 0.1, Vector2.ZERO)
	_check(deterministic, "equal run seeds preserve the full deterministic task and destination sequence")
	other.queue_free()

func _check(ok: bool, message: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + message)
	if not ok: failures.append(message)
