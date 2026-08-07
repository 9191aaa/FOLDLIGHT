extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate() as FoldlightGame if packed != null else null
	_check(game != null, "release scene loads for the second-room reward contract")
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

	session.run_controller.run_state.room_count = 2
	session.run_controller.run_state.active_item_id = &""
	session.run_controller.phase = FoldlightRogueRunController.Phase.REWARD
	session.current_room_node["category"] = &"combat"
	session._enter_modal_safety()
	session._on_run_room_cleared(session.current_room_node, {"duration": 42.0})
	await process_frame

	_check(session._current_reward_kind == &"upgrade", "second room first presents a normal three-choice upgrade")
	_check(session._pending_reward_sequence == [&"active"], "active-item choice is queued behind the upgrade")
	_check(session.player.active_item_slot.definition == null, "active slot remains empty before the second reward stage")
	var upgrade_id := _first_choice_of_kind(session, &"upgrade")
	_check(not upgrade_id.is_empty(), "second-room upgrade stage contains a valid choice")
	if not upgrade_id.is_empty():
		session._on_reward_chosen(upgrade_id)
	await process_frame

	_check(session._current_reward_kind == &"active", "choosing the upgrade immediately opens the active-item stage")
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD, "combat stays frozen between both reward stages")
	var active_id := _first_choice_of_kind(session, &"active")
	_check(not active_id.is_empty(), "second-room active-item stage contains a valid item")
	if not active_id.is_empty():
		session._on_reward_chosen(active_id)
	await process_frame

	_check(session.run_controller.run_state.active_item_id == active_id, "chosen active item is written to the run build")
	_check(session.player.active_item_slot.definition != null, "chosen active item is equipped immediately")
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE, "route choice opens only after both rewards are complete")

	game.queue_free()
	await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	_finish()


func _first_choice_of_kind(session: FoldlightRogueSessionController, kind: StringName) -> StringName:
	for choice_id: Variant in session._pending_reward_kinds.keys():
		if StringName(session._pending_reward_kinds.get(String(choice_id), &"")) == kind:
			return StringName(choice_id)
	return &""


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_SECOND_ROOM_DOUBLE_REWARD_3_7: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_SECOND_ROOM_DOUBLE_REWARD_3_7: FAIL - %s" % ", ".join(_failures))
		quit(1)
