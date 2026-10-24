extends SceneTree

const Target = preload("res://scripts/endless/endless_objective_target.gd")
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"dash_blast_contract", Vector2(2880,1620), [], Color.WHITE, 318)
	world.activate()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var combat := world.combat_runtime
	await physics_frame
	_test_path_union_and_replay(combat)
	await process_frame
	_test_real_dash_signal(combat, player)
	await process_frame
	_test_guarded_targets(combat)
	await process_frame
	await _test_wall(combat)
	world.queue_free()
	player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_DASH_BLAST_COMBAT_3_18: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _enemy(combat: FoldlightRogueCombatRuntime, point: Vector2, id: StringName = &"drifter") -> Node2D:
	var actor := combat._spawn_enemy_from_entry({"enemy_id": id, "spawn_position": point}, false)
	actor.set("health", 100.0)
	return actor


func _blast(serial: int, path: PackedVector2Array, damage: float = 10.0, radius: float = 110.0) -> Dictionary:
	return {"enabled": true, "dash_serial": serial, "path": path, "radius": radius, "damage": damage, "clear_projectiles": true}


func _test_path_union_and_replay(combat: FoldlightRogueCombatRuntime) -> void:
	var path := PackedVector2Array([Vector2(500,500), Vector2(800,500), Vector2(800,800)])
	var start := _enemy(combat, Vector2(450,500))
	var middle := _enemy(combat, Vector2(650,500))
	var corner := _enemy(combat, Vector2(790,520))
	var end := _enemy(combat, Vector2(800,850))
	var outside := _enemy(combat, Vector2(620,700))
	var hostile := combat._spawn_projectile({"origin": Vector2(800,650), "velocity": Vector2.ZERO, "hostile": true, "reflectable": false})
	var friendly := combat._spawn_projectile({"origin": Vector2(800,650), "velocity": Vector2.ZERO, "hostile": false})
	var distant := combat._spawn_projectile({"origin": Vector2(1200,1200), "velocity": Vector2.ZERO, "hostile": true})
	var result := combat.resolve_player_blast(_blast(1, path))
	_check(int(result.get("hit_count", 0)) == 4 and is_equal_approx(float(result.get("actual_damage", 0.0)), 40.0), "one blast reaches start, both real segments and end exactly once")
	_check(float(start.health) == 90.0 and float(middle.health) == 90.0 and float(corner.health) == 90.0 and float(end.health) == 90.0 and float(outside.health) == 100.0, "overlapping capsules never double-hit a foe or fill the untravelled diagonal")
	_check(not combat.projectiles.has(hostile) and combat.projectiles.has(friendly) and combat.projectiles.has(distant) and result.projectiles_cleared == 1, "blast clears nearby black-gold hostile bullets while preserving friendly and distant shots")
	_check(combat.resolve_player_blast(_blast(1, path)).is_empty() and float(corner.health) == 90.0, "replayed dash completion cannot duplicate damage or feedback")
	combat.set_active(false)
	_check(combat.resolve_player_blast(_blast(2, path)).is_empty(), "late completion during a paused or reward phase cannot deal damage")
	combat.set_active(true)
	_check(not combat.resolve_player_blast(_blast(2, path)).is_empty(), "rejected paused event does not consume a future valid sequence")
	combat.clear_combat()


func _test_real_dash_signal(combat: FoldlightRogueCombatRuntime, player: FoldlightPlayer) -> void:
	player.rogue_build_stats["dash_blast_level"] = 1
	player.position = Vector2(500,700)
	var target := _enemy(combat, Vector2(650,700))
	_check(player.dash_component.request(Vector2.RIGHT), "real player dash begins through the shared dash component")
	player.position = Vector2(700,700)
	player._record_dash_blast_position()
	# Upgrading after the start must not retroactively change the current dash.
	player.rogue_build_stats["dash_blast_level"] = 6
	player.dash_component.tick(0.2)
	var resolved := combat.get_dash_blast_snapshot()
	_check(float(target.health) == 90.0 and float(resolved.get("damage", 0.0)) == 10.0 and float(resolved.get("radius", 0.0)) == 110.0, "actual dash-ended signal resolves its start-time level and travelled path")
	player.dash_ended.emit()
	_check(float(target.health) == 90.0, "duplicate real dash-ended delivery is idempotent")
	player.dash_component.reset()
	_check(float(target.health) == 90.0, "dash reset never synthesizes a completion explosion")
	combat.clear_combat()


func _test_guarded_targets(combat: FoldlightRogueCombatRuntime) -> void:
	var elite := _enemy(combat, Vector2(700,600), &"shutter_seraph") as FoldlightShutterSeraph
	var boss := combat._spawn_enemy_from_entry({"boss_id": &"reef_crown_battery", "spawn_position": Vector2(800,600), "boss_options": {"arena_pressure": false}}, false) as FoldlightRogueBossActor
	var flag := Target.new()
	flag.configure({"target_id": &"blast_flag", "target_position": Vector2(760,630), "required": 80.0})
	combat.register_objective_target(flag)
	var actual: Array[float] = []
	flag.damage_reported.connect(func(_id: StringName, amount: float) -> void: actual.append(amount))
	var before := boss.health
	var path := PackedVector2Array([Vector2(600,600), Vector2(850,600)])
	combat.resolve_player_blast(_blast(1, path, 30.0))
	_check(elite.health == 100.0 and elite.phase == FoldlightShutterSeraph.Phase.CLOSED, "blast respects the elite's closed damage window")
	_check(is_equal_approx(boss.health, before - 30.0) and is_zero_approx(boss.return_meter) and boss.phase_controller.state != FoldlightBossPhaseController.State.STAGGERED, "boss blast uses normal weapon damage without fabricating return light or stagger")
	_check(flag.health == 50.0 and actual == [30.0], "physical flag receives and reports actual blast damage once")
	elite.phase = FoldlightShutterSeraph.Phase.FIRING
	combat.resolve_player_blast(_blast(2, path, 30.0))
	_check(elite.health == 70.0, "the same elite becomes vulnerable during its authored firing window")
	combat.clear_combat()


func _test_wall(combat: FoldlightRogueCombatRuntime) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1 << 2
	wall.collision_mask = 0
	wall.position = Vector2(800,650)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30,500)
	shape.shape = rectangle
	wall.add_child(shape)
	root.add_child(wall)
	var blocked := _enemy(combat, Vector2(840,650))
	var visible := _enemy(combat, Vector2(710,650))
	var hidden_shot := combat._spawn_projectile({"origin": Vector2(840,650), "velocity": Vector2.ZERO, "hostile": true})
	await physics_frame
	combat.resolve_player_blast(_blast(1, PackedVector2Array([Vector2(750,500), Vector2(750,800)])))
	_check(float(visible.health) == 90.0 and float(blocked.health) == 100.0 and combat.projectiles.has(hidden_shot), "solid terrain blocks both blast damage and bullet clearing across its wall")
	wall.queue_free()
	combat.clear_combat()
	await process_frame


func _check(value: bool, label: String) -> void:
	checks += 1
	print(("[PASS] " if value else "[FAIL] ") + label)
	if not value: failures.append(label)
