extends SceneTree

## Real session overlays must preserve both warning time and temporary hazards.
## Countdown continues through normal engine frames after resuming combat.
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	# Keep authored encounter scheduling out of this bounded lifetime fixture.
	session.set_physics_process(false)
	var combat := session.world.combat_runtime
	combat.clear_combat()
	var player := session.player
	player.global_position = Vector2(1680, 1180)
	var original_health := player.health
	var effects := _spawn_effects(combat, player.global_position)
	await physics_frame
	await physics_frame
	await process_frame
	_check(player.has_status(&"bound_crease") and is_equal_approx(player.status_effects.get_move_multiplier(), 0.70), "temporary circle still applies the real 30 percent binding slow")
	_check(player.health == original_health and not player.has_status(&"wet_ink"), "binding circle neither damages nor applies permanent wet-ink recovery loss")
	var zone := effects[0] as FoldlightInkDenialZone
	_check(is_equal_approx((zone.collision_shape.shape as CircleShape2D).radius, 165.0) and is_equal_approx(zone.duration, 0.5) and is_equal_approx(zone.movement_multiplier, 0.72), "temporary art keeps the configured circle geometry and gameplay values")
	_check(not zone.z_as_relative and zone.z_index > combat.room.terrain_container.z_index and zone.z_index < player.z_index and zone.z_index < combat.room.projectile_container.z_index and zone.z_index < (effects[2] as Node2D).z_index, "binding floor renders above permanent terrain and below the real player, bullets and boss warnings")
	var pause_key := InputEventKey.new()
	pause_key.keycode = KEY_ESCAPE
	pause_key.pressed = true
	root.push_input(pause_key)
	var paused_times := _times(effects)
	var late_effects := _spawn_effects(combat, player.global_position + Vector2(500, 0))
	var late_times := _times(late_effects)
	await create_timer(0.65).timeout
	_check(session.is_paused() and _same_times(effects, paused_times), "mapped Escape preserves existing zones and both warnings beyond their normal lifetime")
	_check(_same_times(late_effects, late_times), "effects created while combat is inactive inherit its paused state")
	session._resume_game()
	await create_timer(0.10).timeout
	_check(_advanced(effects, paused_times) and _advanced(late_effects, late_times), "resume advances all three effect clocks without restarting their lifetime")

	session._mechanic_intro_queue.append({"content_id": &"drifter", "title": "test", "body": "test", "preview_kind": &"enemy"})
	session._show_next_mechanic_briefing()
	var briefing_times := _times(effects)
	await create_timer(0.65).timeout
	_check(session.presentation.screen_kind == &"mechanic_intro" and _same_times(effects, briefing_times), "mechanic briefing preserves temporary danger and warning time")
	session._on_mechanic_card_dismissed(&"drifter")
	await create_timer(0.65).timeout
	_check(_all_expired(effects) and _all_expired(late_effects), "resumed effects expire after their remaining combat time")

	var reward_effects := _spawn_effects(combat, player.global_position)
	session._on_encounter_cleared({"duration": 30.0})
	var reward_times := _times(reward_effects)
	await create_timer(0.65).timeout
	_check(session.presentation.screen_kind == &"reward" and _same_times(reward_effects, reward_times), "reward selection freezes the same temporary effects while the world remains visible")
	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_TEMPORARY_HAZARD_PAUSE: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _spawn_effects(combat: FoldlightRogueCombatRuntime, origin: Vector2) -> Array[Node]:
	combat._on_zone_requested({"position": origin, "radius": 165.0, "duration": 0.5, "movement_multiplier": 0.72})
	var zone: Node = combat.room.projectile_container.get_children().back()
	combat._on_spawn_telegraph({"spawn_position": origin + Vector2(250, 0)}, 0.5)
	var spawn_warning: Node = combat.room.get_children().back()
	combat._on_boss_telegraph_requested({"origin": origin + Vector2(-250, 0), "target_position": origin, "duration": 0.5, "pattern_id": &"ink_partition", "zone_radius": 165.0})
	var boss_warning: Node = combat.room.projectile_container.get_children().back()
	return [zone, spawn_warning, boss_warning]


func _times(effects: Array[Node]) -> Array[float]:
	var result: Array[float] = []
	for effect in effects:
		if not is_instance_valid(effect):
			result.append(-1.0)
		else:
			result.append(float(effect.get("_remaining" if effect is FoldlightInkDenialZone else "remaining")))
	return result


func _same_times(effects: Array[Node], expected: Array[float]) -> bool:
	var current := _times(effects)
	for index in current.size():
		if current[index] <= 0.0 or not is_equal_approx(current[index], expected[index]):
			return false
	return true


func _advanced(effects: Array[Node], expected: Array[float]) -> bool:
	var current := _times(effects)
	for index in current.size():
		if current[index] <= 0.0 or current[index] >= expected[index] - 0.02:
			return false
	return true


func _all_expired(effects: Array[Node]) -> bool:
	for effect in effects:
		if is_instance_valid(effect):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
