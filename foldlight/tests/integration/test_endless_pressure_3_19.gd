extends SceneTree

const Definition = preload("res://resources/endless/maps/solar_archipelago.tres")
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	_test_schedule()
	_test_seven_boss_rotation()
	var map := FoldlightEndlessHandcraftedMap.new()
	map.build_physics_walls = false
	root.add_child(map)
	map.configure(Definition)
	var barrage := FoldlightEndlessBombardment.new()
	root.add_child(barrage)
	_test_bombardment(barrage, map)
	barrage.queue_free()
	map.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_ENDLESS_PRESSURE_3_19: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_schedule() -> void:
	var director := FoldlightEndlessBossDirector.new()
	director.reset(319)
	_check(director.advance(0.1, 7, 4000.0).state == &"waiting", "a long run still cannot skip the first level-eight gate")
	director.reset(319)
	director.advance(0.1, 8, 100.0)
	_ready(director, 8, 103.0)
	_check(director.confirm_spawned([&"first"]) and director.report_defeated(&"first", 103.0), "a real first reservation is acknowledged and cleared")
	_check(director.advance(0.1, 8, 252.9).state == &"waiting", "early same-level follow-up waits for its longer timed interval")
	_check(director.advance(0.1, 8, 253.0).state == &"warning", "early timed follow-up begins after 150 combat seconds")
	_ready(director, 28, 256.0)
	_check(director.confirm_spawned([&"second"]), "level growth during a warning cannot expand its reserved count")
	_check(director.get_snapshot().next_level == 29, "late encounters advance the next earned threshold by one level")
	_check(director.report_defeated(&"second", 256.0), "the acknowledged wave completes exactly once")
	_check(director.advance(0.1, 29, 261.99).state == &"waiting", "earned late encounters still respect six seconds of recovery")
	_check(director.advance(0.1, 29, 262.0).state == &"warning", "a newly earned level starts the late encounter after recovery")
	var before := float(director.get_snapshot().warning_remaining)
	director.advance(20.0, 60, 900.0)
	_check(is_equal_approx(director.get_snapshot().warning_remaining, before - 0.1), "a delayed frame never consumes the whole arrival warning")
	_ready(director, 60, 900.0)
	_check(not director.confirm_spawned([&"partial"]), "partial spawn acknowledgements cannot activate a larger reservation")
	_check(not director.confirm_spawned([&"duplicate", &"duplicate", &"duplicate"]), "duplicate actors cannot consume a three-boss reservation")
	_check(director.confirm_spawned([&"a", &"b", &"c"]), "retry accepts all three unique reserved identities")
	director.advance(0.1, 90, 5000.0)
	_check(director.get_snapshot().state == &"active" and director.get_snapshot().active_count == 3 and director.get_snapshot().wave_index == 3, "elapsed time and level bursts never add unreserved bosses to an active wave")
	_check(not director.report_defeated(&"a", 5000.0) and not director.report_defeated(&"b", 5000.0), "partial clear does not pay or start a new-wave timer")
	_check(director.report_defeated(&"c", 5000.0) and not director.report_defeated(&"c", 5000.0), "final clear pays one wave completion and rejects replay")
	_check(director.advance(0.1, 90, 5005.99).state == &"waiting", "active-wave time cannot be banked to bypass post-clear recovery")
	director.reset(319)
	director.advance(0.1, 7, 1380.0)
	_check(is_equal_approx(director.encounter_interval(), 12.0) and is_equal_approx(director.recovery_interval(), 6.0), "long combat time also reaches the late pressure floors independently of leveling")


func _test_seven_boss_rotation() -> void:
	var director := FoldlightEndlessBossDirector.new()
	var twin := FoldlightEndlessBossDirector.new()
	director.reset(319)
	twin.reset(319)
	var seen: Dictionary = {}
	for wave in range(1, 9):
		var clock := 1000.0 + wave * 12.0
		director.advance(0.1, 50, clock)
		twin.advance(0.1, 50, clock)
		var plan := director.planned_boss_ids()
		_check(plan == twin.planned_boss_ids(), "same-seed wave %d reserves the same roster" % wave)
		var unique: Dictionary = {}
		for id in plan:
			unique[id] = true
			seen[id] = true
		_check(plan.size() == mini(wave, 6) and unique.size() == plan.size(), "wave %d grows with unique bosses without exceeding six" % wave)
		_ready(director, 50, clock)
		_ready(twin, 50, clock)
		var actors: Array[StringName] = []
		for index in plan.size():
			actors.append(StringName("%d_%d" % [wave, index]))
		_check(director.confirm_spawned(actors) and twin.confirm_spawned(actors), "both directors acknowledge every reserved identity")
		for actor in actors:
			director.report_defeated(actor, clock)
			twin.report_defeated(actor, clock)
	_check(seen.size() == 7 and seen.has(&"mirror_moth"), "deterministic rotation includes the mirror and all six existing bosses")


func _test_bombardment(barrage: FoldlightEndlessBombardment, map: FoldlightEndlessHandcraftedMap) -> void:
	var point: Vector2 = Definition.player_spawn
	barrage.configure(Definition, map, 319)
	barrage.advance(0.1, 10.0, point, PackedVector2Array(), 1)
	_check(barrage.get_snapshot().state == &"rest" and is_equal_approx(barrage.get_snapshot().next_at, 14.0), "boss arrival shortens only rest to at most four seconds")
	barrage.advance(0.1, 13.99, point, PackedVector2Array(), 1)
	_check(barrage.get_snapshot().state == &"rest", "arrival grace cannot be consumed before its combat-clock deadline")
	barrage.advance(0.1, 14.0, point, PackedVector2Array(), 1)
	var locked: Array = barrage.get_snapshot().zones
	_check(barrage.get_snapshot().state == &"warning" and locked.size() > 0 and locked.size() <= 2, "early boss combat enables a bounded visible bombardment")
	barrage.advance(0.0, 1000.0, point, PackedVector2Array(), 6)
	_check(is_equal_approx(barrage.get_snapshot().warning_remaining, 3.2), "a frozen visible clock preserves the complete warning")
	barrage.advance(20.0, 1000.0, point + Vector2(900, 0), PackedVector2Array(), 6)
	_check(barrage.get_snapshot().zones == locked and is_equal_approx(barrage.get_snapshot().warning_remaining, 3.1), "more bosses and player movement cannot relocate or skip a locked warning")
	var edges := 0
	for step in 40:
		edges += 1 if not barrage.advance(0.1, 1000.0, point, PackedVector2Array(), 6).is_empty() else 0
	_check(edges == 1 and barrage.get_snapshot().state == &"rest", "six-boss bombardment emits exactly one damage edge for the entire round")
	_check(is_equal_approx(barrage.get_snapshot().next_at, 1008.0), "deep boss combat rests eight seconds between completed rounds")
	_check(barrage.rest_interval(90.0, 1) == 14.0 and barrage.rest_interval(630.0, 6) == 8.0 and barrage.rest_interval(630.0, 0) > 8.0, "boss pressure progresses from fourteen to eight seconds and is faster than ordinary combat")
	barrage.advance(0.1, 1007.99, point, PackedVector2Array(), 6)
	_check(barrage.get_snapshot().state == &"rest", "late barrage cannot fire before the complete rest interval")
	barrage.advance(0.1, 1008.0, point, PackedVector2Array(), 6)
	_check(barrage.get_snapshot().state == &"warning" and is_equal_approx(barrage.get_snapshot().warning_remaining, 3.2), "six simultaneous bosses do not suppress the next fully warned barrage")
	barrage.cancel()
	barrage.advance(0.1, 5000.0, point, PackedVector2Array(), 6)
	_check(barrage.get_snapshot().state == &"rest" and barrage.get_snapshot().zones.is_empty() and barrage.get_snapshot().remaining == 0.0, "exit cancellation cannot leave or restart old landing sites")
	barrage.configure(Definition, map, 319)
	barrage.advance(0.1, 90.0, point, PackedVector2Array([point]), 6)
	var zones: Array = barrage.get_snapshot().zones
	var protected := true
	for i in zones.size():
		protected = protected and Vector2(zones[i].position).distance_to(point) >= float(zones[i].radius) + 300.0
		for j in range(i):
			protected = protected and Vector2(zones[i].position).distance_to(zones[j].position) >= float(zones[i].radius) * 2.0 + 70.0
	_check(protected and zones.size() <= 2 and barrage.get_snapshot().cycle == 1, "restart clears counters and retains protected escort routes plus separated boss landing sites")


func _ready(director: FoldlightEndlessBossDirector, level: int, clock: float) -> void:
	for step in 31:
		director.advance(0.1, level, clock)


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		_failures.append(label)
