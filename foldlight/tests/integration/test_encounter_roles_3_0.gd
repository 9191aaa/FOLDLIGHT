extends SceneTree

## 3.0 encounter contract: deterministic threat composition, safe spawns, and
## three immediately legible mechanic roles with hard simultaneous quotas.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := FoldlightEncounterDirector.new()
	root.add_child(director)
	var slots := _make_slots()
	var blockers: Array[Rect2] = [Rect2(Vector2(1260, 690), Vector2(360, 240))]
	var reef := FoldlightRogueContentCatalog.encounter_by_id(&"reef_crossfire")
	var city := FoldlightRogueContentCatalog.encounter_by_id(&"ink_city_order")
	var court := FoldlightRogueContentCatalog.encounter_by_id(&"sun_court_verdict")
	_check(reef != null and city != null and court != null, "catalog exposes one authored encounter spine per region")
	_check(FoldlightRogueContentCatalog.ENEMIES.size() >= 5, "catalog ships fodder, charger, turret, buffer, and controller roles")
	_check(FoldlightRogueContentCatalog.validation_errors().is_empty(), "enemy and encounter references pass catalog validation")
	if reef == null or city == null or court == null:
		_finish()
		return

	var plan_a := director.compose_encounter(reef, FoldlightRogueContentCatalog.ENEMIES, 55001, 1, slots, Vector2(240, 810), blockers)
	var plan_b := director.compose_encounter(reef, FoldlightRogueContentCatalog.ENEMIES, 55001, 1, slots, Vector2(240, 810), blockers)
	_check(plan_a == plan_b, "the same seed produces an identical enemy, wave, and spawn-slot plan")
	_check((plan_a.get("errors", []) as Array).is_empty(), "valid authored slots produce a composition without errors")
	_assert_plan_contract(plan_a, reef, Vector2(240, 810), blockers)

	var intro := director.compose_encounter(city, FoldlightRogueContentCatalog.ENEMIES, 71007, 2, slots, Vector2(240, 810), blockers, FoldlightRogueEnemyDefinition.EnemyRole.TURRET)
	var intro_counts := intro.get("role_counts", {}) as Dictionary
	_check(int(intro_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.TURRET, 0)) == 1, "introduction encounter presents exactly one requested mechanic")
	_check(int(intro_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, 0)) == 0 and int(intro_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, 0)) == 0, "introduction encounter pairs the mechanic only with ordinary support")

	var seen_roles: Dictionary = {}
	for seed_offset in 24:
		var plan := director.compose_encounter(court, FoldlightRogueContentCatalog.ENEMIES, 99000 + seed_offset, 3, slots, Vector2(240, 810), blockers)
		_assert_plan_contract(plan, court, Vector2(240, 810), blockers)
		for entry_variant: Variant in plan.get("entries", []):
			var entry := entry_variant as Dictionary
			seen_roles[int(entry.get("role", -1))] = true
	_check(seen_roles.has(FoldlightRogueEnemyDefinition.EnemyRole.TURRET), "seed variation schedules stationary turret pressure")
	_check(seen_roles.has(FoldlightRogueEnemyDefinition.EnemyRole.BUFFER), "seed variation schedules visible enemy buffs")
	_check(seen_roles.has(FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER), "seed variation schedules temporary space denial")

	var cramped_slots: Array[Dictionary] = [
		{"id": &"too_close", "position": Vector2(300, 810), "kind": &"ground"},
		{"id": &"inside_wall", "position": Vector2(1400, 780), "kind": &"ground"},
	]
	var invalid := director.compose_encounter(reef, FoldlightRogueContentCatalog.ENEMIES, 1, 1, cramped_slots, Vector2(240, 810), blockers)
	_check(not (invalid.get("errors", []) as Array).is_empty(), "director rejects a room without safe spawn capacity")

	var intro_tracker := FoldlightMechanicIntroductionTracker.new()
	root.add_child(intro_tracker)
	for mechanic_id in [&"paper_turret", &"bell_binder", &"ink_warden"]:
		var mechanic_definition := FoldlightRogueContentCatalog.enemy_by_id(mechanic_id)
		var card := intro_tracker.request_introduction(mechanic_definition)
		_check(not String(card.get("rule", "")).is_empty() and not String(card.get("counterplay", "")).is_empty(), "mechanic archive card teaches one rule and one response")
		_check(intro_tracker.request_introduction(mechanic_definition).is_empty(), "mechanic introduction never interrupts twice")
	_check(intro_tracker.make_snapshot().size() == 3, "introduced mechanic IDs serialize independently from scene nodes")

	await _test_mechanic_scenes()
	intro_tracker.queue_free()
	director.queue_free()
	await process_frame
	_finish()


func _assert_plan_contract(plan: Dictionary, definition: FoldlightRogueEncounterDefinition, player_position: Vector2, blockers: Array[Rect2]) -> void:
	var entries: Array = plan.get("entries", [])
	var spent := int(plan.get("spent", 0))
	var role_counts := plan.get("role_counts", {}) as Dictionary
	_check(spent <= definition.threat_budget and spent >= int(ceil(float(definition.threat_budget) * 0.75)), "composition spends 75-100 percent of its threat budget")
	_check(entries.size() <= FoldlightEncounterDirector.MAX_LIVE_ENEMIES, "composition never exceeds the live-enemy readability cap")
	var fodder_threat := 0
	var wave_slots: Dictionary = {}
	var player_clear := true
	var terrain_clear := true
	var wave_slots_unique := true
	for entry_variant: Variant in entries:
		var entry := entry_variant as Dictionary
		if int(entry.get("role", -1)) == FoldlightRogueEnemyDefinition.EnemyRole.FODDER:
			fodder_threat += int(entry.get("threat_cost", 0))
		var spawn_position := Vector2(entry.get("spawn_position", Vector2.ZERO))
		player_clear = player_clear and spawn_position.distance_to(player_position) >= FoldlightEncounterDirector.MIN_PLAYER_SPAWN_DISTANCE
		var clear := true
		for blocker in blockers:
			clear = clear and FoldlightEncounterDirector.distance_to_rect(spawn_position, blocker) >= FoldlightEncounterDirector.MIN_TERRAIN_SPAWN_DISTANCE
		terrain_clear = terrain_clear and clear
		var wave := int(entry.get("wave", 0))
		var slot_key := "%d:%s" % [wave, String(entry.get("spawn_slot", &""))]
		wave_slots_unique = wave_slots_unique and not wave_slots.has(slot_key)
		wave_slots[slot_key] = true
	_check(player_clear, "all spawns keep their player telegraph distance")
	_check(terrain_clear, "all spawns keep their terrain clearance")
	_check(wave_slots_unique, "spawn slots stay unique inside each wave")
	_check(spent > 0 and float(fodder_threat) / float(spent) + 0.001 >= definition.minimum_fodder_ratio, "ordinary enemies retain the authored minimum threat share")
	_check(int(role_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, 0)) <= definition.controller_quota, "controller quota is enforced")
	_check(int(role_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, 0)) <= definition.buffer_quota, "buffer quota is enforced")
	_check(int(role_counts.get(FoldlightRogueEnemyDefinition.EnemyRole.TURRET, 0)) <= definition.turret_quota, "turret quota is enforced")


func _test_mechanic_scenes() -> void:
	var turret_scene := load("res://scenes/roguelite/enemies/paper_turret.tscn") as PackedScene
	var turret := turret_scene.instantiate() as FoldlightPaperTurret if turret_scene != null else null
	_check(turret != null, "Paper Turret scene loads as a stationary combat actor")
	if turret != null:
		root.add_child(turret)
		var volleys: Array[Dictionary] = []
		turret.volley_requested.connect(func(snapshot: Dictionary) -> void: volleys.append(snapshot))
		_check(turret.phase == FoldlightPaperTurret.Phase.TELEGRAPH, "turret begins with a readable lane telegraph")
		turret.advance_simulation(turret.telegraph_duration + 0.01, Vector2(900, 0))
		_check(volleys.size() == 1 and int(volleys[0].get("projectile_count", 0)) == 5, "turret telegraph resolves to one bounded five-shot volley")
		turret.advance_simulation(turret.volley_duration + 0.01, Vector2(900, 0))
		_check(turret.phase == FoldlightPaperTurret.Phase.EXPOSED and turret.damage_multiplier() > 1.0, "turret exposes a clear punish window after firing")
		turret.queue_free()

	var binder_scene := load("res://scenes/roguelite/enemies/bell_binder.tscn") as PackedScene
	var binder := binder_scene.instantiate() as FoldlightBellBinder if binder_scene != null else null
	_check(binder != null, "Bell Binder scene loads")
	if binder != null:
		root.add_child(binder)
		binder.global_position = Vector2(500, 500)
		var candidates: Array[Dictionary] = [
			{"id": &"near_a", "position": Vector2(610, 500), "alive": true, "role": FoldlightRogueEnemyDefinition.EnemyRole.FODDER},
			{"id": &"near_b", "position": Vector2(680, 540), "alive": true, "role": FoldlightRogueEnemyDefinition.EnemyRole.TURRET},
			{"id": &"near_c", "position": Vector2(720, 600), "alive": true, "role": FoldlightRogueEnemyDefinition.EnemyRole.CHARGER},
			{"id": &"far", "position": Vector2(1500, 500), "alive": true, "role": FoldlightRogueEnemyDefinition.EnemyRole.FODDER},
		]
		binder.update_tethers(candidates)
		_check(binder.get_tether_ids().size() == 2 and not binder.get_tether_ids().has(&"far"), "binder shows at most two local buff tethers")
		var buff := binder.get_buff_snapshot()
		_check(float(buff.get("attack_interval_multiplier", 1.0)) < 1.0 and float(buff.get("move_speed_multiplier", 1.0)) > 1.0, "binder buff has an explicit reusable data snapshot")
		binder.queue_free()

	var warden_scene := load("res://scenes/roguelite/enemies/ink_warden.tscn") as PackedScene
	var warden := warden_scene.instantiate() as FoldlightInkWarden if warden_scene != null else null
	_check(warden != null, "Ink Warden scene loads")
	if warden != null:
		root.add_child(warden)
		var zones: Array[Dictionary] = []
		warden.zone_requested.connect(func(snapshot: Dictionary) -> void: zones.append(snapshot))
		warden.begin_cast(Vector2(960, 540))
		warden.advance_simulation(warden.telegraph_duration + 0.01, Vector2.ZERO)
		_check(zones.size() == 1 and float(zones[0].get("radius", 0.0)) <= 210.0, "warden creates one bounded zone only after its telegraph")
		_check(float(zones[0].get("duration", 0.0)) <= 5.0, "denial zone is temporary rather than permanent floor loss")
		warden.queue_free()
	await process_frame


func _make_slots() -> Array[Dictionary]:
	return [
		{"id": &"g1", "position": Vector2(620, 310), "kind": &"ground"},
		{"id": &"g2", "position": Vector2(980, 310), "kind": &"ground"},
		{"id": &"g3", "position": Vector2(1880, 310), "kind": &"ground"},
		{"id": &"g4", "position": Vector2(2300, 390), "kind": &"ground"},
		{"id": &"g5", "position": Vector2(620, 1280), "kind": &"ground"},
		{"id": &"g6", "position": Vector2(1060, 1280), "kind": &"ground"},
		{"id": &"g7", "position": Vector2(1920, 1260), "kind": &"ground"},
		{"id": &"g8", "position": Vector2(2420, 1180), "kind": &"ground"},
		{"id": &"g9", "position": Vector2(420, 560), "kind": &"ground"},
		{"id": &"g10", "position": Vector2(840, 760), "kind": &"ground"},
		{"id": &"g11", "position": Vector2(2040, 760), "kind": &"ground"},
		{"id": &"g12", "position": Vector2(2520, 660), "kind": &"ground"},
		{"id": &"g13", "position": Vector2(460, 1040), "kind": &"ground"},
		{"id": &"g14", "position": Vector2(2380, 980), "kind": &"ground"},
		{"id": &"t1", "position": Vector2(2740, 370), "kind": &"turret"},
		{"id": &"t2", "position": Vector2(2740, 1260), "kind": &"turret"},
	]


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ENCOUNTER_ROLES_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENCOUNTER_ROLES_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
