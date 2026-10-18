extends SceneTree

## Exercise the real combat wiring, not a stand-alone mirror actor: player
## weapon emission, absorption/removal, copied skill signals and source cleanup.
const ORIGIN := Vector2(1300, 1050)
var _world: FoldlightRogueWorld
var _player: FoldlightPlayer
var _combat: FoldlightRogueCombatRuntime
var _failures: Array[String] = []


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
	_world.load_room(_player, &"mirror_runtime", Vector2(2880, 1620), [], Color.WHITE, 31971)
	_world.activate()
	_combat = _world.combat_runtime
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_test_actual_capture_and_pause()
	_test_push_and_shield_conversion()
	_test_slow_and_decoy()
	_test_heal_and_haste()
	_test_successful_hit_echo()
	await _test_flying_bell_source_lifecycle()
	_test_source_cleanup_and_budget()
	_world.queue_free()
	_player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_MIRROR_RUNTIME_3_19: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _reset(skill: StringName = &"paper_burst", weapon_id: StringName = &"crease_lantern") -> FoldlightRogueBossActor:
	_combat.clear_combat()
	_player.reset_player()
	_player.set_play_enabled(true)
	_player.global_position = ORIGIN
	_player.active_item_slot.unequip()
	_player.active_item_slot.equip(FoldlightRogueContentCatalog.active_item_by_id(skill))
	_player.weapon_mount.unequip_all()
	_player.weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(weapon_id), 1)
	_combat.apply_run_build({})
	_combat.set_active(true)
	_combat.set_physics_process(false)
	var boss := _combat._spawn_enemy_from_entry({"boss_id": &"mirror_moth", "spawn_position": ORIGIN + Vector2(500, 0), "boss_options": {"endless_roam": true, "arena_pressure": false}}, false) as FoldlightRogueBossActor
	_check(boss != null and boss.has_method("get_mirror_snapshot"), "the shared runtime creates the actual mirror subclass")
	if boss == null:
		return null
	# This fixture advances combat manually while its scene has processing
	# disabled. Keep the real collision body in the physics space for movement.
	boss.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	# Freeze the unrelated phase scheduler so these checks isolate combat
	# plumbing, while still using the real actor's signal and hit contracts.
	boss.phase_controller.state = FoldlightBossPhaseController.State.RECOVERY
	boss.phase_controller._remaining = 1000.0
	boss.phase_controller._transition_remaining = 0.0
	boss.set("_active_remaining", 1000.0)
	# The real runtime supplies the target before any copied skill can begin.
	_combat._update_enemies(0.001)
	return boss


func _fire_player() -> FoldlightRogueProjectile:
	var before := _combat.projectiles.size()
	_player.tick_automatic_weapons(0.6, true)
	for index in range(before, _combat.projectiles.size()):
		if not _combat.projectiles[index].hostile:
			return _combat.projectiles[index]
	return null


func _test_actual_capture_and_pause() -> void:
	var boss := _reset()
	if boss == null: return
	var copied: Dictionary = boss.call("get_mirror_snapshot")
	_check(String(copied.build.provenance.source) == "actual_player_components" and String(copied.build.provenance.boss_actor_id) == String(boss.actor_id), "spawn copy records the real player component source and unique boss identity")
	var projectile := _fire_player()
	_check(projectile != null and not projectile.reflectable, "capture fixture uses a real non-reflectable player automatic shot")
	if projectile == null: return
	_check(_player.try_begin_fold(), "actual player fold action starts from shared controls")
	_combat._update_enemies(0.1)
	projectile.global_position = boss.global_position + Vector2(0, 30)
	var health_before := boss.health
	_combat._update_projectiles(0.0)
	copied = boss.call("get_mirror_snapshot")
	_check(copied.folding and copied.captured == 1 and boss.health == health_before and not _combat.projectiles.has(projectile), "live fold synchronization absorbs one real player shot without hurting the mirror")
	_combat._update_projectiles(0.0)
	_check(int(boss.call("get_mirror_snapshot").captured) == 1, "the removed shot cannot be captured twice by subsequent collision passes")
	_check(_player.release_fold_action(), "actual player release drives the mirrored release edge")
	_combat._update_enemies(0.1)
	var paused: Dictionary = boss.call("get_mirror_snapshot")
	_check(paused.release_remaining > 0.0 and _combat.projectiles.is_empty(), "release starts a warning before any hostile ammunition appears")
	_combat.set_active(false)
	_combat._physics_process(20.0)
	_check(boss.call("get_mirror_snapshot") == paused, "paused runtime preserves copied build, stored light, warning and cooldowns")
	_combat.set_active(true)
	_combat.set_physics_process(false)
	for step in 8:
		_combat._update_enemies(0.1)
	var returned := 0
	for shot in _combat.projectiles:
		if shot.hostile and shot.boss_source == boss.actor_id:
			returned += 1
			_check(shot.homing_target == _player and shot.homing_duration > 0.0 and shot.reflectable, "actual released shot pursues the player for a bounded interval and can be recaptured")
			_check(shot.style == &"mirror_return" and shot.get_visual_contract().motif == &"hostile_fold_petal", "actual returned clone shot uses hostile paper geometry rather than friendly gold return trails")
	_check(returned == 1 and int(boss.call("get_mirror_snapshot").captured) == 0, "one absorbed player projectile creates exactly one hostile return through the runtime")


func _test_push_and_shield_conversion() -> void:
	for skill in [&"paper_burst", &"crease_anchor"]:
		var boss := _reset(skill)
		if boss == null: continue
		boss.global_position = ORIGIN + Vector2(250, 0)
		var shot := _fire_player()
		_check(shot != null and not shot.reflectable, "%s receives actual player fire for conversion" % skill)
		boss.call("_begin_active")
		var health_before := _player.health
		_check(_combat._mirror_fields.size() == 1 and not _combat._mirror_fields[0].resolved, "%s creates an owned harmless warning field" % skill)
		for step in 8: _combat._update_mirror_fields(0.1)
		_check(not _combat._mirror_fields[0].resolved and _player.health == health_before, "field timer alone cannot resolve the copied skill ahead of its actor")
		boss.call("_resolve_active")
		var converted := 0
		for projectile in _combat.projectiles:
			if projectile.hostile and projectile.boss_source == boss.actor_id: converted += 1
		_check(shot != null and not _combat.projectiles.has(shot) and converted == 1, "%s converts real player fire despite its player-side non-reflectable flag" % skill)
		if skill == &"paper_burst":
			_check(_player.health == health_before - 1, "copied paper burst also damages a nearby player for exactly one heart")
			_player.invulnerability = 0.0
			boss.call("_resolve_active")
			_check(_player.health == health_before - 1, "replaying resolution cannot apply the near-field hit again")
		else:
			var boss_health := boss.health
			boss.take_damage(10.0)
			_check(boss.health == boss_health and int(boss.call("get_mirror_snapshot").shield_hits) == 3, "copied anchor absorbs a real incoming hit using one of its four shields")
	var distant := _reset(&"paper_burst")
	if distant != null:
		distant.call("_begin_active")
		var before := _player.health
		distant.call("_resolve_active")
		_check(_player.health == before, "moving beyond copied paper burst's announced near-field radius avoids the hit")


func _test_slow_and_decoy() -> void:
	var boss := _reset(&"tide_clock")
	if boss == null: return
	boss.call("_begin_active")
	boss.call("_resolve_active")
	_combat._update_mirror_fields(0.1)
	_check(is_equal_approx(_player.status_effects.get_move_multiplier(), 0.35), "copied tide clock slows the player inside its real locked field")
	var field := _combat._mirror_fields[0]
	var before := field.remaining
	_combat.set_active(false)
	_combat._physics_process(10.0)
	_check(field.remaining == before, "a paused combat runtime cannot consume an active mirror field")
	_combat.set_active(true)
	_combat.set_physics_process(false)
	_player.global_position += Vector2(500, 0)
	_player.status_effects.tick(0.3)
	_combat._update_mirror_fields(0.1)
	_check(is_equal_approx(_player.status_effects.get_move_multiplier(), 1.0), "leaving the locked field restores movement without a lingering slow")
	boss = _reset(&"mirror_step")
	if boss == null: return
	boss.call("_begin_active")
	boss.call("_resolve_active")
	field = _combat._mirror_fields[0]
	boss.global_position += Vector2(200, 0)
	var shot := _fire_player()
	_check(field.resolved and shot != null and shot.homing_target == field, "copied mirror-step decoy redirects an actual automatically aimed player shot")
	if shot != null:
		shot.global_position = field.global_position
		_combat._update_projectiles(0.0)
		_check(not _combat.projectiles.has(shot), "real decoy collision consumes the redirected projectile")


func _test_heal_and_haste() -> void:
	var boss := _reset(&"ink_wash")
	if boss == null: return
	boss.health -= 80.0
	boss.call("_begin_active")
	boss.call("_resolve_active")
	_check(boss.health == boss.maximum_health, "copied ink wash repairs a wounded spawned mirror without exceeding maximum health")
	var counts: Array[int] = []
	for boosted in [false, true]:
		boss = _reset(&"sun_stamp")
		if boss == null: return
		boss.phase_controller.state = FoldlightBossPhaseController.State.ATTACK
		if boosted:
			boss.call("_begin_active")
			boss.call("_resolve_active")
		for step in 10: _combat._update_enemies(0.1)
		var shots := 0
		for projectile in _combat.projectiles:
			if projectile.hostile and projectile.boss_source == boss.actor_id: shots += 1
		counts.append(shots)
	_check(counts[0] > 0 and counts[1] > counts[0], "copied sun stamp produces more real hostile weapon shots over the same combat interval")


func _test_successful_hit_echo() -> void:
	var boss := _reset()
	if boss == null: return
	var shot := _combat._spawn_projectile({"origin": ORIGIN, "velocity": Vector2(300, 0), "hostile": true, "boss_source": boss.actor_id, "style": &"crease_petal", "homing_duration": 1.0, "homing_turn_speed": 1.2})
	# Force the proc only in this collision fixture; production clamps the
	# player's real chance to 75%, which is covered by projectile stat checks.
	shot.echo_chance = 1.0
	var health_before := _player.health
	_combat._update_projectiles(0.0)
	_check(_player.health == health_before - 1 and _combat.projectiles.size() == 2, "a successful mirrored hit creates exactly two real echo children")
	if _combat.projectiles.size() == 2:
		var child := _combat.projectiles[0]
		var sibling := _combat.projectiles[1]
		_check(child.is_echo and sibling.is_echo and child.echo_chance == 0.0 and sibling.echo_chance == 0.0 and child.boss_source == boss.actor_id, "echo children retain ownership and carry no recursive proc chance")
		sibling.global_position = ORIGIN + Vector2(500, 200)
		child.echo_chance = 1.0
		_player.invulnerability = 0.0
		_combat._update_projectiles(0.0)
		_check(_player.health == health_before - 2 and _combat.projectiles.size() == 1 and _combat.projectiles[0] == sibling, "even a forcibly enabled child proc cannot recurse after a real successful hit")
	for protection in [&"invulnerability", &"shield"]:
		boss = _reset()
		if boss == null: continue
		shot = _combat._spawn_projectile({"origin": ORIGIN, "velocity": Vector2(300, 0), "hostile": true, "boss_source": boss.actor_id})
		shot.echo_chance = 1.0
		if protection == &"invulnerability":
			_player.invulnerability = 1.0
		else:
			_combat._shield_charges = 1
			_combat._shield_remaining = 5.0
		health_before = _player.health
		_combat._update_projectiles(0.0)
		_check(_player.health == health_before and _combat.projectiles.is_empty(), "%s blocks damage and therefore prevents a mirror echo proc" % protection)


func _test_flying_bell_source_lifecycle() -> void:
	var boss := _reset(&"paper_burst", &"tide_bell")
	if boss == null: return
	var copied: Dictionary = boss.call("get_mirror_snapshot")
	boss.call("_emit_mirror_weapon", copied.weapons[0])
	_check(_combat.projectiles.size() == 1 and _combat.projectiles[0].style == &"tide_bell" and _combat.projectiles[0].boss_source == boss.actor_id, "real copied bell emission creates one owned flying hostile projectile")
	if _combat.projectiles.is_empty(): return
	var bell := _combat.projectiles[0]
	var health_before := _player.health
	_combat._update_projectiles(0.05)
	_check(_combat.projectiles.has(bell) and _combat._mirror_fields.is_empty(), "a flying bell does not create its blast field before arrival")
	for step in 40:
		if not _combat.projectiles.has(bell): break
		_combat._update_projectiles(0.05)
	_check(not _combat.projectiles.has(bell) and _combat._mirror_fields.size() == 1 and _player.health == health_before, "a live mirror's arriving bell retires into one harmless blast warning")
	if _combat._mirror_fields.is_empty(): return
	var field := _combat._mirror_fields[0]
	_player.global_position = field.global_position
	_player.invulnerability = 0.0
	for step in 6: _combat._update_mirror_fields(0.1)
	_check(not field.resolved and _player.health == health_before, "bell warning protects the player for the first 0.6 seconds")
	_combat._update_mirror_fields(0.1)
	_check(field.resolved and field.damage_consumed and _player.health == health_before - 1, "completed bell warning causes exactly one shared one-heart hit")
	for step in 4:
		_player.invulnerability = 0.0
		_combat._update_mirror_fields(0.1)
	_check(_player.health == health_before - 1 and _combat._mirror_fields.is_empty(), "bell field cannot repeat damage even without mercy frames and expires normally")

	boss = _reset(&"paper_burst", &"tide_bell")
	if boss == null: return
	copied = boss.call("get_mirror_snapshot")
	boss.call("_emit_mirror_weapon", copied.weapons[0])
	if _combat.projectiles.is_empty():
		_check(false, "dead-source fixture starts with an actual flying bell")
		return
	bell = _combat.projectiles[0]
	_combat._update_projectiles(0.05)
	health_before = _player.health
	boss.take_damage(boss.maximum_health * 10.0)
	await process_frame
	_check(not is_instance_valid(boss) and _combat.projectiles.has(bell), "source actually frees while its previously emitted bell is still in flight")
	for step in 40:
		if not _combat.projectiles.has(bell): break
		_combat._update_projectiles(0.05)
	for step in 10: _combat._update_mirror_fields(0.1)
	_check(not _combat.projectiles.has(bell) and _combat._mirror_fields.is_empty() and _player.health == health_before, "an orphaned arriving bell cannot recreate its defeated source's hazard or damage the player")


func _test_source_cleanup_and_budget() -> void:
	var first := _reset(&"tide_clock")
	if first == null: return
	first.call("_begin_active")
	first.call("_resolve_active")
	var second := _combat._spawn_enemy_from_entry({"boss_id": &"mirror_moth", "spawn_position": ORIGIN + Vector2(700, 0)}, false) as FoldlightRogueBossActor
	second.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	second.phase_controller.state = FoldlightBossPhaseController.State.RECOVERY
	second.phase_controller._remaining = 1000.0
	second.set("_active_remaining", 1000.0)
	_combat._update_enemies(0.001)
	second.call("_begin_active")
	second.call("_resolve_active")
	_check(_combat._mirror_fields.size() == 2, "simultaneous mirrors create independently owned active fields")
	first.take_damage(first.maximum_health * 10.0)
	_check(_combat._mirror_fields.size() == 1 and _combat._mirror_fields[0].source_id == second.actor_id, "defeating one mirror removes only that source's field")
	for index in 30:
		_combat._create_mirror_field({"source_id": second.actor_id, "action": &"dash_decoy", "position": ORIGIN, "serial": index})
	_check(_combat._mirror_fields.size() == 24, "multiple copied skills share a bounded field budget")
	_combat.clear_combat()
	_check(_combat._mirror_fields.is_empty() and _combat.projectiles.is_empty() and _combat.enemies.is_empty(), "restart clears every mirror actor, projectile and owned field")


func _check(condition: bool, label: String) -> void:
	print(("[PASS] " if condition else "[FAIL] ") + label)
	if not condition: _failures.append(label)
