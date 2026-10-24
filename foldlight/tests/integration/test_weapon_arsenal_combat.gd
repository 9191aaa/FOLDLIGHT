extends SceneTree

## Real weapon emission, flight, collision and mode-independent combat clocks.
const STEP: float = 1.0 / 60.0
const ORIGIN := Vector2(1300, 1050)
var _failures: Array[String] = []
var _world: FoldlightRogueWorld
var _player: FoldlightPlayer
var _combat: FoldlightRogueCombatRuntime


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_world = load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	_player = load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(_world)
	root.add_child(_player)
	await process_frame
	_player.configure_roguelite_combat(true)
	_player.set_play_enabled(true)
	_world.load_room(_player, &"arsenal_flight", Vector2(2880, 1620), [], Color.WHITE, 63171)
	_world.activate()
	_combat = _world.combat_runtime
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_test_inventory_and_cadence()
	_test_lamp_tracking()
	_test_orbit_needle()
	_test_returning_gull()
	_test_bell_pulse()
	_test_prism_fan()
	_test_sun_execution()
	_test_armored_targets()
	_test_resonance_and_pause()
	_test_arsenal_object_budget()
	_world.queue_free()
	_player.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_WEAPON_ARSENAL_COMBAT: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _reset(weapon_id: StringName = &"crease_lantern", level: int = 1) -> void:
	_combat.clear_combat()
	_player.global_position = ORIGIN
	_player.velocity = Vector2.ZERO
	_player.weapon_mount.unequip_all()
	_player.weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(weapon_id), level)
	_combat.apply_run_build({})
	_combat.set_active(true)
	_combat.set_physics_process(false)


func _enemy(position: Vector2, enemy_id: StringName = &"drifter", health: float = 100.0) -> Node2D:
	var actor := _combat._spawn_enemy_from_entry({"enemy_id": enemy_id, "spawn_position": position}, false)
	actor.set("health", health)
	return actor


func _fire(weapon_id: StringName) -> void:
	var shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(weapon_id))
	_player.tick_automatic_weapons(float(shot["fire_interval"]) + 0.001, true)


func _fly(seconds: float) -> void:
	for _frame in ceili(seconds / STEP):
		_combat._update_projectiles(STEP)


func _test_inventory_and_cadence() -> void:
	_reset()
	_enemy(ORIGIN + Vector2.UP * 350.0)
	_player.tick_automatic_weapons(0.40, true)
	_player.weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern"), 3)
	_player.tick_automatic_weapons(0.14, true)
	_check(_combat.projectiles.size() == 1, "upgrading an already charging lamp preserves its shot progress")
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		_player.weapon_mount.equip(definition, 5)
	_check(_player.weapon_mount.get_inventory_snapshot().size() == 6 and _player.weapon_mount.definitions.size() == 6, "all six chosen weapons coexist without duplicate mounts")
	var source := FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern")
	_check(is_equal_approx(source.base_damage, 1.0) and source.volley_count == 1, "ranks do not mutate shared authored weapon resources")
	_player.weapon_mount.unequip_all()
	_check(_player.weapon_mount.get_inventory_snapshot().is_empty(), "clearing the mount produces an honestly empty inventory")


func _test_lamp_tracking() -> void:
	_reset()
	var target := _enemy(ORIGIN + Vector2.UP * 430.0)
	_fire(&"crease_lantern")
	_fly(0.12)
	target.global_position += Vector2.RIGHT * 85.0
	_fly(0.8)
	_check(float(target.get("health")) < 100.0, "starter lamp follows a target that moves after launch")


func _test_orbit_needle() -> void:
	_reset(&"needle_orbit", 3)
	var target := _enemy(ORIGIN + Vector2.UP * 350.0)
	_fire(&"needle_orbit")
	_check(_combat.projectiles.size() == 2, "rank three needle launches two actual orbiting needles")
	_fly(0.30)
	_player.global_position += Vector2.RIGHT * 90.0
	_fly(STEP)
	var all_orbiting := true
	for projectile in _combat.projectiles:
		all_orbiting = all_orbiting and projectile.launch_delay > 0.0 and projectile.global_position.distance_to(_player.global_position) < 83.0
	_check(all_orbiting and is_equal_approx(float(target.get("health")), 100.0), "needles follow the moving player during their visible orbit before seeking")
	_fly(1.4)
	_check(float(target.get("health")) < 98.5, "both orbiting needles subsequently seek and damage the distant target")


func _test_returning_gull() -> void:
	_reset(&"returning_gull", 3)
	var target := _enemy(ORIGIN + Vector2.UP * 230.0)
	_fire(&"returning_gull")
	_fly(0.40)
	var outward_damage := 100.0 - float(target.get("health"))
	_check(outward_damage > 1.8 and outward_damage < 1.9, "gull strikes exactly once on its outward leg")
	_fly(0.95)
	var total_damage := 100.0 - float(target.get("health"))
	_check(absf(total_damage - outward_damage * 2.35) < 0.01, "rank three gull hits once more on return with its 35 percent return bonus")
	_check(_combat.projectiles.is_empty(), "returned gull is collected at the player instead of lingering behind them")
	_reset(&"returning_gull", 3)
	var edge_target := _enemy(ORIGIN + Vector2.UP * 440.0)
	_fire(&"returning_gull")
	_fly(0.60)
	var edge_outward := 100.0 - float(edge_target.get("health"))
	_check(edge_outward > 1.8 and edge_outward < 1.9, "gull genuinely reaches a stationary enemy at its 440-pixel targeting edge")
	_fly(0.95)
	_check(absf(100.0 - float(edge_target.get("health")) - edge_outward * 2.35) < 0.01 and _combat.projectiles.is_empty(), "edge-range gull still hits exactly once per leg and returns to its player")


func _test_bell_pulse() -> void:
	_reset(&"tide_bell", 5)
	var primary := _enemy(ORIGIN + Vector2.UP * 410.0)
	var nearby := _enemy(primary.global_position + Vector2.RIGHT * 130.0)
	var outside := _enemy(primary.global_position + Vector2.RIGHT * 320.0)
	# A fixed selected landing point isolates the range assertion from RANDOM
	# targeting while retaining the actual mount snapshot and emitted missile.
	var shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"tide_bell"))
	shot["targeting"] = FoldlightRogueWeaponDefinition.TargetingMode.NEAREST
	shot["projectile_echo_chance"] = 0.75
	_combat._on_player_shot_requested(shot)
	_fly(1.4)
	var expected := float(shot["damage"])
	_check(absf(100.0 - float(primary.get("health")) - expected) < 0.01 and absf(100.0 - float(nearby.get("health")) - expected) < 0.01, "mastered bell pulse damages both nearby actors once each")
	_check(is_equal_approx(float(outside.get("health")), 100.0) and _combat.projectiles.is_empty(), "bell respects its radius and never recursively mints explosive echoes")
	_check(not _combat._active_flashes.is_empty() and float(_combat._active_flashes[-1]["radius"]) > 180.0, "bell hit leaves a visible pulse matching the authored damage radius")
	_reset(&"tide_bell")
	var moving_target := _enemy(ORIGIN + Vector2.UP * 350.0)
	_fire(&"tide_bell")
	moving_target.global_position += Vector2.RIGHT * 400.0
	_fly(1.4)
	_check(_combat.projectiles.is_empty() and not _combat._active_flashes.is_empty(), "bell still detonates at its landing point if its selected target has moved")
	_reset(&"tide_bell")
	_combat.apply_run_build({"hunter_mark": 1})
	var healthy := _enemy(ORIGIN + Vector2.UP * 310.0, &"fan", 100.0)
	var injured := _enemy(healthy.global_position + Vector2.RIGHT * 70.0, &"paper_turret")
	var maximum_health := float((injured.call("get_combat_snapshot") as Dictionary)["maximum_health"])
	injured.set("health", maximum_health * 0.3)
	var injured_before := float(injured.get("health"))
	var execution_shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"tide_bell"))
	execution_shot["targeting"] = FoldlightRogueWeaponDefinition.TargetingMode.NEAREST
	_combat._on_player_shot_requested(execution_shot)
	_fly(1.0)
	var base_damage := float(execution_shot["damage"])
	_check(absf(100.0 - float(healthy.get("health")) - base_damage) < 0.01 and absf(injured_before - float(injured.get("health")) - base_damage * 1.25) < 0.01, "one bell pulse applies Hunter Mark separately: normal damage to healthy targets and 25 percent more to injured targets")
	var before_active := float(injured.get("health"))
	_combat._damage_enemies_in_radius(injured.global_position, 20.0, 0.25)
	_check(absf(before_active - float(injured.get("health")) - 0.25) < 0.01, "ordinary area effects keep their default damage without inheriting weapon execution bonuses")


func _test_prism_fan() -> void:
	_reset(&"prism_fan")
	var target := _enemy(ORIGIN + Vector2.UP * 95.0)
	_fire(&"prism_fan")
	_check(_combat.projectiles.size() == 3, "prism fan emits three distinct close-range lanes")
	_fly(0.65)
	_check(absf(100.0 - float(target.get("health")) - 2.34) < 0.01, "moving close permits all three fan blades to connect")
	_reset(&"prism_fan", 5)
	_enemy(ORIGIN + Vector2.UP * 600.0)
	_fire(&"prism_fan")
	_check(_combat.projectiles.is_empty(), "fan does not waste its limited flight range on unreachable distant targets")


func _test_sun_execution() -> void:
	_reset(&"sun_thread", 5)
	var injured := _enemy(ORIGIN + Vector2.UP * 170.0, &"drifter", 2.0)
	var behind := _enemy(ORIGIN + Vector2.UP * 270.0)
	var outer := _enemy(ORIGIN + Vector2.UP * 390.0)
	_fire(&"sun_thread")
	_fly(0.55)
	_check(float(injured.get("health")) <= 0.0 and float(behind.get("health")) < 100.0 and float(outer.get("health")) < 100.0, "sun thread selects the weak enemy and pierces the remaining line")
	_reset(&"sun_thread", 5)
	var boss := _combat._spawn_enemy_from_entry({"boss_id": &"reef_crown_battery", "spawn_position": ORIGIN + Vector2.UP * 300.0}, false) as FoldlightRogueBossActor
	boss.health = boss.definition.base_health * 0.2
	var before := boss.health
	var shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"sun_thread"))
	_combat._on_player_shot_requested(shot)
	_fly(0.50)
	_check(absf(before - boss.health - float(shot["damage"]) * 1.8) < 0.01 and is_zero_approx(boss.return_meter), "mastered sun execution scales low-health damage without counterfeiting a boss return window")


func _test_armored_targets() -> void:
	_reset(&"tide_bell", 5)
	var elite := _enemy(ORIGIN + Vector2.UP * 280.0, &"shutter_seraph") as FoldlightShutterSeraph
	_fire(&"tide_bell")
	_fly(1.0)
	_check(is_equal_approx(elite.health, 100.0), "bell area damage cannot bypass the elite's closed armor")
	elite.phase = FoldlightShutterSeraph.Phase.FIRING
	_fire(&"tide_bell")
	_fly(1.0)
	_check(elite.health < 100.0, "the same bell can damage the elite during its attack window")
	_reset(&"tide_bell")
	var bulwark := _enemy(ORIGIN + Vector2.UP * 280.0, &"prism_bulwark") as FoldlightPrismBulwark
	bulwark.facing_direction = Vector2.DOWN
	_fire(&"tide_bell")
	_fly(1.0)
	_check(bulwark.prism_active and 100.0 - bulwark.health < 2.0, "bell preserves directional shield reduction and does not count as shield-breaking return light")


func _test_resonance_and_pause() -> void:
	_reset()
	_enemy(ORIGIN + Vector2.UP * 600.0)
	_combat._on_player_fold_released(0, 1.0)
	_check(int(_player.weapon_mount.get_resonance_snapshot()["charge"]) == 0, "empty release grants no resonance")
	_combat._on_player_fold_released(6, 1.0)
	_check(int(_player.weapon_mount.get_resonance_snapshot()["charge"]) == 6, "actual returned shots accumulate toward the eight-shot threshold")
	_combat._on_player_fold_released(2, 1.0)
	var state := _player.weapon_mount.get_resonance_snapshot()
	_check(bool(state["active"]) and is_equal_approx(float(state["remaining"]), 3.0), "eight returned shots activate a three-second arsenal resonance")
	var shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern"))
	_check(is_equal_approx(float(shot["damage"]), 1.2), "resonance strengthens newly emitted shots by twenty percent")
	var shots_before := _combat.projectiles.size()
	_player.tick_automatic_weapons(0.47, true)
	_check(_combat.projectiles.size() == shots_before + 1, "resonance releases a 0.55-second lamp shot within 0.47 seconds")
	_combat.set_active(false)
	_combat._physics_process(10.0)
	_check(is_equal_approx(float(_player.weapon_mount.get_resonance_snapshot()["remaining"]), 3.0), "paused combat freezes resonance rather than consuming it behind a menu")
	_combat.set_active(true)
	_combat.set_physics_process(false)
	_combat._physics_process(0.5)
	_combat._on_player_fold_released(8, 1.0)
	_check(is_equal_approx(float(_player.weapon_mount.get_resonance_snapshot()["remaining"]), 2.5), "further full releases cannot stack or refresh an active resonance")
	_combat.clear_combat()
	state = _player.weapon_mount.get_resonance_snapshot()
	_check(not bool(state["active"]) and int(state["charge"]) == 0, "changing rooms clears transient resonance and charge")


func _test_arsenal_object_budget() -> void:
	_reset()
	_enemy(ORIGIN + Vector2.UP * 220.0)
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		_player.weapon_mount.equip(definition, 5)
	for index in 190:
		_combat._spawn_projectile({"origin": Vector2(100 + index, 200), "velocity": Vector2.ZERO, "hostile": true, "lifetime": 8.0})
	for _wave in 30:
		for definition in _player.weapon_mount.definitions:
			_combat._on_player_shot_requested(_player.weapon_mount.make_shot_snapshot(definition))
	var hostile_count := 0
	var automatic_count := 0
	var counts: Dictionary = {}
	for projectile in _combat.projectiles:
		if projectile.hostile:
			hostile_count += 1
		if not projectile.automatic_weapon_id.is_empty():
			automatic_count += 1
			counts[projectile.automatic_weapon_id] = int(counts.get(projectile.automatic_weapon_id, 0)) + 1
	_check(hostile_count == 190 and automatic_count <= 64 and _combat.projectiles.size() <= 260, "all-six mastered arsenal stays bounded without deleting hostile bullets")
	var per_weapon_bounded := true
	for count in counts.values():
		per_weapon_bounded = per_weapon_bounded and int(count) <= 16
	_check(counts.size() == 6 and per_weapon_bounded, "every weapon remains represented under a per-weapon projectile ceiling")


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
	print(("[PASS] " if condition else "[FAIL] ") + label)
