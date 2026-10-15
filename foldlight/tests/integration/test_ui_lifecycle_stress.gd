extends SceneTree

## Exercise actual viewport key dispatch and SceneTree replacement while the
## shared menus have queued focus and card tweens. Combat outcomes are fixtures;
## transitions, reward protection and confirmation run through production UI.
var failures: Array[String] = []
var run_starts: int = 0
var reward_claims: int = 0
var observed_rewards: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.profile["roguelite"]["prologue_complete"] = true
	await _test_rapid_menus_and_restarts()
	await _test_reward_changes_and_scene_exit()
	await _test_detached_ui_callbacks()
	print("FOLDLIGHT_UI_LIFECYCLE_STRESS: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_rapid_menus_and_restarts() -> void:
	var slice := await _open_endless()
	if slice == null:
		return
	slice.controller.run_started.connect(func(_data: Dictionary) -> void: run_starts += 1)
	var ui := slice.presentation
	for cycle in 12:
		slice._finish_run()
		await _result_ready(ui)
		_key(KEY_ENTER)
		_key(KEY_E)
		_key(KEY_SPACE)
		_freeze_fixture(slice)
		_check(run_starts == cycle + 1 and slice.controller.active and not slice.run_ended and ui.screen_kind == &"hud", "rapid Enter/E/Space starts exactly one new run, cycle %d" % cycle)
		_key(KEY_ESCAPE)
		await _frames(3)
		_key(KEY_S)
		_key(KEY_E)
		_key(KEY_ESCAPE)
		_key(KEY_SPACE)
		await _frames(3)
		_check(ui.screen_kind == &"pause" and slice._modal_kind == &"pause" and not slice.player.play_enabled, "same-frame settings/back/confirm cannot activate the old setting or bypass deferred focus, cycle %d" % cycle)
		_key(KEY_SPACE)
		_check(ui.screen_kind == &"hud" and slice.player.play_enabled and slice._modal_kind.is_empty(), "fresh confirmation resumes the same run, cycle %d" % cycle)
		_check(slice.world.room_runtime.get_terrain_pieces().size() == slice.controller.map_definition.walls.size(), "repeated restart retains one terrain set, cycle %d" % cycle)
	# Native key auto-repeat must not continuously enter/leave menus.
	_key(KEY_ESCAPE)
	await _frames(3)
	for index in 30:
		_key(KEY_ESCAPE, true)
	_check(ui.screen_kind == &"pause", "held Escape echo does not cycle pause and resume")
	_key(KEY_ESCAPE)
	_check(ui.screen_kind == &"hud", "fresh Escape still resumes after rejected echoes")


func _test_reward_changes_and_scene_exit() -> void:
	var slice := current_scene as FoldlightEndlessSliceRuntime
	if slice == null:
		_check(false, "endless survives all rapid menu cycles")
		return
	slice.controller.mission_reward_claimed.connect(func(_data: Dictionary) -> void: reward_claims += 1)
	var ui := slice.presentation
	slice.controller._on_objective_completed({"completion_count": 1, "title": "生命周期检查"})
	await _reward_ready(ui)
	_key(KEY_ENTER)
	_check(bool(ui._reward_buttons[0].get_presentation_snapshot()["confirming"]), "real Enter begins reward confirmation")
	slice._finish_run()
	await create_timer(0.32).timeout
	_check(reward_claims == 0 and slice.run_ended and ui.screen_kind == &"result" and not slice.combat_runtime.active, "ending the run during confirmation cancels reward grant and cannot resume combat")
	await _result_ready(ui)
	_key(KEY_E)
	_freeze_fixture(slice)
	_check(not slice.run_ended and ui.screen_kind == &"hud", "fresh result retry works after canceled reward confirmation")
	slice.controller._on_objective_completed({"completion_count": 1, "title": "离场检查"})
	await _reward_ready(ui)
	_key(KEY_SPACE)
	var old_scene: WeakRef = weakref(slice)
	var old_ui: WeakRef = weakref(ui)
	slice._return_to_title()
	slice._return_to_title()
	for key: Key in [KEY_ENTER, KEY_E, KEY_ESCAPE, KEY_SPACE]:
		_key(key)
	await _frames(5)
	await create_timer(0.32).timeout
	_check(current_scene is FoldlightGame and old_scene.get_ref() == null and old_ui.get_ref() == null, "exit during card confirmation frees the old UI once despite repeated return and keyboard input")
	_check(reward_claims == 0, "a freed card's pending tween cannot grant a late reward")
	var main := current_scene as FoldlightGame
	_check(main.rogue_session.presentation.screen_kind == &"title", "keys sent while the old scene detached cannot confirm the replacement title")
	# Repeated actual scene changes also exercise detached deferred focus calls.
	for cycle in 5:
		slice = await _open_endless()
		if slice == null:
			return
		slice._finish_run()
		await _result_ready(slice.presentation)
		old_scene = weakref(slice)
		_key(KEY_ESCAPE)
		_key(KEY_ENTER)
		_key(KEY_E)
		await _frames(5)
		_check(current_scene is FoldlightGame and old_scene.get_ref() == null, "result Escape plus immediate confirms leaves one clean title, cycle %d" % cycle)


func _test_detached_ui_callbacks() -> void:
	var ui := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	ui.reward_chosen.connect(func(_id: StringName) -> void: observed_rewards += 1)
	var choices: Array[Dictionary] = [{"content_id": &"steady_lantern", "title": "定灯", "description": "生命周期检查"}]
	ui.show_reward(choices, "换屏检查")
	await _reward_ready(ui)
	_key(KEY_ENTER)
	ui.show_settings((root.get_node("ProfileManager") as FoldlightProfileManager).settings, &"pause")
	ui.show_pause()
	ui.show_hud()
	await create_timer(0.32).timeout
	_check(observed_rewards == 0 and ui.screen_kind == &"hud", "replacing a confirming reward with several screens cancels its tween and stale focus")
	ui.show_reward(choices, "释放检查")
	await _reward_ready(ui)
	_key(KEY_E)
	var old_ui: WeakRef = weakref(ui)
	ui.queue_free()
	await _frames(3)
	await create_timer(0.32).timeout
	_check(old_ui.get_ref() == null and observed_rewards == 0, "freeing presentation during confirmation safely kills node-bound tweens")


func _open_endless() -> FoldlightEndlessSliceRuntime:
	_check(change_scene_to_file("res://scenes/endless/endless_survival_slice.tscn") == OK, "endless loads as the real current scene")
	await _frames(5)
	var slice := current_scene as FoldlightEndlessSliceRuntime
	_check(slice != null and slice.controller.active, "deferred startup creates a live endless run")
	if slice != null:
		_freeze_fixture(slice)
	return slice


func _freeze_fixture(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.player.set_debug_invincible(true)


func _reward_ready(ui: FoldlightRoguePresentation) -> void:
	var deadline := Time.get_ticks_msec() + 3500
	while Time.get_ticks_msec() < deadline:
		if not ui._reward_buttons[0].disabled and root.gui_get_focus_owner() == ui._reward_buttons[0]:
			return
		await process_frame
	_check(false, "reward protection reaches neutral input and valid focus before the deadline")


func _result_ready(ui: FoldlightRoguePresentation) -> void:
	var deadline := Time.get_ticks_msec() + 3500
	while Time.get_ticks_msec() < deadline:
		if ui.is_result_ready() and root.gui_get_focus_owner() == ui._focus_groups[&"result"][0]:
			return
		await process_frame
	_check(false, "result protection reaches neutral input and valid focus before the deadline")


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _key(code: Key, echo: bool = false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		event.echo = echo and down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _check(ok: bool, description: String) -> void:
	if ok:
		print("[PASS] " + description)
	else:
		failures.append(description)
		push_error("[FAIL] " + description)
