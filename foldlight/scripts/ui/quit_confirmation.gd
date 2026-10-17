extends Control

## Native exit is deliberately separate from menu confirmation. Opening input
## must be released, and the initially focused choice always keeps playing.
signal confirmed
signal cancelled

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const INPUT_CONTRACT = preload("res://scripts/ui/input_contract.gd")
const INPUT_GUARD = preload("res://scripts/ui/reward_input_guard.gd")

var _input_guard: Node
var _cancel_button: Button
var _quit_button: Button
var _committed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Palette.build()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(Palette.INK, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 260)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "离开纸海？"
	heading.add_theme_font_size_override("font_size", 34)
	content.add_child(heading)
	var body := Label.new()
	body.text = "退出将关闭游戏窗口。"
	body.add_theme_color_override("font_color", Palette.MUTED)
	content.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	content.add_child(buttons)
	_cancel_button = Button.new()
	_cancel_button.text = "留在纸海"
	_cancel_button.custom_minimum_size = Vector2(240, 62)
	_cancel_button.pressed.connect(_cancel)
	buttons.add_child(_cancel_button)
	_quit_button = Button.new()
	_quit_button.text = "确认退出"
	_quit_button.custom_minimum_size = Vector2(240, 62)
	_quit_button.pressed.connect(_confirm)
	buttons.add_child(_quit_button)
	var hint := Label.new()
	hint.text = "松开按键后选择 · Esc / B 返回"
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Palette.MUTED)
	content.add_child(hint)
	_input_guard = INPUT_GUARD.new()
	add_child(_input_guard)
	_input_guard.state_changed.connect(_update_gate)
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.is_touch_mode():
		panel.custom_minimum_size = Vector2(900, 380)
		heading.add_theme_font_size_override("font_size", 42)
		body.text = "退出将关闭游戏。"
		body.add_theme_font_size_override("font_size", 34)
		hint.text = "点留在纸海继续游戏"
		hint.add_theme_font_size_override("font_size", 32)
		for button: Button in [_cancel_button, _quit_button]:
			button.custom_minimum_size = Vector2(390, 120)
			button.add_theme_font_size_override("font_size", 36)
	hide()


func present() -> void:
	if not is_inside_tree() or visible:
		return
	_committed = false
	show()
	_input_guard.begin(self)


func dismiss() -> void:
	_input_guard.cancel()
	hide()


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_game"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			_cancel()
		return
	if not event.is_pressed() or event.is_echo():
		return
	var direction := INPUT_CONTRACT.navigation_step(event)
	if direction != 0:
		get_viewport().set_input_as_handled()
		if _input_guard.can_select():
			var next := _quit_button if get_viewport().gui_get_focus_owner() == _cancel_button else _cancel_button
			next.grab_focus()
	elif event.is_action_pressed(&"fold") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		if _input_guard.can_select():
			if get_viewport().gui_get_focus_owner() == _quit_button:
				_confirm()
			else:
				_cancel()


func _update_gate() -> void:
	var ready: bool = _input_guard.can_select()
	_quit_button.disabled = not ready
	_cancel_button.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	_quit_button.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	if ready:
		call_deferred("_focus_cancel")


func _focus_cancel() -> void:
	if is_inside_tree() and is_visible_in_tree() and not is_queued_for_deletion() and _input_guard.can_select():
		_cancel_button.grab_focus()


func _cancel() -> void:
	if not is_inside_tree() or not is_visible_in_tree() or _committed:
		return
	dismiss()
	cancelled.emit()


func _confirm() -> void:
	if not is_inside_tree() or not is_visible_in_tree() or _committed or not _input_guard.can_select():
		return
	_committed = true
	dismiss()
	confirmed.emit()
