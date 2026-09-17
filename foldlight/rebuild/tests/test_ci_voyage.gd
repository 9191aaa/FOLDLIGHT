extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + label)
	else:
		failures.append(label)
		push_error("VOYAGE FAIL: " + label)

func defeat_wave(lab: FoldlightBossLab) -> void:
	for enemy: Node2D in lab.world.combat_runtime.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.call("take_damage", 10000.0)

func clear_room(lab: FoldlightBossLab) -> void:
	lab._physics_process(1.0)
	check(not lab.world.combat_runtime.enemies.is_empty(), "authored wave spawns")
	defeat_wave(lab)
	lab._physics_process(0.80)
	check(lab.wave_index == 1, "room has a second wave")
	lab._physics_process(1.0)
	check(not lab.world.combat_runtime.enemies.is_empty(), "second wave spawns")
	defeat_wave(lab)
	lab._physics_process(0.80)

func run_tests() -> void:
	var scene: PackedScene = load("res://rebuild/scenes/boss_lab.tscn")
	var lab := scene.instantiate() as FoldlightBossLab
	root.add_child(lab)
	await process_frame
	lab._no_persist = true
	check(lab.ui is CanvasLayer, "HUD has an independent CanvasLayer")
	check(lab.feedback.strength == 0.55, "default screen shake is subtle")
	lab.start_boss(&"normal")
	await process_frame
	var player: FoldlightBalancedPlayer = lab.player
	var combat := lab.world.combat_runtime as FoldlightBalancedCombat
	var point: Vector2 = player.global_position
	lab.feedback.kick(8.0, 0.2)
	lab.feedback._process(0.02)
	check(lab.feedback.camera_offset.length() > 0.0, "feedback moves rendered canvas")
	check(player.global_position == point, "screen shake never moves collision bodies")
	check(lab.ui.transform == Transform2D.IDENTITY, "HUD remains stationary during shake")
	lab.feedback._process(0.30)
	check(root.canvas_transform == Transform2D.IDENTITY, "shake settles exactly to zero")
	lab.feedback.set_strength(0.0)
	lab.feedback.kick(1000.0, 1.0)
	lab.feedback._process(0.01)
	check(root.canvas_transform == Transform2D.IDENTITY, "disabled shake stays disabled")
	lab.feedback.set_strength(1.0)
	for i in 100:
		lab.feedback.kick(100.0)
		lab.feedback.broken(Vector2(900, 300), true)
	check(lab.feedback.amplitude <= FoldlightDemoFeedback.MAX_SHAKE, "simultaneous hits cannot amplify shake beyond its cap")
	check(lab.feedback.particles.size() <= FoldlightDemoFeedback.MAX_PARTICLES, "particle budget bounded")
	check(lab.feedback.rings.size() <= FoldlightDemoFeedback.MAX_RINGS, "ring budget bounded")
	lab.pause_fight()
	var clock: float = lab.elapsed
	var cooldown: float = player.dash_component.cooldown_remaining
	lab.feedback.kick(8.0)
	for i in 4:
		await process_frame
	check(root.canvas_transform == Transform2D.IDENTITY, "pause resets view offset and rejects new shake")
	check(lab.elapsed == clock and player.dash_component.cooldown_remaining == cooldown, "pause freezes gameplay timers")
	lab.resume_fight()
	lab.feedback.reset()
	check(player.try_begin_fold(), "Fold starts in actual projectile test")
	combat.spawn_hostile_volley({"origin": player.global_position + Vector2(70, 0), "projectile_count": 1, "speed": 10.0, "reflectable": true})
	combat._update_projectiles(0.0)
	check(player.captured == 1, "real purple projectile is captured")
	check(not lab.feedback.particles.is_empty(), "capture signal creates feedback")
	combat.spawn_hostile_volley({"origin": player.global_position + Vector2(-70, 0), "projectile_count": 1, "speed": 10.0, "reflectable": false})
	combat._update_projectiles(0.0)
	check(player.captured == 1, "black projectile cannot be captured")
	player.release_fold_action()
	check(lab.feedback.amplitude > 0.0, "real release requests a camera impulse")
	lab.start_voyage(&"normal")
	await process_frame
	check(lab.is_voyage and lab.stage_index == 0, "voyage begins at the first room")
	check(lab.upgrades.is_empty(), "new voyage has no inherited upgrades")
	clear_room(lab)
	check(lab.mode == FoldlightBossLab.Mode.REWARD and paused, "room one leads to a frozen reward selection")
	var before_reward_health: int = player.health
	lab.choose_reward(-1)
	check(lab.mode == FoldlightBossLab.Mode.REWARD, "invalid reward selection ignored")
	lab.ui.card_buttons[0].pressed.emit()
	check(lab.stage_index == 1 and not paused, "reward button starts the next room")
	check(lab.upgrades == [&"bright_return"], "first reward applied once")
	check(is_equal_approx(float(player.rogue_build_stats["return_damage_multiplier"]), 1.20), "reward affects actual return damage stats")
	lab.choose_reward(0)
	check(lab.upgrades.size() == 1, "duplicate reward activation ignored")
	check(player.health == before_reward_health, "non-healing reward does not secretly heal")
	clear_room(lab)
	check(lab.mode == FoldlightBossLab.Mode.REWARD, "room two has a second upgrade break")
	lab.ui.card_buttons[1].pressed.emit()
	check(lab.stage_index == 2 and lab.upgrades.size() == 2, "second reward leads to room three")
	check(is_equal_approx(player.fold_speed_multiplier, 1.18), "mobility upgrade changes folding speed")
	player.health = 1
	lab.retry_checkpoint()
	check(lab.stage_index == 2 and player.health == player.max_health, "retry restores health at current checkpoint")
	check(lab.upgrades.size() == 2 and is_equal_approx(player.fold_speed_multiplier, 1.18), "checkpoint preserves upgrades without stacking")
	clear_room(lab)
	check(lab.stage_index == 3 and is_instance_valid(lab.boss), "third room leads to boss")
	check(lab.boss.health == 320.0, "standard boss health remains unchanged")
	check(player.health >= 4, "boss checkpoint guarantees a recovery floor")
	lab.boss.take_damage(10000.0, &"return")
	check(lab.mode == FoldlightBossLab.Mode.RESULT, "voyage victory has an ending")
	lab.retry_checkpoint()
	check(lab.stage_index == 3 and lab.upgrades.size() == 2, "boss can be retried without replaying rooms")
	lab.start_voyage(&"relaxed")
	check(player.max_health == 6 and player.health == 6, "relaxed health survives stat resolution")
	check(lab.upgrades.is_empty() and is_equal_approx(player.fold_speed_multiplier, 1.0), "new voyage resets every upgrade")
	clear_room(lab)
	lab.ui.card_buttons[2].pressed.emit()
	check(player.max_health == 7, "paper-heart upgrade adds exactly one health")
	lab.retry_checkpoint()
	lab.retry_checkpoint()
	check(player.max_health == 7, "health upgrade does not stack on retry")
	var combinations: Array[StringName] = [&"bright_return", &"chain_light"]
	var stats: Dictionary = FoldlightDemoContent.build_stats(combinations, 5)
	check(is_equal_approx(float(stats["return_damage_multiplier"]), 1.32), "multiplicative rewards resolve consistently")
	check(float(stats["return_chain_add"]) == 1.0, "extra chain reaches shared runtime schema")
	var capacity_ids: Array[StringName] = [&"wide_fold", &"afterglow"]
	stats = FoldlightDemoContent.build_stats(capacity_ids, 5)
	player.apply_roguelite_stats(stats)
	check(player.get_capture_capacity() == 10 and is_equal_approx(player.fold_radius_multiplier, 1.08), "capacity and radius reward takes effect")
	check(is_equal_approx(player.damage_grace_add, 0.20), "afterglow changes protection duration")
	lab.show_title()
	check(root.canvas_transform == Transform2D.IDENTITY and not paused, "title cleans up all camera and pause state")
	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOLDLIGHT_VOYAGE_TESTS_PASS: %d checks" % checks)
		quit(0)
	else:
		print("FOLDLIGHT_VOYAGE_TESTS_FAIL: " + "; ".join(failures))
		quit(1)
