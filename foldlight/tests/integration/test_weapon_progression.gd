extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_inventory_and_rank_limits()
	_test_reward_draft()
	_test_independent_stats()
	if _failures.is_empty():
		print("FOLDLIGHT_WEAPON_PROGRESSION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_WEAPON_PROGRESSION: FAIL — %s" % ", ".join(_failures))
		quit(1)


func _test_inventory_and_rank_limits() -> void:
	var state := FoldlightRogueRunState.new()
	state.begin_run(313013, {"regions": [{"start_id": "r1_start"}]})
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		if definition.content_id != &"crease_lantern":
			_check(state.acquire_weapon(definition.content_id), "new weapon %s can join the arsenal" % definition.content_id)
	_check(state.weapon_ids.size() == FoldlightRogueContentCatalog.WEAPONS.size() and state.get_weapon_level(&"crease_lantern") == 1, "collecting every weapon preserves the starter and all previously chosen weapons")
	var previous_ids := state.weapon_ids.duplicate()
	for _rank in range(1, FoldlightWeaponProgression.MAX_LEVEL):
		_check(state.acquire_weapon(&"returning_gull"), "repeat choice strengthens the existing gull")
	_check(state.weapon_ids == previous_ids and state.get_weapon_level(&"returning_gull") == 5, "upgrades keep the arsenal order and never duplicate a weapon")
	var previous_levels := state.weapon_levels.duplicate(true)
	_check(not state.acquire_weapon(&"returning_gull") and not state.acquire_weapon(&"missing_weapon"), "full-rank and unknown weapon choices are rejected")
	_check(state.weapon_levels == previous_levels, "rejected acquisitions do not change any weapon level")
	var inventory := FoldlightWeaponProgression.inventory_snapshot(state.weapon_levels)
	_check(inventory.size() == 6 and inventory[2].has("role") and inventory[2].has("accent"), "arsenal presentation receives the complete named loadout and roles")
	inventory[0]["level"] = 999
	_check(state.get_weapon_level(&"crease_lantern") == 1, "presentation snapshots cannot mutate the run inventory")
	state.free()


func _test_reward_draft() -> void:
	var all_ids: Array[StringName] = []
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		all_ids.append(definition.content_id)
	var owned := {"crease_lantern": 1, "needle_orbit": 5}
	seed(771313)
	var expected_next_global := randi()
	seed(771313)
	var first := FoldlightWeaponProgression.draft_choices(313013, 7, owned, all_ids)
	_check(randi() == expected_next_global, "weapon drafting does not consume the global combat RNG")
	_check(first == FoldlightWeaponProgression.draft_choices(313013, 7, owned, all_ids), "same run seed and reward index reproduce the same choices")
	var distinct_drafts: Dictionary = {}
	for draft_index in 20:
		var choices := FoldlightWeaponProgression.draft_choices(313013, draft_index, owned, all_ids)
		var ids: Array[StringName] = []
		var has_new := false
		var has_upgrade := false
		for choice in choices:
			var weapon_id := StringName(choice["content_id"])
			ids.append(weapon_id)
			has_new = has_new or int(choice["next_level"]) == 1
			has_upgrade = has_upgrade or int(choice["next_level"]) > 1
		_check(choices.size() == 3 and has_new and has_upgrade and not ids.has(&"needle_orbit"), "reward %d offers new and upgrade paths without full-rank choices" % draft_index)
		_check(ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2], "reward %d never repeats a weapon card" % draft_index)
		distinct_drafts[str(ids)] = true
	_check(distinct_drafts.size() > 1, "different reward indices produce variety across a run")
	var locked := FoldlightWeaponProgression.draft_choices(313013, 3, {"crease_lantern": 1}, [&"crease_lantern"])
	_check(locked.size() == 1 and StringName(locked[0]["content_id"]) == &"crease_lantern", "unavailable new weapons stay out of the draft while owned ranks remain upgradeable")
	var all_full: Dictionary = {}
	for weapon_id in all_ids:
		all_full[String(weapon_id)] = 5
	_check(FoldlightWeaponProgression.draft_choices(313013, 9, all_full, all_ids).is_empty(), "fully mastered arsenal produces no dead-end weapon cards")
	_check(FoldlightWeaponProgression.make_choice(&"missing", 0).is_empty() and FoldlightWeaponProgression.make_choice(&"crease_lantern", 5).is_empty(), "invalid or already completed choices cannot be presented")
	var milestone := FoldlightWeaponProgression.make_choice(&"tide_bell", 2)
	_check(int(milestone["next_level"]) == 3 and String(milestone["description"]).contains("25%") and String(milestone["display_level"]).contains("Lv.2 → Lv.3"), "milestone cards describe the imminent gameplay change and exact rank")


func _test_independent_stats() -> void:
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		var original_damage := definition.base_damage
		var original_interval := definition.fire_interval
		var original_volley := definition.volley_count
		var original_pierce := definition.pierce
		var base := FoldlightWeaponProgression.level_stats(definition.content_id, 1)
		var middle := FoldlightWeaponProgression.level_stats(definition.content_id, 3)
		var mastered := FoldlightWeaponProgression.level_stats(definition.content_id, 5)
		_check(float(mastered["damage_multiplier"]) > float(middle["damage_multiplier"]) and float(middle["damage_multiplier"]) > float(base["damage_multiplier"]), "%s damage increases across ranks" % definition.content_id)
		_check(float(mastered["interval_multiplier"]) > 0.0 and float(mastered["interval_multiplier"]) < float(base["interval_multiplier"]), "%s cadence improves within a positive bound" % definition.content_id)
		mastered["damage_multiplier"] = 999.0
		_check(definition.base_damage == original_damage and definition.fire_interval == original_interval and definition.volley_count == original_volley and definition.pierce == original_pierce, "%s progression never mutates shared authored Resources" % definition.content_id)
		_check(float(FoldlightWeaponProgression.level_stats(definition.content_id, 5)["damage_multiplier"]) < 2.0, "%s stat snapshots are independent" % definition.content_id)
	_check(int(FoldlightWeaponProgression.level_stats(&"prism_fan", 5)["volley_bonus"]) == 2, "fan mastery adds two rays without unbounded projectile growth")
	_check(is_equal_approx(float(FoldlightWeaponProgression.level_stats(&"tide_bell", 5)["area_radius_multiplier"]), 1.5), "bell mastery widens the explosion instead of duplicating bursts")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
