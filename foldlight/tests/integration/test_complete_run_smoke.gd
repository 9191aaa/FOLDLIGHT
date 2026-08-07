extends SceneTree

## Dependency-free integration smoke test for CI/headless handoff.
## It drives real InputEvents through the live scene and validates the complete run state graph.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	game.profile_manager.profile["story_flags"] = {}
	game.profile_manager.profile["acknowledged_intros"] = []

	game.start_new_run()
	await process_frame
	_check(game.mode == FoldlightGame.RunMode.BRIEFING, "title starts Chapter I with a paused briefing")
	_dismiss_briefings(game)
	_check(game.mode == FoldlightGame.RunMode.PLAYING, "confirmed briefing starts a playable run")
	_check(game.player.health == FoldlightPlayer.MAX_HEALTH, "new run restores player health")

	_send_action(&"fold", true)
	await process_frame
	await process_frame
	_check(game.player.folding, "fold input enters folding state")
	game.hostile_shots.append({
		"position": game.player.position + Vector2(44.0, 0.0),
		"velocity": Vector2.ZERO,
		"curve": 0.0,
		"color": Color.MAGENTA,
		"kind": 0,
		"age": 0.0,
		"life": 2.0,
		"radius": 10.0,
	})
	await physics_frame
	await process_frame
	_check(game.player.captured >= 1, "fold field captures a hostile petal")
	_send_action(&"fold", false)
	await process_frame
	await process_frame
	_check(not game.player.folding, "release exits folding state")
	_check(game.return_lights.size() >= 1, "captured petal becomes return light")

	game.player.invulnerability = 9999.0
	var chosen_path_ids: Array[StringName] = [&"swift_return", &"bright_edge", &"chain_bloom", &"full_moon", &"sunward", &"starfall"]
	for next_act in range(2, FoldlightGame.FINAL_ACT + 1):
		game._spawn_herald()
		_dismiss_briefings(game)
		var herald_index := _find_enemy_type(game, FoldlightGame.EnemyType.HERALD)
		_check(herald_index >= 0, "tide %d closes with a herald" % (next_act - 1))
		if herald_index >= 0:
			var herald_position: Vector2 = game.enemies[herald_index]["position"]
			game._damage_enemy(herald_index, 999, herald_position)
		_check(game.mode == FoldlightGame.RunMode.UPGRADE, "herald defeat opens authored technique seal")
		var expected_option_count := 3 if next_act == 2 else 1
		_check(game._seal_options.size() == expected_option_count, "seal uses fixed option count at tide %d" % (next_act - 1))
		game._seal_selected = 1 if next_act == 2 else 0
		_check(game._seal_options[game._seal_selected].doctrine_id == chosen_path_ids[next_act - 2], "seal follows the chosen deterministic technique path")
		game._apply_selected_doctrine()
		_check(game.act == next_act, "doctrine choice advances to tide %d" % next_act)
		_check(game.mode == FoldlightGame.RunMode.BRIEFING, "new tide waits on a readable stage briefing")
		_dismiss_briefings(game)
		_check(game.mode == FoldlightGame.RunMode.PLAYING, "confirming the stage briefing resumes play")

	var boss_index := _find_boss(game)
	_check(boss_index >= 0, "sixth fixed technique summons Ink Moon boss")
	if boss_index >= 0:
		game._profile_recorded = true
		var boss: Dictionary = game.enemies[boss_index]
		game._damage_enemy(boss_index, 999, boss["position"])
		_check(game.mode == FoldlightGame.RunMode.BRIEFING, "boss defeat pauses on the first Chapter I epilogue")
		_dismiss_briefings(game)
		_check(game.mode == FoldlightGame.RunMode.VICTORY, "confirmed epilogue reaches the victory result")
		_check(not game.rank.is_empty(), "victory assigns a performance rank")

	game.start_new_run()
	await process_frame
	_dismiss_briefings(game)
	game._profile_recorded = true
	game.player.health = 1
	game.player.invulnerability = 0.0
	game.hostile_shots.append({
		"position": game.player.position,
		"velocity": Vector2.ZERO,
		"curve": 0.0,
		"color": Color.MAGENTA,
		"kind": 0,
		"age": 0.0,
		"life": 2.0,
		"radius": 10.0,
	})
	await physics_frame
	await process_frame
	_check(game.mode == FoldlightGame.RunMode.BRIEFING, "first defeat pauses on a narrative recovery beat")
	_dismiss_briefings(game)
	_check(game.mode == FoldlightGame.RunMode.GAME_OVER, "confirmed recovery beat reaches game-over result")
	game.start_new_run()
	await process_frame
	_dismiss_briefings(game)
	_check(game.mode == FoldlightGame.RunMode.PLAYING and game.score == 0, "result can restart a clean chapter attempt")

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	_finish()


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _find_boss(game: FoldlightGame) -> int:
	return _find_enemy_type(game, FoldlightGame.EnemyType.BOSS)


func _find_enemy_type(game: FoldlightGame, enemy_type: int) -> int:
	for index in game.enemies.size():
		if int(game.enemies[index]["type"]) == enemy_type:
			return index
	return -1


func _dismiss_briefings(game: FoldlightGame) -> void:
	while game.mode == FoldlightGame.RunMode.BRIEFING:
		game._advance_briefing(false)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_SMOKE: PASS")
		quit(0)
	else:
		printerr("FOLDLIGHT_SMOKE: FAIL — ", ", ".join(_failures))
		quit(1)
