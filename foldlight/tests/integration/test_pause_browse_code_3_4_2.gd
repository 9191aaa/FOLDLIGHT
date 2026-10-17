extends SceneTree

## 3.4.2 browse-mode contract: the eight-arrow code is pause-only, order-sensitive,
## owned by the current voyage pause, and blocks damage through the player API.

const CODE_KEYS: Array[Key] = [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "release scene loads for pause browse-code regression")
	if game == null:
		_finish()
		return
	root.add_child(game)
	await process_frame
	await process_frame

	game.player.set_debug_invincible(false)
	_press_code(CODE_KEYS)
	_check(not game.player.is_debug_invincible(), "arrow code cannot enable browse mode outside a pause screen")

	game.rogue_session.persist_profile = false
	game.rogue_session.start_new_run()
	game.rogue_session._pause_game()
	await process_frame
	await process_frame
	_check(game.rogue_session.is_paused(), "voyage pause is active for the hidden code")
	_press_code([KEY_UP])
	_check(game._pause_browse_code_index == 1, "a real arrow event reaches the pause observer exactly once despite menu consumption")
	_press_key(KEY_UP, true, true)
	_press_key(KEY_UP, false)
	_check(game._pause_browse_code_index == 1, "keyboard auto-repeat does not advance the hidden code")
	_press_code([KEY_DOWN])
	_press_code([KEY_UP, KEY_DOWN, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT])
	_check(not game.player.is_debug_invincible(), "wrong arrow order does not accidentally enable browse mode")
	_press_code([KEY_UP, KEY_UP])
	_press_code([KEY_ESCAPE])
	_check(not game.rogue_session.is_paused() and game._pause_browse_code_index == 0, "real Escape resume cancels a partial pause code")
	_press_code([KEY_ESCAPE])
	await process_frame
	_press_code([KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT])
	_check(game.rogue_session.is_paused() and not game.player.is_debug_invincible(), "a newly opened pause cannot finish the previous pause's partial code")
	_press_code(CODE_KEYS)
	_check(game.player.is_debug_invincible(), "the eight-arrow code enables browse mode only while paused")
	_check(game.rogue_session.presentation.is_browse_mode_enabled(), "the shared pause UI confirms browse mode")
	game.player.reset_player()
	_check(game.player.is_debug_invincible(), "browse mode survives player reset so the full flow remains browsable")
	game.player.health = 2
	game.player.set_play_enabled(true)
	var rogue_hit := game.player.take_hit()
	_check(not rogue_hit and game.player.health == 2, "browse mode rejects roguelite, boss, projectile, and terrain damage through the same entry")

	game.queue_free()
	await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	_finish()


func _press_code(keys: Array) -> void:
	for key_variant: Variant in keys:
		_press_key(int(key_variant) as Key, true)
		_press_key(int(key_variant) as Key, false)


func _press_key(key: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.echo = echo
	event.keycode = key
	event.physical_keycode = key
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PAUSE_BROWSE_CODE_3_4_2: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PAUSE_BROWSE_CODE_3_4_2: FAIL - %s" % ", ".join(_failures))
		quit(1)
