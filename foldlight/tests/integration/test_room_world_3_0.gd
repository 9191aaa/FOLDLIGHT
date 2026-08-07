extends SceneTree

## 3.0 room contract: a larger camera-bounded world with honest primitive terrain physics.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var room_packed := load("res://scenes/roguelite/room_runtime.tscn") as PackedScene
	var room := room_packed.instantiate() as FoldlightRoomRuntime if room_packed != null else null
	_check(room != null, "large-room runtime scene loads")
	if room == null:
		_finish()
		return
	root.add_child(room)
	var placements: Array[Dictionary] = [
		{"id": &"west_reef", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(720, 810), "size": Vector2(420, 100), "rotation": 0.0},
		{"id": &"split_prism", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(1500, 620), "size": Vector2(150, 150), "rotation": 0.0},
		{"id": &"slow_ink", "kind": FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, "position": Vector2(2080, 1040), "size": Vector2(360, 220), "rotation": 0.0},
		{"id": &"east_current", "kind": FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, "position": Vector2(2240, 520), "size": Vector2(460, 150), "rotation": -0.18, "direction": Vector2.RIGHT, "strength": 1.25},
	]
	var errors := room.configure_room(&"test_large_room", Vector2(2880, 1620), placements, Color(0.28, 0.84, 0.83))
	_check(errors.is_empty(), "authored four-terrain room passes layout validation")
	_check(room.room_bounds.size == Vector2(2880, 1620) and room.room_bounds.size.x > 1920.0 and room.room_bounds.size.y > 1080.0, "room is materially larger than the design viewport")
	_check(room.get_terrain_pieces().size() == 4, "room instantiates each authored terrain placement")
	var body_count := 0
	var area_count := 0
	var primitive_shapes := true
	for piece in room.get_terrain_pieces():
		var collision_object := (piece as FoldlightTerrainPiece).get_collision_object()
		if collision_object is StaticBody2D:
			body_count += 1
		elif collision_object is Area2D:
			area_count += 1
		var shape_node := (piece as FoldlightTerrainPiece).get_collision_shape()
		primitive_shapes = primitive_shapes and shape_node.scale.is_equal_approx(Vector2.ONE) and (shape_node.shape is RectangleShape2D or shape_node.shape is CircleShape2D)
	_check(body_count == 2 and area_count == 2, "walls and pillars block while ink and current remain readable trigger areas")
	_check(primitive_shapes, "terrain uses unscaled primitive collision shapes")

	var player_packed := load("res://scenes/player.tscn") as PackedScene
	var player := player_packed.instantiate() as FoldlightPlayer
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	room.bind_player(player)
	_check(player.play_bounds.position == Vector2(56, 56) and player.play_bounds.end == Vector2(2824, 1564), "room supplies player bounds with a safe wall margin")
	player.position = Vector2(430, 810)
	var wall_collision := player.move_and_collide(Vector2(420, 0))
	_check(wall_collision != null, "roguelite player physically collides with paper reef walls")

	var camera := FoldlightRogueCamera.new()
	root.add_child(camera)
	camera.configure(player, room.room_bounds)
	player.position = Vector2(2800, 1540)
	camera.force_follow(1.0)
	_check(camera.position.x <= 1920.01 and camera.position.y <= 1080.01, "camera clamps to the large room without showing outside the world")
	player.position = Vector2(1440, 810)
	camera.force_follow(1.0)
	_check(camera.position.distance_to(Vector2(1440, 810)) < 2.0, "camera follows the player through the room interior")

	var bad_placements := placements.duplicate(true)
	bad_placements.append({"id": &"outside", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(-20, 30), "size": Vector2(300, 100)})
	_check(not room.validate_layout(Vector2(2880, 1620), bad_placements).is_empty(), "layout validator rejects terrain extending outside room bounds")

	room.queue_free()
	player.queue_free()
	camera.queue_free()
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
		print("FOLDLIGHT_ROOM_WORLD_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROOM_WORLD_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
