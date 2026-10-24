extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	var placements: Array[Dictionary] = [{"id": &"retained_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1600,810), "size": Vector2(240,90)}]
	world.load_room(player, &"old_room", Vector2(2880,1620), placements, Color.WHITE, 92001)
	world.activate()
	var combat := world.combat_runtime
	combat.set_physics_process(false)
	player.global_position = Vector2(500,810)
	var sentinel := Node2D.new()
	sentinel.name = "UnrelatedRoomChild"
	combat.room.projectile_container.add_child(sentinel)
	var effects := _spawn_effects(combat, player.global_position)
	world.deactivate()
	world.load_room(player, &"next_room", Vector2(2880,1620), placements, Color.WHITE, 92002)
	world.activate()
	combat.set_physics_process(false)
	_check(_all_queued_and_hidden(effects), "room replacement immediately hides and queues only the old transient combat effects")
	combat._update_denial_zones()
	_check(not player.has_status(&"bound_crease"), "a queued old binding zone cannot slow the player during the same room-switch frame")
	await process_frame
	_check(_all_freed(effects), "room replacement frees the old projectile, binding zone and both warnings")
	_check(is_instance_valid(player) and player.is_inside_tree() and is_instance_valid(sentinel) and not sentinel.is_queued_for_deletion(), "combat cleanup preserves the player and unrelated room children")
	_check(world.room_runtime.get_terrain_pieces().size() == 1, "the replacement room retains its authored terrain")
	var direct_effects := _spawn_effects(combat, player.global_position)
	combat.clear_combat()
	combat.clear_combat()
	_check(_all_queued_and_hidden(direct_effects), "direct repeated combat cleanup is safe before deferred frees run")
	await process_frame
	_check(_all_freed(direct_effects), "direct cleanup leaves no active transient nodes")
	world.queue_free()
	player.queue_free()
	await process_frame
	var endless := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(endless)
	await process_frame
	endless.set_physics_process(false)
	endless.player.set_physics_process(false)
	endless.combat_runtime.set_physics_process(false)
	var restart_effects := _spawn_effects(endless.combat_runtime, endless.player.global_position)
	endless.start_slice(92003)
	endless.combat_runtime.set_physics_process(false)
	_check(_all_queued_and_hidden(restart_effects), "a real endless restart discards hazards and warnings from its previous attempt")
	endless.combat_runtime._update_denial_zones()
	_check(not endless.player.has_status(&"bound_crease") and endless.controller.active, "the restarted attempt stays playable without the old slow effect")
	await process_frame
	_check(_all_freed(restart_effects), "endless restart releases all previous transient node instances")
	endless.queue_free()
	await process_frame
	print("FOLDLIGHT_COMBAT_TRANSIENT_CLEANUP: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _spawn_effects(combat: FoldlightRogueCombatRuntime, origin: Vector2) -> Array[Node]:
	combat._on_zone_requested({"position": origin, "radius": 165.0, "duration": 5.0})
	var zone: Node = combat.room.projectile_container.get_children().back()
	combat._on_spawn_telegraph({"spawn_position": origin + Vector2(250,0)}, 5.0)
	var spawn_warning: Node = combat.room.get_children().back()
	combat._on_boss_telegraph_requested({"origin": origin + Vector2(-250,0), "target_position": origin, "duration": 5.0, "pattern_id": &"ink_partition", "zone_radius": 165.0})
	var boss_warning: Node = combat.room.projectile_container.get_children().back()
	var projectile := combat._spawn_projectile({"origin": origin + Vector2(700,0), "velocity": Vector2.ZERO, "hostile": true, "lifetime": 8.0})
	return [zone, spawn_warning, boss_warning, projectile]

func _all_queued_and_hidden(nodes: Array[Node]) -> bool:
	for node in nodes:
		if not is_instance_valid(node) or not node.is_queued_for_deletion() or (node as Node2D).visible:
			return false
	return true

func _all_freed(nodes: Array[Node]) -> bool:
	for node in nodes:
		if is_instance_valid(node):
			return false
	return true

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
