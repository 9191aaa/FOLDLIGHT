class_name FoldlightBossLab
extends Node2D

enum Mode { TITLE, FIGHT, PAUSED, RESULT }
var mode: Mode = Mode.TITLE
var selected_profile: StringName = &"normal"
var boss: FoldlightBalancedBoss
var elapsed: float = 0.0

@onready var player: FoldlightBalancedPlayer = $Player
@onready var world: FoldlightRogueWorld = $World
var overlay: ColorRect
var title_label: Label
var info_label: Label
var hint_label: Label
var hud_label: Label
var buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	world.combat_runtime.player_hit.connect(_on_player_hit)
	world.combat_runtime.enemy_defeated.connect(_on_enemy_defeated)
	show_title()
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_packaged_smoke")

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer"
	add_child(layer)
	hud_label = Label.new()
	hud_label.name = "HUD"
	hud_label.position = Vector2(28, 22)
	hud_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(hud_label)
	hint_label = Label.new()
	hint_label.position = Vector2(610, 28)
	hint_label.size = Vector2(1280, 50)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(hint_label)
	var controls := Label.new()
	controls.text = "WASD / ARROWS: move     SPACE: hold to collect, release to return     SHIFT: dash     ESC: pause"
	controls.position = Vector2(225, 1008)
	controls.add_theme_font_size_override("font_size", 23)
	layer.add_child(controls)
	overlay = ColorRect.new()
	overlay.color = Color(0.015, 0.025, 0.07, 0.94)
	overlay.size = Vector2(1920, 1080)
	layer.add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(480, 220)
	panel.size = Vector2(960, 600)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 16)
	overlay.add_child(panel)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	panel.add_child(title_label)
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 24)
	panel.add_child(info_label)
	for text: String in ["Normal - Start Demo", "Relaxed", "Challenge", "Retry", "Back to title", "Quit"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(520, 58)
		button.add_theme_font_size_override("font_size", 24)
		panel.add_child(button)
		buttons.append(button)
	buttons[0].pressed.connect(func() -> void: start_boss(&"normal"))
	buttons[1].pressed.connect(func() -> void: start_boss(&"relaxed"))
	buttons[2].pressed.connect(func() -> void: start_boss(&"challenge"))
	buttons[3].pressed.connect(func() -> void: start_boss(selected_profile))
	buttons[4].pressed.connect(show_title)
	buttons[5].pressed.connect(func() -> void: get_tree().quit())

func show_title() -> void:
	get_tree().paused = false
	mode = Mode.TITLE
	world.deactivate()
	world.combat_runtime.clear_combat()
	player.cancel_fold()
	player.set_play_enabled(false)
	player.visible = false
	boss = null
	hud_label.text = ""
	hint_label.text = ""
	overlay.show()
	title_label.text = "FOLDLIGHT / Reflect Combat Demo"
	info_label.text = "One boss. Two phases. Read the warning, send the light back.\nPurple petals = capture. Black/gold = dodge.\nHold SPACE to collect, release to attack. SHIFT dashes.\nStart with Normal, or choose Relaxed for more breathing room."
	_show_buttons([0, 1, 2, 5])
	buttons[0].grab_focus()

func _show_buttons(indices: Array) -> void:
	for index in buttons.size():
		buttons[index].visible = index in indices

func start_boss(profile_id: StringName) -> void:
	var settings: Dictionary = FoldlightBossLabConfig.profile(profile_id)
	if settings.is_empty():
		return
	get_tree().paused = false
	selected_profile = profile_id
	world.deactivate()
	player.set_play_enabled(false)
	player.configure_lab(settings)
	var errors: Array[String] = world.load_room(player, &"boss_lab", Vector2(1920, 1080), [], Color(0.35, 0.85, 0.80), 20260917, &"paper_reef")
	if not errors.is_empty():
		push_error("Boss Lab room failed: " + "; ".join(errors))
		show_title()
		return
	world.activate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.camera.set_active(false)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.play_bounds = Rect2(70, 145, 1780, 745)
	player.global_position = Vector2(960, 790)
	player.visible = true
	player.set_play_enabled(true)
	boss = (world.combat_runtime as FoldlightBalancedCombat).add_lab_boss(settings)
	elapsed = 0.0
	mode = Mode.FIGHT
	overlay.hide()

func _physics_process(delta: float) -> void:
	if mode != Mode.FIGHT or get_tree().paused:
		return
	elapsed += delta
	if not is_instance_valid(boss):
		return
	var snap: Dictionary = boss.get_lab_snapshot()
	hud_label.text = "HP %d/%d   Fold %d/%d   Dash %.1fs   %.1fs" % [player.health, player.max_health, player.captured, player.get_capture_capacity(), player.dash_component.cooldown_remaining, elapsed]
	hint_label.text = "PHASE %d   %s" % [int(snap["phase"]), String(snap["caption"])]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game") and not event.is_echo():
		if mode == Mode.FIGHT:
			pause_fight()
		elif mode == Mode.PAUSED:
			resume_fight()
		get_viewport().set_input_as_handled()

func pause_fight() -> void:
	mode = Mode.PAUSED
	get_tree().paused = true
	overlay.show()
	title_label.text = "Paused"
	info_label.text = "Press ESC to resume."
	_show_buttons([4, 5])

func resume_fight() -> void:
	get_tree().paused = false
	mode = Mode.FIGHT
	player.reconcile_after_pause()
	overlay.hide()

func _on_player_hit(health: int) -> void:
	if health <= 0:
		_finish(false)

func _on_enemy_defeated(_enemy_id: StringName) -> void:
	_finish(true)

func _finish(won: bool) -> void:
	if mode != Mode.FIGHT:
		return
	mode = Mode.RESULT
	player.set_play_enabled(false)
	world.combat_runtime.set_active(false)
	get_tree().paused = true
	overlay.show()
	title_label.text = "CLEAR" if won else "LIGHT OUT"
	info_label.text = ("Boss defeated!" if won else "Read the warning. Release your light. Dash out of danger.") + "\nTime: %.1f s\nRetry starts directly at the boss with full health." % elapsed
	_show_buttons([3, 4, 5])
	buttons[3].grab_focus()

func _run_packaged_smoke() -> void:
	start_boss(&"normal")
	if mode != Mode.FIGHT or not is_instance_valid(boss):
		push_error("Packaged demo did not start")
		get_tree().quit(1)
		return
	player.set_debug_invincible(true)
	for frame in 240:
		if frame == 100:
			player.try_begin_fold()
		if frame == 150:
			player.release_fold_action()
		await get_tree().physics_frame
	pause_fight()
	await get_tree().process_frame
	resume_fight()
	print("FOLDLIGHT_EXE_SMOKE_PASS")
	get_tree().quit(0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.025, 0.040, 0.085))
	for i in 12:
		var y: float = 155.0 + i * 65.0
		draw_line(Vector2(60, y), Vector2(1860, y), Color(0.18, 0.31, 0.36, 0.16), 1.0)
	draw_rect(Rect2(68, 143, 1784, 749), Color(0.37, 0.64, 0.64, 0.4), false, 2.0)
