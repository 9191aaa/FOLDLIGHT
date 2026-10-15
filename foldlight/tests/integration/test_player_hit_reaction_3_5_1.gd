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
	var physical_radius := (player.collision_shape.shape as CircleShape2D).radius
	var health_before := player.health

	_check(player.take_hit(Vector2.RIGHT), "an eligible projectile hit is accepted")
	var opening := player.get_hit_reaction_snapshot()
	_check(bool(opening.get("active", false)), "accepted damage starts a dedicated body reaction")
	_check(Vector2(opening.get("offset", Vector2.ZERO)).x >= 17.0, "opening impact pose moves a clearly visible eighteen pixels")
	_check(Vector2(opening.get("visual_scale", Vector2.ONE)).distance_to(Vector2.ONE) >= 0.08, "opening impact pose includes a restrained squash")
	_check(player.global_position == physical_position, "hit reaction never changes the gameplay collision position")
	_check(player.health == health_before - 1 and is_equal_approx(player.invulnerability, 1.35), "feedback preserves one health lost and the original immunity duration")
	_check(float(opening.get("damage_mark_strength", 0.0)) > 0.99 and Vector2(opening.get("source_direction", Vector2.ZERO)) == Vector2.LEFT, "real damage immediately marks the side the projectile came from")
	_check(float(opening.get("protection_alpha", 0.0)) >= 0.60, "the immunity cue is visible immediately after damage")
	_check(not player.take_hit(Vector2.UP) and player.get_hit_reaction_snapshot() == opening, "an immune hit cannot restart the reaction or overwrite its direction")

	player._update_hit_reaction(0.08)
	var reversal := player.get_hit_reaction_snapshot()
	_check(Vector2(reversal.get("offset", Vector2.ZERO)).x < -3.0, "body performs one short counter-jolt instead of drifting")
	_check(player.global_position == physical_position, "counter-jolt remains visual-only")

	player._update_hit_reaction(0.20)
	var settled := player.get_hit_reaction_snapshot()
	_check(not bool(settled.get("active", true)), "body reaction settles within a quarter second")
	_check(Vector2(settled.get("offset", Vector2.ONE)).is_zero_approx() and Vector2(settled.get("visual_scale", Vector2.ZERO)).is_equal_approx(Vector2.ONE), "settled body returns exactly to its neutral pose")
	_check(float(settled.get("damage_mark_strength", 0.0)) > 0.0, "brief coral damage cue remains readable after the body has settled")
	player._update_hit_reaction(0.20)
	var marked_out := player.get_hit_reaction_snapshot()
	_check(is_zero_approx(float(marked_out.get("damage_mark_strength", 1.0))) and float(marked_out.get("protection_alpha", 0.0)) >= 0.60, "short damage tear fades while immunity remains legible")
	_check(is_equal_approx(player.invulnerability, 1.35) and is_equal_approx((player.collision_shape.shape as CircleShape2D).radius, physical_radius), "visual feedback neither spends immunity nor changes collision radius")
	var immunity_stays_visible := true
	for frame in 65:
		player.invulnerability = 1.30 - float(frame) * 0.018
		immunity_stays_visible = immunity_stays_visible and float(player.get_hit_reaction_snapshot().get("protection_alpha", 0.0)) > 0.0
	_check(immunity_stays_visible, "immunity has a continuous cue instead of alternating invisible frames")
	player.invulnerability = 0.0
	_check(is_zero_approx(float(player.get_hit_reaction_snapshot().get("protection_alpha", 1.0))), "the protection mark disappears exactly when immunity ends")

	player.set_feedback_motion_scale(0.25)
	_check(player.take_hit(Vector2.UP), "reduced-motion damage still applies normally")
	var reduced := player.get_hit_reaction_snapshot()
	_check(Vector2(reduced.get("offset", Vector2.ZERO)).is_equal_approx(Vector2.UP * 4.5), "body recoil follows the existing motion-strength setting proportionally")
	player.set_feedback_motion_scale(0.0)
	var still := player.get_hit_reaction_snapshot()
	_check(Vector2(still.get("offset", Vector2.ONE)).is_zero_approx() and Vector2(still.get("visual_scale", Vector2.ZERO)) == Vector2.ONE, "turning motion off immediately removes an in-flight body jolt")
	_check(float(still.get("damage_mark_strength", 0.0)) > 0.99 and float(still.get("protection_alpha", 0.0)) > 0.0, "zero motion preserves damage colour and protection information")
	player._update_hit_reaction(0.08)
	_check(Vector2(player.get_hit_reaction_snapshot().get("offset", Vector2.ONE)).is_zero_approx(), "zero motion does not reintroduce a counter-jolt on later frames")
	player.suspend_for_overlay()
	var paused := player.get_hit_reaction_snapshot()
	player._process(0.5)
	_check(player.get_hit_reaction_snapshot() == paused, "modal suspension freezes the remaining player damage feedback")
	player.resume_from_overlay()
	player._update_hit_reaction(0.50)
	_check(is_zero_approx(float(player.get_hit_reaction_snapshot().get("damage_mark_strength", 1.0))), "damage feedback settles after gameplay resumes")
	_check(player.global_position == physical_position and is_equal_approx((player.collision_shape.shape as CircleShape2D).radius, physical_radius), "all motion settings preserve the physical hurtbox and position")

	player.reset_player()
	player.set_play_enabled(true)
	player.try_begin_fold()
	_check(player.capture_one() and player.visual_flash > 0.0, "capturing a projectile retains its original white-light feedback")
	_check(is_zero_approx(float(player.get_hit_reaction_snapshot().get("damage_mark_strength", 1.0))), "capture feedback never creates the player's coral damage cue")
	player.cancel_fold()
	player.damage_grace_add = 0.25
	_check(player.take_hit(Vector2.ZERO) and is_equal_approx(player.invulnerability, 1.60), "extended immunity keeps its existing duration with damage feedback enabled")
	_check(Vector2(player.get_hit_reaction_snapshot().get("source_direction", Vector2.ZERO)).is_normalized(), "directionless terrain hits still receive a valid directional cue")
	player.reset_player()
	_check(not bool(player.get_hit_reaction_snapshot().get("active", true)) and is_zero_approx(float(player.get_hit_reaction_snapshot().get("damage_mark_strength", 1.0))), "starting a fresh run clears all old damage cues")

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
