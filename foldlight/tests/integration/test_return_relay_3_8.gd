extends SceneTree

## Return Relay contract: one stored return-light projectile may continue once
## after it kills a non-boss, but only toward a living, reachable, unhit enemy.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_lethal_return_reuses_one_projectile()
	await _test_relay_preserves_pierce_upgrade()
	await _test_echo_return_never_relays()
	await _test_nonlethal_return_dissipates()
	await _test_boss_kill_never_relays()
	await _test_unreachable_target_does_not_relay()
	_finish()


func _test_lethal_return_reuses_one_projectile() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 650)}, false)
	var second := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1370, 650)}, false)
	var third := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1770, 650)}, false)
	first.set("health", 1.0)
	second.set("health", 1.0)
	third.set("health", 20.0)
	var missile := combat._spawn_return_missile(first.global_position, 4.0)
	var instance_id := missile.get_instance_id()
	var projectile_count := combat.projectiles.size()
	missile.lifetime = 0.02
	missile.global_position = first.global_position
	combat._resolve_friendly_collision(missile)
	_check(combat.projectiles.size() == projectile_count, "a lethal return hit does not create or remove a projectile while relaying")
	_check(combat.projectiles.has(missile) and missile.get_instance_id() == instance_id, "return relay reuses the exact same projectile instance")
	_check(missile.return_relay_used and missile.homing_target == second, "the first lethal hit relays to the next living unhit enemy")
	_check(missile.hit_actor_ids.has(StringName(first.get("actor_id"))), "relay remembers the defeated actor and cannot reacquire it")
	var relay_snapshot := missile.get_navigation_snapshot()
	_check(bool(relay_snapshot.get("relay_used", false)) and float(relay_snapshot.get("relay_pulse", 0.0)) > 0.0, "relay starts the short gold pulse and enhanced trail state")
	var remaining_route := 0.0
	var previous_point := missile.global_position
	for waypoint_index in range(missile.navigation_waypoint_index, missile.navigation_waypoints.size()):
		remaining_route += previous_point.distance_to(missile.navigation_waypoints[waypoint_index])
		previous_point = missile.navigation_waypoints[waypoint_index]
	var required_lifetime := clampf(remaining_route / maxf(1.0, missile.homing_speed) + 0.75, 0.8, 5.6)
	_check(missile.lifetime + 0.001 >= required_lifetime, "relay restores enough lifetime to finish its cached route")

	missile.global_position = second.global_position
	combat._resolve_friendly_collision(missile)
	_check(not combat.projectiles.has(missile), "the same return light dissipates after its single relay hit")
	_check(is_instance_valid(third) and float(third.get("health")) > 0.0, "a return light cannot chain a second time to a third enemy")
	await _free_fixture(fixture)


func _test_relay_preserves_pierce_upgrade() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 650)}, false)
	var second := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1210, 650)}, false)
	var third := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1680, 650)}, false)
	first.set("health", 1.0)
	second.set("health", 20.0)
	third.set("health", 20.0)
	var missile := combat._spawn_return_missile(first.global_position, 4.0)
	missile.pierce_remaining = 1
	missile.global_position = first.global_position
	combat._resolve_friendly_collision(missile)
	_check(missile.return_relay_used and missile.pierce_remaining == 1, "the lethal relay itself does not consume luminous-pierce capacity")
	missile.global_position = second.global_position
	combat._resolve_friendly_collision(missile)
	_check(combat.projectiles.has(missile) and missile.pierce_remaining == 0, "the relayed projectile still receives its normal upgraded pierce hit")
	missile.request_navigation_refresh()
	combat._update_return_light_navigation(missile, 0.0)
	_check(missile.homing_target == third, "piercing return light immediately excludes its already-hit living target")
	await _free_fixture(fixture)


func _test_echo_return_never_relays() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 650)}, false)
	combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1370, 650)}, false)
	first.set("health", 1.0)
	var missile := combat._spawn_return_missile(first.global_position, 4.0)
	missile.is_echo = true
	missile.global_position = first.global_position
	combat._resolve_friendly_collision(missile)
	_check(not combat.projectiles.has(missile), "an echo return cannot relay and amplify the echo upgrade recursively")
	await _free_fixture(fixture)


func _test_nonlethal_return_dissipates() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 650)}, false)
	combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1370, 650)}, false)
	first.set("health", 20.0)
	var missile := combat._spawn_return_missile(first.global_position, 1.0)
	missile.global_position = first.global_position
	combat._resolve_friendly_collision(missile)
	_check(not combat.projectiles.has(missile), "a nonlethal return hit follows the normal dissipate path")
	await _free_fixture(fixture)


func _test_boss_kill_never_relays() -> void:
	var fixture := await _make_fixture([])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var boss := combat._spawn_enemy_from_entry({"boss_id": &"reef_crown_battery", "spawn_position": Vector2(760, 650)}, false)
	combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1370, 650)}, false)
	boss.set("health", 0.1)
	var missile := combat._spawn_return_missile(boss.global_position, 20.0)
	missile.global_position = boss.global_position
	combat._resolve_friendly_collision(missile)
	_check(not combat.projectiles.has(missile), "even a lethal return hit on a boss follows the normal dissipate path")
	await _free_fixture(fixture)


func _test_unreachable_target_does_not_relay() -> void:
	var fixture := await _make_fixture([
		{"id": &"sealed_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1100, 650), "size": Vector2(420, 1236)},
	])
	var combat := fixture["combat"] as FoldlightRogueCombatRuntime
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(760, 650)}, false)
	combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1420, 650)}, false)
	first.set("health", 1.0)
	var missile := combat._spawn_return_missile(first.global_position, 4.0)
	missile.global_position = first.global_position
	combat._resolve_friendly_collision(missile)
	_check(not combat.projectiles.has(missile), "a lethal return hit dissipates when no unhit enemy has an AStar route")
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
	_check(world.load_room(player, &"return_relay", Vector2(2200, 1300), terrain, Color(0.30, 0.84, 0.78), 3808).is_empty(), "return-relay fixture configures")
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
		print("FOLDLIGHT_RETURN_RELAY_3_8: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_RETURN_RELAY_3_8: FAIL - %s" % ", ".join(_failures))
		quit(1)
