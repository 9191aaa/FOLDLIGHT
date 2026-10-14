extends SceneTree

## Exercises real controller hand-offs, including a story run carrying combat
## state. Returning to the hub must preserve saves and transfer input ownership.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	game.rogue_session.persist_profile = false
	var session := game.rogue_session
	_check(game._rogue_mode_active and session.mode == session.SessionMode.TITLE, "launch opens the shared expedition title")

	game.activate_classic_campaign()
	_check(not game._rogue_mode_active and game.mode == game.RunMode.CAMPAIGN_MAP, "story entry transfers control to its voyage map")
	_press_back(game)
	_assert_shared_title(game, "story map back")

	game.start_campaign_mission(0)
	game.enemies.append({"position": Vector2(500, 500)})
	game.hostile_shots.append({"position": Vector2(700, 500)})
	game.return_lights.append({"position": Vector2(800, 500)})
	game._world_hit_stop = 0.12
	game._shake_offset = Vector2(8, -4)
	game.player.captured = 4
	var saved_campaign := game.profile_manager.get_campaign_snapshot().duplicate(true)
	var saved_rogue := game.profile_manager.get_roguelite_snapshot().duplicate(true)
	game.return_to_main_menu()
	game.return_to_main_menu()
	_assert_shared_title(game, "active story return")
	_check(game.enemies.is_empty() and game.hostile_shots.is_empty() and game.return_lights.is_empty(), "story combat entities are cleared on return")
	_check(game._briefing_queue.is_empty() and game._briefing_current.is_empty(), "story introductions cannot leak into the next mode")
	_check(game.player.captured == 0 and is_zero_approx(game._world_hit_stop) and game._shake_offset.is_zero_approx(), "held fold and hit feedback are reset")
	_check(game.profile_manager.get_campaign_snapshot() == saved_campaign, "return keeps the story checkpoint intact")
	_check(game.profile_manager.get_roguelite_snapshot() == saved_rogue, "return keeps the expedition checkpoint intact")

	session.start_new_run()
	await process_frame
	_check(session.mode == session.SessionMode.RUN and game.player.roguelite_combat, "a fresh expedition starts after leaving the story")
	var story_time := game.run_time
	game._physics_process(1.0)
	_check(is_equal_approx(game.run_time, story_time), "story simulation stays idle while the expedition owns control")

	for result_mode in [game.RunMode.GAME_OVER, game.RunMode.VICTORY]:
		game.activate_classic_campaign()
		game.mode = result_mode
		_press_back(game)
		_assert_shared_title(game, "story result %d back to title" % result_mode)
	game.start_campaign_mission(0)
	game.mode = game.RunMode.PAUSED
	var paused_checkpoint := game.profile_manager.get_active_checkpoint().duplicate(true)
	var exit_event := InputEventAction.new()
	exit_event.action = &"open_archive"
	exit_event.pressed = true
	game._unhandled_input(exit_event)
	_assert_shared_title(game, "story pause exit")
	_check(game.profile_manager.get_active_checkpoint() == paused_checkpoint, "pause exit preserves a restorable tide boundary")

	game.start_tutorial()
	game._finish_tutorial()
	_assert_shared_title(game, "legacy tutorial completion")
	_check(game._enemy_tip_data(-1).is_empty(), "unknown story enemy has no misleading introduction")
	for enemy_type in game.EnemyType.values():
		var tip := game._enemy_tip_data(enemy_type)
		_check(not tip.is_empty() and int(tip.get("glyph", -1)) == enemy_type, "story catalog retains enemy introduction %d" % enemy_type)
	var tip_copy := game._effect_tip_data(&"wet_ink")
	tip_copy["title"] = "mutated preview"
	_check(game._effect_tip_data(&"wet_ink").get("title") == "湿墨", "presentation snapshots cannot mutate shared story content")

	game.queue_free()
	await process_frame
	_finish()


func _press_back(game: FoldlightGame) -> void:
	var event := InputEventAction.new()
	event.action = &"pause_game"
	event.pressed = true
	game._unhandled_input(event)


func _assert_shared_title(game: FoldlightGame, context: String) -> void:
	_check(game._rogue_mode_active and game.rogue_session.mode == game.rogue_session.SessionMode.TITLE, "%s restores shared title ownership" % context)
	_check(game.rogue_session.presentation.screen_kind == &"title" and game.rogue_session.presentation.visible and not game.get_node("HUD").visible, "%s shows one menu" % context)
	_check(not game.player.play_enabled and not game.player.visible, "%s suspends the player" % context)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_UNIFIED_STORY_NAVIGATION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_UNIFIED_STORY_NAVIGATION: FAIL - %s" % ", ".join(_failures))
		quit(1)
