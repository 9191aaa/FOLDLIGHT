extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("TEST FAIL: " + label)
	else:
		print("PASS: " + label)

func run_tests() -> void:
	var scene: PackedScene = load("res://rebuild/scenes/boss_lab.tscn")
	var lab = scene.instantiate()
	root.add_child(lab)
	await process_frame
	check(lab.mode == lab.Mode.TITLE, "title starts")
	check(lab.get_node_or_null("CanvasLayer/HUD") != null, "HUD path is valid")
	for preset: StringName in [&"relaxed", &"normal", &"challenge"]:
		lab.start_boss(preset)
		await process_frame
		check(lab.mode == lab.Mode.FIGHT, "fight starts " + String(preset))
		check(is_instance_valid(lab.boss), "boss exists " + String(preset))
		check(lab.player.health == lab.player.max_health, "full health on retry")
		check(lab.world.combat_runtime.enemies.size() == 1, "exactly one boss, no summons")
	lab.start_boss(&"normal")
	await process_frame
	var player = lab.player
	var combat = lab.world.combat_runtime
	check(player.get_capture_capacity() == 8, "normal capacity eight")
	check(is_equal_approx(lab.boss.health, 320.0), "normal boss health 320")
	check(player.try_begin_fold(), "Fold starts")
	check(player.capture_one(), "first captured bullet")
	check(player.capture_one(), "second captured bullet")
	var previous_projectiles: int = combat.projectiles.size()
	check(player.request_dash(Vector2.RIGHT), "dash works with stored light")
	check(not player.folding and player.captured == 0, "dash commits reservoir once")
	check(combat.projectiles.size() == previous_projectiles + 2, "each stored bullet creates one return")
	check(not player.request_dash(Vector2.RIGHT), "unavailable dash cannot fire again")
	var before_cd: float = player.dash_component.cooldown_remaining
	var before_boss: float = lab.boss.remaining
	lab.pause_fight()
	for i in 5:
		await process_frame
	check(is_equal_approx(before_cd, player.dash_component.cooldown_remaining), "pause freezes dash cooldown")
	check(is_equal_approx(before_boss, lab.boss.remaining), "pause freezes boss attacks")
	lab.resume_fight()
	check(not paused and lab.mode == lab.Mode.FIGHT, "resume works")
	var hp_before: float = lab.boss.health
	lab.boss.take_damage(10.0, &"return")
	check(is_equal_approx(hp_before - lab.boss.health, 10.0), "reflection has no hidden suppression")
	lab.boss.take_damage(160.0, &"return")
	check(lab.boss.phase == 1, "second phase reached")
	check(lab.boss.rhythm == lab.boss.Rhythm.TRANSITION, "phase change grants breathing space")
	lab.boss.take_damage(10000.0, &"return")
	check(lab.mode == lab.Mode.RESULT, "victory reaches result")
	lab.start_boss(&"normal")
	await process_frame
	check(lab.mode == lab.Mode.FIGHT and is_equal_approx(lab.boss.health, 320.0), "retry resets boss")
	player.set_debug_invincible(true)
	for i in 180:
		await physics_frame
	check(is_instance_valid(lab.boss), "live encounter advances without losing boss")
	check(lab.elapsed > 1.0, "live fight clock advances")
	lab.show_title()
	check(not paused and lab.mode == lab.Mode.TITLE, "back to title resets pause")
	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOLDLIGHT_DEMO_TESTS_PASS: %d checks" % checks)
		quit(0)
	else:
		print("FOLDLIGHT_DEMO_TESTS_FAIL: " + "; ".join(failures))
		quit(1)
