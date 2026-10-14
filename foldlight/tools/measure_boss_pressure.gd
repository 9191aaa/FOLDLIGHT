extends SceneTree

## A deterministic emission probe, not a player win-rate simulation. Each
## 60-second slice holds boss health in one phase and never damages the boss.
const STEP := 1.0 / 60.0
const SECONDS := 60.0


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var rows: Array[Dictionary] = []
	for definition in FoldlightRogueContentCatalog.BOSSES:
		for phase in 3:
			var boss := load("res://scenes/roguelite/bosses/rogue_boss_actor.tscn").instantiate() as FoldlightRogueBossActor
			root.add_child(boss)
			boss.configure(definition, Rect2(0, 0, 2880, 1620), 20261014)
			var ratio := 1.0 if phase == 0 else float(definition.phase_thresholds[phase - 1]) - 0.04
			boss.health = definition.base_health * ratio
			var row := {"boss": String(definition.content_id), "phase": phase + 1, "health": definition.base_health, "seconds": SECONDS, "volleys": 0, "shots": 0, "black_shots": 0, "largest_burst": 0, "support_requests": 0, "min_warning": 100.0, "min_recovery": 100.0}
			boss.volley_requested.connect(func(volley: Dictionary) -> void:
				var shots := int(volley.get("projectile_count", 1)) * int(volley.get("burst_count", 1))
				row["volleys"] += 1
				row["shots"] += shots
				row["largest_burst"] = maxi(int(row["largest_burst"]), shots)
				if not bool(volley.get("reflectable", true)):
					row["black_shots"] += shots
			)
			boss.telegraph_requested.connect(func(warning: Dictionary) -> void: row["min_warning"] = minf(float(row["min_warning"]), float(warning.get("duration", 100.0))))
			boss.minion_requested.connect(func(_request: Dictionary) -> void: row["support_requests"] += 1)
			for step in int(SECONDS / STEP):
				var before := boss.phase_controller.state
				boss.advance_simulation(STEP, Vector2(1440, 1260))
				if before == FoldlightBossPhaseController.State.TELEGRAPH and boss.phase_controller.state == FoldlightBossPhaseController.State.RECOVERY:
					row["min_recovery"] = minf(float(row["min_recovery"]), float(boss.phase_controller.get_state_snapshot()["remaining"]))
			row["shots_per_second"] = snappedf(float(row["shots"]) / SECONDS, 0.01)
			row["return_multiplier"] = definition.return_damage_outside_stagger
			row["return_window"] = definition.return_window_seconds
			rows.append(row)
			boss.queue_free()
			await process_frame
	var filename := "boss-pressure.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			filename = argument.trim_prefix("--output=").get_file()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/difficulty-checks"))
	var file := FileAccess.open("res://build/difficulty-checks/" + filename, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print(JSON.stringify(rows))
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	quit()
