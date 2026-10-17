extends SceneTree

const RenderRedraw = preload("res://scripts/visuals/render_redraw.gd")
var failures: Array[String] = []
var checks: int = 0


class DrawProbe extends Node2D:
	var value: int = 0
	var drawn_value: int = -1
	var draw_count: int = 0
	var draws_by_frame: Dictionary = {}

	func _draw() -> void:
		drawn_value = value
		draw_count += 1
		var frame := Engine.get_process_frames()
		draws_by_frame[frame] = int(draws_by_frame.get(frame, 0)) + 1
		draw_circle(Vector2.ZERO, 2.0, Color.WHITE)


class PhysicsDriver extends Node:
	var step: Callable

	func _physics_process(delta: float) -> void:
		if step.is_valid(): step.call(delta)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	await _test_catch_up()
	await _test_pause_and_lifetime()
	await _test_feedback_clear()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_RENDER_REDRAW_3_18: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _test_catch_up() -> void:
	var probe := DrawProbe.new()
	var driver := PhysicsDriver.new()
	root.add_child(probe)
	root.add_child(driver)
	driver.set_physics_process(false)
	var enemy := load("res://scenes/roguelite/combat/rogue_enemy_actor.tscn").instantiate() as FoldlightRogueEnemyActor
	root.add_child(enemy)
	enemy.configure(FoldlightRogueContentCatalog.enemy_by_id(&"drifter"), &"redraw_enemy")
	enemy.position = Vector2(300, 300)
	var boss := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn").instantiate() as FoldlightRogueBossActor
	root.add_child(boss)
	boss.configure(FoldlightRogueContentCatalog.boss_by_id(&"tide_loom_mother"), Rect2(0, 0, 2880, 1620), 318, {"arena_pressure": false})
	var returned := FoldlightRogueProjectile.new()
	root.add_child(returned)
	returned.configure({"origin": Vector2(100, 100), "velocity": Vector2(120, 0), "style": &"return_light", "hostile": false, "lifetime": 9.0})
	await physics_frame
	await process_frame
	await process_frame
	probe.draw_count = 0
	probe.draws_by_frame.clear()
	var counts := {"enemy": {}, "boss": {}, "returned": {}}
	for item: Dictionary in [{"node": enemy, "name": "enemy"}, {"node": boss, "name": "boss"}, {"node": returned, "name": "returned"}]:
		var canvas := item["node"] as CanvasItem
		var key: String = item["name"]
		canvas.draw.connect(func() -> void:
			var frame := Engine.get_process_frames()
			counts[key][frame] = int(counts[key].get(frame, 0)) + 1
		)
	var state := {"steps": 0, "frames": {}, "elapsed": 0.0}
	var rng_before := enemy._rng.state
	driver.step = func(delta: float) -> void:
		state.steps += 1
		state.elapsed += delta
		var frame := Engine.get_process_frames()
		state.frames[frame] = int(state.frames.get(frame, 0)) + 1
		probe.value = state.steps
		for duplicate in 6: RenderRedraw.request(probe)
		enemy.advance_simulation(delta, Vector2(900, 300))
		boss.advance_simulation(delta, Vector2(900, 300))
		returned.advance_simulation(delta)
		if state.steps == 8:
			enemy.take_damage(0.1, &"weapon", Vector2.RIGHT)
			driver.set_physics_process(false)
	driver.set_physics_process(true)
	# Deliberately create real engine catch-up steps, whose deferred queues are
	# flushed separately. Eight calls inside one callback would miss this bug.
	OS.delay_msec(150)
	for frame in 30:
		await process_frame
		if state.steps >= 8: break
	await process_frame
	_check(state.steps == 8 and _maximum(state.frames) >= 2, "fixture runs eight real physics steps with multiple catch-up steps in one display frame")
	_check(_maximum(probe.draws_by_frame) == 1 and probe.drawn_value == 8, "duplicate requests rebuild once per display frame and draw the latest simulation state")
	_check(_maximum(counts.enemy) == 1, "ordinary enemy drawing is coalesced across real physics catch-up")
	_check(_maximum(counts.boss) == 1, "boss puppet drawing is coalesced without changing its pose clock")
	_check(_maximum(counts.returned) == 1, "dynamic returned-light trail is coalesced without slowing projectile simulation")
	_check(is_equal_approx(enemy._age, float(state.elapsed)) and is_equal_approx(boss._visual_time, float(state.elapsed)), "enemy and boss clocks retain every physics step")
	_check(returned.position.is_equal_approx(Vector2(100 + 120 * float(state.elapsed), 100)) and returned.age > 0.1, "returned-light movement retains the complete elapsed physics time")
	_check(enemy._rng.state == rng_before and enemy.get_hit_feedback_snapshot()["flash"] > 0.0, "redraw scheduling consumes no combat RNG and retains the final confirmed hit feedback")
	print("FOLDLIGHT_REDRAW_CATCHUP steps=%d display_frames=%d probe_draws=%d enemy_draws=%d" % [state.steps, state.frames.size(), probe.draw_count, _total(counts.enemy)])
	for node in [probe, driver, enemy, boss, returned]: node.queue_free()
	await process_frame


func _test_pause_and_lifetime() -> void:
	var probe := DrawProbe.new()
	var driver := PhysicsDriver.new()
	var doomed := DrawProbe.new()
	root.add_child(probe)
	root.add_child(driver)
	root.add_child(doomed)
	driver.set_physics_process(false)
	await process_frame
	await process_frame
	var doomed_id := doomed.get_instance_id()
	var before := probe.draw_count
	driver.step = func(_delta: float) -> void:
		probe.value = 42
		RenderRedraw.request(probe)
		RenderRedraw.request(doomed)
		doomed.queue_free()
		probe.set_process(false)
		driver.set_physics_process(false)
		paused = true
	driver.set_physics_process(true)
	await physics_frame
	await process_frame
	await process_frame
	_check(paused and probe.drawn_value == 42 and probe.draw_count == before + 1, "the final visual update flushes after the scene pauses and owner processing stops")
	_check(not is_instance_id_valid(doomed_id) and RenderRedraw._pending.is_empty(), "queued deaths are skipped without retaining dead canvases or pending work")
	var paused_draws := probe.draw_count
	await process_frame
	await process_frame
	_check(probe.draw_count == paused_draws, "paused unchanged visuals do not schedule a repeating redraw loop")
	paused = false
	probe.value = 43
	RenderRedraw.request(probe)
	await process_frame
	_check(probe.drawn_value == 43, "idle-frame updates still become visible directly after resume")
	var detached := DrawProbe.new()
	RenderRedraw.request(detached)
	detached.free()
	_check(RenderRedraw._pending.is_empty(), "off-tree requests do not hold nodes or leave a future callback")
	probe.queue_free()
	driver.queue_free()
	await process_frame


func _test_feedback_clear() -> void:
	var runtime := FoldlightRogueCombatRuntime.new()
	var driver := PhysicsDriver.new()
	root.add_child(runtime)
	root.add_child(driver)
	driver.set_physics_process(false)
	runtime.set_active(false)
	runtime._add_active_flash(Vector2(80, 80), Color.WHITE, 36.0, 0.2)
	await process_frame
	await process_frame
	var shown: Array[int] = []
	runtime.draw.connect(func() -> void: shown.append(runtime._active_flashes.size()))
	driver.step = func(_delta: float) -> void:
		runtime._update_visual_feedback(0.25)
		runtime.set_active(false)
		driver.set_physics_process(false)
	driver.set_physics_process(true)
	await physics_frame
	await process_frame
	await process_frame
	_check(not shown.is_empty() and shown[-1] == 0 and runtime._active_flashes.is_empty(), "expired hit effects clear their retained canvas even when combat stops in the same physics frame")
	runtime.queue_free()
	driver.queue_free()
	await process_frame


func _maximum(values: Dictionary) -> int:
	var result := 0
	for value in values.values(): result = maxi(result, int(value))
	return result


func _total(values: Dictionary) -> int:
	var result := 0
	for value in values.values(): result += int(value)
	return result


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
	print(("[PASS] " if condition else "[FAIL] ") + description)
