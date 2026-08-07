extends SceneTree

## Release input contract: every essential action is reachable with the left
## hand or a conventional controller, and those actions reach the live systems.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		_check(_has_event_type(action, "InputEventKey") and _has_event_type(action, "InputEventJoypadMotion"), "%s supports WASD and left stick" % action)
	for action in [&"fold", &"dash", &"active_item", &"pause_game"]:
		_check(_has_event_type(action, "InputEventKey") and _has_event_type(action, "InputEventJoypadButton"), "%s supports one-hand keyboard and controller" % action)
	_check(_has_physical_key(&"move_up", KEY_W) and _has_physical_key(&"move_left", KEY_A) and _has_physical_key(&"move_down", KEY_S) and _has_physical_key(&"move_right", KEY_D), "movement uses the familiar WASD diamond")
	_check(_has_physical_key(&"fold", KEY_SPACE) and _has_physical_key(&"dash", KEY_SHIFT) and _has_physical_key(&"active_item", KEY_Q), "combat actions stay under one left hand")
	_check(_has_joy_button(&"fold", JOY_BUTTON_A) and _has_joy_button(&"dash", JOY_BUTTON_B) and _has_joy_button(&"active_item", JOY_BUTTON_X) and _has_joy_button(&"pause_game", JOY_BUTTON_START), "controller actions use A Fold, B dash, X active, Start pause")

	var player_scene := load("res://scenes/player.tscn") as PackedScene
	var player := player_scene.instantiate() as FoldlightPlayer if player_scene != null else null
	_check(player != null, "live player scene loads for input dispatch")
	if player != null:
		root.add_child(player)
		await process_frame
		player.configure_roguelite_combat(true)
		player.set_play_enabled(true)
		player._unhandled_input(_action_event(&"fold", true))
		_check(player.folding, "Fold press reaches the live player")
		player._unhandled_input(_action_event(&"fold", false))
		_check(not player.folding and player.get_fold_cooldown_remaining() > 0.9, "Fold release reaches the live cooldown")
		player.simulate_combat_cooldowns(1.1)
		Input.action_press(&"move_right")
		player._unhandled_input(_action_event(&"dash", true))
		player._physics_process(0.04)
		Input.action_release(&"move_right")
		_check(player.dash_component.is_dashing() and player.velocity.x > 0.0, "dash input reads the held movement direction")
		var active_uses := [0]
		player.active_item_used.connect(func(_item_id: StringName) -> void: active_uses[0] += 1)
		player._unhandled_input(_action_event(&"active_item", true))
		_check(active_uses[0] == 1, "active-item input reaches the equipped single slot")
		player.queue_free()
		await process_frame

	var game_scene := load("res://scenes/main.tscn") as PackedScene
	var game := game_scene.instantiate() as FoldlightGame if game_scene != null else null
	_check(game != null, "release scene loads for pause and menu navigation")
	if game != null:
		root.add_child(game)
		await process_frame
		await process_frame
		var session := game.get_node("RogueSession") as FoldlightRogueSessionController
		session.persist_profile = false
		session.start_new_run()
		await process_frame
		session._unhandled_input(_action_event(&"pause_game", true))
		_check(session._paused and session.presentation.screen_kind == &"pause", "pause input freezes the live run and opens the pause screen")
		session._unhandled_input(_action_event(&"pause_game", true))
		_check(not session._paused and session.presentation.screen_kind == &"hud", "the same input resumes safely")
		game.queue_free()
		await process_frame

	_finish()


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	return event


func _has_event_type(action: StringName, class_name_value: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event.get_class() == class_name_value:
			return true
	return false


func _has_physical_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == key:
			return true
	return false


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_INPUT_CONTRACT_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_INPUT_CONTRACT_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
