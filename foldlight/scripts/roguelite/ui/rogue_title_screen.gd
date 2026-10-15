class_name FoldlightRogueTitleScreen
extends Control

## Title composition owns presentation only. The session still owns every action.
signal action_requested(action: StringName)

const Palette = preload("res://scripts/ui/foldlight_theme.gd")

var primary_button: Button
var continue_button: Button
var tutorial_button: Button
var record_label: Label
var guide_label: Label
var focus_buttons: Array[Button] = []
var _content: VBoxContainer
var _entrance: Tween


func build(button_factory: Callable) -> void:
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 136)
	margin.add_theme_constant_override("margin_top", 108)
	margin.add_theme_constant_override("margin_right", 136)
	margin.add_theme_constant_override("margin_bottom", 76)
	add_child(margin)
	var columns := HBoxContainer.new()
	margin.add_child(columns)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = 660
	_content.add_theme_constant_override("separation", 0)
	columns.add_child(_content)
	var image_space := Control.new()
	image_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(image_space)

	_content.add_child(_label("深海 · 折纸 · 返光", 18, Palette.FOLD))
	_space(14)
	var logo := _label("FOLDLIGHT", 88, Palette.PAPER)
	logo.add_theme_font_override("font", Palette.display_font())
	_content.add_child(logo)
	var chinese := _label("折  光", 40, Palette.PAPER)
	_content.add_child(chinese)
	_space(18)
	guide_label = _label("将弹幕收入折翼，让微光重返深海。", 22, Palette.MUTED)
	_content.add_child(guide_label)
	_space(46)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_content.add_child(actions)
	continue_button = _action(button_factory, "继续迷航", &"continue", "PrimaryButton", 84)
	actions.add_child(continue_button)
	primary_button = _action(button_factory, "开始迷航", &"new_run", "PrimaryButton", 84)
	actions.add_child(primary_button)
	var story := _action(button_factory, "故事航路", &"classic", "FoldlightMenuButton", 66)
	_add_caption(story, "三章战役")
	actions.add_child(story)
	var endless := _action(button_factory, "无尽挑战", &"endless", "FoldlightMenuButton", 66)
	_add_caption(endless, "生存与进化")
	actions.add_child(endless)
	tutorial_button = _action(button_factory, "操作教学 · 重温", &"prologue", "FoldlightMenuButton", 58)
	actions.add_child(tutorial_button)
	_space(20)
	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 26)
	_content.add_child(utility)
	var settings := _action(button_factory, "设置", &"settings", "QuietButton", 52)
	settings.custom_minimum_size.x = 110
	utility.add_child(settings)
	var quit := _action(button_factory, "退出游戏", &"quit", "QuietButton", 52)
	quit.custom_minimum_size.x = 130
	quit.visible = not OS.has_feature("web")
	utility.add_child(quit)
	var breathing_space := Control.new()
	breathing_space.custom_minimum_size.y = 24
	breathing_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(breathing_space)
	record_label = _label("", 18, Palette.MUTED)
	_content.add_child(record_label)
	_space(12)
	_content.add_child(_label("WASD / 方向键  选择     空格 / A  确认", 17, Color(Palette.MUTED, 0.78)))
	focus_buttons = [continue_button, primary_button, story, endless, tutorial_button, settings, quit]


func present(profile: Dictionary) -> void:
	var active: Variant = profile.get("active_run", {})
	var has_continue := active is Dictionary and not (active as Dictionary).is_empty()
	var learned := bool(profile.get("prologue_complete", false))
	continue_button.visible = has_continue
	primary_button.text = "开始迷航" if learned else "开始迷航  ·  操作教学"
	primary_button.theme_type_variation = "FoldlightMenuButton" if has_continue else "PrimaryButton"
	primary_button.custom_minimum_size.y = 58 if has_continue else 84
	tutorial_button.visible = learned
	var runs := int(profile.get("runs", 0))
	if runs > 0:
		record_label.text = "迷航 %d 次    返航 %d 次    最深 第 %d 区" % [runs, int(profile.get("victories", 0)), int(profile.get("best_region", 0))]
	else:
		record_label.text = "每一次迷航，驶向不同的纸海。"
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	_content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_entrance = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_entrance.tween_property(_content, "modulate:a", 1.0, 0.38)


func _action(factory: Callable, text_value: String, action: StringName, variation: StringName, height: float) -> Button:
	var button: Button = factory.call(text_value, height)
	button.name = String(action).to_pascal_case() + "Button"
	button.theme_type_variation = variation
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void: action_requested.emit(action))
	return button


func _add_caption(button: Button, text_value: String) -> void:
	var caption := _label(text_value, 17, Palette.MUTED)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_right = -28
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(caption)


func _space(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
