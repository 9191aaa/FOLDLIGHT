extends SceneTree

class RecordingBridge extends "res://scripts/autoloads/web_race_bridge.gd":
	func _read_browser_boot() -> Dictionary: return {}
	func _send_browser(_method: StringName, _payload: Dictionary) -> void: pass

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	await _test_rogue()
	await _test_endless()
	await _test_race()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_ACTIVE_COLLECTION_FLOW_3_15: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_rogue() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	session.set_physics_process(false)
	var state := session.run_controller.run_state
	var slot := session.player.active_item_slot
	var profile_before := session.profile_manager.get_roguelite_snapshot().duplicate(true)
	var choices := _offer_rogue_skills(session)
	_check(choices.size() == 3 and slot.get_inventory_snapshot().is_empty(), "voyage starts without a skill and offers unlocked skills through the shared reward flow")
	session._on_reward_chosen(&"sun_stamp")
	_check(slot.get_inventory_snapshot().is_empty(), "a catalog skill absent from the offered cards cannot be collected")
	session._on_reward_chosen(&"paper_burst")
	slot.cooldown_remaining = 4.5
	choices = _offer_rogue_skills(session)
	_check(choices.size() == 2 and not session._pending_reward_kinds.has("paper_burst"), "collected skills leave the new-skill reward pool")
	session._on_reward_chosen(&"mirror_step")
	slot.cooldown_remaining = 3.25
	_check(state.active_item_ids.size() == 2 and slot.get_inventory_snapshot().size() == 2 and state.active_item_id == &"mirror_step", "second real reward collects and equips without discarding the first skill")
	session._pause_game()
	_check(session.presentation.screen_kind == &"route" and not session._paused, "late pause signal cannot turn route choice into a room checkpoint")
	choices = _offer_rogue_skills(session)
	var offered_before := session._pending_reward_kinds.duplicate(true)
	session._pause_game()
	_check(session.presentation.screen_kind == &"reward" and not session._paused, "late pause signal cannot bypass an unresolved reward")
	session.presentation.active_relic_selected.emit(&"paper_burst")
	_check(state.active_item_id == &"paper_burst" and is_equal_approx(slot.cooldown_remaining, 4.5) and session._pending_reward_kinds == offered_before and session.presentation.screen_kind == &"reward", "reward skill selection preserves independent cooldown and leaves the reward unclaimed")
	await create_timer(0.16).timeout
	_check(is_equal_approx(slot.cooldown_remaining, 4.5), "reward freeze includes all collected skill cooldowns")
	session._on_reward_chosen(&"ink_wash")
	_check(state.active_item_ids.size() == 3, "all unlocked skills can coexist in the run collection")
	var saved_count := slot.get_inventory_snapshot().size()
	session._on_reward_chosen(&"ink_wash")
	_check(slot.get_inventory_snapshot().size() == saved_count, "replayed reward selection cannot duplicate an acquired skill")
	var expected := slot.get_save_snapshot()
	var exits: Array = session.run_controller.get_current_room_node().get("exits", [])
	if not exits.is_empty():
		session._on_route_chosen(StringName(exits[0]))
	_check(slot.get_save_snapshot() == expected and state.get_active_collection() == expected, "crossing a real route restores the exact collection and preserves independent cooldowns")
	# The real pause freezes the scene, while direct callback authorization is
	# deliberately checked without depending on animated button coordinates.
	session.presentation.show_hud()
	session._pause_game()
	session.presentation.active_relic_selected.emit(&"mirror_step")
	_check(session._paused and state.active_item_id == &"mirror_step" and is_equal_approx(slot.cooldown_remaining, 3.25), "voyage pause can equip a previous skill without resetting its cooldown")
	session.persist_profile = true
	session.presentation.active_relic_selected.emit(&"paper_burst")
	var persisted: Dictionary = session.profile_manager.get_roguelite_snapshot().get("active_run", {})
	_check(persisted.get("active_item_ids", []).size() == 3 and float((persisted.get("active_item_cooldowns", {}) as Dictionary).get("paper_burst", 0.0)) == 4.5, "safe paused selection persists the entire collection and current remaining cooldowns")
	session.enter_title()
	session.continue_run()
	_check(slot.get_save_snapshot() == {"active_item_ids": persisted.active_item_ids, "active_item_id": persisted.active_item_id, "active_item_cooldowns": persisted.active_item_cooldowns}, "continue reconstructs the live slot from the collection checkpoint")
	var fallback := _offer_rogue_skills(session)
	_check(not fallback.is_empty() and fallback.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) != &"active"), "collecting every unlocked skill falls back to useful build rewards")
	session.persist_profile = false
	session.start_new_run()
	_check(slot.get_inventory_snapshot().is_empty() and state.active_item_ids.is_empty() and state.active_item_cooldowns.is_empty(), "restarting the same voyage instance clears prior skills and cooldowns")
	# Restore the fixture profile: run skills never become permanent unlocks.
	_check(session.profile_manager.get_roguelite_snapshot().get("unlocked_active_items") == profile_before.get("unlocked_active_items"), "run collections cannot mutate permanent skill unlocks")
	game.queue_free()
	await process_frame


func _offer_rogue_skills(session: FoldlightRogueSessionController) -> Array[Dictionary]:
	session._enter_modal_safety()
	session._paused = false
	session.run_controller.phase = FoldlightRogueRunController.Phase.REWARD
	session._pending_reward_sequence.clear()
	session._current_reward_kind = &"active"
	var choices := session._draft_room_reward(&"shop", session.profile_manager.get_roguelite_snapshot(), &"active")
	session._refresh_active_inventory()
	session.presentation.show_reward(choices, "主动技能补给")
	return choices


func _test_endless() -> void:
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.start_slice(315315)
	slice.player.set_debug_invincible(true)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	var original_profile := profile.profile.duplicate(true)
	var options := slice.controller._draft_mission_rewards(3)
	(profile.profile["roguelite"] as Dictionary)["unlocked_active_items"] = []
	_check(options == slice.controller._draft_mission_rewards(3) and options.size() == 3 and StringName(options[2].choice_kind) == &"active" and StringName(options[0].choice_kind) == &"weapon", "same-seed endless skill supplies ignore profile unlocks and keep weapon choices")
	profile.profile = original_profile
	slice.player.active_item_slot.cooldown_remaining = 4.0
	slice.controller._on_objective_completed({"completion_count": 3, "title": "技能补给"})
	var active_id := StringName(options[2].id)
	slice.presentation.active_relic_selected.emit(active_id)
	_check(slice.player.active_item_slot.definition.content_id == &"paper_burst", "completion animation cannot equip an unowned reward skill")
	for step in 6: slice._advance_reward_completion(0.1)
	slice._on_reward_chosen(active_id)
	_check(slice.player.get_active_inventory_snapshot().size() == 2 and slice.controller.active_item_id == active_id and slice._modal_kind.is_empty(), "endless real reward collects its optional skill and resumes combat")
	slice.player.active_item_slot.cooldown_remaining = 2.0
	slice._pause_game()
	slice.presentation.active_relic_selected.emit(&"paper_burst")
	_check(slice._modal_kind == &"pause" and slice.controller.active_item_id == &"paper_burst" and is_equal_approx(slice.player.active_item_slot.cooldown_remaining, 4.0), "solo endless pause can switch despite reward cancellation having locked old cards")
	await create_timer(0.18).timeout
	_check(is_equal_approx(slice.player.active_item_slot.cooldown_remaining, 4.0), "solo endless pause freezes the collected skill cooldowns")
	slice._resume_game()
	for item in FoldlightRogueContentCatalog.ACTIVE_ITEMS:
		slice.player.active_item_slot.acquire(item, false)
	slice.controller.set_active_collection(slice.player.active_item_slot.get_save_snapshot())
	var fallback := slice.controller._draft_mission_rewards(7)
	_check(fallback.size() == 3 and fallback.all(func(choice: Dictionary) -> bool: return StringName(choice.get("choice_kind", &"")) != &"active"), "complete endless collection restores a useful third reward card")
	slice._finish_run()
	var final_collection := slice.player.active_item_slot.get_save_snapshot()
	slice.presentation.active_relic_selected.emit(active_id)
	_check(slice.player.active_item_slot.get_save_snapshot() == final_collection, "death rejects delayed skill-selection callbacks")
	slice.start_slice(315316)
	_check(slice.player.get_active_inventory_snapshot().size() == 1 and slice.controller.active_item_ids == [&"paper_burst"] and slice.player.active_item_slot.cooldown_remaining == 0.0, "same endless instance restart returns to the common starter collection")
	slice.queue_free()
	await process_frame


func _test_race() -> void:
	var bridge := RecordingBridge.new()
	root.add_child(bridge)
	bridge.configure_session({"roomId": "skills", "matchId": "skills", "playerId": "test", "instanceId": "skills-315", "seed": 315315, "rulesVersion": "endless_race_v7"})
	bridge.set_process(false)
	var slice := (load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene).instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	slice.prepare_web_race(bridge)
	await process_frame
	await process_frame
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	slice.player.set_debug_invincible(true)
	# Use the real supply lifecycle to collect the race's second skill.
	slice.controller._on_objective_completed({"completion_count": 3, "title": "好友技能补给"})
	for step in 6: slice._advance_reward_completion(0.1)
	var supply := slice.controller.get_pending_mission_rewards()
	var skill_id := StringName(supply[2].id)
	slice._on_reward_chosen(skill_id)
	slice.player.active_item_slot.cooldown_remaining = 3.0
	slice.presentation.active_relic_selected.emit(&"paper_burst")
	slice._pause_game()
	_check(slice._modal_kind.is_empty() and slice.player.active_item_slot.definition.content_id == skill_id and not slice.presentation.open_active_collection(), "live friend race cannot use skill selection to obtain a manual pause")
	slice.controller._on_objective_completed({"completion_count": 4, "title": "好友成长补给"})
	for step in 6: slice._advance_reward_completion(0.1)
	var offered := slice.controller.get_pending_mission_rewards()
	var score := int(slice.get_race_stats().survivalMs)
	await create_timer(1.15).timeout
	_check(slice.presentation.open_active_collection(), "friend reward exposes the same collected-skill book")
	await create_timer(1.1).timeout
	slice.presentation._on_active_skill_selected(&"paper_burst")
	_check(slice.player.active_item_slot.definition.content_id == &"paper_burst" and slice.controller.active_item_id == &"paper_burst", "friend reward can equip a collected skill before committing the reward")
	_check(slice.controller.get_pending_mission_rewards() == offered and slice.get_race_stats().survivalMs == score and slice.get_race_stats().pauseReason == "reward", "opening and using the book preserves the exact draft and the legitimate reward clock freeze")
	slice.presentation.close_active_collection()
	await create_timer(0.2).timeout
	_check(slice._modal_kind == &"reward" and slice.controller.get_pending_mission_rewards() == offered and slice.presentation._reward_input_guard.can_select(), "closing the book returns to the same protected reward without redrafting or consuming it")
	slice.presentation._reward_buttons[0].pressed.emit()
	await create_timer(0.25).timeout
	_check(slice._modal_kind.is_empty() and slice.controller.get_pending_mission_rewards().is_empty(), "a real reward-card confirmation still resumes the race after using the skill book")
	slice.controller._on_objective_completed({"completion_count": 5, "title": "结束测试"})
	for step in 6: slice._advance_reward_completion(0.1)
	var before := slice.player.active_item_slot.get_save_snapshot()
	bridge.accept_page_state({"phase": "finished", "reason": "match_finished"})
	slice.presentation.active_relic_selected.emit(skill_id)
	_check(slice.player.active_item_slot.get_save_snapshot() == before and slice._modal_kind == &"race_finished" and not slice.combat_runtime.active, "server completion closes reward ownership and rejects late skill callbacks")
	slice.queue_free()
	bridge.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
