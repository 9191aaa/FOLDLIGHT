class_name FoldlightBossLab
extends Node2D

# Preserve the tested Boss Lab entry while adding a finite, authored voyage.
enum Mode { TITLE, FIGHT, PAUSED, RESULT, REWARD }
var mode: Mode = Mode.TITLE
var selected_profile: StringName = &"normal"
var boss: FoldlightBalancedBoss
var elapsed: float = 0.0
var is_voyage: bool = false
var stage_index: int = 3
var wave_index: int = 0
var upgrades: Array[StringName] = []
var run_kills: int = 0
var total_captures: int = 0
var ui: FoldlightDemoUI
var feedback: FoldlightDemoFeedback
var hud_label: Label
var hint_label: Label
var _settings: Dictionary = {}
var _pending_entries: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _between_waves: float = 0.0
var _result_delay: float = -1.0
var _won: bool = false
var _ambience: float = 0.0
var _shake_level: int = 1
var _no_persist: bool = false

@onready var player: FoldlightBalancedPlayer = $Player
@onready var world: FoldlightRogueWorld = $World

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_no_persist = DisplayServer.get_name().to_lower() == "headless" or "--capture-preview" in OS.get_cmdline_user_args()
	ui = FoldlightDemoUI.new()
	add_child(ui)
	feedback = FoldlightDemoFeedback.new()
	add_child(feedback)
	hud_label = ui.hud
	hint_label = ui.hint_label
	ui.action_requested.connect(_on_action)
	ui.reward_requested.connect(choose_reward)
	var combat := world.combat_runtime as FoldlightBalancedCombat
	combat.player_hit.connect(_on_player_hit)
	combat.enemy_defeated.connect(_on_enemy_defeated)
	combat.projectile_captured.connect(_on_capture)
	combat.impact_requested.connect(feedback.impact)
	combat.enemy_broken.connect(feedback.broken)
	player.fold_released.connect(_on_release)
	player.dash_started.connect(_on_dash)
	_load_preferences()
	show_title()
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_packaged_smoke")

func _profile_title() -> String:
	return {&"normal": "标准", &"relaxed": "轻松", &"challenge": "挑战"}.get(selected_profile, "标准")

func _shake_title() -> String:
	return ["关闭", "轻微（推荐）", "标准"][ _shake_level ]

func _load_preferences() -> void:
	if not _no_persist:
		var config := ConfigFile.new()
		if config.load("user://demo_preferences.cfg") == OK:
			_shake_level = clampi(int(config.get_value("feedback", "shake", 1)), 0, 2)
	feedback.set_strength([0.0, 0.55, 1.0][_shake_level])

func cycle_shake() -> void:
	_shake_level = (_shake_level + 1) % 3
	feedback.set_strength([0.0, 0.55, 1.0][_shake_level])
	if not _no_persist:
		var config := ConfigFile.new()
		config.set_value("feedback", "shake", _shake_level)
		config.save("user://demo_preferences.cfg")

func show_title() -> void:
	get_tree().paused = false
	mode = Mode.TITLE
	_result_delay = -1.0
	world.deactivate()
	world.combat_runtime.clear_combat()
	player.cancel_fold()
	player.set_play_enabled(false)
	player.visible = false
	boss = null
	feedback.set_suspended(false)
	feedback.reset()
	ui.show_menu(&"title", _profile_title(), _shake_title())
	_audio_intensity(0.05)

func start_boss(profile_id: StringName) -> void:
	_start_run(profile_id, false)

func start_voyage(profile_id: StringName = &"normal") -> void:
	_start_run(profile_id, true)

func _start_run(profile_id: StringName, voyage: bool) -> void:
	_settings = FoldlightBossLabConfig.profile(profile_id)
	if _settings.is_empty():
		return
	selected_profile = profile_id
	is_voyage = voyage
	upgrades.clear()
	elapsed = 0.0
	run_kills = 0
	total_captures = 0
	_enter_stage(0 if voyage else 3, int(_settings["player_health"]))

func _enter_stage(index: int, carry_health: int) -> void:
	get_tree().paused = false
	world.deactivate()
	player.set_play_enabled(false)
	player.configure_lab(_settings)
	stage_index = index
	wave_index = 0
	boss = null
	_pending_entries.clear()
	_spawn_timer = 0.0
	_between_waves = 0.0
	_result_delay = -1.0
	feedback.set_suspended(false)
	feedback.reset()
	var errors: Array[String] = world.load_room(player, &"reflect_voyage", Vector2(1920, 1080), [], Color("76dbca"), 20260917 + index, &"paper_reef")
	if not errors.is_empty():
		push_error("Demo room failed: " + "; ".join(errors))
		show_title()
		return
	# Keep the original actors; simplify the decorative battlefield for readability.
	for child: Node in world.room_runtime.get_children():
		if child is FoldlightRoomBackdrop:
			(child as CanvasItem).hide()
	world.activate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.camera.set_active(false)
	get_viewport().canvas_transform = Transform2D.IDENTITY
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.play_bounds = Rect2(70, 145, 1780, 745)
	player.global_position = Vector2(960, 790)
	_apply_build()
	player.health = clampi(carry_health, 1, player.max_health)
	player.grant_invulnerability(0.85)
	player.visible = true
	player.set_play_enabled(true)
	mode = Mode.FIGHT
	ui.hide_menu()
	ui.reset_bars()
	if stage_index == 3:
		if is_voyage:
			player.health = maxi(player.health, mini(4, player.max_health))
		boss = (world.combat_runtime as FoldlightBalancedCombat).add_lab_boss(_settings)
		boss.phase_changed.connect(_on_boss_phase)
		boss.stagger_started.connect(_on_boss_break)
		ui.toast("礁冠炮城\n看清预警，再送它一束光。", 3.0)
		_audio_intensity(0.48)
	else:
		_prepare_wave()
		ui.toast("%02d  /  %s\n%s" % [stage_index + 1, FoldlightDemoContent.STAGE_NAMES[stage_index], FoldlightDemoContent.STAGE_HINTS[stage_index]], 3.8)
		_audio_intensity(0.18 + stage_index * 0.08)
	_update_hud()

func _apply_build() -> void:
	var stats: Dictionary = FoldlightDemoContent.build_stats(upgrades, int(_settings["player_health"]))
	player.apply_roguelite_stats(stats)
	world.combat_runtime.apply_build_stats(stats)

func _prepare_wave() -> void:
	_pending_entries = FoldlightDemoContent.wave_entries(stage_index, wave_index)
	for entry: Dictionary in _pending_entries:
		var point: Vector2 = entry["spawn_position"]
		if point.distance_to(player.global_position) < 250.0:
			point.y = 230.0 if player.global_position.y > 500.0 else 790.0
			entry["spawn_position"] = point
		feedback.spawn_marker(point)
	_spawn_timer = 0.90
	_between_waves = 0.0

func _physics_process(delta: float) -> void:
	if mode != Mode.FIGHT or get_tree().paused:
		return
	elapsed += delta
	if stage_index < 3:
		if not _pending_entries.is_empty():
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				world.combat_runtime.spawn_directed_wave(_pending_entries)
				_pending_entries.clear()
		elif world.combat_runtime.enemies.is_empty():
			_between_waves += delta
			if _between_waves >= 0.75:
				if wave_index == 0:
					wave_index = 1
					_prepare_wave()
					ui.toast("第二波 · 光还在路上", 1.8)
				else:
					_clear_stage()
	_update_hud()

func _clear_stage() -> void:
	player.health = mini(player.max_health, player.health + 1)
	(world.combat_runtime as FoldlightBalancedCombat).clear_hostiles()
	if stage_index < 2:
		mode = Mode.REWARD
		player.set_play_enabled(false)
		player.cancel_fold()
		world.combat_runtime.set_active(false)
		get_tree().paused = true
		feedback.set_suspended(true)
		ui.show_rewards(FoldlightDemoContent.REWARDS[stage_index], stage_index + 1)
		_audio_intensity(0.08)
	else:
		_enter_stage(3, player.health)

func choose_reward(index: int) -> void:
	if mode != Mode.REWARD or index < 0 or index >= 3:
		return
	var item: Dictionary = FoldlightDemoContent.REWARDS[stage_index][index]
	var id: StringName = item["id"]
	if id in upgrades:
		return
	upgrades.append(id)
	var hp: int = player.health + int(item.get("heal", 0))
	_enter_stage(stage_index + 1, hp)
	ui.toast("已获得「%s」\n%s" % [item["title"], FoldlightDemoContent.STAGE_NAMES[stage_index]], 2.4)

func retry_checkpoint() -> void:
	if _settings.is_empty():
		return
	var stats: Dictionary = FoldlightDemoContent.build_stats(upgrades, int(_settings["player_health"]))
	_enter_stage(stage_index, 5 + int(stats.get("max_health_add", 0)))

func _build_caption() -> String:
	var names: PackedStringArray = []
	for id: StringName in upgrades:
		names.append(String(FoldlightDemoContent.reward_by_id(id)["title"]))
	return "强化：" + (" · ".join(names) if not names.is_empty() else "尚未选择") + "    /    " + _profile_title()

func _boss_hint() -> String:
	if not is_instance_valid(boss):
		return ""
	match boss.rhythm:
		FoldlightBalancedBoss.Rhythm.INTRO: return "紫色花瓣可收纳；黑芯金边弹要躲。"
		FoldlightBalancedBoss.Rhythm.WARNING: return "黑金封线 · 看清导线，准备横移！" if boss.pattern == &"black_lane" else "弹药将至 · 准备展开折域"
		FoldlightBalancedBoss.Rhythm.BURST: return "黑金弹不可收纳 · 横移或冲刺" if boss.pattern == &"black_lane" else "收纳 → 松手返光 · 不必等到满格"
		FoldlightBalancedBoss.Rhythm.RECOVERY: return "调整站位 · 等待下一束光" if boss.pattern == &"black_lane" else "松手返光！现在是进攻机会"
		FoldlightBalancedBoss.Rhythm.BREAK: return "核心敞开 · 返光伤害 +35%"
		FoldlightBalancedBoss.Rhythm.TRANSITION: return "第二阶段 · 同样的规则，稍快的节奏"
	return ""

func _update_hud() -> void:
	var snap: Dictionary = boss.get_lab_snapshot() if is_instance_valid(boss) else {}
	var stage: String = "%02d / 04  %s" % [stage_index + 1, FoldlightDemoContent.STAGE_NAMES[stage_index]] if is_voyage else "Boss 练习 / 礁冠炮城"
	if stage_index < 3:
		stage += "  ·  %d / 2 波" % (wave_index + 1)
	ui.update_hud({"health": player.health, "max_health": player.max_health, "captured": player.captured, "capacity": player.get_capture_capacity(), "dash_cd": player.dash_component.cooldown_remaining, "fold_cd": player.get_fold_cooldown_remaining(), "stage": stage, "build": _build_caption(), "hint": _boss_hint() if stage_index == 3 else FoldlightDemoContent.STAGE_HINTS[stage_index], "boss": snap})

func _on_action(action: StringName) -> void:
	match action:
		&"voyage": start_voyage(selected_profile)
		&"practice": start_boss(selected_profile)
		&"difficulty":
			var choices: Array[StringName] = [&"normal", &"relaxed", &"challenge"]
			selected_profile = choices[(choices.find(selected_profile) + 1) % 3]
			ui.show_menu(&"title", _profile_title(), _shake_title())
		&"shake":
			cycle_shake()
			ui.show_menu(&"pause" if mode == Mode.PAUSED else &"title", _profile_title(), _shake_title(), _build_caption())
		&"resume": resume_fight()
		&"retry": retry_checkpoint()
		&"again": _start_run(selected_profile, is_voyage)
		&"title": show_title()
		&"quit": get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game") and not event.is_echo():
		if mode == Mode.FIGHT:
			pause_fight()
		elif mode == Mode.PAUSED:
			resume_fight()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
		elif mode == Mode.REWARD and event.keycode in [KEY_1, KEY_2, KEY_3]:
			choose_reward(int(event.keycode - KEY_1))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			var audio := get_node_or_null("/root/AudioDirector") as FoldlightAudioDirector
			if audio != null:
				audio.toggle_mute()
			get_viewport().set_input_as_handled()

func pause_fight() -> void:
	if mode != Mode.FIGHT:
		return
	mode = Mode.PAUSED
	get_tree().paused = true
	feedback.set_suspended(true)
	ui.show_menu(&"pause", _profile_title(), _shake_title(), _build_caption())
	_audio_intensity(0.05)

func resume_fight() -> void:
	if mode != Mode.PAUSED:
		return
	get_tree().paused = false
	mode = Mode.FIGHT
	feedback.set_suspended(false)
	player.reconcile_after_pause()
	ui.hide_menu()
	_audio_intensity(0.48 if stage_index == 3 else 0.22)

func _on_capture(count: int, at: Vector2) -> void:
	total_captures += 1
	feedback.captured(count, at)

func _on_release(count: int, charge: float) -> void:
	feedback.released(count, charge, player.global_position)

func _on_dash(_direction: Vector2, _duration: float) -> void:
	feedback.ring(player.global_position, Color("79decd"), 62.0, 0.18)

func _on_player_hit(health: int) -> void:
	feedback.hurt(player.global_position)
	ui.hurt()
	if health <= 0:
		_finish(false)

func _on_enemy_defeated(_enemy_id: StringName) -> void:
	run_kills += 1
	if is_instance_valid(boss) and boss.health <= 0.0:
		_finish(true)

func _on_boss_phase(_phase: int) -> void:
	if is_instance_valid(boss):
		feedback.phase_changed(boss.global_position)
		ui.toast("核心裂相 · 第二阶段", 1.6)

func _on_boss_break(_duration: float) -> void:
	if is_instance_valid(boss):
		feedback.ring(boss.global_position, Color("efcb8a"), 170.0, 0.45)
		feedback.kick(3.0, 0.18)

func _finish(won: bool) -> void:
	if mode != Mode.FIGHT:
		return
	mode = Mode.RESULT
	_won = won
	_update_hud()
	player.set_play_enabled(false)
	world.combat_runtime.set_active(false)
	get_tree().paused = true
	# Allow visual-only impact tails to finish; all gameplay remains frozen.
	_result_delay = 0.65 if won else 0.35
	_audio_intensity(0.06)

func _process(delta: float) -> void:
	if mode != Mode.PAUSED and mode != Mode.REWARD:
		_ambience += delta
		queue_redraw()
	if _result_delay >= 0.0:
		_result_delay -= delta
		if _result_delay < 0.0:
			var body: String = "累计航行 %.1f 秒 · 收纳 %d 光 · 击破 %d\n\n" % [elapsed, total_captures, run_kills]
			body += "返航完成。换一种强化，再试一条打法。" if _won else "重试从当前关卡开始，恢复满血，\n保留已经选择的强化。\n\n黑金弹不要硬收；存着光也能冲刺。"
			ui.show_menu(&"result", _profile_title(), _shake_title(), body, _won)

func _audio_intensity(value: float) -> void:
	var audio := get_node_or_null("/root/AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.set_intensity(value)

func _run_packaged_smoke() -> void:
	start_voyage(&"normal")
	player.set_debug_invincible(true)
	for frame in 90:
		await get_tree().physics_frame
	if world.combat_runtime.enemies.is_empty():
		push_error("Packaged voyage did not spawn an encounter")
		get_tree().quit(1)
		return
	start_boss(&"normal")
	player.set_debug_invincible(true)
	for frame in 180:
		if frame == 60:
			player.try_begin_fold()
		if frame == 120:
			player.release_fold_action()
		await get_tree().physics_frame
	pause_fight()
	await get_tree().process_frame
	resume_fight()
	print("FOLDLIGHT_EXE_SMOKE_PASS")
	get_tree().quit(0)

func _draw() -> void:
	# Low-contrast paper-sea motifs; keep the combat plane darker than the projectiles.
	draw_rect(Rect2(-20, -20, 1960, 1120), Color("091923"))
	for row in 14:
		var points := PackedVector2Array()
		for column in 65:
			var x: float = -24.0 + float(column) * 31.0
			var y: float = 143.0 + float(row) * 60.0 + sin(x * 0.004 + float(row) * 0.6 + _ambience * 0.20) * 12.0
			points.append(Vector2(x, y))
		draw_polyline(points, Color(0.20, 0.39, 0.42, 0.14), 1.1, true)
	for i in 32:
		var x: float = fposmod(float(i) * 233.7 + _ambience * (3.0 + float(i % 3)), 1850.0) + 35.0
		var y: float = 160.0 + fposmod(float(i) * 127.3, 725.0)
		var alpha: float = 0.12 + 0.08 * sin(_ambience + float(i))
		draw_circle(Vector2(x, y), 1.3, Color(0.76, 0.84, 0.76, alpha))
	draw_rect(Rect2(68, 143, 1784, 749), Color(0.42, 0.72, 0.67, 0.25), false, 1.5)
	for point: Vector2 in [Vector2(68, 143), Vector2(1852, 143), Vector2(68, 892), Vector2(1852, 892)]:
		var inward := Vector2(1.0 if point.x < 960.0 else -1.0, 1.0 if point.y < 540.0 else -1.0)
		draw_line(point, point + Vector2(52.0 * inward.x, 0), Color("acac79"), 2.5, true)
		draw_line(point, point + Vector2(0, 38.0 * inward.y), Color("acac79"), 2.5, true)
