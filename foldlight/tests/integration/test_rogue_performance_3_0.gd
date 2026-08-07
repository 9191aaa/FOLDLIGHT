extends SceneTree

## Rendered 3.0 stress scene: phase-three boss, all three mechanic roles,
## the hard projectile ceiling, terrain, camera, particles, telegraphs and HUD.

const WARMUP_FRAMES: int = 60
const SAMPLE_FRAMES: int = 240

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "3.0 release scene loads for rendered stress")
	if game == null:
		_finish()
		return
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	await create_timer(1.3).timeout
	var runtime := session.world.combat_runtime
	runtime.clear_combat()
	session.player.invulnerability = 9999.0
	session.player.weapon_mount.enabled = false

	var boss_definition := FoldlightRogueContentCatalog.boss_by_id(&"origami_judge")
	var boss := runtime._spawn_boss_actor(boss_definition, {"spawn_position": Vector2(1440, 420)}, false)
	boss.health = boss.definition.base_health * 0.28
	boss.advance_simulation(0.01, session.player.global_position)
	boss.arena_controller.set_phase(2)
	var mechanic_ids: Array[StringName] = [&"paper_turret", &"bell_binder", &"ink_warden"]
	for index in 18:
		var column := index % 6
		var row := index / 6
		runtime._spawn_enemy_from_entry({"enemy_id": mechanic_ids[index % mechanic_ids.size()], "spawn_position": Vector2(320 + column * 390, 250 + row * 430)}, false)

	for index in FoldlightRogueCombatRuntime.MAX_PROJECTILES:
		var column := index % 26
		var row := index / 26
		var position := Vector2(180 + column * 100, 180 + row * 125)
		if position.distance_to(session.player.global_position) < 90.0:
			position.y -= 140.0
		runtime._spawn_projectile({"origin": position, "velocity": Vector2.ZERO, "hostile": true, "reflectable": index % 5 != 0, "damage": 1.0, "radius": 8.0, "lifetime": 8.0, "style": &"black_gold_cut" if index % 5 == 0 else &"judgement_petal"})
		runtime.projectiles[-1].set_meta("terrain_grace", 20.0)
	_check(runtime.projectiles.size() == FoldlightRogueCombatRuntime.MAX_PROJECTILES, "stress scene reaches the hard 260-projectile ceiling")

	for _frame in WARMUP_FRAMES:
		await process_frame
	var samples: Array[float] = []
	var previous_tick := Time.get_ticks_usec()
	var max_draw_calls := 0.0
	for _frame in SAMPLE_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous_tick) / 1000.0)
		previous_tick = now
		max_draw_calls = maxf(max_draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	var average_ms := total / float(samples.size())
	var p95_ms: float = samples[clampi(int(samples.size() * 0.95), 0, samples.size() - 1)]
	var static_memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("FOLDLIGHT_ROGUE_PERF average_ms=%.2f p95_ms=%.2f draw_calls=%.0f memory_mb=%.1f enemies=%d projectiles=%d" % [average_ms, p95_ms, max_draw_calls, static_memory_mb, runtime.enemies.size(), runtime.projectiles.size()])
	_check(average_ms <= 20.5, "average rendered frame stays within 60 fps tolerance")
	_check(p95_ms <= 26.0, "95th percentile avoids visible input stutter")
	_check(max_draw_calls <= 2000.0, "draw calls remain inside the desktop release budget")
	_check(static_memory_mb <= 800.0, "static memory remains inside the release budget")
	_check(runtime.projectiles.size() <= FoldlightRogueCombatRuntime.MAX_PROJECTILES, "live boss fire never exceeds the readability ceiling")
	_check(runtime.enemies.size() <= 20, "stress enemy population remains bounded")

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
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
		print("FOLDLIGHT_ROGUE_PERFORMANCE_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_PERFORMANCE_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
