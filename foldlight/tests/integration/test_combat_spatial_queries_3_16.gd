extends SceneTree

var _failures: Array[String] = []
var _defeats: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	var placements: Array[Dictionary] = [
		{"id": &"rotated", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(760, 500), "size": Vector2(310, 65), "rotation": 0.65},
		{"id": &"pillar", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(1200, 500), "size": Vector2(140, 140)},
	]
	_check(world.load_room(player, &"spatial", Vector2(2400, 1400), placements, Color.WHITE, 316).is_empty(), "real rotated cover fixture loads")
	var room := world.room_runtime
	var combat := world.combat_runtime
	world.activate()
	combat.set_physics_process(false)
	var walls := room.get_terrain_pieces()
	var equivalent := true
	for x in range(550, 1400, 11):
		for y in range(300, 710, 13):
			var point := Vector2(x, y)
			var expected: Array = []
			var actual: Array = []
			for piece in walls:
				if piece.contains_world_point(point):
					expected.append(piece.placement_id)
			for piece: FoldlightTerrainPiece in room.get_terrain_candidates(point):
				if piece.contains_world_point(point):
					actual.append(piece.placement_id)
			equivalent = equivalent and expected == actual
	_check(equivalent, "spatial broad phase exactly matches full scan over rotated walls, circular pillars and cell edges")
	var wall := walls[0]
	wall.global_position += Vector2(500, 400)
	wall.force_update_transform()
	_check(room.get_terrain_candidates(wall.global_position).has(wall) and not room.get_terrain_candidates(Vector2(760, 500)).has(wall), "moving terrain invalidates cached cells")
	wall.configure({"id": &"resized", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(900, 1100), "size": Vector2(640, 70)})
	_check(room.get_terrain_candidates(Vector2(1200, 1100)).has(wall), "reconfiguring terrain dimensions invalidates cached cells")
	room.terrain_container.remove_child(wall)
	wall.queue_free()
	_check(not room.get_terrain_candidates(Vector2(1200, 1100)).has(wall), "removed terrain cannot remain in spatial buckets")
	var actor := combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(320, 850)}, false)
	actor.set("health", 100.0)
	var shape := actor.get_node("CollisionShape2D") as CollisionShape2D
	var radius := (shape.shape as CircleShape2D).radius
	var hit := combat._spawn_projectile({"origin": actor.global_position + Vector2(radius + 7.0, 0), "velocity": Vector2.ZERO, "hostile": false, "damage": 1.0})
	combat._update_projectiles(0.0)
	_check(is_equal_approx(float(actor.get("health")), 99.0) and not combat.projectiles.has(hit), "friendly projectile hits at exact circular edge across an enemy bucket boundary")
	var miss := combat._spawn_projectile({"origin": actor.global_position + Vector2(radius + 7.1, 0), "velocity": Vector2.ZERO, "hostile": false, "damage": 1.0})
	combat._update_projectiles(0.0)
	_check(is_equal_approx(float(actor.get("health")), 99.0) and combat.projectiles.has(miss), "broad phase never turns a nearby miss into a hit")
	shape.disabled = true
	combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.ZERO, "hostile": false})
	combat._update_projectiles(0.0)
	_check(is_equal_approx(float(actor.get("health")), 99.0), "disabled hitboxes stay noncollidable")
	shape.disabled = false
	actor.global_position = Vector2(1680, 850)
	combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.ZERO, "hostile": false})
	combat._update_projectiles(0.0)
	_check(is_equal_approx(float(actor.get("health")), 98.0), "next projectile step uses an actor's new cell")
	var oversized := combat._spawn_projectile({"origin": actor.global_position + Vector2(100, 0), "velocity": Vector2.ZERO, "hostile": false})
	oversized.radius = 100.0
	combat._update_projectiles(0.0)
	_check(is_equal_approx(float(actor.get("health")), 97.0), "future oversized bullets safely fall back to exact checks beyond the current radius budget")
	combat.enemy_defeated_detailed.connect(func(_id: StringName, entry: Dictionary) -> void: _defeats.append(entry))
	_check(combat.retire_directed_enemy(actor) and not combat.retire_directed_enemy(actor) and _defeats.is_empty(), "retirement removes once without emitting kill or reward events")
	var captain := combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1500, 850), "is_captain": true}, false)
	var campaign := combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1700, 850)}, true)
	_check(not combat.retire_directed_enemy(captain) and not combat.retire_directed_enemy(campaign), "retirement protects captains and campaign encounter quota")
	_check(combat.retire_directed_enemy(captain, true) and not combat.retire_directed_enemy(campaign, true) and _defeats.is_empty(), "mode may explicitly retire its expired captain without bypassing room quota or granting a kill")
	var bomber := combat._spawn_enemy_from_entry({"enemy_id": &"cinder_mine", "spawn_position": Vector2(1800, 850)}, false) as FoldlightCinderMine
	for _step in 23:
		bomber.advance_simulation(0.1, bomber.global_position)
	_check(_defeats.size() == 1 and not bool(_defeats[0].grants_kill_credit) and _defeats[0].defeat_reason == &"self_detonation", "self explosion retires threat without natural-kill credit")
	bomber = combat._spawn_enemy_from_entry({"enemy_id": &"cinder_mine", "spawn_position": Vector2(1800, 850)}, false) as FoldlightCinderMine
	bomber.take_damage(100.0)
	_check(_defeats.size() == 2 and bool(_defeats[1].grants_kill_credit) and _defeats[1].defeat_reason == &"damage", "defusing bomber by damage still grants natural-kill credit")
	combat.clear_combat()
	world.queue_free()
	player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	if _failures.is_empty():
		print("FOLDLIGHT_COMBAT_SPATIAL_QUERIES_3_16: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_COMBAT_SPATIAL_QUERIES_3_16: FAIL ", _failures)
		quit(1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
