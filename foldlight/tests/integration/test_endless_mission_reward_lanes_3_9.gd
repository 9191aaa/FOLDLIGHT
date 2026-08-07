extends SceneTree

## Endless 3.9 mission-reward contract: every completion offers one stable card
## from each of three readable lanes, all six rewards affect the live slice, and
## mission choices remain isolated from the two progression axes and Profile.

const EXPECTED_FIRST_IDS: Array[StringName] = [&"surge_return", &"wide_fold", &"steady_lantern"]
const EXPECTED_SECOND_IDS: Array[StringName] = [&"crosswind", &"kinetic_paper", &"clear_current"]
const EXPECTED_LANE_IDS: Array[StringName] = [&"power", &"fold_mobility", &"sustain"]
const EXPECTED_LANE_TITLES: Array[String] = ["火力", "折域机动", "续航"]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene
	var slice := packed.instantiate() as FoldlightEndlessSliceRuntime if packed != null else null
	_check(slice != null, "endless slice loads for mission-reward lane integration")
	if slice == null:
		_finish()
		return
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)

	_test_rotation_determinism_and_card_copy(slice)
	_test_surge_return_effect(slice)
	_test_wide_fold_effect(slice)
	_test_steady_lantern_effect(slice)
	_test_crosswind_real_pierce(slice)
	_test_kinetic_paper_effect(slice)
	_test_clear_current_real_fold_mobility(slice)
	_test_reward_modal_freezes_combat(slice)
	_test_restart_resets_mission_rewards(slice)
	_test_absorb_return_chain(slice)

	slice.queue_free()
	await process_frame
	_finish()


func _test_rotation_determinism_and_card_copy(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(39001)
	var first_a := slice.controller.evolution.get_mission_reward_options(0)
	var first_b := slice.controller.evolution.get_mission_reward_options(0)
	var second_a := slice.controller.evolution.get_mission_reward_options(1)
	var second_b := slice.controller.evolution.get_mission_reward_options(1)
	var wrapped := slice.controller.evolution.get_mission_reward_options(2)

	_check(_option_ids(first_a) == EXPECTED_FIRST_IDS, "completion 0 is exactly surge_return / wide_fold / steady_lantern")
	_check(_option_ids(second_a) == EXPECTED_SECOND_IDS, "completion 1 is exactly crosswind / kinetic_paper / clear_current")
	_check(_option_ids(wrapped) == EXPECTED_FIRST_IDS, "completion 2 wraps exactly back to the first reward tier")
	_check(var_to_str(first_a) == var_to_str(first_b) and var_to_str(second_a) == var_to_str(second_b), "repeated reward-option calls are deterministic")
	_check(_option_lane_ids(first_a) == EXPECTED_LANE_IDS and _option_lane_ids(second_a) == EXPECTED_LANE_IDS, "both tiers preserve power / fold_mobility / sustain lane order")
	_check(_all_unique(_option_ids(first_a)) and _all_unique(_option_ids(second_a)), "each completion offers three unique reward routes")
	var six_ids := _option_ids(first_a)
	six_ids.append_array(_option_ids(second_a))
	_check(_all_unique(six_ids) and six_ids.size() == 6, "the two-tier cycle exposes all six rewards without duplication")
	_check(_all_next_level(first_a, 1) and _all_next_level(second_a, 1), "fresh reward cards all advertise next_level 1")

	var applied := slice.controller.evolution.apply_mission_reward(&"surge_return")
	var leveled_wrap := slice.controller.evolution.get_mission_reward_options(2)
	_check(int(applied.get("level", 0)) == 1, "claim result reports the granted reward level")
	_check(_next_level_for(leveled_wrap, &"surge_return") == 2, "a repeated surge_return card advertises next_level 2")
	_check(_next_level_for(leveled_wrap, &"wide_fold") == 1 and _next_level_for(leveled_wrap, &"steady_lantern") == 1, "unclaimed lanes remain at next_level 1")

	slice.start_slice(39002)
	first_a = slice.controller.evolution.get_mission_reward_options(0)
	slice._on_mission_reward_offered(first_a, {"title": "航路校验"})
	for index in first_a.size():
		var option := first_a[index]
		var card_text := slice.modal_buttons[index].text
		_check(card_text.contains("【%s】" % EXPECTED_LANE_TITLES[index]), "reward card %d shows its lane title" % (index + 1))
		_check(card_text.contains(String(option.get("title", ""))), "reward card %d shows the reward name" % (index + 1))
		_check(card_text.contains("Lv.%d" % int(option.get("next_level", 0))), "reward card %d shows its next level" % (index + 1))
		_check(card_text.contains(String(option.get("description", ""))), "reward card %d shows the complete effect description" % (index + 1))


func _test_surge_return_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39010)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 0, &"surge_return"), "surge_return can be chosen from the power lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("return_damage", 0.0)) > float(before.get("return_damage", INF)), "surge_return increases live return-light damage")
	_check(float(after.get("return_speed", 0.0)) > float(before.get("return_speed", INF)), "surge_return increases live return-light speed")

	var target_position := slice.player_position + Vector2(240.0, 0.0)
	slice._enemies = [_test_enemy(101, target_position, 20.0)]
	slice._return_shots = [{"position": target_position, "target_uid": 101, "waypoints": PackedVector2Array([target_position]), "waypoint_index": 0}]
	slice._update_return_shots(0.01)
	_check(is_equal_approx(20.0 - float(slice._enemies[0].get("hp", 20.0)), float(after.get("return_damage", 0.0))), "surge_return damage reaches a real endless enemy")
	_check(_isolation_unchanged(slice, isolation), "surge_return does not advance waves, absorption, or Profile")


func _test_wide_fold_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39020)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 0, &"wide_fold"), "wide_fold can be chosen from the fold-mobility lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("fold_radius", 0.0)) > float(before.get("fold_radius", INF)), "wide_fold expands the live fold radius")
	_check(int(after.get("capture_capacity", 0)) == int(before.get("capture_capacity", 0)) + 1, "wide_fold adds one real capture slot")
	_check(_isolation_unchanged(slice, isolation), "wide_fold does not advance waves, absorption, or Profile")


func _test_steady_lantern_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39030)
	slice.player_health = slice.max_health - 2
	var health_before := slice.player_health
	var maximum_before := slice.max_health
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 0, &"steady_lantern"), "steady_lantern can be chosen from the sustain lane")
	_check(slice.max_health == maximum_before + 1, "steady_lantern raises the real maximum health by one")
	_check(slice.player_health == health_before + 1, "steady_lantern immediately heals one real health")
	_check(_isolation_unchanged(slice, isolation), "steady_lantern does not advance waves, absorption, or Profile")


func _test_crosswind_real_pierce(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39040)
	var lane := _find_open_weapon_lane(slice)
	var first_position := slice.player_position + lane * 210.0
	var second_position := slice.player_position + lane * 430.0
	slice._enemies = [_test_enemy(201, first_position, 10.0), _test_enemy(202, second_position, 10.0)]
	slice._auto_fire_clock = 0.0
	slice._update_auto_weapon(1.0)
	_check(is_equal_approx(float(slice._enemies[0].get("hp", 0.0)), 9.0) and is_equal_approx(float(slice._enemies[1].get("hp", 0.0)), 10.0), "without crosswind one automatic shot damages only its first target")

	slice._enemies = [_test_enemy(201, first_position, 10.0), _test_enemy(202, second_position, 10.0)]
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 1, &"crosswind"), "crosswind can be chosen from the power lane")
	var after := slice.get_effective_combat_stats()
	_check(int(after.get("weapon_pierce", 0)) == int(before.get("weapon_pierce", 0)) + 1, "crosswind grants one live automatic-weapon pierce")
	_check(float(after.get("auto_fire_interval", INF)) < float(before.get("auto_fire_interval", 0.0)), "crosswind shortens the live automatic-fire interval")
	slice._auto_fire_clock = 0.0
	slice._update_auto_weapon(1.0)
	_check(is_equal_approx(float(slice._enemies[0].get("hp", 0.0)), 9.0) and is_equal_approx(float(slice._enemies[1].get("hp", 0.0)), 9.0), "crosswind makes one real automatic shot damage two collinear enemies")
	_check(_isolation_unchanged(slice, isolation), "crosswind does not advance waves, absorption, or Profile")


func _test_kinetic_paper_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39050)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 1, &"kinetic_paper"), "kinetic_paper can be chosen from the fold-mobility lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("move_speed", 0.0)) > float(before.get("move_speed", INF)), "kinetic_paper raises live movement speed")
	_check(float(after.get("dash_cooldown", INF)) < float(before.get("dash_cooldown", 0.0)), "kinetic_paper lowers live dash cooldown")
	slice.dash_remaining = 0.0
	slice.dash_cooldown_remaining = 0.0
	slice._try_dash()
	_check(is_equal_approx(slice.dash_cooldown_remaining, float(after.get("dash_cooldown", -1.0))), "kinetic_paper cooldown is used by an actual dash")
	_check(_isolation_unchanged(slice, isolation), "kinetic_paper does not advance waves, absorption, or Profile")


func _test_clear_current_real_fold_mobility(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39060)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(_offer_and_choose(slice, 1, &"clear_current"), "clear_current can be chosen from the sustain lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("fold_move_speed", 0.0)) > float(before.get("fold_move_speed", INF)), "clear_current increases the live expanded-fold movement speed")
	_check(float(after.get("damage_grace", 0.0)) > float(before.get("damage_grace", INF)), "clear_current increases live post-hit protection")

	Input.action_press(&"move_right")
	slice.folding = true
	slice.player_velocity = Vector2.ZERO
	slice._update_player(0.5)
	Input.action_release(&"move_right")
	_check(is_equal_approx(slice.player_velocity.length(), float(after.get("fold_move_speed", -1.0))), "clear_current changes actual movement while the fold is expanded")
	slice.player_health = slice.max_health
	slice.player_invulnerability = 0.0
	slice._take_player_damage()
	_check(is_equal_approx(slice.player_invulnerability, float(after.get("damage_grace", -1.0))), "clear_current applies its longer protection to a real player hit")
	_check(_isolation_unchanged(slice, isolation), "clear_current does not advance waves, absorption, or Profile")


func _test_reward_modal_freezes_combat(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(39070)
	slice.set_physics_process(false)
	slice.player_velocity = Vector2.ZERO
	slice.player_health = slice.max_health
	slice.player_invulnerability = 0.0
	var lane := _find_open_weapon_lane(slice)
	slice._enemies = [_test_enemy(301, slice.player_position + lane * 300.0, 99.0)]
	slice._projectiles = [{
		"position": slice.player_position,
		"velocity": Vector2.ZERO,
		"life": 5.0,
		"radius": 7.0,
		"curve": 0.0,
	}]
	slice.controller._on_objective_completed({"completion_count": 1, "title": "modal freeze contract"})
	var health_before := slice.player_health
	var projectiles_before := var_to_str(slice._projectiles)
	var enemies_before := var_to_str(slice._enemies)
	_check(slice._modal_kind == &"reward" and slice.modal_dim.visible, "mission reward opens a blocking modal")

	slice._physics_process(0.25)
	_check(slice.player_health == health_before, "an open reward modal freezes player health")
	_check(slice._projectiles.size() == 1 and var_to_str(slice._projectiles) == projectiles_before, "an open reward modal freezes hostile projectile count and position")
	_check(var_to_str(slice._enemies) == enemies_before, "an open reward modal freezes the complete enemy state")

	slice._activate_modal_choice(0)
	_check(slice._modal_kind.is_empty() and not slice.modal_dim.visible, "choosing a reward closes the blocking modal")
	slice._physics_process(0.1)
	_check(slice.player_health == health_before - 1 and slice._projectiles.is_empty(), "combat resumes after selection and the waiting projectile can hit")
	_check(var_to_str(slice._enemies) != enemies_before, "enemy simulation resumes after reward selection")


func _test_restart_resets_mission_rewards(slice: FoldlightEndlessSliceRuntime) -> void:
	var profile_manager := root.get_node_or_null("ProfileManager") as FoldlightProfileManager
	var profile_before := profile_manager.get_public_snapshot() if profile_manager != null else {}
	_check(not (slice.controller.evolution.get_mission_snapshot().get("reward_levels", {}) as Dictionary).is_empty(), "the preceding run contains a mission reward before restart")
	slice.start_slice(39999)
	var mission := slice.controller.evolution.get_mission_snapshot()
	var modifiers := mission.get("total_modifiers", {}) as Dictionary
	var all_zero := true
	for value: Variant in modifiers.values():
		if not is_zero_approx(float(value)):
			all_zero = false
	_check((mission.get("reward_levels", {}) as Dictionary).is_empty() and all_zero, "restarting resets every mission reward level and modifier")
	_check(slice.controller.get_pending_mission_rewards().is_empty(), "restarting clears pending mission choices")
	var reset_stats := slice.get_effective_combat_stats()
	_check(int(reset_stats.get("max_health", 0)) == 5 and int(reset_stats.get("weapon_pierce", -1)) == 0, "restarting restores baseline live combat values")
	_check(profile_manager == null or var_to_str(profile_manager.get_public_snapshot()) == var_to_str(profile_before), "restarting mission rewards leaves the external Profile unchanged")


func _test_absorb_return_chain(slice: FoldlightEndlessSliceRuntime) -> void:
	slice.start_slice(39080)
	slice.set_physics_process(false)
	var baseline_stats := slice.get_effective_combat_stats()
	_check(baseline_stats.has("return_chain") and int(baseline_stats.get("return_chain", -1)) == 0, "effective combat stats expose a zero baseline return_chain")
	var lane := _find_open_weapon_lane(slice)
	var first_position := slice.player_position + lane * 140.0
	var second_position := slice.player_position + lane * 250.0
	var third_position := slice.player_position + lane * 400.0
	slice._enemies = [
		_test_enemy(401, first_position, 30.0),
		_test_enemy(402, second_position, 30.0),
	]
	slice.folding = true
	slice.captured_buffer = 1
	slice._release_fold()
	_check(slice._return_shots.size() == 1 and int(slice._return_shots[0].get("target_uid", -1)) == 401, "a baseline return shot locks the nearest reachable enemy")
	if not slice._return_shots.is_empty():
		slice._return_shots[0]["position"] = first_position
		slice._update_return_shots(0.0)
	_check(slice._return_shots.is_empty(), "without return_chain one return shot dissipates after its first hit")
	_check(float(slice._enemies[0].get("hp", 30.0)) < 30.0 and is_equal_approx(float(slice._enemies[1].get("hp", 0.0)), 30.0), "a no-chain return shot damages only its original target")

	slice.start_slice(39081)
	slice.set_physics_process(false)
	lane = _find_open_weapon_lane(slice)
	first_position = slice.player_position + lane * 140.0
	second_position = slice.player_position + lane * 250.0
	third_position = slice.player_position + lane * 400.0
	var chain_threshold := int(slice.controller.config.player_absorb_thresholds[3])
	slice.controller.report_projectiles_absorbed(chain_threshold)
	var player_evolution := slice.controller.evolution.get_player_snapshot()
	var chain_stats := slice.get_effective_combat_stats()
	_check(_unlocked_perk_ids(player_evolution).has(&"chain_light"), "the public absorption entry reaches the chain_light evolution")
	_check(int(chain_stats.get("return_chain", 0)) == 1, "effective combat stats expose the unlocked return_chain")

	slice._enemies = [
		_test_enemy(411, first_position, 30.0),
		_test_enemy(412, second_position, 30.0),
		_test_enemy(413, third_position, 30.0),
	]
	slice.folding = true
	slice.captured_buffer = 1
	slice._release_fold()
	var initial_chain := int(chain_stats.get("return_chain", 0))
	_check(
		slice._return_shots.size() == 1
		and int(slice._return_shots[0].get("target_uid", -1)) == 411
		and int(slice._return_shots[0].get("chains_remaining", -1)) == initial_chain,
		"a released return shot carries the effective chain budget",
	)
	if slice._return_shots.is_empty():
		return
	var return_damage := float(chain_stats.get("return_damage", 0.0))
	slice._return_shots[0]["position"] = first_position
	slice._update_return_shots(0.0)
	var primary_after_first := float(slice._enemies[0].get("hp", 30.0))
	_check(is_equal_approx(30.0 - primary_after_first, return_damage), "the chained return shot damages its original target exactly once")
	_check(
		slice._return_shots.size() == 1
		and int(slice._return_shots[0].get("target_uid", -1)) == 412
		and int(slice._return_shots[0].get("chains_remaining", -1)) == initial_chain - 1,
		"the same return-shot slot consumes one chain and retargets the nearest reachable unhit enemy",
	)
	if slice._return_shots.is_empty():
		return
	slice._return_shots[0]["position"] = second_position
	slice._update_return_shots(0.0)
	_check(slice._return_shots.is_empty(), "the return shot dissipates when its chain budget is exhausted")
	_check(
		is_equal_approx(float(slice._enemies[0].get("hp", 0.0)), primary_after_first)
		and is_equal_approx(30.0 - float(slice._enemies[1].get("hp", 30.0)), return_damage)
		and is_equal_approx(float(slice._enemies[2].get("hp", 0.0)), 30.0),
		"return chaining never repeats the original target and does not exceed its chain budget",
	)


func _prepare_effect_case(slice: FoldlightEndlessSliceRuntime, seed: int) -> void:
	slice.start_slice(seed)
	slice.set_physics_process(false)
	slice.controller.advance_simulation(0.25, slice.player_position)
	slice.controller.report_projectiles_absorbed(3)


func _offer_and_choose(slice: FoldlightEndlessSliceRuntime, completion_index: int, reward_id: StringName) -> bool:
	slice.controller._on_objective_completed({"completion_count": completion_index + 1, "title": "奖励契约"})
	var options := slice.controller.get_pending_mission_rewards()
	for index in options.size():
		if StringName(options[index].get("id", &"")) == reward_id:
			slice._activate_modal_choice(index)
			return int((slice.controller.evolution.get_mission_snapshot().get("reward_levels", {}) as Dictionary).get(reward_id, 0)) == 1
	return false


func _capture_isolation_snapshot(slice: FoldlightEndlessSliceRuntime) -> Dictionary:
	var profile_manager := root.get_node_or_null("ProfileManager") as FoldlightProfileManager
	return {
		"wave_sequence": slice.controller.wave_sequence,
		"enemy_axis": var_to_str(slice.controller.evolution.get_enemy_snapshot()),
		"absorb_axis": var_to_str(slice.controller.evolution.get_player_snapshot()),
		"profile": var_to_str(profile_manager.get_public_snapshot()) if profile_manager != null else "",
	}


func _isolation_unchanged(slice: FoldlightEndlessSliceRuntime, before: Dictionary) -> bool:
	var profile_manager := root.get_node_or_null("ProfileManager") as FoldlightProfileManager
	return (
		slice.controller.wave_sequence == int(before.get("wave_sequence", -1))
		and var_to_str(slice.controller.evolution.get_enemy_snapshot()) == String(before.get("enemy_axis", ""))
		and var_to_str(slice.controller.evolution.get_player_snapshot()) == String(before.get("absorb_axis", ""))
		and (profile_manager == null or var_to_str(profile_manager.get_public_snapshot()) == String(before.get("profile", "")))
	)


func _find_open_weapon_lane(slice: FoldlightEndlessSliceRuntime) -> Vector2:
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()]
	for direction in directions:
		var destination := slice.player_position + direction * 430.0
		if slice.controller.map_definition.bounds.grow(-40.0).has_point(destination) and slice.controller.map_runtime.has_line_of_sight(slice.player_position, destination, 8.0):
			return direction
	_check(false, "authored harbor exposes a clear 430-pixel automatic-weapon lane")
	return Vector2.RIGHT


func _test_enemy(uid: int, position: Vector2, health: float) -> Dictionary:
	return {
		"uid": uid,
		"enemy_id": &"drifter",
		"spawn_role": &"melee",
		"position": position,
		"hp": health,
		"projectile_multiplier": 1.0,
		"fire_clock": 99.0,
		"charge_clock": 99.0,
		"charge_remaining": 0.0,
		"hit_flash": 0.0,
		"is_captain": false,
		"captain_id": &"",
	}


func _option_ids(options: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in options:
		ids.append(StringName(option.get("id", &"")))
	return ids


func _option_lane_ids(options: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for option in options:
		ids.append(StringName(option.get("lane_id", &"")))
	return ids


func _all_unique(ids: Array[StringName]) -> bool:
	var seen: Dictionary = {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return true


func _all_next_level(options: Array[Dictionary], expected: int) -> bool:
	for option in options:
		if int(option.get("next_level", 0)) != expected:
			return false
	return true


func _next_level_for(options: Array[Dictionary], reward_id: StringName) -> int:
	for option in options:
		if StringName(option.get("id", &"")) == reward_id:
			return int(option.get("next_level", 0))
	return 0


func _unlocked_perk_ids(snapshot: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for perk: Dictionary in snapshot.get("unlocked_perks", []) as Array[Dictionary]:
		ids.append(StringName(perk.get("id", &"")))
	return ids


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	Input.action_release(&"move_right")
	if _failures.is_empty():
		print("FOLDLIGHT_ENDLESS_MISSION_REWARD_LANES_3_9: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_MISSION_REWARD_LANES_3_9: FAIL - %s" % ", ".join(_failures))
		quit(1)
