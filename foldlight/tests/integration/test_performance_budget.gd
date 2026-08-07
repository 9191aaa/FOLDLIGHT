extends SceneTree

## Rendered stress test: maximum hostile petals, enemy cap, persistent particles,
## phase-three boss, and the live HUD at the same time.

const WARMUP_FRAMES: int = 60
const SAMPLE_FRAMES: int = 240

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("performance test could not load main scene")
		quit(1)
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	game.start_campaign_mission(11)
	game._profile_recorded = true
	_dismiss_briefings(game)
	game.act = FoldlightGame.FINAL_ACT
	game.player.invulnerability = 9999.0
	game._spawn_boss()
	_dismiss_briefings(game)
	if not game.enemies.is_empty():
		game.enemies[0]["position"] = Vector2(960.0, 250.0)
		game.enemies[0]["age"] = 10.0
		game.enemies[0]["boss_phase"] = 3
	for index in FoldlightGame.ENEMY_CAP - 1:
		var roster: Array[int] = [
			FoldlightGame.EnemyType.DRIFTER, FoldlightGame.EnemyType.FAN,
			FoldlightGame.EnemyType.WEAVER, FoldlightGame.EnemyType.RAM,
			FoldlightGame.EnemyType.BLOOMER, FoldlightGame.EnemyType.LEECH,
			FoldlightGame.EnemyType.MIRROR, FoldlightGame.EnemyType.REWINDER,
			FoldlightGame.EnemyType.CARVER, FoldlightGame.EnemyType.BELL,
			FoldlightGame.EnemyType.THIEF, FoldlightGame.EnemyType.MOTH,
		]
		game._spawn_enemy(roster[index % roster.size()], index % 4 == 0)
		game.enemies[-1]["position"] = Vector2(180.0 + (index % 7) * 250.0, 210.0 + (index / 7) * 270.0)
	game.hostile_shots.clear()
	for shot_index in FoldlightGame.HOSTILE_CAP:
		var angle := float(shot_index) * TAU / float(FoldlightGame.HOSTILE_CAP)
		var radius := 170.0 + float(shot_index % 7) * 68.0
		var origin := Vector2(960.0, 540.0) + Vector2.from_angle(angle) * radius
		if shot_index % 9 == 0:
			game._spawn_sealed_hostile(origin, angle + PI * 0.5, 42.0, 0.045)
		else:
			game._spawn_hostile(origin, angle + PI * 0.5, 42.0, 0.045, Color(0.86, 0.24, 0.62), shot_index % 2)
		game.hostile_shots[-1]["life"] = 999.0
	for burst_index in 24:
		game._burst(Vector2(960.0, 540.0), Color(0.95, 0.55, 0.35), 32, 1.0)
	for particle in game.particles:
		particle["life"] = 999.0
		particle["max_life"] = 999.0
		particle["velocity"] = Vector2.ZERO
	game._event_message = "PERFORMANCE STRESS"
	game._event_message_timer = 999.0

	for frame_index in WARMUP_FRAMES:
		await process_frame

	var samples: Array[float] = []
	var previous_tick := Time.get_ticks_usec()
	var max_draw_calls := 0.0
	var process_total_ms := 0.0
	var physics_total_ms := 0.0
	var max_primitives := 0.0
	for frame_index in SAMPLE_FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous_tick) / 1000.0)
		previous_tick = now
		max_draw_calls = maxf(max_draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		process_total_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_total_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		max_primitives = maxf(max_primitives, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	var average_ms := total / float(samples.size())
	var p95_ms: float = samples[clampi(int(samples.size() * 0.95), 0, samples.size() - 1)]
	var static_memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("FOLDLIGHT_PERF average_ms=%.2f p95_ms=%.2f process_ms=%.2f physics_ms=%.2f draw_calls=%.0f primitives=%.0f memory_mb=%.1f enemies=%d hostile=%d particles=%d" % [average_ms, p95_ms, process_total_ms / SAMPLE_FRAMES, physics_total_ms / SAMPLE_FRAMES, max_draw_calls, max_primitives, static_memory_mb, game.enemies.size(), game.hostile_shots.size(), game.particles.size()])
	_check(average_ms <= 20.5, "average rendered frame stays within 60 fps tolerance")
	_check(p95_ms <= 26.0, "95th percentile frame avoids visible stutter")
	_check(max_draw_calls <= 2000.0, "desktop draw calls stay below release budget")
	_check(game.enemies.size() <= FoldlightGame.ENEMY_CAP + 2, "enemy population remains bounded during stress")
	_check(game.hostile_shots.size() <= FoldlightGame.HOSTILE_CAP, "hostile population remains bounded during stress")
	_check(game.particles.size() <= FoldlightGame.PARTICLE_CAP, "particle population remains bounded during stress")

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	if _failures.is_empty():
		print("FOLDLIGHT_PERFORMANCE: PASS")
		quit(0)
	else:
		printerr("FOLDLIGHT_PERFORMANCE: FAIL — ", ", ".join(_failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _dismiss_briefings(game: FoldlightGame) -> void:
	while game.mode == FoldlightGame.RunMode.BRIEFING:
		game._advance_briefing(false)
