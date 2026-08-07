extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[TRACE] reuse test: load scene")
	var packed := load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene
	print("[TRACE] reuse test: instantiate scene")
	var slice := packed.instantiate() as FoldlightEndlessSliceRuntime if packed != null else null
	_check(slice != null, "endless scene loads as the scheduling adapter")
	if slice == null:
		_finish()
		return
	print("[TRACE] reuse test: add scene")
	root.add_child(slice)
	print("[TRACE] reuse test: scene added")
	await process_frame
	await process_frame

	_check(slice.player is FoldlightPlayer, "endless instantiates the exact shared Player scene")
	_check(slice.world is FoldlightRogueWorld, "endless instantiates the exact shared RogueWorld scene")
	_check(slice.combat_runtime is FoldlightRogueCombatRuntime, "endless combat is the shared 2.0 runtime")
	_check(slice.combat_runtime.player == slice.player, "shared combat runtime is bound to the shared player")
	_check(slice.combat_runtime.room == slice.world.room_runtime, "shared combat runtime is bound to the shared room")
	_check(slice.combat_runtime.enemies.size() > 0, "the first endless wave reaches the shared enemy factory")
	for enemy in slice.combat_runtime.enemies:
		_check(enemy is FoldlightRogueEnemyActor, "every initial endless enemy is a reusable 2.0 actor")
		if enemy is FoldlightRogueEnemyActor:
			_check(StringName((enemy as FoldlightRogueEnemyActor).get_classic_contract().get("version", &"")) == &"classic_2_0_exact", "endless enemy keeps the exact 2.0 behavior/visual contract")

	slice.combat_runtime.spawn_hostile_volley({
		"origin": slice.player.global_position + Vector2(280.0, 0.0),
		"direction": Vector2.LEFT,
		"projectile_count": 3,
		"spread_radians": 0.3,
		"reflectable": true,
		"style": &"hostile_petal",
	})
	_check(slice.combat_runtime.projectiles.size() == 3, "endless volleys use the shared projectile pool")
	for projectile in slice.combat_runtime.projectiles:
		_check(projectile is FoldlightRogueProjectile, "every endless bullet is the reusable 2.0 projectile")

	_check(slice.world.room_runtime.get_terrain_pieces().size() == slice.controller.map_definition.walls.size(), "large-map cover is converted into shared TerrainPiece nodes")
	_check(slice.controller.map_runtime.get_node_or_null("AuthoredCoverCollision") == null, "the former parallel wall physics is disabled")
	var reuse := slice.get_combat_reuse_contract()
	_check(StringName(reuse.get("version", &"")) == &"classic_2_0_runtime_reuse", "runtime exposes the hard 2.0 reuse contract")
	_check(not bool(reuse.get("parallel_combat_state", true)), "runtime declares no parallel combat state")

	var source := FileAccess.get_file_as_string("res://scripts/endless/endless_slice_runtime.gd")
	for forbidden in ["func _update_player(", "func _update_enemies(", "func _update_projectiles(", "func _draw_enemy(", "var _enemies:", "var _projectiles:"]:
		_check(not source.contains(forbidden), "endless adapter forbids duplicate combat symbol %s" % forbidden)

	slice.queue_free()
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
		print("FOLDLIGHT_ENDLESS_2_0_RUNTIME_REUSE: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_2_0_RUNTIME_REUSE: FAIL - %s" % ", ".join(_failures))
		quit(1)
