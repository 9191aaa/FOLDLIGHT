extends SceneTree

## The real player -> boss birth copy -> phase scheduler -> combat runtime ->
## projectile chain. This deliberately does not depend on mirror fold syncing.
const STEP: float = 1.0 / 60.0
const ORIGIN := Vector2(1400, 1000)
const LEVELS := {"crease_lantern": 2, "needle_orbit": 3, "returning_gull": 5, "tide_bell": 5, "prism_fan": 3, "sun_thread": 5}
var _world: FoldlightRogueWorld
var _player: FoldlightPlayer
var _combat: FoldlightRogueCombatRuntime
var _boss: FoldlightRogueBossActor
var _expected: Dictionary = {}
var _first_projectiles: Dictionary = {}
var _first_volleys: Dictionary = {}
var _created: Dictionary = {}
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	_world = load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	_player = load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(_world)
	root.add_child(_player)
	await process_frame
	_player.configure_roguelite_combat(true)
	_player.set_play_enabled(true)
	_player.set_debug_invincible(true)
	_check(_world.load_room(_player, &"mirror_six_weapon_contract", Vector2(3600, 2400), [], Color.WHITE, 319101).is_empty(), "six-weapon fixture binds the real world and combat runtime")
	_world.activate()
	_combat = _world.combat_runtime
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_combat.set_physics_process(false)
	_player.global_position = ORIGIN
	_player.active_item_slot.unequip()
	_player.weapon_mount.set_weapon_levels(LEVELS)
	_player.weapon_mount.configure_build({
		"weapon_damage_multiplier": 1.4, "weapon_interval_multiplier": 0.72,
		"projectile_speed_multiplier": 1.1, "weapon_volley_add": 1,
		"projectile_pierce_add": 1, "projectile_size_multiplier": 1.2,
		"critical_chance": 0.2, "projectile_echo_chance": 0.15,
		"execute_damage_multiplier": 1.25,
	})
	var birth := _player.get_mirror_build_snapshot()
	_check(birth.weapons.size() == 6 and birth.weapon_levels == LEVELS, "actual player snapshot contains all six held weapons with their different real levels")
	for shot: Dictionary in birth.weapons:
		_expected[StringName(shot.weapon_id)] = shot.duplicate(true)
	_boss = _combat._spawn_enemy_from_entry({"boss_id": &"mirror_moth", "spawn_position": ORIGIN + Vector2(270, 0), "boss_options": {"endless_roam": true, "arena_pressure": false}}, false) as FoldlightRogueBossActor
	_check(_boss != null and _boss.has_method("get_mirror_snapshot"), "production spawn wiring creates the mirror subclass")
	if _boss == null:
		await _finish()
		return
	_boss.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var copied: Dictionary = _boss.call("get_mirror_snapshot")
	_check(copied.weapons == birth.weapons and copied.build.weapon_levels == LEVELS, "runtime birth wiring preserves all resolved weapon parameters, not merely the starter ID")
	_check(copied.build.provenance.source == "actual_player_components" and copied.build.provenance.boss_actor_id == String(_boss.actor_id), "the copy is tied to the actual player and spawned boss identity")
	_combat.projectile_spawned.connect(_record_projectile)
	_boss.volley_requested.connect(_record_volley)
	# Change the source after birth; the existing mirror must keep its original
	# six-weapon identity while a later mirror sees the new one-weapon build.
	_player.weapon_mount.set_weapon_levels({"sun_thread": 1})
	_player.weapon_mount.configure_build({})
	_player.weapon_mount.enabled = false
	_check(_boss.call("get_mirror_snapshot").weapons == birth.weapons, "later player inventory and stat changes cannot rewrite an existing mirror")

	# Leave INTRO/TELEGRAPH/ATTACK/RECOVERY untouched. A direct _emit helper
	# would hide a scheduler that never lets one of the copied weapons fire.
	var states: Dictionary = {}
	var peak_projectiles := 0
	for frame in 1080:
		_combat._update_enemies(STEP)
		_combat._update_projectiles(STEP)
		_combat._update_mirror_fields(STEP)
		states[_boss.phase_controller.state] = true
		peak_projectiles = maxi(peak_projectiles, _combat.projectiles.size())
	_check(states.has(FoldlightBossPhaseController.State.TELEGRAPH) and states.has(FoldlightBossPhaseController.State.ATTACK) and states.has(FoldlightBossPhaseController.State.RECOVERY), "the unmodified boss scheduler reaches warnings, attack windows and recoveries")
	for key: String in LEVELS:
		var id := StringName(key)
		_check(int(_created.get(id, 0)) > 0, "%s creates real hostile projectiles during natural attack windows" % key)
	_check(_first_projectiles.size() == 6 and _first_volleys.size() == 6, "all six emitted weapon identities survive the runtime projectile creation path")
	_check(peak_projectiles <= FoldlightRogueCombatRuntime.MAX_PROJECTILES, "natural copied arsenal stays within the shared projectile budget")
	if _first_projectiles.size() == 6 and _first_volleys.size() == 6:
		_check_projectile_contracts()
	print("MIRROR_ARSENAL_NATURAL_COUNTS: ", JSON.stringify(_created), " peak_projectiles=", peak_projectiles)
	_test_pause_and_budget()
	await _test_later_birth()
	await _finish()


func _record_projectile(projectile: FoldlightRogueProjectile) -> void:
	if _boss == null or projectile.boss_source != _boss.actor_id or projectile.automatic_weapon_id.is_empty():
		return
	var id := projectile.automatic_weapon_id
	_created[id] = int(_created.get(id, 0)) + 1
	if _first_projectiles.has(id): return
	_first_projectiles[id] = {
		"style": projectile.style, "hostile": projectile.hostile, "reflectable": projectile.reflectable,
		"damage": projectile.damage, "speed": projectile.velocity.length(), "radius": projectile.radius,
		"pierce": projectile.pierce_remaining, "echo_chance": projectile.echo_chance,
		"execute_multiplier": projectile.execute_damage_multiplier,
		"homing_target": projectile.homing_target, "homing_duration": projectile.homing_duration,
		"launch_delay": projectile.launch_delay, "orbit_anchor": projectile.orbit_anchor, "orbit_radius": projectile.orbit_radius,
		"return_anchor": projectile.return_anchor, "return_after": projectile.return_after, "return_multiplier": projectile.return_damage_multiplier,
		"area_radius": projectile.area_radius, "lifetime": projectile.lifetime,
	}


func _record_volley(snapshot: Dictionary) -> void:
	var id := StringName(snapshot.get("weapon_id", &""))
	if not id.is_empty() and not _first_volleys.has(id):
		_first_volleys[id] = snapshot.duplicate(true)


func _check_projectile_contracts() -> void:
	for key: String in LEVELS:
		var id := StringName(key)
		var shot: Dictionary = _first_projectiles[id]
		var volley: Dictionary = _first_volleys[id]
		var expected: Dictionary = _expected[id]
		_check(volley.weapon_level == expected.weapon_level and volley.projectiles.size() == expected.volley_count, "%s fires the copied level and upgraded volley count" % key)
		_check(shot.style == expected.projectile_style and is_equal_approx(shot.speed, expected.projectile_speed) and shot.pierce == expected.pierce and is_equal_approx(shot.radius, 7.0 * expected.projectile_size_multiplier), "%s instantiates its real style, speed, size and pierce" % key)
		_check(shot.hostile and shot.reflectable and shot.homing_target == _player and shot.damage == 1.0, "%s remains a recapturable enemy attack with one-heart hit damage" % key)
	var lamp: Dictionary = _first_projectiles[&"crease_lantern"]
	var needle: Dictionary = _first_projectiles[&"needle_orbit"]
	var gull: Dictionary = _first_projectiles[&"returning_gull"]
	var bell: Dictionary = _first_projectiles[&"tide_bell"]
	var fan: Dictionary = _first_projectiles[&"prism_fan"]
	var sun: Dictionary = _first_projectiles[&"sun_thread"]
	_check(is_equal_approx(lamp.homing_duration, 1.15), "copied lamp instantiates bounded tracking rather than a generic straight bullet")
	_check(needle.orbit_anchor == _boss and needle.orbit_radius > 0.0 and is_equal_approx(needle.launch_delay, 0.65), "copied needles instantiate a real orbit around their own mirror before launch")
	_check(gull.return_anchor == _boss and gull.return_after * gull.speed > float(_expected[&"returning_gull"].targeting_range) and is_equal_approx(gull.return_multiplier, 1.35), "copied gull keeps its own return anchor, enough outward distance and upgraded return multiplier")
	_check(is_equal_approx(bell.area_radius, 187.5) and is_zero_approx(bell.echo_chance), "copied level-five bell instantiates its larger nonrecursive area pulse")
	_check(is_equal_approx(fan.lifetime, 0.64) and _first_volleys[&"prism_fan"].projectiles.size() == 5, "copied level-three fan plus one volley upgrade becomes five short-range rays")
	_check(is_equal_approx(sun.execute_multiplier, float(_expected[&"sun_thread"].execute_damage_multiplier)) and sun.pierce == 5, "copied sun thread retains upgraded pierce and the actual execute metadata")


func _test_pause_and_budget() -> void:
	_combat.set_active(false)
	var frozen: Dictionary = _boss.call("get_mirror_snapshot")
	var created_before := _created.duplicate(true)
	_combat._physics_process(5.0)
	_check(_boss.call("get_mirror_snapshot") == frozen and _created == created_before, "paused runtime cannot consume copied weapon timers or create attacks")
	_combat.set_active(true)
	_combat.set_physics_process(false)
	for projectile in _combat.projectiles.duplicate(): _combat._remove_projectile(projectile)
	for index in FoldlightRogueCombatRuntime.MAX_PROJECTILES:
		_combat._spawn_projectile({"origin": Vector2(100, 100), "velocity": Vector2.ZERO, "hostile": true, "lifetime": 8.0})
	var crowded: Array = _combat.projectiles.duplicate()
	_boss.phase_controller.state = FoldlightBossPhaseController.State.ATTACK
	_boss.phase_controller.current_pattern = &"mirror_pressure"
	_boss.phase_controller._remaining = 100.0
	_boss.phase_controller._transition_remaining = 0.0
	_boss.global_position = ORIGIN + Vector2(270, 0)
	var timers: Dictionary = _boss.get("_weapon_timers")
	for key: Variant in timers: timers[key] = 0.0
	_combat._update_enemies(STEP)
	_check(_created == created_before and _combat.projectiles == crowded, "a full shared budget suppresses automatic fire without evicting existing attacks")
	for projectile in _combat.projectiles.duplicate(): _combat._remove_projectile(projectile)
	for frame in 150:
		_combat._update_enemies(STEP)
		_combat._update_projectiles(STEP)
	for key: String in LEVELS:
		var id := StringName(key)
		_check(int(_created.get(id, 0)) > int(created_before.get(id, 0)), "%s resumes real fire after temporary projectile saturation clears" % key)
	_check(_boss.call("get_mirror_snapshot").weapons.size() == 6, "projectile throttling cannot erase a copied weapon from the arsenal")


func _test_later_birth() -> void:
	var later := _combat._spawn_enemy_from_entry({"boss_id": &"mirror_moth", "spawn_position": ORIGIN + Vector2(600, 0), "boss_options": {"endless_roam": true, "arena_pressure": false}}, false) as FoldlightRogueBossActor
	_check(later != null, "another production mirror can capture a later player build")
	if later != null:
		var snapshot: Dictionary = later.call("get_mirror_snapshot")
		_check(snapshot.weapons.size() == 1 and snapshot.weapons[0].weapon_id == &"sun_thread" and snapshot.weapons[0].weapon_level == 1, "later birth copies the new exact inventory without inserting the starter weapon")
		_check(_boss.call("get_mirror_snapshot").weapons.size() == 6, "the original boss still owns its separate six-weapon birth copy")
	await process_frame


func _finish() -> void:
	_world.queue_free()
	_player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	await process_frame
	print("FOLDLIGHT_MIRROR_ARSENAL_3_19_1: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
