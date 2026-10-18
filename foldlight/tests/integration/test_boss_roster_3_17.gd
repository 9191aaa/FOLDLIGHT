extends SceneTree

const Geometry = preload("res://scripts/roguelite/bosses/boss_pattern_geometry.gd")
const BOSS = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
const STEP := 1.0 / 60.0
const WORLD := Rect2(0, 0, 4800, 3200)
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_test_catalog_and_plans()
	for boss_id in Geometry.NEW_IDS:
		_test_scaled_instances_and_pause(boss_id)
	_test_delayed_cancellation()
	_test_dash_and_navigation()
	_test_intro_offsets()
	_test_roaming_support()
	_test_first_encounter()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_ROSTER_3_17: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _boss(boss_id: StringName, options: Dictionary = {}) -> FoldlightRogueBossActor:
	var actor := BOSS.instantiate() as FoldlightRogueBossActor
	root.add_child(actor)
	actor.configure(FoldlightRogueContentCatalog.boss_by_id(boss_id), WORLD, 31701, options)
	return actor


func _test_catalog_and_plans() -> void:
	_check(FoldlightRogueContentCatalog.validation_errors().is_empty(), "seven boss resources validate together")
	var legacy: Array[StringName] = [&"reef_crown_battery", &"inverted_archivist", &"origami_judge"]
	for index in 3:
		var region := FoldlightRogueContentCatalog.REGIONS[index]
		seed(317)
		var expected := randi()
		seed(317)
		var options := FoldlightRogueContentCatalog.boss_options_for_region(region.content_id)
		_check(options.size() >= 2 and options[0].content_id == legacy[index] and options[1].content_id == Geometry.NEW_IDS[index], "%s retains its old primary and previous region alternative" % region.content_id)
		_check(randi() == expected, "catalog lookup does not consume the seeded gameplay sequence")
	for boss_id in Geometry.NEW_IDS:
		var definition := FoldlightRogueContentCatalog.boss_by_id(boss_id)
		for pattern in definition.pattern_ids:
			var plan := Geometry.build(pattern, Vector2(2000, 1400), Vector2(2300, 1750), 2, 0, WORLD.grow(-100))
			var bullets := 0
			var latest := 0.0
			for pending: Dictionary in plan["volleys"]:
				bullets += int(pending["snapshot"]["projectile_count"])
				latest = maxf(latest, float(pending["at"]))
			_check(not (plan["lanes"] as Array).is_empty() and bullets <= 18 and latest < definition.get_active_seconds(pattern), "%s publishes a bounded fully warned attack inside its active window" % pattern)
			if pattern in [&"loom_shuttle", &"loom_crossweave", &"execution_counterfold", &"bell_alternation", &"eclipse_procession"]:
				_check(not (plan["gaps"] as Array).is_empty(), "%s explicitly marks its authored passage" % pattern)
	var left := Geometry.build(&"bell_alternation", Vector2.ZERO, Vector2.DOWN*400.0, 1, 0, WORLD)
	var right := Geometry.build(&"bell_alternation", Vector2.ZERO, Vector2.DOWN*400.0, 1, 1, WORLD)
	_check(Vector2(left["volleys"][0]["snapshot"]["origin"]).x < 0.0 and Vector2(right["volleys"][0]["snapshot"]["origin"]).x > 0.0, "twin bells alternate the first firing side deterministically")


func _test_scaled_instances_and_pause(boss_id: StringName) -> void:
	var definition := FoldlightRogueContentCatalog.boss_by_id(boss_id)
	var original_health := definition.base_health
	var local := Rect2(600, 500, 1800, 1400)
	var actor := _boss(boss_id, {"health_scale": 0.65, "local_arena": local, "endless_roam": true, "arena_pressure": false})
	var sibling := _boss(boss_id, {"health_scale": 1.2})
	_check(is_equal_approx(actor.maximum_health, original_health*0.65) and is_equal_approx(sibling.maximum_health, original_health*1.2) and is_equal_approx(definition.base_health, original_health), "%s per-instance health never mutates the shared resource" % boss_id)
	var snapshot := actor.get_combat_snapshot()
	_check(snapshot["title"] == definition.title and snapshot["maximum_health"] == actor.maximum_health and snapshot["phase"] == 0 and not snapshot["defeated"], "%s publishes real scaled independent HUD values" % boss_id)
	actor.global_position = Vector2(3700, 2300)
	actor._clamp_to_active_arena()
	_check(actor.global_position.is_equal_approx(Vector2(3700, 2300)), "%s can leave the initial local arena in endless mode" % boss_id)
	var arena_hits: Array[int] = []
	actor.arena_hit_requested.connect(func() -> void: arena_hits.append(1))
	actor.health = actor.maximum_health*0.3
	actor.advance_simulation(STEP, Vector2(4500, 2900))
	_check(actor.phase_controller.phase_index == 2 and not actor.arena_controller.visible and arena_hits.is_empty(), "%s scaled phase thresholds keep endless arena restrictions disabled" % boss_id)
	actor.set_simulation_active(false)
	var before := actor.phase_controller.get_state_snapshot()
	var position_before := actor.global_position
	actor.advance_simulation(5.0, Vector2.ZERO)
	_check(actor.phase_controller.get_state_snapshot() == before and actor.global_position == position_before, "%s pause stops attack clocks and movement" % boss_id)
	actor.configure(definition, WORLD)
	_check(actor.maximum_health == original_health and not actor._endless_roam and actor.arena_controller.visible and actor._pending_volleys.is_empty(), "%s reconfigure restores normal rogue defaults" % boss_id)
	actor.queue_free()
	sibling.queue_free()


func _test_delayed_cancellation() -> void:
	for cancel_reason in [&"stagger", &"phase", &"death"]:
		var actor := _boss(&"eclipse_twin_bells")
		var events: Array[Dictionary] = []
		var warnings: Array[Dictionary] = []
		actor.volley_requested.connect(func(event: Dictionary) -> void: events.append(event))
		actor.telegraph_requested.connect(func(event: Dictionary) -> void: warnings.append(event))
		for tick in 210:
			actor.advance_simulation(STEP, actor.global_position+Vector2(0,450))
			if not events.is_empty(): break
		_check(events.size() == 1 and actor._pending_volleys.size() == 1, "%s cancellation fixture reaches a real first bell with its second pending" % cancel_reason)
		_check(not warnings.is_empty() and is_equal_approx(float(warnings[0]["duration"]), actor.definition.telegraph_seconds) and float(warnings[0]["duration"]) >= 1.0, "paired attacks provide their full authored warning before the first pulse")
		var warning := FoldlightBossAttackTelegraph.new()
		root.add_child(warning)
		warning.configure(warnings[0])
		_check(warning.get_visual_contract()["attack_lanes"] == warnings[0]["attack_lanes"] and warning.remaining > warning.duration, "warning preserves both exact bell sources until the active pair ends")
		warning.set_simulation_active(false)
		var warning_before := warning.remaining
		warning._process(0.5)
		_check(warning.remaining == warning_before, "paused multi-source warning does not expire early")
		warning.queue_free()
		match cancel_reason:
			&"stagger": actor.take_damage(22.4, &"return")
			&"phase": actor.health = actor.maximum_health*0.30
			&"death": actor.take_damage(actor.maximum_health*2.0, &"weapon")
		for tick in 48:
			actor.advance_simulation(STEP, actor.global_position+Vector2(0,450))
		_check(events.size() == 1 and actor._pending_volleys.is_empty(), "%s cancels the queued second bell without residual bullets" % cancel_reason)
		actor.queue_free()


func _test_dash_and_navigation() -> void:
	var actor := _boss(&"torn_page_executioner", {"endless_roam": true, "arena_pressure": false})
	var warnings: Array[Dictionary] = []
	actor.telegraph_requested.connect(func(event: Dictionary) -> void: warnings.append(event))
	var target := actor.global_position+Vector2(500,0)
	for tick in 190:
		actor.advance_simulation(STEP, target)
		if actor.phase_controller.state == FoldlightBossPhaseController.State.ATTACK: break
	var start := Vector2(warnings[0]["origin"])
	var end := Vector2(warnings[0]["attack_lanes"][0]["end"])
	var inside_corridor := true
	for tick in 36:
		actor.advance_simulation(STEP, start+Vector2(-500,700))
		inside_corridor = inside_corridor and absf(actor.global_position.y-start.y) < 3.0 and actor.global_position.x <= end.x+3.0
	_check(inside_corridor and actor.global_position.x > start.x+400.0, "executioner follows the locked dash despite a moving target and stops without overshoot")
	actor.phase_controller.state = FoldlightBossPhaseController.State.RECOVERY
	actor.phase_controller._remaining = 5.0
	actor.velocity = Vector2.ZERO
	actor.set_navigation_target(actor.global_position+Vector2(0,-400))
	actor.advance_simulation(STEP, actor.global_position+Vector2(1000,0))
	_check(actor.velocity.y < 0.0 and is_zero_approx(actor.velocity.x), "far pursuit follows navigation waypoint while keeping target aim separate")
	actor.queue_free()


func _test_intro_offsets() -> void:
	var first := _boss(&"tide_loom_mother")
	var second := _boss(&"tide_loom_mother", {"intro_delay": 0.65})
	first.advance_simulation(1.4, Vector2(2800,1600))
	second.advance_simulation(1.4, Vector2(2800,1600))
	_check(first.phase_controller.state == FoldlightBossPhaseController.State.TELEGRAPH and second.phase_controller.state == FoldlightBossPhaseController.State.INTRO, "multi-boss entrance offsets prevent synchronized first attacks")
	first.queue_free()
	second.queue_free()


func _test_roaming_support() -> void:
	var actor := _boss(&"inverted_archivist", {"endless_roam": true, "arena_pressure": false, "local_arena": Rect2(200,200,1800,1400)})
	actor.global_position = Vector2(4100,2300)
	var packs: Array[Dictionary] = []
	actor.minion_requested.connect(func(pack: Dictionary) -> void: packs.append(pack))
	actor.request_opening_support()
	var near_actor := packs.size() == 1
	if near_actor:
		for point: Vector2 in packs[0]["positions"]:
			near_actor = near_actor and point.distance_to(actor.global_position) < 700.0 and WORLD.grow(-99.0).has_point(point)
	_check(near_actor, "roaming archivist summons near its current body inside world boundaries")
	actor.queue_free()


func _test_first_encounter() -> void:
	var tracker := FoldlightMechanicIntroductionTracker.new()
	root.add_child(tracker)
	for boss_id in Geometry.NEW_IDS:
		var definition := FoldlightRogueContentCatalog.boss_by_id(boss_id)
		var card := tracker.request_boss_introduction(definition)
		var preview := FoldlightMechanicPreviewCanvas.new()
		root.add_child(preview)
		preview.configure({"preview_id": boss_id})
		var state := preview.get_preview_snapshot()
		_check(state["preview_kind"] == &"boss" and state["attack_style"] == card["attack_style"] and card["attack_style"] != &"boss_pattern" and not str(card["counterplay"]).is_empty(), "%s first encounter uses its own paper model, attack demonstration and counterplay" % boss_id)
		_check(tracker.request_boss_introduction(definition).is_empty(), "%s briefing is shown only once per run" % boss_id)
		preview.queue_free()
	tracker.queue_free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("[FAIL] "+label)
	else:
		print("[PASS] "+label)
