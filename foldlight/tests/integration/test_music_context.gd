extends SceneTree

## Real scene transitions and score events drive the production director.
## Audio decoding/crossfades are checked separately by the audio quality suite.
class LocalTransportBridge extends "res://scripts/autoloads/web_race_bridge.gd":
	func _read_browser_boot() -> Dictionary:
		return {}

	func _send_browser(_method: StringName, _payload: Dictionary) -> void:
		pass


var _failures: Array[String] = []
var _audio: FoldlightAudioDirector


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	_audio = root.get_node("AudioDirector") as FoldlightAudioDirector
	if _audio == null:
		quit(1)
		return
	await _test_voyage(profile)
	await _test_survival()
	await _test_friend_race()
	_audio.shutdown()
	print("FOLDLIGHT_MUSIC_CONTEXT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_voyage(profile: FoldlightProfileManager) -> void:
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.set_process(false)
	_expect(&"title", &"harbor", "title starts the harbor score")
	session.start_prologue()
	_expect(&"combat", &"reef", "tutorial enters the reef rather than inheriting title music")
	session._pause_game()
	_expect(&"paused", &"reef", "tutorial pause keeps its phrase and quiets the music")
	session._resume_game()
	_expect(&"combat", &"reef", "tutorial resumes its reef context")
	var themes: Array[StringName] = [&"reef", &"archive", &"eclipse"]
	for region in 3:
		_enter_room(session, region)
		_expect(&"combat", themes[region], "voyage region %d selects its own score" % region)
		var pressure := _target()
		session._pause_game()
		_expect(&"paused", themes[region], "region %d pause retains its score" % region)
		_check(_target() < pressure * 0.2, "region %d pause lowers the rhythm layer" % region)
		session._on_settings_requested()
		_expect(&"paused", themes[region], "pause settings do not switch to title music")
		session._on_settings_back_requested(&"pause")
		session._resume_game()
		_expect(&"combat", themes[region], "region %d resumes its own combat score" % region)
		session.run_controller.complete_room({"duration": 40.0})
		_expect(&"reward", themes[region], "region %d reward settles the current score" % region)
		_check(_target() < pressure * 0.2, "region %d reward softens percussion" % region)
		var checkpoint := session.run_controller._checkpoint_for(&"reward")
		session.enter_title()
		_check(profile.commit_roguelite_checkpoint(checkpoint, false), "reward checkpoint is valid")
		session.continue_run()
		_expect(&"reward", themes[region], "reward checkpoint restores the correct regional score")
		session.run_controller.open_route_choice()
		_expect(&"route", &"harbor", "route selection opens the breathing-space score")
		var exits: Array = session.current_room_node.get("exits", [])
		if not exits.is_empty():
			session.run_controller.choose_exit(StringName(exits[0]))
			_expect(&"combat", themes[region], "route departure returns to the regional score")

	var boss := _enter_room(session, 1, true)
	_check(boss != null, "actual archivist spawns for music lifecycle")
	_expect(&"boss", &"boss", "actual boss room selects the boss score")
	var boss_pressure := _target()
	session._pause_game()
	_expect(&"paused", &"boss", "boss pause keeps the boss phrase")
	session._resume_game()
	_expect(&"boss", &"boss", "boss resume does not accidentally return to ordinary combat")
	_check(_target() >= boss_pressure and _target() < boss_pressure + 0.15, "boss resume retains boss intensity and accounts for its spawned actors")
	# Use the actual introduction tracker signal, then dismiss its real card.
	session.persist_profile = true
	session.mechanic_tracker.restore_introduced([])
	if boss != null:
		var intro_key := StringName("rogue_threat_v3:boss:%s" % boss.definition.content_id)
		var acknowledged: Array = profile.profile.get("acknowledged_intros", [])
		acknowledged.erase(String(intro_key))
		session.mechanic_tracker.request_boss_introduction(boss.definition)
		_check(session._mechanic_intro_active, "production Boss introduction enters a readable modal")
		if session._mechanic_intro_active:
			_expect(&"paused", &"boss", "boss briefing lowers music under reading")
			session.presentation.mechanic_card_dismissed.emit(boss.definition.content_id)
			_expect(&"boss", &"boss", "boss briefing dismissal restores boss music")
	session.persist_profile = false
	if boss != null:
		boss.take_damage(1000000.0)
		_expect(&"victory", &"boss", "actual boss death keeps the phrase under the clear chime")
		_check(_target() < boss_pressure * 0.1, "boss death immediately requests a restrained aftermath")
		for _step in 24:
			session._boss_clear_banner._input_guard._process(0.1)
			session._process(0.1)
		_expect(&"victory", &"boss", "aftermath clock does not restart combat music")
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR, "music does not skip the explicit boss-clear gate")
		session._boss_clear_banner._confirm()
		_expect(&"combat", &"eclipse", "confirmed boss clear opens the next region's score")
	session.run_controller.fail_run(&"lantern_extinguished")
	_expect(&"defeat", &"eclipse", "defeat keeps a quiet tail of the last region")
	_check(is_zero_approx(_target()), "defeat removes the rhythm layer")
	session.enter_title()
	_expect(&"title", &"harbor", "return to title recovers the harbor score")
	game.queue_free()
	await process_frame


func _enter_room(session: FoldlightRogueSessionController, region: int, boss_room: bool = false) -> FoldlightRogueBossActor:
	session.start_new_run()
	var controller := session.run_controller
	controller.run_state.current_region = region
	var region_snapshot := controller.get_current_region_snapshot()
	controller.run_state.current_node_id = StringName(region_snapshot.get("start_id", &""))
	if boss_room:
		for node: Dictionary in region_snapshot.get("nodes", []):
			if StringName(node.get("category", &"")) == &"boss":
				controller.run_state.current_node_id = StringName(node["id"])
				break
	controller.phase = FoldlightRogueRunController.Phase.ENTERING_ROOM
	controller._request_current_room()
	session.world.combat_runtime.set_physics_process(false)
	session.player.set_physics_process(false)
	session.world.room_runtime.advance_encounter(2.0)
	for actor in session.world.combat_runtime.enemies:
		if actor is FoldlightRogueBossActor:
			return actor as FoldlightRogueBossActor
	return null


func _test_survival() -> void:
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	var themes: Array[StringName] = [&"reef", &"archive", &"eclipse"]
	for index in 3:
		slice.start_slice(300 + index)
		_expect(&"endless", themes[index], "endless authored map %d selects a distinct score" % index)
		var opening := _target()
		slice.controller.evolution.advance_survival(300.0)
		slice._restore_survival_music()
		_check(_target() > opening + 0.10, "longer survival raises musical tension without changing maps")
		var active_target := _target()
		slice._pause_game()
		_expect(&"paused", themes[index], "endless pause keeps the selected map score")
		_check(_target() < active_target * 0.2, "endless pause settles the rhythm")
		slice._on_settings_requested()
		_expect(&"paused", themes[index], "endless settings inherit the paused score")
		slice._on_settings_back_requested(&"pause")
		slice._resume_game()
		_expect(&"endless", themes[index], "endless resume returns to its map score")
		_check(is_equal_approx(_target(), active_target), "endless resume preserves survival tension")
		slice.controller._on_objective_completed({"title": "航行任务", "completion_count": 1})
		_expect(&"reward", themes[index], "mission completion settles music under the cards")
		var score_time := slice.controller.evolution.survival_seconds
		slice._physics_process(3.0)
		_expect(&"reward", themes[index], "reward overlay cannot be overwritten by pressure sampling")
		_check(slice.controller.evolution.survival_seconds == score_time, "music does not advance rewarded survival time")
		for transition_step in 6:
			slice._advance_reward_completion(0.1)
		var reward_id := StringName(slice._modal_options[0].id)
		slice._on_reward_chosen(reward_id)
		_expect(&"endless", themes[index], "real mission reward claim restores the same map score")
		var snapshot_before := var_to_str(slice.controller.get_snapshot())
		seed(712011)
		var expected_random := randi()
		seed(712011)
		for _sample in 8:
			slice._restore_survival_music()
		_check(randi() == expected_random and var_to_str(slice.controller.get_snapshot()) == snapshot_before, "music observation leaves combat state and RNG untouched")
		slice._finish_run()
		_expect(&"defeat", themes[index], "survival defeat quiets the current map score")
		slice._retry_run()
		_expect(&"endless", themes[index], "retry recovers the same seeded map's score")
		_check(_target() < active_target, "retry starts at opening tension rather than retaining the previous run's peak")
	slice.queue_free()
	await process_frame


func _test_friend_race() -> void:
	var bridge := LocalTransportBridge.new()
	root.add_child(bridge)
	bridge.set_process(false)
	_check(bridge.configure_session({"roomId": "music-room", "matchId": "music-match", "playerId": "music-player", "instanceId": "music-instance", "seed": 301, "rulesVersion": "endless_race_v5"}), "race accepts the unchanged multiplayer protocol")
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	slice.prepare_web_race(bridge)
	slice.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	_expect(&"paused", &"archive", "friend waiting room settles the seeded map's score")
	slice._physics_process(3.0)
	_check(is_zero_approx(slice.controller.evolution.survival_seconds), "waiting music cannot start the shared battle clock")
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	_expect(&"endless", &"archive", "server-admitted race restores the prepared map score")
	slice._pause_game()
	_expect(&"endless", &"archive", "disallowed race pause does not mute active combat")
	slice.controller._on_objective_completed({"title": "好友任务", "completion_count": 1})
	_expect(&"reward", &"archive", "friend reward uses the same quiet card context")
	bridge.accept_page_state({"phase": "finished", "reason": "match_finished"})
	_expect(&"victory", &"archive", "server completion settles the current map score")
	_check(slice._modal_kind == &"race_finished" and not slice.combat_runtime.active, "music transition does not reopen a finished race")
	slice.queue_free()
	bridge.queue_free()
	await process_frame


func _target() -> float:
	return float(_audio.get_music_state().target_intensity)


func _expect(context: StringName, theme: StringName, label: String) -> void:
	var state := _audio.get_music_state()
	_check(StringName(state.context) == context and StringName(state.theme) == theme, "%s (got %s / %s)" % [label, state.context, state.theme])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
