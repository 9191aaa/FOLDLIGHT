extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_test_director_rules()
	await _test_real_fold_release()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_ENDLESS_RETURN_CAPTURE_3_14: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_director_rules() -> void:
	var config := load("res://resources/endless/endless_survival_default.tres") as FoldlightEndlessSurvivalConfig
	var map := load("res://resources/endless/maps/folded_delta.tres") as FoldlightEndlessMapDefinition
	var director := FoldlightEndlessObjectiveDirector.new()
	director.reset(config, map, 0)
	var objective := director.get_snapshot()
	var task_id := StringName(objective["id"])
	var point := Vector2(objective["target_position"])
	var outside := point + Vector2(171.0, 0.0)
	_check(is_equal_approx(float(objective["required"]), 12.0), "capture keeps its twelve-second baseline")
	_check(not director.report_returned_light(0, point, task_id, 1) and not director.report_returned_light(-1, point, task_id, 1), "empty or negative releases cannot charge the lighthouse")
	_check(not director.report_returned_light(4, point, &"old_task", 1) and not director.report_returned_light(4, point, task_id, 0), "unrelated task IDs and absent release identity are rejected")
	_check(not director.report_returned_light(4, Vector2(NAN, 0.0), task_id, 1), "nonfinite release positions cannot count as inside")
	_check(not director.report_returned_light(4, outside, task_id, 1), "release outside the capture circle grants no progress")
	_check(not director.report_returned_light(4, point, task_id, 1), "an outside release cannot be replayed after entering the circle")
	director.advance(3.0, point)
	_check(bool(director.get_snapshot()["occupied"]) and Vector2(director.get_snapshot()["player_position"]) == point, "facility snapshot reports actual occupancy and player position")
	_check(director.report_returned_light(3, point, task_id, 2), "three real returned lights accumulate without an early boost")
	_check(is_equal_approx(float(director.get_snapshot()["progress"]), 3.0) and int(director.get_snapshot()["return_charge_count"]) == 3, "partial charge never awards fractional bonus time")
	_check(director.report_returned_light(1, point, task_id, 3), "the fourth returned light completes one charge group")
	_check(is_equal_approx(float(director.get_snapshot()["progress"]), 5.0) and is_equal_approx(float(director.get_snapshot()["return_boost_seconds"]), 2.0), "four returned lights add exactly two seconds of capture progress")
	_check(not director.report_returned_light(8, point, task_id, 3) and not director.report_returned_light(8, point, task_id, 2), "duplicate and out-of-order release identities grant no extra time")
	director.advance(1.0, outside)
	_check(not bool(director.get_snapshot()["occupied"]) and is_equal_approx(float(director.get_snapshot()["progress"]), 4.65), "leaving the circle preserves the original 0.35 progress-per-second decay")
	_check(director.report_returned_light(1000, point, task_id, 4), "a large release is bounded by the remaining per-task charge budget")
	var capped := director.get_snapshot()
	_check(int(capped["return_charge_count"]) == 12 and is_equal_approx(float(capped["return_boost_seconds"]), 6.0) and is_equal_approx(float(capped["progress"]), 8.65), "return bonus caps at twelve lights and six seconds per task")
	_check(not director.report_returned_light(4, point, task_id, 5), "further return releases cannot bypass the capture hold requirement")
	director.advance(3.36, point)
	_check(bool(director.get_snapshot()["completed"]) and not director.report_returned_light(4, point, task_id, 6), "completed lighthouse cannot award another boost or completion")
	var terminal := director.get_snapshot()
	_check(terminal["id"] == task_id and Vector2(terminal["target_position"]) == point and is_equal_approx(float(terminal["return_boost_seconds"]), 6.0), "completion retains stable facility identity and progress for its final animation")
	director.reset(config, map, 0)
	var fresh := director.get_snapshot()
	_check(not director.report_returned_light(4, fresh["target_position"], task_id, 100), "the previous run's release cannot charge a new task at the same site")
	_check(int(fresh["return_charge_count"]) == 0 and is_zero_approx(float(fresh["return_boost_seconds"])), "restarting clears all charge and boost state")
	var short_config := config.duplicate() as FoldlightEndlessSurvivalConfig
	short_config.objective_time_limit = 0.25
	director.reset(short_config, map, 0)
	var expiring := director.get_snapshot()
	director.advance(0.26, Vector2(expiring["target_position"]) + Vector2(500, 0))
	_check(bool(director.get_snapshot()["failed"]) and not director.report_returned_light(12, expiring["target_position"], expiring["id"], 1), "late return release cannot rescue an expired capture task")
	director.reset(config, map, 1)
	var captain := director.get_snapshot()
	_check(not director.report_returned_light(12, captain["target_position"], captain["id"], 1), "return charging does not complete unrelated task kinds")
	director.free()


func _test_real_fold_release() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.start_slice(314100)
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.combat_runtime.clear_combat()
	var task := slice.controller.objectives.get_snapshot()
	var point := Vector2(task["target_position"])
	var profile_before := var_to_str(slice.profile_manager.get_public_snapshot())
	var sounds: Array[StringName] = []
	slice.audio_director.sfx_requested.connect(func(id: StringName, _pitch: float, _volume: float) -> void: sounds.append(id))
	slice.player.global_position = point + Vector2(250, 0)
	_check(slice.player.try_begin_fold(), "player can begin collecting light outside the capture point")
	for _index in 8:
		_check(slice.player.capture_one(), "shared Fold stores one genuine captured-light unit")
	slice.player.global_position = point
	slice.player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	_check(slice.player.release_fold_action(), "the real shared release action emits returned light inside the circle")
	var after := slice.controller.objectives.get_snapshot()
	_check(int(after["return_charge_count"]) == 8 and is_equal_approx(float(after["return_boost_seconds"]), 4.0), "outside collection followed by inside release contributes eight real light units")
	_check(slice.combat_runtime.projectiles.size() == 8 and bool(slice.player.weapon_mount.get_resonance_snapshot()["active"]), "objective charging preserves all returned projectiles and the existing eight-light resonance")
	_check(sounds.has(&"fold") and sounds.has(&"release"), "Fold and release keep their established sound feedback")
	slice._on_feedback_fold_released(8, 1.0)
	_check(int(slice.controller.objectives.get_snapshot()["return_charge_count"]) == 8, "repeated feedback callback cannot reuse a consumed release serial")
	slice._pause_game()
	var frozen := slice.controller.objectives.get_snapshot()
	slice.player.fold_released.emit(4, 1.0)
	slice._physics_process(2.0)
	_check(slice.controller.objectives.get_snapshot() == frozen, "paused or synthetic release events cannot progress the capture task")
	slice._resume_game()
	slice.player.fold_component.reset()
	_check(slice.player.try_begin_fold(), "Fold can begin again after pause")
	for _index in 4:
		slice.player.capture_one()
	slice.controller.objectives.reset(slice.controller.config, slice.controller.map_definition, 0)
	var new_task := slice.controller.objectives.get_snapshot()
	slice.player.global_position = new_task["target_position"]
	slice.player.release_fold_action()
	_check(int(slice.controller.objectives.get_snapshot()["return_charge_count"]) == 0, "release begun under an old objective cannot charge its replacement")
	_check(var_to_str(slice.profile_manager.get_public_snapshot()) == profile_before, "capture charging never changes permanent profile progression")
	slice.start_slice(314100)
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.combat_runtime.clear_combat()
	point = Vector2(slice.controller.objectives.get_snapshot()["target_position"])
	slice.player.global_position = point
	slice.controller.objectives.advance(8.0, point)
	_check(slice.player.try_begin_fold(), "finishing release begins through the real shared Fold component")
	for _index in 8:
		slice.player.capture_one()
	slice.player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	slice.player.release_fold_action()
	_check(bool(slice.controller.objectives.get_snapshot()["completed"]) and slice._modal_kind == &"objective_complete" and not slice.combat_runtime.active, "return boost can finish the capture and synchronously enter its safe completion beat")
	_check(slice.combat_runtime.projectiles.size() == 8 and bool(slice.player.weapon_mount.get_resonance_snapshot()["active"]), "the exact release that completes capture still spawns every returned light and grants resonance")
	slice.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		_failures.append(label)
