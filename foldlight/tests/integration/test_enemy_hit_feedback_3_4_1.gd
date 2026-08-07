extends SceneTree

## 3.4.1 regression contract: every enemy family visibly acknowledges damage,
## while automatic-weapon hit bursts coalesce instead of multiplying nodes.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_classic_enemy_feedback()
	await _test_mechanism_enemy_feedback()
	await _test_boss_feedback()
	_test_batched_hit_vfx()
	_finish()


func _test_classic_enemy_feedback() -> void:
	var actor := FoldlightRogueEnemyFactory.create(FoldlightRogueContentCatalog.enemy_by_id(&"drifter"), &"feedback_drifter") as FoldlightRogueEnemyActor
	_check(actor != null, "2.0 enemy actor can be created for hit-feedback regression")
	if actor == null:
		return
	root.add_child(actor)
	actor.global_position = Vector2(400, 300)
	actor.take_projectile_damage(1.0, Vector2.RIGHT * 420.0, &"crease_petal")
	var hit := actor.get_hit_feedback_snapshot()
	_check(float(hit.get("flash", 0.0)) >= 0.99 and float(hit.get("punch", 0.0)) >= 0.90 and float(hit.get("ring", 0.0)) >= 0.99, "every classic-enemy hit restores flash, punch, and ring feedback")
	_check(Vector2(hit.get("direction", Vector2.ZERO)).dot(Vector2.RIGHT) >= 0.99, "classic-enemy punch follows the incoming projectile direction")
	actor.advance_simulation(0.08, Vector2(900, 300))
	var decayed := actor.get_hit_feedback_snapshot()
	_check(float(decayed.get("flash", 1.0)) < float(hit.get("flash", 0.0)) and float(decayed.get("flash", 0.0)) > 0.0, "classic-enemy feedback decays smoothly instead of spawning tweens")
	actor.queue_free()
	await process_frame


func _test_mechanism_enemy_feedback() -> void:
	var turret := FoldlightRogueEnemyFactory.create(FoldlightRogueContentCatalog.enemy_by_id(&"paper_turret"), &"feedback_turret") as FoldlightPaperTurret
	_check(turret != null, "mechanism enemy can be created for hit-feedback regression")
	if turret == null:
		return
	root.add_child(turret)
	turret.take_damage(1.0)
	var hit := turret.get_hit_feedback_snapshot()
	_check(float(hit.get("flash", 0.0)) >= 0.99 and float(hit.get("punch", 0.0)) >= 0.85, "new mechanism enemies retain body flash and elastic hit response")
	turret.advance_simulation(0.08, Vector2(900, 0))
	var decayed := turret.get_hit_feedback_snapshot()
	_check(float(decayed.get("flash", 1.0)) < float(hit.get("flash", 0.0)), "mechanism-enemy feedback is state-decayed and bounded")
	turret.queue_free()
	await process_frame


func _test_boss_feedback() -> void:
	var packed := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn") as PackedScene
	var boss := packed.instantiate() as FoldlightRogueBossActor if packed != null else null
	_check(boss != null, "boss actor loads for hit-feedback regression")
	if boss == null:
		return
	root.add_child(boss)
	await process_frame
	boss.configure(FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery"), Rect2(Vector2.ZERO, Vector2(1920, 1080)), 34101)
	boss.take_damage(1.0)
	var hit := boss.get_hit_feedback_snapshot()
	_check(float(hit.get("flash", 0.0)) >= 0.99 and float(hit.get("punch", 0.0)) >= 0.85 and float(hit.get("ring", 0.0)) >= 0.99, "boss damage restores body flash, punch, and hit ring")
	boss.advance_simulation(0.08, Vector2(300, 300))
	var decayed := boss.get_hit_feedback_snapshot()
	_check(float(decayed.get("flash", 1.0)) < float(hit.get("flash", 0.0)), "boss hit feedback decays without persistent visual state")
	boss.queue_free()
	await process_frame


func _test_batched_hit_vfx() -> void:
	var runtime := FoldlightRogueCombatRuntime.new()
	root.add_child(runtime)
	var child_count_before := runtime.get_child_count()
	for _hit_index in 40:
		runtime._register_enemy_hit_feedback(&"automatic_weapon_target", Vector2(600, 400), Vector2.RIGHT * 500.0, 1.0)
	var coalesced := runtime.get_enemy_hit_vfx_snapshot()
	_check(int(coalesced.get("active_bursts", 0)) == 1 and int(coalesced.get("total_hits", 0)) == 40, "forty same-target hits coalesce into one live draw burst")
	_check(float(coalesced.get("tokens", 0.0)) >= 4.99, "coalesced hits consume only one global visual token")
	_check(runtime.get_child_count() == child_count_before, "hit feedback creates no particles, tweens, or child nodes")
	for unique_index in 40:
		runtime._register_enemy_hit_feedback(StringName("unique_%02d" % unique_index), Vector2(100 + unique_index * 8, 300), Vector2.UP, 1.0)
	var saturated := runtime.get_enemy_hit_vfx_snapshot()
	_check(int(saturated.get("active_bursts", 0)) <= int(saturated.get("maximum_bursts", 0)), "simultaneous unique hit bursts obey the hard global ceiling")
	_check(float(saturated.get("tokens", -1.0)) >= 0.0, "visual token budget never becomes negative under saturation")
	var tokens_before_decay := float(saturated.get("tokens", 0.0))
	runtime._update_enemy_hit_vfx(0.25)
	var expired := runtime.get_enemy_hit_vfx_snapshot()
	_check(int(expired.get("active_bursts", -1)) == 0, "batched impact drawings expire after their short readability window")
	_check(float(expired.get("tokens", 0.0)) > tokens_before_decay, "visual budget refills independently after a burst")
	runtime.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ENEMY_HIT_FEEDBACK_3_4_1: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENEMY_HIT_FEEDBACK_3_4_1: FAIL - %s" % ", ".join(_failures))
		quit(1)
