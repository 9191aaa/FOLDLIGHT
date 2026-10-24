class_name FoldlightRoguePresentation
extends CanvasLayer

signal new_run_requested
signal continue_requested
signal prologue_requested
signal prologue_skip_requested
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
signal pause_navigation(event: InputEventKey)
signal pause_requested
signal screen_changed(kind: StringName)
signal active_relic_selected(id: StringName)

const FOLD := FoldlightRogueUITheme.FOLD
const GOLD := FoldlightRogueUITheme.GOLD
const PAPER := FoldlightRogueUITheme.PAPER
const MUTED := FoldlightRogueUITheme.MUTED
const SURFACE := FoldlightRogueUITheme.SURFACE
const SHARED_THEME = preload("res://scripts/ui/foldlight_theme.gd")
const REWARD_CARD = preload("res://scripts/roguelite/ui/reward_card.gd")
const REWARD_INPUT_GUARD = preload("res://scripts/ui/reward_input_guard.gd")
const TITLE_SCREEN = preload("res://scripts/roguelite/ui/rogue_title_screen.gd")
const QUICK_TUTORIAL_SCENE: PackedScene = preload("res://scenes/roguelite/ui/quick_tutorial_overlay.tscn")
const MECHANIC_PREVIEW_SCENE := preload("res://scripts/roguelite/ui/mechanic_preview_canvas.gd")
const ROUTE_ATLAS := preload("res://scripts/roguelite/ui/route_atlas.gd")
const ROUTE_PANEL := preload("res://scripts/roguelite/ui/route_destination_panel.gd")
const INPUT_CONTRACT := preload("res://scripts/ui/input_contract.gd")
const MOBILE_LAYOUT := preload("res://scripts/roguelite/ui/mobile_presentation_layout.gd")
const MOBILE_HUD := preload("res://scripts/roguelite/ui/mobile_combat_hud.gd")
const WEAPON_ARSENAL := preload("res://scripts/roguelite/ui/weapon_arsenal_strip.gd")
const ACTIVE_COLLECTION := preload("res://scripts/roguelite/ui/active_skill_collection.gd")
const ACTIVE_BADGE := preload("res://scripts/roguelite/ui/active_skill_badge.gd")
const EXPERIENCE_STRIP := preload("res://scripts/roguelite/ui/kill_experience_strip.gd")
const ENDLESS_BOSS_STATUS := preload("res://scripts/roguelite/ui/endless_boss_status.gd")
const REWARD_FEEDBACK := preload("res://scripts/roguelite/ui/reward_feedback_text.gd")

var _touch_layout: bool = false
var _mobile_layout := MOBILE_LAYOUT.new()
var _mobile_hud: Control
var _hud_player: FoldlightPlayer
var _desktop_hud: Control
var _settings_grid: GridContainer
var _settings_minus: Array[Button] = []
var _touch_safe_top: float = -1.0
var _touch_safe_insets: Vector4 = Vector4.ZERO
var _navigation_overlay: Control
var _active_inventory: Array[Dictionary] = []
var _active_collection: Control
var _reward_collection_button: Button
var _pause_collection_button: Button
var _collection_return_blocked: bool = false
var _collection_neutral: float = 0.0
var _collection_input_guard: Node

var screen_kind: StringName = &"title"
var _screens: Dictionary = {}
var _focus_groups: Dictionary = {}
var _focus_index: int = 0
var _focus_request_revision: int = 0
var _mechanic_remaining: float = 0.0
var _title_screen: Control
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
var _hud_arsenal: Control
var _hud_inventory: Array[Dictionary] = []
var _hud_resonance: Dictionary = {}
var _hud_active: Label
var _hud_active_bar: ProgressBar
var _hud_active_badge: Control
var _hud_status: Label
var _hud_experience: Control
var _hud_objective: Label
var _hud_objective_detail: Label
var _hud_objective_bar: ProgressBar
var _hud_help: Label
var _input_device: StringName = &"keyboard"
var _hud_context: Dictionary = {}
var _endless_boss_status: Control
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
var _pause_weapons: Array[Label] = []
var _pause_arsenal_hint: Label
var _browse_mode_enabled: bool = false
var _reward_title: Label
var _reward_eyebrow: Label
var _reward_metadata: Dictionary = {}
var _reward_hint: Label
var _reward_input_guard: Node
var _reward_buttons: Array[Button] = []
var _reward_content: Array[Dictionary] = []
var _reward_selection_locked: bool = false
var _pending_reward_id: StringName = &""
var _route_title: Label
var _route_buttons: Array[Button] = []
var _route_atlas: Control
var _route_preview_title: Label
var _route_preview_body: Label
var _route_nodes: Dictionary = {}
var _route_allowed: Array[String] = []
var _route_pending: bool = false
var _route_panel: Control
var _route_context: Dictionary = {}
var _route_progress: Label
var _route_hint: Label
var _route_input_guard: Node
var _result_title: Label
var _result_body: Label
var _result_hint: Label
var _result_input_guard: Node
var _result_action_locked: bool = true
var _leave_hint: Label
var _leave_input_guard: Node
var _leave_action_locked: bool = true
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
	_build_leave_confirmation()
	_build_settings()
	_build_mechanic_toast()
	_build_mechanic_briefing()
	_active_collection = ACTIVE_COLLECTION.new()
	_active_collection.name = "ActiveSkillCollection"
	interface.add_child(_active_collection)
	_active_collection.skill_selected.connect(_on_active_skill_selected)
	_active_collection.closed.connect(close_active_collection)
	_active_collection.hide()
	_collection_input_guard = REWARD_INPUT_GUARD.new()
	_collection_input_guard.name = "SkillCollectionInputGuard"
	add_child(_collection_input_guard)
	_collection_input_guard.state_changed.connect(_on_collection_input_state_changed)
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		touch.touch_mode_changed.connect(set_touch_layout)
		touch.layout_changed.connect(_on_touch_layout_changed)
		set_touch_layout(bool(touch.is_touch_mode()))
	show_title({})


func set_touch_layout(enabled: bool) -> void:
	if _touch_layout == enabled:
		return
	_touch_layout = enabled
	_mobile_layout.apply(self, enabled)
	_desktop_hud.visible = not enabled
	_mobile_hud.visible = enabled
	_mobile_hud.set_tutorial_mode(_quick_tutorial.visible)
	_title_screen.set_touch_layout(enabled)
	_quick_tutorial.set_touch_layout(enabled)
	_route_atlas.set_touch_layout(enabled)
	_route_panel.set_touch_layout(enabled)
	for card in _reward_buttons:
		card.set_touch_layout(enabled)
	if is_instance_valid(_navigation_overlay):
		_navigation_overlay.set_touch_layout(enabled, MOBILE_LAYOUT.safe_top(self))
	_refresh_input_hint()
	_touch_safe_top = MOBILE_LAYOUT.safe_top(self) if enabled else -1.0
	_touch_safe_insets = MOBILE_LAYOUT.safe_insets(self) if enabled else Vector4.ZERO
	if is_active_collection_open():
		_active_collection.present(_active_inventory, _touch_layout, MOBILE_LAYOUT.safe_insets(self), screen_kind)
	_refresh_endless_boss_status()


func _on_touch_layout_changed() -> void:
	if _touch_layout and (not is_equal_approx(_touch_safe_top, MOBILE_LAYOUT.safe_top(self)) or not _touch_safe_insets.is_equal_approx(MOBILE_LAYOUT.safe_insets(self))):
		_touch_safe_top = MOBILE_LAYOUT.safe_top(self)
		_touch_safe_insets = MOBILE_LAYOUT.safe_insets(self)
		_mobile_layout.apply(self, true)
		if is_instance_valid(_navigation_overlay):
			_navigation_overlay.set_touch_layout(true, _touch_safe_top)
		if is_active_collection_open():
			_active_collection.present(_active_inventory, true, _touch_safe_insets, screen_kind)
	_refresh_endless_boss_status()


func _refresh_endless_boss_status() -> void:
	if not is_instance_valid(_endless_boss_status): return
	_endless_boss_status.configure(_hud_context.get("boss_director", {}), _hud_context.get("bosses", []), _touch_layout)
	var touch := get_node_or_null("/root/TouchControls")
	_endless_boss_status.layout_in_viewport(interface.get_viewport_rect().size, touch.get_layout_snapshot() if touch != null else {})
	if is_instance_valid(_navigation_overlay):
		_navigation_overlay.set_bottom_reserved_rect(_endless_boss_status.get_global_rect() if _endless_boss_status.visible else Rect2())


## Modes may attach read-only navigation without depending on private UI nodes.
## The HUD owns its lifetime; all existing modal screens hide it immediately.
func attach_navigation_overlay(overlay: Control) -> void:
	if not is_instance_valid(overlay) or overlay == _navigation_overlay:
		return
	if is_instance_valid(_navigation_overlay):
		_navigation_overlay.hide()
		_navigation_overlay.queue_free()
	_navigation_overlay = overlay
	(_screens[&"hud"] as Control).add_child(overlay)
	overlay.set_touch_layout(_touch_layout, MOBILE_LAYOUT.safe_top(self))
	overlay.set_hud_visible(screen_kind == &"hud")


func get_endless_navigation_snapshot() -> Dictionary:
	return _navigation_overlay.get_navigation_snapshot() if is_instance_valid(_navigation_overlay) else {}


func get_touch_debug_buttons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_touch_buttons(interface, result)
	return result


func _collect_touch_buttons(node: Node, result: Array[Dictionary]) -> void:
	if node is Button and node.is_visible_in_tree() and not node.disabled:
		var rect: Rect2 = node.get_global_rect()
		result.append({"text": node.text, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y})
	for child in node.get_children(): _collect_touch_buttons(child, result)


func _sync_touch_context() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		var race_bridge := get_node_or_null("/root/WebRaceBridge")
		var room_overlay: bool = race_bridge != null and race_bridge.is_lobby_open()
		touch.set_context(self, _hud_player, visible and screen_kind == &"hud" and not room_overlay)


func _exit_tree() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		touch.clear_context(self)


func _process(delta: float) -> void:
	if _collection_return_blocked:
		var touch := get_node_or_null("/root/TouchControls")
		var held: bool = Input.is_anything_pressed() or (touch != null and touch.has_held_touches())
		for action: StringName in REWARD_INPUT_GUARD.AXIS_ACTIONS:
			if Input.is_action_pressed(action): held = true
		_collection_neutral = 0.0 if held else _collection_neutral + minf(delta, 0.1)
		if _collection_neutral >= 0.12:
			_collection_return_blocked = false
			_on_reward_input_state_changed()
	if _mechanic_remaining > 0.0:
		_mechanic_remaining = maxf(0.0, _mechanic_remaining - delta)
		if _mechanic_remaining <= 0.0:
			_mechanic_panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	# Kept as a callable input surface for diagnostics; real menus consume in
	# _input before native Control navigation can steal settings left/right.
	_handle_menu_input(event)


func _input(event: InputEvent) -> void:
	if not is_inside_tree(): return
	var race_bridge := get_node_or_null("/root/WebRaceBridge")
	if race_bridge != null and race_bridge.is_lobby_open(): return
	# Raw touches allow a second finger to pause while the first holds the stick.
	# It remains observable by the entry guards; no synthetic combat key is sent.
	if _touch_layout and screen_kind == &"hud" and event is InputEventScreenTouch and event.pressed and not event.canceled and _mobile_hud.pause_button.is_visible_in_tree():
		if _mobile_hud.pause_button.get_global_rect().has_point(event.position):
			pause_requested.emit()
			return
	var device := INPUT_CONTRACT.device_for_event(event, _input_device)
	if device != _input_device:
		_input_device = device
		_refresh_input_hint()
	if screen_kind != &"hud":
		_handle_menu_input(event)


func _handle_menu_input(event: InputEvent) -> void:
	if not is_inside_tree() or not visible or not event.is_pressed() or event.is_echo():
		return
	var race_bridge := get_node_or_null("/root/WebRaceBridge")
	if race_bridge != null and race_bridge.is_lobby_open(): return
	var viewport := get_viewport()
	if not is_instance_valid(viewport) or not viewport.is_inside_tree():
		return
	if is_active_collection_open() and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_game")):
		viewport.set_input_as_handled()
		close_active_collection()
		return
	if is_active_collection_open() and not _collection_input_guard.can_select():
		viewport.set_input_as_handled()
		return
	if screen_kind == &"reward" and not _reward_input_guard.can_select():
		return
	if screen_kind == &"reward" and _collection_return_blocked:
		viewport.set_input_as_handled()
		return
	if screen_kind == &"result" and not event.is_action_pressed(&"mute_audio") and not is_result_ready():
		viewport.set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_game"):
		if screen_kind == &"leave_confirmation":
			viewport.set_input_as_handled()
			_on_leave_action(false)
		elif screen_kind == &"settings":
			viewport.set_input_as_handled()
			settings_back_requested.emit(_settings_return)
		elif screen_kind == &"pause":
			viewport.set_input_as_handled()
			resume_requested.emit()
		elif screen_kind == &"result":
			viewport.set_input_as_handled()
			_on_result_action(&"title")
		return
	if screen_kind == &"leave_confirmation" and (_leave_action_locked or not _leave_input_guard.can_select()) and not event.is_action_pressed(&"mute_audio"):
		viewport.set_input_as_handled()
		return
	if screen_kind == &"hud" or event.is_action_pressed(&"pause_game") or event.is_action_pressed(&"mute_audio"):
		return
	if screen_kind == &"settings" and (event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right")):
		var owner := viewport.gui_get_focus_owner()
		if owner is Button and owner.has_meta("setting_key"):
			viewport.set_input_as_handled()
			setting_adjust_requested.emit(StringName(owner.get_meta("setting_key")), -1 if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") else 1)
		return
	var direction := INPUT_CONTRACT.navigation_step(event, screen_kind != &"settings")
	if direction != 0:
		if screen_kind == &"pause" and event is InputEventKey and not is_active_collection_open():
			pause_navigation.emit(event)
		viewport.set_input_as_handled()
		_move_focus(direction)
	elif event.is_action_pressed(&"fold") or event.is_action_pressed(&"ui_accept"):
		var owner := viewport.gui_get_focus_owner()
		if owner is BaseButton and not owner.disabled and owner.is_visible_in_tree() and (_focus_groups.get(&"active", []) as Array).has(owner):
			# Pressed listeners may synchronously replace and detach this scene.
			viewport.set_input_as_handled()
			(owner as BaseButton).pressed.emit()


func show_title(profile_snapshot: Dictionary) -> void:
	_show_only(&"title")
	visual_canvas.configure(&"title", FOLD)
	_title_screen.present(profile_snapshot)
	_set_focus_group(_visible_buttons(_focus_groups.get(&"title", [])))


func show_hud() -> void:
	_show_only(&"hud")
	visual_canvas.configure(&"hud", FOLD)
	_set_focus_group([])


func update_hud(player: FoldlightPlayer, snapshot: Dictionary, room_node: Dictionary, region_title: String, wave_text: String = "", boss_snapshot: Dictionary = {}, context: Dictionary = {}) -> void:
	if player == null:
		return
	_hud_player = player
	if player.has_method("get_active_inventory_snapshot"):
		set_active_inventory(player.get_active_inventory_snapshot())
	_sync_touch_context()
	_hud_region.text = "%s  /  %s" % [region_title, _category_title(StringName(room_node.get("category", &"combat")))]
	_hud_room.text = _t(&"ROGUE_HUD_ROOM", "房间 %d  ·  微光 %d") % [int(snapshot.get("room_count", 0)) + 1, int(snapshot.get("glimmer", 0))]
	_hud_context = context
	_hud_experience.configure(context.get("experience", {}))
	if is_instance_valid(_navigation_overlay):
		_navigation_overlay.set_objective_feedback(context.get("objective_feedback", {}))
	_on_touch_layout_changed()
	if context.has("region_text"):
		_hud_region.text = str(context["region_text"])
	if context.has("voyage_text"):
		_hud_room.text = str(context["voyage_text"])
	_hud_objective.visible = context.has("objective_title") and not bool(context.get("endless_navigation", false))
	_hud_objective_detail.visible = _hud_objective.visible
	_hud_objective_bar.visible = _hud_objective.visible
	if context.has("objective_title"):
		_hud_objective.text = str(context["objective_title"])
		_hud_objective_detail.text = str(context.get("objective_detail", ""))
		_hud_objective_bar.value = clampf(float(context.get("objective_progress", 0.0)), 0.0, 1.0) * 100.0
	_refresh_input_hint()
	_hud_health.text = "灯芯  %d / %d" % [player.health, player.max_health]
	_hud_health_bar.max_value = maxi(1, player.max_health)
	_hud_health_bar.value = player.health
	var health_accent := FoldlightRogueUITheme.DANGER if player.health <= ceili(float(player.max_health) * 0.34) else GOLD
	_hud_health.add_theme_color_override("font_color", health_accent)
	_hud_health_bar.add_theme_stylebox_override("fill", FoldlightRogueUITheme.bar_style(health_accent))
	var cooldown := player.get_fold_cooldown_remaining()
	var fold_ready := cooldown <= 0.01
	_hud_fold.text = "折域  ·  收纳 %d / %d" % [player.captured, player.get_capture_capacity()] if fold_ready else "折域回折  %.1fs  ·  %d / %d" % [cooldown, player.captured, player.get_capture_capacity()]
	_hud_focus_bar.value = player.focus * 100.0
	_hud_charge_bar.value = player.get_charge_ratio() * 100.0 if player.folding else 0.0
	_hud_charge_row.visible = player.folding
	var dash_ratio := player.get_dash_cooldown_ratio()
	var dash_ready := player.dash_component.is_ready()
	_hud_dash.text = "就绪" if dash_ready else "回充  %.1fs" % player.dash_component.cooldown_remaining
	_hud_dash_bar.value = 100.0 if dash_ready else (1.0 - dash_ratio) * 100.0
	_hud_dash.add_theme_color_override("font_color", FOLD if dash_ready else MUTED)
	_hud_inventory = player.weapon_mount.get_inventory_snapshot()
	_hud_resonance = player.weapon_mount.get_resonance_snapshot()
	_hud_weapon.text = "自动武器 · %d 把同行" % _hud_inventory.size()
	_hud_arsenal.configure(_hud_inventory, _hud_resonance)
	var resonance_active := bool(_hud_resonance.get("active", false))
	_hud_weapon_bar.max_value = maxf(0.01, float(_hud_resonance.get("duration", 3.0))) if resonance_active else maxi(1, int(_hud_resonance.get("required", 8)))
	_hud_weapon_bar.value = float(_hud_resonance.get("remaining", 0.0)) if resonance_active else float(_hud_resonance.get("charge", 0))
	_hud_weapon_bar.add_theme_stylebox_override("fill", SHARED_THEME.bar_style(GOLD if resonance_active else FOLD))
	var active_title := _t(&"ROGUE_HUD_EMPTY_ACTIVE", "未装备主动技能")
	if player.active_item_slot.definition != null:
		active_title = player.active_item_slot.definition.title
		_hud_active_badge.configure(player.active_item_slot.definition.content_id, player.active_item_slot.definition.accent)
	else:
		_hud_active_badge.configure(&"", MUTED)
	var active_ratio := player.get_active_item_cooldown_ratio()
	var active_ready := active_ratio <= 0.01 and player.active_item_slot.definition != null
	if player.active_item_slot.definition == null:
		_hud_active.text = "尚未获得"
		_hud_active_bar.value = 0.0
		_hud_active.add_theme_color_override("font_color", MUTED)
	elif active_ready:
		_hud_active.text = "%s · 就绪" % active_title
		_hud_active_bar.value = 100.0
		_hud_active.add_theme_color_override("font_color", GOLD)
	else:
		_hud_active.text = "%s · %.1fs" % [active_title, player.active_item_slot.cooldown_remaining]
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
		_boss_label.text = "%s  ·  已澄清" % str(boss_snapshot.get("title", "终潮")) if bool(boss_snapshot.get("defeated", false)) else "%s  ·  阶段 %d" % [str(boss_snapshot.get("title", "终潮")), int(boss_snapshot.get("phase", 1))]
		var mirror: Dictionary = boss_snapshot.get("mirror", {})
		if float(mirror.get("release_remaining", 0.0)) > 0.0:
			_boss_label.text = "%s · 复射%d发 · %.1fs" % [str(boss_snapshot.get("title", "复影")), int(mirror.get("release_count", 0)), float(mirror.release_remaining)]
		elif int(mirror.get("return_queue_count", 0)) > 0:
			_boss_label.text = "%s · 复射剩余%d发" % [str(boss_snapshot.get("title", "复影")), int(mirror.return_queue_count)]
	if _touch_layout:
		_mobile_hud.update_from(self)
		_mobile_hud.set_tutorial_mode(_quick_tutorial.visible)


func show_prologue_step(step_number: int, _total_steps: int, _title: String, _body: String) -> void:
	show_hud()
	_prologue_banner.hide()
	if step_number <= 1:
		_quick_tutorial.begin(not Input.get_connected_joypads().is_empty())
	else:
		_quick_tutorial.show_step(step_number - 1)
	if _touch_layout: _mobile_hud.set_tutorial_mode(true)


func hide_prologue_step() -> void:
	_prologue_banner.hide()
	_quick_tutorial.dismiss()


func show_reward(choices: Array[Dictionary], room_title: String, metadata: Dictionary = {}) -> void:
	_cancel_reward_motion()
	_reward_metadata = metadata.duplicate(true)
	_show_only(&"reward")
	_reward_selection_locked = false
	_pending_reward_id = &""
	visual_canvas.configure(&"reward", FOLD)
	_reward_title.text = _t(&"ROGUE_REWARD_TITLE", "%s · 选择一项奖励") % room_title
	_reward_eyebrow.text = "航行补给 · 本局生效"
	match StringName(metadata.get("source", &"")):
		&"mission":
			_reward_eyebrow.text = "任务完成 · 本局补给"
			_reward_title.text = "%s完成 · 领取任务补给" % room_title
		&"kill_level":
			_reward_eyebrow.text = "击破成长 · 本局生效"
			_reward_title.text = "击破升级 · Lv.%d · 选择一项强化" % maxi(1, int(metadata.get("level", 1)))
		&"boss":
			_reward_eyebrow.text = "首领已击破 · 三选一战利品"
			_reward_title.text = "%s · 领取首领战利品" % room_title
	for index in _reward_buttons.size():
		var button := _reward_buttons[index]
		if index >= choices.size():
			button.hide()
			continue
		var choice := choices[index].duplicate(true)
		var choice_kind := StringName(choice.get("choice_kind", &"upgrade"))
		var rarity_text := str(choice.get("display_rarity", _choice_kind_title(choice_kind) if choice_kind != &"upgrade" else _rarity_title(int(choice.get("rarity", 0)))))
		if choice_kind == &"upgrade" and bool(choice.get("offensive", false)):
			rarity_text += "  ·  火力强化"
		choice["display_rarity"] = rarity_text
		button.show()
		button.configure(choice, index)
		if choice.has("display_level"):
			button.level_label.text = str(choice["display_level"])
		button.set_selection_available(false)
		button.reveal(float(index) * 0.085)
	_set_focus_group([])
	_reward_input_guard.begin(_screens[&"reward"])
	_reward_collection_button.visible = not _active_inventory.is_empty()


func show_route(region_snapshot: Dictionary, current_id: StringName, exits: Array[String]) -> void:
	_show_only(&"route")
	_route_pending = false
	_route_allowed = exits.duplicate()
	_route_context = (region_snapshot.get("context", {}) as Dictionary).duplicate(true)
	var region_accent := _region_accent(StringName(region_snapshot.get("id", &"")))
	visual_canvas.configure(&"route", region_accent)
	_route_atlas.configure(region_snapshot, current_id, exits)
	_route_title.text = str(region_snapshot.get("title", "无名海域"))
	var journey: Dictionary = _route_atlas.get_journey_snapshot()
	_route_progress.text = "海域 %d / %d   ·   第 %d / %d 折点   ·   距终潮 %d 航段" % [int(region_snapshot.get("index", 0)) + 1, int(_route_context.get("region_count", 3)), int(journey["current_step"]), int(journey["total_steps"]), int(journey["remaining_steps"])]
	_route_nodes.clear()
	for node_variant: Variant in region_snapshot.get("nodes", []):
		if node_variant is Dictionary:
			_route_nodes[String((node_variant as Dictionary).get("id", ""))] = node_variant
	for index in _route_buttons.size():
		var button := _route_buttons[index]
		if index >= exits.size():
			button.hide()
			continue
		var destination_id := exits[index]
		var node: Dictionary = _route_nodes.get(destination_id, {})
		button.show()
		button.disabled = true
		button.set_meta("destination_id", StringName(destination_id))
		var preview: Dictionary = _route_atlas.get_node_preview(StringName(destination_id))
		button.text = "前往%s  →\n%s · %s" % [_category_title(StringName(node.get("category", &"combat"))), _risk_title(int(node.get("risk", 1))), str(preview.get("pressure", "敌潮"))]
	_set_focus_group([])
	_preview_route_node(StringName(exits[0]) if not exits.is_empty() else current_id)
	_route_input_guard.begin(_screens[&"route"])


func show_result(result: Dictionary, prologue: bool = false) -> void:
	_result_input_guard.cancel()
	_show_only(&"result")
	_result_action_locked = false
	visual_canvas.configure(&"prologue_result" if prologue else &"result", GOLD if bool(result.get("won", false)) else SHARED_THEME.DANGER)
	if prologue:
		_result_title.text = "准备好，驶入纸海"
		_result_body.text = "操作教学已完成。\n收纳来袭弹幕，松开折翼，让光返航。"
	else:
		var won := bool(result.get("won", false))
		_result_title.text = _t(&"ROGUE_RESULT_WIN", "光已返航") if won else _t(&"ROGUE_RESULT_LOSE", "这盏灯沉入了纸海")
		var elapsed := int(float(result.get("time", 0.0)))
		_result_body.text = _t(&"ROGUE_RESULT_BODY", "抵达区域  %d / 3\n澄清房间  %d\n航行时间  %02d:%02d\n收集微光  %d") % [int(result.get("region", 1)), int(result.get("rooms", 0)), elapsed / 60, elapsed % 60, int(result.get("glimmer", 0))]
	if result.has("title"):
		_result_title.text = str(result["title"])
	if result.has("body"):
		_result_body.text = str(result["body"])
	if result.has("accent"):
		visual_canvas.configure(&"result", Color(result["accent"]))
	var actions: Array = _focus_groups[&"result"]
	(actions[0] as Button).text = str(result.get("retry_label", "再次迷航"))
	(actions[0] as Button).visible = bool(result.get("allow_retry", true))
	(actions[1] as Button).visible = bool(result.get("allow_title", true))
	for button: Button in actions:
		button.disabled = true
	_set_focus_group([])
	_result_hint.visible = (actions[0] as Button).visible or (actions[1] as Button).visible
	if _result_hint.visible:
		_result_input_guard.begin(_screens[&"result"])


func is_result_ready() -> bool:
	return screen_kind == &"result" and not _result_action_locked and _result_input_guard.can_select()


func _on_result_input_state_changed() -> void:
	if screen_kind != &"result" or _result_action_locked:
		return
	var ready: bool = _result_input_guard.can_select()
	for button: Button in _focus_groups[&"result"]:
		button.disabled = not ready
	_result_hint.text = ("轻触选择下一段航程" if _touch_layout else INPUT_CONTRACT.menu_hint(_input_device == &"gamepad")) if ready else "先看一眼航行记录 · 松开操作后再选择"
	if ready:
		_set_focus_group(_visible_buttons(_focus_groups[&"result"]))


func _on_result_action(action: StringName) -> void:
	if not is_inside_tree() or not is_result_ready():
		return
	var actions: Array = _focus_groups[&"result"]
	var button: Button = actions[0] if action == &"retry" else actions[1]
	if button.disabled or not button.is_visible_in_tree():
		return
	_result_action_locked = true
	_result_input_guard.cancel()
	for entry: Button in actions:
		entry.disabled = true
	_set_focus_group([])
	# Listeners may detach this scene or open another result synchronously.
	if action == &"retry":
		retry_requested.emit()
	else:
		title_requested.emit()


func show_notice(title: String, body: String, seconds: float = 2.8) -> void:
	_mechanic_title.text = title
	_mechanic_body.text = body
	_mechanic_remaining = maxf(0.0, seconds)
	_mechanic_panel.visible = screen_kind == &"hud" and _mechanic_remaining > 0.0


func reset_feedback() -> void:
	show_notice("", "", 0.0)
	visual_canvas.clear_damage_flash()


func cancel_reward_selection() -> void:
	if is_instance_valid(_active_collection): _active_collection.hide()
	_collection_return_blocked = false
	_cancel_reward_motion()
	_set_focus_group([])


func _refresh_input_hint() -> void:
	if _title_screen != null:
		_title_screen.set_input_device(_input_device == &"gamepad")
	if _hud_help == null:
		return
	_hud_help.text = INPUT_CONTRACT.combat_hint(_input_device == &"gamepad")
	if bool(_hud_context.get("race", false)):
		_hud_help.text += "   ·   好友竞赛不可手动暂停"
	else:
		_hud_help.text += "   Start 暂停" if _input_device == &"gamepad" else "   Esc 暂停   M 静音"
	if screen_kind == &"reward" and _reward_input_guard != null and _reward_input_guard.can_select() and not _reward_selection_locked:
		_reward_hint.text = _reward_choice_hint()


func _reward_choice_hint() -> String:
	var arsenal_hint := ""
	for button in _reward_buttons:
		if button.visible and StringName(button.get_meta("choice_kind", &"upgrade")) == &"weapon":
			arsenal_hint = "  ·  武器全部保留，重选升阶"
			break
	if _touch_layout:
		return _with_reward_heal_hint("轻触一张卡片，领取奖励" + arsenal_hint)
	# Rewards cannot be dismissed, so show only the shared selection/confirm
	# bindings and omit the menu's Back action.
	var hint := INPUT_CONTRACT.menu_hint(_input_device == &"gamepad")
	return _with_reward_heal_hint("%s    %s" % [hint.get_slice("    ", 0), hint.get_slice("    ", 1)] + arsenal_hint)


func _with_reward_heal_hint(text: String) -> String:
	var heal_hint := REWARD_FEEDBACK.heal_on_claim(_reward_metadata)
	return text + " · " + heal_hint if not heal_hint.is_empty() else text


func show_pause() -> void:
	_show_only(&"pause")
	visual_canvas.configure(&"pause", FOLD)
	_refresh_pause_arsenal()
	if _pause_browse_status != null:
		_pause_browse_status.visible = _browse_mode_enabled
	_set_focus_group(_visible_buttons(_focus_groups.get(&"pause", [])))


func set_active_inventory(snapshot: Array[Dictionary]) -> void:
	_active_inventory = snapshot.duplicate(true)
	if is_instance_valid(_pause_collection_button):
		var title := "未装备"
		for entry in _active_inventory:
			if bool(entry.get("equipped", false)): title = str(entry.get("title", ""))
		_pause_collection_button.text = "主动技能册 · %d 件\n当前：%s" % [_active_inventory.size(), title]
	if is_instance_valid(_reward_collection_button):
		_reward_collection_button.text = "技能册 · %d 件" % _active_inventory.size()
		_reward_collection_button.visible = not _active_inventory.is_empty()
	if is_active_collection_open():
		_active_collection.present(_active_inventory, _touch_layout, MOBILE_LAYOUT.safe_insets(self), screen_kind)
		_on_collection_input_state_changed()


func is_active_collection_open() -> bool:
	return is_instance_valid(_active_collection) and _active_collection.visible


func open_active_collection() -> bool:
	if not visible or screen_kind not in [&"pause", &"reward"] or _reward_selection_locked and screen_kind == &"reward":
		return false
	if screen_kind == &"reward" and (not _reward_input_guard.can_select() or _collection_return_blocked):
		return false
	_active_collection.present(_active_inventory, _touch_layout, MOBILE_LAYOUT.safe_insets(self), screen_kind)
	_set_focus_group([])
	_collection_input_guard.begin(_active_collection)
	if screen_kind == &"reward":
		for button in _reward_buttons: button.set_selection_available(false)
	return true


func close_active_collection() -> void:
	if not is_active_collection_open(): return
	_collection_input_guard.cancel()
	_active_collection.hide()
	_set_focus_group([])
	if screen_kind == &"reward":
		# The original reward guard and draft remain intact. Only wait for the
		# book's closing input to become neutral before restoring card focus.
		_collection_return_blocked = true
		_collection_neutral = 0.0
	else:
		_set_focus_group(_visible_buttons(_focus_groups.get(&"pause", [])))


func _on_collection_input_state_changed() -> void:
	if not is_active_collection_open(): return
	var available: bool = _collection_input_guard.can_select()
	for button in _active_collection._buttons:
		button.disabled = not available
	if available:
		_set_focus_group(_active_collection.focus_buttons)


func _on_active_skill_selected(id: StringName) -> void:
	if is_active_collection_open() and _collection_input_guard.can_select():
		active_relic_selected.emit(id)


func _refresh_pause_arsenal() -> void:
	if is_instance_valid(_hud_player):
		_hud_inventory = _hud_player.weapon_mount.get_inventory_snapshot()
	for index in _pause_weapons.size():
		var label := _pause_weapons[index]
		label.visible = index < _hud_inventory.size()
		if not label.visible:
			continue
		var entry := _hud_inventory[index]
		label.text = "%s  Lv.%d  ·  %s" % [entry.get("title", ""), int(entry.get("level", 1)), entry.get("role", "")]
		label.add_theme_color_override("font_color", SHARED_THEME.comfort_accent(Color(entry.get("accent", FOLD))).lightened(0.12))
	_pause_arsenal_hint.text = "所选武器全部同行；再次选择升阶，最高 Lv.5。\n累计返还 8 枚弹幕，全体共鸣 3 秒：伤害、攻速 +20%。"


func show_leave_confirmation() -> void:
	if screen_kind != &"pause":
		return
	_show_only(&"leave_confirmation")
	visual_canvas.configure(&"pause", GOLD)
	_leave_action_locked = false
	for button: Button in _focus_groups[&"leave_confirmation"]:
		button.disabled = true
	_set_focus_group([])
	_leave_input_guard.begin(_screens[&"leave_confirmation"])


func _on_leave_input_state_changed() -> void:
	if screen_kind != &"leave_confirmation" or _leave_action_locked:
		return
	var ready: bool = _leave_input_guard.can_select()
	for button: Button in _focus_groups[&"leave_confirmation"]:
		button.disabled = not ready
	_leave_hint.text = "默认取消 · 选择结束后才会离开本次航行" if ready else ("请松开触点，稍后再作选择" if _touch_layout else "请松开按键，再作选择 · Esc / B / Start 可取消")
	if ready:
		_set_focus_group(_visible_buttons(_focus_groups[&"leave_confirmation"]))


func _on_leave_action(confirmed: bool) -> void:
	if not is_inside_tree() or not visible or screen_kind != &"leave_confirmation" or _leave_action_locked:
		return
	if confirmed and not _leave_input_guard.can_select():
		return
	_leave_action_locked = true
	_leave_input_guard.cancel()
	_set_focus_group([])
	if not confirmed:
		show_pause()
		return
	for button: Button in _focus_groups[&"leave_confirmation"]:
		button.disabled = true
	# Keep the confirmation screen active until the owner accepts this action.
	abandon_requested.emit()


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
	var preview_kind := StringName(snapshot.get("preview_kind", &"boss" if FoldlightRogueContentCatalog.boss_by_id(preview_id) != null else &"enemy"))
	_mechanic_intro_accent.color = accent
	_mechanic_intro_role.text = "%s  /  %s" % [str(snapshot.get("role_title", "首领" if preview_kind == &"boss" else "机制单位")), "首领登场" if preview_kind == &"boss" else "首次遭遇"]
	_mechanic_intro_role.add_theme_color_override("font_color", accent)
	_mechanic_intro_title.text = str(snapshot.get("title", "未知首领" if preview_kind == &"boss" else "未知敌人"))
	_mechanic_intro_description.text = str(snapshot.get("description", "先看清动作，再进入交锋。"))
	_mechanic_intro_rule.text = "它怎么打\n%s" % str(snapshot.get("rule", "出手前会有清晰预警。"))
	_mechanic_intro_counter.text = "怎么躲\n%s" % str(snapshot.get("counterplay", "看到预警先换位，再抓住空档反击。"))
	_mechanic_intro_attack_caption.text = str(snapshot.get("attack_preview_text", _attack_demo_title(StringName(snapshot.get("attack_style", &"")), preview_id)))
	_mechanic_intro_preview.configure(snapshot)
	_mechanic_intro_button.text = "知道怎么躲了 · 开始交锋" if _touch_layout else "知道怎么躲了，开始交锋   [空格 / A]"
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
	_title_screen = TITLE_SCREEN.new()
	interface.add_child(_title_screen)
	_title_screen.build(_button)
	_screens[&"title"] = _title_screen
	_title_screen.action_requested.connect(_on_title_action)
	# Keep the presentation API used by the session and existing integration tests.
	_title_primary = _title_screen.primary_button
	_title_continue = _title_screen.continue_button
	_title_prologue = _title_screen.tutorial_button
	_title_stats = _title_screen.record_label
	_title_guide = _title_screen.guide_label
	_focus_groups[&"title"] = _title_screen.focus_buttons


func _on_title_action(action: StringName) -> void:
	match action:
		&"new_run": new_run_requested.emit()
		&"continue": continue_requested.emit()
		&"prologue": prologue_requested.emit()
		&"endless": endless_requested.emit()
		&"settings": settings_requested.emit()
		&"quit": quit_requested.emit()


func _build_hud() -> void:
	var screen := _new_screen(&"hud")
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := _full_margin(screen, 42, 30, 42, 28)
	_desktop_hud = margin
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
	voyage_panel.custom_minimum_size = Vector2(340, 94)
	voyage_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(FOLD.r, FOLD.g, FOLD.b, 0.48)))
	top.add_child(voyage_panel)
	var voyage_stack := VBoxContainer.new()
	voyage_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voyage_stack.add_theme_constant_override("separation", 7)
	voyage_panel.add_child(voyage_stack)
	_hud_region = _label("", 21, PAPER)
	voyage_stack.add_child(_hud_region)
	_hud_room = _label("", 18, MUTED)
	voyage_stack.add_child(_hud_room)

	var health_panel := PanelContainer.new()
	health_panel.name = "HealthCard"
	health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_panel.custom_minimum_size = Vector2(284, 94)
	health_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(GOLD.r, GOLD.g, GOLD.b, 0.68)))
	top.add_child(health_panel)
	var health_stack := VBoxContainer.new()
	health_stack.add_theme_constant_override("separation", 7)
	health_panel.add_child(health_stack)
	_hud_health = _label("灯芯  4 / 4", 23, GOLD)
	health_stack.add_child(_hud_health)
	_hud_health_bar = _hud_progress_bar("HealthBar", GOLD)
	_hud_health_bar.custom_minimum_size.y = 8
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
	_hud_objective = _label("", 20, GOLD)
	_hud_objective_detail = _label("", 16, MUTED)
	_hud_objective_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_objective_detail.custom_minimum_size.x = 450
	_hud_objective_bar = _hud_progress_bar("ObjectiveProgress", GOLD)
	boss_stack.add_child(_hud_objective)
	boss_stack.add_child(_hud_objective_detail)
	boss_stack.add_child(_hud_objective_bar)
	_hud_objective.hide()
	_hud_objective_detail.hide()
	_hud_objective_bar.hide()
	_hud_experience = EXPERIENCE_STRIP.new()
	_hud_experience.name = "KillExperience"
	_hud_experience.custom_minimum_size = Vector2(520, 74)
	_hud_experience.hide()
	boss_stack.add_child(_hud_experience)

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
	fold_core.custom_minimum_size = Vector2(420, 106)
	var core_style := _hud_surface_style(Color(FOLD, 0.65))
	core_style.border_width_left = 3
	core_style.content_margin_left = 0.0
	core_style.content_margin_right = 0.0
	core_style.content_margin_top = 0.0
	core_style.content_margin_bottom = 0.0
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
	fold_stack.add_child(_label("折翼    SPACE / E / A", 15, MUTED))
	_hud_fold = _label("", 21, PAPER)
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

	var dash_card := _hud_action_card("冲刺", "SHIFT / B", FOLD, 230.0)
	action_band.add_child(dash_card["panel"])
	_hud_dash = dash_card["state"] as Label
	_hud_dash_bar = dash_card["bar"] as ProgressBar

	var active_card := _hud_action_card("主动技能", "Q / X", GOLD, 280.0)
	action_band.add_child(active_card["panel"])
	_hud_active = active_card["state"] as Label
	_hud_active_bar = active_card["bar"] as ProgressBar
	var active_stack := _hud_active.get_parent()
	var state_index := _hud_active.get_index()
	active_stack.remove_child(_hud_active)
	var active_row := HBoxContainer.new()
	active_row.add_theme_constant_override("separation", 8)
	active_stack.add_child(active_row)
	active_stack.move_child(active_row, state_index)
	_hud_active_badge = ACTIVE_BADGE.new()
	active_row.add_child(_hud_active_badge)
	_hud_active.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_row.add_child(_hud_active)

	var weapon_panel := PanelContainer.new()
	weapon_panel.name = "WeaponArsenalCard"
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_panel.custom_minimum_size.x = 550
	weapon_panel.add_theme_stylebox_override("panel", _hud_surface_style(Color(FOLD, 0.62)))
	action_band.add_child(weapon_panel)
	var weapon_stack := VBoxContainer.new()
	weapon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_stack.add_theme_constant_override("separation", 3)
	weapon_panel.add_child(weapon_stack)
	_hud_weapon = _label("自动武器", 16, MUTED)
	weapon_stack.add_child(_hud_weapon)
	_hud_arsenal = WEAPON_ARSENAL.new()
	_hud_arsenal.name = "WeaponArsenal"
	_hud_arsenal.custom_minimum_size = Vector2(510, 90)
	weapon_stack.add_child(_hud_arsenal)
	_hud_weapon_bar = _hud_progress_bar("ResonanceProgress", FOLD)
	_hud_weapon_bar.custom_minimum_size.y = 4
	weapon_stack.add_child(_hud_weapon_bar)
	_hud_help = _label("", 15, MUTED)
	_hud_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_hud_help)
	_refresh_input_hint()
	_mobile_hud = MOBILE_HUD.new()
	_mobile_hud.name = "MobileCombatHUD"
	screen.add_child(_mobile_hud)
	_mobile_hud.pause_requested.connect(func() -> void: pause_requested.emit())
	_mobile_hud.hide()
	_endless_boss_status = ENDLESS_BOSS_STATUS.new()
	_endless_boss_status.name = "EndlessBossStatus"
	screen.add_child(_endless_boss_status)
	_endless_boss_status.hide()

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
	panel.custom_minimum_size = Vector2(width, 106)
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
	bar.custom_minimum_size.y = 6
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
	bar.add_theme_stylebox_override("background", SHARED_THEME.bar_style(Color(SHARED_THEME.INK, 0.88)))
	bar.add_theme_stylebox_override("fill", SHARED_THEME.bar_style(accent))
	return bar


func _hud_surface_style(accent: Color) -> StyleBoxFlat:
	var style := SHARED_THEME.panel_style()
	style.bg_color = Color(SHARED_THEME.INK, 0.88)
	style.border_color = Color(accent, 0.28)
	style.border_width_bottom = 2
	style.shadow_size = 0
	style.content_margin_left = 18.0
	style.content_margin_top = 12.0
	style.content_margin_right = 18.0
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
	_reward_eyebrow = _label("航行补给 · 本局生效", 20, FOLD)
	_reward_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_reward_eyebrow)
	_reward_title = _label("", 38, PAPER)
	_reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_reward_title)
	var choices := HBoxContainer.new()
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 30)
	stack.add_child(choices)
	for index in 3:
		var button := REWARD_CARD.new()
		button.name = "RewardCard%d" % (index + 1)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		choices.add_child(button)
		button.pressed.connect(_on_reward_pressed.bind(button))
		button.selection_confirmed.connect(_on_reward_confirmed)
		button.focus_entered.connect(_on_reward_focused.bind(button))
		_reward_buttons.append(button)
		_reward_content.append({"title": button.title_label, "description": button.description_label, "rarity": button.rarity_label, "level": button.level_label})
	var reward_footer := HBoxContainer.new()
	reward_footer.add_theme_constant_override("separation", 24)
	stack.add_child(reward_footer)
	_reward_hint = _label("", 18, MUTED)
	_reward_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_footer.add_child(_reward_hint)
	_reward_collection_button = _button("技能册", 64)
	_reward_collection_button.custom_minimum_size.x = 280
	_reward_collection_button.pressed.connect(open_active_collection)
	reward_footer.add_child(_reward_collection_button)
	_reward_input_guard = REWARD_INPUT_GUARD.new()
	_reward_input_guard.name = "RewardInputGuard"
	add_child(_reward_input_guard)
	_reward_input_guard.state_changed.connect(_on_reward_input_state_changed)


func _build_route() -> void:
	var screen := _new_screen(&"route")
	var margin := _full_margin(screen, 48, 34, 48, 30)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("纸海航图  /  下一段航程", 17, FOLD))
	_route_title = _label("", 36, PAPER)
	heading.add_child(_route_title)
	_route_progress = _label("", 18, MUTED)
	heading.add_child(_route_progress)
	_route_atlas = ROUTE_ATLAS.new()
	_route_atlas.name = "RouteAtlas"
	_route_atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_route_atlas.custom_minimum_size.y = 460
	_route_atlas.node_selected.connect(_on_atlas_node_selected)
	for control_name in ["−", "+", "前方航路", "航图全览"]:
		var action := _button(control_name, 52)
		action.custom_minimum_size.x = 56 if control_name in ["−", "+"] else 152
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action.focus_mode = Control.FOCUS_NONE
		action.theme_type_variation = &"QuietButton"
		if control_name == "−":
			action.pressed.connect(func() -> void: _route_atlas.zoom_by(1.0 / 1.18))
		elif control_name == "+":
			action.pressed.connect(func() -> void: _route_atlas.zoom_by(1.18))
		elif control_name == "前方航路":
			action.pressed.connect(func() -> void: _route_atlas.focus_ahead())
		else:
			action.pressed.connect(func() -> void: _route_atlas.recenter())
		header.add_child(action)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 28)
	stack.add_child(content)
	var chart_column := VBoxContainer.new()
	chart_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_column.add_theme_constant_override("separation", 10)
	content.add_child(chart_column)
	chart_column.add_child(_route_atlas)
	chart_column.add_child(_label("拖拽阅图  ·  滚轮缩放  ·  点选折岛或下方航迹，仅查看目的地", 16, MUTED))
	var note := PanelContainer.new()
	note.custom_minimum_size.x = 438
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(SURFACE, 0.76)
	paper.border_color = Color(FOLD, 0.30)
	paper.border_width_left = 2
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 22
	paper.content_margin_bottom = 22
	note.add_theme_stylebox_override("panel", paper)
	content.add_child(note)
	var note_stack := VBoxContainer.new()
	note_stack.add_theme_constant_override("separation", 12)
	note.add_child(note_stack)
	note_stack.add_child(_label("航路手记", 17, FOLD))
	_route_panel = ROUTE_PANEL.new()
	note_stack.add_child(_route_panel)
	_route_preview_title = _route_panel.title_label
	_route_preview_body = _route_panel.body_label
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	note_stack.add_child(spacer)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	note_stack.add_child(choices)
	for index in 3:
		var button := _button("", 76)
		button.custom_minimum_size.x = 370
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_on_route_pressed.bind(button))
		button.focus_entered.connect(func() -> void: _preview_route_node(StringName(button.get_meta("destination_id", &""))))
		choices.add_child(button)
		_route_buttons.append(button)
	_route_hint = _label("", 17, MUTED)
	_route_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_route_hint)
	_route_input_guard = REWARD_INPUT_GUARD.new()
	_route_input_guard.name = "RouteInputGuard"
	add_child(_route_input_guard)
	_route_input_guard.state_changed.connect(_on_route_input_state_changed)


func _on_route_input_state_changed() -> void:
	if screen_kind != &"route" or _route_pending:
		return
	var available: bool = _route_input_guard.can_select()
	for button in _route_buttons:
		button.disabled = not available
	_route_hint.text = ("点折岛查看 · 点出发启航" if _touch_layout else "方向键 / 摇杆选择航路   ·   空格 / A 确认出发") if available else "航图正在展开 · 松开操作后再启航"
	if available:
		# Arming may follow programmatic inspection. Keep the selected island;
		# a distant preview must not silently focus a different launch action.
		_set_focus_group([])
		var group := _visible_buttons(_route_buttons)
		_focus_groups[&"active"] = group
		for button: Button in group:
			if StringName(button.get_meta("destination_id", &"")) == _route_atlas.selected_node_id:
				_focus_current_control.call_deferred(weakref(button), _focus_request_revision)
				return
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null: owner.release_focus()


func _on_atlas_node_selected(node_id: StringName) -> void:
	if screen_kind != &"route" or _route_pending:
		return
	_preview_route_node(node_id)
	if _route_allowed.has(String(node_id)) and _route_input_guard.can_select():
		for button in _route_buttons:
			if button.visible and StringName(button.get_meta("destination_id", &"")) == node_id:
				button.grab_focus()
				return
	else:
		# Inspecting a distant island must not leave an unrelated launch focused.
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null:
			owner.release_focus()


func _preview_route_node(node_id: StringName) -> void:
	var node: Dictionary = _route_nodes.get(String(node_id), {})
	if node.is_empty():
		return
	_route_atlas.focus_destination(node_id)
	var preview: Dictionary = _route_atlas.get_node_preview(node_id)
	_route_panel.configure(preview, _route_context)


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
	retry.pressed.connect(_on_result_action.bind(&"retry"))
	action_row.add_child(retry)
	var title := _button(_t(&"ROGUE_RESULT_TITLE", "返回主菜单"), 70)
	title.custom_minimum_size.x = 280
	title.pressed.connect(_on_result_action.bind(&"title"))
	action_row.add_child(title)
	_focus_groups[&"result"] = [retry, title]
	_result_hint = _label("", 18, MUTED)
	stack.add_child(_result_hint)
	_result_input_guard = REWARD_INPUT_GUARD.new()
	_result_input_guard.name = "ResultInputGuard"
	add_child(_result_input_guard)
	_result_input_guard.state_changed.connect(_on_result_input_state_changed)


func _build_pause() -> void:
	var screen := _new_screen(&"pause")
	var margin := _full_margin(screen, 250, 190, 250, 170)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	panel.add_child(columns)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 410
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 16)
	columns.add_child(stack)
	var eyebrow := _label("航行途中", 18, FOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	var title := _label("暂停", 48, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_pause_browse_status = _label("浏览模式已开启  ·  玩家伤害无效", 20, FOLD)
	_pause_browse_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_browse_status.hide()
	stack.add_child(_pause_browse_status)
	var resume := _button("继续航行", 72)
	resume.theme_type_variation = "PrimaryButton"
	resume.pressed.connect(func() -> void: resume_requested.emit())
	stack.add_child(resume)
	var settings := _button("设置", 64)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	stack.add_child(settings)
	var abandon := _button("结束本次航行", 64)
	abandon.pressed.connect(show_leave_confirmation)
	stack.add_child(abandon)
	stack.add_child(_label("Esc / Start 继续", 17, MUTED))
	_focus_groups[&"pause"] = [resume, settings, abandon]
	var inventory := VBoxContainer.new()
	inventory.name = "PauseWeaponInventory"
	inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory.alignment = BoxContainer.ALIGNMENT_CENTER
	inventory.add_theme_constant_override("separation", 15)
	columns.add_child(inventory)
	inventory.add_child(_label("同行武器 · 同时出击", 27, PAPER))
	for index in 6:
		var label := _label("", 23, FOLD)
		label.name = "WeaponDetail%d" % index
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inventory.add_child(label)
		_pause_weapons.append(label)
	_pause_arsenal_hint = _label("", 20, MUTED)
	_pause_arsenal_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_arsenal_hint.custom_minimum_size.x = 530
	inventory.add_child(_pause_arsenal_hint)
	_pause_collection_button = _button("主动技能册", 96)
	_pause_collection_button.add_theme_font_size_override("font_size", 23)
	_pause_collection_button.pressed.connect(open_active_collection)
	inventory.add_child(_pause_collection_button)
	_focus_groups[&"pause"].append(_pause_collection_button)


func _build_leave_confirmation() -> void:
	var screen := _new_screen(&"leave_confirmation")
	var margin := _full_margin(screen, 570, 280, 570, 260)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 22)
	panel.add_child(stack)
	var title := _label("结束本次航行？", 42, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var body := _label("本次航行会结束。\n如果只是想歇一会儿，留在暂停即可。", 23, MUTED)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(body)
	var cancel := _button("取消 · 留在暂停", 72)
	cancel.theme_type_variation = "PrimaryButton"
	cancel.pressed.connect(_on_leave_action.bind(false))
	stack.add_child(cancel)
	var confirm := _button("确认结束本次航行", 64)
	confirm.pressed.connect(_on_leave_action.bind(true))
	stack.add_child(confirm)
	_leave_hint = _label("", 17, MUTED)
	_leave_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leave_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_leave_hint)
	_focus_groups[&"leave_confirmation"] = [cancel, confirm]
	_leave_input_guard = REWARD_INPUT_GUARD.new()
	_leave_input_guard.name = "LeaveInputGuard"
	add_child(_leave_input_guard)
	_leave_input_guard.state_changed.connect(_on_leave_input_state_changed)


func _build_settings() -> void:
	var screen := _new_screen(&"settings")
	var margin := _full_margin(screen, 550, 130, 550, 120)
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
	_settings_grid = GridContainer.new()
	_settings_grid.columns = 1
	_settings_grid.add_theme_constant_override("h_separation", 24)
	_settings_grid.add_theme_constant_override("v_separation", 10)
	stack.add_child(_settings_grid)
	for key in _settings_keys:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_settings_grid.add_child(row)
		var minus := _button("−", 58)
		minus.name = String(key).to_pascal_case() + "Decrease"
		minus.custom_minimum_size.x = 120
		minus.pressed.connect(func() -> void: setting_adjust_requested.emit(key, -1))
		minus.hide()
		row.add_child(minus)
		_settings_minus.append(minus)
		var button := _button(String(key), 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("setting_key", key)
		button.pressed.connect(func() -> void: setting_adjust_requested.emit(StringName(button.get_meta("setting_key")), 1))
		row.add_child(button)
		_settings_buttons.append(button)
	var back := _button("返回", 58)
	back.pressed.connect(func() -> void: settings_back_requested.emit(_settings_return))
	stack.add_child(back)
	_settings_buttons.append(back)
	stack.add_child(_label("上下选择  ·  左右调整  ·  空格确认", 17, MUTED))


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
	dim.color = Color(SHARED_THEME.INK, 0.94)
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
	rule_panel.add_theme_stylebox_override("panel", _briefing_info_style(Color(SHARED_THEME.DANGER, 0.50)))
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
	_mechanic_intro_counter = _label("", 23, FOLD)
	_mechanic_intro_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mechanic_intro_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mechanic_intro_counter.custom_minimum_size = Vector2(620, 140)
	counter_panel.add_child(_mechanic_intro_counter)
	_mechanic_intro_button = _button("知道怎么躲了，开始交锋   [空格 / A]", 72)
	_mechanic_intro_button.pressed.connect(_dismiss_mechanic_briefing)
	outer.add_child(_mechanic_intro_button)


func _briefing_info_style(border: Color) -> StyleBoxFlat:
	var style := SHARED_THEME.panel_style()
	style.bg_color = Color(SHARED_THEME.INK, 0.65)
	style.border_color = border
	style.border_width_left = 3
	style.shadow_size = 0
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
	if is_instance_valid(_active_collection): _active_collection.hide()
	if is_instance_valid(_collection_input_guard): _collection_input_guard.cancel()
	_collection_return_blocked = false
	if screen_kind == &"reward" and kind != &"reward":
		_cancel_reward_motion()
	if screen_kind == &"result" and kind != &"result":
		_result_input_guard.cancel()
		_result_action_locked = true
	if screen_kind == &"leave_confirmation" and kind != &"leave_confirmation":
		_leave_input_guard.cancel()
		_leave_action_locked = true
	screen_kind = kind
	_on_touch_layout_changed()
	_sync_touch_context()
	if is_instance_valid(_navigation_overlay):
		_navigation_overlay.set_hud_visible(kind == &"hud")
	screen_changed.emit(kind)
	for key_variant: Variant in _screens.keys():
		(_screens[key_variant] as Control).visible = StringName(key_variant) == kind
	_mechanic_panel.visible = _mechanic_remaining > 0.0 and kind == &"hud"


func _set_focus_group(group: Array) -> void:
	_focus_groups[&"active"] = group
	_focus_index = 0
	_focus_request_revision += 1
	if not group.is_empty() and group[0] is Control:
		_focus_current_control.call_deferred(weakref(group[0]), _focus_request_revision)


func _focus_current_control(reference: WeakRef, revision: int) -> void:
	# A scene change removes the old UI before its deferred calls are drained.
	# Also reject requests superseded by another screen in the same frame.
	if revision != _focus_request_revision or not is_inside_tree() or is_queued_for_deletion() or not visible:
		return
	var target := reference.get_ref() as Control
	if target == null or not target.is_inside_tree() or target.is_queued_for_deletion() or not target.is_visible_in_tree():
		return
	if target is BaseButton and target.disabled:
		return
	if (_focus_groups.get(&"active", []) as Array).has(target):
		target.grab_focus()


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
	if screen_kind != &"reward" or _reward_selection_locked or is_active_collection_open() or _collection_return_blocked or not _reward_input_guard.can_select() or button.disabled or not button.is_visible_in_tree():
		return
	if not button.confirm_selection():
		return
	_reward_selection_locked = true
	_pending_reward_id = StringName(button.get_meta("upgrade_id", &""))
	for card in _reward_buttons:
		card.lock_choice(card == button)
	_set_focus_group([])
	_reward_hint.text = "奖励已确认"
	audio_director.play_sfx(&"act", 1.08, -3.0)


func _on_reward_confirmed(upgrade_id: StringName) -> void:
	if screen_kind != &"reward" or not _reward_selection_locked or upgrade_id != _pending_reward_id:
		return
	# The listener may immediately show the next reward stage. Do not mutate
	# presentation state after this signal, which would overwrite that stage.
	reward_chosen.emit(upgrade_id)


func _cancel_reward_motion() -> void:
	_reward_selection_locked = true
	_pending_reward_id = &""
	_reward_input_guard.cancel()
	for card in _reward_buttons:
		card.cancel_motion()


func _on_reward_input_state_changed() -> void:
	if screen_kind != &"reward" or _reward_selection_locked:
		return
	var available: bool = _reward_input_guard.can_select() and not is_active_collection_open() and not _collection_return_blocked
	_reward_collection_button.disabled = not available
	for card in _reward_buttons:
		card.set_selection_available(available)
	_reward_hint.text = _reward_choice_hint() if available else _with_reward_heal_hint(_reward_input_guard.get_hint())
	if available:
		var choices := _visible_buttons(_reward_buttons)
		if _reward_collection_button.visible: choices.append(_reward_collection_button)
		_set_focus_group(choices)


func _on_reward_focused(button: Button) -> void:
	var active: Array = _focus_groups.get(&"active", [])
	var index := active.find(button)
	if index >= 0:
		_focus_index = index
	audio_director.play_sfx(&"ui", 1.12, -8.0)


func _on_route_pressed(button: Button) -> void:
	var destination_id := StringName(button.get_meta("destination_id", &""))
	if screen_kind != &"route" or _route_pending or button.disabled or not button.is_visible_in_tree() or not _route_input_guard.can_select() or not _route_allowed.has(String(destination_id)):
		return
	_route_pending = true
	_route_input_guard.cancel()
	for choice in _route_buttons:
		choice.disabled = true
	audio_director.play_sfx(&"start", 1.12, -5.0)
	route_chosen.emit(destination_id)


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
	return {&"weapon": "自动武器 · 同行与升阶", &"active": "主动技能 · 收藏并装备"}.get(kind, "局内升级")


func _risk_title(risk: int) -> String:
	return "威胁 %d" % maxi(1, risk)


func _attack_demo_title(style: StringName, preview_id: StringName) -> String:
	var resolved := style
	if resolved.is_empty():
		resolved = {
			&"paper_turret": &"aimed_volley", &"brood_lantern": &"summon",
			&"bell_binder": &"tether", &"ink_warden": &"zone",
			&"prism_bulwark": &"shield", &"shear_scribe": &"cross_cut",
			&"reef_crown_battery": &"tide_gap", &"inverted_archivist": &"partitions",
			&"origami_judge": &"shrinking_frame",
			&"tide_loom_mother": &"woven_lanes", &"torn_page_executioner": &"locked_dash", &"eclipse_twin_bells": &"paired_gaps",
		}.get(preview_id, &"radial")
	return {
		&"aimed_volley": "动态演示 · 红线锁定 → 横向躲开 → 五弹齐射",
		&"exposure_barrage": "动态演示 · 闭翼免伤 → 蓄光预警 → 开火时返光",
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
		&"woven_lanes": "动态演示 · 平行织线 → 青色空隙穿行",
		&"locked_dash": "动态演示 · 金线锁定 → 横向避让 → 冲刺收招",
		&"paired_gaps": "动态演示 · 双铃先后响起 → 分别寻找缺口",
	}.get(resolved, "动态演示 · 先看预警，再看弹道与安全位置")


func _region_accent(region_id: StringName) -> Color:
	match region_id:
		&"inverted_ink_city": return Color(0.51, 0.43, 0.62)
		&"nameless_sun_court": return Color(0.78, 0.56, 0.32)
		_: return FOLD
