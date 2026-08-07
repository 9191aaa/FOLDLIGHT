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

@onready var controller: FoldlightEndlessSurvivalController = $Controller
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
	controller.enemy_wave_requested.connect(_on_enemy_wave_requested)
	controller.player_evolution_changed.connect(_on_player_evolution_changed)
	controller.mission_reward_offered.connect(_on_mission_reward_offered)
	controller.mission_reward_claimed.connect(_on_mission_reward_claimed)
	combat_runtime.projectile_captured.connect(_on_projectile_captured)
	combat_runtime.player_hit.connect(_on_player_hit)
	combat_runtime.enemy_defeated_detailed.connect(_on_enemy_defeated_detailed)
	for index in modal_buttons.size():
		modal_buttons[index].pressed.connect(_activate_modal_choice.bind(index))
	call_deferred("start_slice")


func start_slice(seed: int = 20260728) -> Dictionary:
	if controller.active:
		controller.exit_mode(&"restart")
	world.deactivate()
	player.set_play_enabled(false)
	player.reset_player()
	player.configure_roguelite_combat(true)
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
	if _toast_remaining > 0.0:
		_toast_remaining = maxf(0.0, _toast_remaining - delta)
		reward_toast.visible = _toast_remaining > 0.0
	if _damage_flash_remaining > 0.0:
		_damage_flash_remaining = maxf(0.0, _damage_flash_remaining - delta)
		var ratio := _damage_flash_remaining / 0.24
		damage_flash.color.a = 0.18 * ratio
		damage_flash.visible = ratio > 0.0
	elif damage_flash.visible:
		damage_flash.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _modal_kind.is_empty():
		if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
			_move_modal_selection(-1)
		elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
			_move_modal_selection(1)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"fold"):
			_activate_modal_choice(_modal_selected)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause_game"):
		_return_to_title()
		get_viewport().set_input_as_handled()


func _return_to_title() -> void:
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


func _on_projectile_captured(_captured_count: int, _position: Vector2) -> void:
	controller.report_projectiles_absorbed(1)


func _on_enemy_defeated_detailed(enemy_id: StringName, entry: Dictionary) -> void:
	var report := entry.duplicate(true)
	report["enemy_id"] = enemy_id
	controller.report_enemy_defeated(report)
	var shake := 0.34 if bool(entry.get("is_captain", false)) else 0.16
	camera.add_trauma(shake)


func _on_player_hit(health_remaining: int) -> void:
	_damage_flash_remaining = 0.24
	damage_flash.show()
	camera.add_trauma(0.62)
	camera.add_hit_kick(1.0)
	if health_remaining <= 0:
		_finish_run()


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
	_update_modal_focus()


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
	var visible_count := 0
	for button in modal_buttons:
		if button.visible:
			visible_count += 1
	if visible_count <= 0:
		return
	_modal_selected = posmod(_modal_selected + direction, visible_count)
	_update_modal_focus()


func _update_modal_focus() -> void:
	if _modal_selected >= 0 and _modal_selected < modal_buttons.size() and modal_buttons[_modal_selected].visible:
		modal_buttons[_modal_selected].grab_focus()


func _activate_modal_choice(index: int) -> void:
	if _modal_kind == &"reward":
		if index < 0 or index >= _modal_options.size():
			return
		var reward_id := StringName(_modal_options[index].get("id", &""))
		if controller.claim_mission_reward(reward_id).is_empty():
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


func _finish_run() -> void:
	if run_ended:
		return
	run_ended = true
	player.set_play_enabled(false)
	combat_runtime.set_active(false)
	controller.exit_mode(&"player_defeated")
	_modal_kind = &"game_over"
	_modal_options.clear()
	_modal_selected = 0
	modal_title.text = "灯火熄灭"
	modal_body.text = "坚持 %s · 击破 %d\n所有战斗规则均来自 2.0 本体。" % [
		_format_time(controller.evolution.survival_seconds),
		controller.defeated_total,
	]
	modal_buttons[0].text = "重新开始"
	modal_buttons[0].show()
	modal_buttons[1].text = "返回标题"
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
	status_label.text = "FOLDLIGHT / 无尽生存\n生命 %d/%d · 敌人 %d · 击破 %d\n威胁阶段 %d · 收纳进化 %d · 生存 %s" % [
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
	help_label.text = "WASD / 方向键移动    空格折域    Shift 冲刺    Q 主动道具    Esc 返回标题"


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
