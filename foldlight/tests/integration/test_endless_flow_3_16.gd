extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	await process_frame
	await process_frame
	slice.set_process(false)
	slice.set_physics_process(false)
	slice.player.set_physics_process(false)
	slice.combat_runtime.set_physics_process(false)
	_test_reward_recovery(slice)
	_test_real_deaths_and_dual_reward(slice)
	_test_spawning_and_retirement(slice)
	_test_expired_captain_cleanup(slice)
	slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_ENDLESS_FLOW_3_16: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _fresh(slice: FoldlightEndlessSliceRuntime, seed: int = 316002) -> void:
	slice.start_slice(seed)
	slice.combat_runtime.set_physics_process(false)
	slice.player.set_physics_process(false)

func _enter_cards(slice: FoldlightEndlessSliceRuntime) -> void:
	for step in 6:
		slice._process(0.1)

func _claim(slice: FoldlightEndlessSliceRuntime) -> void:
	_enter_cards(slice)
	var options := slice.controller.get_pending_mission_rewards()
	check(not options.is_empty() and slice.presentation.screen_kind == &"reward", "pending reward reaches real card presentation")
	if not options.is_empty():
		slice._on_reward_chosen(StringName(options[0]["id"]))

func _test_reward_recovery(slice: FoldlightEndlessSliceRuntime) -> void:
	_fresh(slice)
	var task := slice.controller.objectives.get_snapshot()
	slice._pause_game()
	# Model an already-issued completion notification arriving while a menu
	# owns the UI: the task entitlement must outlive the missed offered signal.
	slice.controller.objectives.advance(float(task.required), task.target_position)
	check(slice._modal_kind == &"pause" and not slice.controller.peek_pending_reward().is_empty(), "a paused completion retains its reward without replacing the pause menu")
	slice._resume_game()
	check(slice._modal_kind == &"objective_complete" and not slice.combat_runtime.active, "resuming recovers a completed task and keeps combat frozen")
	_enter_cards(slice)
	check(slice.presentation.screen_kind == &"reward", "recovered completion cannot remain a targetless HUD")
	var old_token := slice._reward_token
	var option := StringName(slice._modal_options[0].id)
	slice.player.health = 1
	slice._on_reward_chosen(option)
	check(slice.player.health == 2 and slice.controller.weapon_levels.size() >= 1 and slice._modal_kind.is_empty(), "task grants its original reinforcement plus one health and resumes play")
	check(slice.controller.claim_pending_reward(old_token, option).is_empty() and slice.player.health == 2, "repeated old token cannot grant another item or heal")
	_fresh(slice)
	task = slice.controller.objectives.get_snapshot()
	slice.controller.mission_reward_offered.disconnect(slice._on_mission_reward_offered)
	slice.controller.objectives.advance(float(task.required), task.target_position)
	check(slice._modal_kind.is_empty(), "lost-notification fixture has only a queued entitlement")
	slice._process(0.016)
	check(slice._modal_kind == &"objective_complete", "safe-frame polling restores a missed completion notification")
	slice.controller.mission_reward_offered.connect(slice._on_mission_reward_offered)
	_fresh(slice)
	check(slice.controller.peek_pending_reward().is_empty() and slice._reward_token.is_empty(), "restart cancels old entitlements and presentation tokens")

func _test_real_deaths_and_dual_reward(slice: FoldlightEndlessSliceRuntime) -> void:
	_fresh(slice)
	slice._clear_pending_spawns()
	for index in 20:
		var actor := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1800, 1600)}, false)
		actor.take_damage(1000.0)
	check(int(slice.controller.evolution.get_experience_snapshot().total_xp) == 40, "real ordinary actors award kill XP through shared combat signals")
	var threshold_kill := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(1800, 1600)}, false)
	threshold_kill.take_damage(1000.0)
	check(slice.controller.evolution.get_experience_snapshot().level == 2 and slice._reward_context.get("source") == &"kill_level", "ordinary kills trigger a real level-up reward without a mission")
	_claim(slice)
	check(slice.controller.evolution.get_experience_snapshot().total_modifiers != {} and slice.combat_runtime.active, "experience reward applies build growth and resumes combat")
	_fresh(slice, 316003)
	slice.controller.evolution.record_kill_experience(34)
	for step in 7:
		slice._advance_spawn_queue(0.1)
	var captain: Node2D
	for actor: Node2D in slice.combat_runtime.enemies:
		if bool((actor.get_meta("directed_spawn_entry", {}) as Dictionary).get("is_captain", false)):
			captain = actor
	check(is_instance_valid(captain), "task captain arrives through the staged spawn queue")
	if is_instance_valid(captain):
		captain.take_damage(1000.0)
		check(slice._reward_context.get("source") == &"mission", "one real captain kill presents the completed task first")
		_claim(slice)
		check(slice._reward_context.get("source") == &"kill_level" and not slice.combat_runtime.active, "same-kill level-up remains queued after task claim")
		_claim(slice)
		check(slice.controller.peek_pending_reward().is_empty() and slice.combat_runtime.active, "both rewards are consumed exactly once before combat resumes")

func _test_spawning_and_retirement(slice: FoldlightEndlessSliceRuntime) -> void:
	_fresh(slice)
	var pending := slice._pending_spawns.size()
	check(pending > 0 and slice.combat_runtime.enemies.is_empty(), "opening reinforcement shows a warning before actors exist")
	var marker: Node = slice._pending_spawns[0].marker.get_ref()
	slice._advance_spawn_queue(5.0)
	check(slice.combat_runtime.enemies.is_empty() and is_equal_approx(marker.remaining, 0.55), "a long frame retains the visible warning on the same bounded clock")
	slice._pause_game()
	slice._advance_spawn_queue(5.0)
	check(is_equal_approx(marker.remaining, 0.55), "pause freezes both the entry queue and its visible marker")
	slice._resume_game()
	for step in 5:
		slice._advance_spawn_queue(0.1)
	check(slice.combat_runtime.enemies.is_empty(), "warning remains visible for its full interval")
	slice._advance_spawn_queue(0.1)
	check(slice.combat_runtime.enemies.size() > 0 and slice.combat_runtime.enemies.size() <= 2, "one presentation step creates at most two actors")
	for index in 12:
		slice._report_population()
		slice.controller.force_next_wave()
	check(slice._pending_spawns.size() + slice.combat_runtime.enemies.size() <= 28, "same-frame waves count queued and live actors toward the opening limit")
	slice._clear_pending_spawns()
	slice.combat_runtime.clear_combat()
	slice.combat_runtime.set_active(true)
	var actor := slice.combat_runtime._spawn_enemy_from_entry({"enemy_id": &"drifter", "spawn_position": Vector2(100, 100)}, false)
	slice.player.global_position = Vector2(4800, 3500)
	var kills_before := slice.controller.defeated_total
	for step in 23:
		slice._retire_distant_enemies(0.5)
	check(slice.combat_runtime.enemies.has(actor), "distant actors remain for the full grace interval")
	slice._retire_distant_enemies(0.5)
	check(not slice.combat_runtime.enemies.has(actor) and slice.controller.defeated_total == kills_before and slice.controller.evolution.get_experience_snapshot().total_xp == 0, "distant cleanup grants neither kill credit nor experience")

func _test_expired_captain_cleanup(slice: FoldlightEndlessSliceRuntime) -> void:
	_fresh(slice, 316003)
	for step in 7:
		slice._advance_spawn_queue(0.1)
	var captain: Node2D
	for actor: Node2D in slice.combat_runtime.enemies:
		if bool((actor.get_meta("directed_spawn_entry", {}) as Dictionary).get("is_captain", false)):
			captain = actor
	check(is_instance_valid(captain), "expiry fixture contains a real task captain")
	var task := slice.controller.objectives.get_snapshot()
	slice._on_objective_failed(task)
	check(not slice.combat_runtime.enemies.has(captain) and slice.controller.evolution.get_experience_snapshot().total_xp == 0 and slice.controller.peek_pending_reward().is_empty(), "expired task captain is retired without XP or a false task reward")
	_fresh(slice, 316003)
	task = slice.controller.objectives.get_snapshot()
	slice._on_objective_failed(task)
	check(not slice._has_pending_captain(StringName(task.target_id)), "expired captain cannot arrive from an older pending warning")

func check(value: bool, label: String) -> void:
	print(("[PASS] " if value else "[FAIL] ") + label)
	if not value:
		failures.append(label)
