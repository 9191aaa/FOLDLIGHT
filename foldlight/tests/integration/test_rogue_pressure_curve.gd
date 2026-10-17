extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	session.set_physics_process(false)
	var valid := true
	var pressure_met := true
	var mechanic_kept := true
	var openers_active := true
	var first_room_safe := true
	var count := 0
	for region in 3:
		var last_depth := FoldlightRogueContentCatalog.REGIONS[region].depth_count - 2
		for depth in last_depth + 1:
			for sample in 16:
				var category := &"entry" if depth == 0 else (&"elite" if depth == last_depth else &"combat")
				var plan := _plan(session, region, depth, category, sample)
				var entries: Array = plan.get("entries", [])
				valid = valid and plan.get("errors", []).is_empty() and entries.size() <= 32 and int(plan["spent"]) <= int(plan["budget"])
				var pressure_count := _pressure_count(entries)
				pressure_met = pressure_met and pressure_count >= int(plan["pressure_target"])
				if region > 0 or depth >= 4:
					mechanic_kept = mechanic_kept and entries.any(func(entry: Dictionary) -> bool: return int(entry["role"]) in [3, 4, 5, 6])
				if region == 0 and depth == 0:
					first_room_safe = first_room_safe and int(plan["budget"]) == 23 and is_zero_approx(float(plan["reinforcement_interval"])) and entries.all(func(entry: Dictionary) -> bool: return entry["enemy_id"] in [&"drifter", &"fan"])
				else:
					openers_active = openers_active and entries.any(func(entry: Dictionary) -> bool: return int(entry["wave"]) == 0 and int(entry["role"]) in [1, 2])
				var waves: Dictionary = {}
				for entry: Dictionary in entries:
					waves[entry["wave"]] = int(waves.get(entry["wave"], 0)) + 1
				valid = valid and waves.values().all(func(size: int) -> bool: return size > 0 and size <= 16)
				count += 1
			await process_frame
	_check(count == 304 and valid, "304 cross-region plans fit their budgets, spawn capacity and wave cap")
	_check(pressure_met and mechanic_kept, "every sampled plan meets pressure floors while retaining an eligible mechanic")
	_check(openers_active, "all post-introduction openers contain a shooter or charger")
	_check(first_room_safe, "first room retains its old budget, two enemy types and kill-driven pacing")
	var category_rows: Array[Dictionary] = []
	var category_layers := true
	for region in 3:
		var averages: Dictionary = {}
		for category in [&"rest", &"cache", &"shop", &"combat", &"event", &"elite"]:
			var pressure_total := 0
			var body_total := 0
			var budget := 0
			var interval := 0.0
			for sample in 16:
				var plan := _plan(session, region, 4, category, sample)
				valid = valid and plan["errors"].is_empty()
				pressure_total += _pressure_count(plan["entries"])
				body_total += plan["entries"].size()
				budget = int(plan["budget"])
				interval = float(plan["reinforcement_interval"])
			averages[category] = float(pressure_total) / 16.0
			var row := {"region":region+1,"depth":4,"category":category,"samples":16,"pressure":float(pressure_total)/16.0,"bodies":float(body_total)/16.0,"budget":budget,"reinforcement_interval":interval}
			category_rows.append(row)
			print("CATEGORY_SAMPLE %s" % JSON.stringify(row))
		category_layers = category_layers and float(averages[&"rest"]) < float(averages[&"combat"]) and float(averages[&"combat"]) < float(averages[&"elite"])
	_check(valid and category_layers, "288 category samples preserve rest < combat < elite pressure in every region")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/test-runtime/difficulty-audit"))
	var file := FileAccess.open("res://build/test-runtime/difficulty-audit/categories.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(category_rows, "\t"))
	file.close()
	var low_budget := FoldlightRogueContentCatalog.encounter_by_id(&"reef_crossfire").duplicate(true) as FoldlightRogueEncounterDefinition
	low_budget.threat_budget = 18
	low_budget.minimum_pressure_count = 8
	low_budget.minimum_fodder_ratio = 0.40
	low_budget.enemy_ids = [&"drifter", &"fan", &"ram", &"paper_turret"]
	var fallback := session.encounter_director.compose_encounter(low_budget, FoldlightRogueContentCatalog.ENEMIES, 55001, 1, session._spawn_slots(), session.player.global_position, session.world.room_runtime.get_solid_terrain_bounds(22.0), FoldlightRogueEnemyDefinition.EnemyRole.TURRET)
	_check(fallback["errors"].is_empty() and int(fallback["role_counts"].get(FoldlightRogueEnemyDefinition.EnemyRole.TURRET, 0)) == 1, "insufficient pressure budget preserves the required mechanic introduction")
	game.queue_free()
	await process_frame
	_test_wave_limits()
	_test_dynamic_spawn_warning()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_ROGUE_PRESSURE_CURVE: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _plan(session: FoldlightRogueSessionController, region: int, depth: int, category: StringName, sample: int) -> Dictionary:
	session.mode = FoldlightRogueSessionController.SessionMode.RUN
	session.run_controller.run_state.current_region = region
	session.run_controller.run_state.seed = 91800 + sample * 7919
	var room := {"id": StringName("audit_%d_%d_%d" % [region, depth, sample]), "depth": depth, "category": category, "risk": region + 1 + int(depth / 2)}
	session._on_room_requested(room, {})
	return session._encounter_plan(room)


func _pressure_count(entries: Array) -> int:
	return entries.filter(func(entry: Dictionary) -> bool: return int(entry["role"]) in [1, 2]).size()


func _test_wave_limits() -> void:
	var runtime := FoldlightRoomEncounterRuntime.new()
	root.add_child(runtime)
	var spawned: Array[Dictionary] = []
	var clears: Array[Dictionary] = []
	runtime.enemy_spawn_requested.connect(func(entry: Dictionary) -> void: spawned.append(entry))
	runtime.encounter_cleared.connect(func(performance: Dictionary) -> void: clears.append(performance))
	_check(runtime.configure(_waves([9, 8, 5], 2.0, 6)).is_empty() and runtime.begin(), "timed encounter begins")
	runtime.advance_simulation(0.71)
	runtime.advance_simulation(2.1)
	_check(runtime.state == runtime.State.ACTIVE and runtime.current_wave == 0, "elapsed reinforcement waits while the next wave would exceed 16")
	runtime.notify_enemy_defeated(1)
	_check(runtime.state == runtime.State.TELEGRAPHING and runtime.projected_enemy_count() == 16, "timer plus one defeat reserves exactly 16 active and incoming wave units")
	runtime.advance_simulation(0.35)
	runtime.notify_enemy_defeated(8)
	_check(runtime.state == runtime.State.TELEGRAPHING and runtime.projected_enemy_count() == 8, "killing every survivor retains the warned incoming wave")
	runtime.advance_simulation(0.36)
	runtime.advance_simulation(2.1)
	_check(runtime.state == runtime.State.TELEGRAPHING and runtime.projected_enemy_count() == 13, "timer maintains pressure when more than the kill threshold survive")
	runtime.notify_enemy_defeated(8)
	runtime.advance_simulation(0.71)
	runtime.notify_enemy_defeated(5)
	_check(runtime.state == runtime.State.CLEARED and spawned.size() == 22 and clears.size() == 1, "zero survivors during telegraph still reaches one complete clear")
	runtime.configure(_waves([12, 12], 0.0, 6))
	runtime.begin()
	runtime.advance_simulation(0.71)
	runtime.notify_enemy_defeated(6)
	_check(runtime.state == runtime.State.ACTIVE, "kill-triggered reinforcement also waits above the 16-unit cap")
	runtime.notify_enemy_defeated(2)
	_check(runtime.state == runtime.State.TELEGRAPHING and runtime.projected_enemy_count() == 16, "kill-triggered reinforcement begins only once capacity is available")
	var legacy_plan := _waves([20, 1], 0.0, 4)
	legacy_plan.erase("maximum_active_enemies")
	legacy_plan.erase("reinforcement_interval")
	legacy_plan.erase("reinforcement_threshold")
	_check(runtime.configure(legacy_plan).is_empty() and runtime.maximum_active_enemies == 0 and is_zero_approx(runtime.reinforcement_interval), "plans without expedition pacing fields retain legacy wave capacity and no timer")
	runtime.begin()
	runtime.advance_simulation(0.71)
	runtime.advance_simulation(20.0)
	_check(runtime.active_enemy_count == 20 and runtime.current_wave == 0, "legacy authored waves are neither capped at 16 nor reinforced on a timer")
	runtime.queue_free()


func _waves(sizes: Array[int], interval: float, threshold: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	for wave in sizes.size():
		for index in sizes[wave]:
			entries.append({"enemy_id": &"drifter", "wave": wave, "spawn_position": Vector2(500 + index * 80, 500)})
	return {"entries":entries,"reinforcement_interval":interval,"reinforcement_threshold":threshold,"maximum_active_enemies":16}


func _test_dynamic_spawn_warning() -> void:
	var runtime := FoldlightRoomEncounterRuntime.new()
	var player := Node2D.new()
	root.add_child(runtime)
	root.add_child(player)
	player.position = Vector2(500, 500)
	var blockers: Array[Rect2] = [Rect2(Vector2(650, 450), Vector2(200, 200))]
	runtime.set_spawn_safety(player, Rect2(Vector2(80, 80), Vector2(1840, 1040)), blockers)
	var warnings: Array[Dictionary] = []
	var spawned: Array[Dictionary] = []
	runtime.spawn_telegraph_requested.connect(func(entry: Dictionary, duration: float) -> void: warnings.append({"entry":entry,"duration":duration}))
	runtime.enemy_spawn_requested.connect(func(entry: Dictionary) -> void: spawned.append(entry))
	runtime.telegraph_duration = 0.1
	runtime.configure(_waves([1], 0.0, 4))
	runtime.begin()
	var warned_position := Vector2(warnings[0]["entry"]["spawn_position"])
	_check(warned_position.distance_to(player.position) >= 180.0 and FoldlightEncounterDirector.distance_to_rect(warned_position, blockers[0]) >= 100.0, "spawn warning relocates away from the current player and solid terrain")
	_check(float(warnings[0]["duration"]) >= 0.7, "all reinforcement warnings keep at least 0.7 seconds")
	player.position = Vector2(1200, 900)
	runtime.advance_simulation(0.71)
	_check(spawned.size() == 1 and Vector2(spawned[0]["spawn_position"]) == warned_position, "landing matches the visible warning instead of chasing the player")
	runtime.queue_free()
	player.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
