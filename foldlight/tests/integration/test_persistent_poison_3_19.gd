extends SceneTree

const Cloud = preload("res://scripts/roguelite/enemies/miasma_cloud.gd")
const Wraith = preload("res://scripts/roguelite/enemies/miasma_wraith.gd")
const Bomber = preload("res://scripts/roguelite/enemies/cinder_mine.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	_test_persistent_clock()
	await _test_pursuit_and_command()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_PERSISTENT_POISON_3_19: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_persistent_clock() -> void:
	var cloud := Cloud.new()
	root.add_child(cloud)
	cloud.configure({"position": Vector2(800, 600), "source_id": &"old_carrier"})
	cloud.advance_simulation(0.1)
	var warning_before := float(cloud.get_hazard_snapshot()["warning_remaining"])
	_check(cloud.refresh_duration(), "a carrier can refresh its own still-visible trail")
	_check(is_equal_approx(float(cloud.get_hazard_snapshot()["warning_remaining"]), warning_before) and not cloud.consume_damage_at(cloud.position), "refresh during warning neither skips nor restarts the readable countdown")
	for index in 8:
		cloud.advance_simulation(0.1)
	_check(cloud.consume_damage_at(cloud.position), "the complete warning creates one normal poison damage opportunity")
	cloud.advance_simulation(0.1)
	var tick_before := float(cloud.get_hazard_snapshot()["tick_remaining"])
	var boundary_before := cloud.radius
	_check(cloud.refresh_duration(), "a refreshed active area remains one cloud")
	_check(is_equal_approx(float(cloud.get_hazard_snapshot()["tick_remaining"]), tick_before) and not cloud.consume_damage_at(cloud.position), "refresh cannot reset the damage cadence for an extra hit")
	_check(is_equal_approx(cloud.radius, boundary_before) and is_equal_approx(float(cloud.get_hazard_snapshot()["remaining"]), 60.0), "refresh replenishes duration without expanding the visible damage boundary")
	cloud.set_simulation_active(false)
	var paused := cloud.get_hazard_snapshot()
	for index in 20:
		cloud.advance_simulation(20.0)
	_check(cloud.get_hazard_snapshot() == paused and not cloud.refresh_duration(90.0), "pause freezes the entire sixty-second lifetime and rejects delayed refresh events")
	cloud.set_simulation_active(true)
	for index in 599:
		cloud.advance_simulation(0.1)
	_check(not bool(cloud.get_hazard_snapshot()["expired"]) and cloud.consume_damage_at(cloud.position), "the trail is still real and harmful at 59.9 seconds")
	cloud.advance_simulation(0.1)
	_check(bool(cloud.get_hazard_snapshot()["expired"]) and not cloud.consume_damage_at(cloud.position) and not cloud.refresh_duration(), "expiry removes damage and stale refresh cannot resurrect an invisible cloud")
	cloud.queue_free()


func _test_pursuit_and_command() -> void:
	var wraith_definition := FoldlightRogueContentCatalog.enemy_by_id(&"miasma_wraith")
	var bomber_definition := FoldlightRogueContentCatalog.enemy_by_id(&"cinder_mine")
	var wraith := FoldlightRogueEnemyFactory.create(wraith_definition, &"faster_wraith") as Wraith
	var bomber := FoldlightRogueEnemyFactory.create(bomber_definition, &"faster_bomber") as Bomber
	root.add_child(wraith)
	root.add_child(bomber)
	wraith.global_position = Vector2(500, 400)
	bomber.global_position = Vector2(500, 900)
	# These checks measure steering without scene geometry or player collision.
	wraith.collision_mask = 0
	bomber.collision_mask = 0
	await process_frame
	for index in 60:
		wraith.advance_simulation(1.0 / 60.0, wraith.global_position + Vector2(1500, 0))
		bomber.advance_simulation(1.0 / 60.0, bomber.global_position + Vector2(1500, 0))
	_check(wraith.velocity.length() >= 269.0 and bomber.velocity.length() >= 279.0, "actual poison and bomber pursuit reaches the faster 270/280px-per-second base movement")
	var stronger := {"move_multiplier": 2.2, "projectile_speed_multiplier": 1.85, "attack_interval_multiplier": 0.28}
	wraith.set_command_buff(stronger)
	bomber.set_command_buff(stronger)
	_check(wraith.get_command_buff_snapshot() == stronger and is_equal_approx(wraith.support_attack_multiplier, 0.28), "shared actor accepts the commander's actual new strongest movement, projectile and attack buffs")
	for index in 90:
		wraith.advance_simulation(1.0 / 60.0, wraith.global_position + Vector2(1500, 0))
		bomber.advance_simulation(1.0 / 60.0, bomber.global_position + Vector2(1500, 0))
	_check(wraith.velocity.length() >= 593.0 and bomber.velocity.length() >= 615.0, "commander visibly accelerates both pursuit enemies without multiplying speed every tick")
	bomber.advance_simulation(0.02, bomber.global_position + Vector2(80, 0))
	_check(bomber.phase == Bomber.Phase.CHARGING and is_equal_approx(float(bomber.get_phase_snapshot()["remaining"]), 1.5), "even maximum command acceleration starts a complete anchored 1.5-second fuse")
	var anchor := bomber.global_position
	for index in 10:
		bomber.advance_simulation(0.1, anchor + Vector2(1000, 0))
	_check(bomber.phase == Bomber.Phase.CHARGING and bomber.global_position.is_equal_approx(anchor) and float(bomber.get_phase_snapshot()["remaining"]) >= 0.49, "the commander cannot shorten the committed blast warning or drag its damage circle")
	wraith.set_support_buff(0.78)
	_check(is_equal_approx(wraith.support_attack_multiplier, 0.28), "a weaker bell tether cannot overwrite or multiply the stronger command buff")
	wraith.set_command_buff({})
	_check(is_equal_approx(wraith.support_attack_multiplier, 0.78) and is_equal_approx(wraith.command_move_multiplier, 1.0), "leaving command range restores base movement while retaining an independent bell tether")
	wraith.set_support_buff(1.0)
	bomber.set_command_buff({})
	_check(is_equal_approx(wraith.support_attack_multiplier, 1.0) and is_equal_approx(bomber.command_move_multiplier, 1.0), "leaving every buff restores original authored stats")
	wraith.queue_free()
	bomber.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
