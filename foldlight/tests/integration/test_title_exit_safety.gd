extends SceneTree

## The exit probe runs in a child engine because SceneTree.quit really closes
## that process. A zero exit code alone would hide the accidental-quit bug.
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--exit-probe" in OS.get_cmdline_user_args():
		await _run_exit_probe()
		return
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/integration/test_title_exit_safety.gd", "--", "--exit-probe"], output, true)
	var transcript := "\n".join(output)
	print(transcript)
	_check(code == 0 and "EXIT_CONFIRMATION_SAFE" in transcript, "real title keyboard exit keeps the engine alive until an explicit confirmation")
	_check("ERROR:" not in transcript and "[FAIL]" not in transcript, "native exit probe has no freed-node or input lifecycle errors")
	await _test_scene_transition()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_TITLE_EXIT_SAFETY: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _run_exit_probe() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.clear_roguelite_checkpoint()
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	current_scene = game
	await _frames(3)
	_key(KEY_UP, true)
	_key(KEY_UP, false)
	_check(root.gui_get_focus_owner().name == "QuitButton", "one up-arrow reaches the real native exit action")
	_key(KEY_SPACE, true)
	await _frames(2)
	var dialog := game.rogue_session.presentation._title_screen.get_node("QuitConfirmation") as Control
	_check(dialog.visible, "first exit activation opens confirmation rather than closing the process")
	for frame in 16:
		dialog._input_guard._process(0.1)
		_key(KEY_SPACE, true, true)
	_check(not dialog._input_guard.can_select(), "holding or repeating the opening Space cannot arm exit confirmation")
	_key(KEY_SPACE, false)
	for frame in 14:
		dialog._input_guard._process(0.1)
	await _frames(2)
	_check(root.gui_get_focus_owner() == dialog._cancel_button, "armed confirmation focuses the safe cancel action")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames(2)
	_check(not dialog.visible and game.rogue_session.mode == FoldlightRogueSessionController.SessionMode.TITLE, "a repeated confirmation key cancels by default without leaving the title")
	game.rogue_session.presentation._title_screen.request_quit()
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	_check(not dialog.visible, "Escape cancels immediately even while the entry guard is locked")
	game.rogue_session.presentation._title_screen.request_quit()
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 2
		event.button_index = JOY_BUTTON_B
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	_check(not dialog.visible, "controller B cancels native quit immediately while its input guard is locked")
	game.rogue_session.presentation._title_screen.request_quit()
	for frame in 14:
		dialog._input_guard._process(0.1)
	await _frames(2)
	_key(KEY_RIGHT, true)
	_key(KEY_RIGHT, false)
	_check(root.gui_get_focus_owner() == dialog._quit_button, "exit requires deliberately selecting the destructive action")
	_check(auto_accept_quit, "the operating system's native window-close behavior remains enabled")
	print("EXIT_CONFIRMATION_SAFE" if _failures.is_empty() else "EXIT_CONFIRMATION_FAILED")
	create_timer(0.2).timeout.connect(func() -> void:
		push_error("Explicit exit confirmation did not close the engine")
		quit(1)
	)
	_key(KEY_ENTER, true)


func _test_scene_transition() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	current_scene = game
	await _frames(3)
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	session.presentation.title_requested.emit()
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN, "a stale result-title signal cannot interrupt an active voyage")
	session.presentation.endless_requested.emit()
	_check(session.is_inside_tree() and session.mode == FoldlightRogueSessionController.SessionMode.RUN, "a hidden title's endless request cannot replace an active voyage")
	session._pause_game()
	session._on_settings_requested()
	session.presentation.abandon_requested.emit()
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN and session.presentation.screen_kind == &"settings", "a stale pause action cannot abandon a voyage while settings are open")
	session.enter_title()
	session._on_endless_requested()
	_check(session.is_inside_tree() and session._scene_transitioning, "real endless departure locks the old voyage until the input batch has finished")
	# Repeated button signals in the same input batch must not schedule a
	# second scene replacement while the original Controls are still attached.
	session._on_endless_requested()
	session.presentation.endless_requested.emit()
	await _frames(4)
	_check(current_scene is FoldlightEndlessSliceRuntime, "repeated scene requests produce exactly one live endless world")
	var slice := current_scene as FoldlightEndlessSliceRuntime
	_check(slice.player.play_enabled and slice.combat_runtime.active, "endless gameplay remains active after ignored late requests")
	slice.queue_free()
	await _frames(2)


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)
