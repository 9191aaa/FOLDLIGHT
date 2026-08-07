extends SceneTree

const CLASSIC_STATS := {
	&"drifter": [2.0, 27.0],
	&"fan": [4.0, 34.0],
	&"weaver": [6.0, 38.0],
	&"ram": [8.0, 42.0],
	&"bloomer": [9.0, 45.0],
	&"leech": [10.0, 43.0],
	&"mirror": [11.0, 48.0],
	&"rewinder": [12.0, 45.0],
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for enemy_id: StringName in CLASSIC_STATS:
		var actor := _make_actor(enemy_id)
		_check(actor != null, "%s actor exists" % enemy_id)
		if actor == null:
			continue
		var expected: Array = CLASSIC_STATS[enemy_id]
		var contract := actor.get_classic_contract()
		_check(StringName(contract.get("version", &"")) == &"classic_2_0_exact", "%s declares exact 2.0 visual contract" % enemy_id)
		_check(is_equal_approx(float(contract.get("health", 0.0)), float(expected[0])), "%s keeps 2.0 health" % enemy_id)
		_check(is_equal_approx(float(contract.get("radius", 0.0)), float(expected[1])), "%s keeps 2.0 body radius" % enemy_id)
		actor.queue_free()

	var ram_actor := _make_actor(&"ram")
	var ram_contract := ram_actor.get_classic_contract().get("behavior", {}) as Dictionary
	_check(is_equal_approx(float(ram_contract.get("telegraph", 0.0)), 0.95), "Ram keeps the 2.0 telegraph duration")
	_check(is_equal_approx(float(ram_contract.get("charge_speed", 0.0)), 840.0), "Ram keeps the 2.0 charge speed")
	ram_actor.free()
	var rewind_actor := _make_actor(&"rewinder")
	var rewind_contract := rewind_actor.get_classic_contract().get("behavior", {}) as Dictionary
	_check(int(rewind_contract.get("history_samples", 0)) == 54, "Rewinder keeps the 2.0 four-second history buffer")
	_check(is_equal_approx(float(rewind_contract.get("rewind_speed", 0.0)), 900.0), "Rewinder keeps the 2.0 rewind speed")
	rewind_actor.free()

	var drifter := await _first_attack(&"drifter")
	_check(_exact_shot(drifter, 0, 160.0, 0.0), "Drifter keeps its 160-speed straight petal")
	_check(Color(drifter.get("color", Color.BLACK)).is_equal_approx(Color(0.68, 0.27, 0.70)), "Drifter restores its original projectile color")
	var fan := await _first_attack(&"fan")
	var fan_shots: Array = fan.get("projectiles", [])
	_check(fan_shots.size() == 5, "Fan keeps five individually parameterized petals")
	if fan_shots.size() == 5:
		_check(is_equal_approx(float((fan_shots[0] as Dictionary).get("speed", 0.0)), 168.72), "Fan outer petal keeps its 2.0 speed ramp")
		_check(is_equal_approx(float((fan_shots[0] as Dictionary).get("curve", 0.0)), -0.0304), "Fan outer petal keeps its 2.0 curve")
	var weaver := await _first_attack(&"weaver")
	_check(_exact_shot(weaver, 0, 146.0, 0.31), "Weaver keeps its 146-speed 0.31 curve thread")
	_check(int(weaver.get("kind", 0)) == 1 and StringName(weaver.get("status", &"")) == &"veiled_fold", "Weaver restores its thin status-petal type")
	var bloomer := await _first_attack(&"bloomer")
	_check(int(bloomer.get("projectile_count", 0)) == 9 and bool(bloomer.get("radial", false)), "Bloomer keeps the 2.0 nine-petal ring")
	var leech := await _first_attack(&"leech")
	_check(int(leech.get("projectile_count", 0)) == 3 and StringName(leech.get("status", &"")) == &"wet_ink", "Leech keeps its wet-ink three-petal spread")
	var mirror := await _first_attack(&"mirror")
	_check(int(mirror.get("projectile_count", 0)) == 2 and _exact_shot(mirror, 0, 172.0, 0.0192), "Mirror keeps the 2.0 paired counter-curving shot")

	var projectile := FoldlightRogueProjectile.new()
	root.add_child(projectile)
	projectile.configure({"hostile": true, "reflectable": true, "kind": 0, "style": &"hostile_petal"})
	var petal_visual := projectile.get_visual_contract()
	_check(StringName(petal_visual.get("version", &"")) == &"classic_2_0_exact" and is_equal_approx(float(petal_visual.get("length", 0.0)), 12.0), "hostile projectile geometry is the 2.0 twelve-by-six petal")
	projectile.configure({"hostile": true, "reflectable": false, "kind": 2, "style": &"paper_seal"})
	var seal_visual := projectile.get_visual_contract()
	_check(is_equal_approx(float(seal_visual.get("length", 0.0)), 18.0) and is_equal_approx(float(seal_visual.get("width", 0.0)), 8.0), "unreflectable seal restores the 2.0 black-gold silhouette")
	projectile.configure({"hostile": false, "style": &"return_light"})
	var return_visual := projectile.get_visual_contract()
	_check(StringName(return_visual.get("motif", &"")) == &"gold_diamond_return" and is_equal_approx(float(return_visual.get("trail", 0.0)), 28.0), "return missile restores the 2.0 gold diamond and cyan trail")
	projectile.queue_free()

	await process_frame
	_finish()


func _make_actor(enemy_id: StringName) -> FoldlightRogueEnemyActor:
	var definition := FoldlightRogueContentCatalog.enemy_by_id(enemy_id)
	if definition == null:
		return null
	return FoldlightRogueEnemyFactory.create(definition, StringName("exact_%s" % enemy_id)) as FoldlightRogueEnemyActor


func _first_attack(enemy_id: StringName) -> Dictionary:
	var actor := _make_actor(enemy_id)
	if actor == null:
		return {}
	root.add_child(actor)
	actor.global_position = Vector2(800, 500)
	actor.set_arena_center(Vector2(960, 535))
	var snapshots: Array[Dictionary] = []
	actor.attack_requested.connect(func(snapshot: Dictionary) -> void: snapshots.append(snapshot))
	for step in 30:
		actor.advance_simulation(0.1, Vector2(1200, 500))
		if not snapshots.is_empty():
			break
	actor.queue_free()
	await process_frame
	return snapshots[0] if not snapshots.is_empty() else {}


func _exact_shot(snapshot: Dictionary, index: int, speed: float, curve: float) -> bool:
	var shots: Array = snapshot.get("projectiles", [])
	if index < 0 or index >= shots.size():
		return false
	var shot := shots[index] as Dictionary
	return is_equal_approx(float(shot.get("speed", 0.0)), speed) and is_equal_approx(float(shot.get("curve", 0.0)), curve)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ROGUE_2_0_EXACT_CONTRACT: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROGUE_2_0_EXACT_CONTRACT: FAIL - %s" % ", ".join(_failures))
		quit(1)
