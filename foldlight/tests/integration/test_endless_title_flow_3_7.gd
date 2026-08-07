extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_check(main_scene != null, "formal main scene loads for endless title flow")
	if main_scene == null:
		_finish()
		return
	var game := main_scene.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node_or_null("RogueSession") as FoldlightRogueSessionController
	var presentation := game.get_node_or_null("RoguePresentation") as FoldlightRoguePresentation
	_check(presentation != null, "title presentation is available")
	_check(session != null, "roguelite session is available")
	if presentation != null and session != null:
		_check(presentation.endless_requested.is_connected(session._on_endless_requested), "title endless entry is connected to the scene switch handler")
	var endless_scene := load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene
	var endless := endless_scene.instantiate() as FoldlightEndlessSliceRuntime if endless_scene != null else null
	_check(endless != null, "title destination is the playable survival scene")
	if endless != null:
		root.add_child(endless)
		await process_frame
		await process_frame
		_check(endless.controller.active, "survival destination starts a live run")
		_check(endless.has_method("_return_to_title"), "survival exposes a safe pause return handler")
		endless.controller.exit_mode(&"test_cleanup")
		_check(not endless.controller.active, "survival exit stops the run before title return")
		endless.queue_free()
	game.queue_free()
	await process_frame
	await process_frame

	# Exercise the real SceneTree lifecycle. The former assertions only proved
	# that both scenes could exist independently; they could not catch a crash or
	# dangling connection during main -> endless -> main replacement.
	var open_error := change_scene_to_file("res://scenes/main.tscn")
	_check(open_error == OK, "formal title can become the active SceneTree scene")
	await process_frame
	await process_frame
	await process_frame
	var live_game := current_scene as FoldlightGame
	_check(live_game != null, "real title transition owns a live main scene")
	if live_game != null:
		var old_game_ref: WeakRef = weakref(live_game)
		var live_session := live_game.get_node_or_null("RogueSession") as FoldlightRogueSessionController
		_check(live_session != null, "real title transition exposes the roguelite session")
		if live_session != null:
			live_session._on_endless_requested()
			await process_frame
			await process_frame
			await process_frame
			var live_endless := current_scene as FoldlightEndlessSliceRuntime
			_check(live_endless != null and live_endless.controller.active, "real main-to-endless scene replacement starts safely")
			_check(old_game_ref.get_ref() == null, "main scene is released after entering endless mode")
			if live_endless != null:
				live_endless.player.dash_component.cooldown_remaining = 1.4
				live_endless._damage_flash_remaining = 0.2
				live_endless.camera.offset = Vector2(9.0, -6.0)
				live_endless._finish_run()
				live_endless._activate_modal_choice(0)
				_check(is_zero_approx(live_endless.player.dash_component.cooldown_remaining) and is_zero_approx(live_endless._damage_flash_remaining) and live_endless.camera.offset.is_zero_approx(), "restart clears shared-component cooldown, damage and camera feedback")
				await process_frame
				await process_frame
				_check(live_endless.controller.active and not live_endless.run_ended, "game-over restart reuses the scene without stale run state")
				_check(live_endless.world.room_runtime.get_terrain_pieces().size() == live_endless.controller.map_definition.walls.size(), "restart rebuilds one valid shared-terrain set")
				var old_endless_ref: WeakRef = weakref(live_endless)
				live_endless._return_to_title()
				live_endless._return_to_title()
				_check(live_endless._transitioning_to_title, "duplicate title requests are collapsed while scene replacement is pending")
				await process_frame
				await process_frame
				await process_frame
				_check(current_scene is FoldlightGame, "real endless-to-title scene replacement returns safely")
				_check(old_endless_ref.get_ref() == null, "endless scene is released after returning to title")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ENDLESS_TITLE_FLOW_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_TITLE_FLOW_3_7: FAIL - %s" % ", ".join(_failures))
		quit(1)
