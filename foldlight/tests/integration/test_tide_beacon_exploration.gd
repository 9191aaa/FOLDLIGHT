extends SceneTree

## Exercise the actual physics overlap and mapped Fold input, then verify the
## same devices respect session modals and never enter encounter/save counts.
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	var room := world.room_runtime
	var combat := world.combat_runtime
	var terrain: Array[Dictionary] = []
	_check(world.load_room(player, &"beacon_contract", Vector2(3360, 1620), terrain, Color.CYAN).is_empty(), "expanded exploration room loads")
	room.configure_tide_beacons()
	world.activate()
	var beacons := room.get_tide_beacons()
	_check(beacons.size() == 2 and beacons.all(func(beacon: FoldlightTideBeacon) -> bool: return beacon.simulation_enabled), "activation preserves both interactive beacons")
	var beacon := beacons[0]
	player.global_position = beacon.global_position + Vector2(0, 370)
	await _frames(3)
	_spawn(combat, beacon.global_position + Vector2(500, 0))
	await _begin_ready_fold(player)
	await _frames(35)
	_check(player.folding and beacon.nearby_player == null and not beacon.consumed and is_zero_approx(beacon.charge), "mapped Fold outside the physical proximity area cannot use a beacon")
	_press_fold(false)
	await _frames(20)
	player.global_position = beacon.global_position
	await _frames(3)
	_check(beacon.nearby_player == player, "Area2D detects the real player entering the shore lantern")
	await _frames(32)
	_check(not beacon.consumed and player.captured == 0, "standing at a beacon without Fold does not convert bullets")
	_spawn(combat, beacon.global_position + Vector2(510, 15))
	_spawn(combat, beacon.global_position + Vector2(520, -15))
	var sealed := _spawn(combat, beacon.global_position + Vector2(530, 30), false)
	var outside := _spawn(combat, beacon.global_position + Vector2(680, 0))
	var friendly := combat._spawn_projectile({"origin": beacon.global_position + Vector2(500, -40), "hostile": false, "velocity": Vector2.ZERO, "lifetime": 8.0})
	await _begin_ready_fold(player)
	await _frames(29)
	_check(beacon.consumed and player.captured == 3, "holding mapped Fold charges the beacon and captures distant reflectable enemy shots")
	_check(combat.projectiles.has(sealed) and combat.projectiles.has(outside) and combat.projectiles.has(friendly), "sealed, friendly and out-of-range projectiles remain untouched")
	_check(player.invulnerability > 0.0, "successful pulse provides a brief window to release safely")
	_check(room.encounter_runtime.active_enemy_count == 0 and room.encounter_runtime.state == FoldlightRoomEncounterRuntime.State.IDLE, "beacons never count as enemies or change the encounter lifecycle")
	var ordinary_after := _spawn(combat, beacon.global_position + Vector2(510, 0))
	await _frames(20)
	_check(player.captured == 3 and combat.projectiles.has(ordinary_after), "each beacon is consumed at most once per room")
	_press_fold(false)
	await _frames(2)
	_check(not player.folding and player.captured == 0 and combat.projectiles.filter(func(shot: FoldlightRogueProjectile) -> bool: return shot.style == &"return_light").size() == 3, "releasing the same input creates three real return-light projectiles")

	combat.clear_combat()
	player.global_position = beacons[1].global_position
	player.focus = 1.0
	await _frames(25)
	await _begin_ready_fold(player)
	await _frames(32)
	_check(not beacons[1].consumed, "charging with no eligible bullets does not consume the second beacon")
	player.captured = player.get_capture_capacity()
	_spawn(combat, beacons[1].global_position + Vector2(-500, 0))
	await _frames(32)
	_check(not beacons[1].consumed and player.captured == player.get_capture_capacity(), "full storage never spends a beacon")
	player.captured = player.get_capture_capacity() - 1
	await _frames(30)
	_check(beacons[1].consumed and player.captured == player.get_capture_capacity(), "pulse fills the final free slot without exceeding capture capacity")
	_press_fold(false)
	combat.clear_combat()
	room.configure_tide_beacons()
	beacon = room.get_tide_beacons()[0]
	player.global_position = beacon.global_position
	player.focus = 1.0
	await _frames(25)
	for index in 12:
		_spawn(combat, beacon.global_position + Vector2(480 + index * 4, 0))
	player.capture_capacity = 16
	await _begin_ready_fold(player)
	await _frames(30)
	_check(player.captured == 8 and combat.projectiles.filter(func(shot: FoldlightRogueProjectile) -> bool: return shot.hostile).size() == 4, "one pulse is capped at eight bullets even with a larger build")
	_press_fold(false)
	await _frames(2)
	combat.clear_combat()
	await _check_templates(room)
	world.queue_free()
	player.queue_free()
	await process_frame
	await _check_session()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_TIDE_BEACON_EXPLORATION: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _check_templates(room: FoldlightRoomRuntime) -> void:
	var layouts_safe := true
	var lanterns_clear := true
	var checked := 0
	for region in FoldlightRogueRoomTemplateCatalog.REGION_IDS:
		for template in FoldlightRogueRoomTemplateCatalog.templates_for_region(region):
			var placements: Array[Dictionary] = []
			for entry: Dictionary in template["terrain"]:
				var shifted := entry.duplicate(true)
				shifted["position"] = Vector2(entry["position"]) + Vector2(240, 0)
				placements.append(shifted)
			layouts_safe = layouts_safe and room.configure_room(template["id"], Vector2(3360, 1620), placements, Color.CYAN).is_empty()
			room.configure_tide_beacons()
			for beacon in room.get_tide_beacons():
				for piece in room.get_terrain_pieces():
					lanterns_clear = lanterns_clear and not piece.get_world_bounds(148.0).has_point(beacon.global_position)
			checked += 1
	_check(checked == 36 and layouts_safe, "all 36 translated region templates keep valid nonoverlapping terrain")
	_check(lanterns_clear, "both proximity areas are clear of all terrain and hazards in all 36 templates")
	await process_frame


func _check_session() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	session.set_physics_process(false)
	var world := session.world
	var room := world.room_runtime
	var combat := world.combat_runtime
	var player := game.player
	combat.clear_combat()
	_check(room.room_bounds.size == Vector2(3360, 1620) and player.global_position == Vector2(1680, 1180), "main expedition centers the player in the wider room")
	_check(world.camera.room_bounds == room.room_bounds and player.play_bounds == room.room_bounds.grow(-56.0), "camera and movement clamp share the actual expanded room bounds")
	player.global_position = Vector2(3300, 810)
	Input.action_press(&"move_right")
	await _frames(25)
	Input.action_release(&"move_right")
	_check(player.global_position.x <= 3304.0 and player.global_position.x > 2880.0, "real movement reaches the new shore and stops at its boundary")
	world.camera.force_follow()
	_check(is_equal_approx(world.camera.position.x, 2400.0), "camera reaches the new shore without showing beyond the map")
	player.velocity = Vector2.ZERO
	var beacon := room.get_tide_beacons()[0]
	player.global_position = beacon.global_position
	await _frames(3)
	await _begin_ready_fold(player)
	await _frames(10)
	var partial_charge := beacon.charge
	_check(partial_charge > 0.0 and partial_charge < beacon.charge_seconds, "main-mode device begins charging through gameplay input")
	var pause_key := InputEventKey.new()
	pause_key.keycode = KEY_ESCAPE
	pause_key.pressed = true
	root.push_input(pause_key)
	var paused_tide_time := room.backdrop._ambient_time
	await _frames(35)
	_check(session.is_paused() and not beacon.simulation_enabled and is_equal_approx(beacon.charge, partial_charge) and not beacon.consumed, "Escape pause freezes beacon charge and activation")
	_check(paused_tide_time > 0.0 and is_equal_approx(room.backdrop._ambient_time, paused_tide_time), "shore currents animate during combat and freeze with pause")
	_press_fold(false)
	session._resume_game()
	await _frames(2)
	session._mechanic_intro_queue.append({"content_id": &"drifter", "title": "test", "body": "test", "preview_kind": &"enemy"})
	session._show_next_mechanic_briefing()
	var mechanic_charge := beacon.charge
	await _frames(30)
	_check(not beacon.simulation_enabled and is_equal_approx(beacon.charge, mechanic_charge) and not beacon.consumed, "mechanic introduction freezes the scene device")
	session._on_mechanic_card_dismissed(&"drifter")
	session._on_encounter_cleared({"duration": 30.0})
	var reward_charge := beacon.charge
	await _frames(30)
	_check(session.presentation.screen_kind == &"reward" and not beacon.simulation_enabled and is_equal_approx(beacon.charge, reward_charge), "reward choice cannot advance beacon charge")
	var view := session._route_view_snapshot()
	_check(view["cleared_node_ids"] == session.run_controller.run_state.cleared_node_ids and not session.current_region_snapshot.has("cleared_node_ids"), "route view receives actual cleared rooms without mutating the generated region")
	var cleared_count := session.run_controller.run_state.cleared_node_ids.size()
	view["cleared_node_ids"].append(&"view_only")
	_check(session.run_controller.run_state.cleared_node_ids.size() == cleared_count, "route rendering cannot mutate saved cleared-room history")
	session._on_room_requested({"id": &"boss_contract", "category": &"boss", "depth": 6}, session.current_region_snapshot)
	_check(room.room_bounds.size == Vector2(2880, 1620) and room.get_tide_beacons().is_empty(), "boss rooms retain their original arena and have no leftover shore devices")
	game.queue_free()
	await process_frame


func _spawn(combat: FoldlightRogueCombatRuntime, origin: Vector2, reflectable: bool = true) -> FoldlightRogueProjectile:
	return combat._spawn_projectile({"origin": origin, "velocity": Vector2.ZERO, "hostile": true, "reflectable": reflectable, "lifetime": 8.0})


func _press_fold(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)


func _begin_ready_fold(player: FoldlightPlayer) -> void:
	while player.get_fold_cooldown_remaining() > 0.0 or player._hit_stop_timer > 0.0:
		await physics_frame
	_press_fold(true)


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
