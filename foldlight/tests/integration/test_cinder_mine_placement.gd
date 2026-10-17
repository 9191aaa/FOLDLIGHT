extends SceneTree

var failures: Array[String] = []


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
	var later_bombers := 0
	for region in 3:
		for depth in [0, 1, 3]:
			for seed_value in [31, 97, 331]:
				session.run_controller.run_state.current_region = region
				session.run_controller.run_state.seed = seed_value
				var room := {"id": &"bomber_audit", "depth": depth, "category": &"combat", "risk": region + 3}
				session._on_room_requested(room, {})
				var plan := session._encounter_plan(room)
				var count := _bombers(plan).size()
				if region > 0 and depth >= 2:
					later_bombers += count
				_check(plan.get("errors", []).is_empty() and int(plan["spent"]) <= int(plan["budget"]) and count <= 2 and (count == 0 if region == 0 or depth < 2 else true), "region %d / depth %d / seed %d obeys timing, actor cap, and budget" % [region + 1, depth, seed_value])
	_check(later_bombers > 0, "later rogue encounters actually select the bomber")
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
	controller.evolution.advance_survival(149.0)
	controller.wave_sequence = 17
	_check(_bombers(controller._emit_next_wave()).is_empty(), "endless bomber cannot spawn before 150 survival seconds")
	controller.evolution.advance_survival(1.0)
	controller.wave_sequence = 17
	var first := controller._emit_next_wave()
	_check(_bombers(first).size() == 1, "150-second authored third wave contains one bomber")
	controller.wave_sequence = 17
	var same := controller._emit_next_wave()
	_check(_bombers(first) == _bombers(same), "same seed, survival stage and wave deterministically place the same bomber")
	controller.wave_sequence = 18
	_check(_bombers(controller._emit_next_wave()).is_empty(), "intermediate endless wave adds no bomber")
	slice.world.activate()
	var bomber_only := {"entries": _bombers(first)}
	for attempt in 4:
		slice._on_enemy_wave_requested(bomber_only)
	_check(slice.combat_runtime.enemies.filter(func(enemy: Node) -> bool: return enemy.definition.content_id == &"cinder_mine").size() == 2, "repeated endless waves cannot exceed two live bombers")
	_check(slice._bomber_introduced, "first endless spawn enables the concise warning notice")
	slice.start_slice(331)
	_check(slice.combat_runtime.enemies.is_empty() and not slice._bomber_introduced, "restart clears actors and introduction state")
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_CINDER_MINE_PLACEMENT: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _bombers(request: Dictionary) -> Array:
	return (request.get("entries", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("enemy_id") == &"cinder_mine")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
