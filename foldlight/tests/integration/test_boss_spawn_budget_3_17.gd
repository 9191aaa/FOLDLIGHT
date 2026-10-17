extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	slice.start_slice(3)
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice._clear_pending_spawns()
	slice.combat_runtime.clear_combat()
	slice.combat_runtime.set_active(true)
	slice.controller.evolution.record_kill_experience(812)
	var pressure := slice.controller.evolution.get_enemy_snapshot()
	check(pressure.stage == 3 and pressure.threat_limit == 59, "Lv8 fixture has the actual early boss pressure budget")
	# 16 heavy + one elite + five drifters use 59 threat in only 22 actors.
	# A population-only reservation sees spare slots and would add 12 excess.
	for index in 22:
		var enemy_id := &"ram" if index < 16 else (&"shutter_seraph" if index == 16 else &"drifter")
		var threat := 3 if index < 16 else (6 if index == 16 else 1)
		slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": enemy_id, "threat_cost": threat,
			"spawn_position": slice.player.global_position + Vector2(700.0 + index * 10.0, 0.0)}, false)
	slice._report_population()
	check(slice.controller.get_population_snapshot().alive_count == 22 and slice.controller.get_population_snapshot().threat_total == 59, "real shared heavy actors fill threat while leaving population space")
	var kills := slice.controller.defeated_total
	var xp := slice.controller.evolution.experience_total
	for step in 34:
		slice._advance_boss_encounter(0.1)
	slice._report_population()
	var population := slice.controller.get_population_snapshot()
	check(slice._boss_director.get_snapshot().state == &"active" and slice._boss_snapshots().size() == 1, "the earned boss really arrives after its warning")
	check(int(population.threat_total) <= int(population.threat_limit) and int(population.alive_count) <= slice._effective_population_limit(), "boss arrival reserves both live threat and the reduced actor limit")
	check(slice.combat_runtime.enemies.size() < 23, "the arrival retires surplus ordinary threat even when actor slots alone were sufficient")
	check(slice.controller.defeated_total == kills and slice.controller.evolution.experience_total == xp and slice.controller.peek_pending_reward().is_empty(), "population retirement grants no kills, XP, task completion or false boss reward")
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_SPAWN_BUDGET_3_17: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + label)
	if not ok:
		failures.append(label)
