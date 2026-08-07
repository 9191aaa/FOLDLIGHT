class_name FoldlightQuickTutorialOverlay
extends Control

## Compact, non-modal tutorial card for the roguelite prologue.
##
## This node only presents steps. The session/controller remains responsible
## for deciding when a gameplay action has been performed and calling
## [method show_step] or [method advance].

signal tutorial_completed
signal tutorial_skipped
signal step_changed(step_index: int, step_count: int)

const MAX_STEPS: int = 3
const DEFAULT_STEPS: Array[Dictionary] = [
	{
		"tag": "01  起步",
		"title": "先移动，再穿线",
		"keyboard": "WASD  移动     SHIFT  冲刺",
		"gamepad": "左摇杆  移动     B  冲刺",
		"body": "移动约一小段，再冲刺一次；冲刺 2.0 秒恢复。",
		"warning": "冲刺期间短暂无敌",
	},
	{
		"tag": "02  核心",
		"title": "按住收纳，松开追踪",
		"keyboard": "按住 SPACE  折域     松开  返航",
		"gamepad": "按住 A  折域     松开 A  返航",
		"body": "基础收纳 8 枚可反射弹；松开后自动变成追踪弹。",
		"warning": "每轮收纳后，1.5 秒才能再次展开",
	},
	{
		"tag": "03  生存",
		"title": "你管走位，武器会开火",
		"keyboard": "自动武器  自动攻击     Q  主动技能",
		"gamepad": "自动武器  自动攻击     X  主动技能",
		"body": "自动武器负责输出；主动技能留着解围。",
		"warning": "黑金弹不可反射；脚下地形可能增益，也可能限制走位",
	},
]

@export var listen_for_skip_action: bool = true
@export var manual_advance_enabled: bool = false
@export_range(0.05, 0.5, 0.01) var transition_duration: float = 0.16

var _steps: Array[Dictionary] = []
var _step_index: int = 0
var _gamepad_mode: bool = false
var _finished: bool = false
var _transition: Tween

@onready var card: PanelContainer = %Card
@onready var content: VBoxContainer = %Content
@onready var step_badge_panel: PanelContainer = %StepBadgePanel
@onready var step_badge: Label = %StepBadge
@onready var title_label: Label = %Title
@onready var device_label: Label = %DeviceLabel
@onready var controls_label: Label = %Controls
@onready var body_label: Label = %Body
@onready var warning_panel: PanelContainer = %WarningPanel
@onready var warning_label: Label = %Warning
@onready var step_progress: ProgressBar = %StepProgress
@onready var page_label: Label = %PageLabel
@onready var continue_button: Button = %ContinueButton
@onready var skip_button: Button = %SkipButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = FoldlightRogueUITheme.build()
	_steps = DEFAULT_STEPS.duplicate(true)
	_apply_styles()
	continue_button.pressed.connect(advance)
	skip_button.pressed.connect(skip)
	skip_button.text = "F / LB  跳过并开始"
	set_manual_advance_enabled(manual_advance_enabled)
	_apply_step(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton and event.is_pressed():
		set_input_mode(true)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= 0.45:
		set_input_mode(true)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		set_input_mode(false)
	if listen_for_skip_action and event.is_action_pressed(&"open_tutorial") and not event.is_echo():
		skip()
		get_viewport().set_input_as_handled()


## Resets and opens the tutorial. Gameplay remains active behind the card.
func begin(prefer_gamepad: bool = false) -> void:
	_finished = false
	_step_index = 0
	_gamepad_mode = prefer_gamepad
	show()
	modulate.a = 0.0
	_apply_step(false)
	_kill_transition()
	_transition = create_tween()
	_transition.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_transition.tween_property(self, "modulate:a", 1.0, transition_duration)
	if manual_advance_enabled:
		continue_button.call_deferred("grab_focus")


## Replaces the built-in copy while keeping the three-step limit.
## Each dictionary accepts: tag, title, keyboard, gamepad, body, warning.
func configure_steps(custom_steps: Array[Dictionary]) -> void:
	var sanitized: Array[Dictionary] = []
	for custom_step in custom_steps:
		if sanitized.size() >= MAX_STEPS:
			break
		if not custom_step.is_empty():
			sanitized.append(custom_step.duplicate(true))
	_steps = sanitized if not sanitized.is_empty() else DEFAULT_STEPS.duplicate(true)
	_step_index = clampi(_step_index, 0, _steps.size() - 1)
	_apply_step(false)


## Displays a zero-based step. The host can call this from real player signals.
func show_step(step_index: int) -> void:
	if _steps.is_empty():
		return
	var next_index := clampi(step_index, 0, _steps.size() - 1)
	var changed := next_index != _step_index
	_step_index = next_index
	if not visible:
		show()
	_apply_step(changed)


func advance() -> void:
	if _finished or _steps.is_empty():
		return
	if _step_index + 1 >= _steps.size():
		complete()
	else:
		show_step(_step_index + 1)


func previous_step() -> void:
	if not _finished:
		show_step(_step_index - 1)


func complete() -> void:
	if _finished:
		return
	_finished = true
	tutorial_completed.emit()
	_animate_out()


func skip() -> void:
	if _finished:
		return
	_finished = true
	tutorial_skipped.emit()
	_animate_out()


## Hides the card without treating the tutorial as completed or skipped.
func dismiss() -> void:
	_kill_transition()
	hide()


func set_input_mode(gamepad: bool) -> void:
	if _gamepad_mode == gamepad:
		return
	_gamepad_mode = gamepad
	_apply_step(false)


func set_manual_advance_enabled(enabled: bool) -> void:
	manual_advance_enabled = enabled
	if not is_node_ready():
		return
	continue_button.visible = enabled
	continue_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	skip_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if enabled and visible:
		continue_button.call_deferred("grab_focus")


func get_current_step() -> int:
	return _step_index


func get_step_count() -> int:
	return _steps.size()


func is_gamepad_mode() -> bool:
	return _gamepad_mode


func _apply_step(animate_change: bool) -> void:
	if _steps.is_empty() or not is_node_ready():
		return
	var step := _steps[_step_index]
	step_badge.text = str(step.get("tag", "%02d" % (_step_index + 1)))
	title_label.text = str(step.get("title", "新手提示"))
	device_label.text = "手柄" if _gamepad_mode else "单手键盘"
	controls_label.text = str(step.get("gamepad" if _gamepad_mode else "keyboard", ""))
	body_label.text = str(step.get("body", ""))
	warning_label.text = "◆  %s" % str(step.get("warning", ""))
	page_label.text = "%d / %d" % [_step_index + 1, _steps.size()]
	step_progress.max_value = float(_steps.size())
	step_progress.value = float(_step_index + 1)
	continue_button.text = "开始战斗" if _step_index + 1 >= _steps.size() else "下一条"
	step_changed.emit(_step_index, _steps.size())
	if animate_change:
		_kill_transition()
		content.modulate.a = 0.34
		content.position.y = 8.0
		_transition = create_tween()
		_transition.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_transition.tween_property(content, "modulate:a", 1.0, transition_duration)
		_transition.tween_property(content, "position:y", 0.0, transition_duration)


func _apply_styles() -> void:
	card.add_theme_stylebox_override("panel", _card_style())
	step_badge_panel.add_theme_stylebox_override("panel", _badge_style())
	warning_panel.add_theme_stylebox_override("panel", _warning_style())
	step_badge.add_theme_color_override("font_color", FoldlightRogueUITheme.INK)
	step_badge.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", FoldlightRogueUITheme.PAPER)
	device_label.add_theme_color_override("font_color", FoldlightRogueUITheme.MUTED)
	device_label.add_theme_font_size_override("font_size", 18)
	controls_label.add_theme_color_override("font_color", FoldlightRogueUITheme.GOLD)
	controls_label.add_theme_font_size_override("font_size", 25)
	body_label.add_theme_color_override("font_color", Color(0.75, 0.86, 0.84, 1.0))
	body_label.add_theme_font_size_override("font_size", 21)
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42, 1.0))
	warning_label.add_theme_font_size_override("font_size", 18)
	page_label.add_theme_color_override("font_color", FoldlightRogueUITheme.MUTED)
	page_label.add_theme_font_size_override("font_size", 18)
	step_progress.add_theme_stylebox_override("background", _bar_style(Color(0.08, 0.14, 0.17, 0.9)))
	step_progress.add_theme_stylebox_override("fill", _bar_style(FoldlightRogueUITheme.FOLD))


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.030, 0.060, 0.96)
	style.border_color = Color(0.29, 0.88, 0.83, 0.64)
	style.border_width_left = 5
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 30.0
	style.content_margin_top = 22.0
	style.content_margin_right = 26.0
	style.content_margin_bottom = 20.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	return style


func _badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FoldlightRogueUITheme.FOLD
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _warning_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.075, 0.035, 0.58)
	style.border_color = Color(1.0, 0.68, 0.26, 0.58)
	style.border_width_left = 3
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _animate_out() -> void:
	_kill_transition()
	_transition = create_tween()
	_transition.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_transition.tween_property(self, "modulate:a", 0.0, transition_duration * 0.8)
	_transition.tween_callback(hide)


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
