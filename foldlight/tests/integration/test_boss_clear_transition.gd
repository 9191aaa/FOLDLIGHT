extends SceneTree

## Production scenes, actual lethal projectile collisions and viewport input.
## Only the reading clock is stepped explicitly to keep this regression short.
var _failures: Array[String] = []
var _checkpoints: Array[Dictionary] = []
var _finished: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	session.run_controller.checkpoint_ready.connect(func(snapshot: Dictionary) -> void: _checkpoints.append(snapshot.duplicate(true)))
	session.run_controller.run_finished.connect(func(result: Dictionary) -> void: _finished.append(result.duplicate(true)))
	var first_clear: Dictionary = {}
	for input_kind in ["space", "enter", "gamepad", "mouse"]:
		var boss := _enter_boss(session, 0)
		if boss == null:
			_check(false, "real first boss spawns for %s input" % input_kind)
			continue
		var before_region := session.run_controller.run_state.current_region
		_send(input_kind, true)
		var health := session.player.health
		_defeat_with_projectile(session, boss)
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session.run_controller.run_state.current_region == before_region, "%s lethal hit does not synchronously advance the region" % input_kind)
		_check(session.presentation.screen_kind == &"hud" and session.world.visible and session.player.visible and session.presentation._boss_bar.visible and session.presentation._boss_bar.value == 0.0, "%s victory retains the arena, player and zero-health Boss HUD" % input_kind)
		_check(not session.world.combat_runtime.active and not session.player.play_enabled and session.world.combat_runtime.projectiles.is_empty(), "%s victory clears threats and prevents same-hit echoes" % input_kind)
		_check(not session.player.take_hit() and session.player.health == health, "%s old hostile projectiles and direct damage cannot hurt during victory" % input_kind)
		var elapsed := session.run_controller.run_state.elapsed
		var position_before := session.player.global_position
		var rooms := session.run_controller.run_state.room_count
		var glimmer := session.run_controller.run_state.glimmer
		session._pause_game()
		_check(not session.is_paused() and session.presentation.screen_kind == &"hud", "%s pause cannot replace the pending victory or reactivate combat" % input_kind)
		_advance_read(session, 20)
		session._boss_clear_banner._continue_button.pressed.emit()
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session._boss_clear_banner._continue_button.disabled, "%s quick confirm cannot skip the 2.2-second aftermath" % input_kind)
		_advance_read(session, 5)
		_check(session._boss_clear_banner._continue_button.disabled, "%s held before defeat remains blocked after the reading time" % input_kind)
		_check(is_equal_approx(session.run_controller.run_state.elapsed, elapsed) and session.player.global_position == position_before, "%s aftermath advances visuals without advancing run time or movement" % input_kind)
		_check(session.world.combat_runtime._active_flashes.is_empty(), "%s defeat ripple finishes while combat stays suspended" % input_kind)
		_check(session.run_controller.run_state.room_count == rooms and session.run_controller.run_state.glimmer == glimmer, "%s waiting does not repeat clear rewards" % input_kind)
		await process_frame
		_check(session.world.room_runtime.projectile_container.get_child_count() == 0, "%s all transient hazards are removed from the real scene" % input_kind)
		var point: Vector2 = session._boss_clear_banner._continue_button.get_global_rect().get_center()
		_send(input_kind, false, point)
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR, "%s releasing the old input does not continue" % input_kind)
		_advance_read(session, 2)
		_check(session._boss_clear_banner.can_continue(), "%s neutral input enables a fresh continuation" % input_kind)
		if first_clear.is_empty():
			first_clear = _checkpoints.back().duplicate(true)
		_send(input_kind, true, point)
		_send(input_kind, false, point)
		await process_frame
		_check(session.run_controller.run_state.current_region == 1 and session.run_controller.phase == FoldlightRogueRunController.Phase.COMBAT and session.player.visible and session.player.play_enabled, "%s fresh input opens exactly the next playable region" % input_kind)
		_check(not session._boss_clear_banner.visible and not session.player.folding, "%s confirmation does not leak into another screen or a new fold" % input_kind)

	_check(StringName(first_clear.get("session_phase", &"")) == &"boss_clear", "checkpoint records a cleared Boss awaiting explicit continuation")
	session.enter_title()
	_check(profile.commit_roguelite_checkpoint(first_clear, false), "Boss aftermath checkpoint passes the real profile boundary")
	session.continue_run()
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session.world.visible and session.player.visible and session.world.combat_runtime.enemies.is_empty(), "resuming a cleared Boss reconstructs a safe visible arena without replaying combat")
	_check(session.run_controller.run_state.room_count == int(first_clear.get("room_count", -1)) and session.run_controller.run_state.glimmer == int(first_clear.get("glimmer", -1)), "resuming does not award a duplicate room or glimmer")
	_check(not session._boss_clear_banner.can_continue(), "resuming reapplies the reading and input-release guard")
	_advance_read(session, 24)
	session._boss_clear_banner._confirm()
	_check(session.run_controller.run_state.current_region == 1 and session.player.play_enabled, "a restored ordinary Boss can continue to the next region")

	var archivist := _enter_boss(session, 1)
	if archivist != null:
		_defeat_with_projectile(session, archivist)
		await process_frame
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session.world.combat_runtime.enemies.is_empty(), "the archivist's deferred opening support cannot spawn after its victory")
		_check(session.world.combat_runtime.spawn_hostile_volley({"origin": session.player.global_position}) == 0, "late boss volleys cannot repopulate the cleared arena")

	var final_boss := _enter_boss(session, 2)
	if final_boss != null:
		_defeat_with_projectile(session, final_boss)
		_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN and _finished.is_empty() and session.world.visible, "the final Boss also keeps the victory on the battlefield before settlement")
		var final_clear: Dictionary = _checkpoints.back().duplicate(true)
		session.enter_title()
		profile.commit_roguelite_checkpoint(final_clear, false)
		session.continue_run()
		_check(session.run_controller.phase == FoldlightRogueRunController.Phase.BOSS_CLEAR and session.run_controller.run_state.current_region == 2 and session.world.combat_runtime.enemies.is_empty(), "a final-Boss aftermath checkpoint never respawns the Boss or skips the victory")
		var wins := int(profile.get_roguelite_snapshot().get("victories", 0))
		session.persist_profile = true
		_advance_read(session, 24)
		_send("enter", true)
		_send("enter", false)
		await process_frame
		_check(session.mode == FoldlightRogueSessionController.SessionMode.RESULT and session.presentation.screen_kind == &"result" and _finished.size() == 1 and bool(_finished[0].get("won", false)), "fresh confirmation opens the final result once")
		session._boss_clear_banner._confirm()
		_check(not session.run_controller.continue_after_boss() and int(profile.get_roguelite_snapshot().get("victories", 0)) == wins + 1, "duplicate confirmation cannot double-commit a victory")
		_check((profile.get_roguelite_snapshot().get("active_run", {}) as Dictionary).is_empty(), "final result clears the pending checkpoint only after confirmation")
	game.queue_free()
	await process_frame
	await _test_endless_unchanged()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_CLEAR_TRANSITION: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _enter_boss(session: FoldlightRogueSessionController, region: int) -> FoldlightRogueBossActor:
	session.persist_profile = false
	session.start_new_run()
	var controller := session.run_controller
	controller.run_state.current_region = region
	for node: Dictionary in controller.get_current_region_snapshot().get("nodes", []):
		if StringName(node.get("category", &"")) == &"boss":
			controller.run_state.current_node_id = StringName(node["id"])
			break
	controller.phase = FoldlightRogueRunController.Phase.ENTERING_ROOM
	controller._request_current_room()
	session.world.combat_runtime.set_physics_process(false)
	session.world.room_runtime.advance_encounter(2.0)
	for enemy in session.world.combat_runtime.enemies:
		if enemy is FoldlightRogueBossActor:
			return enemy as FoldlightRogueBossActor
	return null


func _defeat_with_projectile(session: FoldlightRogueSessionController, boss: FoldlightRogueBossActor) -> void:
	var combat := session.world.combat_runtime
	var shot := combat._spawn_projectile({"origin": boss.global_position, "velocity": Vector2.RIGHT * 800.0, "hostile": false, "damage": 1000000.0, "echo_chance": 0.75})
	# Force the echo branch to expose any combat tail running after defeat.
	shot.echo_chance = 1.0
	shot.set_meta("terrain_grace", 1.0)
	combat._spawn_projectile({"origin": session.player.global_position, "velocity": Vector2.ZERO, "hostile": true, "damage": 1.0})
	combat._on_zone_requested({"origin": session.player.global_position, "radius": 200.0, "duration": 5.0})
	combat._on_boss_telegraph_requested({"origin": boss.global_position, "duration": 2.0})
	session.player.invulnerability = 0.0
	combat._update_projectiles(0.001)


func _advance_read(session: FoldlightRogueSessionController, steps: int) -> void:
	for step in steps:
		session._boss_clear_banner._input_guard._process(0.10)
		session._process(0.10)


func _test_endless_unchanged() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	var actors := slice.combat_runtime.spawn_directed_wave([{"boss_id": &"reef_crown_battery", "spawn_position": slice.player.global_position + Vector2(0, -350)}])
	var before := float(slice.controller.evolution.get_enemy_snapshot().get("survival_seconds", 0.0))
	(actors[0] as FoldlightRogueBossActor).take_damage(1000000.0)
	slice._physics_process(0.2)
	var after := float(slice.controller.evolution.get_enemy_snapshot().get("survival_seconds", 0.0))
	_check(slice.combat_runtime.active and slice.player.play_enabled and slice._modal_kind.is_empty() and after > before, "endless Boss defeat keeps its own live survival flow and effective time")
	slice.queue_free()
	await process_frame


func _send(kind: String, pressed: bool, point: Vector2 = Vector2(960, 650)) -> void:
	var event: InputEvent
	if kind == "mouse":
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = pressed
		event = mouse
	elif kind == "gamepad":
		var joy := InputEventJoypadButton.new()
		joy.button_index = JOY_BUTTON_A
		joy.device = 0
		joy.pressed = pressed
		event = joy
	else:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER if kind == "enter" else KEY_SPACE
		key.physical_keycode = key.keycode
		key.pressed = pressed
		event = key
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
