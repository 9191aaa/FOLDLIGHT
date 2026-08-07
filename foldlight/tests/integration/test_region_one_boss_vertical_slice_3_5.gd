extends SceneTree

## Region-one vertical-slice contract: 2.0 enemies arrive in readable pairs,
## the first boss rewards folding instead of becoming a 210-second health wall,
## and its arena pressure is a warned tide surge rather than continuous lasers.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "release scene loads for region-one boss vertical slice")
	if game == null:
		_finish()
		return
	root.add_child(game)
	await process_frame
	await process_frame

	var session := game.rogue_session as FoldlightRogueSessionController
	var tier_zero: Array[StringName] = session.call("_enemy_ids_for_room", &"paper_reef", 0, &"entry")
	var tier_one: Array[StringName] = session.call("_enemy_ids_for_room", &"paper_reef", 2, &"combat")
	var tier_two: Array[StringName] = session.call("_enemy_ids_for_room", &"paper_reef", 4, &"combat")
	var elite_pool: Array[StringName] = session.call("_enemy_ids_for_room", &"paper_reef", 5, &"elite")
	_check(tier_zero == [&"drifter", &"fan"], "first two rooms teach two familiar 2.0 enemies")
	_check(_contains_all(tier_one, [&"drifter", &"fan", &"ram", &"bloomer"]) and tier_one.size() == 4, "rooms three and four introduce exactly two more readable enemies")
	_check(_contains_all(tier_two, [&"weaver", &"paper_turret"]) and tier_two.size() == 6, "rooms five and six introduce a final pair instead of dumping the full catalog")
	_check(elite_pool.has(&"brood_lantern"), "the priority summoner is reserved as an elite-room escalation")

	var boss_definition := FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery")
	_check(boss_definition != null, "reef crown boss definition remains catalogued")
	if boss_definition != null:
		_check(boss_definition.base_health >= 440.0 and boss_definition.base_health <= 500.0, "first boss health preserves the later anti-drag tuning without becoming trivial")
		_check(boss_definition.target_duration >= 90.0 and boss_definition.target_duration <= 120.0, "first boss target duration is 90 to 120 seconds")
		_check(boss_definition.return_window_seconds >= 2.0 and boss_definition.return_window_fraction >= 0.18, "fold stagger grants a readable burst-damage window")
		_check(boss_definition.return_damage_outside_stagger >= 0.5, "reflected ammunition remains meaningful outside stagger")
		_check(boss_definition.pattern_ids == [&"petal_salvo", &"tide_fan", &"turret_crown", &"black_lane"], "boss phases introduce ammo, turrets, then black-gold pressure in order")

	var arena := FoldlightBossArenaController.new()
	root.add_child(arena)
	arena.configure(&"reef_tide_pulse", Rect2(Vector2.ZERO, Vector2(2880.0, 1620.0)))
	var center := Vector2(1440.0, 810.0)
	_check(arena.is_player_safe(center + Vector2(500.0, 0.0)), "tide arena is harmless during its rest interval")
	arena.advance_simulation(4.0, center)
	var warning_snapshot := arena.get_rule_snapshot()
	_check(StringName(warning_snapshot.get("hazard_state", &"")) == &"telegraph", "periodic tide surge enters an explicit warning state")
	_check(arena.is_player_safe(center + Vector2(500.0, 0.0)), "warning graphics never deal early damage")
	arena.advance_simulation(1.2, center)
	var surge_snapshot := arena.get_rule_snapshot()
	_check(StringName(surge_snapshot.get("hazard_state", &"")) == &"surge", "warning resolves into a short expanding shockwave")
	var surge_radius := float(surge_snapshot.get("pulse_radius", 0.0))
	_check(not arena.is_player_safe(center + Vector2(surge_radius, 0.0)), "only the visible shockwave ring is dangerous")
	_check(arena.is_player_safe(center), "space inside the moving ring remains safe")

	if boss_definition != null:
		var boss_scene := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn") as PackedScene
		var boss := boss_scene.instantiate() as FoldlightRogueBossActor
		root.add_child(boss)
		boss.configure(boss_definition, Rect2(Vector2.ZERO, Vector2(2880.0, 1620.0)), 3500)
		var volleys: Array[Dictionary] = []
		var support_requests: Array[Dictionary] = []
		boss.volley_requested.connect(func(snapshot: Dictionary) -> void: volleys.append(snapshot.duplicate(true)))
		boss.minion_requested.connect(func(snapshot: Dictionary) -> void: support_requests.append(snapshot.duplicate(true)))
		boss._emit_reef_pattern(&"petal_salvo", 0.9)
		_check(not volleys.is_empty() and bool(volleys[-1].get("reflectable", false)) and int(volleys[-1].get("burst_count", 1)) >= 3, "opening salvo supplies several readable waves of fold ammunition")
		_check(not support_requests.is_empty() and (support_requests[-1].get("enemy_ids", []) as Array).size() >= 2, "opening boss pattern replenishes a mixed familiar support pack")
		boss.phase_controller.phase_index = 2
		boss._emit_reef_pattern(&"black_lane", 0.7)
		_check(not volleys.is_empty() and not bool(volleys[-1].get("reflectable", true)), "black-gold lane remains a late clearly unreflectable movement check")
		boss.queue_free()

	arena.queue_free()
	game.queue_free()
	await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _contains_all(values: Array[StringName], expected: Array[StringName]) -> bool:
	for value: StringName in expected:
		if not values.has(value):
			return false
	return true


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_REGION_ONE_BOSS_VERTICAL_SLICE_3_5: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REGION_ONE_BOSS_VERTICAL_SLICE_3_5: FAIL - %s" % ", ".join(_failures))
		quit(1)
