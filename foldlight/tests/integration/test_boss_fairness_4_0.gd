extends SceneTree

## Exercise warning -> volley, real Fold -> return missiles, phase transitions,
## and hazard clocks. These are behavior contracts rather than damage snapshots.
const STEP: float = 1.0 / 60.0
const BOUNDS := Rect2(0, 0, 2880, 1620)
const BOSS_SCENE: PackedScene = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
var _failures: Array[String] = []
var _checks: int = 0
var _burst_snapshot: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	for definition in FoldlightRogueContentCatalog.BOSSES:
		_test_locked_casts(definition)
		await _test_full_fold_cycle(definition)
	_test_phase_reward_and_hazard_rest()
	_test_arena_transitions()
	_test_tide_reachability()
	await _test_delayed_burst_origin()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_FAIRNESS_4_0: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)


func _boss(definition: FoldlightRogueBossDefinition) -> FoldlightRogueBossActor:
	var result := BOSS_SCENE.instantiate() as FoldlightRogueBossActor
	root.add_child(result)
	result.configure(definition, BOUNDS, 20261014)
	return result


func _test_locked_casts(definition: FoldlightRogueBossDefinition) -> void:
	var boss := _boss(definition)
	boss.health = definition.base_health * 0.30
	var state: Dictionary = {"warning": {}, "patterns": {}, "volleys": 0, "origins_match": true, "aims_match": true, "fan_matches": true, "zones_match": true, "cast_stationary": true, "retarget_challenged": false, "support_bounded": true}
	boss.telegraph_requested.connect(func(warning: Dictionary) -> void:
		state["warning"] = warning.duplicate(true)
		(state["patterns"] as Dictionary)[warning["pattern_id"]] = true
	)
	boss.volley_requested.connect(func(volley: Dictionary) -> void:
		var warning: Dictionary = state["warning"]
		state["volleys"] = int(state["volleys"]) + 1
		var warned_origin := Vector2(warning["origin"])
		var warned_target := Vector2(warning["target_position"])
		state["origins_match"] = bool(state["origins_match"]) and Vector2(volley["origin"]).is_equal_approx(warned_origin)
		state["aims_match"] = bool(state["aims_match"]) and Vector2(volley["direction"]).is_equal_approx(warned_origin.direction_to(warned_target))
		state["retarget_challenged"] = bool(state["retarget_challenged"]) or warned_target.distance_to(boss._target_position) > 100.0
		if not bool(volley["reflectable"]):
			state["fan_matches"] = bool(state["fan_matches"]) and is_equal_approx(float(volley["spread_radians"]), float(warning["spread_radians"])) and float(warning["duration"]) >= 1.17
		if _burst_snapshot.is_empty() and int(volley.get("burst_count", 1)) > 1:
			_burst_snapshot = volley.duplicate(true)
	)
	boss.zone_requested.connect(func(zone: Dictionary) -> void:
		var warning: Dictionary = state["warning"]
		state["zones_match"] = bool(state["zones_match"]) and Vector2(zone["position"]).is_equal_approx(Vector2(warning["target_position"])) and is_equal_approx(float(zone["radius"]), float(warning["zone_radius"]))
	)
	boss.minion_requested.connect(func(support: Dictionary) -> void:
		state["support_bounded"] = bool(state["support_bounded"]) and int(support["total_maximum"]) <= 4
	)
	for tick in 1800:
		var target := BOUNDS.get_center() + Vector2.from_angle(float(tick) * 0.008) * 500.0
		boss.advance_simulation(STEP, target)
		if boss.phase_controller.state == FoldlightBossPhaseController.State.TELEGRAPH:
			var warning: Dictionary = state["warning"]
			state["cast_stationary"] = bool(state["cast_stationary"]) and boss.global_position.is_equal_approx(Vector2(warning["origin"])) and boss.velocity.is_zero_approx()
	var name := String(definition.content_id)
	_check(int(state["volleys"]) > 5 and (state["patterns"] as Dictionary).size() == definition.pattern_ids.size(), name + ": every authored pattern reaches its firing state")
	_check(bool(state["retarget_challenged"]) and bool(state["aims_match"]), name + ": dodging after the warning never redirects the attack")
	_check(bool(state["origins_match"]) and bool(state["cast_stationary"]), name + ": moving body stops at the warned firing origin")
	_check(bool(state["fan_matches"]), name + ": black-gold fan width and extra warning match its real volley")
	_check(bool(state["zones_match"]), name + ": ink zones resolve at the warned position and radius")
	_check(bool(state["support_bounded"]), name + ": support cannot exceed four concurrent helpers")
	boss.queue_free()


func _test_full_fold_cycle(definition: FoldlightRogueBossDefinition) -> void:
	var room := load("res://scenes/roguelite/room_runtime.tscn").instantiate() as FoldlightRoomRuntime
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	var combat := FoldlightRogueCombatRuntime.new()
	root.add_child(room)
	root.add_child(player)
	root.add_child(combat)
	room.configure_room(&"fold_fairness", BOUNDS.size, [], definition.accent)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	player.global_position = BOUNDS.get_center() + Vector2(0, 370)
	combat.bind(room, player)
	combat.set_physics_process(false)
	var boss := _boss(definition)
	combat.enemies.append(boss)
	var state := {"release": 0, "first_stagger": false, "second_hits": 0, "full_second_damage": true, "clock": 0.0, "first_release_time": 0.0, "second_release_time": 0.0}
	boss.stagger_started.connect(func(_duration: float) -> void: state["first_stagger"] = true)
	player.fold_released.connect(func(_count: int, _ratio: float) -> void:
		state["release"] = int(state["release"]) + 1
		state["first_release_time" if int(state["release"]) == 1 else "second_release_time"] = state["clock"]
	)
	boss.damaged.connect(func(amount: float, _health: float, source: StringName) -> void:
		if source == &"return" and int(state["release"]) == 2:
			state["second_hits"] = int(state["second_hits"]) + 1
			state["full_second_damage"] = bool(state["full_second_damage"]) and is_equal_approx(amount, 2.8) and boss.phase_controller.state == FoldlightBossPhaseController.State.STAGGERED
	)
	for cycle in 2:
		for wait_tick in 180:
			if player.fold_component.can_begin():
				break
			_tick_fold_cycle(player, combat, boss, state)
		_check(player.try_begin_fold(), "%s: full Fold cycle %d can begin after its real cooldown" % [definition.content_id, cycle + 1])
		combat.spawn_hostile_volley({"origin": player.global_position + Vector2(80, 0), "projectile_count": player.get_capture_capacity(), "direction": Vector2.RIGHT, "speed": 0.0, "reflectable": true})
		for charge_tick in 180:
			_tick_fold_cycle(player, combat, boss, state)
			if player.get_charge_ratio() >= 1.0:
				break
		_check(player.captured == 8 and is_equal_approx(player.get_charge_ratio(), 1.0), "%s: Fold cycle %d physically captures and fully charges eight projectiles" % [definition.content_id, cycle + 1])
		if cycle == 1:
			_check(bool(state["first_stagger"]), String(definition.content_id) + ": one basic full store opens the stagger window")
		player.release_fold_action()
	for flight_tick in 240:
		_tick_fold_cycle(player, combat, boss, state)
		if combat.projectiles.is_empty():
			break
	var release_interval := float(state["second_release_time"]) - float(state["first_release_time"])
	_check(release_interval >= 3.04, String(definition.content_id) + ": second release pays both cooldown and full charge time")
	_check(int(state["second_hits"]) == 8 and bool(state["full_second_damage"]), String(definition.content_id) + ": all eight real follow-up return missiles arrive inside the earned window at full damage")
	combat.clear_combat()
	combat.queue_free()
	player.queue_free()
	room.queue_free()
	await process_frame


func _tick_fold_cycle(player: FoldlightPlayer, combat: FoldlightRogueCombatRuntime, boss: FoldlightRogueBossActor, state: Dictionary) -> void:
	state["clock"] = float(state["clock"]) + STEP
	player._physics_process(STEP)
	boss.advance_simulation(STEP, player.global_position)
	combat._update_projectiles(STEP)


func _test_phase_reward_and_hazard_rest() -> void:
	var definition := FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery")
	var boss := _boss(definition)
	var arena_hits: Array[int] = []
	boss.arena_hit_requested.connect(func() -> void: arena_hits.append(1))
	boss.arena_controller.tide_state = FoldlightBossArenaController.TideState.SURGE
	boss.arena_controller.pulse_radius = 500.0
	var danger_point := BOUNDS.get_center() + Vector2(500, 0)
	boss.advance_simulation(0.5, danger_point)
	_check(arena_hits.is_empty() and is_zero_approx(boss.arena_controller.elapsed), "introduction freezes arena clocks and cannot hurt the player")
	boss.health = definition.base_health * 0.69
	boss.take_damage(22.4, &"return")
	var health_after_opening := boss.health
	boss.advance_simulation(0.02, danger_point)
	_check(boss.phase_controller.phase_index == 0 and int(boss.phase_controller.get_state_snapshot()["pending_phase"]) == 1, "return crossing the health line queues phase change behind its earned window")
	boss.take_damage(22.4, &"return")
	_check(is_equal_approx(health_after_opening - boss.health, 22.4), "crossing the threshold keeps full return damage available")
	boss.advance_simulation(3.0, danger_point)
	_check(boss.phase_controller.state == FoldlightBossPhaseController.State.STAGGERED and arena_hits.is_empty() and is_zero_approx(boss.arena_controller.elapsed), "arena pressure stays frozen throughout stagger")
	boss.advance_simulation(0.4, danger_point)
	_check(boss.phase_controller.phase_index == 1 and boss.phase_controller.state == FoldlightBossPhaseController.State.RECOVERY, "deferred phase change runs after the full stagger window")
	_check(boss.arena_controller.tide_state == FoldlightBossArenaController.TideState.REST and boss.arena_controller.is_player_safe(danger_point), "phase transition resets an old surge instead of resuming it beneath the player")
	boss.queue_free()


func _test_arena_transitions() -> void:
	var arena := FoldlightBossArenaController.new()
	root.add_child(arena)
	arena.configure(&"moving_safe_frame", BOUNDS)
	var before := arena.safe_rect
	var old_edge := before.end - Vector2.ONE * 10.0
	arena.set_phase(2)
	_check(arena.safe_rect == before, "phase change does not teleport the Judge frame")
	arena.advance_simulation(0.75, old_edge)
	_check(arena.safe_rect.size.x < before.size.x and arena.safe_rect.size.x > 1100.0 and arena.is_player_safe(old_edge), "Judge frame visibly folds inward during a harmless transition")
	arena.advance_simulation(0.76, old_edge)
	_check(arena.safe_rect.size == Vector2(1100, 660) and not arena.is_player_safe(old_edge), "new Judge boundary becomes harmful only after the transition")
	arena.configure(&"ink_partitions", BOUNDS)
	arena.set_phase(1)
	_check(arena.is_player_safe(BOUNDS.get_center()), "new Archivist ink wall grants time to leave its newly marked strip")
	arena.advance_simulation(1.51, BOUNDS.get_center())
	_check(not arena.is_player_safe(BOUNDS.get_center()), "ink wall becomes a real restriction after its warning grace")
	arena.queue_free()


func _test_tide_reachability() -> void:
	var arena := FoldlightBossArenaController.new()
	root.add_child(arena)
	for phase in 3:
		arena.configure(&"reef_tide_pulse", BOUNDS)
		arena.set_phase(phase)
		var player_position := BOUNDS.position + Vector2(90, 90)
		var relative := player_position - BOUNDS.get_center()
		arena.advance_simulation(arena.tide_remaining, player_position)
		var warning := arena.get_rule_snapshot()
		var angular_distance := maxf(0.0, absf(wrapf(relative.angle() - float(warning["safe_gap_angle"]), -PI, PI)) - float(warning["safe_gap_half_angle"]))
		var path_to_gap := angular_distance * relative.length()
		_check(path_to_gap < FoldlightPlayer.MOVE_SPEED * arena.TIDE_TELEGRAPH_DURATION, "reef phase %d: a player near the far corner can reach the warned gap at normal speed" % (phase + 1))
	arena.queue_free()


func _test_delayed_burst_origin() -> void:
	_check(not _burst_snapshot.is_empty(), "a natural boss warning supplies a real multi-burst volley for runtime validation")
	if _burst_snapshot.is_empty():
		return
	var room := load("res://scenes/roguelite/room_runtime.tscn").instantiate() as FoldlightRoomRuntime
	var combat := FoldlightRogueCombatRuntime.new()
	root.add_child(room)
	root.add_child(combat)
	room.configure_room(&"burst_fairness", BOUNDS.size, [], Color.WHITE)
	combat.bind(room, null)
	combat.set_physics_process(false)
	combat.spawn_hostile_volley(_burst_snapshot)
	var origin := Vector2(_burst_snapshot["origin"])
	var preserved := true
	var delayed := 0
	for projectile in combat.projectiles:
		preserved = preserved and projectile.global_position.is_equal_approx(origin)
		if projectile.launch_delay > 0.0:
			delayed += 1
			var direction := projectile.velocity.normalized()
			projectile.advance_simulation(projectile.launch_delay * 0.5)
			preserved = preserved and projectile.global_position.is_equal_approx(origin)
			projectile.advance_simulation(projectile.launch_delay + 0.01)
			preserved = preserved and projectile.global_position.distance_to(origin + direction * projectile.velocity.length() * 0.01) < 0.2
	_check(delayed > 0 and preserved, "later runtime bursts retain the original warning origin and trajectory through their launch delay")
	combat.clear_combat()
	combat.queue_free()
	room.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("[FAIL] " + label)
	else:
		print("[PASS] " + label)
