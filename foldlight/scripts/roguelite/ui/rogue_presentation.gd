class_name FoldlightRoguePresentation
extends CanvasLayer

signal new_run_requested
signal continue_requested
signal prologue_requested
signal prologue_skip_requested
signal classic_requested
signal endless_requested
signal quit_requested
signal settings_requested
signal resume_requested
signal abandon_requested
signal setting_adjust_requested(setting_key: StringName, direction: int)
signal settings_back_requested(return_screen: StringName)
signal reward_chosen(upgrade_id: StringName)
signal route_chosen(destination_id: StringName)
signal retry_requested
signal title_requested
signal mechanic_card_dismissed(content_id: StringName)

const FOLD := FoldlightRogueUITheme.FOLD
const GOLD := FoldlightRogueUITheme.GOLD
const PAPER := FoldlightRogueUITheme.PAPER
const MUTED := FoldlightRogueUITheme.MUTED
const SURFACE := FoldlightRogueUITheme.SURFACE
const QUICK_TUTORIAL_SCENE: PackedScene = preload("res://scenes/roguelite/ui/quick_tutorial_overlay.tscn")
const MECHANIC_PREVIEW_SCENE := preload("res://scripts/roguelite/ui/mechanic_preview_canvas.gd")

var screen_kind: StringName = &"title"
var _screens: Dictionary = {}
var _focus_groups: Dictionary = {}
var _focus_index: int = 0
var _mechanic_remaining: float = 0.0
var _title_primary: Button
var _title_continue: Button
var _title_prologue: Button
var _title_stats: Label
var _title_guide: Label
var _hud_region: Label
var _hud_room: Label
var _hud_health: Label
var _hud_health_bar: ProgressBar
var _hud_fold: Label
var _hud_dash: Label
var _hud_dash_bar: ProgressBar
var _hud_focus_bar: ProgressBar
var _hud_charge_bar: ProgressBar
var _hud_charge_row: Control
var _hud_weapon: Label
var _hud_weapon_bar: ProgressBar
var _hud_active: Label
var _hud_active_bar: ProgressBar
var _hud_status: Label
var _last_dash_ready: bool = true
var _last_active_ready: bool = true
var _last_fold_ready: bool = true
var _boss_bar: ProgressBar
var _boss_label: Label
var _prologue_banner: PanelContainer
var _quick_tutorial: FoldlightQuickTutorialOverlay
var _mechanic_panel: PanelContainer
var _mechanic_title: Label
var _mechanic_body: Label
var _mechanic_intro_content_id: StringName = &""
var _mechanic_intro_role: Label
var _mechanic_intro_title: Label
var _mechanic_intro_description: Label
var _mechanic_intro_rule: Label
var _mechanic_intro_counter: Label
var _mechanic_intro_accent: ColorRect
var _mechanic_intro_button: Button
var _mechanic_intro_preview: FoldlightMechanicPreviewCanvas
var _mechanic_intro_attack_caption: Label
var _pause_browse_status: Label
var _browse_mode_enabled: bool = false
var _reward_title: Label
var _reward_buttons: Array[Button] = []
var _route_title: Label
var _route_buttons: Array[Button] = []
var _result_title: Label
var _result_body: Label
var _settings_return: StringName = &"title"
var _settings_buttons: Array[Button] = []
var _settings_keys: Array[StringName] = [&"master_volume", &"music_volume", &"sfx_volume", &"screen_shake", &"vibration", &"high_contrast", &"fullscreen"]

@onready var visual_canvas: FoldlightRogueVisualCanvas = $VisualCanvas
@onready var interface: Control = $Interface
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	interface.theme = FoldlightRogueUITheme.build()
	_build_title()
	_build_hud()
	_build_reward()
	_build_route()
	_build_result()
	_build_pause()
	_build_settings()
	_build_mechanic_toast()
	_build_mechanic_briefing()
	show_title({})


func _process(delta: float) -> void:
	if _mechanic_remaining > 0.0:
		_mechanic_remaining = maxf(0.0, _mechanic_remaining - delta)
		if _mechanic_remaining <= 0.0:
			_mechanic_panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if screen_kind == &"settings" and (event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_right")):
		var owner := get_viewport().gui_get_focus_owner()
		if owner is Button and owner.has_meta("setting_key"):
			setting_adjust_requested.emit(StringName(owner.get_meta("setting_key")), -1 if event.is_action_pressed(&"move_left") else 1)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_up") or (event.is_action_pressed(&"move_left") and screen_kind != &"settings"):
		_move_focus(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down") or (event.is_action_pressed(&"move_right") and screen_kind != &"settings"):
		_move_focus(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"fold") and screen_kind in [&"title", &"reward", &"route", &"result", &"mechanic_intro"]:
		var owner := get_viewport().gui_get_focus_owner()
		if owner is BaseButton:
			(owner as BaseButton).pressed.emit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"fold") and screen_kind == &"settings":
		var owner := get_viewport().gui_get_focus_owner()
		if owner is Button:
			(owner as Button).pressed.emit()
			get_viewport().set_input_as_handled()


func show_title(profile_snapshot: Dictionary) -> void:
	_show_only(&"title")
	visual_canvas.configure(&"title", FOLD)
	var active_variant: Variant = profile_snapshot.get("active_run", {})
	var active := active_variant as Dictionary if active_variant is Dictionary else {}
	var has_continue := not active.is_empty()
	var learned := bool(profile_snapshot.get("prologue_complete", false))
	_title_continue.visible = has_continue
	_title_primary.text = _t(&"ROGUE_MENU_NEW", "开始迷航") if learned else "45 秒教学 · 开始"
	_title_prologue.visible = learned
	_title_guide.text = "移动  ·  冲刺  ·  折域反射  ·  自动武器  ·  主动技能"
	var runs := int(profile_snapshot.get("runs", 0))
	var victories := int(profile_snapshot.get("victories", 0))
	var best_region := int(profile_snapshot.get("best_region", 0))
	_title_stats.text = _t(&"ROGUE_TITLE_RECORD", "迷航记录  %d 次   返航 %d 次   最深 第%d区") % [runs, victories, best_region]
	_set_focus_group(_visible_buttons(_focus_groups.get(&"title", [])))


func show_hud() -> void:
	_show_only(&"hud")
	visual_canvas.configure(&"hud", FOLD)
	_set_focus_group([])


func update_hud(player: FoldlightPlayer, snapshot: Dictionary, room_node: Dictionary, region_title: String, wave_text: String = "", boss_snapshot: Dictionary = {}) -> void:
	if player == null:
		return
	_hud_region.text = "%s  /  %s" % [region_title, _category_title(StringName(room_node.get("category", &"combat")))]
	_hud_room.text = _t(&"ROGUE_HUD_ROOM", "房间 %d  ·  微光 %d") % [int(snapshot.get("room_count", 0)) + 1, int(snapshot.get("glimmer", 0))]
	_hud_health.text = "灯芯  %d / %d   %s%s" % [player.health, player.max_health, "◆".repeat(player.health), "◇".repeat(maxi(0, player.max_health - player.health))]
	_hud_health_bar.max_value = maxi(1, player.max_health)
	_hud_health_bar.value = player.health
	var health_accent := FoldlightRogueUITheme.DANGER if player.health <= ceili(float(player.max_health) * 0.34) else GOLD
	_hud_health.add_theme_color_override("font_color", health_accent)
	_hud_health_bar.add_theme_stylebox_override("fill", FoldlightRogueUITheme.bar_style(health_accent))
	var cooldown := player.get_fold_cooldown_remaining()
	var fold_ready := cooldown <= 0.01
	_hud_fold.text = "[空格 / A]  折域  %d / %d" % [player.captured, player.get_capture_capacity()] if fold_ready else "折域回折  %.1fs  ·  %d / %d" % [cooldown, player.captured, player.get_capture_capacity()]
	_hud_focus_bar.value = player.focus * 100.0
	_hud_charge_bar.value = player.get_charge_ratio() * 100.0 if player.folding else 0.0
	_hud_charge_row.visible = player.folding
	var dash_ratio := player.get_dash_cooldown_ratio()
	var dash_ready := player.dash_component.is_ready()
	_hud_dash.text = "[SHIFT / B]  冲刺  ·  就绪" if dash_ready else "[SHIFT / B]  冲刺  ·  %.1fs" % player.dash_component.cooldown_remaining
	_hud_dash_bar.value = 100.0 if dash_ready else (1.0 - dash_ratio) * 100.0
	_hud_dash.add_theme_color_override("font_color", FOLD if dash_ready else MUTED)
	var weapon_title := "折灯"
	if not player.weapon_mount.definitions.is_empty() and player.weapon_mount.definitions[0] != null:
		weapon_title = player.weapon_mount.definitions[0].title
	_hud_weapon.text = "[自动]  %s  ·  持续开火" % weapon_title
	_hud_weapon_bar.value = 100.0
	var active_title := _t(&"ROGUE_HUD_EMPTY_ACTIVE", "未装备主动道具")
	if player.active_item_slot.definition != null:
		active_title = player.active_item_slot.definition.title
	var active_ratio := player.get_active_item_cooldown_ratio()
	var active_ready := active_ratio <= 0.01 and player.active_item_slot.definition != null
	if player.active_item_slot.definition == null:
		_hud_active.text = "[Q / X]  主动道具  ·  尚未获得"
		_hud_active_bar.value = 0.0
		_hud_active.add_theme_color_override("font_color", MUTED)
	elif active_ready:
		_hud_active.text = "[Q / X]  %s  ·  就绪" % active_title
		_hud_active_bar.value = 100.0
		_hud_active.add_theme_color_override("font_color", GOLD)
	else:
		_hud_active.text = "[Q / X]  %s  ·  %.1fs" % [active_title, player.active_item_slot.cooldown_remaining]
		_hud_active_bar.value = (1.0 - active_ratio) * 100.0
		_hud_active.add_theme_color_override("font_color", MUTED)
	_hud_status.text = wave_text
	if dash_ready and not _last_dash_ready:
		_pulse_ready(_hud_dash)
	if active_ready and not _last_active_ready:
		_pulse_ready(_hud_active)
	if fold_ready and not _last_fold_ready:
		_pulse_ready(_hud_fold)
	_last_dash_ready = dash_ready
	_last_active_ready = active_ready
	_last_fold_ready = fold_ready
	if boss_snapshot.is_empty():
		_boss_bar.hide()
		_boss_label.hide()
	else:
		_boss_bar.show()
		_boss_label.show()
		var health := maxf(0.0, float(boss_snapshot.get("health", 0.0)))
		var maximum := maxf(1.0, float(boss_snapshot.get("maximum_health", 1.0)))
		_boss_bar.max_value = maximum
		_boss_bar.value = health
		_boss_label.text = "%s  ·  阶段 %d" % [str(boss_snapshot.get("title", "终潮")), int(boss_snapshot.get("phase", 1))]


func show_prologue_step(step_number: int, _total_steps: int, _title: String, _body: String) -> void:
	show_hud()
	_prologue_banner.hide()
	if step_number <= 1:
		_quick_tutorial.begin(not Input.get_connected_joypads().is_empty())
	else:
		_quick_tutorial.show_step(step_number - 1)


func hide_prologue_step() -> void:
	_prologue_banner.hide()
	_quick_tutorial.dismiss()


func show_reward(choices: Array[Dictionary], room_title: String) -> void:
	_show_only(&"reward")
	visual_canvas.configure(&"reward", FOLD)
	_reward_title.text = _t(&"ROGUE_REWARD_TITLE", "%s 已澄清 · 选择一道折痕") % room_title
	for index in _reward_buttons.size():
		var button := _reward_buttons[index]
		if index >= choices.size():
			button.hide()
			continue
		var choice := choices[index]
		button.show()
		button.set_meta("upgrade_id", StringName(choice.get("content_id", &"")))
		var choice_kind := StringName(choice.get("choice_kind", &"upgrade"))
		var rarity_text := _choice_kind_title(choice_kind) if choice_kind != &"upgrade" else _rarity_title(int(choice.get("rarity", 0)))
		if bool(choice.get("offensive", false)):
			rarity_text += "  ·  火力强化"
		var level := int(choice.get("next_level", 1))
		var maximum := int(choice.get("maximum_level", 1))
		button.text = "%s\n\n%s\n%s  ·  Lv.%d/%d" % [str(choice.get("title", "无名折痕")), str(choice.get("description", "")), rarity_text, level, maximum]
		var accent_value: Color = choice.get("accent", FOLD)
		button.add_theme_color_override("font_hover_color", accent_value.lightened(0.16))
		button.add_theme_stylebox_override("normal", _choice_card_style(accent_value, false))
		button.add_theme_stylebox_override("hover", _choice_card_style(accent_value, true))
		button.add_theme_stylebox_override("pressed", _choice_card_style(accent_value.lightened(0.10), true))
	_set_focus_group(_visible_buttons(_reward_buttons))


func show_route(region_snapshot: Dictionary, current_id: StringName, exits: Array[String]) -> void:
	_show_only(&"route")
	var region_accent := _region_accent(StringName(region_snapshot.get("id", &"")))
	visual_canvas.configure(&"route", region_accent)
	visual_canvas.configure_route(region_snapshot, current_id)
	_route_title.text = _t(&"ROGUE_ROUTE_TITLE", "%s · 选择下一处折点") % str(region_snapshot.get("title", "无名海域"))
	var by_id: Dictionary = {}
	for node_variant: Variant in region_snapshot.get("nodes", []):
		if node_variant is Dictionary:
			by_id[String((node_variant as Dictionary).get("id", ""))] = node_variant
	for index in _route_buttons.size():
		var button := _route_buttons[index]
		if index >= exits.size():
			button.hide()
			continue
		var destination_id := exits[index]
		var node: Dictionary = by_id.get(destination_id, {})
		button.show()
		button.set_meta("destination_id", StringName(destination_id))
		button.text = "%s\n%s" % [_category_title(StringName(node.get("category", &"combat"))), _risk_title(int(node.get("risk", 1)))]
	_set_focus_group(_visible_buttons(_route_buttons))


func show_result(result: Dictionary, prologue: bool = false) -> void:
	_show_only(&"result")
	visual_canvas.configure(&"prologue_result" if prologue else &"result", GOLD if bool(result.get("won", false)) else Color(0.90, 0.28, 0.42))
	if prologue:
		_result_title.text = _t(&"ROGUE_PROLOGUE_COMPLETE", "折灯已经会呼吸")
		_result_body.text = _t(&"ROGUE_PROLOGUE_COMPLETE_BODY", "你学会了走位、冲刺、折域、自动武器与主动道具。\n真正的纸海会更难，但规则不会再藏起来。")
	else:
		var won := bool(result.get("won", false))
		_result_title.text = _t(&"ROGUE_RESULT_WIN", "光已返航") if won else _t(&"ROGUE_RESULT_LOSE", "这盏灯沉入了纸海")
		var elapsed := int(float(result.get("time", 0.0)))
		_result_body.text = _t(&"ROGUE_RESULT_BODY", "抵达区域  %d / 3\n澄清房间  %d\n航行时间  %02d:%02d\n收集微光  %d") % [int(result.get("region", 1)), int(result.get("rooms", 0)), elapsed / 60, elapsed % 60, int(result.get("glimmer", 0))]
	_set_focus_group(_visible_buttons(_focus_groups.get(&"result", [])))


func show_pause() -> void:
	_show_only(&"pause")
	visual_canvas.configure(&"pause", FOLD)
	if _pause_browse_status != null:
		_pause_browse_status.visible = _browse_mode_enabled
	_set_focus_group(_visible_buttons(_focus_groups.get(&"pause", [])))


func set_browse_mode_enabled(enabled: bool) -> void:
	_browse_mode_enabled = enabled
	if _pause_browse_status != null:
		_pause_browse_status.visible = enabled and screen_kind == &"pause"
	if enabled:
		audio_director.play_sfx(&"release", 1.18, -4.0)


func is_browse_mode_enabled() -> bool:
	return _browse_mode_enabled


func show_settings(settings: Dictionary, return_screen: StringName) -> void:
	_settings_return = return_screen
	_show_only(&"settings")
	visual_canvas.configure(&"pause", FOLD)
	refresh_settings(settings)
	_set_focus_group(_visible_buttons(_settings_buttons))


func refresh_settings(settings: Dictionary) -> void:
	for index in mini(_settings_buttons.size(), _settings_keys.size()):
		var key := _settings_keys[index]
		var value: Variant = settings.get(String(key))
		var title: String = {
			&"master_volume": "主音量", &"music_volume": "音乐", &"sfx_volume": "音效",
			&"screen_shake": "震屏强度", &"vibration": "手柄震动", &"high_contrast": "高对比弹幕", &"fullscreen": "全屏",
		}.get(key, String(key))
		var display := ""
		if value is bool:
			display = "开启" if bool(value) else "关闭"
		elif key == &"screen_shake":
			display = ["关闭", "轻微", "标准"][clampi(int(round(float(value) * 2.0)), 0, 2)]
		else:
			display = "%d%%" % int(round(float(value) * 100.0))
		_settings_buttons[index].text = "%s     ‹  %s  ›" % [title, display]


func show_mechanic_card(snapshot: Dictionary) -> void:
	_mechanic_intro_content_id = StringName(snapshot.get("content_id", &""))
	var accent := FoldlightRogueUITheme.comfort_accent(Color(snapshot.get("accent", GOLD)))
	var preview_id := StringName(snapshot.get("preview_id", _mechanic_intro_content_id))
	var preview_kind := StringName(snapshot.get("preview_kind", &"boss" if preview_id in [&"reef_crown_battery", &"inverted_archivist", &"origami_judge"] else &"enemy"))
	_mechanic_intro_accent.color = accent
	_mechanic_intro_role.text = "%s  /  %s" % [str(snapshot.get("role_title", "首领" if preview_kind == &"boss" else "机制单位")), "首领登场" if preview_kind == &"boss" else "首次遭遇"]
	_mechanic_intro_role.add_theme_color_override("font_color", accent)
	_mechanic_intro_title.text = str(snapshot.get("title", "未知首领" if preview_kind == &"boss" else "未知敌人"))
	_mechanic_intro_description.text = str(snapshot.get("description", "先看清动作，再进入交锋。"))
	_mechanic_intro_rule.text = "它怎么打\n%s" % str(snapshot.get("rule", "出手前会有清晰预警。"))
	_mechanic_intro_counter.text = "怎么躲\n%s" % str(snapshot.get("counterplay", "看到预警先换位，再抓住空档反击。"))
	_mechanic_intro_attack_caption.text = str(snapshot.get("attack_preview_text", _attack_demo_title(StringName(snapshot.get("attack_style", &"")), preview_id)))
	_mechanic_intro_preview.configure(snapshot)
	_mechanic_intro_button.text = "知道怎么躲了，开始交锋   [空格 / A]"
	_mechanic_remaining = 0.0
	_mechanic_panel.hide()
	_show_only(&"mechanic_intro")
	visual_canvas.configure(&"mechanic_intro", accent)
	_set_focus_group([_mechanic_intro_button])
	audio_director.play_sfx(&"boss", 1.18, -7.0)


func show_boss_card(snapshot: Dictionary) -> void:
	var boss_snapshot := snapshot.duplicate(true)
	boss_snapshot["preview_kind"] = &"boss"
	show_mechanic_card(boss_snapshot)


func flash_player_damage() -> void:
	visual_canvas.flash_player_damage()


func get_mechanic_briefing_snapshot() -> Dictionary:
	var preview := _mechanic_intro_preview.get_preview_snapshot() if _mechanic_intro_preview != null else {}
	return {
		"content_id": _mechanic_intro_content_id,
		"screen_kind": screen_kind,
		"title": _mechanic_intro_title.text if _mechanic_intro_title != null else "",
		# Keep legacy aliases in the diagnostic snapshot while the actual screen
		# uses the shorter, more natural headings below.
		"rule": "它会做什么\n%s" % _mechanic_intro_rule.text if _mechanic_intro_rule != null else "",
		"counterplay": "你该怎么应对\n%s" % _mechanic_intro_counter.text if _mechanic_intro_counter != null else "",
		"rule_heading": "它怎么打",
		"counterplay_heading": "怎么躲",
		"preview": preview,
		"requires_confirmation": _mechanic_intro_button != null and _mechanic_intro_button.visible,
	}


func _build_title() -> void:
	var screen := _new_screen(&"title")
	var margin := _full_margin(screen, 110, 78, 110, 74)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 72)
	margin.add_child(columns)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 6)
	columns.add_child(identity)
	var top_space := Control.new()
	top_space.custom_minimum_size.y = 82
	identity.add_child(top_space)
	var eyebrow := _label(_t(&"ROGUE_TITLE_EYEBROW", "一只手的深海折返战"), 22, FOLD)
	identity.add_child(eyebrow)
	var logo := _label("FOLDLIGHT", 88, PAPER)
	logo.add_theme_constant_override("outline_size", 8)
	logo.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.82))
	identity.add_child(logo)
	var chinese := _label("折  光", 42, GOLD)
	identity.add_child(chinese)
	var strap := _label(_t(&"ROGUE_TITLE_STRAP", "把危险折进掌心，再让整片光返航。"), 26, MUTED)
	strap.custom_minimum_size.x = 700
	strap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(strap)
	_title_guide = _label("", 19, Color(FOLD.r, FOLD.g, FOLD.b, 0.82))
	_title_guide.custom_minimum_size.x = 700
	identity.add_child(_title_guide)
	var identity_spacer := Control.new()
	identity_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_spacer)
	_title_stats = _label("", 18, Color(MUTED.r, MUTED.g, MUTED.b, 0.85))
	identity.add_child(_title_stats)

	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 470
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 12)
	columns.add_child(menu)
	var menu_label := _label("折灯航海台", 19, MUTED)
	menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(menu_label)
	_title_continue = _button(_t(&"ROGUE_MENU_CONTINUE", "继续迷航"), 70)
	_title_continue.pressed.connect(func() -> void: continue_requested.emit())
	menu.add_child(_title_continue)
	_title_primary = _button(_t(&"ROGUE_MENU_NEW", "开始迷航"), 82)
	_title_primary.add_theme_font_size_override("font_size", 30)
	_title_primary.pressed.connect(func() -> void: new_run_requested.emit())
	menu.add_child(_title_primary)
	_title_prologue = _button("重温 45 秒教学", 62)
	_title_prologue.pressed.connect(func() -> void: prologue_requested.emit())
	menu.add_child(_title_prologue)
	var classic := _button(_t(&"ROGUE_MENU_CLASSIC", "经典战役 · 2.0 十二航"), 62)
	classic.pressed.connect(func() -> void: classic_requested.emit())
	menu.add_child(classic)
	var endless := _button("无尽生存 · 进化远航", 58)
	endless.pressed.connect(func() -> void: endless_requested.emit())
	menu.add_child(endless)
	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 12)
	menu.add_child(utility_row)
	var settings := _button(_t(&"ROGUE_MENU_SETTINGS", "设置"), 58)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func() -> void: settings_requested.emit())
	utility_row.add_child(settings)
	var quit := _button(_t(&"ROGUE_MENU_QUIT", "退出"), 58)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void: quit_requested.emit())
	utility_row.add_child(quit)
	var hint := _label(_t(&"ROGUE_TITLE_INPUT", "方向键 / WASD 选择   ·   空格 / A 确认"), 18, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(hint)
	_focus_groups[&"title"] = [_title_continue, _title_primary, _title_prologue, classic, endless, settings, quit]


func _build_hud() -> void:
	var screen := _new_screen(&"hud")
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := _full_margin(screen, 34, 28, 34, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 14)
	layout.add_child(top)
	var voyage_panel := PanelContainer.new()
	voyage_panel.name = "VoyagePanel"
	voyage_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voyage_panel.custom_minimum_size = Vector2(410, 118)
	voyage_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(FOLD.r, FOLD.g, FOLD.b, 0.48)))
	top.add_child(voyage_panel)
	var voyage_stack := VBoxContainer.new()
	voyage_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voyage_stack.add_theme_constant_override("separation", 7)
	voyage_panel.add_child(voyage_stack)
	_hud_region = _label("", 24, PAPER)
	voyage_stack.add_child(_hud_region)
	_hud_room = _label("", 18, MUTED)
	voyage_stack.add_child(_hud_room)

	var health_panel := PanelContainer.new()
	health_panel.name = "HealthCard"
	health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_panel.custom_minimum_size = Vector2(410, 118)
	health_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(GOLD.r, GOLD.g, GOLD.b, 0.68)))
	top.add_child(health_panel)
	var health_stack := VBoxContainer.new()
	health_stack.add_theme_constant_override("separation", 7)
	health_panel.add_child(health_stack)
	health_stack.add_child(_label("生命", 16, MUTED))
	_hud_health = _label("灯芯  5 / 5   ◆◆◆◆◆", 25, GOLD)
	_hud_health.add_theme_constant_override("outline_size", 3)
	_hud_health.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.74))
	health_stack.add_child(_hud_health)
	_hud_health_bar = _hud_progress_bar("HealthBar", GOLD)
	_hud_health_bar.custom_minimum_size.y = 15
	health_stack.add_child(_hud_health_bar)

	var boss_stack := VBoxContainer.new()
	boss_stack.custom_minimum_size = Vector2(520, 74)
	boss_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(boss_stack)
	_boss_label = _label("", 20, GOLD)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(520, 16)
	_boss_bar.step = 0.0
	_boss_bar.show_percentage = false
	boss_stack.add_child(_boss_label)
	boss_stack.add_child(_boss_bar)
	_boss_label.hide()
	_boss_bar.hide()

	_hud_status = _label("", 20, FOLD)
	_hud_status.custom_minimum_size.x = 250
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_hud_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	var bottom_center := CenterContainer.new()
	bottom_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(bottom_center)
	var action_band := HBoxContainer.new()
	action_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_band.add_theme_constant_override("separation", 14)
	bottom_center.add_child(action_band)

	var fold_core := PanelContainer.new()
	fold_core.name = "FoldCorePanel"
	fold_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fold_core.custom_minimum_size = Vector2(548, 122)
	var core_style := StyleBoxFlat.new()
	core_style.bg_color = Color(0.020, 0.054, 0.068, 0.94)
	core_style.border_color = Color(FOLD.r, FOLD.g, FOLD.b, 0.68)
	core_style.border_width_left = 5
	core_style.border_width_top = 1
	core_style.border_width_right = 1
	core_style.border_width_bottom = 2
	core_style.corner_radius_top_left = 2
	core_style.corner_radius_top_right = 14
	core_style.corner_radius_bottom_left = 2
	core_style.corner_radius_bottom_right = 14
	core_style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	core_style.shadow_size = 8
	fold_core.add_theme_stylebox_override("panel", core_style)
	action_band.add_child(fold_core)
	var core_margin := MarginContainer.new()
	core_margin.add_theme_constant_override("margin_left", 20)
	core_margin.add_theme_constant_override("margin_top", 9)
	core_margin.add_theme_constant_override("margin_right", 20)
	core_margin.add_theme_constant_override("margin_bottom", 9)
	fold_core.add_child(core_margin)
	var fold_stack := VBoxContainer.new()
	fold_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fold_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fold_stack.add_theme_constant_override("separation", 3)
	core_margin.add_child(fold_stack)
	fold_stack.add_child(_label("核心操作", 15, MUTED))
	_hud_fold = _label("", 23, PAPER)
	fold_stack.add_child(_hud_fold)
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 10)
	var focus_label := _label("折息", 16, MUTED)
	focus_label.custom_minimum_size.x = 54
	focus_row.add_child(focus_label)
	_hud_focus_bar = _hud_progress_bar("FoldFocusBar", FOLD)
	focus_row.add_child(_hud_focus_bar)
	fold_stack.add_child(focus_row)
	_hud_charge_row = HBoxContainer.new()
	_hud_charge_row.add_theme_constant_override("separation", 10)
	var charge_label := _label("蓄力", 16, GOLD)
	charge_label.custom_minimum_size.x = 54
	_hud_charge_row.add_child(charge_label)
	_hud_charge_bar = _hud_progress_bar("FoldChargeBar", GOLD)
	_hud_charge_row.add_child(_hud_charge_bar)
	fold_stack.add_child(_hud_charge_row)
	_hud_charge_row.hide()

	var dash_card := _hud_action_card("机动", "冲刺", Color(0.42, 0.68, 0.78), 290.0)
	action_band.add_child(dash_card["panel"])
	_hud_dash = dash_card["state"] as Label
	_hud_dash_bar = dash_card["bar"] as ProgressBar

	var active_card := _hud_action_card("主动道具", "Q / X", GOLD, 340.0)
	action_band.add_child(active_card["panel"])
	_hud_active = active_card["state"] as Label
	_hud_active_bar = active_card["bar"] as ProgressBar

	var weapon_card := _hud_action_card("自动武器", "AUTO", FOLD, 320.0)
	action_band.add_child(weapon_card["panel"])
	_hud_weapon = weapon_card["state"] as Label
	_hud_weapon_bar = weapon_card["bar"] as ProgressBar

	_prologue_banner = PanelContainer.new()
	_prologue_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_prologue_banner)
	_prologue_banner.hide()
	_quick_tutorial = QUICK_TUTORIAL_SCENE.instantiate() as FoldlightQuickTutorialOverlay
	_quick_tutorial.tutorial_skipped.connect(func() -> void: prologue_skip_requested.emit())
	screen.add_child(_quick_tutorial)


func _hud_action_card(title: String, binding: String, accent: Color, width: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "%sCard" % title
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(width, 122)
	panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(accent.r, accent.g, accent.b, 0.62)))
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)
	var heading_row := HBoxContainer.new()
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(heading_row)
	var heading := _label(title, 16, MUTED)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	var key_label := _label(binding, 15, accent)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_row.add_child(key_label)
	var state := _label("", 20, accent)
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(state)
	var bar := _hud_progress_bar("%sCooldown" % title, accent)
	bar.custom_minimum_size.y = 11
	stack.add_child(bar)
	return {"panel": panel, "state": state, "bar": bar}


func _hud_progress_bar(node_name: String, accent: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 9
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.06, 0.09, 0.88)
	background.corner_radius_top_left = 5
	background.corner_radius_top_right = 5
	background.corner_radius_bottom_left = 5
	background.corner_radius_bottom_right = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.corner_radius_top_left = 5
	fill.corner_radius_top_right = 5
	fill.corner_radius_bottom_left = 5
	fill.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _hud_surface_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.88)
	style.border_color = accent
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	return style


func _pulse_ready(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.modulate = Color(1.35, 1.35, 1.35, 1.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate", Color.WHITE, 0.26)


func _build_reward() -> void:
	var screen := _new_screen(&"reward")
	var margin := _full_margin(screen, 100, 70, 100, 66)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 22)
	margin.add_child(stack)
	var eyebrow := _label(_t(&"ROGUE_REWARD_EYEBROW", "局内构筑 · 只在本次迷航生效"), 20, FOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	_reward_title = _label("", 38, PAPER)
	_reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_reward_title)
	var choices := HBoxContainer.new()
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 26)
	stack.add_child(choices)
	for index in 3:
		var button := _button("", 390)
		button.custom_minimum_size.x = 430
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 22)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_reward_pressed.bind(button))
		choices.add_child(button)
		_reward_buttons.append(button)
	var hint := _label(_t(&"ROGUE_REWARD_HINT", "左右选择   ·   空格 / A 刻下折痕"), 18, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)


func _choice_card_style(accent: Color, lifted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.065, 0.088, 0.97) if lifted else Color(0.015, 0.035, 0.062, 0.90)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.92 if lifted else 0.46)
	style.border_width_left = 6 if lifted else 3
	style.border_width_top = 2 if lifted else 1
	style.border_width_right = 2 if lifted else 1
	style.border_width_bottom = 2 if lifted else 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 28.0
	style.content_margin_top = 24.0
	style.content_margin_right = 28.0
	style.content_margin_bottom = 24.0
	return style


func _build_route() -> void:
	var screen := _new_screen(&"route")
	var margin := _full_margin(screen, 90, 70, 90, 68)
	var stack := VBoxContainer.new()
	margin.add_child(stack)
	var eyebrow := _label(_t(&"ROGUE_ROUTE_EYEBROW", "折航图 · 你只能驶向相连的房间"), 19, FOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	_route_title = _label("", 38, PAPER)
	_route_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_route_title)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 24)
	stack.add_child(choices)
	for index in 3:
		var button := _button("", 96)
		button.custom_minimum_size.x = 360
		button.pressed.connect(_on_route_pressed.bind(button))
		choices.add_child(button)
		_route_buttons.append(button)
	stack.add_child(_label(_t(&"ROGUE_ROUTE_HINT", "分支会在汇流处重新相遇；难度标记代表威胁预算，而非敌人堆量。"), 17, MUTED))


func _build_result() -> void:
	var screen := _new_screen(&"result")
	var margin := _full_margin(screen, 120, 100, 120, 90)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 620
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 24)
	margin.add_child(stack)
	stack.add_child(_label(_t(&"ROGUE_RESULT_EYEBROW", "本次航行记录"), 20, FOLD))
	_result_title = _label("", 52, PAPER)
	stack.add_child(_result_title)
	_result_body = _label("", 25, MUTED)
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_result_body)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 18)
	stack.add_child(action_row)
	var retry := _button(_t(&"ROGUE_RESULT_RETRY", "再次迷航"), 70)
	retry.custom_minimum_size.x = 280
	retry.pressed.connect(func() -> void: retry_requested.emit())
	action_row.add_child(retry)
	var title := _button(_t(&"ROGUE_RESULT_TITLE", "返回标题"), 70)
	title.custom_minimum_size.x = 280
	title.pressed.connect(func() -> void: title_requested.emit())
	action_row.add_child(title)
	_focus_groups[&"result"] = [retry, title]


func _build_pause() -> void:
	var screen := _new_screen(&"pause")
	var margin := _full_margin(screen, 650, 150, 650, 150)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	var eyebrow := _label("纸海暂时静止", 19, FOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	var title := _label("暂停", 48, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_pause_browse_status = _label("浏览模式已开启  ·  玩家伤害无效", 20, Color(0.52, 1.0, 0.86))
	_pause_browse_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_browse_status.hide()
	stack.add_child(_pause_browse_status)
	var resume := _button("继续航行", 72)
	resume.pressed.connect(func() -> void: resume_requested.emit())
	stack.add_child(resume)
	var settings := _button("设置", 64)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	stack.add_child(settings)
	var abandon := _button("结束本次迷航", 64)
	abandon.pressed.connect(func() -> void: abandon_requested.emit())
	stack.add_child(abandon)
	stack.add_child(_label("Esc / Start 继续", 17, MUTED))
	_focus_groups[&"pause"] = [resume, settings, abandon]


func _build_settings() -> void:
	var screen := _new_screen(&"settings")
	var margin := _full_margin(screen, 520, 74, 520, 66)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	panel.add_child(stack)
	var eyebrow := _label("无障碍与音画", 18, FOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	var title := _label("设置", 40, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	for key in _settings_keys:
		var button := _button(String(key), 58)
		button.set_meta("setting_key", key)
		button.pressed.connect(func() -> void: setting_adjust_requested.emit(StringName(button.get_meta("setting_key")), 1))
		stack.add_child(button)
		_settings_buttons.append(button)
	var back := _button("返回", 58)
	back.pressed.connect(func() -> void: settings_back_requested.emit(_settings_return))
	stack.add_child(back)
	_settings_buttons.append(back)
	stack.add_child(_label("上下选择 · 左右调整 · 高对比模式会强化不可反射弹的黑色内芯", 16, MUTED))


func _build_mechanic_toast() -> void:
	_mechanic_panel = PanelContainer.new()
	_mechanic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mechanic_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mechanic_panel.position = Vector2(-486, 108)
	_mechanic_panel.size = Vector2(444, 116)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	_mechanic_panel.add_child(stack)
	_mechanic_title = _label("", 20, GOLD)
	_mechanic_body = _label("", 18, PAPER)
	_mechanic_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mechanic_body.max_lines_visible = 2
	stack.add_child(_mechanic_title)
	stack.add_child(_mechanic_body)
	interface.add_child(_mechanic_panel)
	_mechanic_panel.hide()


func _build_mechanic_briefing() -> void:
	var screen := _new_screen(&"mechanic_intro")
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.006, 0.011, 0.021, 0.93)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	var margin := _full_margin(screen, 280, 130, 280, 110)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 720)
	margin.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	_mechanic_intro_accent = ColorRect.new()
	_mechanic_intro_accent.custom_minimum_size.y = 7
	_mechanic_intro_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_mechanic_intro_accent)
	_mechanic_intro_role = _label("机制单位  /  首次遭遇", 20, GOLD)
	outer.add_child(_mechanic_intro_role)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 22)
	outer.add_child(content)
	var preview_stack := VBoxContainer.new()
	preview_stack.custom_minimum_size.x = 452
	preview_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_stack.add_theme_constant_override("separation", 8)
	content.add_child(preview_stack)
	var preview_panel := PanelContainer.new()
	preview_panel.name = "MechanicPreviewPanel"
	preview_panel.custom_minimum_size = Vector2(452, 470)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(FOLD.r, FOLD.g, FOLD.b, 0.46)))
	preview_stack.add_child(preview_panel)
	_mechanic_intro_preview = MECHANIC_PREVIEW_SCENE.new() as FoldlightMechanicPreviewCanvas
	_mechanic_intro_preview.name = "MechanicAttackPreview"
	_mechanic_intro_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_panel.add_child(_mechanic_intro_preview)
	_mechanic_intro_attack_caption = _label("动态演示 · 预警 → 出手 → 躲法", 18, MUTED)
	_mechanic_intro_attack_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mechanic_intro_attack_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_stack.add_child(_mechanic_intro_attack_caption)

	var briefing := VBoxContainer.new()
	briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefing.add_theme_constant_override("separation", 12)
	content.add_child(briefing)
	_mechanic_intro_title = _label("未知单位", 50, PAPER)
	_mechanic_intro_title.add_theme_constant_override("outline_size", 5)
	_mechanic_intro_title.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.9))
	briefing.add_child(_mechanic_intro_title)
	_mechanic_intro_description = _label("", 20, MUTED)
	_mechanic_intro_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mechanic_intro_description.custom_minimum_size.y = 58
	briefing.add_child(_mechanic_intro_description)
	var divider := HSeparator.new()
	briefing.add_child(divider)
	var rule_panel := PanelContainer.new()
	rule_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule_panel.add_theme_stylebox_override("panel", _briefing_info_style(Color(0.74, 0.48, 0.34, 0.66)))
	briefing.add_child(rule_panel)
	_mechanic_intro_rule = _label("", 23, PAPER)
	_mechanic_intro_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mechanic_intro_rule.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mechanic_intro_rule.custom_minimum_size = Vector2(620, 140)
	rule_panel.add_child(_mechanic_intro_rule)
	var counter_panel := PanelContainer.new()
	counter_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	counter_panel.add_theme_stylebox_override("panel", _briefing_info_style(Color(FOLD.r, FOLD.g, FOLD.b, 0.70)))
	briefing.add_child(counter_panel)
	_mechanic_intro_counter = _label("", 23, Color(0.57, 0.84, 0.74))
	_mechanic_intro_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mechanic_intro_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mechanic_intro_counter.custom_minimum_size = Vector2(620, 140)
	counter_panel.add_child(_mechanic_intro_counter)
	_mechanic_intro_button = _button("知道怎么躲了，开始交锋   [空格 / A]", 72)
	_mechanic_intro_button.pressed.connect(_dismiss_mechanic_briefing)
	outer.add_child(_mechanic_intro_button)


func _briefing_info_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.050, 0.94)
	style.border_color = border
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 22.0
	style.content_margin_top = 16.0
	style.content_margin_right = 22.0
	style.content_margin_bottom = 16.0
	return style


func _dismiss_mechanic_briefing() -> void:
	if screen_kind != &"mechanic_intro":
		return
	audio_director.play_sfx(&"start", 1.12, -5.0)
	mechanic_card_dismissed.emit(_mechanic_intro_content_id)


func _new_screen(kind: StringName) -> Control:
	var screen := Control.new()
	screen.name = "%sScreen" % String(kind).capitalize()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.add_child(screen)
	_screens[kind] = screen
	return screen


func _full_margin(parent: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	parent.add_child(margin)
	return margin


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text_value: String, minimum_height: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = minimum_height
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_entered.connect(func() -> void:
		var active_variant: Variant = _focus_groups.get(&"active", [])
		if active_variant is Array:
			var focused_index := (active_variant as Array).find(button)
			if focused_index >= 0:
				_focus_index = focused_index
		audio_director.play_sfx(&"ui", 1.12, -8.0)
	)
	return button


func _show_only(kind: StringName) -> void:
	screen_kind = kind
	for key_variant: Variant in _screens.keys():
		(_screens[key_variant] as Control).visible = StringName(key_variant) == kind
	_mechanic_panel.visible = _mechanic_remaining > 0.0 and kind == &"hud"


func _set_focus_group(group: Array) -> void:
	_focus_groups[&"active"] = group
	_focus_index = 0
	if not group.is_empty() and group[0] is Control:
		(group[0] as Control).call_deferred("grab_focus")


func _move_focus(direction: int) -> void:
	var group_variant: Variant = _focus_groups.get(&"active", [])
	if not group_variant is Array:
		return
	var group := group_variant as Array
	if group.is_empty():
		return
	var owner := get_viewport().gui_get_focus_owner()
	var owner_index := group.find(owner)
	if owner_index >= 0:
		_focus_index = owner_index
	_focus_index = posmod(_focus_index + direction, group.size())
	var target_variant: Variant = group[_focus_index]
	if target_variant is Control:
		(target_variant as Control).grab_focus()


func _visible_buttons(source: Variant) -> Array:
	var result: Array = []
	if source is Array:
		for value: Variant in source:
			if value is Button and (value as Button).visible and not (value as Button).disabled:
				result.append(value)
	return result


func _on_reward_pressed(button: Button) -> void:
	audio_director.play_sfx(&"act", 1.08, -3.0)
	reward_chosen.emit(StringName(button.get_meta("upgrade_id", &"")))


func _on_route_pressed(button: Button) -> void:
	audio_director.play_sfx(&"start", 1.12, -5.0)
	route_chosen.emit(StringName(button.get_meta("destination_id", &"")))


func _t(key: StringName, fallback: String) -> String:
	var translated := tr(String(key))
	return fallback if translated == String(key) else translated


func _category_title(category: StringName) -> String:
	return {
		&"entry": _t(&"ROGUE_ROOM_ENTRY", "入潮口"),
		&"combat": _t(&"ROGUE_ROOM_COMBAT", "交锋房"),
		&"elite": _t(&"ROGUE_ROOM_ELITE", "高压房"),
		&"cache": _t(&"ROGUE_ROOM_CACHE", "藏光室"),
		&"event": _t(&"ROGUE_ROOM_EVENT", "异潮室"),
		&"forge": _t(&"ROGUE_ROOM_FORGE", "折纸坊"),
		&"shop": _t(&"ROGUE_ROOM_SHOP", "漂灯市"),
		&"rest": _t(&"ROGUE_ROOM_REST", "静水泊"),
		&"boss": _t(&"ROGUE_ROOM_BOSS", "终潮庭"),
	}.get(category, _t(&"ROGUE_ROOM_UNKNOWN", "无名房"))


func _rarity_title(rarity: int) -> String:
	return ["常见", "精巧", "稀有", "传说", "诅咒"][clampi(rarity, 0, 4)]


func _choice_kind_title(kind: StringName) -> String:
	return {&"weapon": "自动武器 · 最多携带两把", &"active": "主动道具 · 替换当前槽位"}.get(kind, "局内升级")


func _risk_title(risk: int) -> String:
	return "威胁 " + "◆".repeat(clampi(risk, 1, 5))


func _attack_demo_title(style: StringName, preview_id: StringName) -> String:
	var resolved := style
	if resolved.is_empty():
		resolved = {
			&"paper_turret": &"aimed_volley", &"brood_lantern": &"summon",
			&"bell_binder": &"tether", &"ink_warden": &"zone",
			&"prism_bulwark": &"shield", &"shear_scribe": &"cross_cut",
			&"reef_crown_battery": &"tide_gap", &"inverted_archivist": &"partitions",
			&"origami_judge": &"shrinking_frame",
		}.get(preview_id, &"radial")
	return {
		&"aimed_volley": "动态演示 · 红线锁定 → 横向躲开 → 五弹齐射",
		&"line_volley": "动态演示 · 红线锁定 → 横向躲开 → 五弹齐射",
		&"summon": "动态演示 · 外圈蓄满 → 召出两只漂兵",
		&"brood_summon": "动态演示 · 外圈蓄满 → 召出两只漂兵",
		&"tether": "动态演示 · 金线连接 → 两名敌人加速",
		&"ally_buff": "动态演示 · 金线连接 → 两名敌人加速",
		&"zone": "动态演示 · 圆圈收紧 → 原地留下减速墨区",
		&"ink_zone": "动态演示 · 圆圈收紧 → 原地留下减速墨区",
		&"shield": "动态演示 · 正面挡弹 → 返光击碎棱镜",
		&"prism_shield": "动态演示 · 正面挡弹 → 返光击碎棱镜",
		&"cross_cut": "动态演示 · 红金十字 → 四向不可反射裁切",
		&"shear_cross": "动态演示 · 红金十字 → 四向不可反射裁切",
		&"tide_gap": "动态演示 · 橙色潮环扩散，青色缺口可以躲",
		&"reef_tide_pulse": "动态演示 · 橙色潮环扩散，青色缺口可以躲",
		&"partitions": "动态演示 · 墨墙改道 → 花瓣环潮追击",
		&"ink_partitions": "动态演示 · 墨墙改道 → 花瓣环潮追击",
		&"shrinking_frame": "动态演示 · 安全框收紧 → 留在框内走位",
		&"moving_safe_frame": "动态演示 · 安全框收紧 → 留在框内走位",
	}.get(resolved, "动态演示 · 先看预警，再看弹道与安全位置")


func _region_accent(region_id: StringName) -> Color:
	match region_id:
		&"inverted_ink_city": return Color(0.51, 0.43, 0.62)
		&"nameless_sun_court": return Color(0.78, 0.56, 0.32)
		_: return FOLD
