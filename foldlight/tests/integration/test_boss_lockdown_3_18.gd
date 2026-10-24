extends SceneTree
var failures := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	_test_clock()
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.start_slice(318001)
	slice.combat_runtime.set_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.controller.evolution.experience_level = 8
	for step in 32: slice._advance_encounters(0.1)
	check(slice._boss_snapshots().size() == 1, "fixture contains a real acknowledged boss")
	var lockdown := slice._boss_lockdown
	lockdown._elapsed = 89.9
	slice._advance_encounters(0.1)
	check(lockdown.get_snapshot().state == &"warning", "live boss starts a visible perimeter warning after 90 combat seconds")
	var remaining := float(lockdown.get_snapshot().remaining)
	slice._application_suspended = true
	slice._advance_encounters(10.0)
	check(lockdown.get_snapshot().remaining == remaining, "solo background suspension freezes the arena warning")
	slice._application_suspended = false
	slice._pause_game()
	slice._advance_encounters(10.0)
	check(lockdown.get_snapshot().remaining == remaining, "pause freezes the arena warning")
	slice._resume_game()
	slice.combat_runtime.set_physics_process(false)
	slice._modal_kind = &"objective_complete"
	slice._advance_encounters(10.0)
	check(lockdown.get_snapshot().remaining == remaining, "reward completion freezes the arena warning")
	slice._modal_kind = &""
	lockdown._remaining = 0.1
	slice._advance_encounters(0.1)
	var center := Vector2(lockdown.get_snapshot().position)
	slice.player.global_position = center + Vector2(float(lockdown.get_snapshot().radius) + 200.0, 0)
	slice.player.invulnerability = 0.0
	var health := slice.player.health
	for step in 19: slice._advance_encounters(0.1)
	check(slice.player.health == health, "outside the perimeter gets a full two-second re-entry grace")
	slice._advance_encounters(0.1)
	check(slice.player.health == health - 1, "lockdown deals one real heart through shared combat feedback")
	slice.player.grant_invulnerability(10.0)
	for step in 20: slice._advance_encounters(0.1)
	check(slice.player.health == health - 1, "shared invulnerability protects against the next scheduled lockdown hit")
	var nav := slice.get_navigation_snapshot()
	check(nav.boss_lockdown.outside and nav.boss_lockdown.safe_position is Vector2, "outside player receives a world-space return waypoint")
	slice._navigation.update_snapshot(nav)
	check(slice._navigation.get_navigation_snapshot().danger_text.contains("围猎圈外") and slice._navigation._indicator_kind == &"boss_lockdown", "HUD and return arrow identify the hunting perimeter rather than the mission")
	check(slice._boss_hud_snapshot().lockdown.state == &"active", "boss HUD projects the same authoritative lockdown state")
	# The last boss also finishes a mission, which opens its completion modal
	# synchronously before the later boss reward is queued.
	slice.controller.objectives.current["kind"] = &"clear_swarm"
	slice.controller.objectives.current["progress"] = 0.0
	slice.controller.objectives.current["required"] = 1.0
	for actor in slice.combat_runtime.enemies.duplicate():
		if actor is FoldlightRogueBossActor: actor.take_damage(actor.get_maximum_health() * 10)
	check(lockdown.get_snapshot().state == &"idle", "actual final boss death removes the perimeter before loot opens")
	check(slice._modal_kind == &"objective_complete" and StringName(slice._reward_context.get("source", &"")) == &"mission", "simultaneous final boss and mission preserve mission-first reward presentation")
	check(not slice._navigation.get_navigation_snapshot().danger_text.contains("围猎") and slice._navigation._indicator_kind != &"boss_lockdown", "completion HUD immediately drops the cleared arena and return arrow")
	slice.start_slice(318001)
	check(lockdown.get_snapshot().state == &"idle" and not slice.player.is_horizontal_input_reversed(), "restart leaves no stale world restriction or reversed controls")
	for seed in 3:
		slice.start_slice(seed)
		slice.combat_runtime.set_process(false)
		slice.combat_runtime.set_physics_process(false)
		lockdown._center = slice.controller.map_definition.player_spawn
		lockdown._radius = 1800.0
		var point := slice.controller.map_definition.bounds.end - Vector2(400,400)
		slice.controller.zones.advance_to(73.0, PackedVector2Array(), point)
		var waypoint := lockdown.return_waypoint(point, slice.controller.map_runtime, slice.controller.zones)
		var route := lockdown.get_snapshot()
		check(route.return_route_valid and waypoint != point, "map %d supplies a genuinely reachable return route" % seed)
		check(Vector2(route.return_goal).distance_to(lockdown._center) < lockdown._radius and not slice.controller.zones.is_point_closed(route.return_goal) and not slice.controller.zones.is_point_reserved(route.return_goal), "map %d return destination is inside the circle and outside announced poison" % seed)
		check(slice.controller.map_definition.is_permanent_safe(route.return_goal, 32.0), "map %d prefers a permanent refuge rather than a closed district" % seed)
		lockdown._state = &"warning"
		lockdown._outside = true
		lockdown._remaining = 8.0
		lockdown.extend_return_warning()
		check(lockdown.get_snapshot().remaining >= float(route.return_distance) / 280.0 + 3.0, "map %d return warning accounts for the real wall detour" % seed)
	slice.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_BOSS_LOCKDOWN_3_18: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _test_clock() -> void:
	var zone := FoldlightEndlessBossLockdown.new()
	root.add_child(zone)
	var director := {"state": &"active", "wave_index": 1}
	var bosses: Array[Dictionary] = [{"position": Vector2(2000,2000)}]
	var inside := Vector2(2000,2000)
	var outside := Vector2(4200,2000)
	for step in 899: zone.advance(0.1, director, bosses, inside)
	check(zone.get_snapshot().state == &"approach", "early combat has no area punishment")
	zone.advance(0.1, director, bosses, inside)
	check(zone.get_snapshot().state == &"warning" and zone.get_snapshot().radius == 1800, "90 seconds announces a wide 1800-radius arena")
	var remaining := float(zone.get_snapshot().remaining)
	zone.advance(30.0, director, bosses, outside)
	check(is_equal_approx(zone.get_snapshot().remaining, remaining - 0.1), "a stalled frame cannot skip the warning")
	bosses[0].position += Vector2(1000,0)
	for step in 79: zone.advance(0.1, director, bosses, inside)
	check(zone.get_snapshot().state == &"active" and zone.get_snapshot().position == inside, "the announced circle stays fixed when bosses move")
	var hits := 0
	for step in 59:
		if zone.advance(0.1, director, bosses, outside): hits += 1
	check(hits == 2, "continuous outside exposure gives periodic hits, never a per-frame damage burst")
	zone.advance(0.1, director, bosses, inside)
	hits = 0
	for step in 19:
		if zone.advance(0.1, director, bosses, outside): hits += 1
	check(hits == 0, "re-entering the safe circle resets outside exposure")
	zone.advance(0.1, {"state": &"waiting"}, [], outside)
	check(zone.get_snapshot().state == &"idle" and not zone.get_snapshot().outside, "cleared encounters remove all exposure and drawing state")
	director.wave_index = 2
	for index in 5: bosses.append({"position": inside + Vector2(index * 100,0)})
	for step in 900: zone.advance(0.1, director, bosses, Vector2(9000,2000))
	check(zone.get_snapshot().radius >= 2400 and zone.get_snapshot().remaining > 8, "multiple bosses widen the arena and distant players receive return time")
	zone.queue_free()

func check(value: bool, label: String) -> void:
	if value: print("[PASS] " + label)
	else:
		failures += 1
		push_error("[FAIL] " + label)
