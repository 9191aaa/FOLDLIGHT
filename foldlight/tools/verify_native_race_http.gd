extends SceneTree

## Run against the actual room API: two independent HTTP transports, one real
## native endless scene. The endpoint is injected via environment, never logged.
const Client = preload("res://scripts/network/native_race_client.gd")
var _failures: Array[String] = []
var _host: Node
var _guest: Node
var _bridge: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_bridge = root.get_node("WebRaceBridge")
	_host = _bridge.native_client
	_host.persistence_enabled = false
	_guest = Client.new()
	_guest.persistence_enabled = false
	root.add_child(_guest)
	var endpoint := OS.get_environment("FOLDLIGHT_RACE_TEST_ENDPOINT")
	if endpoint.is_empty():
		push_error("Set FOLDLIGHT_RACE_TEST_ENDPOINT to a running v3 room API before this live verification.")
		quit(2)
		return
	_check(not Client.endpoint_error("http://untrusted.example").is_empty(), "remote plain HTTP is rejected")
	_check(not Client.endpoint_error("https://user:pass@example.com").is_empty(), "credential-bearing authority is rejected")
	_check(_host.configure_endpoint(endpoint) and _guest.configure_endpoint(endpoint), "both native transports accept the test endpoint")
	_check(not _guest.join_room("0000000", "guest"), "invalid room code never sends a request")
	_check(_host.create_room("原生主机"), "native create sends the real HTTP request")
	if not await _until(func() -> bool: return not _host.room.is_empty(), 18.0):
		_check(false, "room create succeeded")
		_finish()
		return
	_check(_guest.join_room(String(_host.room.code), "原生好友"), "second native transport joins by room code")
	if not await _until(func() -> bool: return not _guest.room.is_empty(), 18.0):
		_check(false, "room join succeeded")
		_finish()
		return
	_check(_host.room.seed == _guest.room.seed, "both platforms receive the same authoritative seed")
	_check(not _host.configure_endpoint("https://example.org"), "endpoint cannot change while the room has a player token")
	_check(_host.prepare_match() and _guest.prepare_match(), "each client prepares one match")
	_guest.runtime_ready()
	_check(not _host.prepare_match(), "the loaded native match cannot be prepared twice")
	if not await _until(func() -> bool: return _bridge.phase == &"running", 18.0):
		_check(false, "server countdown admits the real native runtime")
		_finish()
		return
	var slice: Node = current_scene
	_check(slice != null and slice.scene_file_path.ends_with("endless_survival_slice.tscn") and slice._race_started, "native ready admission begins the real shared endless scene")
	_check(slice.controller.run_seed == int(_guest.room.seed), "native scene uses the same room seed as its opponent")
	_check(_host._ready_confirmed and _guest._ready_confirmed, "both instance IDs are accepted under the current rules")
	_check(_bridge.is_native_session() and not _bridge.configure_session({}), "active native bridge identity cannot be replaced")
	var touch := root.get_node("TouchControls")
	touch._set_touch_mode(true)
	_bridge.show_native_lobby()
	_bridge.request_native_leave()
	var before_confirmation: float = slice.controller.evolution.survival_seconds
	await create_timer(0.35).timeout
	var contact := InputEventScreenTouch.new()
	contact.index = 61
	contact.position = touch.get_layout_snapshot().move
	contact.pressed = true
	touch._input(contact)
	_check(not touch._active and slice.controller.evolution.survival_seconds > before_confirmation, "native leave confirmation blocks battle touches without pausing competitive time")
	_check(touch._owned_touches.is_empty() and touch._stick_vector == Vector2.ZERO, "HUD refreshes and another thumb touch cannot steal the confirmation layer")
	contact.pressed = false
	touch._input(contact)
	var player: FoldlightPlayer = slice.player
	player.velocity = Vector2.ZERO
	var still_position := player.global_position
	_key(KEY_D, true)
	_key(KEY_E, true)
	_key(KEY_SHIFT, true)
	_key(KEY_Q, true)
	await create_timer(0.12).timeout
	_check(player.global_position.distance_to(still_position) < 1.0, "keyboard navigation cannot move the player behind the room confirmation")
	_check(not player.folding and not player.dash_component.is_dashing() and player._dash_buffer_timer == 0.0 and player._fold_buffer_timer == 0.0, "keyboard fold and dash do not leak or queue behind the room confirmation")
	_check(player.active_item_slot.cooldown_remaining == 0.0, "room confirmation cannot spend the active item through keyboard input")
	for key in [KEY_D, KEY_E, KEY_SHIFT, KEY_Q]: _key(key, false)
	var stick := InputEventJoypadMotion.new()
	stick.device = 33
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	await create_timer(0.12).timeout
	_check(player.global_position.distance_to(still_position) < 1.0, "gamepad navigation cannot move the player behind the room confirmation")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	player.active_item_slot.cooldown_remaining = 2.0
	var cooldown_before := player.active_item_slot.cooldown_remaining
	await create_timer(0.12).timeout
	_check(player.active_item_slot.cooldown_remaining < cooldown_before and slice.combat_runtime.active and player.play_enabled, "room confirmation leaves cooldowns and combat simulation active")
	var automatic_shots: Array = []
	player.weapon_mount.shot_requested.connect(func(snapshot: Dictionary) -> void: automatic_shots.append(snapshot))
	player.tick_automatic_weapons(2.0, true)
	_check(not automatic_shots.is_empty(), "automatic weapons keep firing while room controls own manual input")
	player.invulnerability = 0.0
	var health_before := player.health
	_check(player.take_hit(Vector2.LEFT) and player.health == health_before - 1, "room confirmation does not grant damage immunity")
	player.health = health_before
	_bridge.native_lobby._cancel_leave()
	_check(touch._active and slice.player.play_enabled, "cancelling native leave restores touch controls to the same running player")
	await create_timer(0.12).timeout
	var resumed_position := player.global_position
	_key(KEY_D, true)
	await create_timer(0.12).timeout
	_key(KEY_D, false)
	_check(player.global_position.x > resumed_position.x + 1.0, "cancelling native leave restores keyboard movement")
	_key(KEY_E, true)
	await physics_frame
	await physics_frame
	_check(player.folding, "cancelling native leave restores keyboard fold")
	_key(KEY_E, false)
	_key(KEY_SHIFT, true)
	await physics_frame
	await physics_frame
	_key(KEY_SHIFT, false)
	_check(player.dash_component.is_dashing(), "cancelling native leave restores keyboard dash")
	_guest.submit_report({"status": "dead", "survivalMs": 0, "kills": 0, "health": 0, "maxHealth": 6, "terminal": true})
	_guest.submit_report({"status": "alive", "survivalMs": 999000, "terminal": false})
	_check(_guest._report.status == "dead", "terminal reports cannot be overwritten by a later alive report")
	if await _until(func() -> bool: return _host.room.get("phase") == "finished" and _bridge.phase == &"terminal", 12.0):
		_check(_host.room.result.winner == _host.room.selfId, "server awards survival result from real native combat time")
		_check(not slice.combat_runtime.active and not slice.player.play_enabled, "authoritative room completion freezes native combat")
	else: _check(false, "native clients receive the authoritative result")
	_guest.leave_room()
	_host.leave_room()
	await _until(func() -> bool: return _host.room.is_empty() and _guest.room.is_empty(), 15.0)
	_check(_host.room.is_empty() and _host._token.is_empty() and not _bridge.is_race_session(), "leave clears credentials and releases the bridge for a new match")
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn", "leaving a native race returns safely to the common title")
	_finish()

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false

func _check(value: bool, label: String) -> void:
	if value: print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _finish() -> void:
	if _guest != null: _guest.queue_free()
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_NATIVE_RACE_HTTP: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
