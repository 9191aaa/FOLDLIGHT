extends SceneTree

## 3.0 foundation contract: typed content, deterministic route/run state, and v5 migration.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var regions: Array[FoldlightRogueRegionDefinition] = []
	for index in 3:
		var region := FoldlightRogueRegionDefinition.new()
		region.content_id = StringName("region_%d" % (index + 1))
		region.title = "测试海域 %d" % (index + 1)
		region.depth_count = 7
		region.base_threat_budget = 8 + index * 3
		region.boss_ids = [StringName("boss_%d" % (index + 1))]
		regions.append(region)

	var generator := FoldlightRogueRouteGenerator.new()
	root.add_child(generator)
	var route_a := generator.generate_route(330031, regions)
	var route_b := generator.generate_route(330031, regions)
	var route_c := generator.generate_route(330032, regions)
	_check(route_a == route_b, "same seed produces an identical three-region route snapshot")
	_check(route_a != route_c, "different seed changes at least one branch or room category")
	_check((route_a.get("regions", []) as Array).size() == 3, "route contains exactly three authored regions")
	for region_variant in route_a.get("regions", []):
		var region_snapshot := region_variant as Dictionary
		_check(_region_reaches_boss(region_snapshot), "every generated region has a reachable boss")
		_check((region_snapshot.get("nodes", []) as Array).size() >= 7, "each region exposes a sustained multi-room route")

	var run_state := FoldlightRogueRunState.new()
	root.add_child(run_state)
	run_state.begin_run(330031, route_a)
	run_state.current_region = 1
	run_state.current_node_id = &"r2_d3_a"
	run_state.room_count = 8
	run_state.glimmer = 17
	run_state.weapon_ids = [&"crease_lantern", &"needle_orbit"]
	run_state.active_item_id = &"paper_burst"
	run_state.apply_upgrade(&"swift_wing")
	run_state.apply_upgrade(&"swift_wing")
	var checkpoint := run_state.make_checkpoint()
	var restored := FoldlightRogueRunState.new()
	root.add_child(restored)
	_check(restored.restore_checkpoint(checkpoint), "cleared-room run checkpoint restores through its public API")
	_check(restored.seed == 330031 and restored.current_region == 1 and restored.room_count == 8, "checkpoint restores route position and deterministic seed")
	_check(restored.weapon_ids == run_state.weapon_ids and restored.get_upgrade_level(&"swift_wing") == 2, "checkpoint restores weapons, active item, and stacked run upgrades")
	checkpoint["glimmer"] = 999
	_check(restored.glimmer == 17, "restored run state owns a deep copy of serialized data")

	var weapon := FoldlightRogueWeaponDefinition.new()
	weapon.content_id = &"crease_lantern"
	weapon.title = "折灯"
	weapon.fire_interval = 0.55
	weapon.base_damage = 1.0
	_check(weapon.validation_errors().is_empty(), "valid automatic weapon definition passes typed validation")
	weapon.fire_interval = 0.0
	_check(not weapon.validation_errors().is_empty(), "invalid weapon cadence is rejected before entering the catalog")

	var profile_manager := FoldlightProfileManager.new()
	profile_manager.persistence_enabled = false
	root.add_child(profile_manager)
	var legacy_campaign := {"unlocked_missions": ["c1m1", "c1m2"], "completed": {"c1m1": {"clears": 1}}, "reward_grants": [], "campaign_complete": false, "campaign_seconds": 420.0, "active_checkpoint": {}, "failure_counts": {}, "assisted_missions": []}
	var legacy_challenge := {"runs": 4, "best_time": 321.0, "best_score": 9999, "best_tier": 7, "total_events": 13}
	var migrated := profile_manager._migrate_profile({"version": 5, "meta_upgrades": {"crease_rebuke": 1}, "campaign": legacy_campaign, "challenge": legacy_challenge, "tutorial_complete": true})
	_check(int(migrated.get("version", 0)) == 6, "version-five profile migrates to the 3.0 schema")
	_check((migrated.get("campaign", {}) as Dictionary).get("completed", {}) == legacy_campaign["completed"], "v6 migration preserves classic campaign completion")
	_check(int((migrated.get("challenge", {}) as Dictionary).get("best_score", 0)) == 9999, "v6 migration preserves 2.1 challenge records")
	var rogue_profile := migrated.get("roguelite", {}) as Dictionary
	_check(rogue_profile.has("unlocked_weapons") and rogue_profile.has("active_run") and not bool(rogue_profile.get("prologue_complete", true)), "v6 migration supplies safe roguelite defaults")
	_check(FoldlightRogueContentCatalog.validation_errors().is_empty(), "starter regions, weapon, active item, upgrades, and bosses form a valid typed catalog")
	_check(FoldlightRogueContentCatalog.REGIONS.size() == 3 and FoldlightRogueContentCatalog.BOSSES.size() == 3, "catalog ships the three-region and three-boss product spine")
	profile_manager.profile = migrated.duplicate(true)
	_check(profile_manager.commit_roguelite_checkpoint(restored.make_checkpoint(), false), "profile accepts a valid cleared-room roguelite checkpoint")
	_check(not (profile_manager.get_roguelite_snapshot().get("active_run", {}) as Dictionary).is_empty(), "roguelite checkpoint is isolated inside its profile branch")
	_check((profile_manager.get_campaign_snapshot().get("active_checkpoint", {}) as Dictionary).is_empty(), "standalone roguelite profile operations never synthesize a campaign checkpoint")

	var packed := load("res://scenes/main.tscn") as PackedScene
	var game: FoldlightGame = packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "main composition loads with the dormant 3.0 runtime")
	if game != null:
		root.add_child(game)
		await process_frame
		var rogue_controller := game.get_node("RogueRunController") as FoldlightRogueRunController
		_check(rogue_controller.phase == FoldlightRogueRunController.Phase.INACTIVE and game.mode == FoldlightGame.RunMode.TITLE, "roguelite runtime stays dormant while Classic/title owns the game")
		var first_room_signals := [0]
		rogue_controller.room_requested.connect(func(_room: Dictionary, _region: Dictionary) -> void: first_room_signals[0] += 1)
		var start_snapshot := rogue_controller.start_new_run(60603)
		_check(not start_snapshot.is_empty() and first_room_signals[0] == 1, "isolated run controller starts a deterministic first room")
		_check(game.mode == FoldlightGame.RunMode.TITLE, "starting the isolated controller does not mutate legacy mode state before title integration")
		game.queue_free()

	generator.queue_free()
	run_state.queue_free()
	restored.queue_free()
	profile_manager.queue_free()
	await process_frame
	_finish()


func _region_reaches_boss(region_snapshot: Dictionary) -> bool:
	var nodes: Array = region_snapshot.get("nodes", [])
	var by_id: Dictionary = {}
	for node_variant in nodes:
		var node := node_variant as Dictionary
		by_id[String(node.get("id", ""))] = node
	var frontier: Array[String] = [String(region_snapshot.get("start_id", ""))]
	var visited: Dictionary = {}
	while not frontier.is_empty():
		var node_id := String(frontier.pop_front())
		if visited.has(node_id) or not by_id.has(node_id):
			continue
		visited[node_id] = true
		var node: Dictionary = by_id[node_id]
		if StringName(node.get("category", &"")) == &"boss":
			return true
		var exits_variant: Variant = node.get("exits", [])
		if exits_variant is Array:
			for exit_id: Variant in exits_variant:
				frontier.append(String(exit_id))
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ROGUELITE_FOUNDATION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUELITE_FOUNDATION: FAIL — %s" % ", ".join(_failures))
		quit(1)
