class_name FoldlightPixelPlayableHud
extends Control

var game: Node


func bind_game(game_node: Node) -> void:
	game = game_node
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_draw_top_bar()
	_draw_player_status()
	_draw_cooldowns()
	_draw_boss_status()
	_draw_controls()
	_draw_state_overlay()


func _draw_top_bar() -> void:
	draw_rect(Rect2(18, 14, 1218, 48), Color(0.015, 0.035, 0.045, 0.88))
	draw_rect(Rect2(18, 14, 6, 48), Color("49d5c3") if int(game.room_index) == 1 else Color("f06b4b"))
	var title := "房间一 · 纸礁伏击" if int(game.room_index) == 1 else "房间二 · 礁冠炮城"
	draw_string(ThemeDB.fallback_font, Vector2(39, 47), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color("f4e7bd"))
	var objective := "清除守卫，进入潮门" if int(game.room_index) == 1 else "击破礁冠核心"
	draw_string(ThemeDB.fallback_font, Vector2(978, 46), objective, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("9dc3bb"))


func _draw_player_status() -> void:
	if not is_instance_valid(game.player):
		return
	draw_rect(Rect2(26, 78, 278, 66), Color(0.01, 0.03, 0.04, 0.78))
	draw_string(ThemeDB.fallback_font, Vector2(44, 103), "耐久", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("b8d2c9"))
	for index in int(game.player.max_health):
		var origin := Vector2(106 + index * 27, 91)
		var alive_heart := index < int(game.player.health)
		var color := Color("ff6b54") if alive_heart else Color("27383b")
		draw_rect(Rect2(origin, Vector2(20, 16)), color)
		draw_rect(Rect2(origin + Vector2(4, 16), Vector2(12, 5)), color.darkened(0.08))
	draw_string(ThemeDB.fallback_font, Vector2(44, 132), "收纳 %d / %d" % [int(game.captured_count), int(game.capture_capacity)], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("f4cf69"))
	var weapon_text := "自动追踪折光弹"
	draw_string(ThemeDB.fallback_font, Vector2(164, 132), weapon_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color("63e2d2"))


func _draw_cooldowns() -> void:
	var entries: Array[Dictionary] = [
		{"label": "空格 反射", "remaining": float(game.fold_cooldown), "maximum": float(game.fold_cooldown_duration), "color": Color("58e9d4")},
		{"label": "Shift 冲刺", "remaining": float(game.dash_cooldown), "maximum": float(game.dash_cooldown_duration), "color": Color("f1c35b")},
		{"label": "Q 潮爆", "remaining": float(game.active_cooldown), "maximum": float(game.active_cooldown_duration), "color": Color("ff7654")},
	]
	for index in entries.size():
		var entry := entries[index]
		var rect := Rect2(330 + index * 188, 82, 170, 54)
		draw_rect(rect, Color(0.01, 0.03, 0.04, 0.78))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 23), String(entry.label), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("e7ddbd"))
		var maximum := maxf(0.01, float(entry.maximum))
		var ready_ratio := 1.0 - clampf(float(entry.remaining) / maximum, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(12, 34), Vector2(146, 8)), Color("20363a"))
		draw_rect(Rect2(rect.position + Vector2(12, 34), Vector2(146 * ready_ratio, 8)), entry.color as Color)


func _draw_boss_status() -> void:
	if int(game.room_index) != 2 or not is_instance_valid(game.boss):
		return
	var ratio := float(game.boss.get_health_ratio())
	draw_rect(Rect2(330, 154, 594, 42), Color(0.015, 0.025, 0.035, 0.88))
	draw_rect(Rect2(342, 168, 570, 14), Color("311b20"))
	draw_rect(Rect2(342, 168, 570 * ratio, 14), Color("f0644d"))
	draw_string(ThemeDB.fallback_font, Vector2(348, 164), "礁冠炮城 · 阶段 %d" % int(game.boss_phase), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("f3dfbd"))


func _draw_controls() -> void:
	draw_rect(Rect2(24, 662, 1206, 32), Color(0.01, 0.025, 0.035, 0.84))
	var controls := "WASD / 左摇杆移动    自动攻击    按住并松开空格 / A 收纳反射    Shift / B 冲刺    Q / X 主动技    Esc / Start 退出"
	draw_string(ThemeDB.fallback_font, Vector2(45, 685), controls, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("bfd1c7"))


func _draw_state_overlay() -> void:
	var state_name := StringName(game.run_state)
	if state_name == &"playing" and float(game.tutorial_time) <= 0.0:
		return
	var title := ""
	var subtitle := ""
	var accent := Color("56e4d1")
	if state_name == &"dead":
		title = "折光熄灭"
		subtitle = "按 R / 手柄确认键重新挑战当前房间"
		accent = Color("ff6750")
	elif state_name == &"victory":
		title = "礁冠崩解 · Demo 完成"
		subtitle = "按 R 重玩，或 Esc 退出"
		accent = Color("f5c85d")
	elif state_name == &"room_clear":
		title = "房间肃清"
		subtitle = "进入右侧潮门，开始 Boss 战"
	elif float(game.tutorial_time) > 0.0:
		title = "移动即可自动锁敌"
		subtitle = "青色弹幕可收纳反射，橙色方弹只能闪避"
	else:
		return
	var alpha := 1.0 if state_name != &"playing" else clampf(float(game.tutorial_time), 0.0, 1.0)
	draw_rect(Rect2(350, 256, 554, 142), Color(0.01, 0.025, 0.035, 0.82 * alpha))
	draw_rect(Rect2(350, 256, 8, 142), Color(accent, alpha))
	var title_size := ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 31)
	draw_string(ThemeDB.fallback_font, Vector2(627 - title_size.x * 0.5, 316), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 31, Color(accent, alpha))
	var subtitle_size := ThemeDB.fallback_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(ThemeDB.fallback_font, Vector2(627 - subtitle_size.x * 0.5, 358), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color(0.88, 0.91, 0.82, alpha))

