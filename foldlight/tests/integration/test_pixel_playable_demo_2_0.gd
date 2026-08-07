extends SceneTree

const DEMO_SCENE_PATH := "res://scenes/demos/pixel_playable_demo.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(DEMO_SCENE_PATH) as PackedScene
	_check(packed != null, "playable demo scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame

	var contract := game.call("get_playable_contract") as Dictionary
	_check(bool(contract.get("playable", false)), "delivery declares real gameplay")
	_check(int(contract.get("finished_room_count", 0)) == 2, "delivery contains exactly two finished fixed rooms")
	_check(not bool(contract.get("random_map", true)), "demo does not pretend to provide a random map")
	_check(contract.get("base_resolution") == Vector2i(1254, 705), "DPI-exact native canvas prevents fractional upscale blur")
	_check(not bool(contract.get("background_resampling", true)), "backgrounds are native source crops")
	_check(not bool(contract.get("changes_display_mode", true)), "demo never changes the desktop display mode")
	_check(bool(contract.get("terrain_recomposable", false)), "terrain is based on reusable authored modules")
	_check(bool(contract.get("terrain_modules_native_scale", false)), "terrain modules preserve native pixels")
	var mechanics := contract.get("mechanics", {}) as Dictionary
	_check(bool(mechanics.get("auto_homing_weapon", false)), "player has an automatic homing weapon")
	_check(int(mechanics.get("capture_capacity", 0)) == 8, "fold starts with eight capture slots")
	_check(is_equal_approx(float(mechanics.get("fold_cooldown", 0.0)), 1.5), "fold release cooldown is 1.5 seconds")
	_check(is_equal_approx(float(mechanics.get("dash_cooldown", 0.0)), 2.0), "dash cooldown is 2 seconds")
	_check(bool(mechanics.get("active_skill", false)), "active skill is present")
	_check(bool(mechanics.get("reflectable_and_forbidden_projectiles", false)), "enemy arsenal includes readable reflectable and forbidden shots")

	var snapshot := game.call("get_runtime_snapshot") as Dictionary
	_check(int(snapshot.get("room_index", 0)) == 1, "run opens in room one")
	_check(int(snapshot.get("living_enemies", 0)) == 4, "room one contains four distinct active enemies")
	_check(int(snapshot.get("player_health", 0)) == 6, "player starts with six durability")
	_check(game.get_node_or_null("Stage/Backdrop") != null, "backdrop layer exists")
	_check(game.get_node_or_null("Stage/Terrain") != null, "reusable terrain layer exists")
	_check(game.get_node_or_null("Stage/ArenaFx") != null, "arena feedback layer exists")
	_check(game.get_node_or_null("Stage/Actors") != null, "Y-sorted actor layer exists")
	_check(game.get_node_or_null("Stage/Projectiles") != null, "projectile layer exists")
	_check(game.get_node_or_null("Stage/Vfx") != null, "impact VFX layer exists")
	_check(game.get_node_or_null("Hud") is CanvasLayer, "HUD stays on an isolated canvas layer")

	var player := game.get("player") as CharacterBody2D
	var start_position := player.global_position
	Input.action_press(&"move_right")
	for _frame in 5:
		await physics_frame
	Input.action_release(&"move_right")
	_check(player.global_position.x > start_position.x, "keyboard/gamepad action path moves the player in physics frames")
	_check(InputMap.has_action(&"dash") and InputMap.action_get_events(&"dash").size() >= 2, "dash is mapped for keyboard and gamepad")
	_check(bool(game.call("_start_dash")) and float(game.get("dash_cooldown")) > 1.9, "dash starts the full two-second cooldown")
	_check(InputMap.has_action(&"active_item") and InputMap.action_get_events(&"active_item").size() >= 2, "active skill is mapped for keyboard and gamepad")
	game.call("_use_active_skill")
	_check(float(game.get("active_cooldown")) > 7.9, "active skill triggers a strong eight-second ability")
	var projectile_count_before := int((game.call("get_runtime_snapshot") as Dictionary).get("projectile_count", 0))
	for _frame in 20:
		await physics_frame
	var projectile_count_after := int((game.call("get_runtime_snapshot") as Dictionary).get("projectile_count", 0))
	_check(projectile_count_after > projectile_count_before, "combat simulation produces live automatic and enemy projectiles")

	game.call("debug_defeat_all_enemies")
	await process_frame
	await physics_frame
	snapshot = game.call("get_runtime_snapshot") as Dictionary
	_check(StringName(snapshot.get("run_state", &"")) == &"room_clear", "clearing room one opens the transition gate")

	game.call("start_boss_room")
	await process_frame
	await physics_frame
	snapshot = game.call("get_runtime_snapshot") as Dictionary
	_check(int(snapshot.get("room_index", 0)) == 2, "boss room is directly playable")
	_check(int(snapshot.get("living_enemies", 0)) == 1, "boss room contains the reef-crown boss")
	game.call("debug_set_boss_health_ratio", 0.5)
	await physics_frame
	snapshot = game.call("get_runtime_snapshot") as Dictionary
	_check(int(snapshot.get("boss_phase", 0)) == 2 and is_equal_approx(float(snapshot.get("arena_radius", 0.0)), 286.0), "boss phase two visibly restricts movement")
	game.call("debug_set_boss_health_ratio", 0.2)
	await physics_frame
	snapshot = game.call("get_runtime_snapshot") as Dictionary
	_check(int(snapshot.get("boss_phase", 0)) == 3 and is_equal_approx(float(snapshot.get("arena_radius", 0.0)), 232.0), "boss phase three tightens the arena")
	game.call("debug_defeat_all_enemies")
	await process_frame
	await physics_frame
	snapshot = game.call("get_runtime_snapshot") as Dictionary
	_check(StringName(snapshot.get("run_state", &"")) == &"victory", "defeating the boss completes the demo")

	game.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PIXEL_PLAYABLE_DEMO_2_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PIXEL_PLAYABLE_DEMO_2_0: FAIL - %s" % ", ".join(_failures))
		quit(1)
