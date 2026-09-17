class_name FoldlightBossLab
extends Node2D

enum Mode { TITLE, FIGHT, PAUSED, RESULT }
var mode: Mode = Mode.TITLE
var selected_profile: StringName = &"normal"
var boss: FoldlightBalancedBoss
var elapsed := 0.0

@onready var player: FoldlightBalancedPlayer = $Player
@onready var world: FoldlightRogueWorld = $World
var overlay: ColorRect
var title_label: Label
var info_label: Label
var hint_label: Label
var buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	world.combat_runtime.player_hit.connect(_on_player_hit)
	world.combat_runtime.enemy_defeated.connect(_on_enemy_defeated)
	show_title()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Label.new()
	hud.name = "HUD"
	hud.position = Vector2(28, 22)
	hud.add_theme_font_size_override("font_size", 24)
	layer.add_child(hud)
	hint_label = Label.new()
	hint_label.position = Vector2(520, 28)
	hint_label.size = Vector2(900, 50)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 24)
	layer.add_child(hint_label)
	overlay = ColorRect.new()
	overlay.color = Color(0.015,0.025,0.07,0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(560, 250)
	panel.size = Vector2(800, 580)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(panel)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 46)
	panel.add_child(title_label)
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 22)
	panel.add_child(info_label)
	for text in ["Normal - Start Demo", "Relaxed", "Challenge", "Retry", "Back"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(520, 58)
		button.add_theme_font_size_override("font_size", 22)
		panel.add_child(button)
		buttons.append(button)
	buttons[0].pressed.connect(func(): start_boss(&"normal"))
	buttons[1].pressed.connect(func(): start_boss(&"relaxed"))
	buttons[2].pressed.connect(func(): start_boss(&"challenge"))
	buttons[3].pressed.connect(func(): start_boss(selected_profile))
	buttons[4].pressed.connect(show_title)

func show_title() -> void:
	get_tree().paused = false
	mode = Mode.TITLE
	world.deactivate()
	world.combat_runtime.clear_combat()
	player.cancel_fold()
	player.set_play_enabled(false)
	player.visible = false
	boss = null
	overlay.show()
	title_label.text = "FOLDLIGHT · Reflect Combat Demo"
	info_label.text = "One boss. Two phases. Clear warnings.\nPurple petals = capture. Black/gold = dodge.\nHold SPACE to Fold, release to return. SHIFT dashes.\nNormal is the intended balance."
	buttons[0].show(); buttons[1].show(); buttons[2].show(); buttons[3].hide(); buttons[4].hide()
	buttons[0].grab_focus()

func start_boss(profile_id: StringName) -> void:
	var settings := FoldlightBossLabConfig.profile(profile_id)
	if settings.is_empty(): return
	get_tree().paused = false
	selected_profile = profile_id
	world.deactivate()
	player.set_play_enabled(false)
	player.configure_lab(settings)
	var errors := world.load_room(player, &"boss_lab", Vector2(1920,1080), [], Color(0.35,0.85,0.80), 20260917, &"paper_reef")
	if not errors.is_empty():
		push_error("Boss Lab room failed: " + "; ".join(errors)); show_title(); return
	world.activate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.camera.set_active(false)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.play_bounds = Rect2(70,145,1780,745)
	player.global_position = Vector2(960,790)
	player.visible = true
	player.set_play_enabled(true)
	boss = (world.combat_runtime as FoldlightBalancedCombat).add_lab_boss(settings)
	elapsed = 0.0
	mode = Mode.FIGHT
	overlay.hide()

func _physics_process(delta: float) -> void:
	if mode != Mode.FIGHT or get_tree().paused: return
	elapsed += delta
	if not is_instance_valid(boss): return
	var snap := boss.get_lab_snapshot()
	var hud := get_node("CanvasLayer/HUD") as Label
	hud.text = "HP %d/%d   Fold %d/%d   Dash %.1fs   Time %.1fs" % [player.health,player.max_health,player.captured,player.get_capture_capacity(),player.dash_component.cooldown_remaining,elapsed]
	hint_label.text = "PHASE %d   %s" % [int(snap["phase"]), String(snap["caption"])]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_game") and not event.is_echo():
		if mode == Mode.FIGHT: pause_fight()
		elif mode == Mode.PAUSED: resume_fight()
		get_viewport().set_input_as_handled()

func pause_fight() -> void:
	mode = Mode.PAUSED
	get_tree().paused = true
	overlay.show()
	title_label.text = "Paused"
	info_label.text = "ESC resumes."
	buttons[0].hide(); buttons[1].hide(); buttons[2].hide(); buttons[3].hide(); buttons[4].hide()

func resume_fight() -> void:
	get_tree().paused = false
	mode = Mode.FIGHT
	player.reconcile_after_pause()
	overlay.hide()

func _on_player_hit(health: int) -> void:
	if health <= 0: _finish(false)

func _on_enemy_defeated(_enemy_id: StringName) -> void:
	_finish(true)

func _finish(won: bool) -> void:
	if mode != Mode.FIGHT: return
	mode = Mode.RESULT
	player.set_play_enabled(false)
	world.combat_runtime.set_active(false)
	get_tree().paused = true
	overlay.show()
	title_label.text = "CLEAR" if won else "LIGHT OUT"
	info_label.text = ("Boss defeated" if won else "Try reading the warning before reacting") + "\nTime: %.1f s\nNormal target: roughly 75-105 s after tuning." % elapsed
	buttons[0].hide(); buttons[1].hide(); buttons[2].hide(); buttons[3].show(); buttons[4].show()
	buttons[3].grab_focus()

func _draw() -> void:
	draw_rect(Rect2(0,0,1920,1080), Color(0.025,0.040,0.085))
	for i in 12:
		var y := 155.0 + i * 65.0
		draw_line(Vector2(60,y),Vector2(1860,y),Color(0.18,0.31,0.36,0.16),1.0)
	draw_rect(Rect2(68,143,1784,749),Color(0.37,0.64,0.64,0.4),false,2.0)
