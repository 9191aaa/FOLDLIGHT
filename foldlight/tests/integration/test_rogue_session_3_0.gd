extends SceneTree

## End-to-end contract for the actual default mode: title -> large room ->
## reward -> route -> next room -> result -> the shared title.

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
	_check(game.get_node_or_null("HUD") == null and game.get_node("RoguePresentation").visible, "the shared presentation is the only interface in the main scene")

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

	var offered_ids: Array[StringName] = []
	for card: Button in session.presentation._reward_buttons:
		if card.visible:
			offered_ids.append(StringName(card.get_meta("upgrade_id", &"")))
	_check(offered_ids.size() == 3, "live reward draft supplies three legal weapon or build choices")
	if not offered_ids.is_empty():
		session._on_reward_chosen(offered_ids[0])
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

	var audio_cues: Array[StringName] = []
	session.audio_director.sfx_requested.connect(func(sound_name: StringName, _pitch: float, _volume_db: float) -> void: audio_cues.append(sound_name))
	session.run_controller.fail_run(&"test_complete")
	await process_frame
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RESULT and session.presentation.screen_kind == &"result", "failed voyage produces a complete result screen")
	_check(audio_cues.count(&"hurt") == 1, "a non-damage failure retains its single result cue")

	session.start_new_run()
	await process_frame
	session.player.health = 1
	session.player.invulnerability = 0.0
	session.player.set_debug_invincible(false)
	audio_cues.clear()
	_check(session.world.combat_runtime._try_hit_player(Vector2.LEFT), "a real combat hit reaches the one-health player")
	_check(session.player.health == 0 and session.mode == FoldlightRogueSessionController.SessionMode.RESULT and session.presentation.screen_kind == &"result", "fatal combat damage reaches the voyage result synchronously")
	_check(audio_cues.count(&"hurt") == 1, "fatal damage and its result screen share exactly one hurt cue")

	game.return_to_main_menu()
	await process_frame
	_check(session._active and session.mode == FoldlightRogueSessionController.SessionMode.TITLE and session.presentation.screen_kind == &"title", "result returns to the shared title with one active input owner")

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
