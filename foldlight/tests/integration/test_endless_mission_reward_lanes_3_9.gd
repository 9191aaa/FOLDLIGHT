extends SceneTree

## Endless 3.9 mission-reward contract: every completion offers one stable card
## from each of three readable lanes, all six rewards affect shared combat, and
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
	await _test_surge_return_effect(slice)
	await _test_wide_fold_effect(slice)
	await _test_steady_lantern_effect(slice)
	await _test_crosswind_real_pierce(slice)
	await _test_kinetic_paper_effect(slice)
	await _test_clear_current_real_fold_mobility(slice)
	await _test_reward_modal_freezes_combat(slice)
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
	_check(await _offer_and_choose(slice, 0, &"surge_return"), "surge_return can be chosen from the power lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("return_damage", 0.0)) > float(before.get("return_damage", INF)), "surge_return increases live return-light damage")
	_check(float(after.get("return_speed", 0.0)) > float(before.get("return_speed", INF)), "surge_return increases live return-light speed")
	var targets := _spawn_test_enemies(slice, [240.0], 20.0)
	var shot := _release_single_return(slice)
	_check(shot != null, "surge_return releases a shared return-light projectile")
	if shot != null:
		_check(is_equal_approx(shot.homing_speed, float(after["return_speed"])), "surge_return speed reaches the real homing projectile")
		_place_projectile_on_target(slice, shot, targets[0])
		_check(is_equal_approx(20.0 - targets[0].health, float(after["return_damage"])), "surge_return damage reaches a real shared enemy")
	_check(_isolation_unchanged(slice, isolation), "surge_return does not advance waves, absorption, or Profile")


func _test_wide_fold_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39020)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(await _offer_and_choose(slice, 0, &"wide_fold"), "wide_fold can be chosen from the fold-mobility lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("fold_radius", 0.0)) > float(before.get("fold_radius", INF)), "wide_fold expands the live fold radius")
	_check(int(after.get("capture_capacity", 0)) == int(before.get("capture_capacity", 0)) + 1, "wide_fold adds one real capture slot")
	_check(slice.player.try_begin_fold(), "wide_fold permits a real fold")
	slice.player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	_check(is_equal_approx(slice.player.get_fold_radius(), float(after["fold_radius"])), "wide_fold expands the player's capture geometry")
	slice.player.captured = int(before["capture_capacity"])
	_check(slice.player.capture_one() and not slice.player.capture_one(), "wide_fold accepts exactly one capture beyond the old capacity")
	_check(_isolation_unchanged(slice, isolation), "wide_fold does not advance waves, absorption, or Profile")


func _test_steady_lantern_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39030)
	slice.player.health = slice.player.max_health - 2
	var health_before := slice.player.health
	var maximum_before := slice.player.max_health
	var isolation := _capture_isolation_snapshot(slice)
	_check(await _offer_and_choose(slice, 0, &"steady_lantern"), "steady_lantern can be chosen from the sustain lane")
	_check(slice.player.max_health == maximum_before + 1, "steady_lantern raises the real maximum health by one")
	_check(slice.player.health == health_before + 1, "steady_lantern immediately heals one real health")
	_check(_isolation_unchanged(slice, isolation), "steady_lantern does not advance waves, absorption, or Profile")


func _test_crosswind_real_pierce(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39040)
	var targets := _spawn_test_enemies(slice, [210.0, 430.0], 10.0)
	var shot := _fire_single_automatic_shot(slice)
	_check(shot != null, "baseline automatic weapon emits a shared projectile")
	if shot == null:
		return
	var damage := shot.damage
	_place_projectile_on_target(slice, shot, targets[0])
	_check(not slice.combat_runtime.projectiles.has(shot) and is_equal_approx(targets[0].health, 10.0 - damage) and is_equal_approx(targets[1].health, 10.0), "without crosswind one automatic shot damages only its first target")

	targets = _spawn_test_enemies(slice, [210.0, 430.0], 10.0)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(await _offer_and_choose(slice, 1, &"crosswind"), "crosswind can be chosen from the power lane")
	var after := slice.get_effective_combat_stats()
	_check(int(after.get("weapon_pierce", 0)) == int(before.get("weapon_pierce", 0)) + 1, "crosswind grants one live automatic-weapon pierce")
	_check(float(after.get("auto_fire_interval", INF)) < float(before.get("auto_fire_interval", 0.0)), "crosswind shortens the live automatic-fire interval")
	shot = _fire_single_automatic_shot(slice)
	_check(shot != null and shot.pierce_remaining == 1, "crosswind reaches the shared weapon's actual projectile")
	if shot != null:
		damage = shot.damage
		_place_projectile_on_target(slice, shot, targets[0])
		_check(slice.combat_runtime.projectiles.has(shot) and shot.pierce_remaining == 0, "crosswind keeps the shot alive after its first collision")
		_place_projectile_on_target(slice, shot, targets[1])
		_check(is_equal_approx(targets[0].health, 10.0 - damage) and is_equal_approx(targets[1].health, 10.0 - damage), "crosswind makes one real automatic shot damage two collinear enemies")
		_check(not slice.combat_runtime.projectiles.has(shot), "the automatic shot stops after consuming its pierce budget")
	_check(_isolation_unchanged(slice, isolation), "crosswind does not advance waves, absorption, or Profile")


func _test_kinetic_paper_effect(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39050)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(await _offer_and_choose(slice, 1, &"kinetic_paper"), "kinetic_paper can be chosen from the fold-mobility lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("move_speed", 0.0)) > float(before.get("move_speed", INF)), "kinetic_paper raises live movement speed")
	_check(float(after.get("dash_cooldown", INF)) < float(before.get("dash_cooldown", 0.0)), "kinetic_paper lowers live dash cooldown")
	slice.player.dash_component.reset()
	_check(slice.player.request_dash(Vector2.RIGHT), "kinetic_paper starts an actual shared-player dash")
	_check(is_equal_approx(slice.player.dash_component.cooldown_remaining, float(after.get("dash_cooldown", -1.0))), "kinetic_paper cooldown is used by the actual dash component")
	_check(_isolation_unchanged(slice, isolation), "kinetic_paper does not advance waves, absorption, or Profile")


func _test_clear_current_real_fold_mobility(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39060)
	var before := slice.get_effective_combat_stats()
	var isolation := _capture_isolation_snapshot(slice)
	_check(await _offer_and_choose(slice, 1, &"clear_current"), "clear_current can be chosen from the sustain lane")
	var after := slice.get_effective_combat_stats()
	_check(float(after.get("fold_move_speed", 0.0)) > float(before.get("fold_move_speed", INF)), "clear_current increases the live expanded-fold movement speed")
	_check(float(after.get("damage_grace", 0.0)) > float(before.get("damage_grace", INF)), "clear_current increases live post-hit protection")
	_check(slice.player.try_begin_fold(), "clear_current permits expanded-fold movement")
	Input.action_press(&"move_right")
	slice.player.velocity = Vector2.ZERO
	slice.player._physics_process(0.5)
	Input.action_release(&"move_right")
	_check(is_equal_approx(slice.player.velocity.length(), float(after.get("fold_move_speed", -1.0))), "clear_current changes actual shared-player movement while folding")
	slice.player.cancel_fold()
	slice.player.health = slice.player.max_health
	slice.player.invulnerability = 0.0
	_check(slice.player.take_hit(), "a real hit reaches the shared player after protection expires")
	_check(is_equal_approx(slice.player.invulnerability, float(after.get("damage_grace", -1.0))), "clear_current applies longer protection to a real player hit")
	_check(_isolation_unchanged(slice, isolation), "clear_current does not advance waves, absorption, or Profile")


func _test_reward_modal_freezes_combat(slice: FoldlightEndlessSliceRuntime) -> void:
	_prepare_effect_case(slice, 39070)
	slice.player.velocity = Vector2.ZERO
	slice.player.health = slice.player.max_health
	slice.player.invulnerability = 0.0
	var targets := _spawn_test_enemies(slice, [300.0], 99.0)
	slice.combat_runtime.spawn_hostile_volley({
		"origin": slice.player.global_position + Vector2(0.0, -80.0),
		"direction": Vector2.DOWN, "speed": 100.0, "projectile_count": 1,
	})
	var hostile := slice.combat_runtime.projectiles[0]
	slice.controller._on_objective_completed({"completion_count": 1, "title": "modal freeze contract"})
	var health_before := slice.player.health
	var projectile_position := hostile.global_position
	var projectile_lifetime := hostile.lifetime
	var enemy_before := targets[0].get_combat_snapshot()
	_check(slice._modal_kind == &"reward" and slice.modal_dim.visible, "mission reward opens a blocking modal")
	_check(not slice.player.play_enabled and not slice.combat_runtime.active, "reward suspension reaches shared player and combat runtime")
	slice._physics_process(0.25)
	slice.player._physics_process(0.25)
	slice.combat_runtime._physics_process(0.25)
	_check(slice.player.health == health_before, "an open reward modal freezes player health")
	_check(slice.combat_runtime.projectiles.size() == 1 and hostile.global_position == projectile_position and is_equal_approx(hostile.lifetime, projectile_lifetime), "an open reward modal freezes hostile position and lifetime")
	_check(targets[0].get_combat_snapshot() == enemy_before, "an open reward modal freezes the shared enemy state")

	await _wait_for_reward_input(slice)
	slice._activate_modal_choice(0)
	_check(slice._modal_kind.is_empty() and not slice.modal_dim.visible, "choosing a reward closes the blocking modal")
	_check(slice.player.play_enabled and slice.combat_runtime.active and slice.player.invulnerability >= 0.75, "selection restores shared combat with the overlay safety window")
	slice.combat_runtime._physics_process(0.1)
	_check(hostile.global_position != projectile_position and targets[0].get_combat_snapshot() != enemy_before, "hostile projectiles and enemies resume simulation after selection")
	_check(slice.player.health == health_before, "resuming does not bypass the player safety window")
	slice.player._physics_process(0.8)
	slice.combat_runtime._physics_process(0.8)
	_check(slice.player.health == health_before - 1 and not slice.combat_runtime.projectiles.has(hostile), "a waiting hostile projectile can hit after resume protection expires")


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
	_prepare_effect_case(slice, 39080)
	var baseline_stats := slice.get_effective_combat_stats()
	_check(baseline_stats.has("return_chain") and int(baseline_stats.get("return_chain", -1)) == 0, "effective combat stats expose a zero baseline return_chain")
	var targets := _spawn_test_enemies(slice, [140.0, 250.0], 30.0)
	var shot := _release_single_return(slice)
	_check(shot != null and shot.homing_target == targets[0], "a baseline shared return shot locks the nearest reachable enemy")
	if shot != null:
		_place_projectile_on_target(slice, shot, targets[0])
		_check(not slice.combat_runtime.projectiles.has(shot), "without return_chain the shared shot dissipates after its first hit")
		_check(targets[0].health < 30.0 and is_equal_approx(targets[1].health, 30.0), "a no-chain return shot damages only its original target")

	_prepare_effect_case(slice, 39081)
	var chain_threshold := int(slice.controller.config.player_absorb_thresholds[3])
	slice.controller.report_projectiles_absorbed(chain_threshold)
	var player_evolution := slice.controller.evolution.get_player_snapshot()
	var chain_stats := slice.get_effective_combat_stats()
	_check(_unlocked_perk_ids(player_evolution).has(&"chain_light"), "the public absorption entry reaches the chain_light evolution")
	_check(int(chain_stats.get("return_chain", 0)) == 1, "effective combat stats expose the unlocked return_chain")
	targets = _spawn_test_enemies(slice, [140.0, 250.0, 400.0], 30.0)
	shot = _release_single_return(slice)
	var initial_chain := int(chain_stats.get("return_chain", 0))
	_check(shot != null and shot.homing_target == targets[0] and shot.return_chain_remaining == initial_chain, "a released shared return shot carries the effective chain budget")
	if shot == null:
		return
	var return_damage := shot.damage
	_place_projectile_on_target(slice, shot, targets[0])
	var primary_after_first := targets[0].health
	_check(is_equal_approx(30.0 - primary_after_first, return_damage), "the chained return shot damages its original target exactly once")
	_check(slice.combat_runtime.projectiles.has(shot) and shot.homing_target == targets[1] and shot.return_chain_remaining == initial_chain - 1, "the shared shot consumes one chain and retargets the nearest reachable unhit enemy")
	_place_projectile_on_target(slice, shot, targets[1])
	_check(not slice.combat_runtime.projectiles.has(shot), "the shared shot dissipates when its chain budget is exhausted")
	_check(is_equal_approx(targets[0].health, primary_after_first) and is_equal_approx(30.0 - targets[1].health, return_damage) and is_equal_approx(targets[2].health, 30.0), "return chaining never repeats the original target or exceeds its chain budget")


func _prepare_effect_case(slice: FoldlightEndlessSliceRuntime, seed: int) -> void:
	slice.start_slice(seed)
	# Step the actual shared actors explicitly; prevent frame scheduling from
	# adding shots, input or objective time between deterministic observations.
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	slice.controller.advance_simulation(0.25, slice.player.global_position)
	slice.controller.report_projectiles_absorbed(3)
	slice.combat_runtime.clear_combat()


func _spawn_test_enemies(slice: FoldlightEndlessSliceRuntime, distances: Array, health: float) -> Array[FoldlightRogueEnemyActor]:
	slice.combat_runtime.clear_combat()
	var direction := _find_open_weapon_lane(slice)
	var entries: Array[Dictionary] = []
	for distance: float in distances:
		entries.append({"enemy_id": &"drifter", "spawn_position": slice.player.global_position + direction * distance})
	var spawned := slice.combat_runtime.spawn_directed_wave(entries)
	var result: Array[FoldlightRogueEnemyActor] = []
	for node in spawned:
		var actor := node as FoldlightRogueEnemyActor
		actor.health = health
		result.append(actor)
	_check(result.size() == distances.size(), "directed wave creates the requested real shared enemies")
	return result


func _release_single_return(slice: FoldlightEndlessSliceRuntime) -> FoldlightRogueProjectile:
	if not slice.player.try_begin_fold() or not slice.player.capture_one():
		return null
	slice.player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	slice.player.release_fold_action()
	for projectile in slice.combat_runtime.projectiles:
		if not projectile.hostile and projectile.style == &"return_light":
			return projectile
	return null


func _fire_single_automatic_shot(slice: FoldlightEndlessSliceRuntime) -> FoldlightRogueProjectile:
	slice.player.weapon_mount.reset_cadence()
	slice.player.tick_automatic_weapons(float(slice.get_effective_combat_stats()["auto_fire_interval"]) + 0.01, true)
	for projectile in slice.combat_runtime.projectiles:
		if not projectile.hostile:
			return projectile
	return null


func _place_projectile_on_target(slice: FoldlightEndlessSliceRuntime, projectile: FoldlightRogueProjectile, target: FoldlightRogueEnemyActor) -> void:
	# Position a real emitted projectile at impact, then exercise the real
	# collision, hit bookkeeping, pierce and return-chain path without travel.
	projectile.global_position = target.global_position
	slice.combat_runtime._update_projectiles(0.0)


func _offer_and_choose(slice: FoldlightEndlessSliceRuntime, completion_index: int, reward_id: StringName) -> bool:
	slice.controller._on_objective_completed({"completion_count": completion_index + 1, "title": "奖励契约"})
	await _wait_for_reward_input(slice)
	var options := slice.controller.get_pending_mission_rewards()
	for index in options.size():
		if StringName(options[index].get("id", &"")) == reward_id:
			slice._activate_modal_choice(index)
			return int((slice.controller.evolution.get_mission_snapshot().get("reward_levels", {}) as Dictionary).get(reward_id, 0)) == 1
	return false


func _wait_for_reward_input(slice: FoldlightEndlessSliceRuntime) -> void:
	for frame in 180:
		if not slice.modal_buttons[0].disabled:
			return
		await create_timer(0.02).timeout


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
		var destination := slice.player.global_position + direction * 430.0
		if slice.controller.map_definition.bounds.grow(-40.0).has_point(destination) and slice.controller.map_runtime.has_line_of_sight(slice.player.global_position, destination, 8.0):
			return direction
	_check(false, "authored harbor exposes a clear 430-pixel automatic-weapon lane")
	return Vector2.RIGHT


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
