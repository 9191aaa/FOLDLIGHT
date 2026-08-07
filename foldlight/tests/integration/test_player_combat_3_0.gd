extends SceneTree

## Player-facing 3.0 contract: small honest hitbox, movement-first cadence, and bounded feedback.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(InputMap.has_action(&"dash") and _action_has_keyboard_and_gamepad(&"dash"), "dash has keyboard and controller bindings")
	_check(InputMap.has_action(&"active_item") and _action_has_keyboard_and_gamepad(&"active_item"), "active item has keyboard and controller bindings")

	var packed := load("res://scenes/player.tscn") as PackedScene
	var player := packed.instantiate() as FoldlightPlayer if packed != null else null
	_check(player != null, "3.0 composed player scene loads")
	if player == null:
		_finish()
		return
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	var collision := player.get_node("CollisionShape2D") as CollisionShape2D
	var shape := collision.shape as CircleShape2D
	_check(is_equal_approx(player.get_hit_radius(), 13.0) and is_equal_approx(shape.radius, 13.0), "roguelite body and primitive collision radius shrink from eighteen to thirteen")
	_check(player.scale.is_equal_approx(Vector2.ONE), "player physics body is never scaled to change size")
	_check(player.get_capture_capacity() == 8, "roguelite Fold uses an eight-light base reservoir")

	_check(player.try_begin_fold(), "ready Fold begins through its public action API")
	player.release_fold_action()
	_check(is_equal_approx(player.get_fold_cooldown_remaining(), 1.5), "Fold release starts the 1.5 second internal cooldown")
	_check(not player.try_begin_fold(), "Fold cannot be mashed again during its internal cooldown")
	player.simulate_combat_cooldowns(1.4)
	_check(not player.try_begin_fold(), "Fold remains locked until the whole 1.5 second cooldown elapses")
	player.simulate_combat_cooldowns(0.11)
	_check(player.try_begin_fold(), "Fold becomes ready again after the full cooldown")
	player.captured = 1
	_check(not player.request_dash(Vector2.RIGHT), "loaded Fold cannot be discarded by a dash")
	player.cancel_fold()

	var start := player.position
	_check(player.request_dash(Vector2.RIGHT), "ready directional dash starts")
	player._physics_process(0.09)
	_check(player.position.x > start.x + 60.0 and player.invulnerability > 0.0, "dash produces a fast movement burst with a short safety window")
	_check(not player.request_dash(Vector2.RIGHT), "dash respects its own cooldown")
	player.simulate_combat_cooldowns(2.1)
	_check(player.request_dash(Vector2.DOWN), "dash recharges independently from Fold")

	player.set_body_size_multiplier(0.82)
	_check(is_equal_approx(player.get_hit_radius(), 10.66) and is_equal_approx((collision.shape as CircleShape2D).radius, 10.66), "tiny in-run boon changes both reported and physical hit radius")
	player.set_body_size_multiplier(1.22)
	_check(is_equal_approx(player.get_hit_radius(), 15.86) and player.scale.is_equal_approx(Vector2.ONE), "large debuff enlarges the primitive shape without scaling the physics body")

	var weapon_mount := player.get_node("WeaponMount") as FoldlightWeaponMount
	var fired := [0]
	weapon_mount.fire_requested.connect(func(_definition: FoldlightRogueWeaponDefinition) -> void: fired[0] += 1)
	weapon_mount.tick(0.56, true)
	_check(fired[0] == 1, "starter automatic weapon requests a shot without extra input")
	_check(player.request_active_item(), "equipped active item fires when ready")
	_check(not player.request_active_item(), "active item cannot be spammed during cooldown")

	var feedback := player.get_node("FeedbackBudget") as FoldlightFeedbackBudget
	var batches := [0]
	var hit_stops := [0]
	feedback.impact_batch_requested.connect(func(_weight: float, _count: int) -> void: batches[0] += 1)
	feedback.hit_stop_requested.connect(func(_duration: float) -> void: hit_stops[0] += 1)
	for index in 120:
		feedback.register_impact(0.2, false)
	feedback.tick(0.08)
	_check(batches[0] == 1 and hit_stops[0] == 0, "one hundred ordinary hits aggregate into one feedback batch without hit-stop")
	feedback.register_impact(1.0, true)
	_check(hit_stops[0] == 1, "critical break may request one capped hit-stop")

	player.configure_roguelite_combat(false)
	_check(is_equal_approx(player.get_hit_radius(), 18.0) and player.get_capture_capacity() == 16, "Classic Voyage restores the exact 2.1 hitbox and Fold capacity")
	_check(not player.request_dash(Vector2.RIGHT), "dash remains isolated from Classic Voyage")

	player.queue_free()
	await process_frame
	_finish()


func _action_has_keyboard_and_gamepad(action: StringName) -> bool:
	var has_key := false
	var has_pad := false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			has_key = true
		elif event is InputEventJoypadButton:
			has_pad = true
	return has_key and has_pad


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PLAYER_COMBAT_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PLAYER_COMBAT_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
