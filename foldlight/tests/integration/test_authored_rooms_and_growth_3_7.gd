extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authored_room_library()
	_test_empty_active_item_start()
	_test_boss_readability_contracts()
	_finish()


func _test_authored_room_library() -> void:
	_check(FoldlightRogueRoomTemplateCatalog.template_count() >= 36, "room library contains dozens of complete authored templates")
	var all_ids: Dictionary = {}
	for region_id in FoldlightRogueRoomTemplateCatalog.REGION_IDS:
		var templates := FoldlightRogueRoomTemplateCatalog.templates_for_region(region_id)
		_check(templates.size() >= 12, "%s has at least twelve backup rooms" % region_id)
		for template in templates:
			var template_id := String(template.get("id", ""))
			all_ids[template_id] = true
			var terrain: Array = template.get("terrain", [])
			var slots: Array = template.get("spawn_slots", [])
			_check(terrain.size() >= 6, "%s is a full terrain composition" % template_id)
			_check(slots.size() >= 30, "%s provides enough authored wave slots" % template_id)
			var has_boon := false
			var has_hazard := false
			var has_cover := false
			var entrance_clear := true
			for placement_variant: Variant in terrain:
				var placement := placement_variant as Dictionary
				var kind := int(placement.get("kind", -1))
				has_boon = has_boon or kind == FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH
				has_hazard = has_hazard or kind in [FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER]
				has_cover = has_cover or kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]
				if kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
					entrance_clear = entrance_clear and Vector2(placement.get("position", Vector2.ZERO)).distance_to(FoldlightRogueSessionController.PLAYER_START) >= 230.0
			var overlap_free := true
			for first_index in terrain.size():
				for second_index in range(first_index + 1, terrain.size()):
					var first_bounds := _placement_bounds(terrain[first_index] as Dictionary).grow(-12.0)
					var second_bounds := _placement_bounds(terrain[second_index] as Dictionary).grow(-12.0)
					overlap_free = overlap_free and not first_bounds.intersects(second_bounds)
			_check(entrance_clear, "%s keeps solid cover away from the entrance" % template_id)
			_check(overlap_free, "%s keeps authored terrain pieces from overlapping" % template_id)
			_check(has_boon and has_hazard and has_cover, "%s mixes cover, positive terrain and negative terrain" % template_id)
	_check(all_ids.size() == FoldlightRogueRoomTemplateCatalog.template_count(), "all authored room IDs are unique")
	var first := FoldlightRogueRoomTemplateCatalog.select_template(&"paper_reef", 99173, &"r1_a", &"combat", 2)
	var repeat := FoldlightRogueRoomTemplateCatalog.select_template(&"paper_reef", 99173, &"r1_a", &"combat", 2)
	_check(first == repeat, "seeded room selection is deterministic without transforming props")


func _test_empty_active_item_start() -> void:
	var run_state := FoldlightRogueRunState.new()
	run_state.begin_run(8831, {"regions": [{"start_id": "r1_start"}]})
	_check(run_state.active_item_id.is_empty(), "a new run starts with an empty active-item slot")
	_check(run_state.weapon_ids == [&"crease_lantern"], "the familiar automatic weapon remains equipped")
	run_state.free()


func _test_boss_readability_contracts() -> void:
	var reef := FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery")
	var archivist := FoldlightRogueContentCatalog.boss_by_id(&"inverted_archivist")
	_check(reef != null and reef.base_health <= 500.0, "first boss health no longer drags")
	_check(archivist != null and archivist.base_health <= 900.0, "second boss health no longer drags")
	var arena := FoldlightBossArenaController.new()
	arena.configure(&"reef_tide_pulse", Rect2(Vector2.ZERO, Vector2(2880, 1620)))
	arena.tide_state = FoldlightBossArenaController.TideState.TELEGRAPH
	var snapshot := arena.get_rule_snapshot()
	_check(bool(snapshot.get("safe_gap_visible", false)), "first boss telegraph explicitly exposes the dodge gap")
	_check(float(snapshot.get("safe_gap_half_angle", 0.0)) >= 0.48, "first boss leaves a generous real dodge space")
	arena.free()
	var tracker := FoldlightMechanicIntroductionTracker.new()
	var boss_card := tracker.request_boss_introduction(reef)
	_check(StringName(boss_card.get("preview_kind", &"")) == &"boss", "bosses use the same dynamic introduction system as new enemies")
	_check(not String(boss_card.get("counterplay", "")).is_empty(), "boss introduction teaches immediate counterplay")
	tracker.free()


func _placement_bounds(placement: Dictionary) -> Rect2:
	var size := Vector2(placement.get("size", Vector2.ZERO)).abs()
	var angle := float(placement.get("rotation", 0.0))
	var c := absf(cos(angle))
	var s := absf(sin(angle))
	var rotated_size := Vector2(size.x * c + size.y * s, size.x * s + size.y * c)
	return Rect2(Vector2(placement.get("position", Vector2.ZERO)) - rotated_size * 0.5, rotated_size)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_AUTHORED_ROOMS_GROWTH_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_AUTHORED_ROOMS_GROWTH_3_7: FAIL - %s" % ", ".join(_failures))
		quit(1)
