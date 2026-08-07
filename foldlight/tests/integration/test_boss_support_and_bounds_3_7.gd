extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn") as PackedScene
	_check(packed != null, "boss actor scene loads")
	if packed == null:
		_finish()
		return
	var bounds := Rect2(Vector2.ZERO, Vector2(2880, 1620))

	var judge := packed.instantiate() as FoldlightRogueBossActor
	root.add_child(judge)
	await process_frame
	judge.configure(FoldlightRogueContentCatalog.boss_by_id(&"origami_judge"), bounds, 77)
	judge.arena_controller.safe_rect = Rect2(Vector2(940, 480), Vector2(1000, 620))
	judge.global_position = Vector2(2600, 220)
	judge._clamp_to_active_arena()
	var legal_frame := judge.arena_controller.safe_rect.grow(-86.0)
	_check(legal_frame.has_point(judge.global_position), "final boss is clamped inside its own restricted arena")
	judge.queue_free()
	await process_frame

	var archivist := packed.instantiate() as FoldlightRogueBossActor
	root.add_child(archivist)
	await process_frame
	archivist.configure(FoldlightRogueContentCatalog.boss_by_id(&"inverted_archivist"), bounds, 91)
	var support_snapshots: Array[Dictionary] = []
	archivist.minion_requested.connect(func(snapshot: Dictionary) -> void: support_snapshots.append(snapshot.duplicate(true)))
	archivist.request_opening_support()
	var support: Dictionary = support_snapshots[0] if not support_snapshots.is_empty() else {}
	var enemy_ids: Array = support.get("enemy_ids", [])
	var positions: Array = support.get("positions", [])
	_check(enemy_ids.size() >= 2, "second boss opens with a mixed support squad")
	_check(positions.size() >= 4, "second boss support squad has several central spawn points")
	var all_central := true
	for position_variant: Variant in positions:
		var point := Vector2(position_variant)
		all_central = all_central and point.x >= 800.0 and point.x <= 2080.0 and point.y >= 450.0 and point.y <= 1170.0
	_check(all_central, "second boss support sources stay visible in the middle of the room")
	archivist.queue_free()
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
		print("FOLDLIGHT_BOSS_SUPPORT_BOUNDS_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_BOSS_SUPPORT_BOUNDS_3_7: FAIL - %s" % ", ".join(_failures))
		quit(1)
