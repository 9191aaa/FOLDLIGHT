extends SceneTree

## Every enemy family acknowledges damage. Ordinary fire stays compact while
## returns and earned boss breaks receive stronger, bounded paper reactions.

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
	var original_position: Vector2 = actor.global_position
	var original_radius: float = actor.get_contact_radius()
	var original_rng_state: int = actor._rng.state
	actor.take_projectile_damage(1.0, Vector2.RIGHT * 420.0, &"crease_petal")
	var hit := actor.get_hit_feedback_snapshot()
	_check(float(hit.get("flash", 0.0)) > 0.0 and float(hit.get("flash", 1.0)) < 0.60 and float(hit.get("punch", 1.0)) < 0.50 and is_zero_approx(float(hit.get("ring", 1.0))), "ordinary fire uses a short light tap without an expanding ring")
	_check(Vector2(hit.get("direction", Vector2.ZERO)).dot(Vector2.RIGHT) >= 0.99, "classic-enemy punch follows the incoming projectile direction")
	for _index in 40:
		actor.take_projectile_damage(0.01, Vector2.RIGHT * 420.0, &"crease_petal")
	_check(int(actor.get_hit_feedback_snapshot().get("pulse_count", 0)) == 1 and is_equal_approx(actor.health, 0.60), "a burst applies all damage but does not restart the body flash forty times")
	_check(actor.global_position.is_equal_approx(original_position) and is_equal_approx(actor.get_contact_radius(), original_radius) and actor._rng.state == original_rng_state, "visual impact leaves physics geometry and gameplay randomness unchanged")
	actor.advance_simulation(0.035, Vector2(900, 300))
	var decayed := actor.get_hit_feedback_snapshot()
	_check(float(decayed.get("flash", 1.0)) < float(hit.get("flash", 0.0)) and float(decayed.get("flash", 0.0)) > 0.0, "classic-enemy feedback decays smoothly instead of spawning tweens")
	actor.take_projectile_damage(0.10, Vector2.UP * 700.0, &"return_light")
	var returned := actor.get_hit_feedback_snapshot()
	_check(int(returned.get("tier", 0)) == 2 and float(returned.get("flash", 0.0)) > float(hit.get("flash", 1.0)) and float(returned.get("punch", 0.0)) > float(hit.get("punch", 1.0)), "return light immediately upgrades an active light tap to a stronger paper reaction")
	actor.take_projectile_damage(0.01, Vector2.LEFT * 420.0, &"crease_petal")
	_check(int(actor.get_hit_feedback_snapshot().get("pulse_count", 0)) == 2 and Vector2(actor.get_hit_feedback_snapshot().get("direction", Vector2.ZERO)).is_equal_approx(Vector2.UP), "a following ordinary pellet cannot erase or redirect the return-light reaction")
	actor.advance_simulation(0.32, Vector2(900, 300))
	_check(is_zero_approx(float(actor.get_hit_feedback_snapshot().get("remaining", 1.0))), "return paper shards and body deformation settle completely")
	actor.take_projectile_damage(10.0, Vector2.DOWN, &"crease_petal")
	_check(int(actor.get_hit_feedback_snapshot().get("tier", 0)) == 3 and actor.health == 0.0, "a lethal hit publishes a directional break reaction before defeat cleanup")
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
	var original_position: Vector2 = boss.global_position
	var original_rng_state: int = boss._rng.state
	boss.take_damage(1.0, &"weapon", Vector2.RIGHT)
	var hit := boss.get_hit_feedback_snapshot()
	_check(float(hit.get("flash", 0.0)) > 0.0 and float(hit.get("flash", 1.0)) < 0.60 and is_zero_approx(float(hit.get("ring", 1.0))), "boss ordinary damage acknowledges the hit without a large flashing ring")
	_check(boss.global_position.is_equal_approx(original_position) and boss._rng.state == original_rng_state, "boss impact remains a visual offset and does not consume attack randomness")
	boss.advance_simulation(0.08, Vector2(300, 300))
	var decayed := boss.get_hit_feedback_snapshot()
	_check(float(decayed.get("flash", 1.0)) < float(hit.get("flash", 0.0)), "boss hit feedback decays without persistent visual state")
	var health_before_return: float = boss.health
	boss.take_damage(22.4, &"return", Vector2.UP)
	var broken := boss.get_hit_feedback_snapshot()
	_check(int(broken.get("tier", 0)) == 3 and boss.phase_controller.state == FoldlightBossPhaseController.State.STAGGERED, "earning the return window produces the strongest break pose")
	_check(is_equal_approx(health_before_return - boss.health, 22.4 * boss.definition.return_damage_outside_stagger), "feedback tiers preserve the boss return-damage multiplier")
	_check(Vector2(broken.get("direction", Vector2.ZERO)).is_equal_approx(Vector2.UP), "boss break pose uses the incoming projectile direction")
	boss.take_damage(1.0, &"weapon", Vector2.LEFT)
	_check(boss.get_hit_feedback_snapshot().get("pulse_count") == broken.get("pulse_count"), "automatic fire cannot replace an earned boss break animation")
	boss.take_damage(99999.0, &"weapon", Vector2.LEFT)
	var defeated_pose := boss.get_hit_feedback_snapshot()
	_check(boss.health == 0.0 and int(defeated_pose.get("pulse_count", 0)) == int(broken.get("pulse_count", 0)) + 1 and Vector2(defeated_pose.get("direction", Vector2.ZERO)).is_equal_approx(Vector2.LEFT), "a lethal hit during stagger still publishes its own final break direction")
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
