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
			while session._mechanic_intro_active and not session._mechanic_intro_queue.is_empty():
				session._on_mechanic_card_dismissed(StringName(session._mechanic_intro_queue[0]["content_id"]))
			session.world.room_runtime.advance_encounter(2.0)
			for enemy in session.world.combat_runtime.enemies.duplicate():
				if not is_instance_valid(enemy):
					continue
				if enemy is FoldlightRogueBossActor:
					defeated_bosses.append((enemy as FoldlightRogueBossActor).definition.content_id)
					(enemy as FoldlightRogueBossActor).take_damage(1000000.0, &"weapon")
				elif enemy.has_method("take_damage"):
					# Preserve the elite's real immunity contract in this accelerated
					# route audit: simulate its warning and wait for a firing window.
					if enemy.has_method("is_damageable"):
						for _step in 80:
							if enemy.call("is_damageable"):
								break
							enemy.call("advance_simulation", 0.1, session.player.global_position)
					enemy.call("take_damage", 1000000.0)
			await process_frame
		_check(wave_guard < 100, "room %d combat terminates" % room_guard)
		if session.mode != FoldlightRogueSessionController.SessionMode.RUN:
			break
		if category == &"boss":
			_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session.world.visible, "boss %d retains its arena until a deliberate continue" % defeated_bosses.size())
			for step in 24:
				session._boss_clear_banner._input_guard._process(0.10)
			session._boss_clear_banner._confirm()
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
	var regional_bosses_valid := defeated_bosses.size() == FoldlightRogueContentCatalog.REGIONS.size()
	if regional_bosses_valid:
		for index in defeated_bosses.size():
			regional_bosses_valid = regional_bosses_valid and FoldlightRogueContentCatalog.REGIONS[index].boss_ids.has(defeated_bosses[index])
	_check(regional_bosses_valid, "complete voyage fights one valid authored boss from every region")
	_check(session.run_controller.run_state.room_count >= 18, "branch route delivers a sustained thirty-to-forty-five-minute room count")
	var total_upgrade_stacks := 0
	for stack_count in session.run_controller.run_state.upgrade_levels.values():
		total_upgrade_stacks += int(stack_count)
	for rank in session.run_controller.run_state.weapon_levels.values():
		total_upgrade_stacks += int(rank)
	total_upgrade_stacks -= 1 # The starting lantern is not a room reward.
	_check(total_upgrade_stacks >= 10, "full route creates a substantial build across weapon ranks and general upgrades")
	var mounted_ids: Array[StringName] = []
	for definition in session.player.weapon_mount.definitions:
		mounted_ids.append(definition.content_id)
	_check(mounted_ids.size() == session.run_controller.run_state.weapon_ids.size() and mounted_ids.has(&"crease_lantern"), "all collected automatic weapons remain equipped alongside the starter through the final boss")
	for weapon_id in session.run_controller.run_state.weapon_ids:
		_check(mounted_ids.has(weapon_id), "completed voyage retains chosen weapon %s" % weapon_id)

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
