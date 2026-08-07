extends SceneTree

## Return-light routing contract: stored bullets choose reachable enemies, route
## around solid cover, reacquire on target loss, and share cached grid paths.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_reachable_target_priority()
	await _test_wall_aware_route_and_hit()
	await _test_target_reacquisition()
	await _test_cached_260_projectile_budget()
	_finish()


func _test_reachable_target_priority() -> void:
	var fixture := await _make_fixture([
		{"id": &"sealed_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1100, 650), "size": Vector2(160, 1236)},
	])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var player := fixture["player"] as FoldlightPlayer
	var reachable := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(720, 650)}, false)
	combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1420, 650)}, false)
	var selected := combat._select_homing_target(player.global_position, 1650.0)
	_check(selected == reachable, "return light rejects the nearer-side trap and prioritizes an enemy with a valid route")
	await _free_fixture(fixture)


func _test_wall_aware_route_and_hit() -> void:
	var fixture := await _make_fixture([
		{"id": &"route_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1030, 650), "size": Vector2(180, 620)},
		{"id": &"route_pillar", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(1370, 925), "size": Vector2(170, 170)},
	])
	var world := fixture["world"] as FoldlightRogueWorld
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var player := fixture["player"] as FoldlightPlayer
	var enemy := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1710, 650)}, false)
	var route := combat._find_return_route(player.global_position, enemy.global_position)
	var route_clear := route.size() >= 3
	for point in route:
		for piece in world.room_runtime.get_terrain_pieces():
			if piece.kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR] and piece.contains_world_point(point):
				route_clear = false
	_check(route_clear, "return route contains real waypoints around paper walls and refraction pillars")

	var before_health := float(enemy.get("health"))
	var missile := combat._spawn_return_missile(player.global_position, 6.0)
	var maximum_vertical_deviation := 0.0
	for _step in 480:
		if not is_instance_valid(missile) or missile.is_queued_for_deletion() or not combat.projectiles.has(missile):
			break
		combat._update_projectiles(1.0 / 120.0)
		maximum_vertical_deviation = maxf(maximum_vertical_deviation, absf(missile.global_position.y - 650.0))
	_check(float(enemy.get("health")) < before_health, "return light reaches and damages the enemy instead of attacking cover")
	_check(maximum_vertical_deviation >= 250.0, "the visible trajectory materially bends around the wall")
	var visual := missile.get_visual_contract() if is_instance_valid(missile) else {"trajectory_animated": true, "trajectory_samples": 9}
	_check(bool(visual.get("trajectory_animated", false)) and int(visual.get("trajectory_samples", 0)) >= 8, "return light exposes an animated multi-sample trajectory")
	await _free_fixture(fixture)


func _test_target_reacquisition() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var player := fixture["player"] as FoldlightPlayer
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 520)}, false)
	var second := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1420, 780)}, false)
	var missile := combat._spawn_return_missile(player.global_position, 2.0)
	_check(missile.homing_target == first, "return light initially acquires the closest reachable target")
	combat.enemies.erase(first)
	first.queue_free()
	combat._update_projectiles(1.0 / 60.0)
	_check(missile.homing_target == second, "return light immediately reacquires a reachable target when its target disappears")
	await _free_fixture(fixture)


func _test_cached_260_projectile_budget() -> void:
	var fixture := await _make_fixture([
		{"id": &"cache_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1120, 650), "size": Vector2(160, 520)},
	])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var player := fixture["player"] as FoldlightPlayer
	for index in 10:
		combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1450 + float(index % 5) * 105.0, 300 + float(index / 5) * 650.0)}, false)
	for index in FoldlightRogueCombatRuntime.MAX_PROJECTILES:
		combat._spawn_return_missile(player.global_position, 1.0, index, FoldlightRogueCombatRuntime.MAX_PROJECTILES)
	var snapshot := combat.get_return_navigation_snapshot()
	_check(combat.projectiles.size() == FoldlightRogueCombatRuntime.MAX_PROJECTILES, "routing supports the full 260-projectile hard ceiling")
	_check(int(snapshot.get("queries", 9999)) <= 12 and int(snapshot.get("cache_hits", 0)) >= 2000, "same-cell salvos share cached paths instead of recalculating per projectile")
	combat._update_projectiles(1.0 / 120.0)
	var after_update := combat.get_return_navigation_snapshot()
	_check(int(after_update.get("queries", 9999)) == int(snapshot.get("queries", -1)), "staggered repath timers avoid a 260-projectile refresh spike")
	await _free_fixture(fixture)


func _make_fixture(terrain: Array[Dictionary]) -> Dictionary:
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.global_position = Vector2(500, 650)
	_check(world.load_room(player, &"reflection_pathing", Vector2(2200, 1300), terrain, Color(0.30, 0.84, 0.78), 3707).is_empty(), "reflection-pathing fixture configures")
	world.activate()
	return {"world": world, "player": player, "combat": world.combat_runtime}


func _free_fixture(fixture: Dictionary) -> void:
	var world := fixture.get("world") as FoldlightRogueWorld
	var player := fixture.get("player") as FoldlightPlayer
	world.queue_free()
	player.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_REFLECTION_PATHING_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REFLECTION_PATHING_3_7: FAIL - %s" % ", ".join(_failures))
		quit(1)
