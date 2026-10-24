extends Control
signal skill_selected(id: StringName)
signal closed
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const SkillArt = preload("res://scripts/roguelite/ui/active_skill_art.gd")

class SkillButton extends Button:
	var entry: Dictionary = {}
	var mobile: bool = false
	var _font: Font = Palette.body_font()
	func _init() -> void:
		custom_minimum_size = Vector2(470, 158)
	func configure(value: Dictionary, touch: bool) -> void:
		entry = value.duplicate(true)
		mobile = touch
		text = str(entry.get("title", ""))
		tooltip_text = str(entry.get("description", ""))
		for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for key in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_disabled_color"]:
			add_theme_color_override(key, Color.TRANSPARENT)
		queue_redraw()
	func _draw() -> void:
		if entry.is_empty(): return
		var accent := Palette.comfort_accent(Color(entry.get("accent", Palette.GOLD)))
		var equipped := bool(entry.get("equipped", false))
		var focused := has_focus() or is_hovered()
		var fill := Color("1c363c") if equipped else Color("10272f")
		draw_rect(Rect2(Vector2(0, 5), size), Color(Palette.INK, 0.5))
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x - 20, 0), Vector2(size.x, 20), size, Vector2(0, size.y)]), fill.lightened(0.05 if focused else 0.0))
		draw_colored_polygon(PackedVector2Array([Vector2(size.x - 20, 0), Vector2(size.x - 20, 20), Vector2(size.x, 20)]), Color(accent, 0.22))
		draw_line(Vector2(20, size.y - 2), Vector2(size.x - 20, size.y - 2), Color(accent, 0.85 if equipped or focused else 0.16), 3 if equipped else 1.0, true)
		SkillArt.draw_icon(self, StringName(entry.get("id", &"")), Vector2(55, 65), 29, accent)
		var font := _font
		draw_string(font, Vector2(106, 44), str(entry.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 132, 36 if mobile else 30, Palette.PAPER)
		draw_string(font, Vector2(106, 84), str(entry.get("usage_label", "主动技能")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 132, 28 if mobile else 23, Color(accent, 0.88))
		var remaining := maxf(0.0, float(entry.get("cooldown_remaining", 0.0)))
		var duration := maxf(0.01, float(entry.get("cooldown_duration", 1.0)))
		var status := ("当前装备" if equipped else "已收藏") + (" · %.1f秒" % remaining if remaining > 0.01 else " · 就绪")
		draw_string(font, Vector2(24, 128), status, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48, 28 if mobile else 23, accent if equipped else Palette.MUTED)
		if remaining > 0.0:
			draw_line(Vector2(24, 142), Vector2(24 + (size.x - 48) * (1.0 - minf(1.0, remaining / duration)), 142), Color(accent, 0.6), 3, true)

var focus_buttons: Array[Button] = []
var entries: Array[Dictionary] = []
var _mobile: bool = false
var _insets := Vector4.ZERO
var _source: StringName = &"pause"
var _preview_id: StringName = &""
var _heading: Label
var _hint: Label
var _grid: GridContainer
var _detail_title: Label
var _detail_body: Label
var _return: Button
var _buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_heading = _label(46, Palette.PAPER)
	_hint = _label(25, Palette.MUTED)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 20)
	add_child(_grid)
	for index in 6:
		var button := SkillButton.new()
		button.name = "CollectedSkill%d" % index
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_choose.bind(index))
		button.focus_entered.connect(_preview.bind(index))
		button.mouse_entered.connect(_preview.bind(index))
		button.focus_exited.connect(button.queue_redraw)
		button.mouse_exited.connect(button.queue_redraw)
		_grid.add_child(button)
		_buttons.append(button)
	_detail_title = _label(29, Palette.GOLD)
	_detail_body = _label(25, Palette.PAPER)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_return = Button.new()
	_return.custom_minimum_size = Vector2(300, 100)
	_return.add_theme_font_size_override("font_size", 30)
	_return.pressed.connect(func() -> void: closed.emit())
	add_child(_return)
	resized.connect(_layout)
	_layout()

func present(value: Array[Dictionary], mobile: bool, insets: Vector4, source: StringName) -> void:
	entries = value.duplicate(true)
	_mobile = mobile
	_insets = insets
	_source = source
	_heading.text = "主动技能册  ·  本局收藏 %d / 6" % entries.size()
	_hint.text = "全部保留 · 同时装备一件 · 切换保留各自冷却"
	_return.text = "返回奖励选择" if source == &"reward" else "返回暂停菜单"
	focus_buttons.clear()
	var equipped_index := 0
	for index in _buttons.size():
		var button := _buttons[index]
		button.visible = index < entries.size()
		if button.visible:
			button.configure(entries[index], mobile)
			focus_buttons.append(button)
			if _preview_id == &"" or bool(entries[index].get("equipped", false)):
				_preview_id = StringName(entries[index].get("id", &""))
			if bool(entries[index].get("equipped", false)):
				equipped_index = index
	focus_buttons.append(_return)
	# The presenter focuses the first control after each inventory refresh.
	# Rotate the navigation cycle so that this stays on the equipped skill;
	# visual card order and the cyclic keyboard traversal remain unchanged.
	for index in equipped_index:
		focus_buttons.append(focus_buttons.pop_front())
	_layout()
	_refresh_detail()
	show()
	queue_redraw()

func _layout() -> void:
	if _heading == null: return
	var left := maxf(120, _insets.x + 36)
	var right := maxf(120, _insets.z + 36)
	var top := maxf(96, _insets.y + 24) if not _mobile else maxf(150, _insets.y + 24)
	var width := maxf(1490, size.x - left - right)
	_heading.position = Vector2(left, top)
	_heading.size = Vector2(width, 66)
	_heading.add_theme_font_size_override("font_size", 42 if _mobile else 46)
	_hint.position = Vector2(left, top + 70)
	_hint.size = Vector2(width, 46)
	_hint.add_theme_font_size_override("font_size", 32 if _mobile else 25)
	_grid.position = Vector2(left, top + 136)
	_grid.size = Vector2(width, 336)
	_detail_title.position = Vector2(left, top + 504)
	_detail_title.size = Vector2(width, 44)
	_detail_title.add_theme_font_size_override("font_size", 32 if _mobile else 29)
	_detail_body.position = Vector2(left, top + 552)
	_detail_body.size = Vector2(width - 20, 136 if _mobile else 116)
	_detail_body.add_theme_font_size_override("font_size", 32 if _mobile else 25)
	_return.size = Vector2(340, 120 if _mobile else 100)
	_return.position = Vector2(left + width - _return.size.x, maxf(top + 710, size.y - maxf(66, _insets.w + 24) - _return.size.y))
	queue_redraw()

func _choose(index: int) -> void:
	if not visible or index >= entries.size(): return
	_preview_id = StringName(entries[index].get("id", &""))
	_refresh_detail()
	skill_selected.emit(_preview_id)

func _preview(index: int) -> void:
	if index >= entries.size(): return
	_preview_id = StringName(entries[index].get("id", &""))
	_refresh_detail()
	_buttons[index].queue_redraw()

func _refresh_detail() -> void:
	for entry in entries:
		if StringName(entry.get("id", &"")) != _preview_id: continue
		_detail_title.text = str(entry.get("title", "")) + (" · 当前装备" if bool(entry.get("equipped", false)) else " · 点按上方技能即可装备")
		_detail_body.text = str(entry.get("description", "")) + "\n冷却 %.0f 秒 · 实战中恢复，暂停时冻结。" % float(entry.get("cooldown_duration", 0.0))
		return
	_detail_title.text = "尚未获得主动技能"
	_detail_body.text = "选择技能奖励后将收藏并装备，原有技能会一直保留在这里。"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
	draw_colored_polygon(PackedVector2Array([Vector2(0, size.y * 0.69), Vector2(size.x * 0.44, size.y * 0.48), size, Vector2(0, size.y)]), Color("102a32", 0.56))
	draw_line(Vector2(74, 54), Vector2(74, size.y - 54), Color(Palette.GOLD, 0.3), 2, true)
	if _detail_title != null:
		draw_line(_detail_title.position - Vector2(0, 20), _detail_title.position + Vector2(_detail_title.size.x, -20), Color(Palette.GOLD, 0.23), 1.5, true)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
