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
	var terrain: Array[Dictionary] = [{"id": &"wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1600, 650), "size": Vector2(180, 120)}]
	_check(world.load_room(player, &"fold_2_0_contract", Vector2(2200, 1300), terrain, Color(0.35, 0.88, 0.84), 2020).is_empty(), "2.0 Fold fixture configures")
	world.activate()
	player.global_position = Vector2(1100, 650)
	_check(player.get_capture_capacity() == 8, "Fold has an eight-light base reservoir")
	_check(player.try_begin_fold(), "ready Fold begins charging")
	player.release_fold_action()
	_check(is_equal_approx(player.get_fold_cooldown_remaining(), 1.5), "every charged Fold release starts a 1.5 second cooldown")
	player.simulate_combat_cooldowns(1.4)
	_check(not player.try_begin_fold(), "Fold remains unavailable before the 1.5 second cooldown ends")
	player.simulate_combat_cooldowns(0.11)
	_check(player.try_begin_fold(), "Fold becomes available after the full cooldown")
	player.cancel_fold()
	_check(is_equal_approx(player.dash_component.base_cooldown, 2.0), "dash base cooldown is exactly two seconds")

	var combat := world.combat_runtime
	combat._on_player_fold_released(8, 1.0)
	var returns := combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.style == &"return_light")
	_check(returns.size() == 8, "every absorbed bullet becomes one return light")
	var latest_delay := 0.0
	var launch_angles: Array[float] = []
	for projectile: FoldlightRogueProjectile in returns:
		var delay_variant: Variant = projectile.get("launch_delay")
		if delay_variant is float:
			latest_delay = maxf(latest_delay, float(delay_variant))
		launch_angles.append(projectile.velocity.angle())
	_check(latest_delay >= 0.24, "return light leaves in the 2.0 staggered ribbon cadence")
	launch_angles.sort()
	_check(launch_angles.size() == 8 and launch_angles.back() - launch_angles.front() >= 2.3, "return light preserves the wide 2.0 launch fan")
	_check(returns.all(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.homing_strength >= 7.0 and projectile.get("orbit_anchor") == player), "the whole ribbon orbits the player briefly, then homes automatically")
	var queued_return := returns.back() as FoldlightRogueProjectile
	queued_return.global_position = Vector2(1600, 650)
	_check(not combat._resolve_projectile_terrain(queued_return, 0.0), "cover cannot erase stored light while the ribbon is waiting to launch")
	queued_return.launch_delay = 0.0
	_check(not combat._resolve_projectile_terrain(queued_return, 0.0) and float(queued_return.get_meta("terrain_grace", 0.0)) > 0.0, "launched return light recovers from solid cover for the later routed-missile contract")

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
		print("FOLDLIGHT_FOLD_2_0_HOTFIX: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_FOLD_2_0_HOTFIX: FAIL - %s" % ", ".join(_failures))
		quit(1)
