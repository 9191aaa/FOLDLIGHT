extends SceneTree

## Reward/route screens are modal safety states: the run remains visible, but
## combat, encounter time, controls, and damage stay frozen until the next room.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "release scene loads for reward-modal safety regression")
	if game == null:
		_finish()
		return
	root.add_child(game)
	await process_frame
	await process_frame

	var session := game.rogue_session as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	await process_frame
	var runtime := session.world.combat_runtime as FoldlightRogueCombatRuntime
	_check(runtime.active and session.player.play_enabled, "new room begins with live combat and player control")

	var projectile := runtime._spawn_projectile({
		"origin": session.player.global_position + Vector2(180.0, 0.0),
		"velocity": Vector2(-360.0, 0.0),
		"hostile": true,
		"reflectable": true,
		"lifetime": 4.0,
	})
	var projectile_position := projectile.global_position
	var health_before := session.player.health
	session._on_encounter_cleared({"duration": 30.0})
	await process_frame

	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD, "room clear enters the reward phase")
	_check(session.presentation.screen_kind == &"reward", "three-choice reward screen is visible")
	_check(not runtime.active and not session.player.play_enabled, "reward screen freezes combat and player control")
	runtime._physics_process(0.5)
	_check(projectile.global_position.is_equal_approx(projectile_position), "hostile projectiles cannot advance behind reward cards")
	_check(session.player.health == health_before and not session.player.take_hit(), "player cannot lose health while choosing a reward")

	var reward_button: Button = null
	for candidate: Button in session.presentation._reward_buttons:
		if candidate.visible:
			reward_button = candidate
			break
	_check(reward_button != null, "reward screen exposes a selectable upgrade")
	if reward_button != null:
		session._on_reward_chosen(StringName(reward_button.get_meta("upgrade_id", &"")))
	await process_frame
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE, "reward selection enters route choice")
	_check(not runtime.active and not session.player.play_enabled, "route choice remains a frozen safety state")

	var exits: Array[String] = []
	for exit_variant: Variant in session.current_room_node.get("exits", []):
		exits.append(String(exit_variant))
	if not exits.is_empty():
		session._on_route_chosen(StringName(exits[0]))
	await process_frame
	_check(runtime.active and session.player.play_enabled, "combat resumes only after the chosen next room is loaded")

	game.queue_free()
	await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_REWARD_MODAL_SAFETY_3_4_3: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REWARD_MODAL_SAFETY_3_4_3: FAIL - %s" % ", ".join(_failures))
		quit(1)
