class_name FoldlightDemoUI
extends CanvasLayer

signal action_requested(action: StringName)
signal reward_requested(index: int)

const INK := Color("0b1b28")
const PAPER := Color("e7e6d7")
const TEAL := Color("76dbca")
const GOLD := Color("edc887")
var hud: Label
var stage_label: Label
var hint_label: Label
var build_label: Label
var health_bar: ProgressBar
var fold_bar: ProgressBar
var dash_bar: ProgressBar
var boss_bar: ProgressBar
var core_bar: ProgressBar
var boss_label: Label
var overlay: ColorRect
var heading: Label
var description: Label
var eyebrow: Label
var menu_column: VBoxContainer
var menu_buttons: Array[Button] = []
var menu_actions: Array[StringName] = []
var cards: HBoxContainer
var card_buttons: Array[Button] = []
var card_titles: Array[Label] = []
var card_bodies: Array[Label] = []
var card_lanes: Array[Label] = []
var toast_label: Label
var _toast_remaining: float = 0.0
var _boss_target: float = 1.0
var _hp_target: float = 1.0
var _edges: Array[ColorRect] = []
var _hurt_remaining: float = 0.0

func _ready() -> void:
	name = "CanvasLayer"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "DejaVu Sans"])
	theme.default_font = font
	theme.default_font_size = 24
	var base := Control.new()
	base.name = "Chrome"
	base.size = Vector2(1920, 1080)
	base.theme = theme
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_panel(base, Rect2(28, 20, 1010, 102))
	_panel(base, Rect2(1052, 20, 840, 102))
	hud = _label(self, "HUD", Vector2(50, 28), Vector2(960, 34), 22)
	hud.theme = theme
	health_bar = _bar(base, Vector2(50, 76), Vector2(270, 9), Color("db8d88"))
	fold_bar = _bar(base, Vector2(370, 76), Vector2(310, 9), TEAL)
	dash_bar = _bar(base, Vector2(730, 76), Vector2(270, 9), GOLD)
	stage_label = _label(base, "Stage", Vector2(1080, 34), Vector2(780, 40), 27)
	stage_label.add_theme_color_override("font_color", GOLD)
	build_label = _label(base, "Build", Vector2(1080, 78), Vector2(780, 32), 19)
	hint_label = _label(base, "Hint", Vector2(200, 916), Vector2(1520, 40), 26)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label = _label(base, "BossName", Vector2(285, 950), Vector2(1350, 32), 21)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = _bar(base, Vector2(285, 987), Vector2(1350, 10), GOLD)
	core_bar = _bar(base, Vector2(735, 1004), Vector2(450, 4), TEAL)
	var controls := _label(base, "Controls", Vector2(110, 1033), Vector2(1700, 36), 20)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.text = "WASD / 方向键  移动     空格  按住收弹 / 松手返光     Shift  冲刺     Esc  暂停     F11  全屏     M  静音"
	controls.modulate = Color(0.72, 0.81, 0.82)
	toast_label = _label(base, "Toast", Vector2(350, 168), Vector2(1220, 92), 32)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", PAPER)
	for rect: Rect2 in [Rect2(0, 0, 1920, 16), Rect2(0, 1064, 1920, 16), Rect2(0, 0, 16, 1080), Rect2(1904, 0, 16, 1080)]:
		var edge := ColorRect.new()
		edge.position = rect.position
		edge.size = rect.size
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.color = Color(0.90, 0.35, 0.38, 0.0)
		base.add_child(edge)
		_edges.append(edge)
	overlay = ColorRect.new()
	overlay.size = Vector2(1920, 1080)
	overlay.color = Color(0.025, 0.06, 0.09, 0.96)
	overlay.theme = theme
	add_child(overlay)
	eyebrow = _label(overlay, "Eyebrow", Vector2(150, 200), Vector2(850, 40), 23)
	eyebrow.add_theme_color_override("font_color", GOLD)
	heading = _label(overlay, "Heading", Vector2(145, 276), Vector2(890, 230), 64)
	description = _label(overlay, "Description", Vector2(150, 545), Vector2(840, 235), 26)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("adbec4"))
	var foot := _label(overlay, "Version", Vector2(150, 927), Vector2(1200, 42), 20)
	foot.text = "FOLDLIGHT  /  0.2.0   ·   返航试玩   ·   三段交锋 + 两次强化 + 一位 Boss"
	foot.add_theme_color_override("font_color", Color("728c98"))
	menu_column = VBoxContainer.new()
	menu_column.position = Vector2(1150, 265)
	menu_column.size = Vector2(590, 640)
	menu_column.add_theme_constant_override("separation", 16)
	overlay.add_child(menu_column)
	for index in 6:
		var button := Button.new()
		button.custom_minimum_size = Vector2(590, 78)
		_style_button(button)
		button.pressed.connect(_menu_pressed.bind(index))
		menu_column.add_child(button)
		menu_buttons.append(button)
	cards = HBoxContainer.new()
	cards.position = Vector2(240, 430)
	cards.size = Vector2(1440, 350)
	cards.add_theme_constant_override("separation", 30)
	overlay.add_child(cards)
	for index in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(460, 345)
		_style_button(button)
		button.pressed.connect(func() -> void: reward_requested.emit(index))
		cards.add_child(button)
		card_buttons.append(button)
		var lane := _label(button, "Lane", Vector2(30, 25), Vector2(390, 38), 21)
		lane.add_theme_color_override("font_color", TEAL)
		card_lanes.append(lane)
		var title := _label(button, "Title", Vector2(30, 78), Vector2(390, 65), 38)
		card_titles.append(title)
		var body := _label(button, "Body", Vector2(30, 164), Vector2(395, 150), 23)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", Color("adbec4"))
		card_bodies.append(body)

func _label(parent: Node, node_name: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PAPER)
	parent.add_child(label)
	return label

func _box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 24
	box.content_margin_right = 24
	return box

func _panel(parent: Node, rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.025, 0.08, 0.12, 0.92), Color("264653")))
	parent.add_child(panel)

func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(Color("102735"), Color("31535c")))
	button.add_theme_stylebox_override("hover", _box(Color("183b47"), TEAL, 2))
	button.add_theme_stylebox_override("pressed", _box(Color("24505b"), GOLD, 2))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), GOLD, 2))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_font_size_override("font_size", 27)

func _bar(parent: Node, at: Vector2, dimensions: Vector2, tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = at
	bar.size = dimensions
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _box(Color("142f3d"), Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("fill", _box(tint, tint, 0))
	parent.add_child(bar)
	return bar

func show_menu(kind: StringName, profile_name: String, shake_name: String, body: String = "", won: bool = false) -> void:
	overlay.show()
	cards.hide()
	menu_column.show()
	eyebrow.position = Vector2(150, 200)
	heading.position = Vector2(145, 276)
	heading.add_theme_font_size_override("font_size", 64)
	description.position = Vector2(150, 545)
	var texts: Array[String] = []
	match kind:
		&"title":
			eyebrow.text = "PAPER SEA  /  纸海档案 02"
			heading.text = "折 光\n把光送回去。"
			description.text = "把危险折进掌心，再让光返航。\n\n三段短交锋中熟悉收纳与冲刺，\n选择两次强化，最后挑战礁冠炮城。\n紫色弹可收纳；黑金弹只能闪避。"
			texts = ["开始返航", "Boss 单独练习", "难度：" + profile_name, "震屏：" + shake_name, "退出游戏"]
			menu_actions = [&"voyage", &"practice", &"difficulty", &"shake", &"quit"]
		&"pause":
			eyebrow.text = "航行暂停  /  PAUSED"
			heading.text = "让纸海\n停一会儿。"
			description.text = "敌人、弹幕与冷却均已暂停。\n\n" + body
			texts = ["继续航行", "重试当前关卡", "震屏：" + shake_name, "返回标题", "退出游戏"]
			menu_actions = [&"resume", &"retry", &"shake", &"title", &"quit"]
		&"result":
			eyebrow.text = "航行记录  /  " + ("CLEAR" if won else "RETRY")
			heading.text = "光已返航。" if won else "灯还可以\n重新点亮。"
			description.text = body
			texts = ["再来一航" if won else "重试当前关卡", "返回标题", "退出游戏"]
			menu_actions = [&"again" if won else &"retry", &"title", &"quit"]
	for index in menu_buttons.size():
		menu_buttons[index].visible = index < texts.size()
		if index < texts.size():
			menu_buttons[index].text = texts[index]
	menu_buttons[0].grab_focus()

func _menu_pressed(index: int) -> void:
	if overlay.visible and menu_column.visible and index < menu_actions.size():
		action_requested.emit(menu_actions[index])

func show_rewards(options: Array, number: int) -> void:
	overlay.show()
	menu_column.hide()
	cards.show()
	eyebrow.position = Vector2(240, 194)
	eyebrow.text = "航间停泊  /  强化 %d · 2" % number
	heading.position = Vector2(235, 263)
	heading.add_theme_font_size_override("font_size", 48)
	heading.text = "选一件，让下一束光不同。"
	description.position = Vector2(240, 804)
	description.text = "过关已回复 1 点生命。强化仅在本航次有效；重试保留已选强化。"
	for index in 3:
		var item: Dictionary = options[index]
		card_lanes[index].text = "%02d   /   %s" % [index + 1, item["lane"]]
		card_titles[index].text = item["title"]
		card_bodies[index].text = item["body"]
	card_buttons[0].grab_focus()

func hide_menu() -> void:
	overlay.hide()

func toast(text: String, duration: float = 2.6) -> void:
	toast_label.text = text
	_toast_remaining = duration
	toast_label.modulate.a = 1.0

func hurt() -> void:
	_hurt_remaining = 0.24

func reset_bars() -> void:
	boss_bar.value = 1.0
	health_bar.value = 1.0
	_boss_target = 1.0
	_hp_target = 1.0
	_hurt_remaining = 0.0

func update_hud(snapshot: Dictionary) -> void:
	hud.text = "生命  %d / %d                 收纳  %d / %d                 冲刺  %s" % [snapshot["health"], snapshot["max_health"], snapshot["captured"], snapshot["capacity"], "就绪" if float(snapshot["dash_cd"]) <= 0.0 else "%.1f 秒" % float(snapshot["dash_cd"])]
	_hp_target = float(snapshot["health"]) / maxf(1.0, float(snapshot["max_health"]))
	fold_bar.value = float(snapshot["captured"]) / float(snapshot["capacity"]) if float(snapshot["fold_cd"]) <= 0.0 else 1.0 - float(snapshot["fold_cd"]) / 1.5
	dash_bar.value = 1.0 - clampf(float(snapshot["dash_cd"]) / 2.0, 0.0, 1.0)
	stage_label.text = snapshot["stage"]
	build_label.text = snapshot["build"]
	hint_label.text = snapshot["hint"]
	var boss_snapshot: Dictionary = snapshot.get("boss", {})
	boss_bar.visible = not boss_snapshot.is_empty()
	core_bar.visible = boss_bar.visible
	boss_label.visible = boss_bar.visible
	if not boss_snapshot.is_empty():
		_boss_target = float(boss_snapshot["health"]) / float(boss_snapshot["maximum_health"])
		core_bar.value = float(boss_snapshot["stagger_ratio"])
		boss_label.text = "礁冠炮城    ·    阶段 %d / 2    ·    核心蓄压 %d%%" % [boss_snapshot["phase"], int(float(boss_snapshot["stagger_ratio"]) * 100.0)]

func _process(delta: float) -> void:
	# These are presentation timers, deliberately separate from the combat clock.
	boss_bar.value = move_toward(boss_bar.value, _boss_target, delta * 0.55)
	health_bar.value = move_toward(health_bar.value, _hp_target, delta * 1.5)
	if not get_tree().paused:
		_toast_remaining = maxf(0.0, _toast_remaining - delta)
		toast_label.modulate.a = minf(1.0, _toast_remaining * 2.0)
	_hurt_remaining = maxf(0.0, _hurt_remaining - delta)
	for edge: ColorRect in _edges:
		edge.color.a = (_hurt_remaining / 0.24) * 0.4
