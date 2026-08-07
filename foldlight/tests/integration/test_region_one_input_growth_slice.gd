extends SceneTree

## Region-one vertical-slice contract: combat input has a single owner and
## every ordinary three-choice draft contains a visible, immediately useful
## firepower option.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_has_physical_key(&"active_item", KEY_Q), "Q remains the roguelite active-item key")
	_check(not _has_physical_key(&"open_challenge", KEY_Q) and _has_physical_key(&"open_challenge", KEY_V), "classic challenge shortcut no longer shares Q")
	_check(_has_joy_button(&"active_item", JOY_BUTTON_X) and not _has_joy_button(&"open_archive", JOY_BUTTON_X), "gamepad X belongs only to the active item during combat")
	_check(_has_joy_button(&"dash", JOY_BUTTON_B) and not _has_joy_button(&"open_challenge", JOY_BUTTON_B), "gamepad B belongs only to dash during combat")
	_check(_has_joy_button(&"open_challenge", JOY_BUTTON_RIGHT_SHOULDER), "classic challenge keeps a non-conflicting controller shortcut")

	var reward_director := FoldlightRewardDirector.new()
	root.add_child(reward_director)
	var starter_ids: Array[StringName] = []
	for value in FoldlightRogueUnlockCatalog.STARTER_UPGRADES:
		starter_ids.append(StringName(value))
	for seed in range(9100, 9124):
		var draft := reward_director.draft_upgrades(seed, seed % 7, {}, starter_ids, 3)
		_check(draft.size() == 3 and draft.any(func(choice: Dictionary) -> bool: return bool(choice.get("offensive", false))), "starter draft %d guarantees a firepower card" % seed)

	var damage_upgrade := FoldlightRogueContentCatalog.upgrade_by_id(&"rapid_crease")
	var cadence_upgrade := FoldlightRogueContentCatalog.upgrade_by_id(&"steady_lantern")
	var volley_upgrade := FoldlightRogueContentCatalog.upgrade_by_id(&"twin_fold")
	_check(damage_upgrade != null and is_equal_approx(float(damage_upgrade.stat_modifiers.get("weapon_damage_multiplier", 0.0)), 1.25) and damage_upgrade.description.contains("×1.25"), "damage card exposes its strong exact multiplier")
	_check(cadence_upgrade != null and is_equal_approx(float(cadence_upgrade.stat_modifiers.get("weapon_interval_multiplier", 0.0)), 0.82) and cadence_upgrade.description.contains("×0.82"), "cadence card exposes its strong exact multiplier")
	_check(volley_upgrade != null and int(volley_upgrade.stat_modifiers.get("weapon_volley_add", 0)) == 1 and FoldlightRogueUnlockCatalog.STARTER_UPGRADES.has("twin_fold"), "multishot +1 is available during the first run")
	var resolved := FoldlightBuildResolver.aggregate_stats({"rapid_crease": 1, "steady_lantern": 1, "twin_fold": 1})
	var mount := FoldlightWeaponMount.new()
	root.add_child(mount)
	mount.configure_build(resolved)
	var base_weapon := FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern")
	var shot := mount.make_shot_snapshot(base_weapon)
	_check(is_equal_approx(float(shot.get("damage", 0.0)), base_weapon.base_damage * 1.25), "damage choice reaches the live automatic weapon snapshot")
	_check(is_equal_approx(float(shot.get("fire_interval", 0.0)), base_weapon.fire_interval * 0.82), "cadence choice reaches the live automatic weapon snapshot")
	_check(int(shot.get("volley_count", 0)) == base_weapon.volley_count + 1, "multishot choice adds one real projectile to every volley")

	var game_scene := load("res://scenes/main.tscn") as PackedScene
	var game := game_scene.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.get_node("RogueSession") as FoldlightRogueSessionController
	session.persist_profile = false
	session.start_new_run()
	await process_frame
	var all_active_ids: Array[String] = []
	for definition in FoldlightRogueContentCatalog.ACTIVE_ITEMS:
		all_active_ids.append(String(definition.content_id))
	var shop_choices := session._draft_room_reward(&"shop", {"unlocked_active_items": all_active_ids})
	_check(shop_choices.size() == 3 and shop_choices.any(func(choice: Dictionary) -> bool: return bool(choice.get("offensive", false))), "active-item shop also keeps one immediate offense option")
	session._enter_modal_safety()
	session.presentation.show_reward(reward_director.draft_upgrades(707, 0, {}, starter_ids, 3), "输入安全测试")
	var health_before := session.player.health
	var position_before := session.player.global_position
	var active_before := session.player.active_item_slot.cooldown_remaining
	Input.action_press(&"move_right")
	session.player._physics_process(0.2)
	Input.action_release(&"move_right")
	for action in [&"fold", &"dash", &"active_item"]:
		var event := _action_event(action)
		session._unhandled_input(event)
		session.player._unhandled_input(event)
	_check(session.player.global_position.is_equal_approx(position_before) and not session.player.folding, "reward modal blocks keyboard and stick movement plus Fold")
	_check(not session.player.dash_component.is_dashing() and is_equal_approx(session.player.active_item_slot.cooldown_remaining, active_before), "reward modal blocks dash and active item")
	_check(session.player.health == health_before and session.presentation.screen_kind == &"reward", "combat state remains intact while reward owns input")

	for legacy_action in [&"open_challenge", &"open_archive", &"menu_settings", &"open_tutorial"]:
		game._unhandled_input(_action_event(legacy_action))
	_check(bool(game.get("_rogue_mode_active")) and session.mode == FoldlightRogueSessionController.SessionMode.RUN and session.presentation.screen_kind == &"reward", "legacy shortcuts cannot tear down a roguelite modal")

	reward_director.queue_free()
	mount.queue_free()
	game.queue_free()
	await process_frame
	_finish()


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	return event


func _has_physical_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == key:
			return true
	return false


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_REGION_ONE_INPUT_GROWTH: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_REGION_ONE_INPUT_GROWTH: FAIL — %s" % ", ".join(_failures))
		quit(1)
