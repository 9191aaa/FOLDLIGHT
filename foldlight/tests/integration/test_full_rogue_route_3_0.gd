extends SceneTree

## Fast deterministic traversal of the complete three-region product route.
## It resolves combat through actor damage and makes real reward/route choices,
## exercising every transition without waiting thirty minutes of wall time.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	await process_frame
	var visited_regions: Dictionary = {}
	var defeated_bosses: Array[StringName] = []
	var room_guard := 0
	while session.mode == FoldlightRogueSessionController.SessionMode.RUN and room_guard < 40:
		room_guard += 1
		visited_regions[session.run_controller.run_state.current_region] = true
		var category := StringName(session.current_room_node.get("category", &""))
		var wave_guard := 0
		while session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and wave_guard < 100:
			wave_guard += 1
			session.world.room_runtime.advance_encounter(2.0)
			for enemy in session.world.combat_runtime.enemies.duplicate():
				if not is_instance_valid(enemy):
					continue
				if enemy is FoldlightRogueBossActor:
					defeated_bosses.append((enemy as FoldlightRogueBossActor).definition.content_id)
					(enemy as FoldlightRogueBossActor).take_damage(1000000.0, &"weapon")
				elif enemy.has_method("take_damage"):
					enemy.call("take_damage", 1000000.0)
			await process_frame
		_check(wave_guard < 100, "room %d combat terminates" % room_guard)
		if session.mode != FoldlightRogueSessionController.SessionMode.RUN:
			break
		if category == &"boss":
			await process_frame
			continue
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD, "room %d reaches reward phase" % room_guard)
		var visible_reward: Button
		for button in session.presentation._reward_buttons:
			if button.visible:
				visible_reward = button
				break
		_check(visible_reward != null, "room %d has a selectable authored reward" % room_guard)
		if visible_reward != null:
			session._on_reward_chosen(StringName(visible_reward.get_meta("upgrade_id", &"")))
		await process_frame
		# Room two deliberately has two consecutive rewards in 3.7:
		# first a build upgrade, then the run's first active item.
		if session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD:
			var second_reward: Button
			for button in session.presentation._reward_buttons:
				if button.visible:
					second_reward = button
					break
			_check(second_reward != null, "room %d queued reward stage is selectable" % room_guard)
			if second_reward != null:
				session._on_reward_chosen(StringName(second_reward.get_meta("upgrade_id", &"")))
			await process_frame
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE, "room %d reaches route phase" % room_guard)
		var exits: Array = session.current_room_node.get("exits", [])
		_check(not exits.is_empty(), "room %d route has a valid destination" % room_guard)
		if not exits.is_empty():
			session._on_route_chosen(StringName(exits[0]))
		await process_frame

	_check(room_guard < 40, "complete route finishes without a transition loop")
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RESULT, "third boss produces final result")
	_check(visited_regions.size() == 3, "complete voyage visits all three regions")
	_check(defeated_bosses.size() == 3 and defeated_bosses.has(&"reef_crown_battery") and defeated_bosses.has(&"inverted_archivist") and defeated_bosses.has(&"origami_judge"), "complete voyage fights all three rebuilt bosses")
	_check(session.run_controller.run_state.room_count >= 18, "branch route delivers a sustained thirty-to-forty-five-minute room count")
	var total_upgrade_stacks := 0
	for stack_count in session.run_controller.run_state.upgrade_levels.values():
		total_upgrade_stacks += int(stack_count)
	_check(total_upgrade_stacks >= 10, "full route creates a substantial stacked in-run build")
	_check(session.player.weapon_mount.definitions.size() <= 2, "weapon rewards respect the two-automatic-weapon readability cap")

	game.queue_free()
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
		print("FOLDLIGHT_FULL_ROGUE_ROUTE_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_FULL_ROGUE_ROUTE_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
