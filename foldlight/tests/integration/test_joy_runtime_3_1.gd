extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_mechanic_enemy_behaviors()
	await _test_active_item_behaviors()
	_finish()


func _test_mechanic_enemy_behaviors() -> void:
	var prism_scene := load("res://scenes/roguelite/enemies/prism_bulwark.tscn") as PackedScene
	var prism := prism_scene.instantiate() as FoldlightPrismBulwark
	root.add_child(prism)
	prism.configure(FoldlightRogueContentCatalog.enemy_by_id(&"prism_bulwark"), &"prism_test")
	var prism_health := prism.health
	prism.take_projectile_damage(2.0, Vector2.RIGHT * 800.0, &"return_light")
	_check(not prism.prism_active and prism.health <= prism_health - 3.5, "Return light visibly breaks the Prism Bulwark and opens burst damage")

	var brood_scene := load("res://scenes/roguelite/enemies/brood_lantern.tscn") as PackedScene
	var brood := brood_scene.instantiate() as FoldlightBroodLantern
	var brood_requests: Array[Dictionary] = []
	root.add_child(brood)
	brood.configure(FoldlightRogueContentCatalog.enemy_by_id(&"brood_lantern"), &"brood_test")
	brood.spawn_requested.connect(func(snapshot: Dictionary) -> void: brood_requests.append(snapshot))
	brood.advance_simulation(3.3, Vector2.ZERO)
	_check(brood_requests.size() == 1 and (brood_requests[0].get("positions", []) as Array).size() == 2, "Brood Lantern creates a small readable reinforcement pair")

	var shear_scene := load("res://scenes/roguelite/enemies/shear_scribe.tscn") as PackedScene
	var shear := shear_scene.instantiate() as FoldlightShearScribe
	var shear_volleys: Array[Dictionary] = []
	root.add_child(shear)
	shear.configure(FoldlightRogueContentCatalog.enemy_by_id(&"shear_scribe"), &"shear_test")
	shear.volley_requested.connect(func(snapshot: Dictionary) -> void: shear_volleys.append(snapshot))
	shear.advance_simulation(2.21, Vector2(400, 200))
	shear.advance_simulation(1.16, Vector2(400, 200))
	_check(shear_volleys.size() == 1 and not bool(shear_volleys[0].get("reflectable", true)) and int(shear_volleys[0].get("projectile_count", 0)) == 4, "Shear Scribe warns, then fires four unmistakable unreflectable blades")

	prism.queue_free()
	brood.queue_free()
	shear.queue_free()
	await process_frame


func _test_active_item_behaviors() -> void:
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	_check(world.load_room(player, &"active_item_runtime", Vector2(2200, 1300), [], Color(0.42, 0.88, 0.82), 3131).is_empty(), "active-item behavior fixture configures")
	world.activate()
	var combat := world.combat_runtime
	player.global_position = Vector2(1100, 650)
	var victim := combat._spawn_enemy_from_entry({"enemy_id": &"prism_bulwark", "spawn_position": Vector2(1240, 650)}, false)
	var victim_health := float(victim.get("health"))
	for index in 5:
		combat._spawn_projectile({"origin": player.global_position + Vector2(80 + index * 20, 0), "velocity": Vector2.LEFT * 220.0, "hostile": true, "reflectable": true, "lifetime": 3.0})
	combat._spawn_projectile({"origin": player.global_position + Vector2(180, 60), "velocity": Vector2.LEFT * 220.0, "hostile": true, "reflectable": false, "lifetime": 3.0})
	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"paper_burst"))
	_check(float(victim.get("health")) <= victim_health - 4.9, "Paper Burst immediately chunks nearby mechanic enemies")
	_check(combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.style == &"return_light").size() >= 5, "Paper Burst rewrites ordinary bullets into homing return light")
	_check(combat.projectiles.any(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile and not projectile.reflectable), "Paper Burst preserves unreflectable threat identity")

	player.dash_component.charges = 0
	player.dash_component.cooldown_remaining = 1.5
	player.invulnerability = 0.0
	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"mirror_step"))
	_check(player.dash_component.charges == player.dash_component.maximum_charges and player.dash_component.cooldown_remaining <= 0.0 and player.invulnerability >= 0.95, "Mirror Step fully resets mobility and supplies a real safety beat")

	combat._on_zone_requested({"origin": player.global_position, "radius": 180.0, "duration": 5.0})
	player.health = player.max_health - 3
	player.focus = 0.0
	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"ink_wash"))
	await process_frame
	_check(player.health == player.max_health - 1 and player.focus >= 0.99, "Ink Wash restores two health and a full Fold resource")
	_check(_count_denial_zones(world) == 0 and float(combat.get("_terrain_cleanse_remaining")) >= 3.9, "Ink Wash clears denial zones and suppresses terrain hazards")

	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"crease_anchor"))
	_check(int(combat.get("_shield_charges")) >= 4 and float(combat.get("_shield_remaining")) >= 4.9, "Crease Anchor covers a whole danger sequence with four layers")
	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"tide_clock"))
	_check(float(combat.get("_hostile_slow_scale")) <= 0.40 and float(combat.get("_hostile_slow_remaining")) >= 4.9, "Tide Clock strongly slows the whole hostile simulation")
	player.focus = 0.0
	combat._on_active_item_used(FoldlightRogueContentCatalog.active_item_by_id(&"sun_stamp"))
	_check(float(combat.get("_weapon_haste")) >= 2.0 and float(combat.get("_weapon_overdrive_remaining")) >= 5.9 and not player.fold_temporarily_locked and player.focus >= 0.49, "Sun Stamp combines sustained overdrive with immediate Fold tempo")

	world.queue_free()
	player.queue_free()
	await process_frame


func _count_denial_zones(world: FoldlightRogueWorld) -> int:
	var count := 0
	for child in (world.room_runtime.get_node("Projectiles") as Node2D).get_children():
		if child is FoldlightInkDenialZone and not child.is_queued_for_deletion():
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_JOY_RUNTIME_3_1: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_JOY_RUNTIME_3_1: FAIL - %s" % ", ".join(_failures))
		quit(1)
