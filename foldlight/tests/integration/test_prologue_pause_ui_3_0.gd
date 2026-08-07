extends SceneTree

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
	var presentation := session.presentation
	presentation.show_title({})
	_check(not presentation._title_prologue.visible and presentation._title_primary.text.contains("教学"), "first-time title has one unambiguous tutorial entry")
	presentation.show_title({"prologue_complete": true})
	_check(presentation._title_prologue.visible and presentation._title_prologue.text.contains("重温"), "learned players can replay the short tutorial without blocking a run")

	session.start_prologue()
	await process_frame
	_check(session.mode == FoldlightRogueSessionController.SessionMode.PROLOGUE and presentation.screen_kind == &"hud", "prologue starts inside the real large-room controller")
	_check(session.player.invulnerability > 30.0 and session._prologue_step_index == 0, "early lessons protect a first-time player without changing normal runs")

	session._pause_game()
	_check(session._paused and not session.player.play_enabled and not session.world.combat_runtime.active and presentation.screen_kind == &"pause", "pause freezes player, combat, encounter time, and shows a controller menu")
	session._on_settings_requested()
	_check(presentation.screen_kind == &"settings" and presentation._settings_buttons.size() == 8, "pause and title share a complete accessibility/settings screen")
	var previous_contrast := bool(session.profile_manager.get_setting(&"high_contrast", false))
	session._on_setting_adjust_requested(&"high_contrast", 1)
	_check(bool(session.profile_manager.get_setting(&"high_contrast", false)) != previous_contrast, "high-contrast projectile setting is adjustable in place")
	session.profile_manager.settings["high_contrast"] = previous_contrast
	session.profile_manager.apply_settings()
	session._on_settings_back_requested(&"pause")
	_check(presentation.screen_kind == &"pause", "settings returns to the correct pause owner")
	session._resume_game()
	_check(not session._paused and session.player.play_enabled and session.world.combat_runtime.active and presentation.screen_kind == &"hud", "resume restores the live encounter with a safety window")

	_check(FoldlightRogueSessionController.PROLOGUE_STEPS.size() == 3 and presentation._quick_tutorial.visible, "prologue is a visible three-step quick tutorial")
	session._prologue_distance = 300.0
	session._update_prologue(0.01)
	_check(session._prologue_step_index == 0, "movement lesson waits for both movement and the real dash")
	session._on_player_dash_started(Vector2.RIGHT, 0.18)
	_check(session._prologue_step_index == 1, "combined movement lesson advances after the real dash signal")
	session._on_player_fold_released(2, 0.5)
	_check(session._prologue_step_index == 2 and session._prologue_encounter_started, "Fold lesson requires a meaningful release and immediately opens practice")
	session._on_player_active_item_used(&"paper_burst")
	_check(session._prologue_step_index == 2 and session.current_wave_text.contains("主动技能"), "active item is taught as useful feedback rather than a blocking gate")

	var guard := 0
	while session.mode == FoldlightRogueSessionController.SessionMode.PROLOGUE and guard < 80:
		guard += 1
		session.world.room_runtime.advance_encounter(2.0)
		for enemy in session.world.combat_runtime.enemies.duplicate():
			if is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.call("take_damage", 100000.0)
		await process_frame
	_check(guard < 80 and session.mode == FoldlightRogueSessionController.SessionMode.RESULT, "final practice completes the prologue without a soft lock")
	_check(presentation.screen_kind == &"result" and not session.player.visible, "prologue ends on a polished handoff result instead of dropping into a test state")
	session.start_prologue()
	presentation._quick_tutorial.skip()
	await process_frame
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN and presentation.screen_kind == &"hud", "skip leaves the lesson cleanly and starts a real run")

	var all_buttons_large := true
	for child in _descendants(presentation.interface):
		if child is Button and (child as Button).custom_minimum_size.y < 52.0:
			all_buttons_large = false
	_check(all_buttons_large, "all new interactive controls meet the 52-pixel controller/touch target")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "new anchored UI coexists with the classic campaign's exact 16:9 composition")

	game.queue_free()
	await process_frame
	_finish()


func _descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PROLOGUE_PAUSE_UI_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PROLOGUE_PAUSE_UI_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
