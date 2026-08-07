extends SceneTree

## 3.0 run-build contract: six readable weapon identities, one replaceable
## active slot, and deterministic legal three-choice drafts over 36 upgrades.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FoldlightRogueContentCatalog.WEAPONS.size() >= 6, "run catalog ships at least six automatic weapons")
	_check(FoldlightRogueContentCatalog.ACTIVE_ITEMS.size() >= 6, "run catalog ships at least six active items")
	_check(FoldlightRogueContentCatalog.UPGRADES.size() >= 36, "run catalog ships at least thirty-six upgrades")
	_check(FoldlightRogueContentCatalog.validation_errors().is_empty(), "expanded run catalog passes IDs, references, and typed resource validation")
	var projectile_styles: Dictionary = {}
	for weapon in FoldlightRogueContentCatalog.WEAPONS:
		projectile_styles[weapon.projectile_style] = true
	_check(projectile_styles.size() >= 6, "each shipped automatic weapon has a distinct projectile behavior key")
	var active_effects: Dictionary = {}
	for active_item in FoldlightRogueContentCatalog.ACTIVE_ITEMS:
		active_effects[active_item.effect_id] = true
	_check(active_effects.size() >= 6, "each shipped active item has a distinct explicit effect")
	_check(FoldlightRogueUnlockCatalog.validation_errors().is_empty(), "horizontal unlock schedule references every shipped content ID exactly through the catalog")

	var director := FoldlightRewardDirector.new()
	root.add_child(director)
	var all_upgrade_ids: Array[StringName] = []
	for upgrade in FoldlightRogueContentCatalog.UPGRADES:
		all_upgrade_ids.append(upgrade.content_id)
	var draft_a := director.draft_upgrades(808031, 7, {}, all_upgrade_ids, 3)
	var draft_b := director.draft_upgrades(808031, 7, {}, all_upgrade_ids, 3)
	_check(draft_a == draft_b, "same run seed and room index reproduce the exact reward draft")
	_check(draft_a.size() == 3 and _unique_choice_ids(draft_a).size() == 3, "reward room offers three distinct upgrade choices")
	_check(draft_a.all(func(choice: Dictionary) -> bool: return choice.has("title") and choice.has("next_level") and choice.has("stat_modifiers")), "draft snapshots contain all UI-facing preview data")

	var locked_owned := {"steady_lantern": 4, "large_burden": 1}
	var legal := director.legal_upgrade_ids(locked_owned, all_upgrade_ids)
	_check(not legal.has(&"steady_lantern"), "max-stack upgrades leave the legal pool")
	_check(not legal.has(&"tiny_silhouette"), "an owned exclusion removes its opposite size modifier")
	_check(not legal.has(&"paper_storm"), "an unmet prerequisite stays out of the legal pool")
	locked_owned.erase("large_burden")
	locked_owned["rapid_crease"] = 1
	legal = director.legal_upgrade_ids(locked_owned, all_upgrade_ids)
	_check(legal.has(&"paper_storm"), "meeting a prerequisite makes its capstone eligible")

	var tiny_stats := FoldlightBuildResolver.aggregate_stats({"tiny_silhouette": 1})
	var large_stats := FoldlightBuildResolver.aggregate_stats({"large_burden": 1})
	_check(is_equal_approx(float(tiny_stats.get("body_size_multiplier", 1.0)), 0.82), "tiny upgrade explicitly reduces both presented and physical body size")
	_check(is_equal_approx(float(large_stats.get("body_size_multiplier", 1.0)), 1.22), "large curse explicitly increases body size")
	_check(float(large_stats.get("weapon_damage_multiplier", 1.0)) > 1.0, "large curse advertises a real upside in exchange for its hitbox cost")
	var stacked_stats := FoldlightBuildResolver.aggregate_stats({"steady_lantern": 2, "swift_wing": 2, "wide_return": 2})
	_check(float(stacked_stats.get("weapon_interval_multiplier", 1.0)) < 0.78 and float(stacked_stats.get("dash_cooldown_multiplier", 1.0)) < 0.82, "multiplicative stacks aggregate on demand rather than mutating definitions")
	_check(int(stacked_stats.get("capture_capacity", 0)) == 2, "additive capacity stacks aggregate exactly")

	var run_state := FoldlightRogueRunState.new()
	root.add_child(run_state)
	var route_generator := FoldlightRogueRouteGenerator.new()
	root.add_child(route_generator)
	var route := route_generator.generate_route(808031, FoldlightRogueContentCatalog.REGIONS)
	run_state.begin_run(808031, route)
	_check(director.apply_upgrade_choice(run_state, &"steady_lantern"), "legal reward applies through RunState IDs and levels")
	run_state.upgrade_levels["steady_lantern"] = 4
	_check(not director.apply_upgrade_choice(run_state, &"steady_lantern"), "reward application refuses a definition's maximum stack")

	var active_slot := FoldlightActiveItemSlot.new()
	root.add_child(active_slot)
	active_slot.enabled = true
	var starter := FoldlightRogueContentCatalog.active_item_by_id(&"paper_burst")
	var replacement := FoldlightRogueContentCatalog.active_item_by_id(&"mirror_step")
	_check(active_slot.equip(starter), "single active slot equips its starter item")
	var previous := active_slot.replace(replacement)
	_check(previous == starter and active_slot.definition == replacement, "active replacement returns the discarded item and keeps exactly one slot")

	var player_scene := load("res://scenes/player.tscn") as PackedScene
	var player := player_scene.instantiate() as FoldlightPlayer
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	var applied := player.apply_roguelite_build({"steady_lantern": 2, "swift_wing": 2, "wide_return": 2, "tiny_silhouette": 1, "thick_paper": 1})
	_check(player.get_capture_capacity() == 10 and is_equal_approx(player.hit_radius, 13.0 * 0.82), "resolved build adds two Wide Return stacks to the eight-light base and keeps honest player collision")
	_check(player.max_health == 6 and player.dash_component.cooldown_multiplier < 0.82, "resolved build reaches survival and dash components")
	var shot := player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern"))
	_check(float(shot.get("fire_interval", 1.0)) < 0.43 and float(applied.get("body_size_multiplier", 1.0)) == 0.82, "resolved build reaches automatic-weapon cadence without mutating its Resource")

	var profile_manager := FoldlightProfileManager.new()
	profile_manager.persistence_enabled = false
	root.add_child(profile_manager)
	profile_manager.profile = profile_manager._migrate_profile({"version": 5, "meta_upgrades": {"lantern_frame": 2}})
	var starter_profile := profile_manager.get_roguelite_snapshot()
	_check((starter_profile.get("unlocked_upgrades", []) as Array).size() == 12, "fresh profile starts with a varied draft pool instead of permanent power")
	var classic_meta_before := (profile_manager.profile.get("meta_upgrades", {}) as Dictionary).duplicate(true)
	profile_manager.record_roguelite_run({"won": false, "region": 1, "rooms": 4}, false)
	profile_manager.record_roguelite_run({"won": false, "region": 2, "rooms": 9}, false)
	profile_manager.record_roguelite_run({"won": true, "region": 3, "rooms": 18, "time": 2100.0}, false)
	var mature_profile := profile_manager.get_roguelite_snapshot()
	_check((mature_profile.get("unlocked_weapons", []) as Array).size() == 6 and (mature_profile.get("unlocked_active_items", []) as Array).size() == 6, "play milestones unlock horizontal weapon and active choices")
	_check((mature_profile.get("unlocked_upgrades", []) as Array).size() == 36, "three runs reaching victory expose the complete in-run upgrade pool")
	_check(profile_manager.profile.get("meta_upgrades", {}) == classic_meta_before, "roguelite completion never increases Classic's permanent combat stats")

	director.queue_free()
	run_state.queue_free()
	route_generator.queue_free()
	active_slot.queue_free()
	player.queue_free()
	profile_manager.queue_free()
	await process_frame
	_finish()


func _unique_choice_ids(choices: Array[Dictionary]) -> Dictionary:
	var ids: Dictionary = {}
	for choice in choices:
		ids[StringName(choice.get("content_id", &""))] = true
	return ids


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_RUN_BUILD_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_RUN_BUILD_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
