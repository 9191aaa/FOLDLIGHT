extends Control

var controller: Node
var _font: Font = FoldlightTheme.body_font()


func _draw() -> void:
	if not is_instance_valid(controller):
		return
	var layout: Dictionary = controller.get_layout_snapshot()
	var pressed: Array = layout["pressed"]
	var stick_center: Vector2 = layout["move"]
	var stick: Vector2 = layout["stick"]
	draw_circle(stick_center, float(layout["move_radius"]), Color(FoldlightTheme.INK, 0.60))
	draw_arc(stick_center, float(layout["move_radius"]), 0, TAU, 48, Color(FoldlightTheme.PAPER, 0.35), 2.0, true)
	draw_arc(stick_center, 76.0, 0, TAU, 40, Color(FoldlightTheme.FOLD, 0.15), 2.0, true)
	var knob := stick_center + stick * 86.0
	draw_circle(knob, 45.0, Color(FoldlightTheme.FOLD, 0.40 if pressed.has(&"move") else 0.18))
	draw_arc(knob, 45.0, 0, TAU, 32, Color(FoldlightTheme.FOLD, 0.85), 2.0, true)
	_label(stick_center + Vector2(0, 164), "移动", 26, FoldlightTheme.PAPER)
	var player: Node = controller.get_player()
	for action in [&"fold", &"dash", &"active"]:
		var center: Vector2 = layout[action]
		var radius := float(layout[String(action) + "_radius"])
		var held := pressed.has(action)
		var color := FoldlightTheme.FOLD if action == &"fold" else FoldlightTheme.GOLD
		var status_text := ""
		var cooldown := 0.0
		if is_instance_valid(player):
			if action == &"dash":
				cooldown = float(player.call("get_dash_cooldown_ratio"))
				status_text = "× %d" % player.dash_component.charges if player.dash_component.charges > 0 else "%.1f 秒" % player.dash_component.cooldown_remaining
			elif action == &"active":
				cooldown = float(player.call("get_active_item_cooldown_ratio"))
				if player.active_item_slot.definition == null:
					status_text = "未装备"
					color = FoldlightTheme.MUTED
				else:
					status_text = "%.1f 秒" % player.active_item_slot.cooldown_remaining if cooldown > 0.0 else "就绪"
			elif action == &"fold":
				var duration: float = maxf(0.01, player.fold_component.roguelite_cooldown * player.fold_component.cooldown_multiplier)
				cooldown = clampf(float(player.call("get_fold_cooldown_remaining")) / duration, 0.0, 1.0)
		draw_circle(center, radius, Color(FoldlightTheme.INK, 0.76))
		draw_circle(center, radius - 8.0, Color(color, 0.23 if held else 0.06))
		draw_arc(center, radius, 0, TAU, 48, Color(color, 0.94 if held else 0.55), 3.0 if held else 2.0, true)
		if cooldown > 0.0:
			draw_arc(center, radius - 7.0, -PI * 0.5, -PI * 0.5 + TAU * cooldown, 40, Color(FoldlightTheme.MUTED, 0.7), 5.0, true)
		match action:
			&"fold":
				_label(center + Vector2(0, -7), "按住收纳", 29, color)
				_label(center + Vector2(0, 30), "松开返光", 24, FoldlightTheme.PAPER)
			&"dash":
				_label(center + Vector2(0, -4), "冲刺", 29, color)
				_label(center + Vector2(0, 30), status_text, 22, FoldlightTheme.PAPER)
			&"active":
				_label(center + Vector2(0, -4), "技能", 29, color)
				_label(center + Vector2(0, 30), status_text, 22, FoldlightTheme.PAPER)


func _label(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, center - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
