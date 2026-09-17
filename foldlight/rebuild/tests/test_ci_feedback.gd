extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FEEDBACK FAIL: " + label)

func run_tests() -> void:
	var scene: PackedScene = load("res://rebuild/scenes/boss_lab.tscn")
	var lab := scene.instantiate() as FoldlightBossLab
	root.add_child(lab)
	await process_frame
	lab.start_boss(&"normal")
	var fb: FoldlightDemoFeedback = lab.feedback
	var player: FoldlightBalancedPlayer = lab.player
	# Sample render clocks deterministically; never advance collision bodies here.
	lab.set_physics_process(false)
	lab.world.combat_runtime.set_active(false)
	player.set_physics_process(false)
	fb.set_process(false)
	var player_before: Vector2 = player.global_position
	var boss_before: Vector2 = lab.boss.global_position
	var hud_before: Transform2D = lab.ui.hud.get_global_transform()
	var health_before: int = player.health
	fb.reset()
	fb.set_strength(0.55)
	for i in 8:
		fb.captured(i + 1, player_before)
	check(is_zero_approx(fb.amplitude), "capture sparks do not shake the camera continuously")
	fb.released(0, 0.0, player_before)
	check(is_zero_approx(fb.amplitude), "empty release does not kick")
	fb.released(1, 0.2, player_before)
	var small_release: float = fb.amplitude
	fb.reset()
	fb.released(8, 1.0, player_before)
	var full_release: float = fb.amplitude
	check(is_equal_approx(full_release, 7.04), "default eight-light release has a 7.04 logical-pixel peak")
	check(full_release / 2.86 > 2.4, "same subtle preset is over 2.4x previous full-release amplitude")
	check(full_release > small_release * 2.0, "full reservoir feels stronger than a single bullet")
	check(fb.camera_offset.length() > 7.0, "initial punch is visible without waiting for a random waveform phase")
	check(is_equal_approx(fb.shake_duration, 0.24), "full-release tail is short and explicit")
	fb._process(0.025)
	check(is_equal_approx(fb._envelope(), 1.0), "onset survives the first short render interval")
	var remaining_before: float = fb.shake_remaining
	var duration_before: float = fb.shake_duration
	fb.kick(1.0, 0.05)
	check(fb.shake_remaining == remaining_before and fb.shake_duration == duration_before, "weak impact does not replace release timing")
	check(fb.amplitude == full_release, "weak impact does not re-amplify a full release")
	fb.reset()
	fb.impact(&"boss", boss_before, Vector2.RIGHT, 0.55)
	check(is_zero_approx(fb.amplitude), "weak automatic fire does not cause continuous shake")
	fb.reset()
	fb.impact(&"boss", boss_before, Vector2.RIGHT, 2.8)
	var hit_peak: float = fb.amplitude
	fb._process(0.02)
	var gate_remaining: float = fb.shake_remaining
	fb.impact(&"boss", boss_before, Vector2.RIGHT, 2.8)
	check(fb.shake_remaining == gate_remaining, "rapid multi-hit volley remains rate limited")
	fb.reset()
	fb.broken(boss_before, false)
	var kill_peak: float = fb.amplitude
	fb.reset()
	fb.hurt(player_before)
	var hurt_peak: float = fb.amplitude
	check(hit_peak < kill_peak and kill_peak < full_release and full_release < hurt_peak, "hit, kill, full release and hurt have distinct escalating peaks")
	check(player.global_position == player_before and lab.boss.global_position == boss_before, "feedback never displaces physics actors")
	check(player.health == health_before and lab.boss.health == 320.0, "feedback changes no health or boss difficulty")
	check(lab.ui.transform == Transform2D.IDENTITY and lab.ui.hud.get_global_transform() == hud_before, "HUD transform is independent of camera translation")
	for fps in [30, 60, 144]:
		fb.reset()
		fb.released(8, 1.0, player_before)
		var peak: float = 0.0
		var over_limit: bool = false
		for frame in range(int(fps / 2)):
			fb._process(1.0 / float(fps))
			peak = maxf(peak, fb.camera_offset.length())
			over_limit = over_limit or fb.camera_offset.length() > FoldlightDemoFeedback.MAX_SHAKE + 0.001
		check(peak > 4.0, "%d FPS sampling retains a noticeable full-release impulse" % fps)
		check(not over_limit, "%d FPS offset stays within displacement budget" % fps)
		check(root.canvas_transform == Transform2D.IDENTITY and fb.amplitude == 0.0, "%d FPS returns exactly to rest" % fps)
	fb.reset()
	fb.set_strength(1.0)
	fb.released(8, 1.0, player_before)
	check(is_equal_approx(fb.amplitude, 12.8) and fb.amplitude > full_release, "standard setting is stronger than subtle")
	for i in 200:
		fb.kick(1000.0, 10.0)
		fb.broken(boss_before, true)
	check(fb.amplitude <= 16.0 and fb.shake_duration <= 0.30, "burst event spam cannot exceed amplitude or duration caps")
	check(fb.particles.size() <= FoldlightDemoFeedback.MAX_PARTICLES and fb.rings.size() <= FoldlightDemoFeedback.MAX_RINGS, "visual budgets remain bounded")
	fb._process(0.5)
	check(root.canvas_transform == Transform2D.IDENTITY, "burst event spam settles after events stop")
	fb.set_strength(0.0)
	fb.released(8, 1.0, player_before)
	fb.hurt(player_before)
	fb.broken(boss_before, true)
	fb._process(0.01)
	check(root.canvas_transform == Transform2D.IDENTITY and fb.amplitude == 0.0, "off remains off for every high-impact event")
	fb.set_strength(0.55)
	fb.released(8, 1.0, player_before)
	lab.pause_fight()
	fb.hurt(player_before)
	fb._process(0.05)
	check(fb.suspended and root.canvas_transform == Transform2D.IDENTITY, "pause clears and rejects camera impulses")
	lab.resume_fight()
	check(not fb.suspended and fb.camera_offset == Vector2.ZERO, "resume has no residual jolt")
	fb.reset()
	fb.kick(-10.0, 0.2)
	check(fb.amplitude == 0.0, "negative impulses are ignored")
	check(player.try_begin_fold(), "real player can begin capture")
	for i in 8:
		player.capture_one()
	player.release_fold_action()
	check(is_equal_approx(fb.amplitude, 7.04), "actual full-release signal uses upgraded feedback")
	check(player.captured == 0 and not player.folding, "new feedback does not alter release ownership")
	check(lab.world.combat_runtime.projectiles.size() == 8, "eight stored bullets still become exactly eight returns")
	lab.show_title()
	check(root.canvas_transform == Transform2D.IDENTITY, "returning to title clears feedback offset")
	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOLDLIGHT_FEEDBACK_TESTS_PASS: %d checks" % checks)
		quit(0)
	else:
		print("FOLDLIGHT_FEEDBACK_TESTS_FAIL: " + "; ".join(failures))
		quit(1)
