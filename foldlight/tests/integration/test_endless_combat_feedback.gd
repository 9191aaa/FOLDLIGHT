extends SceneTree

var failures: Array[String] = []
var cues: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	var original_settings := profile.settings.duplicate(true)
	profile.settings["screen_shake"] = 0.0
	profile.settings["vibration"] = false
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_physics_process(false)
	slice.set_process(false)
	slice.world.process_mode = Node.PROCESS_MODE_DISABLED
	slice.player.set_process(false)
	slice.player.set_physics_process(false)
	var audio := slice.audio_director
	audio.set_process(false)
	audio.sfx_requested.connect(_record_cue)
	audio.reset_combat_feedback()
	var combat := slice.combat_runtime
	combat.clear_combat()
	check(audio == root.get_node("AudioDirector") and slice.get_node_or_null("AudioDirector") == null, "endless reuses the one music/SFX autoload without creating a second soundtrack")
	check(is_zero_approx(slice._feedback_motion_scale) and not slice._feedback_vibration, "endless startup applies the existing shake and vibration preferences")
	check(is_zero_approx(slice.player._feedback_motion_scale), "the same preference reaches the shared player body feedback")

	var actor := combat._spawn_enemy_from_entry({"enemy_id": &"fan", "spawn_position": slice.player.global_position + Vector2(340, -120), "health_multiplier": 20.0}, false)
	var initial_health := float(actor.get("health"))
	var shot := combat._spawn_projectile({"origin": actor.global_position + Vector2(100, 0), "velocity": Vector2.LEFT * 400.0, "hostile": false, "damage": 1.0, "style": &"crease_petal"})
	combat._resolve_friendly_collision(shot)
	check(cues.is_empty(), "a genuine near miss remains silent")
	shot.global_position = actor.global_position
	combat._resolve_friendly_collision(shot)
	check(cues == [&"paper_hit"] and float(actor.get("health")) < initial_health, "actual automatic-weapon damage produces the short paper impact")
	for index in 30:
		var volley := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.LEFT * 400.0, "hostile": false, "damage": 0.1, "style": &"crease_petal"})
		combat._resolve_friendly_collision(volley)
	check(cues.count(&"paper_hit") == 1, "one volley cannot multiply the same impact sound")
	var returned := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.UP * 600.0, "hostile": false, "damage": 1.0, "style": &"return_light"})
	combat._resolve_friendly_collision(returned)
	check(cues.count(&"return_hit") == 1, "actual returned light has a separate heavier impact cue")
	var kill_shot := combat._spawn_projectile({"origin": actor.global_position, "velocity": Vector2.UP * 600.0, "hostile": false, "damage": 10000.0, "style": &"return_light"})
	combat._resolve_friendly_collision(kill_shot)
	check(cues.count(&"paper_break") == 1 and combat.enemies.is_empty(), "a real defeat produces one break cue without an extra enemy-defeated sound")
	check(is_zero_approx(slice.camera._trauma), "kill feedback respects the zero-shake setting")

	combat.clear_combat()
	audio.reset_combat_feedback()
	cues.clear()
	check(slice.player.try_begin_fold() and cues == [&"fold"], "opening the actual Fold announces the change once")
	for index in 4:
		combat._spawn_projectile({"origin": slice.player.global_position + Vector2(36 + index * 4, 0), "velocity": Vector2.LEFT * 40.0, "hostile": true, "reflectable": true, "damage": 1.0, "style": &"hostile_petal"})
	combat._update_projectiles(0.0)
	check(slice.player.captured == 4 and cues.count(&"capture") == 1, "four actual captures retain all light while coalescing their sound")
	slice.player.release_fold_action()
	check(cues.count(&"release") == 1 and combat.projectiles.size() == 4, "releasing stored light keeps the real salvo and emits one release sound")
	check(is_zero_approx(slice.camera._trauma), "returned-light camera motion is also disabled at zero shake")
	combat.clear_combat()
	slice.player._hit_stop_timer = 0.0

	var position_before := slice.player.global_position
	var velocity_before := slice.player.velocity
	var score_before := slice.controller.evolution.survival_seconds
	for index in 100:
		audio._process(0.01)
		slice._on_combat_impact_confirmed(&"weapon", 0.5)
	check(is_equal_approx(slice.controller.evolution.survival_seconds, score_before), "audio clocks never grant effective race survival time")
	check(slice.player.global_position == position_before and slice.player.velocity == velocity_before and is_zero_approx(slice.player._hit_stop_timer) and is_equal_approx(Engine.time_scale, 1.0), "feedback changes neither movement, hit-stop nor global simulation speed")
	slice._physics_process(0.5)
	check(is_equal_approx(slice.controller.evolution.survival_seconds, score_before + 0.5), "normal endless simulation retains its exact effective-time increment")

	slice._pause_game()
	var cue_count := cues.size()
	slice._on_combat_impact_confirmed(&"return", 1.0)
	slice._on_feedback_fold_started()
	check(cues.size() == cue_count and not combat._try_hit_player(Vector2.RIGHT), "paused combat cannot trigger attack or damage feedback")
	slice._resume_game()
	slice.player.invulnerability = 0.0
	audio.reset_combat_feedback()
	cues.clear()
	var hit_points := slice.player.health
	var before_image: Image
	if DisplayServer.get_name().to_lower() != "headless":
		slice.camera.force_follow(1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		before_image = root.get_texture().get_image()
	check(combat._try_hit_player(Vector2.RIGHT) and slice.player.health == hit_points - 1, "real damage still removes exactly one health point")
	check(slice.status_label.text.contains("灯芯 %d/%d" % [slice.player.health, slice.player.max_health]), "damage immediately refreshes the visible health count without waiting for the HUD timer")
	check(cues == [&"hurt"], "real damage immediately takes audio priority")
	check(not audio.play_combat_impact(&"weapon", 1.0) and not audio.play_combat_impact(&"return", 1.0), "weak impacts cannot mask the first 160 milliseconds of the hurt cue")
	check(is_zero_approx(slice.camera._trauma) and is_zero_approx(slice.camera._hit_kick_remaining) and Vector2(slice.player.get_hit_reaction_snapshot()["offset"]).is_zero_approx(), "zero shake disables camera and body recoil while retaining the hit")
	check(slice.damage_flash.visible and slice.damage_flash.material is ShaderMaterial and slice.damage_flash.mouse_filter == Control.MOUSE_FILTER_IGNORE, "damage uses a noninteractive edge-only shader overlay")
	var after_hit := cues.size()
	check(not combat._try_hit_player(Vector2.UP) and cues.size() == after_hit, "an invulnerable collision cannot repeat hurt audio or damage feedback")
	if before_image != null:
		await process_frame
		await RenderingServer.frame_post_draw
		var after_image := root.get_texture().get_image()
		var center := Vector2i(after_image.get_width() / 2 + 150, after_image.get_height() / 2)
		var edge := Vector2i(5, after_image.get_height() / 2)
		check(_pixel_difference(before_image.get_pixelv(center), after_image.get_pixelv(center)) < 0.015, "real renderer keeps the central combat field untinted during damage")
		check(_pixel_difference(before_image.get_pixelv(edge), after_image.get_pixelv(edge)) > 0.08, "real renderer makes the outer damage rim visible")
		var output_dir := ProjectSettings.globalize_path("res://build/test-runtime/endless-feedback-capture")
		DirAccess.make_dir_recursive_absolute(output_dir)
		after_image.save_png(output_dir.path_join("endless_damage.png"))
		print("CAPTURED " + output_dir.path_join("endless_damage.png"))
	slice._process(0.30)
	check(not slice.damage_flash.visible, "the edge cue expires promptly instead of leaving a red veil")
	audio._process(0.20)
	check(audio.play_combat_impact(&"weapon", 0.5), "ordinary impact sound resumes after hurt emphasis")
	slice._feedback_motion_scale = 1.0
	slice._on_combat_impact_confirmed(&"return", 0.8)
	check(slice.camera._hit_kick_remaining > 0.0 and is_equal_approx(slice.camera._hit_kick_strength, 0.32), "return impact adds a bounded camera kick when motion is enabled")
	slice.camera._update_shake(0.06)
	var kick_remaining := slice.camera._hit_kick_remaining
	for index in 20:
		slice._on_combat_impact_confirmed(&"return", 0.8)
	check(is_equal_approx(slice.camera._hit_kick_remaining, kick_remaining), "a returned-light salvo cannot keep restarting the camera kick")
	_test_sound_shapes(audio)
	_test_voice_priority(audio)
	audio.sfx_requested.disconnect(_record_cue)
	profile.settings = original_settings
	audio.set_process(true)
	slice.queue_free()
	await process_frame
	print("FOLDLIGHT_ENDLESS_COMBAT_FEEDBACK: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_sound_shapes(audio: FoldlightAudioDirector) -> void:
	var paper := audio._synthesize_sfx(&"paper_hit")
	var reflected := audio._synthesize_sfx(&"return_hit")
	var broken := audio._synthesize_sfx(&"paper_break")
	check(paper.get_length() < 0.08 and reflected.get_length() > paper.get_length() * 1.9 and broken.get_length() < 0.20, "generated hit, return and break sounds have distinct bounded durations")
	var audible := true
	var unclipped := true
	for stream: AudioStreamWAV in [paper, reflected, broken]:
		var maximum := 0
		for index in range(0, stream.data.size(), 2):
			maximum = maxi(maximum, absi(stream.data.decode_s16(index)))
		audible = audible and maximum > 500
		unclipped = unclipped and maximum < 32760
	check(audible and unclipped, "all generated combat cues contain audible unclipped PCM")


func _test_voice_priority(audio: FoldlightAudioDirector) -> void:
	if audio._sfx_players.is_empty():
		audio._build_sfx_pool()
	audio._sfx[&"hurt"] = audio._synthesize_sfx(&"hurt")
	audio._sfx[&"capture"] = audio._synthesize_sfx(&"capture")
	for voice in audio._sfx_players:
		voice.stop()
		voice.stream = audio._sfx[&"hurt"]
		voice.set_meta(&"sfx_priority", 3)
		voice.play()
	var before := cues.size()
	audio.play_sfx(&"capture", 1.0, -4.0)
	check(cues.size() == before, "a saturated pool never steals a protected hurt voice for a weak sound")
	audio.play_sfx(&"hurt", 0.96, -4.0)
	check(cues.size() == before + 1 and cues.back() == &"hurt", "hurt can still claim a voice when the pool is saturated")
	for voice in audio._sfx_players:
		voice.stop()


func _record_cue(sound_name: StringName, _pitch: float, _volume: float) -> void:
	cues.append(sound_name)


func _pixel_difference(first: Color, second: Color) -> float:
	return absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)


func check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
