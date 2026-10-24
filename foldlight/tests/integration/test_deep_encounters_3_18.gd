extends SceneTree

class RecordingBridge extends "res://scripts/autoloads/web_race_bridge.gd":
	func _read_browser_boot() -> Dictionary: return {}
	func _read_page_state() -> Dictionary: return {"phase": "waiting", "mayStart": false}
	func _send_browser(_method: StringName, _payload: Dictionary) -> void: pass

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	_test_schedule()
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	slice.set_process(false)
	slice.set_physics_process(false)
	_test_inversion_field(slice)
	_test_inversion_runtime(slice)
	await _test_six_boss_mobile_hud(slice)
	slice.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_DEEP_ENCOUNTERS_3_18: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_schedule() -> void:
	var director := FoldlightEndlessBossDirector.new()
	director.reset(318)
	_check(director.advance(0.1, 7, 500.0).state == &"waiting", "first boss still requires level eight")
	_check(director.advance(0.1, 8, 500.0).warning_count == 1, "level eight teaches exactly one boss")
	for step in 30:
		director.advance(0.1, 8, 503.0)
	_check(director.confirm_spawned([&"first"]) and director.report_defeated(&"first", 503.0), "first encounter clears through an actual acknowledged identity")
	_check(director.advance(0.1, 50, 508.9).state == &"waiting" and is_equal_approx(director.recovery_interval(), 6.0), "deep progression retains six seconds of recovery")
	_check(director.advance(0.1, 50, 509.0).warning_count == 2, "earning many levels cannot skip from the first directly to six bosses")
	var encounter_time := 509.0
	for wave in range(2, 8):
		if wave > 2:
			_check(director.advance(0.1, 50, encounter_time + 11.9).state == &"waiting", "timed encounter waits until its full minimum interval")
			encounter_time += 12.0
			director.advance(0.1, 50, encounter_time)
		var planned := director.planned_boss_ids()
		var unique: Dictionary = {}
		for identity in planned:
			unique[identity] = true
		_check(planned.size() == mini(6, wave) and unique.size() == planned.size(), "wave %d contains unique independent boss definitions up to the six-boss cap" % wave)
		_check(is_equal_approx(director.encounter_interval(), 12.0) and director.intensity_tier() == 5, "deep encounters expose the capped interval and fifth attack-intensity tier")
		for step in 30:
			director.advance(0.1, 50, encounter_time)
		var ids: Array[StringName] = []
		for index in planned.size():
			ids.append(StringName("wave_%d_actor_%d" % [wave, index]))
		_check(director.confirm_spawned(ids), "all reserved identities acknowledge the same encounter")
		var completed := 0
		for identity in ids:
			completed += 1 if director.report_defeated(identity, encounter_time) else 0
		_check(completed == 1 and not director.report_defeated(ids.back(), encounter_time), "only the final unique boss death awards one wave completion")
	director.reset(318)
	_check(director.get_snapshot().wave_index == 0 and director.intensity_tier() == 0, "restart clears deep scheduling and intensity")


func _test_inversion_field(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(3)
	var field := slice._inversion
	var point := slice.player.global_position
	field.advance(0.1, 719.0, 17, point, PackedVector2Array())
	_check(field.get_snapshot().state == &"rest", "inversion is absent below both late-run unlock thresholds")
	field.advance(0.1, 719.0, 18, point, PackedVector2Array())
	var snapshot := field.get_snapshot()
	_check(snapshot.state == &"warning" and is_equal_approx(snapshot.remaining, 3.0) and not snapshot.inside, "level eighteen starts three seconds of visible warning without reversing input")
	var center := Vector2(snapshot.position)
	field.advance(30.0, 720.0, 18, point + Vector2(900.0, 0.0), PackedVector2Array())
	_check(is_equal_approx(field.get_snapshot().remaining, 2.9) and Vector2(field.get_snapshot().position) == center, "a long frame cannot skip warning and the announced field never chases movement")
	for step in 29:
		field.advance(0.1, 720.0, 18, center, PackedVector2Array())
	_check(field.get_snapshot().state == &"active" and field.get_snapshot().inside and is_equal_approx(field.get_snapshot().remaining, 14.0), "warning becomes a fourteen-second stationary control field")
	_check(not field.advance(0.1, 720.0, 18, center + Vector2(FoldlightEndlessInversionField.RADIUS + 1.0, 0), PackedVector2Array()), "leaving the actual circle immediately restores normal controls")
	for step in 139:
		field.advance(0.1, 734.0, 18, center, PackedVector2Array())
	_check(field.get_snapshot().state == &"rest" and not field.get_snapshot().inside, "active inversion expires after fourteen visible seconds")
	field.configure(slice.controller.map_definition, slice.controller.map_runtime, 318)
	field.advance(0.1, 720.0, 1, point, PackedVector2Array())
	_check(field.get_snapshot().state == &"warning", "twelve minutes also unlock inversion independently of combat level")
	field.configure(slice.controller.map_definition, slice.controller.map_runtime, 318)
	field.advance(0.1, 720.0, 18, point, PackedVector2Array([point]))
	snapshot = field.get_snapshot()
	_check(snapshot.state == &"rest" or Vector2(snapshot.position).distance_to(point) >= FoldlightEndlessInversionField.RADIUS + 300.0, "protected task facilities and escort points outrank inversion placement")
	field.cancel()
	_check(field.get_snapshot().state == &"rest" and not field.get_snapshot().inside, "cancellation clears warning, active state and occupancy")


func _prepare_runtime_inversion(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.debug_invincible = true
	slice.controller.evolution.experience_level = 18
	slice.controller.objectives.rotation_index = 5
	slice.controller.objectives._task_serial = 0
	slice.controller.objectives._start_current_objective()
	slice._advance_encounters(0.1)


func _test_inversion_runtime(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(3)
	_prepare_runtime_inversion(slice)
	_check(slice._inversion.get_snapshot().state == &"warning", "real solo runtime installs the field at the same combat unlock")
	var remaining := float(slice._inversion.get_snapshot().remaining)
	slice._pause_game()
	slice._advance_encounters(1.0)
	_check(float(slice._inversion.get_snapshot().remaining) == remaining, "a real solo pause freezes inversion warning")
	slice._resume_game()
	slice._application_suspended = true
	slice._advance_encounters(1.0)
	_check(float(slice._inversion.get_snapshot().remaining) == remaining, "solo application suspension also freezes inversion")
	slice._application_suspended = false
	var touch := slice._touch_controls
	var old_host: Dictionary = {}
	for key in ["_host_suspended", "_host_layout", "_host_cancel_epoch", "_touch_mode", "_safe_insets"]:
		old_host[key] = touch.get(key)
	touch.apply_host_state({"suspended": true, "cancelEpoch": int(old_host._host_cancel_epoch) + 1})
	slice._advance_encounters(1.0)
	_check(float(slice._inversion.get_snapshot().remaining) == remaining, "solo rotate overlay does not consume the visible warning")
	for key in old_host:
		touch.set(key, old_host[key])
	touch._refresh_active()
	for step in 30:
		slice._advance_encounters(0.1)
	_check(slice.player.is_horizontal_input_reversed(), "the actual runtime switches the player's horizontal transform when its warning finishes")
	slice.player.global_position = Vector2(slice._inversion.get_snapshot().position) + Vector2(400.0, 0.0)
	slice._advance_encounters(0.1)
	_check(not slice.player.is_horizontal_input_reversed(), "actual movement outside the live field clears the input transform")
	slice._clear_pending_spawns()
	_check(slice._inversion.get_snapshot().state == &"rest" and not slice.player.is_horizontal_input_reversed(), "the shared exit cleanup resets the active field and player state")
	var bridge := RecordingBridge.new()
	root.add_child(bridge)
	bridge.configure_session({"roomId": "deep318", "matchId": "deep318", "playerId": "test", "instanceId": "deep318-test", "seed": 3, "rulesVersion": "endless_race_v11"})
	bridge.set_process(false)
	slice.prepare_web_race(bridge)
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	_prepare_runtime_inversion(slice)
	remaining = float(slice._inversion.get_snapshot().remaining)
	touch.apply_host_state({"suspended": true, "cancelEpoch": int(touch._host_cancel_epoch) + 1})
	slice._application_suspended = true
	var before_time := slice.controller.evolution.survival_seconds
	slice._physics_process(0.1)
	slice._advance_encounters(0.1)
	_check(float(slice._inversion.get_snapshot().remaining) < remaining and slice.controller.evolution.survival_seconds > before_time, "an admitted race keeps score and inversion advancing together behind a rotate or focus overlay")
	for key in old_host:
		touch.set(key, old_host[key])
	touch._refresh_active()
	slice._application_suspended = false
	slice._web_race_bridge = null
	bridge.queue_free()
	slice._clear_pending_spawns()


func _test_six_boss_mobile_hud(slice: FoldlightEndlessSliceRuntime) -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var touch := root.get_node("TouchControls")
	var previous_insets: Vector4 = touch._safe_insets
	var previous_mode: bool = touch._touch_mode
	touch._safe_insets = Vector4(80, 160, 56, 24)
	touch._set_touch_mode(true)
	var ui := slice.presentation
	var bosses: Array[Dictionary] = []
	for index in 6:
		bosses.append({"title": "首领%d" % (index + 1), "health": 100.0 + index * 10, "maximum_health": 800.0 + index * 100})
	var context := {"endless_navigation": true, "experience": {"level": 50, "xp_in_level": 1, "xp_to_next": 1000}, "boss_director": {"state": &"active", "capacity": 6, "active_count": 6, "difficulty_tier": 24, "next_level": 52}, "bosses": bosses}
	ui.show_hud()
	for resolution in [Vector2i(844, 390), Vector2i(360, 780)]:
		root.size = resolution
		ui.update_hud(slice.player, {}, {}, "无尽挑战", "", {}, context)
		for frame in 4:
			await process_frame
		var rail: Control = ui._endless_boss_status
		var snapshot: Dictionary = rail.get_display_snapshot()
		var rect := rail.get_global_rect()
		_check(snapshot.rows == 6 and snapshot.columns == 2 and snapshot.grid_rows == 3 and snapshot.health_values.size() == 6, "six independent mobile boss health bars use two columns and three rows")
		_check(Rect2(80, 160, 1784, 896).encloses(rect), "the six-boss rail stays inside landscape and portrait safe bounds")
		var layout: Dictionary = touch.get_layout_snapshot()
		for key in ["move", "fold", "dash", "active"]:
			var center := Vector2(layout[key])
			var radius := float(layout[key + "_radius"])
			_check(not rect.intersects(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2)), "six-boss HUD clears mobile %s controls" % key)
		for blocked in [ui._mobile_hud.arsenal.get_global_rect(), ui._mobile_hud.experience.get_global_rect(), ui._mobile_hud.pause_button.get_global_rect()]:
			_check(not rect.intersects(blocked), "six-boss rail does not cover the shared arsenal, growth or pause UI")
	touch._safe_insets = previous_insets
	touch._set_touch_mode(previous_mode)


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition:
		failures.append(label)
