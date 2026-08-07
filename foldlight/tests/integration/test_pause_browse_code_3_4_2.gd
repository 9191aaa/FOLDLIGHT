extends SceneTree

## 3.4.2 browse-mode contract: the eight-arrow code is pause-only, order-sensitive,
## shared by classic/roguelite flow, and blocks damage through the player API.

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
	_press_code(game, CODE_KEYS)
	_check(not game.player.is_debug_invincible(), "arrow code cannot enable browse mode outside a pause screen")

	game._rogue_mode_active = false
	game.mode = FoldlightGame.RunMode.PAUSED
	_press_code(game, [KEY_UP, KEY_DOWN, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT])
	_check(not game.player.is_debug_invincible(), "wrong arrow order does not accidentally enable browse mode")
	_press_code(game, CODE_KEYS)
	_check(game.player.is_debug_invincible(), "up up down down left right left right enables classic browse mode while paused")

	game.player.health = 3
	game.player.set_play_enabled(true)
	var classic_hit := game.player.take_hit()
	_check(not classic_hit and game.player.health == 3, "browse mode rejects classic damage at the shared player hit entry")
	game.player.reset_player()
	_check(game.player.is_debug_invincible(), "browse mode survives player reset so the full flow remains browsable")

	game.player.set_debug_invincible(false)
	game._rogue_mode_active = true
	game.rogue_session.mode = FoldlightRogueSessionController.SessionMode.RUN
	game.rogue_session._pause_game()
	_check(game.rogue_session.is_paused(), "roguelite pause screen is active for the hidden code")
	_press_code(game, CODE_KEYS)
	_check(game.player.is_debug_invincible(), "the same eight-arrow code enables roguelite browse mode")
	_check(game.rogue_session.presentation.is_browse_mode_enabled(), "roguelite pause UI confirms that browse mode is active")
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


func _press_code(game: FoldlightGame, keys: Array) -> void:
	for key_variant: Variant in keys:
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = int(key_variant) as Key
		event.physical_keycode = int(key_variant) as Key
		game._input(event)


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
