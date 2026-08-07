extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	var placements: Array[Dictionary] = [
		{"id": &"wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(700, 500), "size": Vector2(220, 80)},
		{"id": &"pillar", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(1100, 500), "size": Vector2(140, 140)},
		{"id": &"ink", "kind": FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, "position": Vector2(500, 900), "size": Vector2(300, 180)},
		{"id": &"current", "kind": FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, "position": Vector2(1100, 900), "size": Vector2(360, 160), "direction": Vector2.RIGHT, "strength": 1.0},
		{"id": &"sun", "kind": FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, "position": Vector2(1500, 900), "size": Vector2(280, 180), "strength": 1.0},
		{"id": &"thorn", "kind": FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, "position": Vector2(1900, 900), "size": Vector2(250, 180), "strength": 1.0},
	]
	_check(world.load_room(player, &"terrain_combat", Vector2(2200, 1300), placements, Color(0.3, 0.86, 0.82), 99).is_empty(), "tactical terrain room configures")
	world.activate()
	var combat := world.combat_runtime
	player.global_position = Vector2(500, 900)
	combat._update_terrain_effects(0.1)
	_check(player.has_status(&"wet_ink"), "ink terrain continuously applies its readable slow")
	player.global_position = Vector2(1100, 900)
	player.velocity = Vector2.ZERO
	combat._update_terrain_effects(0.1)
	_check(player.velocity.x > 40.0, "current lane physically pushes the player")
	player.global_position = Vector2(1500, 900)
	player.focus = 0.05
	combat._update_terrain_effects(0.5)
	_check(player.has_status(&"sunlit") and player.focus > 0.05, "sun patch grants readable movement and focus upside")
	player.global_position = Vector2(1900, 900)
	player.health = player.max_health
	player.invulnerability = 0.0
	combat._update_terrain_effects(0.1)
	_check(player.health == player.max_health - 1, "thorn paper is an explicit negative terrain hazard")
	var thorn_enemy := combat._spawn_enemy_from_entry({"enemy_id": &"paper_drifter", "spawn_position": Vector2(1900, 900)}, false)
	var thorn_health := float(thorn_enemy.get("health"))
	combat._update_terrain_effects(0.1)
	_check(float(thorn_enemy.get("health")) < thorn_health, "thorn paper can be deliberately used against enemies")

	var wall_shot := combat._spawn_projectile({"origin": Vector2(700, 500), "velocity": Vector2.RIGHT * 200.0, "hostile": true, "reflectable": true, "lifetime": 2.0})
	_check(combat._resolve_projectile_terrain(wall_shot, 0.0), "paper wall absorbs projectiles and creates real cover")
	var pillar_shot := combat._spawn_projectile({"origin": Vector2(1170, 500), "velocity": Vector2.LEFT * 200.0, "hostile": true, "reflectable": true, "lifetime": 2.0})
	var before := pillar_shot.velocity
	_check(not combat._resolve_projectile_terrain(pillar_shot, 0.0) and not pillar_shot.velocity.is_equal_approx(before), "refraction pillar bends ordinary bullets instead of acting like decoration")
	var black_shot := combat._spawn_projectile({"origin": Vector2(1100, 500), "velocity": Vector2.RIGHT * 200.0, "hostile": true, "reflectable": false, "lifetime": 2.0})
	_check(combat._resolve_projectile_terrain(black_shot, 0.0), "solid cover still stops unreflectable black-gold shots")

	world.queue_free()
	player.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_TERRAIN_COMBAT_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_TERRAIN_COMBAT_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
