extends SceneTree

## 3.0 playable-combat contract: authored encounter entries become actors,
## automatic weapons and Fold interact with real projectiles, and a clear opens exits.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_scene := load("res://scenes/roguelite/rogue_world.tscn") as PackedScene
	var player_scene := load("res://scenes/player.tscn") as PackedScene
	var world := world_scene.instantiate() as FoldlightRogueWorld if world_scene != null else null
	var player := player_scene.instantiate() as FoldlightPlayer if player_scene != null else null
	_check(world != null and player != null, "roguelite world and player scenes load together")
	if world == null or player == null:
		_finish()
		return
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.global_position = Vector2(320, 810)
	var placements: Array[Dictionary] = [
		{"id": &"center_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1440, 810), "size": Vector2(320, 90)},
	]
	_check(world.load_room(player, &"combat_contract", Vector2(2880, 1620), placements, Color(0.28, 0.84, 0.83), 44551).is_empty(), "world binds room, player, camera, and combat runtime")
	world.activate()
	var room := world.room_runtime
	var combat := world.combat_runtime
	room.configure_exits([
		{"id": &"west", "position": Vector2(10, 810), "normal": Vector2.LEFT},
		{"id": &"east", "position": Vector2(2870, 810), "normal": Vector2.RIGHT},
	])
	var entries: Array[Dictionary] = [
		{"enemy_id": &"paper_drifter", "role": FoldlightRogueEnemyDefinition.EnemyRole.FODDER, "wave": 0, "spawn_slot": &"g1", "spawn_position": Vector2(1040, 420)},
		{"enemy_id": &"paper_turret", "role": FoldlightRogueEnemyDefinition.EnemyRole.TURRET, "wave": 0, "spawn_slot": &"t1", "spawn_position": Vector2(2500, 360)},
		{"enemy_id": &"bell_binder", "role": FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, "wave": 0, "spawn_slot": &"g2", "spawn_position": Vector2(2180, 520)},
		{"enemy_id": &"ink_warden", "role": FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, "wave": 0, "spawn_slot": &"g3", "spawn_position": Vector2(2100, 930)},
	]
	_check(room.begin_encounter({"encounter_id": &"combat_contract", "errors": [], "entries": entries}).is_empty(), "authored encounter begins in the bound runtime")
	_check(room.get_doors().all(func(door: FoldlightRogueDoor) -> bool: return door.locked), "combat runtime starts behind locked physical exits")
	room.advance_encounter(room.encounter_runtime.telegraph_duration + 0.01)
	_check(combat.enemies.size() == 4, "telegraph resolution creates all four combat actors")
	_check(combat.enemies.any(func(enemy: Node2D) -> bool: return enemy is FoldlightPaperTurret) and combat.enemies.any(func(enemy: Node2D) -> bool: return enemy is FoldlightBellBinder) and combat.enemies.any(func(enemy: Node2D) -> bool: return enemy is FoldlightInkWarden), "mechanic entries instantiate their dedicated readable scenes")
	combat._physics_process(0.2)
	var binder := combat.enemies.filter(func(enemy: Node2D) -> bool: return enemy is FoldlightBellBinder)[0] as FoldlightBellBinder
	_check(not binder.get_tether_ids().is_empty() and binder.get_tether_ids().size() <= 2, "live binder selects and exposes bounded support tethers")

	var projectile_count_before := combat.projectiles.size()
	combat._physics_process(0.6)
	_check(combat.projectiles.size() > projectile_count_before and combat.projectiles.any(func(projectile: FoldlightRogueProjectile) -> bool: return not projectile.hostile), "starter weapon automatically creates a friendly in-room projectile")

	player.folding = true
	player.fold_time = 1.0
	var captured_before := player.captured
	combat.spawn_hostile_volley({"origin": player.global_position + Vector2(90, 0), "direction": Vector2.ZERO, "speed": 0.0, "projectile_count": 1, "reflectable": true})
	combat.spawn_hostile_volley({"origin": player.global_position + Vector2(115, 0), "direction": Vector2.ZERO, "speed": 0.0, "projectile_count": 1, "reflectable": false})
	combat._update_projectiles(0.01)
	_check(player.captured == captured_before + 1, "Fold captures one reflectable hostile projectile")
	_check(combat.projectiles.any(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile and not projectile.reflectable and projectile.fold_slowed), "unreflectable projectile stays dangerous but visibly slows inside Fold")
	var friendly_before_release := combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return not projectile.hostile).size()
	player.release_fold_action()
	var friendly_after_release := combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return not projectile.hostile).size()
	_check(friendly_after_release == friendly_before_release + 1, "releasing captured light creates one bounded return projectile")

	player.active_item_slot.cooldown_remaining = 0.0
	combat.spawn_hostile_volley({"origin": player.global_position + Vector2(130, 0), "direction": Vector2.ZERO, "speed": 0.0, "projectile_count": 1, "reflectable": true})
	var unreflectable_before := combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile and not projectile.reflectable).size()
	_check(player.request_active_item(), "active item fires through the player's single slot")
	_check(not combat.projectiles.any(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile and projectile.reflectable and projectile.global_position.distance_to(player.global_position) <= 330.0), "Paper Burst clears nearby ordinary bullets")
	_check(combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile and not projectile.reflectable).size() == unreflectable_before, "Paper Burst never erases unreflectable bullets")

	for index in FoldlightRogueCombatRuntime.MAX_PROJECTILES + 30:
		combat.spawn_hostile_volley({"origin": Vector2(2700, 100 + index % 1200), "direction": Vector2.LEFT, "speed": 1.0, "projectile_count": 1, "reflectable": true})
	_check(combat.projectiles.size() <= FoldlightRogueCombatRuntime.MAX_PROJECTILES, "projectile density respects its hard performance/readability cap")

	combat.damage_all_enemies(999.0)
	_check(combat.enemies.is_empty(), "combat damage path removes defeated actors through their common interface")
	_check(room.encounter_runtime.state == FoldlightRoomEncounterRuntime.State.CLEARED and room.get_doors().all(func(door: FoldlightRogueDoor) -> bool: return not door.locked), "last real enemy defeat clears the room and opens exits")

	combat.clear_combat()
	var boss_plan := {"encounter_id": &"boss_contract", "errors": [], "entries": [{"boss_id": &"reef_crown_battery", "role": FoldlightRogueEnemyDefinition.EnemyRole.BOSS, "wave": 0, "spawn_slot": &"boss", "spawn_position": Vector2(2200, 810)}]}
	_check(room.begin_encounter(boss_plan).is_empty(), "boss room enters the same lock/telegraph lifecycle")
	room.advance_encounter(room.encounter_runtime.telegraph_duration + 0.01)
	_check(combat.enemies.size() == 1 and combat.enemies[0] is FoldlightRogueBossActor, "boss entry instantiates the reusable staged actor")
	var live_boss := combat.enemies[0] as FoldlightRogueBossActor
	live_boss.health = live_boss.definition.base_health * 0.30
	for _step in 35:
		combat._physics_process(0.2)
	_check(combat.projectiles.any(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile), "boss patterns feed the same capped projectile and Fold interaction runtime")
	combat.damage_all_enemies(99999.0)
	_check(room.encounter_runtime.state == FoldlightRoomEncounterRuntime.State.CLEARED and combat.enemies.is_empty(), "boss defeat clears its room without leaving summoned actors behind")

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
		print("FOLDLIGHT_ROGUE_COMBAT_RUNTIME_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_COMBAT_RUNTIME_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
