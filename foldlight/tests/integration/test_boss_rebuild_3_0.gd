extends SceneTree

## Cross-version boss contract: three staged fights, bounded readable patterns,
## capped return-light burst, and authored arena restrictions. Region one was
## deliberately shortened to a 90-120 second onboarding boss in 3.5.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FoldlightRogueContentCatalog.BOSSES.size() == 3, "catalog ships exactly three region bosses")
	var arena_rules: Dictionary = {}
	var previous_health := 0.0
	for boss_index in FoldlightRogueContentCatalog.BOSSES.size():
		var definition := FoldlightRogueContentCatalog.BOSSES[boss_index]
		_check(definition.base_health > previous_health, "boss durability rises across the three regions")
		if boss_index == 0:
			_check(definition.target_duration >= 90.0 and definition.target_duration <= 120.0, "region-one boss stays in its authored 90-120 second onboarding band")
		else:
			_check(definition.target_duration >= 180.0 and definition.target_duration <= 330.0, "late boss target duration stays in the authored three-to-five-minute band")
		arena_rules[definition.arena_rule] = true
		previous_health = definition.base_health
	_check(arena_rules.size() == 3, "each boss owns a distinct arena rule")

	var boss_scene := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn") as PackedScene
	var reef := boss_scene.instantiate() as FoldlightRogueBossActor if boss_scene != null else null
	_check(reef != null, "reusable boss actor scene loads")
	if reef == null:
		_finish()
		return
	root.add_child(reef)
	reef.configure(FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery"), Rect2(Vector2.ZERO, Vector2(2880, 1620)), 81001)
	var phase_events: Array[int] = []
	var volleys: Array[Dictionary] = []
	var minions: Array[Dictionary] = []
	var telegraphs: Array[Dictionary] = []
	reef.phase_changed.connect(func(phase: int) -> void: phase_events.append(phase))
	reef.volley_requested.connect(func(snapshot: Dictionary) -> void: volleys.append(snapshot))
	reef.minion_requested.connect(func(snapshot: Dictionary) -> void: minions.append(snapshot))
	_check(reef.phase_controller.state == FoldlightBossPhaseController.State.INTRO, "boss begins with a non-damaging entrance beat")
	var health_before_return := reef.health
	reef.take_damage(999.0, &"return")
	_check(reef.health > 0.0 and health_before_return - reef.health < reef.definition.base_health * 0.30, "one return-light burst cannot instantly erase the boss")
	_check(reef.phase_controller.state == FoldlightBossPhaseController.State.STAGGERED, "large return pressure opens a bounded stagger window")
	var before_window_hit := reef.health
	reef.take_damage(9999.0, &"return")
	_check(before_window_hit - reef.health <= reef.definition.base_health * reef.definition.return_window_fraction + 0.01, "stagger return damage obeys the per-window cap")

	reef.health = reef.definition.base_health * 0.66
	reef.advance_simulation(0.01, Vector2(320, 810))
	_check(reef.phase_controller.phase_index == 1 and phase_events.has(1), "health threshold advances to a clearly signaled second phase")
	reef.health = reef.definition.base_health * 0.30
	reef.advance_simulation(0.01, Vector2(320, 810))
	_check(reef.phase_controller.phase_index == 2 and phase_events.has(2), "second threshold advances to the final phase")
	# Simulate with a separate fresh actor so prior forced staggers do not skew cadence.
	var simulation := boss_scene.instantiate() as FoldlightRogueBossActor
	root.add_child(simulation)
	simulation.configure(FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery"), Rect2(Vector2.ZERO, Vector2(2880, 1620)), 81002)
	simulation.health = simulation.definition.base_health * 0.30
	simulation.volley_requested.connect(func(snapshot: Dictionary) -> void: volleys.append(snapshot))
	simulation.minion_requested.connect(func(snapshot: Dictionary) -> void: minions.append(snapshot))
	simulation.telegraph_requested.connect(func(snapshot: Dictionary) -> void: telegraphs.append(snapshot))
	for _step in 600:
		simulation.advance_simulation(0.1, Vector2(420, 810))
	_check(not volleys.is_empty(), "boss simulation emits sustained authored projectile patterns")
	_check(volleys.all(func(snapshot: Dictionary) -> bool: return int(snapshot.get("projectile_count", 0)) <= 18 and float(snapshot.get("telegraph", 0.0)) >= 0.55), "every boss volley keeps a bounded count and explicit warning")
	_check(volleys.any(func(snapshot: Dictionary) -> bool: return bool(snapshot.get("reflectable", false))) and volleys.any(func(snapshot: Dictionary) -> bool: return not bool(snapshot.get("reflectable", true))), "boss patterns clearly mix reflectable and unreflectable threats")
	_check(not minions.is_empty() and minions.all(func(snapshot: Dictionary) -> bool: return int(snapshot.get("maximum", 0)) <= 4 and int(snapshot.get("total_maximum", 6)) <= 6), "Reef-Crown support packs and turrets stay inside the six-enemy arena quota")
	_check(not telegraphs.is_empty() and telegraphs.all(func(snapshot: Dictionary) -> bool: return float(snapshot.get("duration", 0.0)) >= 0.55 and snapshot.has("target_position")), "boss attacks publish timed target-aware warning snapshots")
	var attack_warning_scene := load("res://scenes/roguelite/bosses/boss_attack_telegraph.tscn") as PackedScene
	var attack_warning := attack_warning_scene.instantiate() as FoldlightBossAttackTelegraph if attack_warning_scene != null else null
	_check(attack_warning != null, "boss warning visual loads as a finished scene")
	if attack_warning != null and not telegraphs.is_empty():
		root.add_child(attack_warning)
		attack_warning.configure(telegraphs[0])
		_check(attack_warning.duration >= 0.55 and attack_warning.target_position == Vector2(420, 810), "warning visual preserves attack timing and aim")
		attack_warning.queue_free()
	var reef_center := reef.arena_controller.room_bounds.get_center()
	reef.arena_controller.set_phase(2)
	_check(reef.arena_controller.is_player_safe(reef_center), "Reef-Crown tide warning never deals hidden early damage")
	reef.arena_controller.advance_simulation(2.5, reef_center)
	reef.arena_controller.advance_simulation(1.4, reef_center)
	var tide_snapshot := reef.arena_controller.get_rule_snapshot()
	var tide_angle := float(tide_snapshot.get("safe_gap_angle", 0.0)) + PI
	var tide_point := reef_center + Vector2.from_angle(tide_angle) * float(tide_snapshot.get("pulse_radius", 0.0))
	_check(tide_snapshot.get("hazard_state", &"") == &"surge" and not reef.arena_controller.is_player_safe(tide_point), "Reef-Crown visible tide ring is a real movement constraint")

	var judge := boss_scene.instantiate() as FoldlightRogueBossActor
	root.add_child(judge)
	judge.configure(FoldlightRogueContentCatalog.boss_by_id(&"origami_judge"), Rect2(Vector2.ZERO, Vector2(2880, 1620)), 91003)
	var phase_one_frame := Rect2(judge.arena_controller.get_rule_snapshot().get("safe_rect", Rect2()))
	judge.health = judge.definition.base_health * 0.3
	judge.advance_simulation(0.01, Vector2(1440, 810))
	judge.arena_controller.advance_simulation(3.0, Vector2(1440, 810))
	var final_frame := Rect2(judge.arena_controller.get_rule_snapshot().get("safe_rect", Rect2()))
	_check(final_frame.size.x < phase_one_frame.size.x and final_frame.size.y < phase_one_frame.size.y, "Origami Judge materially shrinks the legal movement frame")
	var frame_position_before := final_frame.position
	judge.arena_controller.advance_simulation(2.0, Vector2(1440, 810))
	var moved_frame := Rect2(judge.arena_controller.get_rule_snapshot().get("safe_rect", Rect2()))
	_check(moved_frame.position.distance_to(frame_position_before) > 10.0, "final safe frame moves instead of rewarding stationary play")
	_check(not judge.arena_controller.is_player_safe(Vector2(40, 40)), "space outside the framed arena is explicitly unsafe")

	reef.queue_free()
	simulation.queue_free()
	judge.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_BOSS_REBUILD_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_BOSS_REBUILD_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
