extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("ProfileManager").persistence_enabled = false
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.configure_roguelite_combat(true)
	player.reset_player()
	_check(player.health == 4 and player.max_health == 4, "new run starts at four hearts")
	player.apply_roguelite_stats({"max_health_add": 2.0, "move_speed_multiplier": 1.3, "fold_cooldown_multiplier": 0.5, "dash_cooldown_multiplier": 0.6, "capture_capacity": 24.0, "weapon_interval_multiplier": 0.7, "weapon_damage_multiplier": 1.4})
	player.weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(&"needle_orbit"), 4)
	player.active_item_slot.acquire(FoldlightRogueContentCatalog.active_item_by_id(&"tide_clock"))
	player.active_item_slot.cooldown_remaining = 7.25
	player.dash_component.cooldown_remaining = 0.7
	var build := player.get_mirror_build_snapshot()
	_check(build.max_health == 6 and build.current_health == 4, "copy records real maximum and current life without healing player")
	_check(is_equal_approx(build.move_speed, 559.0) and is_equal_approx(build.capture_cooldown, 0.75), "copy uses resolved speed and fold cooldown")
	_check(build.capture_capacity == 32 and build.weapon_levels.get("needle_orbit") == 4, "capacity and actual equipped levels are copied")
	_check(build.active_item_id == "tide_clock" and is_equal_approx(build.active_cooldown_remaining, 7.25) and is_equal_approx(build.dash_cooldown_remaining, 0.7), "equipped skill and current cooldowns retain source state")
	_check(build.owned_active_items.size() == 2 and build.weapons.size() == 2, "only actually held equipment enters snapshot")
	build.build_stats["weapon_damage_multiplier"] = 999.0
	build.weapon_levels["needle_orbit"] = 1
	_check(player.rogue_build_stats.weapon_damage_multiplier == 1.4 and player.get_mirror_build_snapshot().weapon_levels.needle_orbit == 4, "snapshot mutation cannot change actual player build")
	_test_pursuit(player)
	player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_MIRROR_BUILD_PROJECTILES_3_19: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _test_pursuit(target: Node2D) -> void:
	target.position = Vector2(0, 1000)
	var projectile := FoldlightRogueProjectile.new()
	root.add_child(projectile)
	projectile.configure({"origin": Vector2.ZERO, "velocity": Vector2(300, 0), "hostile": true, "homing_target": target, "homing_duration": 1.0, "homing_turn_speed": 1.25, "lifetime": 5.0})
	projectile.advance_simulation(0.1)
	_check(is_equal_approx(projectile.velocity.angle(), 0.125) and is_equal_approx(projectile.velocity.length(), 300.0), "hostile pursuit has a real turn-rate ceiling at constant speed")
	for index in 10: projectile.advance_simulation(0.1)
	var committed := projectile.velocity
	target.position = Vector2(-1000, -1000)
	for index in 12: projectile.advance_simulation(0.1)
	_check(projectile.velocity.is_equal_approx(committed), "tracking expires: moving away cannot make projectile U-turn forever")
	projectile.configure({"origin": Vector2.ZERO, "velocity": Vector2(300, 0), "hostile": true, "homing_target": target, "homing_duration": 0.9, "homing_turn_speed": 1.6, "launch_delay": 0.65, "orbit_anchor": target, "orbit_radius": 70.0, "lifetime": 5.0})
	projectile.advance_simulation(0.5)
	_check(is_zero_approx(projectile.homing_elapsed), "orbit warning does not consume finite pursuit before launch")
	projectile.advance_simulation(0.2)
	_check(is_equal_approx(projectile.homing_elapsed, 0.05), "only launched movement consumes homing window")
	projectile.configure({"origin": Vector2.ZERO, "velocity": Vector2(300, 0), "hostile": false, "homing_target": target, "homing_strength": 8.0, "lifetime": 5.0})
	projectile.advance_simulation(0.1)
	_check(not projectile.velocity.is_equal_approx(Vector2(300, 0)), "friendly tracking still uses original full pursuit")
	projectile.configure({"velocity": Vector2(0, 900), "hostile": true, "style": &"sun_thread"})
	_check(is_equal_approx(projectile.rotation, PI * 0.5), "copied sun thread drawing faces its actual flight direction")
	projectile.configure({"velocity": Vector2(300, 0), "hostile": true, "style": &"mirror_return"})
	_check(projectile.get_visual_contract().motif == &"hostile_fold_petal", "returned mirror ammunition keeps the hostile silhouette instead of friendly gold trails")
	projectile.queue_free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[FAIL] " + message)
