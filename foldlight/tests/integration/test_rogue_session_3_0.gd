extends SceneTree

## End-to-end contract for the actual default mode: title -> large room ->
## reward -> route -> next room -> result, with the classic campaign still
## reachable through its preserved controller.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "main scene loads with the 3.0 presentation stack")
	if game == null:
		_finish()
		return
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	_check(session.mode == FoldlightRogueSessionController.SessionMode.TITLE, "new roguelite title is the default mode")
	_check(not game.get_node("HUD").visible and game.get_node("RoguePresentation").visible, "legacy HUD stays dormant behind the new title")

	session.start_new_run()
	await process_frame
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN and session.world.visible, "starting a voyage enters a live large room")
	_check(session.player.roguelite_combat and session.player.play_enabled, "room enables the dash/weapon/active roguelite controller")
	_check(session.world.room_runtime.get_terrain_pieces().size() >= 4, "live room contains readable tactical terrain")
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT, "run controller and room encounter enter combat together")

	# Resolve every authored wave through the same defeat signals used in play.
	var guard := 0
	while session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and guard < 80:
		guard += 1
		session.world.room_runtime.advance_encounter(2.0)
		for enemy in session.world.combat_runtime.enemies.duplicate():
			if is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.call("take_damage", 100000.0)
		await process_frame
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD, "clearing the room opens a real run-build reward")
	_check(session.presentation.screen_kind == &"reward", "three-choice reward presentation replaces combat without leaving the run")

	var profile_manager := root.get_node("ProfileManager") as FoldlightProfileManager
	var rogue := profile_manager.get_roguelite_snapshot()
	var unlocked: Array[StringName] = []
	for value: Variant in rogue.get("unlocked_upgrades", []):
		unlocked.append(StringName(value))
	var choices := session.reward_director.draft_upgrades(session.run_controller.run_state.seed, session.run_controller.run_state.room_count, session.run_controller.run_state.upgrade_levels, unlocked, 3)
	_check(choices.size() == 3, "reward draft supplies three legal unlocked upgrades")
	if not choices.is_empty():
		session._on_reward_chosen(StringName(choices[0].get("content_id", &"")))
	await process_frame
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE and session.presentation.screen_kind == &"route", "reward flows into the branching route chart")
	var exits: Array[String] = []
	for exit_variant: Variant in session.current_room_node.get("exits", []):
		exits.append(String(exit_variant))
	_check(not exits.is_empty(), "current route node exposes at least one authored exit")
	if not exits.is_empty():
		session._on_route_chosen(StringName(exits[0]))
	await process_frame
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and String(session.current_room_node.get("id", "")) == exits[0], "route selection loads the chosen next room")

	session.run_controller.fail_run(&"test_complete")
	await process_frame
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RESULT and session.presentation.screen_kind == &"result", "failed voyage produces a complete result screen")

	session._on_classic_requested()
	await process_frame
	_check(not session._active and game.get_node("HUD").visible and game.mode == FoldlightGame.RunMode.CAMPAIGN_MAP, "classic Twelve Voyages remains reachable and owns its original HUD")

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
		print("FOLDLIGHT_ROGUE_SESSION_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_SESSION_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
