extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var definition := FoldlightRogueContentCatalog.enemy_by_id(&"shutter_seraph")
	_check(definition != null, "new elite is registered in the playable catalog")
	if definition == null:
		quit(1)
		return
	_check(definition.validation_errors().is_empty(), "new elite resource validates")
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	session.set_physics_process(false)
	for region in 3:
		for category: StringName in [&"entry", &"combat", &"elite"]:
			for seed_value in [31, 97, 331]:
				session.run_controller.run_state.current_region = region
				session.run_controller.run_state.seed = seed_value
				var room := {"id": &"seraph_audit", "depth": 4, "category": category, "risk": region + 3}
				session._on_room_requested(room, {})
				var plan := session._encounter_plan(room)
				var entries: Array = plan.get("entries", [])
				var elites: Array = entries.filter(func(entry: Dictionary) -> bool: return entry.get("enemy_id") == &"shutter_seraph")
				var expected := 1 if region > 0 and category == &"elite" else 0
				_check(plan.get("errors", []).is_empty() and int(plan["spent"]) <= int(plan["budget"]) and elites.size() == expected, "region %d / %s / seed %d keeps elite count and threat budget" % [region + 1, category, seed_value])
	var tracker := FoldlightMechanicIntroductionTracker.new()
	root.add_child(tracker)
	var briefing := tracker.request_introduction(definition)
	_check(briefing.get("attack_style") == &"exposure_barrage" and not str(briefing.get("counterplay", "")).is_empty(), "first encounter explains the open-wing damage window")
	_check(tracker.request_introduction(definition).is_empty(), "elite briefing is shown once")
	tracker.queue_free()
	game.queue_free()
	await process_frame
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.start_slice(331)
	slice.controller.set_process(false)
	slice.world.deactivate()
	var controller := slice.controller
	controller.enemy_wave_requested.disconnect(slice._on_enemy_wave_requested)
	# The paused fixture still has its initial captain in the arrival queue.
	# Acknowledge that actor for the planner, as live gameplay does on arrival.
	controller.confirm_captain_spawned(StringName(controller.objectives.get_snapshot().get("target_id", &"")))
	var no_early_elites := true
	for index in 8:
		# Pure planning has no actor factory to consume/report reservations.
		controller.report_population({})
		var request := controller._emit_next_wave()
		no_early_elites = no_early_elites and _elite_entries(request).is_empty()
	_check(no_early_elites, "opening endless waves cannot roll an invulnerable elite")
	controller.evolution.advance_survival(105.0)
	controller.wave_sequence = 11
	controller.report_population({})
	var first := controller._emit_next_wave()
	_check(_elite_entries(first).size() == 1, "105-second endless wave introduces one elite")
	controller.wave_sequence = 11
	controller.report_population({})
	var same := controller._emit_next_wave()
	_check(_elite_entries(first) == _elite_entries(same), "same seed and wave select the same elite placement")
	slice.world.activate()
	slice._on_enemy_wave_requested(first)
	slice._on_enemy_wave_requested(first)
	for warning_step in 16:
		slice._advance_spawn_queue(0.1)
	_check(slice.combat_runtime.enemies.filter(func(enemy: Node) -> bool: return enemy.definition.content_id == &"shutter_seraph").size() == 1, "repeated waves cannot overlap two live barrage elites")
	slice.start_slice(331)
	_check(slice.combat_runtime.enemies.is_empty(), "restart clears the old elite along with combat")
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await create_timer(1.0).timeout
	print("FOLDLIGHT_SHUTTER_SERAPH_PLACEMENT: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _elite_entries(request: Dictionary) -> Array:
	return (request.get("entries", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("enemy_id") == &"shutter_seraph")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
