extends SceneTree

## Formal 3.6 pass: the game keeps the 2.0 visual language, restores modal
## mechanic teaching, and gives the first/final bosses authored readable VFX.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_mechanic_archive_contract()
	_test_tide_gap_contract()
	_test_judge_vfx_contract()
	_test_terrain_variety_contract()
	_test_enemy_hit_weight_contract()
	await _test_mechanic_modal_contract()
	_finish()


func _test_mechanic_archive_contract() -> void:
	var tracker := FoldlightMechanicIntroductionTracker.new()
	var turret := FoldlightRogueContentCatalog.enemy_by_id(&"paper_turret")
	var card := tracker.request_introduction(turret)
	_check(not String(card.get("description", "")).is_empty(), "new-enemy archive includes a readable identity description")
	_check(not String(card.get("role_title", "")).is_empty(), "new-enemy archive names the mechanic role")
	_check(float(card.get("duration", -1.0)) == 0.0, "new-enemy briefing waits for explicit confirmation instead of expiring")
	_check(tracker.request_introduction(turret).is_empty(), "one run never interrupts twice for the same enemy")
	tracker.free()


func _test_tide_gap_contract() -> void:
	var arena := FoldlightBossArenaController.new()
	arena.configure(&"reef_tide_pulse", Rect2(Vector2.ZERO, Vector2(2880, 1620)))
	arena.tide_state = FoldlightBossArenaController.TideState.SURGE
	arena.pulse_radius = 620.0
	arena.tide_gap_angle = -PI * 0.32
	var center := arena.room_bounds.get_center()
	var gap_point := center + Vector2.from_angle(arena.tide_gap_angle) * arena.pulse_radius
	var dangerous_point := center + Vector2.from_angle(arena.tide_gap_angle + PI) * arena.pulse_radius
	_check(arena.is_player_safe(gap_point), "chapter-one tide ring leaves a real angular dodge gap")
	_check(not arena.is_player_safe(dangerous_point), "the remaining tide ring still applies pressure at the same radius")
	var snapshot := arena.get_rule_snapshot()
	_check(float(snapshot.get("safe_gap_half_angle", 0.0)) >= 0.30, "the safe gap remains readable in every phase")
	arena.free()


func _test_judge_vfx_contract() -> void:
	var motifs: Dictionary = {}
	for pattern_id in [&"judgement_petals", &"unreflectable_cut", &"shrinking_frame"]:
		var telegraph := FoldlightBossAttackTelegraph.new()
		telegraph.configure({"pattern_id": pattern_id, "origin": Vector2.ZERO, "target_position": Vector2.DOWN * 800.0, "duration": 0.8})
		var contract := telegraph.get_visual_contract()
		_check(bool(contract.get("authored", false)), "chapter-three pattern %s has authored VFX" % pattern_id)
		motifs[String(contract.get("motif", ""))] = true
		telegraph.free()
	_check(motifs.size() == 3, "the three chapter-three skills no longer share one generic effect")


func _test_terrain_variety_contract() -> void:
	var session := FoldlightRogueSessionController.new()
	var signatures: Dictionary = {}
	for depth in 3:
		var layout: Array[Dictionary] = session._terrain_layout(&"paper_reef", &"combat", depth)
		var points: Array[String] = []
		var has_boon := false
		var has_hazard := false
		for placement in layout:
			points.append(str(Vector2(placement.get("position", Vector2.ZERO)).round()))
			var kind := int(placement.get("kind", -1))
			has_boon = has_boon or kind == FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH
			has_hazard = has_hazard or kind in [FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER]
			if kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
				_check(Vector2(placement.get("position", Vector2.ZERO)).distance_to(FoldlightRogueSessionController.PLAYER_START) >= 230.0, "solid terrain keeps the room entrance clear")
		signatures["|".join(points)] = true
		_check(has_boon and has_hazard, "each reef layout mixes positive and negative terrain")
	_check(signatures.size() == 3, "ordinary rooms rotate through three materially different terrain layouts")
	var backdrop := FoldlightRoomBackdrop.new()
	backdrop.configure(&"r1_contract", Vector2(2880, 1620), Color(0.3, 0.8, 0.8), &"paper_reef")
	_check(not (backdrop.get_visual_contract().get("motifs", []) as Array).has(&"pixel_tide_strata"), "formal backdrop has returned to the refined 2.0 paper language")
	backdrop.free()
	session.free()


func _test_enemy_hit_weight_contract() -> void:
	var enemy := FoldlightRogueEnemyActor.new()
	var definition := FoldlightRogueContentCatalog.enemy_by_id(&"drifter")
	enemy.configure(definition, &"feedback_contract")
	enemy.take_projectile_damage(1.0, Vector2.RIGHT * 600.0, &"return_light")
	var feedback := enemy.get_hit_feedback_snapshot()
	_check(float(feedback.get("flash", 0.0)) >= 0.99, "enemy hit begins with a full white flash")
	_check(float(feedback.get("punch", 0.0)) >= 0.99, "enemy hit begins with a full local punch pose")
	_check(float(feedback.get("ring", 0.0)) >= 0.99, "enemy hit emits the restored impact ring")
	enemy.free()


func _test_mechanic_modal_contract() -> void:
	var scene := load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene
	var presentation := scene.instantiate() as FoldlightRoguePresentation if scene != null else null
	_check(presentation != null, "roguelite presentation scene loads")
	if presentation == null:
		return
	root.add_child(presentation)
	await process_frame
	presentation.show_mechanic_card({
		"content_id": &"paper_turret", "title": "折纸炮台", "description": "固定阵地单位",
		"role_title": "阵地单位", "rule": "锁定直线后齐射", "counterplay": "横向离开火线", "accent": Color(1.0, 0.5, 0.2),
	})
	var snapshot := presentation.get_mechanic_briefing_snapshot()
	_check(StringName(snapshot.get("screen_kind", &"")) == &"mechanic_intro", "first encounter replaces the HUD with a safe modal briefing")
	_check(bool(snapshot.get("requires_confirmation", false)), "briefing cannot disappear before the player confirms")
	_check("它会做什么" in String(snapshot.get("rule", "")) and "你该怎么应对" in String(snapshot.get("counterplay", "")), "briefing separates rule from response")
	presentation.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_FORMAL_ART_FEEDBACK_3_6: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_FORMAL_ART_FEEDBACK_3_6: FAIL — %s" % ", ".join(_failures))
		quit(1)
