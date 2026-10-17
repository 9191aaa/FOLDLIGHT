extends SceneTree

## Exercise the real reward controllers and mounted loadouts in both modes.
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := root.get_node_or_null("ProfileManager") as FoldlightProfileManager
	if profile != null:
		profile.persistence_enabled = false
	await _test_rogue_rewards()
	await _test_endless_rewards()
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	if _failures.is_empty():
		print("FOLDLIGHT_WEAPON_REWARD_FLOW: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_WEAPON_REWARD_FLOW: FAIL — %s" % ", ".join(_failures))
		quit(1)


func _test_rogue_rewards() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	await process_frame
	session.set_physics_process(false)
	var state := session.run_controller.run_state
	var profile_before := var_to_str(session.profile_manager.get_public_snapshot())
	session._on_encounter_cleared({"duration": 30.0})
	await process_frame
	var weapon_id := _offered_rogue_weapon(session)
	_check(session.presentation.screen_kind == &"reward" and session._pending_reward_kinds.size() == 3 and not weapon_id.is_empty(), "first real room offers one weapon alongside two build choices")
	var old_inventory := state.weapon_levels.duplicate(true)
	var unoffered := _unoffered_weapon(session._pending_reward_kinds)
	session._on_reward_chosen(unoffered)
	_check(state.weapon_levels == old_inventory and session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD, "valid catalog IDs that were not offered cannot claim a rogue reward")
	if not weapon_id.is_empty():
		session._on_reward_chosen(weapon_id)
		_check(state.get_weapon_level(weapon_id) == 1 and state.weapon_ids.has(&"crease_lantern") and session.player.weapon_mount.definitions.size() == 2, "first new weapon joins the live mount while the starter continues firing")
		var claimed_inventory := state.weapon_levels.duplicate(true)
		session._on_reward_chosen(weapon_id)
		_check(state.weapon_levels == claimed_inventory, "replayed rogue choice after closing a reward gives no second weapon rank")
	await process_frame
	_enter_next_room(session)
	await process_frame
	session._on_encounter_cleared({"duration": 30.0})
	await process_frame
	_check(session._pending_reward_sequence == [&"active"] and state.active_item_id.is_empty(), "second room retains its separate active-item teaching reward")
	var first_stage_id := _first_offered_rogue_id(session)
	if not first_stage_id.is_empty():
		session._on_reward_chosen(first_stage_id)
	_check(session.run_controller.phase == FoldlightRogueRunController.Phase.REWARD and session._current_reward_kind == &"active", "accepting the build reward advances to the active item instead of skipping it")
	var active_id := _first_offered_rogue_id(session)
	if not active_id.is_empty():
		session._on_reward_chosen(active_id)
	_check(not state.active_item_id.is_empty() and session.run_controller.phase == FoldlightRogueRunController.Phase.ROUTE_CHOICE, "second reward equips an active item before returning to the route")

	var all_unlocked := session.profile_manager.get_roguelite_snapshot()
	all_unlocked["unlocked_weapons"] = _all_weapon_ids()
	var previously_held := state.weapon_ids.duplicate()
	for reward_index in 6:
		state.room_count = 3 + reward_index
		var choices := session._draft_room_reward(&"forge", all_unlocked)
		_check(not choices.is_empty() and choices.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) == &"weapon"), "forge choices exclusively expand or improve the weapon arsenal")
		if choices.is_empty():
			break
		session.run_controller.phase = FoldlightRogueRunController.Phase.REWARD
		session.presentation.show_reward(choices, "试炼锻坊")
		var offered_id := StringName(choices[0]["content_id"])
		var old_rank := state.get_weapon_level(offered_id)
		session._on_reward_chosen(offered_id)
		_check(state.get_weapon_level(offered_id) == old_rank + 1, "accepting the real forge card acquires or upgrades exactly one rank")
		for retained_id: StringName in previously_held:
			_check(state.weapon_ids.has(retained_id), "forge selection retains prior weapon %s" % retained_id)
		previously_held = state.weapon_ids.duplicate()
	_check(state.weapon_ids.size() == 6 and session.player.weapon_mount.definitions.size() == 6, "rogue mode can collect and simultaneously equip all six automatic weapons")
	_enter_next_room(session)
	await process_frame
	var before_pause := state.weapon_levels.duplicate(true)
	session._pause_game()
	_check(session.is_paused() and not session.player.play_enabled, "pause suspends combat with the collected arsenal")
	session._resume_game()
	_check(state.weapon_levels == before_pause and session.player.weapon_mount.definitions.size() == 6, "pause and resume preserve all weapon ranks and mounted weapons")
	for owned_id in state.weapon_ids.duplicate():
		while state.get_weapon_level(owned_id) < FoldlightWeaponProgression.MAX_LEVEL:
			state.acquire_weapon(owned_id)
	var fallback := session._draft_room_reward(&"forge", all_unlocked)
	_check(not fallback.is_empty() and fallback.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"upgrade")) != &"weapon"), "mastered rogue arsenal falls back to meaningful build rewards")
	_check(var_to_str(session.profile_manager.get_public_snapshot()) == profile_before, "run weapon choices do not grant or overwrite permanent profile progression")
	session.start_new_run()
	await process_frame
	_check(state.weapon_levels == {"crease_lantern": 1} and session.player.weapon_mount.definitions.size() == 1, "a new rogue run resets ranks and removes the previous run's extra weapons")
	game.queue_free()
	await process_frame


func _test_endless_rewards() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.start_slice(313701)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	var profile_before := var_to_str(slice.profile_manager.get_public_snapshot())
	var first := {"completion_count": 1, "title": "首次任务"}
	slice.controller._on_objective_completed(first)
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	var options := slice.controller.get_pending_mission_rewards()
	_check(options.size() == 3 and options.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) == &"weapon"), "first endless task offers the shared weapon draft")
	_check(slice._modal_kind == &"reward" and not slice.player.play_enabled and not slice.combat_runtime.active, "weapon choices suspend real endless combat")
	var before := slice.controller.weapon_levels.duplicate(true)
	slice._on_reward_chosen(&"missing_weapon")
	_check(slice.controller.weapon_levels == before and not slice.controller.get_pending_mission_rewards().is_empty(), "unoffered endless choice cannot grant a rank or consume the pending reward")
	var selected := StringName(options[0]["id"])
	slice._on_reward_chosen(selected)
	_check(int(slice.controller.weapon_levels.get(String(selected), 0)) == 1 and slice.player.weapon_mount.definitions.size() == 2, "endless weapon reward synchronizes the live arsenal and keeps the starter")
	var earned := slice.controller.weapon_levels.duplicate(true)
	_check(slice.controller.claim_mission_reward(selected).is_empty(), "a second direct claim is rejected after a reward was consumed")
	slice.controller._on_objective_completed(first)
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	_check(slice.controller.get_pending_mission_rewards().is_empty() and slice.controller.weapon_levels == earned and slice._modal_kind.is_empty(), "a stale completion event cannot reopen or duplicate a finished task reward")
	slice._pause_game()
	_check(slice._modal_kind == &"pause", "endless pause remains available after a weapon reward")
	slice._resume_game()
	_check(slice.controller.weapon_levels == earned and slice.player.weapon_mount.definitions.size() == 2, "endless resume preserves weapon ranks and mount contents")

	slice.controller._on_objective_completed({"completion_count": 2, "title": "成长任务"})
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	options = slice.controller.get_pending_mission_rewards()
	_check(options.size() == 3 and options.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) != &"weapon"), "second endless task retains the three firepower, fold, and sustain lanes")
	var pending_before := options.duplicate(true)
	slice.controller._on_objective_completed({"completion_count": 3, "title": "意外抢先事件"})
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	_check(slice.controller.get_pending_mission_rewards() == pending_before, "a new event cannot replace choices while the player is deciding")
	slice._on_reward_chosen(StringName(options[0]["id"]))
	_check(slice.controller.weapon_levels == earned and not (slice.controller.evolution.get_mission_snapshot()["reward_levels"] as Dictionary).is_empty(), "growth task improves its own lane without replacing collected weapons")
	slice.controller._on_objective_completed({"completion_count": 3, "title": "继续武器补给"})
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	options = slice.controller.get_pending_mission_rewards()
	var upgrade_id := &""
	for option in options:
		if int(option.get("next_level", 1)) > 1:
			upgrade_id = StringName(option["id"])
	_check(not upgrade_id.is_empty(), "next weapon task includes an upgrade for an existing weapon")
	if not upgrade_id.is_empty():
		var rank_before := int(slice.controller.weapon_levels.get(String(upgrade_id), 0))
		slice._on_reward_chosen(upgrade_id)
		_check(int(slice.controller.weapon_levels.get(String(upgrade_id), 0)) == rank_before + 1 and slice.player.weapon_mount.definitions.size() == 2, "repeated endless weapon upgrades one rank without creating a duplicate mount")
	for weapon_id in _all_weapon_ids():
		slice.controller.weapon_levels[String(weapon_id)] = FoldlightWeaponProgression.MAX_LEVEL
	slice.controller._on_objective_completed({"completion_count": 5, "title": "满阶补给"})
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	options = slice.controller.get_pending_mission_rewards()
	_check(not options.is_empty() and options.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) != &"weapon"), "mastered endless arsenal uses growth cards instead of an empty reward modal")
	if not options.is_empty():
		slice._on_reward_chosen(StringName(options[0]["id"]))
	_check(var_to_str(slice.profile_manager.get_public_snapshot()) == profile_before, "endless arsenal and lane rewards stay isolated from permanent profile progress")
	slice.start_slice(313701)
	_check(slice.controller.weapon_levels == {"crease_lantern": 1} and slice.player.weapon_mount.definitions.size() == 1 and slice.controller.get_pending_mission_rewards().is_empty(), "new endless run clears extra weapons, ranks, and pending choices")
	slice.controller._on_objective_completed(first)
	# Finish the visible facility unfold before inspecting or choosing cards.
	for transition_step in 6:
		slice._advance_reward_completion(0.1)
	_check(slice.controller.get_pending_mission_rewards().size() == 3, "restarting resets the completion guard so task one can reward again")
	slice.queue_free()
	await process_frame


func _all_weapon_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		result.append(definition.content_id)
	return result


func _offered_rogue_weapon(session: FoldlightRogueSessionController) -> StringName:
	for key: String in session._pending_reward_kinds:
		if StringName(session._pending_reward_kinds[key]) == &"weapon":
			return StringName(key)
	return &""


func _first_offered_rogue_id(session: FoldlightRogueSessionController) -> StringName:
	for button: Button in session.presentation._reward_buttons:
		if button.visible:
			return StringName(button.get_meta("upgrade_id", &""))
	return &""


func _unoffered_weapon(offered: Dictionary) -> StringName:
	for weapon_id in _all_weapon_ids():
		if not offered.has(String(weapon_id)):
			return weapon_id
	return &"missing_weapon"


func _enter_next_room(session: FoldlightRogueSessionController) -> void:
	var exits: Array = session.current_room_node.get("exits", [])
	if not exits.is_empty():
		session._on_route_chosen(StringName(exits[0]))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
