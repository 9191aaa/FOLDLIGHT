extends CanvasLayer

## A single in-game lobby for Windows, Android and standalone web builds.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
var bridge: Node
var client: Node
var _root: Control
var _shade: ColorRect
var _margin: MarginContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _entry: VBoxContainer
var _room_panel: VBoxContainer
var _endpoint: LineEdit
var _name: LineEdit
var _code: LineEdit
var _error: Label
var _room_title: Label
var _players: Label
var _phase: Label
var _ready_button: Button
var _create_button: Button
var _join_button: Button
var _back: Button
var _strip: HBoxContainer
var _strip_text: Label
var _confirm: VBoxContainer
var _keyboard_height := 0.0
var _opened := false
var _confirming := false
var _mobile := false
var _clock := 0.0
var _previous_focus: WeakRef
var _touch_modal_blocked := false


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = Palette.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.focus_mode = Control.FOCUS_ALL
	add_child(_root)
	_shade = ColorRect.new()
	_shade.color = Color(Palette.INK, 0.98)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_margin.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	_scroll.add_child(_body)
	_body.add_child(_label("好友无尽", 46, Palette.PAPER))
	_body.add_child(_label("同一纸海 · 各自生存 · 按有效战斗时间比拼", 28, Palette.FOLD))
	_entry = VBoxContainer.new()
	_entry.add_theme_constant_override("separation", 16)
	_body.add_child(_entry)
	_entry.add_child(_label("称呼", 26, Palette.MUTED))
	_name = _field("1–16 字", 16)
	_name.text = client.display_name
	_entry.add_child(_name)
	_entry.add_child(_label("联机入口", 26, Palette.MUTED))
	var endpoint_row := HBoxContainer.new()
	_endpoint = _field("粘贴完整入口链接", 2048)
	_endpoint.text = client.endpoint
	_endpoint.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_endpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint_row.add_child(_endpoint)
	endpoint_row.add_child(_button("粘贴", _paste_endpoint))
	_entry.add_child(endpoint_row)
	_entry.add_child(_label("双方使用同一个入口。临时链接约 3 小时失效，到期后粘贴新链接。", 24, Palette.MUTED))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	_create_button = _button("创建房间", _create)
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_create_button)
	_entry.add_child(actions)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 18)
	_code = _field("朋友的 7 位房间码", 7)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_code)
	_join_button = _button("加入房间", _join)
	join_row.add_child(_join_button)
	_entry.add_child(join_row)
	_room_panel = VBoxContainer.new()
	_room_panel.add_theme_constant_override("separation", 24)
	_body.add_child(_room_panel)
	var code_row := HBoxContainer.new()
	_room_title = _label("", 40, Palette.GOLD)
	_room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_room_title)
	code_row.add_child(_button("复制房间码", _copy_code))
	_room_panel.add_child(code_row)
	_players = _label("", 32, Palette.PAPER)
	_room_panel.add_child(_players)
	_phase = _label("", 32, Palette.FOLD)
	_room_panel.add_child(_phase)
	_ready_button = _button("准备出发", func() -> void: client.prepare_match())
	_room_panel.add_child(_ready_button)
	_room_panel.add_child(_label("电脑、安卓和网页可一起比赛。奖励选择不计时；离开或断线 30 秒判负。", 26, Palette.MUTED))
	_error = _label("", 28, Palette.DANGER)
	_body.add_child(_error)
	_back = _button("返回标题", _request_back)
	_body.add_child(_back)
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 20)
	_confirm.add_child(_label("确认离开房间？", 38, Palette.GOLD))
	_confirm.add_child(_label("等待时离开会关闭房间；开局后离开按弃赛处理。比赛继续计时。", 28, Palette.MUTED))
	_confirm.add_child(_button("继续航行", _cancel_leave))
	_confirm.add_child(_button("确认离开", func() -> void: client.leave_room()))
	_body.add_child(_confirm)
	_strip = HBoxContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_constant_override("separation", 14)
	_root.add_child(_strip)
	_strip_text = _label("", 26, Palette.PAPER)
	_strip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip_text.add_theme_color_override("font_outline_color", Palette.INK)
	_strip_text.add_theme_constant_override("outline_size", 8)
	_strip.add_child(_strip_text)
	_strip.add_child(_button("离开", _request_back))
	client.room_changed.connect(_refresh)
	client.error_changed.connect(func(_value: String) -> void: _refresh())
	client.busy_changed.connect(func(_value: bool) -> void: _refresh())
	client.room_left.connect(_on_room_left)
	bridge.phase_changed.connect(func(_value: StringName) -> void: _refresh())
	get_viewport().size_changed.connect(_layout)
	call_deferred("_bind_touch_controls")
	_layout()
	_refresh()


func _bind_touch_controls() -> void:
	# This lobby belongs to the first autoload; TouchControls is created later.
	# Bind after all autoloads are ready so later native safe-area updates reach
	# the lobby even when its initial startup had no touch singleton yet.
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		if not touch.touch_mode_changed.is_connected(_on_touch_mode_changed):
			touch.touch_mode_changed.connect(_on_touch_mode_changed)
		if not touch.layout_changed.is_connected(_layout):
			touch.layout_changed.connect(_layout)
	_layout()


func _on_touch_mode_changed(_enabled: bool) -> void:
	_layout()


func open() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and not _root.is_ancestor_of(focused): _previous_focus = weakref(focused)
	_opened = true
	_endpoint.text = client.endpoint
	_name.text = client.display_name
	_confirming = false
	_layout()
	_refresh()
	if not _mobile: _name.grab_focus()
	else: _root.grab_focus()
	_scroll.set_deferred("scroll_vertical", 0)


func _process(delta: float) -> void:
	if not _root.visible: return
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.2
		_refresh()
		var keyboard_height := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
		var screen_height := float(maxi(1, DisplayServer.window_get_size().y))
		var logical_height := keyboard_height * get_viewport().get_visible_rect().size.y / screen_height
		if not is_equal_approx(_keyboard_height, logical_height):
			_keyboard_height = logical_height
			_layout()
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null and _body.is_ancestor_of(focused):
				_scroll.ensure_control_visible.call_deferred(focused)


func _input(event: InputEvent) -> void:
	var back_pressed := event.is_action_pressed(&"pause_game") or (captures_menu_input() and event.is_action_pressed(&"ui_cancel"))
	if _root.visible and back_pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _confirming: _cancel_leave()
		else: _request_back()


func captures_menu_input() -> bool:
	return _margin != null and _margin.is_visible_in_tree()


func _layout() -> void:
	if _root == null: return
	var touch := get_node_or_null("/root/TouchControls")
	_mobile = touch != null and touch.is_touch_mode()
	var safe := Vector4.ZERO
	if touch != null: safe = touch.get_layout_snapshot().get("safe_insets", Vector4.ZERO)
	var extent := get_viewport().get_visible_rect().size
	var side := maxf(48.0, (extent.x - 1300.0) * 0.5) if not _mobile else 64.0
	_margin.add_theme_constant_override("margin_left", int(side + safe.x))
	_margin.add_theme_constant_override("margin_right", int(side + safe.z))
	_margin.add_theme_constant_override("margin_top", int(safe.y + 36.0))
	_margin.add_theme_constant_override("margin_bottom", int(maxf(safe.w + 30.0, _keyboard_height + 24.0)))
	_size_controls(_body)
	_size_controls(_strip)
	_strip.position = Vector2(44.0 + safe.x, safe.y + 12.0)
	_strip.size = Vector2(maxf(400, extent.x - 88.0 - safe.x - safe.z), 120.0 if _mobile else 70.0)
	_strip_text.add_theme_font_size_override("font_size", 34 if _mobile else 25)


func _size_controls(node: Node) -> void:
	if node is Button or node is LineEdit:
		node.custom_minimum_size.y = 132 if _mobile else 66
		node.add_theme_font_size_override("font_size", 36 if _mobile else 27)
	elif node is Label:
		if not node.has_meta("desktop_font_size"): node.set_meta("desktop_font_size", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", maxi(32, int(node.get_meta("desktop_font_size"))) if _mobile else int(node.get_meta("desktop_font_size")))
	for child in node.get_children(): _size_controls(child)


func _refresh(_snapshot: Dictionary = {}) -> void:
	if _root == null: return
	var active: bool = not client.room.is_empty()
	var running: bool = active and bridge.is_native_session() and bridge.phase == &"running"
	var fullscreen: bool = _opened and (not running or _confirming)
	_root.visible = _opened or active
	_shade.visible = fullscreen
	_margin.visible = fullscreen
	_entry.visible = not active and not _confirming
	_room_panel.visible = active and not _confirming
	_back.visible = not _confirming
	_confirm.visible = _confirming
	_strip.visible = running and not _confirming
	_sync_touch_block(fullscreen)
	_error.text = client.error_message
	_error.visible = not _error.text.is_empty()
	_create_button.disabled = client._busy
	_join_button.disabled = client._busy
	_back.disabled = client._busy and client._action == "leave"
	_back.text = "离开房间" if active else "返回标题"
	if not active: return
	var snapshot: Dictionary = client.room
	_room_title.text = "房间  %s" % String(snapshot.code)
	var lines: Array[String] = []
	var opponent := "等待好友加入"
	for pilot: Dictionary in snapshot.players:
		var own := String(pilot.id) == String(snapshot.selfId)
		var title := "%s%s" % [String(pilot.name), "（你）" if own else ""]
		var state := _status_text(pilot)
		lines.append("%s  ·  %s  ·  %s" % [title, _time(float(pilot.elapsed)), state])
		if not own: opponent = "%s  %s · %s" % [String(pilot.name), _time(float(pilot.elapsed)), state]
	_players.text = "\n\n".join(lines)
	_ready_button.visible = snapshot.phase == "waiting"
	_ready_button.disabled = client.match_loaded or client._lost_match
	_ready_button.text = "已准备 · 等待好友" if client.match_loaded else "准备出发"
	if snapshot.phase == "finished":
		var result: Dictionary = snapshot.get("result", {}) if snapshot.get("result") is Dictionary else {}
		_phase.text = "平局 · 一起返航" if result.get("draw", false) else ("你赢得本局 · 获胜" if result.get("winner") == snapshot.selfId else "好友赢得本局 · 下次再来")
	elif client._lost_match:
		_phase.text = "连接中断 · 本局已停止计分"
	elif bridge.phase == &"terminal":
		_phase.text = "你的航程已结束 · 等待好友成绩"
	elif snapshot.phase == "running":
		_phase.text = "即将出发  %d" % client.countdown_seconds() if client.countdown_seconds() > 0 else "双方航行中"
	else:
		_phase.text = "分享房间码，双方准备后统一倒数 5 秒。"
	_strip_text.text = "好友  %s" % opponent
	if not client.error_message.is_empty(): _strip_text.text = "正在重连 · 超过 30 秒会判负"


func _sync_touch_block(fullscreen: bool) -> void:
	# Full-screen room controls must never share raw touches with the battle's
	# thumb zones. Combat continues; only touch ownership changes while asking.
	if not bridge.is_native_session():
		_touch_modal_blocked = false
		return
	var runtime: Node = bridge._runtime
	if not is_instance_valid(runtime) or _touch_modal_blocked == fullscreen: return
	_touch_modal_blocked = fullscreen
	var touch := get_node_or_null("/root/TouchControls")
	if touch == null: return
	if fullscreen:
		touch.set_context(runtime.presentation, runtime.player, false)
	else:
		runtime.presentation._sync_touch_context()


func _status_text(pilot: Dictionary) -> String:
	if not bool(pilot.get("connected", true)): return "连接中"
	match String(pilot.get("status", "waiting")):
		"alive": return "航行中"
		"reward": return "选择折痕"
		"dead": return "航程结束"
		"forfeit": return "已弃赛"
		"disconnected": return "断线"
	return "已准备" if pilot.get("ready", false) else "未准备"


func _create() -> void:
	if client.configure_endpoint(_endpoint.text, _name.text): client.create_room(_name.text)


func _join() -> void:
	if client.configure_endpoint(_endpoint.text, _name.text): client.join_room(_code.text, _name.text)


func _paste_endpoint() -> void:
	_endpoint.text = DisplayServer.clipboard_get().strip_edges().left(2048)


func _copy_code() -> void:
	if not client.room.is_empty(): DisplayServer.clipboard_set(String(client.room.code))


func _request_back() -> void:
	if client.room.is_empty():
		if client._busy: return
		_opened = false
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref()
			if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	else:
		_confirming = true
		_scroll.scroll_vertical = 0
	_refresh()
	if _confirming: _confirm.get_child(2).grab_focus()


func request_leave_confirmation() -> void:
	_request_back()


func _cancel_leave() -> void:
	_confirming = false
	_refresh()


func _on_room_left() -> void:
	_confirming = false
	_opened = false
	_refresh()


func _field(placeholder: String, maximum: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = maximum
	field.custom_minimum_size = Vector2(0, 66)
	field.add_theme_stylebox_override("normal", Palette.panel_style())
	field.add_theme_stylebox_override("focus", Palette.button_style(true))
	field.add_theme_color_override("font_color", Palette.PAPER)
	field.add_theme_color_override("caret_color", Palette.FOLD)
	return field


func _button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(180, 66)
	button.pressed.connect(callback)
	return button


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
