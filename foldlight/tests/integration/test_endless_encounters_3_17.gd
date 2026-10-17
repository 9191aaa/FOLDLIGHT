extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_test_schedule()
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	_test_boss_runtime(slice)
	_test_bombardment(slice)
	_test_closure_bias(slice)
	_test_solo_host_suspension(slice)
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_ENCOUNTERS_3_17: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _test_schedule() -> void:
	var director := FoldlightEndlessBossDirector.new()
	director.reset(317)
	check(director.advance(1.0, 7, 900.0).state == &"waiting", "no first boss below level eight even during a long run")
	check(director.advance(1.0, 8, 900.0).state == &"warning", "level eight starts a real warning")
	check(director.advance(10.0, 50, 910.0).warning_remaining > 2.8, "a stall or burst of levels cannot consume the full warning")
	for step in 30:
		director.advance(0.1, 8, 910.0)
	check(director.confirm_spawned([&"boss_a"]), "spawn acknowledgement activates one reserved encounter")
	check(not director.report_defeated(&"unknown", 910.0), "unrelated deaths cannot complete an encounter")
	check(director.report_defeated(&"boss_a", 910.0) and not director.report_defeated(&"boss_a", 910.0), "last boss grants one completion edge only")
	check(director.advance(0.1, 50, 923.0).state == &"waiting", "new levels respect the deep-run fourteen-second post-boss recovery")
	check(director.advance(0.1, 50, 924.0).wave_index == 2, "the next encounter begins after recovery")
	for step in 31:
		director.advance(0.1, 50, 924.0)
	check(director.planned_boss_ids().size() == 2, "high-level second encounter enables two distinct simultaneous bosses")
	check(director.confirm_spawned([&"boss_b", &"boss_c"]), "two boss identities activate as a single encounter")
	check(not director.report_defeated(&"boss_b", 924.0) and director.get_snapshot().active_count == 1, "first of two deaths keeps the encounter active")
	check(director.report_defeated(&"boss_c", 924.0), "only final death completes a multi-boss wave")
	for wave in range(3, 8):
		var time := 924.0 + (wave - 2) * 38.0
		director.advance(0.1, 50, time)
		for step in 31:
			director.advance(0.1, 50, time)
		var ids: Array[StringName] = []
		for index in director.planned_boss_ids().size():
			ids.append(StringName("late_%d_%d" % [wave, index]))
		check(ids.size() == mini(wave, 6), "deep encounter %d grows predictably and caps at six bosses" % wave)
		check(director.confirm_spawned(ids), "deep encounter acknowledges every reserved actor")
		for identity in ids:
			director.report_defeated(identity, time)
	director.reset(317)
	check(director.get_snapshot().wave_index == 0 and director.get_snapshot().active_count == 0, "restart clears all boss scheduling state")

func _test_boss_runtime(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(317001)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice._clear_pending_spawns()
	slice.controller.evolution.experience_level = 8
	slice._advance_encounters(0.1)
	check(slice._boss_entries.size() == 1 and slice._boss_snapshots().is_empty(), "runtime displays a located boss warning before creating its actor")
	var warning := float(slice._boss_director.get_snapshot().warning_remaining)
	slice._pause_game()
	slice._advance_encounters(5.0)
	check(is_equal_approx(warning, slice._boss_director.get_snapshot().warning_remaining), "pause freezes located boss arrival")
	slice._resume_game()
	slice.combat_runtime.set_physics_process(false)
	for step in 31:
		slice._advance_encounters(0.1)
	check(slice._boss_snapshots().size() == 1, "level eight creates an actual shared boss actor")
	var boss: FoldlightRogueBossActor
	for actor in slice.combat_runtime.enemies:
		if actor is FoldlightRogueBossActor:
			boss = actor
	if boss == null:
		return
	var second := slice.combat_runtime._spawn_enemy_from_entry({"boss_id": &"tide_loom_mother", "spawn_position": slice.player.global_position + Vector2(700, 0), "boss_options": {"health_scale": 0.8, "endless_roam": true, "arena_pressure": false}}, false) as FoldlightRogueBossActor
	check(boss.actor_id != second.actor_id, "simultaneous bosses have independent actor identities")
	var minion := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": slice.player.global_position + Vector2(600, 0), "spawned_by": boss.actor_id}, false)
	var ordinary := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": slice.player.global_position + Vector2(640, 0)}, false)
	slice.combat_runtime._on_boss_telegraph_requested({"origin": boss.global_position, "duration": 3.0}, boss.actor_id)
	slice.combat_runtime._on_boss_telegraph_requested({"origin": second.global_position, "duration": 3.0}, second.actor_id)
	slice.combat_runtime._on_boss_attack_cancelled(1.0, boss.actor_id)
	var retained := 0
	for child in slice.world.room_runtime.projectile_container.get_children():
		if child is FoldlightBossAttackTelegraph and not child.is_queued_for_deletion():
			retained += 1
	check(retained == 1, "stagger cancels only its own boss telegraph")
	boss.take_damage(boss.get_maximum_health() * 10.0)
	check(not slice.combat_runtime.enemies.has(minion) and slice.combat_runtime.enemies.has(ordinary) and slice.combat_runtime.enemies.has(second), "boss defeat removes only owned summons, preserving other bosses and ordinary mobs")
	check(slice.controller.peek_pending_reward().get("source") == &"boss" and slice._modal_kind == &"objective_complete", "real scheduled boss defeat queues a visible guarded reinforcement reward")
	check(slice.controller.peek_pending_reward().get("heal_on_claim") == 1, "boss reinforcement includes one health")
	slice.start_slice(317001)
	slice.combat_runtime.set_physics_process(false)
	check(slice._boss_snapshots().is_empty() and slice._boss_entries.is_empty(), "restart removes old boss actors and warnings")

func _test_bombardment(slice: FoldlightEndlessSliceRuntime) -> void:
	var barrage := slice._bombardment
	var point := slice.player.global_position
	barrage.advance(0.1, 90.0, point, PackedVector2Array(), 0)
	var snapshot := barrage.get_snapshot()
	check(snapshot.state == &"warning" and snapshot.zones.size() >= 1, "bombardment creates real visible landing sites near the player")
	check(Vector2(snapshot.zones[0].position).is_equal_approx(point), "unprotected player area can be targeted to force movement")
	var warning := float(snapshot.warning_remaining)
	barrage.advance(10.0, 100.0, point, PackedVector2Array(), 0)
	check(is_equal_approx(barrage.get_snapshot().warning_remaining, warning - 0.1), "long frame cannot skip bombardment warning")
	var edges := 0
	for step in 40:
		edges += 1 if not barrage.advance(0.1, 100.0, point, PackedVector2Array(), 0).is_empty() else 0
	check(edges == 1, "one barrage produces exactly one damage edge across all landing sites")
	barrage.configure(slice.controller.map_definition, slice.controller.map_runtime, 317)
	barrage.advance(0.1, 90.0, point, PackedVector2Array(), 2)
	check(barrage.get_snapshot().state == &"rest", "two bosses suppress additional bombardment pressure")
	barrage.advance(0.1, 90.0, point, PackedVector2Array([point]), 0)
	var protected := true
	for zone in barrage.get_snapshot().zones:
		protected = protected and Vector2(zone.position).distance_to(point) >= float(zone.radius) + 300.0
	check(protected, "active facilities and escort-route points stay clear of bomb landing sites")

func _test_closure_bias(slice: FoldlightEndlessSliceRuntime) -> void:
	var map := slice.controller.map_definition
	check(map.bounds.size.x >= 7680 and map.bounds.size.y >= 5120 and map.closure_zone_ids.size() >= 11, "expanded authored maps add actual districts and closure choices")
	var director := FoldlightEndlessZoneDirector.new()
	director.reset(map, 317)
	var point := Vector2(650, 700)
	var state := director.advance_to(60.0, PackedVector2Array(), point)
	var targeting := false
	for zone in state.zones:
		if zone.state == &"warning" and Rect2(zone.rect).has_point(point):
			targeting = true
	check(targeting, "nearby closure rounds can select the player's current district")
	var chosen: Array = state.warning_ids.duplicate()
	check(director.advance_to(61.0, PackedVector2Array(), map.bounds.end - Vector2(500, 500)).warning_ids == chosen, "moving away never makes an announced poison zone chase the player")
	director.reset(map, 317)
	state = director.advance_to(60.0, PackedVector2Array([point]), point)
	check(state.warning_ids != chosen, "active task protection takes precedence over local poison pressure")

func _test_solo_host_suspension(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(317001)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.controller.evolution.experience_level = 8
	slice.controller.evolution.advance_survival(90.0)
	slice.controller.objectives.rotation_index = 5
	slice.controller.objectives._task_serial = 0
	slice.controller.objectives._start_current_objective()
	slice._advance_encounters(0.1)
	check(not slice._pending_spawns.is_empty() and slice._boss_entries.size() == 1 and slice._bombardment.get_snapshot().state == &"warning", "solo host fixture contains ordinary, boss and bombardment warnings")
	if slice._pending_spawns.is_empty():
		return
	var before_time := slice.controller.evolution.survival_seconds
	var before_spawn := float(slice._pending_spawns[0].remaining)
	var before_boss := float(slice._boss_director.get_snapshot().warning_remaining)
	var before_bomb := float(slice._bombardment.get_snapshot().warning_remaining)
	var touch := slice._touch_controls
	var old_host: Dictionary = {}
	for key: String in ["_host_suspended", "_host_layout", "_host_cancel_epoch", "_touch_mode", "_safe_insets"]:
		old_host[key] = touch.get(key)
	touch.call("apply_host_state", {"suspended": true, "cancelEpoch": int(old_host._host_cancel_epoch) + 1})
	slice._physics_process(0.1)
	slice._advance_spawn_queue(0.1)
	slice._advance_encounters(0.1)
	check(slice.controller.evolution.survival_seconds == before_time and float(slice._pending_spawns[0].remaining) == before_spawn and float(slice._boss_director.get_snapshot().warning_remaining) == before_boss and float(slice._bombardment.get_snapshot().warning_remaining) == before_bomb, "solo host overlay still freezes progression and all three warning clocks")
	for key: String in old_host:
		touch.set(key, old_host[key])
	touch.call("_refresh_active")
	slice._application_suspended = true
	slice._physics_process(0.1)
	slice._advance_spawn_queue(0.1)
	slice._advance_encounters(0.1)
	check(slice.controller.evolution.survival_seconds == before_time and float(slice._pending_spawns[0].remaining) == before_spawn and float(slice._boss_director.get_snapshot().warning_remaining) == before_boss and float(slice._bombardment.get_snapshot().warning_remaining) == before_bomb, "solo application suspension retains the same frozen simulation policy")
	slice._application_suspended = false
	slice._physics_process(0.1)
	slice._advance_spawn_queue(0.1)
	slice._advance_encounters(0.1)
	check(slice.controller.evolution.survival_seconds > before_time and float(slice._pending_spawns[0].remaining) < before_spawn and float(slice._boss_director.get_snapshot().warning_remaining) < before_boss and float(slice._bombardment.get_snapshot().warning_remaining) < before_bomb, "solo resumes every clock after the host and application become available")

func check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
