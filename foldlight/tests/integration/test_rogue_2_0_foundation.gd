extends SceneTree

## The roguelite is an extension of the shipped 2.0 combat language, not a
## replacement for it. Explicit later additions (smaller body, dash, active
## item, eight-light reservoir and Fold cooldown) are tested as exceptions.

const CLASSIC_IDS: Array[StringName] = [
	&"drifter", &"fan", &"weaver", &"ram",
	&"bloomer", &"leech", &"mirror", &"rewinder",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(is_equal_approx(FoldlightPlayer.MOVE_SPEED, 430.0), "roguelite keeps the 2.0 movement speed")
	_check(is_equal_approx(FoldlightPlayer.FOLD_SPEED, 235.0), "roguelite keeps the 2.0 movement penalty while folding")
	_check(is_equal_approx(FoldlightPlayer.FULL_CHARGE_TIME, 1.55), "roguelite keeps the 2.0 Fold growth cadence")
	_check(is_equal_approx(FoldlightPlayer.FOLD_RADIUS_MIN, 112.0) and is_equal_approx(FoldlightPlayer.FOLD_RADIUS_MAX, 315.0), "roguelite keeps the 2.0 Fold radius curve")

	var catalog_ids: Array[StringName] = []
	for definition in FoldlightRogueContentCatalog.ENEMIES:
		catalog_ids.append(definition.content_id)
	_check(CLASSIC_IDS.all(func(enemy_id: StringName) -> bool: return catalog_ids.has(enemy_id)), "roguelite catalog restores all eight original enemy designs")
	for encounter in FoldlightRogueContentCatalog.ENCOUNTERS:
		var classic_count := 0
		for enemy_id in encounter.enemy_ids:
			if CLASSIC_IDS.has(enemy_id):
				classic_count += 1
		_check(classic_count >= 4, "%s is built on the original enemy roster" % encounter.content_id)

	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	_check(player.get_capture_capacity() == 8, "the requested eight-light reservoir remains an explicit extension")
	_check(is_equal_approx(player.fold_component.roguelite_cooldown, 1.5), "the requested 1.5 second Fold cooldown remains an explicit extension")
	_check(is_equal_approx(player.dash_component.base_cooldown, 2.0), "the requested two-second dash remains an explicit extension")
	_check(is_equal_approx(player.get_hit_radius(), 13.0), "the requested smaller player body remains an explicit extension")

	var terrain: Array[Dictionary] = []
	_check(world.load_room(player, &"classic_foundation", Vector2(2200, 1300), terrain, Color(0.35, 0.88, 0.84), 2020).is_empty(), "2.0 foundation fixture configures")
	world.activate()
	player.global_position = Vector2(1100, 650)
	_check(player.try_begin_fold(), "Fold begins for radial slowdown verification")
	player.fold_time = FoldlightPlayer.FULL_CHARGE_TIME
	var combat := world.combat_runtime
	_check(combat.has_signal(&"projectile_captured"), "roguelite exposes a capture feedback event for every stored light")
	var center_shot := combat._spawn_projectile({"origin": player.global_position + Vector2(8, 0), "velocity": Vector2(100, 0), "hostile": true, "reflectable": false, "lifetime": 3.0})
	var center_start := center_shot.global_position
	combat._update_projectiles(0.1)
	var center_distance := center_shot.global_position.distance_to(center_start)
	_check(center_distance >= 0.5 and center_distance <= 1.5, "Fold center slows hostile light to the 2.0 ten-percent cadence")
	player.cancel_fold()

	for enemy_id in CLASSIC_IDS:
		var definition := FoldlightRogueContentCatalog.enemy_by_id(enemy_id)
		if definition == null:
			continue
		var actor := FoldlightRogueEnemyFactory.create(definition, StringName("contract_%s" % enemy_id))
		_check(actor is FoldlightRogueEnemyActor, "%s uses the reusable original-enemy actor" % enemy_id)
		if actor is FoldlightRogueEnemyActor:
			_check(StringName((actor as FoldlightRogueEnemyActor).get_combat_snapshot().get("classic_archetype", &"")) == enemy_id, "%s exposes its original combat identity" % enemy_id)
		actor.queue_free()

	var fan_snapshot := await _first_attack_snapshot(&"fan", Vector2(400, 0))
	_check(int(fan_snapshot.get("projectile_count", 0)) == 5 and not bool(fan_snapshot.get("radial", false)), "Fan keeps its original five-petal aimed spread")
	var bloom_snapshot := await _first_attack_snapshot(&"bloomer", Vector2(400, 0))
	_check(int(bloom_snapshot.get("projectile_count", 0)) == 9 and bool(bloom_snapshot.get("radial", false)), "Bloomer keeps its original nine-petal ring")
	var mirror := _make_actor(&"mirror")
	if mirror != null:
		root.add_child(mirror)
		mirror.global_position = Vector2(800, 500)
		for step in 9:
			mirror.advance_simulation(0.3, Vector2(1200, 500))
	_check(mirror != null and mirror.has_method("can_intercept_return_light") and bool(mirror.call("can_intercept_return_light")), "Mirror Folder keeps its timed return-light interception rule")
	if mirror != null:
		mirror.queue_free()
	var rewinder := _make_actor(&"rewinder")
	_check(rewinder != null and bool(rewinder.get_combat_snapshot().get("records_rewind_path", false)), "Rewinder keeps its four-second path replay identity")
	if rewinder != null:
		rewinder.queue_free()

	var presentation := (load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene).instantiate()
	root.add_child(presentation)
	await process_frame
	_check(presentation.find_child("FoldCorePanel", true, false) != null, "roguelite HUD restores Fold as the bottom-center visual anchor")
	_check(presentation.find_child("FoldFocusBar", true, false) != null, "roguelite HUD exposes the original focus economy at a glance")
	_check(presentation.find_child("FoldChargeBar", true, false) != null, "roguelite HUD exposes Fold charge rather than hiding it in text")
	presentation.queue_free()

	world.queue_free()
	player.queue_free()
	await process_frame
	_finish()


func _make_actor(enemy_id: StringName) -> FoldlightRogueEnemyActor:
	var definition := FoldlightRogueContentCatalog.enemy_by_id(enemy_id)
	if definition == null:
		return null
	return FoldlightRogueEnemyFactory.create(definition, StringName("probe_%s" % enemy_id)) as FoldlightRogueEnemyActor


func _first_attack_snapshot(enemy_id: StringName, target_offset: Vector2) -> Dictionary:
	var actor := _make_actor(enemy_id)
	if actor == null:
		return {}
	root.add_child(actor)
	actor.global_position = Vector2(800, 500)
	var snapshots: Array[Dictionary] = []
	actor.attack_requested.connect(func(snapshot: Dictionary) -> void: snapshots.append(snapshot))
	for step in 12:
		actor.advance_simulation(0.3, actor.global_position + target_offset)
		if not snapshots.is_empty():
			break
	actor.queue_free()
	await process_frame
	return snapshots[0] if not snapshots.is_empty() else {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ROGUE_2_0_FOUNDATION: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_2_0_FOUNDATION: FAIL - %s" % ", ".join(_failures))
		quit(1)
