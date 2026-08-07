class_name FoldlightHUD
extends Control

## Responsive, cardless HUD drawn in screen space. The world pushes snapshots down;
## this node never polls gameplay state.

const INK := Color(0.018, 0.028, 0.075, 0.96)
const PAPER := Color(0.94, 0.91, 0.78, 1.0)
const MUTED_PAPER := Color(0.67, 0.70, 0.70, 1.0)
const CYAN := Color(0.30, 0.88, 0.86, 1.0)
const GOLD := Color(1.0, 0.70, 0.29, 1.0)
const MAGENTA := Color(0.90, 0.30, 0.60, 1.0)

var _state: Dictionary = {
	"mode": &"title",
	"score": 0,
	"health": 5,
	"max_health": 5,
	"focus": 1.0,
	"captured": 0,
	"capacity": 16,
	"folding": false,
	"charge_ratio": 0.0,
	"act": 0,
	"act_name": "序",
	"act_scene_tag": "",
	"act_objective": "",
	"progress": 0.0,
	"pressure": 1,
	"combo": 0,
	"boss_health": 0,
	"boss_max": 0,
	"tutorial": "",
	"tutorial_alpha": 0.0,
	"stage_message": "",
	"stage_subtitle": "",
	"stage_alpha": 0.0,
	"device": &"keyboard",
	"muted": false,
	"run_time": 0.0,
	"rank": "",
	"event_message": "",
	"event_alpha": 0.0,
	"seal_options": [],
	"seal_selected": 0,
	"path_locked": false,
	"path_name": "",
	"path_step": 0,
	"next_threat": "",
	"owned_doctrines": [],
	"synergies": [],
	"status_effects": [],
	"enemy_tip": {},
	"effect_tip": {},
	"briefing": {},
	"briefing_queue": 0,
	"profile": {},
	"settings": {},
	"settings_selected": 0,
	"meta_catalog": [],
	"sanctuary_selected": 0,
	"glimmer_reward": 0,
	"mission": {},
	"mission_index": 0,
	"mission_assisted": false,
	"mission_result": {},
	"objective": {},
	"campaign_missions": [],
	"campaign_selected": 0,
	"campaign": {},
	"active_checkpoint": {},
	"challenge_active": false,
	"challenge": {},
	"challenge_draft": false,
	"challenge_drafts": 0,
	"tutorial_active": false,
	"tutorial_step": 0,
	"tutorial_total": 0.0,
}
var _display_score: float = 0.0
var _time: float = 0.0
var _flash_color := Color.WHITE
var _flash_amount: float = 0.0
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	_display_score = move_toward(_display_score, float(_state.get("score", 0)), maxf(10.0, absf(float(_state.get("score", 0)) - _display_score) * delta * 6.0))
	_flash_amount = maxf(0.0, _flash_amount - delta * 1.8)
	queue_redraw()


func present(snapshot: Dictionary) -> void:
	for key in snapshot:
		_state[key] = snapshot[key]
	queue_redraw()


func flash(color: Color, amount: float = 0.45) -> void:
	_flash_color = color
	_flash_amount = maxf(_flash_amount, amount)


func _draw() -> void:
	var mode: StringName = _state.get("mode", &"title")
	match mode:
		&"title": _draw_title()
		&"campaign_map": _draw_campaign_map()
		&"playing": _draw_playing_hud()
		&"briefing":
			_draw_playing_hud()
			_draw_briefing()
		&"upgrade":
			_draw_playing_hud()
			_draw_upgrade()
		&"settings": _draw_settings()
		&"archive": _draw_archive()
		&"paused":
			_draw_playing_hud()
			_draw_pause()
		&"game_over": _draw_result(false)
		&"victory": _draw_result(true)
		_: pass

	var stage_alpha: float = float(_state.get("stage_alpha", 0.0))
	if stage_alpha > 0.005 and mode != &"briefing":
		_draw_stage_message(stage_alpha)
	if _flash_amount > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_amount * 0.42))


func _draw_title() -> void:
	var viewport_size := size
	# Poster-like hierarchy: one dominant title, no framed menu.
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.018, 0.055, 0.18))
	var center_x := viewport_size.x * 0.5
	var horizon := viewport_size.y * 0.45
	_draw_text("PAPER SEA / 纸海档案 07", Vector2(90, 76), 22, Color(CYAN.r, CYAN.g, CYAN.b, 0.78), 2.0)
	_draw_text("THREE CHAPTERS / TWELVE VOYAGES", Vector2(viewport_size.x - 500, 76), 18, Color(PAPER.r, PAPER.g, PAPER.b, 0.48), 1.5)
	draw_line(Vector2(90, 106), Vector2(viewport_size.x - 90, 106), Color(CYAN.r, CYAN.g, CYAN.b, 0.16), 1.0, true)

	_draw_centered("FOLDLIGHT", horizon - 72, 126, PAPER, 7.0)
	_draw_centered("折　光", horizon + 45, 58, GOLD, 3.0)
	_draw_centered("把躲不开的，折成你的光。", horizon + 126, 27, Color(PAPER.r, PAPER.g, PAPER.b, 0.78), 2.0)

	var device: StringName = _state.get("device", &"keyboard")
	var control_text := "左摇杆移动　·　按住 A 收纳弹幕　·　松开返还" if device == &"gamepad" else "WASD / 方向键移动　·　按住 空格 收纳弹幕　·　松开返还"
	_draw_centered(control_text, viewport_size.y - 190, 23, Color(MUTED_PAPER.r, MUTED_PAPER.g, MUTED_PAPER.b, 0.8), 1.0)
	var mode_prompt := "RB 无尽挑战　·　LB 新手教程" if device == &"gamepad" else "V 无尽挑战　·　F 新手教程"
	_draw_centered(mode_prompt, viewport_size.y - 150, 18, Color(CYAN.r, CYAN.g, CYAN.b, 0.72), 1.0)
	var pulse := 0.62 + sin(_time * 3.2) * 0.24
	var profile: Dictionary = _state.get("profile", {})
	var campaign: Dictionary = profile.get("campaign", {})
	var checkpoint: Dictionary = campaign.get("active_checkpoint", {})
	var start_text := ("按 A 继续航路" if device == &"gamepad" else "按 空格 继续航路") if not checkpoint.is_empty() else ("按 A 从潮界继续" if device == &"gamepad" else "按 空格 从潮界继续")
	_draw_centered(start_text, viewport_size.y - 112, 30, Color(GOLD.r, GOLD.g, GOLD.b, pulse), 2.0)
	draw_line(Vector2(center_x - 78, viewport_size.y - 74), Vector2(center_x + 78, viewport_size.y - 74), Color(GOLD.r, GOLD.g, GOLD.b, pulse * 0.62), 2.0, true)
	var side_prompt := "X 折光庭　·　Y 设置" if device == &"gamepad" else "C 折光庭　·　TAB 设置"
	_draw_text(side_prompt, Vector2(viewport_size.x - 310, viewport_size.y - 72), 16, Color(PAPER.r, PAPER.g, PAPER.b, 0.42), 1.0)
	var best_score := int(profile.get("best_score", 0))
	var victories := int(profile.get("victories", 0))
	var glimmer := int(profile.get("glimmer", 0))
	if best_score > 0:
		_draw_text("BEST %07d　/　DAWNS %02d　/　余辉 %03d" % [best_score, victories, glimmer], Vector2(90, viewport_size.y - 72), 16, Color(PAPER.r, PAPER.g, PAPER.b, 0.42), 1.0)


func _draw_campaign_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.014, 0.046, 0.96))
	_draw_text("PAPER SEA / MAIN VOYAGE", Vector2(76, 62), 18, Color(CYAN.r, CYAN.g, CYAN.b, 0.64), 1.0)
	_draw_centered("纸　海　航　路", 92, 46, PAPER, 4.0)
	var campaign: Dictionary = _state.get("campaign", {})
	var campaign_seconds := float(campaign.get("campaign_seconds", 0.0))
	var completed: Dictionary = campaign.get("completed", {})
	_draw_centered("三章十二航　·　完成 %02d / 12　·　航行 %02d:%02d" % [completed.size(), int(campaign_seconds) / 3600, (int(campaign_seconds) / 60) % 60], 135, 16, Color(GOLD.r, GOLD.g, GOLD.b, 0.68), 1.0)
	draw_line(Vector2(76, 160), Vector2(size.x - 76, 160), Color(CYAN.r, CYAN.g, CYAN.b, 0.14), 1.0, true)

	var missions: Array = _state.get("campaign_missions", [])
	var selected := clampi(int(_state.get("campaign_selected", 0)), 0, maxi(0, missions.size() - 1))
	var card_size := Vector2(400.0, 148.0)
	for index in missions.size():
		var mission: Dictionary = missions[index]
		var column := index % 4
		var row := index / 4
		var rect := Rect2(Vector2(76.0 + column * 444.0, 196.0 + row * 176.0), card_size)
		var accent: Color = mission.get("accent", CYAN)
		var locked := bool(mission.get("locked", false))
		var is_selected := index == selected
		var alpha := 0.32 if locked else 1.0
		draw_rect(rect, Color(0.018, 0.032, 0.072, 0.90 if not locked else 0.55))
		draw_rect(rect, Color(accent.r, accent.g, accent.b, (0.92 if is_selected else 0.22) * alpha), false, 3.0 if is_selected else 1.0)
		if is_selected:
			draw_rect(rect.grow(7.0), Color(accent.r, accent.g, accent.b, 0.075), false, 3.0)
		var chapter := int(mission.get("chapter", 1))
		var mission_number := int(mission.get("mission_number", 1))
		_draw_text("%s-%d" % [["I", "II", "III"][chapter - 1], mission_number], rect.position + Vector2(24, 32), 15, Color(accent.r, accent.g, accent.b, 0.78 * alpha), 1.0)
		_draw_text(str(mission.get("title", "")), rect.position + Vector2(24, 73), 27, Color(PAPER.r, PAPER.g, PAPER.b, 0.90 * alpha), 2.0)
		_draw_text(str(mission.get("location", "")), rect.position + Vector2(24, 105), 14, Color(PAPER.r, PAPER.g, PAPER.b, 0.48 * alpha), 1.0)
		var minutes := int(mission.get("expected_seconds", 0)) / 60
		var status := "封存" if locked else ("已归航 %s" % str(mission.get("best_rank", "—")) if bool(mission.get("completed", false)) else "可出航")
		_draw_text("%02d 分　·　%s" % [minutes, status], rect.position + Vector2(255, 129), 13, Color(GOLD.r, GOLD.g, GOLD.b, 0.62 * alpha), 1.0)

	if not missions.is_empty():
		var selected_mission: Dictionary = missions[selected]
		var detail_rect := Rect2(Vector2(76, 738), Vector2(size.x - 152, 250))
		var detail_accent: Color = selected_mission.get("accent", CYAN)
		draw_rect(detail_rect, Color(0.012, 0.026, 0.062, 0.88))
		draw_rect(detail_rect, Color(detail_accent.r, detail_accent.g, detail_accent.b, 0.30), false, 1.0)
		_draw_text(str(selected_mission.get("chapter_title", "")), detail_rect.position + Vector2(28, 36), 14, Color(detail_accent.r, detail_accent.g, detail_accent.b, 0.72), 1.0)
		_draw_text(str(selected_mission.get("title", "")), detail_rect.position + Vector2(28, 83), 34, PAPER, 2.0)
		_draw_text(str(selected_mission.get("subtitle", "")), detail_rect.position + Vector2(28, 118), 17, Color(GOLD.r, GOLD.g, GOLD.b, 0.72), 1.0)
		_draw_wrapped_left(str(selected_mission.get("synopsis", "")), detail_rect.position + Vector2(28, 157), 16, Color(PAPER.r, PAPER.g, PAPER.b, 0.60), 44)
		_draw_text("终潮　%s" % str(selected_mission.get("boss_title", "")), detail_rect.position + Vector2(1160, 67), 19, Color(PAPER.r, PAPER.g, PAPER.b, 0.70), 1.0)
		var checkpoint: Dictionary = _state.get("active_checkpoint", {})
		if String(checkpoint.get("mission_id", "")) == String(selected_mission.get("id", "")):
			_draw_text("潮界存档　潮之 %d　·　可继续" % int(checkpoint.get("tide", 1)), detail_rect.position + Vector2(1160, 111), 17, GOLD, 1.0)
		elif bool(selected_mission.get("locked", false)):
			_draw_text("完成前一航路后解锁", detail_rect.position + Vector2(1160, 111), 17, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.62), 1.0)
		else:
			_draw_text("从第一潮出航", detail_rect.position + Vector2(1160, 111), 17, Color(CYAN.r, CYAN.g, CYAN.b, 0.68), 1.0)

	var device: StringName = _state.get("device", &"keyboard")
	var prompt := "左摇杆选航路　·　A 出航　·　X 折光庭　·　START 返回" if device == &"gamepad" else "WASD / 方向键选航路　·　空格出航　·　C 折光庭　·　ESC 返回"
	_draw_centered(prompt, size.y - 38, 17, Color(PAPER.r, PAPER.g, PAPER.b, 0.52), 1.0)


func _draw_playing_hud() -> void:
	var viewport_size := size
	var health: int = int(_state.get("health", 5))
	var max_health: int = int(_state.get("max_health", 5))
	var focus: float = float(_state.get("focus", 1.0))
	var captured: int = int(_state.get("captured", 0))
	var capacity: int = int(_state.get("capacity", 16))
	var folding: bool = bool(_state.get("folding", false))
	var charge_ratio: float = float(_state.get("charge_ratio", 0.0))
	var progress: float = clampf(float(_state.get("progress", 0.0)), 0.0, 1.0)
	var combo: int = int(_state.get("combo", 0))
	var mission: Dictionary = _state.get("mission", {})

	# Hairline edge frame and title mark.
	draw_line(Vector2(54, 48), Vector2(viewport_size.x - 54, 48), Color(CYAN.r, CYAN.g, CYAN.b, 0.12), 1.0, true)
	_draw_text("FOLDLIGHT / 折光", Vector2(64, 83), 20, Color(PAPER.r, PAPER.g, PAPER.b, 0.72), 1.0)
	if not mission.is_empty():
		_draw_text("%s / %s" % [str(mission.get("title", "")), str(mission.get("location", ""))], Vector2(64, 143), 12, Color(GOLD.r, GOLD.g, GOLD.b, 0.44), 1.0)
	_draw_text("LIFE", Vector2(64, 119), 14, Color(CYAN.r, CYAN.g, CYAN.b, 0.6), 1.0)
	for index in max_health:
		var center := Vector2(124 + index * 38, 113)
		_draw_life_petals(center, index < health)

	# Chapter progress sits on the same visual baseline, without a panel.
	var act: int = int(_state.get("act", 1))
	var act_name: String = str(_state.get("act_name", "静水"))
	_draw_centered("潮之%d · %s" % [act, act_name], 85, 20, Color(PAPER.r, PAPER.g, PAPER.b, 0.84), 1.0)
	var pressure := int(_state.get("pressure", 1))
	var scene_tag := str(_state.get("act_scene_tag", ""))
	_draw_centered("%s　/　潮压 %02d" % [scene_tag, pressure], 139, 13, Color(GOLD.r, GOLD.g, GOLD.b, 0.66), 1.0)
	var progress_start := Vector2(viewport_size.x * 0.34, 112)
	var progress_end := Vector2(viewport_size.x * 0.66, 112)
	draw_line(progress_start, progress_end, Color(PAPER.r, PAPER.g, PAPER.b, 0.12), 3.0, true)
	draw_line(progress_start, progress_start.lerp(progress_end, progress), GOLD, 3.0, true)
	draw_circle(progress_start.lerp(progress_end, progress), 5.0, PAPER)

	var score_text := "%07d" % int(_display_score)
	var score_width := _font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_draw_text(score_text, Vector2(viewport_size.x - 64 - score_width, 91), 34, PAPER, 2.0)
	_draw_text("SCORE", Vector2(viewport_size.x - 134, 119), 13, Color(CYAN.r, CYAN.g, CYAN.b, 0.58), 1.0)

	if combo >= 3:
		var combo_alpha := clampf(0.42 + float(combo) * 0.025, 0.42, 0.96)
		_draw_text("光返 × %d" % combo, Vector2(viewport_size.x - 205, 168), 19, Color(GOLD.r, GOLD.g, GOLD.b, combo_alpha), 1.5)

	var owned: Array = _state.get("owned_doctrines", [])
	if not owned.is_empty():
		_draw_text("折法", Vector2(64, 164), 13, Color(CYAN.r, CYAN.g, CYAN.b, 0.54), 1.0)
		var display_start := maxi(0, owned.size() - 6)
		for owned_index in range(display_start, owned.size()):
			var doctrine: Dictionary = owned[owned_index]
			var family := int(doctrine.get("family", 0))
			var color := CYAN if family == 0 else (GOLD if family == 1 else MAGENTA)
			var local_index := owned_index - display_start
			var center := Vector2(80.0 + local_index * 27.0, 185.0)
			var mark := PackedVector2Array([center + Vector2(0,-7), center + Vector2(7,0), center + Vector2(0,7), center + Vector2(-7,0)])
			draw_colored_polygon(mark, Color(color.r, color.g, color.b, 0.66))
	var synergies: Array = _state.get("synergies", [])
	if not synergies.is_empty():
		var synergy_names: Array[String] = []
		for synergy_value in synergies:
			var synergy: Dictionary = synergy_value
			synergy_names.append(str(synergy.get("title", "")))
		_draw_text("共鸣　%s" % " · ".join(synergy_names), Vector2(230, 188), 12, Color(GOLD.r, GOLD.g, GOLD.b, 0.58), 1.0)

	var statuses: Array = _state.get("status_effects", [])
	for status_index in statuses.size():
		var status: Dictionary = statuses[status_index]
		var status_color: Color = status.get("color", MAGENTA)
		var status_rect := Rect2(Vector2(64.0, 218.0 + status_index * 62.0), Vector2(326.0, 52.0))
		draw_rect(status_rect, Color(0.025, 0.038, 0.08, 0.88))
		draw_rect(status_rect, Color(status_color.r, status_color.g, status_color.b, 0.52), false, 1.0)
		draw_rect(Rect2(status_rect.position, Vector2(4.0, status_rect.size.y)), Color(status_color.r, status_color.g, status_color.b, 0.86))
		_draw_text("%s  %.1fs" % [str(status.get("title", "")), float(status.get("remaining", 0.0))], status_rect.position + Vector2(14, 21), 14, Color(PAPER.r, PAPER.g, PAPER.b, 0.92), 1.0)
		_draw_text(str(status.get("detail", "")), status_rect.position + Vector2(111, 21), 12, Color(PAPER.r, PAPER.g, PAPER.b, 0.46), 1.0)
		_draw_text(str(status.get("counter", "")), status_rect.position + Vector2(14, 42), 12, Color(status_color.r, status_color.g, status_color.b, 0.84), 1.0)

	# Focus, fold charge and captured ammunition share one action-oriented footer.
	var bar_left := viewport_size.x * 0.36
	var bar_right := viewport_size.x * 0.64
	var bar_y := viewport_size.y - 62
	var footer_rect := Rect2(Vector2(bar_left - 118.0, bar_y - 45.0), Vector2(bar_right - bar_left + 236.0, 72.0))
	draw_rect(footer_rect, Color(0.012, 0.027, 0.064, 0.76))
	draw_rect(footer_rect, Color(CYAN.r, CYAN.g, CYAN.b, 0.10), false, 1.0)
	draw_line(Vector2(bar_left, bar_y), Vector2(bar_right, bar_y), Color(PAPER.r, PAPER.g, PAPER.b, 0.11), 5.0, true)
	var focus_color := CYAN.lerp(MAGENTA, clampf((0.26 - focus) * 3.8, 0.0, 1.0))
	draw_line(Vector2(bar_left, bar_y), Vector2(lerpf(bar_left, bar_right, focus), bar_y), focus_color, 5.0, true)
	draw_circle(Vector2(lerpf(bar_left, bar_right, focus), bar_y), 5.0, PAPER)
	if folding:
		draw_line(Vector2(bar_left, bar_y - 8.0), Vector2(lerpf(bar_left, bar_right, charge_ratio), bar_y - 8.0), GOLD, 2.0, true)
	_draw_text("折息 %03d%%" % int(round(focus * 100.0)), Vector2(bar_left - 104, bar_y + 7), 15, Color(PAPER.r, PAPER.g, PAPER.b, 0.68), 1.0)
	_draw_text("收纳 %02d / %02d" % [captured, capacity], Vector2(bar_right + 25, bar_y + 7), 16, Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 1.0)

	var device: StringName = _state.get("device", &"keyboard")
	var action_name := "A" if device == &"gamepad" else "空格"
	var action_text := "松开 %s 返还　·　蓄力 %03d%%" % [action_name, int(round(charge_ratio * 100.0))] if folding else "按住 %s 展开折域" % action_name
	_draw_centered(action_text, bar_y - 20.0, 14, Color(GOLD.r, GOLD.g, GOLD.b, 0.76), 1.0)
	var pause_text := "START 暂停" if device == &"gamepad" else "ESC 暂停"
	_draw_text(pause_text, Vector2(viewport_size.x - 160, viewport_size.y - 31), 14, Color(PAPER.r, PAPER.g, PAPER.b, 0.38), 1.0)
	var muted: bool = bool(_state.get("muted", false))
	_draw_text("M 声音：%s" % ("关" if muted else "开"), Vector2(64, viewport_size.y - 31), 14, Color(PAPER.r, PAPER.g, PAPER.b, 0.38), 1.0)

	var boss_health: int = int(_state.get("boss_health", 0))
	var boss_max: int = int(_state.get("boss_max", 0))
	var challenge_active := bool(_state.get("challenge_active", false))
	if challenge_active:
		var challenge: Dictionary = _state.get("challenge", {})
		var event: Dictionary = challenge.get("event", {})
		# Enemy counterplay cards own the upper-right lane; endless events sit below it.
		var panel := Rect2(Vector2(viewport_size.x - 424.0, 370.0), Vector2(360.0, 128.0))
		var event_accent: Color = event.get("accent", CYAN)
		draw_rect(panel, Color(0.012, 0.024, 0.064, 0.90))
		draw_rect(panel, Color(event_accent.r, event_accent.g, event_accent.b, 0.46), false, 1.5)
		_draw_text("ENDLESS / 潮压 %02d" % int(challenge.get("tier", 1)), panel.position + Vector2(18, 28), 15, Color(GOLD.r, GOLD.g, GOLD.b, 0.88), 1.0)
		_draw_text("疆界 %03d%%　事件 %.0fs　折法 %.0fs" % [int(round(float(challenge.get("arena_ratio", 0.0)) * 100.0)), float(challenge.get("next_event", 0.0)), float(challenge.get("next_draft", 0.0))], panel.position + Vector2(18, 55), 12, Color(PAPER.r, PAPER.g, PAPER.b, 0.58), 1.0)
		if not event.is_empty():
			var sign_text := "吉潮" if StringName(event.get("polarity", &"positive")) == &"positive" else "凶潮"
			_draw_text("%s · %s" % [sign_text, str(event.get("title", ""))], panel.position + Vector2(18, 84), 15, Color(event_accent.r, event_accent.g, event_accent.b, 0.94), 1.0)
			_draw_text("%s　%.1fs" % [str(event.get("detail", "")), float(event.get("remaining", 0.0))], panel.position + Vector2(18, 108), 11, Color(PAPER.r, PAPER.g, PAPER.b, 0.60), 1.0)
		else:
			_draw_text("潮面暂稳 · 准备下一次异变", panel.position + Vector2(18, 91), 13, Color(PAPER.r, PAPER.g, PAPER.b, 0.52), 1.0)
		_draw_centered("活下去 · 收纳 · 构筑", 170, 13, Color(PAPER.r, PAPER.g, PAPER.b, 0.42), 1.0)
	elif boss_max > 0 and boss_health > 0:
		var ratio := float(boss_health) / float(boss_max)
		_draw_centered(str(mission.get("boss_title", "终潮")), 155, 18, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.9), 1.0)
		var boss_left := viewport_size.x * 0.31
		var boss_right := viewport_size.x * 0.69
		draw_line(Vector2(boss_left, 176), Vector2(boss_right, 176), Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.16), 7.0, true)
		draw_line(Vector2(boss_left, 176), Vector2(lerpf(boss_left, boss_right, ratio), 176), MAGENTA, 7.0, true)
	else:
		_draw_centered(str(_state.get("act_objective", "")), 170, 13, Color(PAPER.r, PAPER.g, PAPER.b, 0.38), 1.0)
		var objective: Dictionary = _state.get("objective", {})
		if not objective.is_empty() and StringName(objective.get("state_name", &"pending")) != &"pending":
			var objective_rect := Rect2(Vector2(viewport_size.x - 414.0, 204.0), Vector2(350.0, 78.0))
			var objective_state := StringName(objective.get("state_name", &"active"))
			var objective_color := Color(0.50, 0.92, 0.66) if objective_state == &"success" else (MAGENTA if objective_state == &"failure" else GOLD)
			draw_rect(objective_rect, Color(0.012, 0.027, 0.064, 0.84))
			draw_rect(objective_rect, Color(objective_color.r, objective_color.g, objective_color.b, 0.42), false, 1.0)
			_draw_text("航契　%s" % ("完成" if objective_state == &"success" else ("未竟" if objective_state == &"failure" else "进行中")), objective_rect.position + Vector2(16, 24), 13, Color(objective_color.r, objective_color.g, objective_color.b, 0.84), 1.0)
			_draw_text(str(objective.get("label", "")), objective_rect.position + Vector2(16, 49), 13, Color(PAPER.r, PAPER.g, PAPER.b, 0.74), 1.0)
			var objective_ratio := clampf(float(objective.get("ratio", 0.0)), 0.0, 1.0)
			draw_line(objective_rect.position + Vector2(16, 65), objective_rect.position + Vector2(334, 65), Color(PAPER.r, PAPER.g, PAPER.b, 0.12), 3.0, true)
			draw_line(objective_rect.position + Vector2(16, 65), objective_rect.position + Vector2(16 + 318.0 * objective_ratio, 65), objective_color, 3.0, true)

	var tutorial_alpha: float = float(_state.get("tutorial_alpha", 0.0))
	var tutorial: String = str(_state.get("tutorial", ""))
	if tutorial_alpha > 0.01 and not tutorial.is_empty():
		_draw_centered(tutorial, viewport_size.y * 0.72, 26, Color(PAPER.r, PAPER.g, PAPER.b, tutorial_alpha), 2.0)

	var event_alpha: float = float(_state.get("event_alpha", 0.0))
	var event_message: String = str(_state.get("event_message", ""))
	if event_alpha > 0.01 and not event_message.is_empty():
		var event_y := viewport_size.y * 0.245
		draw_line(Vector2(viewport_size.x * 0.31, event_y + 15), Vector2(viewport_size.x * 0.69, event_y + 15), Color(GOLD.r, GOLD.g, GOLD.b, event_alpha * 0.18), 1.0, true)
		_draw_centered(event_message, event_y, 21, Color(PAPER.r, PAPER.g, PAPER.b, event_alpha * 0.88), 2.0)

	var enemy_tip: Dictionary = _state.get("enemy_tip", {})
	if not enemy_tip.is_empty():
		_draw_teaching_tip(enemy_tip, Rect2(Vector2(viewport_size.x - 524.0, 188.0), Vector2(460.0, 156.0)), true)
	var effect_tip: Dictionary = _state.get("effect_tip", {})
	if not effect_tip.is_empty():
		_draw_teaching_tip(effect_tip, Rect2(Vector2(64.0, viewport_size.y - 300.0), Vector2(430.0, 138.0)), false)


func _draw_teaching_tip(tip: Dictionary, source_rect: Rect2, enemy_card: bool) -> void:
	var alpha := clampf(float(tip.get("alpha", 0.0)), 0.0, 1.0)
	if alpha <= 0.005:
		return
	var accent: Color = tip.get("accent", CYAN)
	var slide := (1.0 - alpha) * (28.0 if enemy_card else -28.0)
	var rect := Rect2(source_rect.position + Vector2(slide, 0.0), source_rect.size)
	draw_rect(Rect2(rect.position + Vector2(7, 8), rect.size), Color(0.0, 0.0, 0.025, alpha * 0.30))
	draw_rect(rect, Color(0.012, 0.025, 0.064, alpha * 0.94))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, alpha * 0.62), false, 1.4)
	draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), Color(accent.r, accent.g, accent.b, alpha * 0.90))
	draw_line(rect.position + Vector2(20, 35), rect.position + Vector2(rect.size.x - 20, 35), Color(accent.r, accent.g, accent.b, alpha * 0.20), 1.0, true)

	var glyph_center := rect.position + Vector2(59.0, rect.size.y * 0.58)
	_draw_tip_glyph(glyph_center, int(tip.get("glyph", 0)), accent, alpha, enemy_card)
	var text_x := rect.position.x + 112.0
	_draw_text(str(tip.get("eyebrow", "提示")), Vector2(text_x, rect.position.y + 24.0), 12, Color(accent.r, accent.g, accent.b, alpha * 0.78), 1.0)
	_draw_text(str(tip.get("title", "")), Vector2(text_x, rect.position.y + 66.0), 25, Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.96), 2.0)
	_draw_text(str(tip.get("body", "")), Vector2(text_x, rect.position.y + 94.0), 13, Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.58), 1.0)
	_draw_text(str(tip.get("counter", "")), Vector2(text_x, rect.position.y + 123.0), 14, Color(accent.r, accent.g, accent.b, alpha * 0.90), 1.0)

	var queued := mini(3, int(tip.get("queued", 0)))
	for queue_index in queued:
		var mark_center := rect.end - Vector2(18.0 + queue_index * 12.0, 13.0)
		var mark := _tip_diamond(mark_center, 4.0, 4.0, 0.0)
		draw_colored_polygon(mark, Color(accent.r, accent.g, accent.b, alpha * 0.52))


func _draw_tip_glyph(center: Vector2, glyph: int, accent: Color, alpha: float, enemy_card: bool) -> void:
	draw_circle(center, 37.0, Color(accent.r, accent.g, accent.b, alpha * 0.055))
	draw_arc(center, 37.0, -PI * 0.78, PI * 0.68, 32, Color(accent.r, accent.g, accent.b, alpha * 0.34), 1.4, true)
	if not enemy_card:
		match glyph:
			0:
				draw_line(center + Vector2(-22, 5), center + Vector2(22, -5), Color(accent.r, accent.g, accent.b, alpha * 0.88), 3.0, true)
				draw_circle(center, 7.0, Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.86))
			1:
				var crease := PackedVector2Array([center + Vector2(-25,-15), center + Vector2(5,-4), center + Vector2(24,17), center + Vector2(-6,5)])
				draw_polyline(crease, Color(accent.r, accent.g, accent.b, alpha * 0.90), 3.0, true)
			2:
				for ring in 3:
					draw_arc(center, 12.0 + ring * 8.0, -PI * 0.85 + ring * 0.4, PI * 0.45 + ring * 0.4, 24, Color(accent.r, accent.g, accent.b, alpha * (0.90 - ring * 0.18)), 2.0, true)
			3:
				var seal := _tip_diamond(center, 27.0, 11.0, -PI * 0.5)
				draw_colored_polygon(seal, Color(0.04, 0.01, 0.025, alpha))
				draw_polyline(_closed_tip(seal), Color(accent.r, accent.g, accent.b, alpha * 0.94), 2.2, true)
				draw_line(center + Vector2(-18, 0), center + Vector2(18, 0), Color(1.0, 0.68, 0.20, alpha), 3.0, true)
			4:
				for wind in 3:
					draw_line(center + Vector2(-25, -12 + wind * 12), center + Vector2(25, -18 + wind * 12), Color(accent.r, accent.g, accent.b, alpha * (0.92 - wind * 0.18)), 2.0, true)
			_:
				draw_circle(center, 18.0, Color(0.02, 0.02, 0.05, alpha * 0.88))
				draw_arc(center, 25.0, -PI, 0.0, 24, Color(accent.r, accent.g, accent.b, alpha * 0.92), 3.0, true)
		return

	match glyph:
		0:
			var petal := _tip_diamond(center, 24.0, 13.0, 0.0)
			draw_colored_polygon(petal, Color(accent.r, accent.g, accent.b, alpha * 0.66))
		1:
			for wing in [-1.0, 1.0]:
				var triangle := PackedVector2Array([center, center + Vector2(wing * 29.0, -17.0), center + Vector2(wing * 23.0, 18.0)])
				draw_colored_polygon(triangle, Color(accent.r, accent.g, accent.b, alpha * 0.55))
		2:
			for ring in 3:
				draw_arc(center, 11.0 + ring * 9.0, ring * 0.7, ring * 0.7 + PI * 1.35, 26, Color(accent.r, accent.g, accent.b, alpha * (0.88 - ring * 0.16)), 2.0, true)
		3:
			var horn := PackedVector2Array([center + Vector2(-26,-19), center + Vector2(30,0), center + Vector2(-26,19), center + Vector2(-10,0)])
			draw_colored_polygon(horn, Color(accent.r, accent.g, accent.b, alpha * 0.62))
		4:
			for petal_index in 6:
				var petal_center := center + Vector2.from_angle(float(petal_index) * TAU / 6.0) * 19.0
				draw_circle(petal_center, 8.0, Color(accent.r, accent.g, accent.b, alpha * 0.45))
		5:
			draw_circle(center, 25.0, Color(accent.r, accent.g, accent.b, alpha * 0.42))
			draw_circle(center + Vector2(-9, 3), 22.0, Color(0.012, 0.025, 0.064, alpha))
		6:
			draw_rect(Rect2(center - Vector2(22, 22), Vector2(44, 44)), Color(accent.r, accent.g, accent.b, alpha * 0.70), false, 2.0)
			draw_arc(center, 29.0, -PI * 0.8, PI * 0.55, 28, Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.54), 2.0, true)
		7:
			for loop_index in 3:
				var loop_radius := 14.0 + loop_index * 8.0
				draw_arc(center, loop_radius, PI * 0.18 + loop_index * 0.7, PI * 1.74 + loop_index * 0.7, 24, Color(accent.r, accent.g, accent.b, alpha * (0.90 - loop_index * 0.16)), 2.5, true)
			draw_line(center + Vector2(23, -19), center + Vector2(-22, 18), Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.72), 2.0, true)
		_:
			for spoke in 8:
				var angle := float(spoke) * TAU / 8.0
				draw_line(center + Vector2.from_angle(angle) * 12.0, center + Vector2.from_angle(angle) * 30.0, Color(accent.r, accent.g, accent.b, alpha * 0.64), 2.0, true)
			draw_circle(center, 10.0, Color(PAPER.r, PAPER.g, PAPER.b, alpha * 0.74))


func _tip_diamond(center: Vector2, length: float, width: float, angle: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle)
	var side := forward.rotated(PI * 0.5)
	return PackedVector2Array([center + forward * length, center + side * width, center - forward * length, center - side * width])


func _closed_tip(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not points.is_empty():
		result.append(points[0])
	return result


func _draw_briefing() -> void:
	var briefing: Dictionary = _state.get("briefing", {})
	if briefing.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.004, 0.008, 0.032, 0.72))
	var accent: Color = briefing.get("accent", CYAN)
	var kind := StringName(briefing.get("kind", &"stage"))
	var card_size := Vector2(1040.0, 530.0)
	var rect := Rect2((size - card_size) * 0.5, card_size)
	for glow in range(6, 0, -1):
		draw_rect(rect.grow(float(glow) * 8.0), Color(accent.r, accent.g, accent.b, 0.008 * float(7 - glow)), false, 3.0)
	draw_rect(Rect2(rect.position + Vector2(10, 12), rect.size), Color(0.0, 0.0, 0.02, 0.36))
	draw_rect(rect, Color(0.012, 0.025, 0.064, 0.985))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.76), false, 2.5)
	draw_rect(Rect2(rect.position, Vector2(7.0, rect.size.y)), Color(accent.r, accent.g, accent.b, 0.92))
	draw_line(rect.position + Vector2(42, 92), rect.position + Vector2(rect.size.x - 42, 92), Color(accent.r, accent.g, accent.b, 0.22), 1.0, true)
	_draw_text("游戏已暂停 · 阅读后确认", rect.position + Vector2(42, 45), 15, Color(accent.r, accent.g, accent.b, 0.66), 1.0)
	var eyebrow := str(briefing.get("eyebrow", "航行简报"))
	_draw_text(eyebrow, rect.position + Vector2(42, 78), 18, Color(PAPER.r, PAPER.g, PAPER.b, 0.54), 1.0)

	if kind == &"enemy" or kind == &"effect":
		_draw_tip_glyph(rect.position + Vector2(142, 274), int(briefing.get("glyph", 0)), accent, 1.0, kind == &"enemy")
		var text_left := rect.position.x + 245.0
		_draw_text(str(briefing.get("title", "")), Vector2(text_left, rect.position.y + 178.0), 50, PAPER, 4.0)
		_draw_text("行　为", Vector2(text_left, rect.position.y + 235.0), 15, Color(accent.r, accent.g, accent.b, 0.72), 1.0)
		_draw_wrapped_left(str(briefing.get("body", "")), Vector2(text_left, rect.position.y + 275.0), 25, Color(PAPER.r, PAPER.g, PAPER.b, 0.82), 28)
		_draw_text("应　对", Vector2(text_left, rect.position.y + 356.0), 15, Color(accent.r, accent.g, accent.b, 0.72), 1.0)
		_draw_wrapped_left(str(briefing.get("counter", "")), Vector2(text_left, rect.position.y + 400.0), 27, Color(accent.r, accent.g, accent.b, 0.96), 27)
	else:
		var ornament_center := rect.position + Vector2(150, 278)
		for ring in 5:
			var radius := 34.0 + ring * 22.0 + sin(_time * 0.55 + ring) * 4.0
			draw_arc(ornament_center, radius, -PI * 0.86 + ring * 0.68, PI * 0.18 + ring * 0.68, 42, Color(accent.r, accent.g, accent.b, 0.16 - ring * 0.018), 2.0, true)
		var story_left := rect.position.x + 275.0
		_draw_text(str(briefing.get("title", "")), Vector2(story_left, rect.position.y + 190.0), 48, PAPER, 4.0)
		_draw_wrapped_left(str(briefing.get("body", "")), Vector2(story_left, rect.position.y + 255.0), 24, Color(PAPER.r, PAPER.g, PAPER.b, 0.80), 31)
		_draw_text(str(briefing.get("counter", "")), Vector2(story_left, rect.position.y + 410.0), 21, Color(accent.r, accent.g, accent.b, 0.88), 1.0)

	var device: StringName = _state.get("device", &"keyboard")
	var prompt := "按 A 继续" if device == &"gamepad" else "按 空格 / Enter 继续"
	var pulse := 0.70 + sin(_time * 3.4) * 0.20
	_draw_centered(prompt, rect.end.y - 38.0, 23, Color(GOLD.r, GOLD.g, GOLD.b, pulse), 2.0)
	var queued := int(_state.get("briefing_queue", 0))
	if queued > 0:
		_draw_text("另有 %d 页" % queued, rect.end - Vector2(126, 26), 14, Color(PAPER.r, PAPER.g, PAPER.b, 0.40), 1.0)


func _draw_upgrade() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.012, 0.042, 0.88))
	for band in 7:
		var radius := 210.0 + band * 66.0 + sin(_time * 0.55 + band) * 9.0
		draw_arc(size * Vector2(0.5, 0.47), radius, -PI * 0.85 + band * 0.4, PI * 0.20 + band * 0.4, 64, Color(CYAN.r, CYAN.g, CYAN.b, 0.035), 1.4, true)
	var options: Array = _state.get("seal_options", [])
	var selected := int(_state.get("seal_selected", 0))
	var path_locked := bool(_state.get("path_locked", false))
	var challenge_draft := bool(_state.get("challenge_draft", false))
	_draw_centered("RANDOM CREASE / 无尽折选" if challenge_draft else "潮汐留白", 104, 20, Color(CYAN.r, CYAN.g, CYAN.b, 0.62), 1.0)
	_draw_centered("从三种折法中选一种" if challenge_draft else ("技艺成章" if path_locked else "选择本次航行的技艺"), 164, 45, PAPER, 4.0)
	var build_line := "本局永久叠加 · 每 75 秒再选一次" if challenge_draft else ("路线固定成长 · 全程没有随机掉落" if not path_locked else "%s · 固定成长 %d / 6" % [str(_state.get("path_name", "")), int(_state.get("path_step", 0)) + 1])
	_draw_centered(build_line, 205, 17, Color(PAPER.r, PAPER.g, PAPER.b, 0.52), 1.0)
	var forecast := "已经历 %d 次折选" % int(_state.get("challenge_drafts", 0)) if challenge_draft else "下一潮预报　/　%s" % str(_state.get("next_threat", "未知"))
	_draw_centered(forecast, 247, 15, Color(GOLD.r, GOLD.g, GOLD.b, 0.66), 1.0)


	var single_card := options.size() == 1
	var card_size := Vector2(620.0, 410.0) if single_card else Vector2(430.0, 440.0)
	var gap := 34.0
	var total_width := card_size.x * float(options.size()) + gap * float(maxi(0, options.size() - 1))
	var left := (size.x - total_width) * 0.5
	for index in options.size():
		var doctrine: Dictionary = options[index]
		var is_selected := index == selected
		var family := int(doctrine.get("family", 0))
		var family_color := CYAN if family == 0 else (GOLD if family == 1 else MAGENTA)
		var lift := -15.0 if is_selected else 0.0
		var rect := Rect2(Vector2(left + index * (card_size.x + gap), (286.0 if single_card else 300.0) + lift), card_size)
		if is_selected:
			for glow in range(5, 0, -1):
				draw_rect(rect.grow(float(glow) * 7.0), Color(family_color.r, family_color.g, family_color.b, 0.012 * float(6 - glow)), false, 3.0)
		draw_rect(rect, Color(0.025, 0.039, 0.082, 0.97))
		draw_rect(rect, Color(family_color.r, family_color.g, family_color.b, 0.82 if is_selected else 0.26), false, 3.0 if is_selected else 1.0)
		draw_line(rect.position + Vector2(28, 90), rect.position + Vector2(rect.size.x - 28, 90), Color(family_color.r, family_color.g, family_color.b, 0.24), 1.0, true)

		var emblem_center := rect.position + Vector2(card_size.x * 0.5, 60)
		for fold in 4:
			var angle := PI * 0.25 + fold * PI * 0.5 + _time * (0.10 if is_selected else 0.02)
			var point := emblem_center + Vector2.from_angle(angle) * 23.0
			draw_colored_polygon(PackedVector2Array([emblem_center, point, emblem_center + Vector2.from_angle(angle + PI * 0.5) * 13.0]), Color(family_color.r, family_color.g, family_color.b, 0.56))

		var family_name := "折域" if family == 0 else ("返光" if family == 1 else "灯身")
		_draw_centered_in_rect(family_name, rect, 126, 15, Color(family_color.r, family_color.g, family_color.b, 0.70))
		_draw_centered_in_rect(str(doctrine.get("title", "未命名折法")), rect, 181, 30, PAPER)
		_draw_wrapped_centered(str(doctrine.get("description", "")), rect, 235, 17, Color(PAPER.r, PAPER.g, PAPER.b, 0.68), 25 if single_card else 16)

		var rarity := int(doctrine.get("rarity", 1))
		for rarity_index in rarity:
			var rarity_center := rect.position + Vector2(card_size.x * 0.5 + (float(rarity_index) - float(rarity - 1) * 0.5) * 20.0, 377.0)
			var gem := PackedVector2Array([rarity_center + Vector2(0,-5), rarity_center + Vector2(5,0), rarity_center + Vector2(0,5), rarity_center + Vector2(-5,0)])
			draw_colored_polygon(gem, Color(family_color.r, family_color.g, family_color.b, 0.78))
		var stacks := int(doctrine.get("stacks", 0))
		var max_stacks := int(doctrine.get("max_stacks", 1))
		if stacks > 0:
			_draw_centered_in_rect("已有 %d / %d" % [stacks, max_stacks], rect, 415, 14, Color(GOLD.r, GOLD.g, GOLD.b, 0.68))
		if single_card:
			_draw_centered_in_rect("本次折法会立即写入纸灯", rect, 362, 16, Color(GOLD.r, GOLD.g, GOLD.b, 0.72))

	var device: StringName = _state.get("device", &"keyboard")
	var prompt := ("A 接受技艺" if device == &"gamepad" else "空格接受技艺") if single_card else ("左摇杆选择　·　A 确认" if device == &"gamepad" else "WASD / 方向键选择　·　空格确认")
	_draw_centered(prompt, size.y - 82, 22, Color(GOLD.r, GOLD.g, GOLD.b, 0.82), 2.0)


func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.013, 0.044, 0.92))
	_draw_text("FOLDLIGHT / SYSTEM", Vector2(86, 74), 18, Color(CYAN.r, CYAN.g, CYAN.b, 0.58), 1.0)
	_draw_centered("设置", 150, 52, PAPER, 4.0)
	_draw_centered("所有选项即时保存", 185, 16, Color(PAPER.r, PAPER.g, PAPER.b, 0.44), 1.0)
	var settings: Dictionary = _state.get("settings", {})
	var selected := int(_state.get("settings_selected", 0))
	var labels: Array[String] = ["总音量", "音乐", "音效", "屏幕晃动", "手柄震动", "全屏", "高对比弹幕"]
	var keys: Array[String] = ["master_volume", "music_volume", "sfx_volume", "screen_shake", "vibration", "fullscreen", "high_contrast"]
	var left := size.x * 0.31
	var right := size.x * 0.69
	for index in labels.size():
		var y := 286.0 + index * 82.0
		var is_selected := index == selected
		var color := GOLD if is_selected else Color(PAPER.r, PAPER.g, PAPER.b, 0.68)
		if is_selected:
			draw_rect(Rect2(Vector2(left - 28, y - 42), Vector2(right - left + 56, 61)), Color(CYAN.r, CYAN.g, CYAN.b, 0.045))
			draw_line(Vector2(left - 28, y + 19), Vector2(right + 28, y + 19), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 2.0, true)
		_draw_text(labels[index], Vector2(left, y), 23, color, 1.5)
		var value: Variant = settings.get(keys[index], 0.0)
		if index <= 3:
			var ratio := clampf(float(value), 0.0, 1.0)
			var bar_left := right - 250.0
			draw_line(Vector2(bar_left, y - 7), Vector2(right, y - 7), Color(PAPER.r, PAPER.g, PAPER.b, 0.13), 6.0, true)
			draw_line(Vector2(bar_left, y - 7), Vector2(lerpf(bar_left, right, ratio), y - 7), CYAN if index < 3 else GOLD, 6.0, true)
			_draw_text("%3d%%" % int(round(ratio * 100.0)), Vector2(right + 30, y), 17, Color(PAPER.r, PAPER.g, PAPER.b, 0.58), 1.0)
		else:
			var toggle_text := "开" if bool(value) else "关"
			var toggle_color := CYAN if bool(value) else Color(PAPER.r, PAPER.g, PAPER.b, 0.35)
			_draw_text(toggle_text, Vector2(right - 28, y), 22, toggle_color, 1.0)
	var device: StringName = _state.get("device", &"keyboard")
	var prompt := "左摇杆选择 / 调整　·　A 切换　·　START 返回" if device == &"gamepad" else "WASD / 方向键选择与调整　·　空格切换　·　ESC 返回"
	_draw_centered(prompt, size.y - 62, 18, Color(PAPER.r, PAPER.g, PAPER.b, 0.52), 1.0)


func _draw_archive() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.013, 0.044, 0.94))
	_draw_text("PAPER SEA / LANTERN COURT", Vector2(80, 70), 18, Color(CYAN.r, CYAN.g, CYAN.b, 0.58), 1.0)
	_draw_centered("折　灯　庭", 132, 48, PAPER, 4.0)
	var profile: Dictionary = _state.get("profile", {})
	var glimmer := int(profile.get("glimmer", 0))
	var complete := bool(profile.get("chapter_one_complete", false))
	_draw_centered("余辉 %03d　·　第一章 %s　·　最深潮位 %d / 7" % [glimmer, "已完成" if complete else "航行中", int(profile.get("highest_tide", 0))], 177, 17, Color(GOLD.r, GOLD.g, GOLD.b, 0.70), 1.0)
	_draw_centered("余辉来自航行、收纳与胜利；永久折法会写入此后每一次出航。", 211, 15, Color(PAPER.r, PAPER.g, PAPER.b, 0.44), 1.0)

	var catalog: Array = _state.get("meta_catalog", [])
	var selected := int(_state.get("sanctuary_selected", 0))
	var card_size := Vector2(520.0, 220.0)
	for index in catalog.size():
		var entry: Dictionary = catalog[index]
		var row := index / 3
		var column := index % 3
		var rect := Rect2(Vector2(100.0 + column * 600.0, 270.0 + row * 260.0), card_size)
		var is_selected := index == selected
		var accent: Color = entry.get("accent", CYAN)
		draw_rect(rect, Color(0.022, 0.036, 0.078, 0.94))
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.88 if is_selected else 0.24), false, 3.0 if is_selected else 1.0)
		if is_selected:
			draw_rect(rect.grow(9.0), Color(accent.r, accent.g, accent.b, 0.08), false, 3.0)
		_draw_text(str(entry.get("title", "")), rect.position + Vector2(34, 62), 31, PAPER, 2.0)
		_draw_wrapped_left(str(entry.get("description", "")), rect.position + Vector2(34, 104), 15, Color(PAPER.r, PAPER.g, PAPER.b, 0.60), 22)
		var level := int(entry.get("level", 0))
		var max_level := int(entry.get("max_level", 1))
		for level_index in max_level:
			var mark_center := rect.position + Vector2(42.0 + level_index * 28.0, 154.0)
			var mark := _tip_diamond(mark_center, 7.0, 7.0, 0.0)
			draw_colored_polygon(mark, accent if level_index < level else Color(PAPER.r, PAPER.g, PAPER.b, 0.12))
		var price_text := "已铭满" if bool(entry.get("maxed", false)) else "消耗 %d 余辉" % int(entry.get("cost", 0))
		var price_color := GOLD if bool(entry.get("affordable", false)) else Color(PAPER.r, PAPER.g, PAPER.b, 0.34)
		_draw_text("等级 %d / %d　·　%s" % [level, max_level, price_text], rect.position + Vector2(34, 194), 16, price_color, 1.0)

	var discovered_enemies: Array = profile.get("discovered_enemies", [])
	var discovered_doctrines: Array = profile.get("discovered_doctrines", [])
	_draw_centered("纸海档案　潮兽 %02d / 10　·　折法 %02d / 18　·　航行 %d" % [discovered_enemies.size(), discovered_doctrines.size(), int(profile.get("total_runs", 0))], 900, 16, Color(CYAN.r, CYAN.g, CYAN.b, 0.52), 1.0)
	var device: StringName = _state.get("device", &"keyboard")
	var prompt := "左摇杆选择　·　A 铭刻　·　START 返回" if device == &"gamepad" else "WASD / 方向键选择　·　空格铭刻　·　ESC 返回"
	_draw_centered(prompt, size.y - 48, 18, Color(PAPER.r, PAPER.g, PAPER.b, 0.52), 1.0)


func _draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.012, 0.04, 0.76))
	_draw_centered("潮汐暂停", size.y * 0.44, 55, PAPER, 4.0)
	var device: StringName = _state.get("device", &"keyboard")
	var text := "按 START 继续" if device == &"gamepad" else "按 ESC 继续"
	_draw_centered(text, size.y * 0.54, 23, Color(GOLD.r, GOLD.g, GOLD.b, 0.82), 1.0)
	var browse_enabled := bool(_state.get("debug_invincible", false))
	if browse_enabled:
		_draw_centered("浏览模式已开启  ·  玩家伤害无效", size.y * 0.60, 19, Color(0.52, 1.0, 0.86, 0.92), 2.0)
	_draw_centered("M　切换声音", size.y * (0.65 if browse_enabled else 0.60), 16, Color(PAPER.r, PAPER.g, PAPER.b, 0.46), 1.0)


func _draw_result(victory: bool) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.016, 0.048, 0.58))
	var center_y := size.y * 0.39
	var mission: Dictionary = _state.get("mission", {})
	var mission_result: Dictionary = _state.get("mission_result", {})
	var challenge_result := bool(mission_result.get("challenge", false))
	if challenge_result:
		_draw_centered("无尽潮仍在远方", center_y - 42, 55, PAPER, 4.0)
		_draw_centered("ENDLESS RUN ARCHIVED / 本局构筑已归档", center_y + 18, 17, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.72), 1.0)
		_draw_centered("潮压 %02d　·　事件 %02d　·　折选 %02d" % [int(mission_result.get("tier", 1)), int(mission_result.get("events", 0)), int(mission_result.get("drafts", 0))], center_y + 116, 22, Color(CYAN.r, CYAN.g, CYAN.b, 0.82), 1.0)
	elif victory:
		_draw_centered(str(mission.get("title", "天光折返")), center_y - 60, 64, PAPER, 5.0)
		_draw_centered("MISSION COMPLETE / 航路已归档", center_y + 2, 18, Color(CYAN.r, CYAN.g, CYAN.b, 0.74), 1.0)
		var rank: String = str(_state.get("rank", "A"))
		_draw_centered(rank, center_y + 122, 112, GOLD, 7.0)
	else:
		_draw_centered("纸灯沉入夜潮", center_y - 42, 55, PAPER, 4.0)
		_draw_centered("潮界已经保存 / THE CREASE REMEMBERS", center_y + 18, 17, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.72), 1.0)

	var score := int(_state.get("score", 0))
	var time_value := float(_state.get("run_time", 0.0))
	_draw_centered("%07d　·　%02d:%02d" % [score, int(time_value) / 60, int(time_value) % 60], center_y + 220, 27, Color(PAPER.r, PAPER.g, PAPER.b, 0.84), 2.0)
	if challenge_result:
		_draw_centered("击破 %04d　·　最佳成绩已保存" % int(mission_result.get("kills", 0)), center_y + 184, 15, Color(PAPER.r, PAPER.g, PAPER.b, 0.50), 1.0)
	var reward := int(_state.get("glimmer_reward", 0))
	_draw_centered("本次带回余辉 +%d　·　已存入折光庭" % reward, center_y + 264, 18, Color(GOLD.r, GOLD.g, GOLD.b, 0.72), 1.0)
	var device: StringName = _state.get("device", &"keyboard")
	var prompt := ("按 A 再战无尽潮" if device == &"gamepad" else "按 空格 再战无尽潮") if challenge_result else (("按 A 返回航路" if device == &"gamepad" else "按 空格 返回航路") if victory else ("按 A 从潮界重试" if device == &"gamepad" else "按 空格 从潮界重试"))
	var pulse := 0.58 + sin(_time * 3.0) * 0.22
	_draw_centered(prompt, size.y - 110, 27, Color(GOLD.r, GOLD.g, GOLD.b, pulse), 2.0)
	if not victory and bool(mission_result.get("assist_available", false)) and not bool(mission_result.get("assist_enabled", false)):
		var assist_prompt := "Y 启用宽折援助（+1 生命 · 最高 B）" if device == &"gamepad" else "TAB 启用宽折援助（+1 生命 · 最高 B）"
		_draw_centered(assist_prompt, size.y - 150, 17, Color(CYAN.r, CYAN.g, CYAN.b, 0.74), 1.0)
	elif not victory and bool(mission_result.get("assist_enabled", false)):
		_draw_centered("宽折援助已启用 · 下一次从潮界生效", size.y - 150, 17, Color(CYAN.r, CYAN.g, CYAN.b, 0.74), 1.0)
	_draw_centered("X 前往折光庭" if device == &"gamepad" else "C 前往折光庭", size.y - 68, 16, Color(CYAN.r, CYAN.g, CYAN.b, 0.56), 1.0)


func _draw_stage_message(alpha: float) -> void:
	var message: String = str(_state.get("stage_message", ""))
	var subtitle: String = str(_state.get("stage_subtitle", ""))
	if message.is_empty():
		return
	var y := size.y * 0.46
	draw_line(Vector2(size.x * 0.29, y - 59), Vector2(size.x * 0.71, y - 59), Color(CYAN.r, CYAN.g, CYAN.b, alpha * 0.2), 1.0, true)
	_draw_centered(message, y, 48, Color(PAPER.r, PAPER.g, PAPER.b, alpha), 4.0)
	_draw_centered(subtitle, y + 50, 18, Color(GOLD.r, GOLD.g, GOLD.b, alpha * 0.82), 1.0)
	draw_line(Vector2(size.x * 0.38, y + 78), Vector2(size.x * 0.62, y + 78), Color(GOLD.r, GOLD.g, GOLD.b, alpha * 0.26), 1.0, true)


func _draw_life_petals(center: Vector2, active: bool) -> void:
	var color := GOLD if active else Color(PAPER.r, PAPER.g, PAPER.b, 0.13)
	var points := PackedVector2Array([
		center + Vector2(0, -10), center + Vector2(8, 0),
		center + Vector2(0, 10), center + Vector2(-8, 0),
	])
	draw_colored_polygon(points, color)
	if active:
		draw_circle(center, 2.0, PAPER)


func _draw_text(text: String, position: Vector2, font_size: int, color: Color, shadow: float = 0.0) -> void:
	if shadow > 0.0:
		draw_string(_font, position + Vector2(shadow, shadow + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.0, 0.0, 0.02, color.a * 0.66))
	draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_centered(text: String, baseline_y: float, font_size: int, color: Color, shadow: float = 0.0) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_draw_text(text, Vector2((size.x - width) * 0.5, baseline_y), font_size, color, shadow)


func _draw_centered_in_rect(text: String, rect: Rect2, baseline_offset: float, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_draw_text(text, Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + baseline_offset), font_size, color, 1.0)


func _draw_wrapped_centered(text: String, rect: Rect2, baseline_offset: float, font_size: int, color: Color, characters_per_line: int) -> void:
	var line_count := ceili(float(text.length()) / float(maxi(1, characters_per_line)))
	for line_index in mini(4, line_count):
		var line := text.substr(line_index * characters_per_line, characters_per_line)
		_draw_centered_in_rect(line, rect, baseline_offset + line_index * 29.0, font_size, color)


func _draw_wrapped_left(text: String, position: Vector2, font_size: int, color: Color, characters_per_line: int) -> void:
	var line_count := ceili(float(text.length()) / float(maxi(1, characters_per_line)))
	for line_index in mini(4, line_count):
		var line := text.substr(line_index * characters_per_line, characters_per_line)
		_draw_text(line, position + Vector2(0.0, float(line_index) * (font_size + 12.0)), font_size, color, 1.0)
