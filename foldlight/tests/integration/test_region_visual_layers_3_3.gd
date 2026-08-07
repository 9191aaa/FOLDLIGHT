extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var room := (load("res://scenes/roguelite/room_runtime.tscn") as PackedScene).instantiate() as FoldlightRoomRuntime
	root.add_child(room)
	await process_frame
	_check((room.get_node("Backdrop") as Node2D).z_index == -30, "backdrop occupies the dedicated rear layer")
	_check((room.get_node("Terrain") as Node2D).z_index == -10, "terrain stays behind every combat warning")
	_check((room.get_node("Projectiles") as Node2D).z_index == 3, "projectiles have an explicit readable layer")

	var motifs: Dictionary = {}
	for style in [&"paper_reef", &"ink_city", &"sun_court"]:
		var backdrop := FoldlightRoomBackdrop.new()
		backdrop.configure(StringName("fixture_%s" % style), Vector2(2200, 1300), Color(0.4, 0.8, 0.8), style)
		var contract := backdrop.get_visual_contract()
		motifs[style] = contract.get("motifs", [])
		_check((contract.get("motifs", []) as Array).size() >= 3, "%s has a complete regional motif set" % style)
		backdrop.free()
	_check((motifs[&"paper_reef"] as Array).has(&"layered_tide_wash") and (motifs[&"paper_reef"] as Array).has(&"folded_reef_silhouette") and (motifs[&"paper_reef"] as Array).has(&"paper_moon"), "paper_reef formal scene uses the approved refined paper-sea language")
	_check(motifs[&"paper_reef"] != motifs[&"ink_city"] and motifs[&"ink_city"] != motifs[&"sun_court"], "all three region backdrops use distinct compositions")

	var terrain_motifs: Dictionary = {}
	for style in [&"paper_reef", &"ink_city", &"sun_court"]:
		var piece := FoldlightTerrainPiece.new()
		piece.configure({"id": StringName("wall_%s" % style), "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2.ZERO, "size": Vector2(320, 80), "visual_style": style})
		terrain_motifs[style] = piece.get_visual_signature().get("motif", &"")
		_check((piece.get_collision_shape().shape as RectangleShape2D).size == Vector2(320, 80), "%s art preserves terrain collision" % style)
		piece.free()
	var unique_terrain_motifs: Array = []
	for value in terrain_motifs.values():
		if not unique_terrain_motifs.has(value):
			unique_terrain_motifs.append(value)
	_check(unique_terrain_motifs.size() == 3, "terrain has three genuinely different visual languages")

	var telegraph := (load("res://scenes/roguelite/bosses/boss_attack_telegraph.tscn") as PackedScene).instantiate() as FoldlightBossAttackTelegraph
	root.add_child(telegraph)
	telegraph.configure({"origin": Vector2(500, 500), "target_position": Vector2(1500, 500), "pattern_id": &"black_lane", "duration": 1.0})
	_check(not telegraph.z_as_relative and telegraph.z_index > (room.get_node("Terrain") as Node2D).z_index, "region-one boss attack warning cannot be hidden by terrain")
	var arena := FoldlightBossArenaController.new()
	root.add_child(arena)
	await process_frame
	arena.configure(&"reef_tide_pulse", Rect2(Vector2.ZERO, Vector2(2200, 1300)))
	_check(not arena.z_as_relative and arena.z_index > (room.get_node("Terrain") as Node2D).z_index, "region-one tide surge cannot be hidden by terrain")

	telegraph.queue_free()
	arena.queue_free()
	room.queue_free()
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
		print("FOLDLIGHT_REGION_VISUAL_LAYERS_3_3: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REGION_VISUAL_LAYERS_3_3: FAIL - %s" % ", ".join(_failures))
		quit(1)
