extends SceneTree

## 3.5.1 player-hit contract: a hit must be readable on the player body even
## when camera shake is disabled, but it must settle before it becomes jitter.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/player.tscn") as PackedScene
	var player := packed.instantiate() as FoldlightPlayer if packed != null else null
	_check(player != null, "player scene loads for hit-reaction verification")
	if player == null:
		_finish()
		return
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.invulnerability = 0.0
	var physical_position := Vector2(840.0, 620.0)
	player.global_position = physical_position

	_check(player.take_hit(Vector2.RIGHT), "an eligible projectile hit is accepted")
	var opening := player.get_hit_reaction_snapshot()
	_check(bool(opening.get("active", false)), "accepted damage starts a dedicated body reaction")
	_check(Vector2(opening.get("offset", Vector2.ZERO)).x >= 17.0, "opening impact pose moves a clearly visible eighteen pixels")
	_check(Vector2(opening.get("visual_scale", Vector2.ONE)).distance_to(Vector2.ONE) >= 0.08, "opening impact pose includes a restrained squash")
	_check(player.global_position == physical_position, "hit reaction never changes the gameplay collision position")

	player._update_hit_reaction(0.08)
	var reversal := player.get_hit_reaction_snapshot()
	_check(Vector2(reversal.get("offset", Vector2.ZERO)).x < -3.0, "body performs one short counter-jolt instead of drifting")
	_check(player.global_position == physical_position, "counter-jolt remains visual-only")

	player._update_hit_reaction(0.20)
	var settled := player.get_hit_reaction_snapshot()
	_check(not bool(settled.get("active", true)), "body reaction settles within a quarter second")
	_check(Vector2(settled.get("offset", Vector2.ONE)).is_zero_approx() and Vector2(settled.get("visual_scale", Vector2.ZERO)).is_equal_approx(Vector2.ONE), "settled body returns exactly to its neutral pose")

	var camera := FoldlightRogueCamera.new()
	root.add_child(camera)
	await process_frame
	camera.add_trauma(0.62)
	camera.add_hit_kick(1.0)
	var peak_camera_offset := 0.0
	var peak_camera_roll := 0.0
	for _frame in 8:
		camera._update_shake(0.016)
		peak_camera_offset = maxf(peak_camera_offset, camera.offset.length())
		peak_camera_roll = maxf(peak_camera_roll, absf(rad_to_deg(camera.rotation)))
	_check(peak_camera_offset > 1.0, "new hit trauma is visible above the former one-pixel floor")
	_check(peak_camera_offset < 7.0 and peak_camera_roll < 1.0, "new hit trauma remains a small kick rather than 2.0 over-shake")

	player.queue_free()
	camera.queue_free()
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
		print("FOLDLIGHT_PLAYER_HIT_REACTION_3_5_1: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PLAYER_HIT_REACTION_3_5_1: FAIL - %s" % ", ".join(_failures))
		quit(1)
