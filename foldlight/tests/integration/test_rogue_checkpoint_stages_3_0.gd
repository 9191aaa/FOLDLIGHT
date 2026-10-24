extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	var checkpoints: Array[Dictionary] = []
	session.run_controller.checkpoint_ready.connect(func(snapshot: Dictionary) -> void: checkpoints.append(snapshot.duplicate(true)))
	session.start_new_run()
	await process_frame
	var guard := 0
	while session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and guard < 60:
		guard += 1
		session.world.room_runtime.advance_encounter(2.0)
		for enemy in session.world.combat_runtime.enemies.duplicate():
			if is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.call("take_damage", 100000.0)
		await process_frame
	var reward_checkpoint: Dictionary = checkpoints.back() if not checkpoints.is_empty() else {}
	_check(StringName(reward_checkpoint.get("session_phase", &"")) == &"reward", "room clear checkpoint records the pending reward phase")

	session.enter_title()
	_check(profile.commit_roguelite_checkpoint(reward_checkpoint, false), "reward checkpoint saves through the profile boundary")
	session.continue_run()
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD and session.presentation.screen_kind == &"reward" and not session.world.visible, "continue returns to reward instead of replaying the cleared room")
	var reward_button: Button
	for button in session.presentation._reward_buttons:
		if button.visible:
			reward_button = button
			break
	if reward_button != null:
		session._on_reward_chosen(StringName(reward_button.get_meta("upgrade_id", &"")))
	await process_frame
	var route_checkpoint: Dictionary = checkpoints.back() if not checkpoints.is_empty() else {}
	_check(StringName(route_checkpoint.get("session_phase", &"")) == &"route", "chosen reward checkpoint records the pending route phase")
	await _choose_next_room(session, "reward continuation")

	session.enter_title()
	_check(profile.commit_roguelite_checkpoint(route_checkpoint, false), "route checkpoint saves through the profile boundary")
	session.continue_run()
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE and session.presentation.screen_kind == &"route" and not session.world.visible, "continue returns to route choice without granting a duplicate reward")
	await _choose_next_room(session, "route continuation")

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	_finish()


func _choose_next_room(session: FoldlightRogueSessionController, label: String) -> void:
	var exits: Array = session.current_room_node.get("exits", [])
	_check(not exits.is_empty(), "%s offers a real next room" % label)
	if exits.is_empty():
		return
	session._on_route_chosen(StringName(exits[0]))
	await process_frame
	_check(session.player.visible and session.player.play_enabled and session.world.visible and session.world.combat_runtime.active, "%s restores a visible playable character in live combat" % label)
	var beacons := session.world.room_runtime.get_tide_beacons()
	_check(beacons.size() == 2 and beacons.all(func(beacon: FoldlightTideBeacon) -> bool: return beacon.simulation_enabled and not beacon.consumed), "%s activates fresh scene interactions" % label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ROGUE_CHECKPOINT_STAGES_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_CHECKPOINT_STAGES_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
