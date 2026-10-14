extends SceneTree

## Real 60 Hz projectile flight: adding a volley must preserve its aimed shot,
## and damage must use the actor's authored collision body.
const STEP: float = 1.0 / 60.0
const PLAYER_POSITION := Vector2(1440, 1180)

var _failures: Array[String] = []
var _world: FoldlightRogueWorld
var _player: FoldlightPlayer
var _combat: FoldlightRogueCombatRuntime


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(_world)
	root.add_child(_player)
	await process_frame
	_player.configure_roguelite_combat(true)
	_player.set_play_enabled(true)
	_player.global_position = PLAYER_POSITION
	_world.load_room(_player, &"volley_accuracy", Vector2(2880, 1620), [], Color.WHITE, 71903)
	_world.activate()
	_combat = _world.combat_runtime
	# Isolate flight geometry from AI motion; retain real actors, weapons,
	# projectile integration, collision resolution and damage signals.
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	for target_id in [&"reef_crown_battery", &"drifter", &"fan"]:
		for distance in [370.0, 620.0, 900.0]:
			var baseline := _fly_volley(target_id, distance, 0)
			_check(baseline >= 0.99, "%s at %.0f: starter shot reaches its target" % [target_id, distance])
			for level in [1, 2]:
				var upgraded := _fly_volley(target_id, distance, level)
				_check(upgraded + 0.001 >= baseline, "%s at %.0f: Twin Fold %d preserves starter damage (%.1f >= %.1f)" % [target_id, distance, level, upgraded, baseline])
	_check(_fly_offset(&"reef_crown_battery", 50.0) > 0.0, "projectile hits the boss's real 52-pixel body away from its center")
	_check(is_zero_approx(_fly_offset(&"reef_crown_battery", 61.0)), "projectile outside the boss body plus its own radius misses")
	_check(_fly_offset(&"fan", 38.0) > 0.0, "ordinary fan uses its authored 34-pixel body")
	_check(is_zero_approx(_fly_offset(&"fan", 44.0)), "ordinary fan is not enlarged beyond its authored body")
	_check(_fly_offset(&"drifter", 32.0) > 0.0, "small drifter preserves its honest 27-pixel body")
	_check(is_zero_approx(_fly_offset(&"drifter", 36.0)), "near miss outside small drifter remains a miss")
	_check(_fly_offset(&"bell_binder", 28.0) > 0.0, "dedicated support actor uses its 23-pixel collision shape")
	_check(is_zero_approx(_fly_offset(&"bell_binder", 33.0)), "support actor does not inherit a false 27-pixel hit radius")
	_test_extra_shot_coverage()
	_test_cancelled_boss_warnings()
	_world.queue_free()
	_player.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOLDLIGHT_WEAPON_VOLLEY_ACCURACY: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_WEAPON_VOLLEY_ACCURACY: FAIL - %s" % ", ".join(_failures))
		quit(1)


func _spawn_target(target_id: StringName, distance: float) -> Node2D:
	_combat.clear_combat()
	var entry := {"spawn_position": PLAYER_POSITION + Vector2.UP * distance}
	entry["boss_id" if FoldlightRogueContentCatalog.boss_by_id(target_id) != null else "enemy_id"] = target_id
	return _combat._spawn_enemy_from_entry(entry, false)


func _fly_volley(target_id: StringName, distance: float, twin_level: int) -> float:
	var target := _spawn_target(target_id, distance)
	_combat.apply_run_build({"twin_fold": twin_level})
	var health_before := float(target.get("health"))
	var shot := _player.weapon_mount.make_shot_snapshot(FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern"))
	_player.tick_automatic_weapons(float(shot.get("fire_interval", 0.55)) + 0.001, true)
	_advance_projectiles()
	return health_before - float(target.get("health"))


func _fly_offset(target_id: StringName, offset: float) -> float:
	var target := _spawn_target(target_id, 370.0)
	var health_before := float(target.get("health"))
	_combat._spawn_projectile({"origin": PLAYER_POSITION + Vector2.RIGHT * offset, "velocity": Vector2.UP * 840.0, "hostile": false, "damage": 1.0, "radius": 7.0, "lifetime": 2.0})
	_advance_projectiles()
	return health_before - float(target.get("health"))


func _advance_projectiles() -> void:
	for _step in 150:
		_combat._update_projectiles(STEP)


func _test_extra_shot_coverage() -> void:
	var primary := _spawn_target(&"drifter", 370.0)
	var secondary := _combat._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": PLAYER_POSITION + Vector2.UP.rotated(0.14) * 420.0}, false)
	var primary_health := float(primary.get("health"))
	var secondary_health := float(secondary.get("health"))
	_combat.apply_run_build({"twin_fold": 1})
	_player.tick_automatic_weapons(0.56, true)
	_advance_projectiles()
	_check(float(primary.get("health")) < primary_health and float(secondary.get("health")) < secondary_health, "extra shot widens coverage to a second enemy while the aimed shot still hits")


func _test_cancelled_boss_warnings() -> void:
	var boss := _spawn_target(&"reef_crown_battery", 370.0) as FoldlightRogueBossActor
	_combat._on_boss_telegraph_requested({"pattern_id": &"petal_salvo", "duration": 1.0, "origin": boss.global_position, "target_position": PLAYER_POSITION, "accent": Color.WHITE})
	var projectile := _combat._spawn_projectile({"origin": Vector2(200, 200), "velocity": Vector2.RIGHT * 50.0, "hostile": true, "lifetime": 4.0})
	boss.phase_controller.enter_stagger(1.0)
	_check(_live_warning_count() == 0 and _combat.projectiles.has(projectile), "stagger cancels obsolete warnings while preserving live hostile shots")
	boss.phase_controller.advance_simulation(1.01, 1.0)
	_combat._on_boss_telegraph_requested({"pattern_id": &"petal_salvo", "duration": 1.0, "origin": boss.global_position, "target_position": PLAYER_POSITION, "accent": Color.WHITE})
	boss.health = boss.definition.base_health * 0.5
	boss.phase_controller.advance_simulation(STEP, 0.5)
	_check(_live_warning_count() == 0 and _combat.projectiles.has(projectile), "phase transition cancels obsolete warnings while preserving live hostile shots")


func _live_warning_count() -> int:
	var count := 0
	for child in _world.room_runtime.projectile_container.get_children():
		if child is FoldlightBossAttackTelegraph and not child.is_queued_for_deletion():
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
