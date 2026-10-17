extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var bullets: Array[FoldlightRogueProjectile] = []
	var expected_positions: Array[Vector2] = []
	var expected_velocities: Array[Vector2] = []
	var redraw_requests := 0
	var motion_matches := true
	var outlines_match := true
	var maximum_tip_error := 0.0
	for index in 260:
		var bullet := FoldlightRogueProjectile.new()
		root.add_child(bullet)
		var origin := Vector2(50 + index * 5, 200)
		var velocity_value := Vector2.from_angle(float(index) * 0.17) * 245.0
		bullet.configure({"origin": origin, "velocity": velocity_value, "hostile": true, "reflectable": index % 5 != 0, "kind": index % 3, "style": &"hostile_petal", "lifetime": 8.0, "curve": 0.4})
		bullets.append(bullet)
		expected_positions.append(origin)
		expected_velocities.append(velocity_value)
	for frame in 120:
		var time_scale := 0.55 if frame % 3 == 0 else 1.0
		var step := (1.0 / 60.0) * time_scale
		for index in bullets.size():
			var bullet := bullets[index]
			expected_velocities[index] = expected_velocities[index].rotated(0.4 * step)
			expected_positions[index] += expected_velocities[index] * step
			bullet.advance_simulation(1.0 / 60.0, time_scale)
			motion_matches = motion_matches and bullet.velocity.is_equal_approx(expected_velocities[index]) and bullet.global_position.is_equal_approx(expected_positions[index])
			var length := 18.0 if not bullet.reflectable else (12.0 if bullet.projectile_kind == 0 else 9.0)
			var expected_tip := Vector2.from_angle(bullet.velocity.angle() + sin(bullet.age * 5.0) * 0.08) * length
			var actual_tip := bullet.to_global(Vector2.RIGHT * length) - bullet.global_position
			maximum_tip_error = maxf(maximum_tip_error, actual_tip.distance_to(expected_tip))
			# Subtracting a small tip from a far world coordinate loses float32
			# precision; compare in pixels rather than relative error near zero.
			outlines_match = outlines_match and actual_tip.distance_to(expected_tip) < 0.001
	for bullet in bullets:
		redraw_requests += int(bullet.get_visual_budget_snapshot()["redraw_requests"])
		bullet.queue_free()
	_check(motion_matches, "31,200 curved and slowed projectile steps retain exact world-space motion")
	_check(outlines_match, "all retained hostile silhouettes reproduce the previous tip direction and sway")
	_check(redraw_requests == 260, "260 hostile bullets request geometry once, with no per-step rebuild")
	print("FOLDLIGHT_PROJECTILE_REDRAW_BUDGET previous_requests=%d retained_requests=%d simulation_steps=%d" % [260 * 121, redraw_requests, 260 * 120])
	print("FOLDLIGHT_PROJECTILE_MAXIMUM_TIP_ERROR_PX: %.6f" % maximum_tip_error)
	var returned := FoldlightRogueProjectile.new()
	root.add_child(returned)
	returned.configure({"origin": Vector2(100, 100), "velocity": Vector2(400, 180), "hostile": false, "style": &"return_light", "lifetime": 8.0})
	for frame in 60:
		returned.advance_simulation(1.0 / 60.0)
	_check(returned.get_navigation_snapshot()["trail_samples"] == 9 and returned.get_visual_budget_snapshot()["redraw_requests"] == 61 and returned.rotation == 0.0, "returned light keeps its animated nine-sample world-space trail without rotation")
	returned.queue_free()
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	world.load_room(player, &"visual_budget", Vector2(2880, 1620), [], Color.WHITE, 411)
	world.activate()
	world.set_physics_process(false)
	var combat := world.combat_runtime
	combat.set_physics_process(false)
	player.global_position = Vector2(1000, 800)
	player.invulnerability = 0.0
	var health_before := player.health
	var hostile := combat._spawn_projectile({"origin": player.global_position, "velocity": Vector2.DOWN * 245, "hostile": true, "reflectable": true, "style": &"hostile_petal"})
	combat._update_projectiles(0.0)
	_check(player.health == health_before - 1 and not combat.projectiles.has(hostile), "rotated cached hostile shape keeps the existing one-heart radius collision")
	player.invulnerability = 0.0
	player.folding = true
	var captured_before := player.captured
	combat._spawn_projectile({"origin": player.global_position + Vector2(0, 40), "velocity": Vector2.LEFT * 245, "hostile": true, "reflectable": true, "style": &"hostile_petal"})
	combat._update_projectiles(0.0)
	_check(player.captured == captured_before + 1 and combat.projectiles.is_empty(), "cached hostile geometry remains captureable with the original fold radius")
	player.folding = false
	var pillar := FoldlightTerrainPiece.new()
	combat.room.terrain_container.add_child(pillar)
	pillar.configure({"id": &"visual_pillar", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(1400, 800), "size": Vector2(100, 100)})
	var deflected := combat._spawn_projectile({"origin": Vector2(1430, 800), "velocity": Vector2.LEFT * 245, "hostile": true, "reflectable": true, "style": &"hostile_petal"})
	combat._resolve_projectile_terrain(deflected, 0.0)
	_check(absf(deflected.rotation - deflected.velocity.angle()) < 0.001 and is_equal_approx(deflected.velocity.length(), 245.0), "real pillar deflection updates the cached silhouette in the same frame without changing speed")
	combat._remove_projectile(deflected)
	var rng_before := combat._rng.state
	for index in 512:
		combat._add_active_flash(Vector2(index, 0), Color.WHITE, 66.0, 0.24)
	_check(combat._active_flashes.size() == FoldlightRogueCombatRuntime.MAX_ACTIVE_FLASHES and combat._active_flashes[-1]["position"] == Vector2(511, 0), "512 cosmetic flashes retain only the newest bounded set")
	_check(combat._rng.state == rng_before and combat.projectiles.is_empty(), "visual flash limiting never consumes combat RNG or spawns entities")
	combat._update_visual_feedback(1.0)
	_check(combat._active_flashes.is_empty(), "bounded flashes fully expire after their authored lifetime")
	world.queue_free()
	player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_PROJECTILE_VISUAL_BUDGET: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
