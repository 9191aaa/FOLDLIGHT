class_name FoldlightEndlessSliceRuntime
extends Node2D

## Endless is an adapter around the exact 2.0 combat stack.  This script owns
## only map setup, wave scheduling, objectives, rewards and modal presentation.
## Player movement/Fold/dash, enemies, projectiles, damage and drawing all live
## in Player + RogueWorld + RogueCombatRuntime.

signal title_requested

const DASH_COOLDOWN := 2.0
const MAX_LIVE_ENEMIES := 84
const BASE_RETURN_DAMAGE := 2.8
const BASE_RETURN_SPEED := 610.0
const REWARD_INPUT_GUARD = preload("res://scripts/ui/reward_input_guard.gd")
const DAMAGE_EDGE_DURATION: float = 0.24
const DAMAGE_EDGE_SHADER: String = """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 distance_from_center = abs(UV * 2.0 - 1.0);
	float edge = smoothstep(0.68, 1.0, max(distance_from_center.x, distance_from_center.y));
	COLOR = vec4(COLOR.rgb, COLOR.a * edge * edge);
}
"""

var run_ended: bool = false
var _modal_kind: StringName = &""
var _modal_options: Array[Dictionary] = []
var _modal_selected: int = 0
var _combined_modifiers: Dictionary = {}
var _toast_remaining: float = 0.0
var _damage_flash_remaining: float = 0.0
var _hud_clock: float = 0.0
var _objective_weapon_clock: float = 0.0
var _transitioning_to_title: bool = false
var _web_race_bridge: Node
var _race_prepared: bool = false
var _race_started: bool = false
var _reward_input_guard: Node
var _reward_entrance_tween: Tween
var _feedback_motion_scale: float = 1.0
var _feedback_vibration: bool = true
var _capture_sfx_cooldown: float = 0.0
var _kill_shake_cooldown: float = 0.0
var _return_kick_cooldown: float = 0.0

@onready var controller: FoldlightEndlessSurvivalController = $Controller
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector
@onready var world: FoldlightRogueWorld = $RogueWorld
@onready var player: FoldlightPlayer = $Player
@onready var camera: FoldlightRogueCamera = $RogueWorld/CameraRig
@onready var combat_runtime: FoldlightRogueCombatRuntime = $RogueWorld/CombatRuntime
@onready var status_label: Label = $HUD/Status
@onready var objective_label: Label = $HUD/Objective
@onready var help_label: Label = $HUD/Help
@onready var damage_flash: ColorRect = $HUD/DamageFlash
@onready var reward_toast: Panel = $HUD/RewardToast
@onready var reward_toast_label: Label = $HUD/RewardToast/RewardToastLabel
@onready var modal_dim: ColorRect = $HUD/ModalDim
@onready var modal_title: Label = $HUD/ModalDim/ModalPanel/ModalTitle
@onready var modal_body: Label = $HUD/ModalDim/ModalPanel/ModalBody
@onready var modal_buttons: Array[Button] = [
	$HUD/ModalDim/ModalPanel/Choice1,
	$HUD/ModalDim/ModalPanel/Choice2,
	$HUD/ModalDim/ModalPanel/Choice3,
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_shared_theme()
	_setup_reward_input()
	_setup_combat_feedback()
	controller.enemy_wave_requested.connect(_on_enemy_wave_requested)
	controller.player_evolution_changed.connect(_on_player_evolution_changed)
	controller.mission_reward_offered.connect(_on_mission_reward_offered)
	controller.mission_reward_claimed.connect(_on_mission_reward_claimed)
	combat_runtime.projectile_captured.connect(_on_projectile_captured)
	combat_runtime.player_hit.connect(_on_player_hit)
	combat_runtime.enemy_defeated_detailed.connect(_on_enemy_defeated_detailed)
	combat_runtime.impact_confirmed.connect(_on_combat_impact_confirmed)
	player.fold_started.connect(_on_feedback_fold_started)
	player.fold_released.connect(_on_feedback_fold_released)
	player.focus_empty.connect(_on_feedback_focus_empty)
	for index in modal_buttons.size():
		modal_buttons[index].pressed.connect(_activate_modal_choice.bind(index))
		modal_buttons[index].focus_entered.connect(_on_modal_button_focused.bind(index))
	call_deferred("_start_initial_slice")


func _start_initial_slice() -> void:
	var bridge := get_node_or_null("/root/WebRaceBridge")
	if bridge != null and bool(bridge.call("is_web_session")):
		if bool(bridge.call("is_race_session")):
			prepare_web_race(bridge)
		else:
			start_slice(int(bridge.call("get_run_seed")))
	else:
		start_slice()


func prepare_web_race(bridge: Node) -> bool:
	if _race_prepared:
		return false
	_web_race_bridge = bridge
	var snapshot := start_slice(int(bridge.call("get_run_seed")))
	_race_prepared = true
	_modal_kind = &"race_waiting"
	_set_combat_suspended(true)
	modal_title.text = "好友无尽 · 等待出发"
	modal_body.text = "双方准备完成后，由网页统一倒计时。\n同一种子、相同基础机体；按有效战斗时间比较。"
	for button in modal_buttons:
		button.hide()
	modal_dim.show()
	_refresh_hud()
	if snapshot.has("errors"):
		bridge.call("finish_local", &"abandoned", "scene_load_failed")
		return false
	return bool(bridge.call("bind_runtime", self))


func begin_web_race() -> void:
	if not _race_prepared or _race_started or run_ended:
		return
	_race_started = true
	_modal_kind = &""
	modal_dim.hide()
	combat_runtime.set_active(true)
	player.set_play_enabled(true)
	_refresh_hud()


func stop_web_race(reason: String) -> void:
	_cancel_reward_entry()
	run_ended = true
	player.set_play_enabled(false)
	combat_runtime.set_active(false)
	controller.exit_mode(StringName(reason))
	_modal_kind = &"race_finished"
	_modal_options.clear()
	modal_title.text = "灯火熄灭" if reason == "player_defeated" else "好友对局已结束"
	modal_body.text = "有效航行 %s · 击破 %d\n请在网页房间查看成绩。本局不能重新开始。" % [_format_time(controller.evolution.survival_seconds), controller.defeated_total]
	for button in modal_buttons:
		button.hide()
	modal_dim.show()


func get_race_stats() -> Dictionary:
	var pause_reason := ""
	if run_ended:
		pause_reason = "finished"
	elif not _race_started and _web_race_bridge != null:
		pause_reason = "waiting"
	elif _modal_kind == &"reward":
		pause_reason = "reward"
	elif not _modal_kind.is_empty():
		pause_reason = "manual"
	return {
		"survivalMs": int(floor(controller.evolution.survival_seconds * 1000.0)),
		"kills": controller.defeated_total,
		"health": player.health,
		"maxHealth": player.max_health,
		"paused": not pause_reason.is_empty(),
		"pauseReason": pause_reason,
	}


func start_slice(seed: int = 20260728) -> Dictionary:
	if _web_race_bridge != null and _race_prepared:
		return {"errors": ["race_attempt_cannot_restart"]}
	_cancel_reward_entry()
	if controller.active:
		controller.exit_mode(&"restart")
	world.deactivate()
	player.set_play_enabled(false)
	player.reset_player()
	player.configure_roguelite_combat(true)
	_apply_feedback_settings()
	audio_director.reset_combat_feedback()
	_capture_sfx_cooldown = 0.0
	_kill_shake_cooldown = 0.0
	_return_kick_cooldown = 0.0
	player.set_debug_invincible(false)
	controller.map_runtime.build_physics_walls = false
	controller.map_runtime.draw_cover_visuals = false
	var room_errors := world.load_room(
		player,
		&"endless_folded_delta",
		controller.map_definition.bounds.size,
		_build_room_terrain(),
		Color("55b8a8"),
		seed,
		&"paper_reef",
	)
	if not room_errors.is_empty():
		push_error("Endless adapter could not configure the 2.0 room: %s" % "; ".join(room_errors))
		return {"errors": room_errors}
	world.activate()
	camera.zoom = Vector2(0.82, 0.82)
	player.global_position = controller.map_definition.player_spawn
	player.health = player.max_health
	player.grant_invulnerability(1.0)
	player.set_play_enabled(true)
	run_ended = false
	_modal_kind = &""
	_modal_options.clear()
	_modal_selected = 0
	modal_dim.hide()
	reward_toast.hide()
	damage_flash.hide()
	_toast_remaining = 0.0
	_damage_flash_remaining = 0.0
	_objective_weapon_clock = 0.0
	_transitioning_to_title = false
	var snapshot := controller.enter_mode(seed, player)
	_refresh_combined_modifiers()
	controller.force_next_wave()
	_refresh_hud()
	return snapshot


func _physics_process(delta: float) -> void:
	if run_ended or not _modal_kind.is_empty() or not controller.active:
		return
	controller.advance_simulation(delta, player.global_position)
	_update_flag_objective(delta)
	_hud_clock -= delta
	if _hud_clock <= 0.0:
		_hud_clock = 0.10
		_refresh_hud()


func _process(delta: float) -> void:
	_capture_sfx_cooldown = maxf(0.0, _capture_sfx_cooldown - delta)
	_kill_shake_cooldown = maxf(0.0, _kill_shake_cooldown - delta)
	_return_kick_cooldown = maxf(0.0, _return_kick_cooldown - delta)
	if _toast_remaining > 0.0:
		_toast_remaining = maxf(0.0, _toast_remaining - delta)
		reward_toast.visible = _toast_remaining > 0.0
	if _damage_flash_remaining > 0.0:
		_damage_flash_remaining = maxf(0.0, _damage_flash_remaining - delta)
		var ratio := _damage_flash_remaining / DAMAGE_EDGE_DURATION
		damage_flash.color.a = 0.42 * ratio
		damage_flash.visible = ratio > 0.0
	elif damage_flash.visible:
		damage_flash.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# Audio remains available while a reward or pause owns the gameplay input.
	if event.is_action_pressed(&"mute_audio"):
		get_viewport().set_input_as_handled()
		audio_director.toggle_mute()
		return
	if not _modal_kind.is_empty():
		if _modal_kind == &"pause" and event.is_action_pressed(&"pause_game"):
			_resume_game()
		elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
			_move_modal_selection(-1)
		elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
			_move_modal_selection(1)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"fold"):
			_activate_modal_choice(_modal_selected)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause_game"):
		_pause_game()
		get_viewport().set_input_as_handled()


func _pause_game() -> void:
	if _web_race_bridge != null:
		reward_toast_label.text = "好友竞赛不能手动暂停；奖励选择不计时。弃赛请使用网页房间。"
		_toast_remaining = 2.8
		reward_toast.show()
		return
	if run_ended or not _modal_kind.is_empty() or not controller.active:
		return
	_cancel_reward_entry()
	_modal_kind = &"pause"
	_modal_selected = 0
	modal_title.text = "暂泊纸海"
	modal_body.text = "无尽挑战已暂停。\n返回主菜单会结束本次挑战。"
	modal_buttons[0].text = "继续航行"
	modal_buttons[0].show()
	modal_buttons[1].text = "结束挑战 · 返回主菜单"
	modal_buttons[1].show()
	modal_buttons[2].hide()
	modal_dim.show()
	_set_combat_suspended(true)
	_update_modal_focus()


func _resume_game() -> void:
	if _modal_kind != &"pause":
		return
	_modal_kind = &""
	modal_dim.hide()
	_set_combat_suspended(false)


func _return_to_title() -> void:
	_cancel_reward_entry()
	if _web_race_bridge != null:
		_web_race_bridge.call("finish_local", &"abandoned", "abandoned")
		return
	if _transitioning_to_title:
		return
	_transitioning_to_title = true
	player.set_play_enabled(false)
	world.deactivate()
	controller.exit_mode(&"return_to_title")
	title_requested.emit()
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		_transitioning_to_title = false
		push_error("Unable to return to title: %s" % error_string(error))


func _on_enemy_wave_requested(request: Dictionary) -> void:
	var open_slots := maxi(0, MAX_LIVE_ENEMIES - combat_runtime.enemies.size())
	if open_slots <= 0:
		return
	var directed: Array[Dictionary] = []
	var entries_variant: Variant = request.get("entries", [])
	if entries_variant is Array:
		for entry_variant: Variant in entries_variant:
			if directed.size() >= open_slots:
				break
			if not entry_variant is Dictionary:
				continue
			var entry := (entry_variant as Dictionary).duplicate(true)
			entry["spawn_position"] = Vector2(entry.get("position", Vector2.ZERO))
			directed.append(entry)
	combat_runtime.spawn_directed_wave(directed)


func _on_projectile_captured(captured_count: int, _position: Vector2) -> void:
	controller.report_projectiles_absorbed(1)
	if _capture_sfx_cooldown <= 0.0 and _feedback_is_live():
		_capture_sfx_cooldown = 0.065
		audio_director.play_sfx(&"capture", 0.90 + minf(0.32, float(captured_count) * 0.025), -10.0)


func _on_enemy_defeated_detailed(enemy_id: StringName, entry: Dictionary) -> void:
	var report := entry.duplicate(true)
	report["enemy_id"] = enemy_id
	controller.report_enemy_defeated(report)
	if _kill_shake_cooldown <= 0.0:
		var shake := 0.34 if bool(entry.get("is_captain", false)) else 0.16
		camera.add_trauma(shake * _feedback_motion_scale)
		_kill_shake_cooldown = 0.075


func _on_player_hit(health_remaining: int) -> void:
	_damage_flash_remaining = DAMAGE_EDGE_DURATION
	damage_flash.color = Color(0.96, 0.43, 0.34, 0.42)
	damage_flash.show()
	audio_director.play_sfx(&"hurt", 0.96, -4.0)
	camera.add_trauma(0.62 * _feedback_motion_scale)
	camera.add_hit_kick(_feedback_motion_scale)
	if _feedback_vibration:
		Input.start_joy_vibration(0, 0.22, 0.46, 0.16)
	_refresh_hud()
	if health_remaining <= 0:
		_finish_run()


func _setup_combat_feedback() -> void:
	var edge_shader := Shader.new()
	edge_shader.code = DAMAGE_EDGE_SHADER
	var edge_material := ShaderMaterial.new()
	edge_material.shader = edge_shader
	damage_flash.material = edge_material
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_feedback_settings() -> void:
	var profile := get_node_or_null("/root/ProfileManager")
	_feedback_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0
	_feedback_vibration = bool(profile.call("get_setting", &"vibration", true)) if profile != null else true
	player.set_feedback_motion_scale(_feedback_motion_scale)


func _feedback_is_live() -> bool:
	return not run_ended and _modal_kind.is_empty() and combat_runtime.active


func _on_combat_impact_confirmed(kind: StringName, weight: float) -> void:
	if _feedback_is_live():
		audio_director.play_combat_impact(kind, weight)
		if kind == &"return" and _return_kick_cooldown <= 0.0:
			camera.add_hit_kick(0.32 * _feedback_motion_scale)
			_return_kick_cooldown = 0.18


func _on_feedback_fold_started() -> void:
	if _feedback_is_live():
		audio_director.play_sfx(&"fold", 1.0, -8.0)


func _on_feedback_fold_released(captured_count: int, _charge_ratio: float) -> void:
	if not _feedback_is_live():
		return
	audio_director.play_sfx(&"release" if captured_count > 0 else &"empty", 0.90 + minf(0.25, float(captured_count) * 0.015), -7.0 if captured_count > 0 else -12.0)
	if captured_count > 0:
		camera.add_trauma(minf(0.30, 0.10 + float(captured_count) * 0.018) * _feedback_motion_scale)
		if _feedback_vibration:
			var strength := minf(0.34, 0.16 + float(captured_count) * 0.012)
			Input.start_joy_vibration(0, strength * 0.55, strength, 0.11)


func _on_feedback_focus_empty(_captured_count: int, _charge_ratio: float) -> void:
	if _feedback_is_live():
		audio_director.play_sfx(&"empty", 0.86, -12.0)


func _on_player_evolution_changed(_snapshot: Dictionary) -> void:
	_refresh_combined_modifiers()


func _on_mission_reward_offered(options: Array[Dictionary], objective_snapshot: Dictionary) -> void:
	if run_ended or options.is_empty():
		return
	_modal_kind = &"reward"
	_modal_options = options.duplicate(true)
	_modal_selected = 0
	modal_title.text = "任务完成 · 选择一次进化"
	modal_body.text = "%s 已完成。三条路线只强化本局。" % String(objective_snapshot.get("title", "系统任务"))
	for index in modal_buttons.size():
		var button := modal_buttons[index]
		button.visible = index < _modal_options.size()
		if button.visible:
			var option := _modal_options[index]
			button.text = "【%s】%s  Lv.%d\n%s" % [
				String(option.get("lane_title", "成长")),
				String(option.get("title", "进化")),
				int(option.get("next_level", 1)),
				String(option.get("description", "")),
			]
	modal_dim.show()
	_set_combat_suspended(true)
	_reward_input_guard.begin(modal_dim)
	if _reward_entrance_tween != null and _reward_entrance_tween.is_valid():
		_reward_entrance_tween.kill()
	modal_dim.modulate.a = 0.0
	_reward_entrance_tween = create_tween()
	_reward_entrance_tween.tween_property(modal_dim, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_mission_reward_claimed(reward: Dictionary) -> void:
	var health_before := player.health
	_refresh_combined_modifiers()
	var reward_modifiers_variant: Variant = reward.get("modifiers", {})
	var reward_modifiers := reward_modifiers_variant as Dictionary if reward_modifiers_variant is Dictionary else {}
	player.health = mini(player.max_health, health_before + int(round(float(reward_modifiers.get("heal", 0.0)))))
	reward_toast_label.text = "已获得【%s】%s  Lv.%d" % [
		String(reward.get("lane_title", "成长")),
		String(reward.get("title", "进化")),
		int(reward.get("level", 1)),
	]
	_toast_remaining = 2.8
	reward_toast.show()


func _move_modal_selection(direction: int) -> void:
	if _modal_kind == &"reward" and not _reward_input_guard.can_select():
		return
	var visible_count := 0
	for button in modal_buttons:
		if button.visible:
			visible_count += 1
	if visible_count <= 0:
		return
	_modal_selected = posmod(_modal_selected + direction, visible_count)
	_update_modal_focus()


func _update_modal_focus() -> void:
	if _modal_selected >= 0 and _modal_selected < modal_buttons.size() and modal_buttons[_modal_selected].visible and not modal_buttons[_modal_selected].disabled:
		modal_buttons[_modal_selected].grab_focus()


func _on_modal_button_focused(index: int) -> void:
	_modal_selected = index


func _activate_modal_choice(index: int) -> void:
	if _modal_kind == &"pause":
		if index == 0:
			_resume_game()
		elif index == 1:
			_return_to_title()
	elif _modal_kind == &"reward":
		if not _reward_input_guard.can_select() or index < 0 or index >= _modal_options.size():
			return
		# Lock before the controller emits synchronous reward signals.
		_reward_input_guard.cancel()
		var reward_id := StringName(_modal_options[index].get("id", &""))
		if controller.claim_mission_reward(reward_id).is_empty():
			_reward_input_guard.begin(modal_dim)
			return
		_modal_kind = &""
		_modal_options.clear()
		modal_dim.hide()
		_set_combat_suspended(false)
	elif _modal_kind == &"game_over":
		if index == 0:
			start_slice(controller.run_seed)
		elif index == 1:
			_return_to_title()


func _setup_reward_input() -> void:
	_reward_input_guard = REWARD_INPUT_GUARD.new()
	_reward_input_guard.name = "RewardInputGuard"
	add_child(_reward_input_guard)
	_reward_input_guard.state_changed.connect(_on_reward_input_state_changed)
	modal_dim.visibility_changed.connect(_on_reward_visibility_changed)


func _on_reward_input_state_changed() -> void:
	if _modal_kind != &"reward":
		return
	var available: bool = _reward_input_guard.can_select()
	for button in modal_buttons:
		button.disabled = not available
	($HUD/ModalDim/ModalPanel/ModalHint as Label).text = "方向键 / WASD 选择    空格 / A 确认" if available else _reward_input_guard.get_hint()
	if available:
		_update_modal_focus()


func _cancel_reward_entry() -> void:
	if _reward_input_guard != null:
		_reward_input_guard.cancel()
	if _reward_entrance_tween != null and _reward_entrance_tween.is_valid():
		_reward_entrance_tween.kill()
	modal_dim.modulate = Color.WHITE
	for button in modal_buttons:
		button.disabled = false
	($HUD/ModalDim/ModalPanel/ModalHint as Label).text = "方向键 / WASD 选择    空格 / A 确认"


func _on_reward_visibility_changed() -> void:
	if not modal_dim.is_visible_in_tree():
		_cancel_reward_entry()


func _finish_run() -> void:
	_cancel_reward_entry()
	if run_ended:
		return
	run_ended = true
	player.set_play_enabled(false)
	combat_runtime.set_active(false)
	controller.exit_mode(&"player_defeated")
	if _web_race_bridge != null:
		_web_race_bridge.call("finish_local", &"dead", "player_defeated")
		return
	_modal_kind = &"game_over"
	_modal_options.clear()
	_modal_selected = 0
	modal_title.text = "灯火熄灭"
	modal_body.text = "航行 %s · 击破 %d\n再点亮一次，继续向深海出发。" % [
		_format_time(controller.evolution.survival_seconds),
		controller.defeated_total,
	]
	modal_buttons[0].text = "重新开始"
	modal_buttons[0].show()
	modal_buttons[1].text = "返回主菜单"
	modal_buttons[1].show()
	modal_buttons[2].hide()
	modal_dim.show()
	_update_modal_focus()


func _set_combat_suspended(suspended: bool) -> void:
	if suspended:
		player.suspend_for_overlay()
		combat_runtime.set_active(false)
	else:
		combat_runtime.set_active(true)
		player.resume_from_overlay(0.75)


func _refresh_combined_modifiers() -> void:
	_combined_modifiers.clear()
	var axes: Array[Dictionary] = [
		controller.evolution.get_player_snapshot().get("total_modifiers", {}) as Dictionary,
		controller.evolution.get_mission_snapshot().get("total_modifiers", {}) as Dictionary,
	]
	for axis in axes:
		for key: Variant in axis:
			_combined_modifiers[key] = float(_combined_modifiers.get(key, 0.0)) + float(axis[key])
	var resolved := {
		"capture_capacity": float(_combined_modifiers.get("capture_capacity", 0.0)),
		"fold_radius_multiplier": 1.0 + float(_combined_modifiers.get("fold_radius_multiplier", 0.0)),
		"return_damage_multiplier": 1.0 + float(_combined_modifiers.get("return_damage_multiplier", 0.0)),
		"fold_move_speed_add": float(_combined_modifiers.get("fold_move_speed_multiplier", 0.0)),
		"move_speed_multiplier": 1.0 + float(_combined_modifiers.get("move_speed_multiplier", 0.0)),
		"dash_cooldown_multiplier": 1.0 + float(_combined_modifiers.get("dash_cooldown_multiplier", 0.0)),
		"max_health_add": float(_combined_modifiers.get("max_health", 0.0)),
		"weapon_interval_multiplier": 1.0 - float(_combined_modifiers.get("weapon_rate_multiplier", 0.0)),
		"projectile_pierce_add": float(_combined_modifiers.get("weapon_pierce", 0.0)),
		"damage_grace_add": float(_combined_modifiers.get("damage_grace_add", 0.0)),
		"return_speed_multiplier": 1.0 + float(_combined_modifiers.get("return_speed_multiplier", 0.0)),
		"return_chain_add": float(_combined_modifiers.get("return_chain", 0.0)),
	}
	player.apply_roguelite_stats(resolved)
	combat_runtime.apply_build_stats(resolved)


func _update_flag_objective(delta: float) -> void:
	var objective := controller.objectives.get_snapshot()
	if StringName(objective.get("kind", &"")) != &"destroy_flag" or bool(objective.get("completed", false)):
		return
	_objective_weapon_clock -= delta
	if _objective_weapon_clock > 0.0:
		return
	_objective_weapon_clock = 0.55 * float(player.rogue_build_stats.get("weapon_interval_multiplier", 1.0))
	var flag_position := Vector2(objective.get("target_position", Vector2.ZERO))
	if player.global_position.distance_to(flag_position) <= 920.0 and controller.map_runtime.has_line_of_sight(player.global_position, flag_position, 8.0):
		controller.report_flag_damage(StringName(objective.get("target_id", &"")), 1.0)


func _build_room_terrain() -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	for index in controller.map_definition.walls.size():
		var wall := controller.map_definition.walls[index]
		placements.append({
			"id": "endless_wall_%02d" % index,
			"kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL,
			"position": wall.get_center(),
			"size": wall.size,
			"rotation": 0.0,
			"strength": 1.0,
			"direction": Vector2.RIGHT,
			"visual_style": &"paper_reef",
		})
	return placements


func _refresh_hud() -> void:
	var enemy_state := controller.evolution.get_enemy_snapshot()
	var player_state := controller.evolution.get_player_snapshot()
	status_label.text = "FOLDLIGHT / 无尽挑战\n灯芯 %d/%d · 敌人 %d · 击破 %d\n威胁阶段 %d · 收纳进化 %d · 航行 %s" % [
		player.health,
		player.max_health,
		combat_runtime.enemies.size(),
		controller.defeated_total,
		int(enemy_state.get("stage", 0)),
		int(player_state.get("stage", 0)),
		_format_time(float(enemy_state.get("survival_seconds", 0.0))),
	]
	var objective := controller.objectives.get_snapshot()
	objective_label.text = "%s\n%s\n进度 %d%% · 剩余 %d 秒" % [
		String(objective.get("title", "任务准备中")),
		String(objective.get("instruction", "")),
		int(float(objective.get("progress_ratio", 0.0)) * 100.0),
		int(ceil(float(objective.get("time_remaining", 0.0)))),
	]
	help_label.text = "左摇杆移动    A 折域    B 冲刺    X 主动道具    Start 暂停" if not Input.get_connected_joypads().is_empty() else "WASD / 方向键移动    空格折域    Shift 冲刺    Q 主动道具    Esc 暂停"
	if _web_race_bridge != null:
		help_label.text = "好友竞赛 · 同一种子 / 基础机体    奖励选择不计时    竞赛不可手动暂停    弃赛请使用网页房间"


func _apply_shared_theme() -> void:
	var shared_theme := FoldlightTheme.build()
	for child in $HUD.get_children():
		if child is Control:
			child.theme = shared_theme
	for panel: Panel in [$HUD/TopPanel, $HUD/ObjectivePanel, $HUD/HelpPanel, reward_toast, $HUD/ModalDim/ModalPanel]:
		panel.add_theme_stylebox_override("panel", FoldlightTheme.panel_style())
	for button in modal_buttons:
		for style in [&"normal", &"hover", &"pressed", &"focus"]:
			button.remove_theme_stylebox_override(style)
		button.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", FoldlightTheme.PAPER)
	objective_label.add_theme_color_override("font_color", FoldlightTheme.GOLD)
	help_label.add_theme_color_override("font_color", FoldlightTheme.MUTED)
	modal_title.add_theme_color_override("font_color", FoldlightTheme.PAPER)
	modal_body.add_theme_color_override("font_color", FoldlightTheme.MUTED)
	reward_toast_label.add_theme_color_override("font_color", FoldlightTheme.GOLD)


func get_slice_snapshot() -> Dictionary:
	return {
		"controller": controller.get_snapshot(),
		"player_position": player.global_position,
		"player_health": player.health,
		"max_health": player.max_health,
		"enemy_count": combat_runtime.enemies.size(),
		"projectile_count": combat_runtime.projectiles.size(),
		"run_ended": run_ended,
		"modal_kind": _modal_kind,
		"combat_reuse": get_combat_reuse_contract(),
	}


func get_combat_reuse_contract() -> Dictionary:
	var all_enemy_actors := true
	for enemy in combat_runtime.enemies:
		if not (enemy is FoldlightRogueEnemyActor or enemy is FoldlightRogueBossActor):
			all_enemy_actors = false
			break
	var all_projectiles := true
	for projectile in combat_runtime.projectiles:
		if not projectile is FoldlightRogueProjectile:
			all_projectiles = false
			break
	return {
		"version": &"classic_2_0_runtime_reuse",
		"player_scene": &"res://scenes/player.tscn",
		"world_scene": &"res://scenes/roguelite/rogue_world.tscn",
		"player_is_2_0": player is FoldlightPlayer,
		"combat_is_2_0": combat_runtime is FoldlightRogueCombatRuntime,
		"enemy_instances_are_2_0": all_enemy_actors,
		"projectile_instances_are_2_0": all_projectiles,
		"parallel_combat_state": false,
	}


func get_effective_combat_stats() -> Dictionary:
	var stats := player.rogue_build_stats
	return {
		"capture_capacity": player.get_capture_capacity(),
		"fold_radius": FoldlightPlayer.FOLD_RADIUS_MAX * player.fold_radius_multiplier,
		"return_damage": BASE_RETURN_DAMAGE * float(stats.get("return_damage_multiplier", 1.0)),
		"return_speed": BASE_RETURN_SPEED * float(stats.get("return_speed_multiplier", 1.0)),
		"return_chain": int(round(float(stats.get("return_chain_add", 0.0)))),
		"move_speed": FoldlightPlayer.MOVE_SPEED * player.move_speed_multiplier,
		"fold_move_speed": FoldlightPlayer.FOLD_SPEED * player.fold_speed_multiplier,
		"dash_cooldown": player.dash_component.base_cooldown * player.dash_component.cooldown_multiplier,
		"auto_fire_interval": _starter_weapon_interval(),
		"weapon_pierce": int(round(float(stats.get("projectile_pierce_add", 0.0)))),
		"damage_grace": 1.35 + player.damage_grace_add,
		"max_health": player.max_health,
	}


func get_return_route_preview() -> PackedVector2Array:
	var target := player.global_position + Vector2(420.0, 0.0)
	if not combat_runtime.enemies.is_empty() and is_instance_valid(combat_runtime.enemies[0]):
		target = combat_runtime.enemies[0].global_position
	return combat_runtime.preview_return_route(player.global_position, target)


func _starter_weapon_interval() -> float:
	if player.weapon_mount.definitions.is_empty():
		return 0.0
	return player.weapon_mount.definitions[0].fire_interval * float(player.rogue_build_stats.get("weapon_interval_multiplier", 1.0))


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
