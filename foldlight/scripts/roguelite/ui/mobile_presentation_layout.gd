extends RefCounted
## A reversible layout pass; never changes actions, saves, or gameplay state.
var _original: Dictionary = {}

func apply(ui: Node, enabled: bool) -> void:
	if not enabled:
		for entry: Dictionary in _original.values():
			var node: Object = entry.ref.get_ref()
			if node == null: continue
			if entry.kind == &"font": node.add_theme_font_size_override("font_size", entry.value)
			elif entry.kind == &"constant": node.add_theme_constant_override(entry.key, entry.value)
			else: node.set(entry.key, entry.value)
		_original.clear()
		return
	var top := safe_top(ui)
	_enlarge(ui.interface)
	for kind: StringName in ui._screens:
		var screen: Control = ui._screens[kind]
		for child in screen.get_children():
			if child is MarginContainer:
				var sides := Vector4(90, top, 90, 36)
				if kind == &"pause": sides = Vector4(400, maxf(top, 160), 400, 100)
				elif kind == &"leave_confirmation": sides = Vector4(360, maxf(top, 180), 360, 130)
				elif kind == &"settings": sides = Vector4(100, top, 100, 36)
				elif kind == &"route": sides = Vector4(50, top, 50, 30)
				elif kind == &"title": sides = Vector4(96, top, 96, 32)
				_margin(child, sides)
	_reward(ui)
	_title(ui)
	_route(ui)
	_prop(ui._settings_grid, &"columns", 2)
	for button: Button in ui._settings_minus: _prop(button, &"visible", true)
	for button: Button in ui._focus_groups.get(&"result", []):
		_prop(button, &"custom_minimum_size", Vector2(460, 120))
	var settings_stack: Node = ui._settings_grid.get_parent()
	_prop(settings_stack.get_child(0), &"visible", false)
	_prop(settings_stack.get_child(settings_stack.get_child_count() - 1), &"text", "点 − 减少 · 点选项增加")
	var pause_stack: Node = ui._focus_groups[&"pause"][0].get_parent()
	_prop(pause_stack.get_child(pause_stack.get_child_count() - 1), &"visible", false)
	_prop(ui._mechanic_panel, &"position", Vector2(-1420, top + 200))
	_prop(ui._mechanic_panel, &"size", Vector2(920, 150))
	ui._mobile_hud.position.y = top - 130.0
	_tutorial(ui, top)

static func safe_top(ui: Node) -> float:
	var touch := ui.get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method("get_layout_snapshot"):
		var insets: Vector4 = touch.get_layout_snapshot().get("safe_insets", Vector4.ZERO)
		return maxf(150.0, insets.y + 24.0)
	return 150.0

func _enlarge(node: Node) -> void:
	if node is Label or node is Button:
		_font(node, maxi(32 if node is Label else 36, node.get_theme_font_size("font_size")))
	if node is Button:
		_prop(node, &"custom_minimum_size", Vector2(maxf(120, node.custom_minimum_size.x), maxf(120, node.custom_minimum_size.y)))
	for child in node.get_children(): _enlarge(child)

func _title(ui: Node) -> void:
	var title: Control = ui._title_screen
	var column: VBoxContainer = title._content
	_prop(column, &"custom_minimum_size", Vector2(880, 0))
	# Retain the wordmark and actions; secondary prose is intentionally absent.
	for index in [0, 3, 5, 11, 13]:
		if index < column.get_child_count(): _prop(column.get_child(index), &"visible", false)
	for child in column.get_children():
		if child.get_class() == "Control": _prop(child, &"custom_minimum_size", Vector2.ZERO)
	for button: Button in title.focus_buttons:
		_prop(button, &"custom_minimum_size", Vector2(maxf(220, button.custom_minimum_size.x), 120))
		for child in button.get_children():
			if child is Label: _prop(child, &"visible", false)
	_prop(title.record_label, &"visible", false)
	_prop(title.input_label, &"visible", false)
	_prop(title.guide_label, &"visible", false)

func _reward(ui: Node) -> void:
	var stack: Node = ui._reward_title.get_parent()
	_prop(stack.get_child(0), &"visible", false)
	_constant(stack, &"separation", 14)
	_font(ui._reward_title, 42)

func _route(ui: Node) -> void:
	var heading: Node = ui._route_title.get_parent()
	_prop(heading.get_child(0), &"visible", false)
	_font(ui._route_title, 40)
	var header: Node = heading.get_parent()
	for child in header.get_children():
		if child is Button:
			_prop(child, &"custom_minimum_size", Vector2(120 if child.text in ["−", "+"] else 220, 120))
	var note_stack: Node = ui._route_panel.get_parent()
	_prop(note_stack.get_child(0), &"visible", false)
	_prop(note_stack.get_parent(), &"custom_minimum_size", Vector2(650, 0))
	var chart: Node = ui._route_atlas.get_parent()
	_prop(chart.get_child(1), &"text", "单指拖动 · 点折岛查看 · ＋ / − 缩放")
	for button: Button in ui._route_buttons:
		_prop(button, &"custom_minimum_size", Vector2(590, 120))
		_font(button, 32)

func _tutorial(ui: Node, top: float) -> void:
	var tutorial: Control = ui._quick_tutorial
	var margin: MarginContainer = tutorial.get_node("SafeArea")
	_margin(margin, Vector4(80, top, 260, 30))
	_prop(tutorial.card, &"custom_minimum_size", Vector2(1580, 0))
	_prop(tutorial.body_label, &"visible", false)
	_prop(tutorial.warning_panel, &"visible", false)
	_prop(tutorial.step_progress, &"visible", false)
	_prop(tutorial.page_label, &"visible", false)
	_font(tutorial.controls_label, 36)
	_font(tutorial.title_label, 40)
	_constant(tutorial.content, &"separation", 8)

func _margin(node: MarginContainer, sides: Vector4) -> void:
	for pair: Array in [[&"margin_left", sides.x], [&"margin_top", sides.y], [&"margin_right", sides.z], [&"margin_bottom", sides.w]]:
		_constant(node, pair[0], int(pair[1]))

func _remember(node: Object, key: StringName, value: Variant, kind: StringName) -> void:
	var id := "%d:%s:%s" % [node.get_instance_id(), key, kind]
	if not _original.has(id): _original[id] = {"ref": weakref(node), "key": key, "value": value, "kind": kind}

func _prop(node: Object, key: StringName, value: Variant) -> void:
	_remember(node, key, node.get(key), &"property")
	node.set(key, value)

func _font(node: Control, value: int) -> void:
	_remember(node, &"font_size", node.get_theme_font_size("font_size"), &"font")
	node.add_theme_font_size_override("font_size", value)

func _constant(node: Control, key: StringName, value: int) -> void:
	_remember(node, key, node.get_theme_constant(key), &"constant")
	node.add_theme_constant_override(key, value)
