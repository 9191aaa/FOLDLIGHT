extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	current_scene = game
	await frames(3)
	var session := game.rogue_session
	session.persist_profile = false
	var platform := root.get_node("PlatformBridge")
	platform._dispatch_native_back()
	await frames(2)
	check(session.mode == FoldlightRogueSessionController.SessionMode.TITLE, "Android Back at title keeps the process alive")
	session.start_new_run()
	await frames(3)
	platform._dispatch_native_back()
	await frames(2)
	check(session.is_paused(), "Android Back pauses a live solo voyage")
	check(not Input.is_action_pressed(&"pause_game") and not Input.is_action_pressed(&"ui_cancel"), "system Back leaves no held keyboard action")
	platform._dispatch_native_back()
	await frames(2)
	check(not session.is_paused() and session.mode == FoldlightRogueSessionController.SessionMode.RUN, "a second Back resumes the same voyage without title transition")
	session._pause_game()
	session.presentation.show_leave_confirmation()
	platform._dispatch_native_back()
	await frames(2)
	check(session.is_paused() and session.mode == FoldlightRogueSessionController.SessionMode.RUN, "Back cancels abandon confirmation instead of confirming it")
	game.queue_free()
	await frames(2)
	root.get_node("AudioDirector").shutdown()
	print("ANDROID_BACK_SAFETY: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func frames(count: int) -> void:
	for i in count: await process_frame

func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
