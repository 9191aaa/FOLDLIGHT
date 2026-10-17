extends SceneTree

var failures: Array[String] = []
var events: Array[StringName] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	world.load_room(player, &"feedback_contract", Vector2(2880, 1620), [], Color.WHITE, 8181)
	world.activate()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var combat := world.combat_runtime
	combat.impact_confirmed.connect(func(kind: StringName, _weight: float) -> void: events.append(kind))
	var actor := combat._spawn_enemy_from_entry({"enemy_id": &"fan", "spawn_position": Vector2(1000, 600), "health_multiplier": 10.0}, false)
	var initial := float(actor.get("health"))
	var shot := combat._spawn_projectile({"origin": actor.global_position + Vector2(80, 0), "velocity": Vector2.LEFT * 400.0, "hostile": false, "damage": 1.0, "style": &"crease_petal"})
	combat._resolve_friendly_collision(shot)
	check(events.is_empty() and is_equal_approx(float(actor.get("health")), initial), "a near miss produces neither sound nor impact")
	shot.global_position = actor.global_position
	combat._resolve_friendly_collision(shot)
	check(events == [&"weapon"] and float(actor.get("health")) < initial, "ordinary impact is emitted only after actual collision damage")
	for i in 25:
		var next := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.LEFT * 400.0, "hostile": false, "damage": 0.1, "style": &"crease_petal"})
		combat._resolve_friendly_collision(next)
	check(events.size() == 1 and combat.get_enemy_hit_vfx_snapshot()["active_bursts"] == 1, "same-frame volleys share a bounded local effect and one sound")
	var reflected := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.UP * 600.0, "hostile": false, "damage": 2.0, "style": &"return_light"})
	combat._resolve_friendly_collision(reflected)
	check(events.back() == &"return", "return impact upgrades a still-active ordinary hit")
	var rng_state: int = combat._rng.state
	combat._register_enemy_hit_feedback(&"area", Vector2(500, 500), Vector2.ZERO, 2.0)
	check(combat._rng.state == rng_state, "directionless cosmetic effects leave gameplay randomness untouched")
	var count_before := events.size()
	combat._register_enemy_hit_feedback(&"blocked", Vector2.ZERO, Vector2.RIGHT, 0.0)
	check(events.size() == count_before, "zero damage cannot falsely confirm a successful hit")
	combat.set_active(false)
	var remaining := float(combat._enemy_hit_bursts[0]["remaining"])
	combat._physics_process(0.5)
	check(is_equal_approx(float(combat._enemy_hit_bursts[0]["remaining"]), remaining), "pause freezes feedback with combat")
	combat.set_active(true)
	combat._update_temporary_effects(0.10)
	combat.damage_all_enemies(99999.0)
	check(events.back() == &"break" and combat.enemies.is_empty(), "lethal damage emits a distinct break before the enemy disappears")
	check(combat.get_enemy_hit_vfx_snapshot()["active_bursts"] > 0, "defeat leaves bounded paper fragments after actor deletion")
	check(is_equal_approx(Engine.time_scale, 1.0) and is_zero_approx(player._hit_stop_timer), "impact feedback introduces no global slowdown or player movement stop")
	combat._update_temporary_effects(0.5)
	check(combat.get_enemy_hit_vfx_snapshot()["active_bursts"] == 0, "all impact fragments expire without persistent nodes")
	combat.clear_combat()
	check(combat._impact_cooldowns.is_empty(), "new rooms clear old sound cooldowns")
	world.queue_free()
	player.queue_free()
	await process_frame
	print("FOLDLIGHT_COMBAT_IMPACT_FEEDBACK: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
