extends Control

## An in-world victory acknowledgement. It never advances combat or run time.
signal continue_requested

const INPUT_GUARD = preload("res://scripts/ui/reward_input_guard.gd")
const READ_SECONDS: float = 2.2

var _input_guard: Node
var _title: Label
var _description: Label
var _hint: Label
var _continue_button: Button
var _confirmed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_top = -58
	panel.offset_right = 310
	panel.offset_bottom = 152
	panel.custom_minimum_size = Vector2(620, 210)
	var style := FoldlightTheme.panel_style()
	style.bg_color = Color(FoldlightTheme.SURFACE, 0.90)
	style.border_color = Color(FoldlightTheme.GOLD, 0.55)
	panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	_title = _label(30, FoldlightTheme.GOLD)
	stack.add_child(_title)
	_description = _label(19, FoldlightTheme.PAPER)
	stack.add_child(_description)
	_hint = _label(17, FoldlightTheme.MUTED)
	stack.add_child(_hint)
	_continue_button = Button.new()
	_continue_button.custom_minimum_size.y = 54
	_continue_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	_continue_button.pressed.connect(_confirm)
	stack.add_child(_continue_button)
	_input_guard = INPUT_GUARD.new()
	_input_guard.state_changed.connect(_update_input_state)
	add_child(_input_guard)
	hide()


func present(boss_title: String, next_region_title: String) -> void:
	_confirmed = false
	_title.text = "%s · 已澄清" % boss_title
	_description.text = "纸海归于平静，微光已留存。" if next_region_title.is_empty() else "这一片海已平静。下一程：%s。" % next_region_title
	_continue_button.text = "查看航行结算" if next_region_title.is_empty() else "继续驶向%s" % next_region_title
	_continue_button.disabled = true
	_continue_button.focus_mode = Control.FOCUS_NONE
	show()
	_input_guard.begin(self, READ_SECONDS)


func dismiss() -> void:
	if is_instance_valid(_input_guard):
		_input_guard.cancel()
	# Scene replacement may detach this banner before the session resets it.
	# Detached Controls cannot use the viewport's focus API.
	if is_instance_valid(_continue_button) and _continue_button.is_inside_tree() and _continue_button.has_focus():
		_continue_button.release_focus()
	hide()


func can_continue() -> bool:
	return visible and not _confirmed and _input_guard.can_select()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Escape cannot reopen combat or replace the pending victory with Pause.
	if event.is_action(&"pause_game") or event.is_action(&"ui_cancel"):
		get_viewport().set_input_as_handled()
	elif event.is_pressed() and not event.is_echo() and (event.is_action_pressed(&"fold") or event.is_action_pressed(&"ui_accept")):
		get_viewport().set_input_as_handled()
		_confirm()


func _confirm() -> void:
	if not can_continue():
		return
	_confirmed = true
	_continue_button.disabled = true
	get_viewport().set_input_as_handled()
	continue_requested.emit()


func _update_input_state() -> void:
	var ready := can_continue()
	_continue_button.disabled = not ready
	_continue_button.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	_hint.text = "按 Space / A、Enter 或点击继续" if ready else ("潮声渐息 · 稍候片刻" if _input_guard._elapsed < READ_SECONDS else "松开按键、鼠标或摇杆，再继续")
	if ready:
		call_deferred("_focus_continue")


func _focus_continue() -> void:
	if can_continue() and _continue_button.is_visible_in_tree():
		_continue_button.grab_focus()


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
