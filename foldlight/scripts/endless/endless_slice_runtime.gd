class_name FoldlightEndlessSliceRuntime
extends Node2D

## Endless is an adapter around the exact 2.0 combat stack.  This script owns
## only map setup, wave scheduling, objectives, rewards and modal presentation.
## Player movement/Fold/dash, enemies, projectiles, damage and drawing all live
## in Player + RogueWorld + RogueCombatRuntime.

signal title_requested

const DASH_COOLDOWN := 2.0
const MAX_LIVE_ENEMIES := 48
const SPAWN_WARNING_SECONDS := 0.65
const SPAWNS_PER_STEP := 2
const DISTANT_RETIRE_DISTANCE := 1800.0
const DISTANT_RETIRE_SECONDS := 12.0
const BASE_RETURN_DAMAGE := 2.8
const BASE_RETURN_SPEED := 610.0
const OBJECTIVE_COMPLETE_SECONDS: float = 0.5
const ObjectiveTarget = preload("res://scripts/endless/endless_objective_target.gd")

var run_ended: bool = false
var _modal_kind: StringName = &""
var _modal_options: Array[Dictionary] = []
var _combined_modifiers: Dictionary = {}
var _hud_clock: float = 0.0
var _objective_target: Node2D
var _zone_exposure := FoldlightEndlessZoneExposure.new()
var _navigation: Control
var _safe_route_clock: float = 0.0
var _safe_route_position := Vector2.ZERO
var _storm_support_count: int = 0
var _storm_support_clock: float = 0.0
var _transitioning_to_title: bool = false
var _web_race_bridge: Node
var _race_prepared: bool = false
var _race_started: bool = false
var _claiming_reward: bool = false
var _feedback_motion_scale: float = 1.0
var _feedback_vibration: bool = true
var _capture_sfx_cooldown: float = 0.0
var _kill_shake_cooldown: float = 0.0
var _return_kick_cooldown: float = 0.0
var _barrage_elite_introduced: bool = false
var _bomber_introduced: bool = false
var _music_sample_clock: float = 0.0
var _reward_completion_remaining: float = 0.0
var _reward_objective_title: String = ""
var _paused_modal_kind: StringName = &""
var _fold_task_id: StringName = &""
var _fold_release_serial: int = 0
var _pending_fold_release_serial: int = 0
var _application_suspended: bool = false
var _reward_token: String = ""
var _reward_context: Dictionary = {}
var _defeat_serial: int = 0
var _pending_spawns: Array[Dictionary] = []
var _distant_enemy_age: Dictionary = {}
var _population_clock: float = 0.0
var _boss_director := FoldlightEndlessBossDirector.new()
var _boss_entries: Array[Dictionary] = []
var _boss_placement_retry: float = 0.0
var _bombardment: FoldlightEndlessBombardment

@onready var controller: FoldlightEndlessSurvivalController = $Controller
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector
@onready var world: FoldlightRogueWorld = $RogueWorld
@onready var player: FoldlightPlayer = $Player
@onready var camera: FoldlightRogueCamera = $RogueWorld/CameraRig
@onready var combat_runtime: FoldlightRogueCombatRuntime = $RogueWorld/CombatRuntime
@onready var presentation: FoldlightRoguePresentation = $RoguePresentation
@onready var profile_manager: FoldlightProfileManager = get_node("/root/ProfileManager") as FoldlightProfileManager
@onready var _touch_controls: Node = get_node_or_null("/root/TouchControls")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bombardment = FoldlightEndlessBombardment.new()
	_bombardment.name = "BombardmentLandingSites"
	add_child(_bombardment)
	presentation.show_hud()
	_navigation = preload("res://scripts/endless/navigation_overlay.gd").new()
	presentation.attach_navigation_overlay(_navigation)
	presentation.reward_chosen.connect(_on_reward_chosen)
	presentation.active_relic_selected.connect(_on_active_relic_selected)
	presentation.resume_requested.connect(_resume_game)
	presentation.pause_requested.connect(_pause_game)
	presentation.settings_requested.connect(_on_settings_requested)
	presentation.setting_adjust_requested.connect(_on_setting_adjust_requested)
	presentation.settings_back_requested.connect(_on_settings_back_requested)
	presentation.abandon_requested.connect(_abandon_run)
	presentation.retry_requested.connect(_retry_run)
	presentation.title_requested.connect(_return_to_title)
	controller.enemy_wave_requested.connect(_on_enemy_wave_requested)
	controller.player_evolution_changed.connect(_on_player_evolution_changed)
	controller.mission_reward_offered.connect(_on_mission_reward_offered)
	controller.mission_reward_claimed.connect(_on_mission_reward_claimed)
	controller.objective_started.connect(_on_objective_started)
	controller.objective_failed.connect(_on_objective_failed)
	combat_runtime.projectile_captured.connect(_on_projectile_captured)
	combat_runtime.player_hit.connect(_on_player_hit)
	combat_runtime.enemy_defeated_detailed.connect(_on_enemy_defeated_detailed)
	combat_runtime.impact_confirmed.connect(_on_combat_impact_confirmed)
	player.fold_started.connect(_on_feedback_fold_started)
	player.fold_released.connect(_on_feedback_fold_released)
	player.focus_empty.connect(_on_feedback_focus_empty)
	call_deferred("_start_initial_slice")


func _start_initial_slice() -> void:
	var bridge := get_node_or_null("/root/WebRaceBridge")
	if bridge != null and bool(bridge.call("is_web_session")):
		if bool(bridge.call("is_race_session")):
			prepare_web_race(bridge)
		else:
			start_slice(int(bridge.call("get_run_seed")))
	else:
		var seed := int(get_tree().get_meta("next_endless_seed", 20260728))
		if get_tree().has_meta("next_endless_seed"):
			get_tree().remove_meta("next_endless_seed")
		start_slice(seed)


func prepare_web_race(bridge: Node) -> bool:
	if _race_prepared:
		return false
	_web_race_bridge = bridge
	var snapshot := start_slice(int(bridge.call("get_run_seed")))
	_race_prepared = true
	_modal_kind = &"race_waiting"
	_set_combat_suspended(true)
	audio_director.set_music_context(&"paused")
	presentation.show_result({
		"title": "好友无尽 · 等待出发",
		"body": "双方准备完成后，统一倒计时。\n同一种子、相同基础机体；按有效战斗时间比较。",
		"accent": FoldlightTheme.FOLD,
		"allow_retry": false, "allow_title": false,
	})
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
	presentation.show_hud()
	combat_runtime.set_active(true)
	player.set_play_enabled(true)
	_restore_survival_music()
	_refresh_hud()


func stop_web_race(reason: String) -> void:
	_cancel_reward_entry()
	_clear_pending_spawns()
	run_ended = true
	player.set_play_enabled(false)
	combat_runtime.set_active(false)
	controller.exit_mode(StringName(reason))
	_modal_kind = &"race_finished"
	_modal_options.clear()
	audio_director.set_music_context(&"defeat" if reason in ["player_defeated", "abandoned", "forfeit", "disconnected"] else &"victory")
	presentation.show_result({
		"title": "灯火熄灭" if reason == "player_defeated" else "好友对局已结束",
		"body": "有效航行 %s · 击破 %d\n请在联机房间查看成绩。本局不能重新开始。" % [_format_time(controller.evolution.survival_seconds), controller.defeated_total],
		"allow_retry": false, "allow_title": false,
	})


func get_race_stats() -> Dictionary:
	var pause_reason := ""
	if run_ended:
		pause_reason = "finished"
	elif not _race_started and _web_race_bridge != null:
		pause_reason = "waiting"
	elif _modal_kind in [&"reward", &"objective_complete"]:
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
	_clear_pending_spawns()
	_distant_enemy_age.clear()
	_defeat_serial = 0
	_population_clock = 0.0
	_boss_director.reset(seed)
	_boss_placement_retry = 0.0
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
	_barrage_elite_introduced = false
	_bomber_introduced = false
	player.set_debug_invincible(false)
	controller.map_runtime.build_physics_walls = false
	controller.map_runtime.draw_cover_visuals = false
	controller.select_map_for_seed(seed)
	_objective_target = null
	_zone_exposure.reset()
	_safe_route_clock = 0.0
	var room_errors := world.load_room(
		player,
		StringName("endless_%s" % controller.map_definition.map_id),
		controller.map_definition.bounds.size,
		_build_room_terrain(),
		Color("55b8a8"),
		seed,
		controller.map_definition.region_style,
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
	_claiming_reward = false
	presentation.reset_feedback()
	presentation.show_hud()
	_transitioning_to_title = false
	var snapshot := controller.enter_mode(seed, player)
	_bombardment.configure(controller.map_definition, controller.map_runtime, seed)
	combat_runtime.directed_spawn_validator = _minion_position_is_safe
	player.weapon_mount.set_weapon_levels(controller.weapon_levels)
	player.active_item_slot.restore_collection(snapshot)
	_refresh_active_inventory()
	_refresh_combined_modifiers()
	_report_population()
	controller.force_next_wave()
	_restore_survival_music()
	_refresh_hud()
	return snapshot


func _physics_process(delta: float) -> void:
	if run_ended or not _modal_kind.is_empty() or not controller.active:
		return
	if _combat_host_suspended():
		return
	_population_clock -= delta
	if _population_clock <= 0.0:
		_retire_distant_enemies(0.5)
		_update_boss_navigation()
		_population_clock = 0.5
	_report_population()
	_report_escort_pressure()
	controller.advance_simulation(delta, player.global_position)
	# Completing a mission synchronously opens a reward modal. Do not apply
	# environmental damage after that modal has suspended combat this frame.
	if run_ended or not _modal_kind.is_empty() or not controller.active:
		return
	_update_zone_exposure(delta)
	if run_ended:
		return
	_ensure_storm_support(delta)
	_music_sample_clock -= delta
	if _music_sample_clock <= 0.0:
		_music_sample_clock = 1.0
		audio_director.set_intensity(_survival_music_pressure())
	_hud_clock -= delta
	if _hud_clock <= 0.0:
		_hud_clock = 0.10
		_refresh_hud()


func _process(delta: float) -> void:
	_capture_sfx_cooldown = maxf(0.0, _capture_sfx_cooldown - delta)
	_kill_shake_cooldown = maxf(0.0, _kill_shake_cooldown - delta)
	_return_kick_cooldown = maxf(0.0, _return_kick_cooldown - delta)
	_try_present_pending_reward()
	_advance_reward_completion(delta)
	_advance_spawn_queue(delta)
	_advance_encounters(delta)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_application_suspended = true
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_application_suspended = false


func _combat_host_suspended() -> bool:
	# A race's rotate prompt or host dialog cancels touch input, not combat.
	# Keep its score clock, reinforcements and hazards advancing together while
	# the engine is ticking. Actual reward/waiting/result modals own their pause.
	return _web_race_bridge == null and (_application_suspended or (_touch_controls != null and bool(_touch_controls.call("is_host_suspended"))))


func _advance_reward_completion(delta: float) -> void:
	if run_ended or _transitioning_to_title or not controller.active or _modal_kind != &"objective_complete":
		return
	if not is_inside_tree() or is_queued_for_deletion() or get_tree().paused or _application_suspended or not is_finite(delta) or delta <= 0.0:
		return
	if _touch_controls != null and bool(_touch_controls.call("is_host_suspended")):
		return
	# A background return or one long frame cannot skip the completion beat.
	var step := minf(minf(delta, 0.10), _reward_completion_remaining)
	controller.advance_presentation(step)
	_reward_completion_remaining = maxf(0.0, _reward_completion_remaining - step)
	if _reward_completion_remaining <= 0.00001:
		_reward_completion_remaining = 0.0
		_modal_kind = &"reward"
		_refresh_active_inventory()
		presentation.show_reward(_reward_card_choices(), _reward_objective_title, _reward_ui_metadata())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# Audio remains available while a reward or pause owns the gameplay input.
	if event.is_action_pressed(&"mute_audio"):
		get_viewport().set_input_as_handled()
		audio_director.toggle_mute()
		return
	if event.is_action_pressed(&"pause_game"):
		# Consume before a listener can change or detach the scene.
		get_viewport().set_input_as_handled()
		if _modal_kind == &"settings":
			_on_settings_back_requested(&"pause")
		elif _modal_kind == &"pause":
			_resume_game()
		else:
			_pause_game()
	elif not _modal_kind.is_empty():
		# Shared presentation owns menu focus/confirmation. No combat input
		# may escape a waiting, reward, settings or result overlay.
		get_viewport().set_input_as_handled()


func _pause_game() -> void:
	if _web_race_bridge != null:
		if _web_race_bridge.has_method("is_native_session") and _web_race_bridge.is_native_session():
			_web_race_bridge.request_native_leave()
		else:
			presentation.show_notice("好友竞赛", "不能手动暂停；奖励选择不计时。弃赛请使用网页房间。")
		return
	if run_ended or _modal_kind not in [&"", &"objective_complete"] or not controller.active:
		return
	_paused_modal_kind = _modal_kind
	if _modal_kind.is_empty():
		_cancel_reward_entry()
	_modal_kind = &"pause"
	_set_combat_suspended(true)
	_refresh_active_inventory()
	presentation.show_pause()
	audio_director.set_music_context(&"paused")


func _resume_game() -> void:
	if _modal_kind != &"pause":
		return
	_modal_kind = _paused_modal_kind
	_paused_modal_kind = &""
	presentation.show_hud()
	if _modal_kind != &"objective_complete":
		_set_combat_suspended(false)
	else:
		audio_director.set_music_context(&"reward")
	_try_present_pending_reward()
	_refresh_hud()


func _on_settings_requested() -> void:
	if _modal_kind != &"pause" or _web_race_bridge != null:
		return
	_modal_kind = &"settings"
	presentation.show_settings(profile_manager.settings.duplicate(true), &"pause")


func _on_settings_back_requested(_return_screen: StringName) -> void:
	if _modal_kind != &"settings":
		return
	_modal_kind = &"pause"
	presentation.show_pause()


func _on_setting_adjust_requested(setting_key: StringName, direction: int) -> void:
	if _modal_kind != &"settings":
		return
	var current: Variant = profile_manager.get_setting(setting_key)
	var value: Variant = current
	match setting_key:
		&"master_volume", &"music_volume", &"sfx_volume":
			value = clampf(float(current) + float(direction) * 0.1, 0.0, 1.0)
		&"screen_shake":
			value = clampf(float(current) + float(direction) * 0.5, 0.0, 1.0)
		&"vibration", &"high_contrast", &"fullscreen":
			value = not bool(current)
	profile_manager.set_setting(setting_key, value)
	_apply_feedback_settings()
	presentation.refresh_settings(profile_manager.settings)
	audio_director.play_sfx(&"ui", 1.0 + float(direction) * 0.06, -7.0)


func _abandon_run() -> void:
	if _modal_kind == &"pause" and presentation.screen_kind == &"leave_confirmation" and _web_race_bridge == null:
		_finish_run(&"abandoned")


func _retry_run() -> void:
	if _modal_kind == &"game_over" and _web_race_bridge == null:
		start_slice(controller.run_seed)


func _return_to_title() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or _transitioning_to_title:
		return
	_cancel_reward_entry()
	_clear_pending_spawns()
	if _web_race_bridge != null:
		_web_race_bridge.call("finish_local", &"abandoned", "abandoned")
		return
	_transitioning_to_title = true
	audio_director.set_music_context(&"title", &"", 0.045)
	player.set_play_enabled(false)
	world.deactivate()
	controller.exit_mode(&"return_to_title")
	# Preserve the result's GUI touch-focus target until the input event batch
	# finishes; its emulated mouse release arrives before the raw touch release.
	call_deferred("_complete_title_transition")
	title_requested.emit()


func _complete_title_transition() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not _transitioning_to_title:
		return
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		_transitioning_to_title = false
		push_error("Unable to return to title: %s" % error_string(error))


func _on_enemy_wave_requested(request: Dictionary) -> void:
	var limit := _effective_population_limit()
	var open_slots := maxi(0, mini(MAX_LIVE_ENEMIES, limit) - combat_runtime.enemies.size() - _pending_spawns.size())
	if open_slots <= 0:
		return
	var directed: Array[Dictionary] = []
	var has_barrage_elite := false
	var bomber_count := 0
	for enemy in combat_runtime.enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.definition.content_id == &"shutter_seraph":
			has_barrage_elite = true
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.definition.content_id == &"cinder_mine":
			bomber_count += 1
	for pending in _pending_spawns:
		var pending_id := StringName(pending.get("enemy_id", &""))
		has_barrage_elite = has_barrage_elite or pending_id == &"shutter_seraph"
		if pending_id == &"cinder_mine":
			bomber_count += 1
	var entries_variant: Variant = request.get("entries", [])
	if entries_variant is Array:
		for entry_variant: Variant in entries_variant:
			if directed.size() >= open_slots:
				break
			if not entry_variant is Dictionary:
				continue
			var entry := (entry_variant as Dictionary).duplicate(true)
			if bool(entry.get("is_captain", false)) and _has_pending_captain(StringName(entry.get("captain_id", &""))):
				continue
			# Keep the final actor slot available for a task captain. Its ID is
			# acknowledged only after the shared factory actually creates it.
			if not bool(entry.get("is_captain", false)) and directed.size() >= maxi(0, open_slots - 1):
				continue
			entry["spawn_position"] = Vector2(entry.get("position", Vector2.ZERO))
			if bool(entry.get("is_captain", false)):
				_relocate_crowded_captain(entry)
			if not _spawn_position_is_safe(entry):
				continue
			if StringName(entry.get("enemy_id", &"")) == &"shutter_seraph":
				if has_barrage_elite:
					continue
				has_barrage_elite = true
				if not _barrage_elite_introduced:
					_barrage_elite_introduced = true
					presentation.show_notice("精英 · 暴雨折翼", "闭翼时无敌；张翼扫射时核心暴露。收纳弹幕，趁它开火返光！")
			if StringName(entry.get("enemy_id", &"")) == &"cinder_mine":
				if bomber_count >= 2:
					continue
				bomber_count += 1
				if not _bomber_introduced:
					_bomber_introduced = true
					presentation.show_notice("烬火纸雷 · 定点自爆", "红圈亮起后有 1.5 秒离圈；冲刺避开或提前击破，不会殉爆。")
			directed.append(entry)
	_queue_directed_spawns(directed)
	_report_population()


func _has_pending_captain(identity: StringName) -> bool:
	return _pending_spawns.any(func(entry: Dictionary) -> bool: return bool(entry.get("is_captain", false)) and StringName(entry.get("captain_id", &"")) == identity)


func _spawn_position_is_safe(entry: Dictionary) -> bool:
	var point := Vector2(entry.get("spawn_position", entry.get("position", Vector2.ZERO)))
	if not point.is_finite() or controller.map_runtime.is_point_blocked(point, 40.0) or controller.zones.is_point_reserved(point, 40.0):
		return false
	# Authored task captains have a fixed, marked site; ordinary reinforcements
	# must stay clear even when the player walks into their warning during entry.
	var clearance := 180.0 if bool(entry.get("is_captain", false)) else (360.0 if entry.has("objective_support") else controller.config.spawn_safe_distance)
	return point.distance_squared_to(player.global_position) >= clearance * clearance


func _relocate_crowded_captain(entry: Dictionary) -> void:
	if _spawn_position_is_safe(entry):
		return
	var origin := Vector2(entry["spawn_position"])
	for index in 24:
		var angle := TAU * float(posmod(controller.run_seed + index, 24)) / 24.0
		entry["spawn_position"] = origin + Vector2.from_angle(angle) * 360.0
		if _spawn_position_is_safe(entry):
			return
	entry["spawn_position"] = origin


func _queue_directed_spawns(entries: Array[Dictionary]) -> void:
	for source in entries:
		if _pending_spawns.size() + combat_runtime.enemies.size() >= MAX_LIVE_ENEMIES:
			break
		var entry := source.duplicate(true)
		entry["remaining"] = SPAWN_WARNING_SECONDS
		var marker := FoldlightSpawnTelegraph.new()
		world.room_runtime.add_child(marker)
		marker.configure(entry, SPAWN_WARNING_SECONDS)
		marker.use_external_clock()
		marker.set_simulation_active(_modal_kind.is_empty())
		entry["marker"] = weakref(marker)
		_pending_spawns.append(entry)


func _clear_pending_spawns() -> void:
	for entry in _pending_spawns:
		_release_spawn_marker(entry)
	_pending_spawns.clear()
	_clear_boss_warning()
	if is_instance_valid(_bombardment):
		_bombardment.cancel()


func _release_spawn_marker(entry: Dictionary) -> void:
	var reference: Variant = entry.get("marker")
	var marker: Node = reference.get_ref() if reference is WeakRef else null
	if is_instance_valid(marker) and not marker.is_queued_for_deletion():
		marker.queue_free()


func _advance_spawn_queue(delta: float) -> void:
	if run_ended or not _modal_kind.is_empty() or not combat_runtime.active or not is_finite(delta) or delta <= 0.0:
		return
	if _combat_host_suspended():
		return
	# Advance once per rendered frame, so catch-up physics and a background
	# return cannot consume an entire warning before the player sees it.
	var warning_step := minf(delta, 0.1)
	for entry in _pending_spawns:
		entry["remaining"] = maxf(0.0, float(entry["remaining"]) - warning_step)
		var reference: Variant = entry.get("marker")
		var marker: Node = reference.get_ref() if reference is WeakRef else null
		if is_instance_valid(marker) and not marker.is_queued_for_deletion():
			marker.set_warning_remaining(float(entry["remaining"]))
	var issued := 0
	while not _pending_spawns.is_empty() and float(_pending_spawns[0]["remaining"]) <= 0.0 and issued < SPAWNS_PER_STEP:
		var entry: Dictionary = _pending_spawns.pop_front()
		_release_spawn_marker(entry)
		var objective := controller.objectives.get_snapshot()
		if bool(entry.get("is_captain", false)) and (not bool(objective.get("target_active", false)) or StringName(objective.get("target_id", &"")) != StringName(entry.get("captain_id", &""))):
			continue
		if entry.has("objective_support") and (not bool(objective.get("target_active", false)) or StringName(objective.get("id", &"")) != StringName(entry["objective_support"])):
			continue
		if not _spawn_position_is_safe(entry):
			continue
		entry.erase("marker")
		entry.erase("remaining")
		var batch: Array[Dictionary] = [entry]
		var spawned := combat_runtime.spawn_directed_wave(batch)
		issued += spawned.size()
		for actor: Node2D in spawned:
			if bool(entry.get("is_captain", false)):
				controller.confirm_captain_spawned(StringName(entry.get("captain_id", &"")))


func _boss_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in combat_runtime.enemies:
		if actor is FoldlightRogueBossActor and is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.health > 0.0:
			result.append(actor.get_combat_snapshot())
	return result


func _effective_population_limit() -> int:
	var limit := int(controller.evolution.get_enemy_snapshot().get("population_limit", MAX_LIVE_ENEMIES))
	var boss_count := maxi(_boss_snapshots().size(), _boss_entries.size())
	# Bosses replace some ordinary pressure. They do not bypass the same frame
	# budget by adding three full waves on top of a crowded battlefield.
	return maxi(16, mini(MAX_LIVE_ENEMIES, limit) - boss_count * 8)


func _minion_position_is_safe(entry: Dictionary) -> bool:
	var point := Vector2(entry.get("spawn_position", Vector2.INF))
	return point.is_finite() and point.distance_to(player.global_position) >= 180.0 and not controller.map_runtime.is_point_blocked(point, 40.0) and not controller.zones.is_point_reserved(point, 40.0)


func _report_escort_pressure() -> void:
	var objective := controller.objectives.get_snapshot()
	if StringName(objective.get("kind", &"")) != &"escort" or not bool(objective.get("target_active", false)):
		return
	var point := Vector2(objective.get("escort_position", Vector2.INF))
	var count := 0
	for actor in combat_runtime.enemies:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and float(actor.get("health")) > 0.0 and actor.global_position.distance_squared_to(point) < 180.0 * 180.0:
			count += 1
	controller.report_escort_pressure(count)


func _clear_boss_warning() -> void:
	for entry in _boss_entries:
		_release_spawn_marker(entry)
	_boss_entries.clear()


func _plan_boss_positions() -> bool:
	_clear_boss_warning()
	var occupied := PackedVector2Array()
	var wave := int(_boss_director.get_snapshot().wave_index)
	for boss_id in _boss_director.planned_boss_ids():
		var chosen := Vector2.INF
		for ring in 3:
			for index in 32:
				var angle := TAU * float(posmod(controller.run_seed + wave * 7 + index, 32)) / 32.0
				var candidate := player.global_position + Vector2.from_angle(angle) * (760.0 + 220.0 * ring)
				if controller.map_runtime.is_point_blocked(candidate, 96.0) or controller.zones.is_point_reserved(candidate, 96.0):
					continue
				var crowded := false
				for other in occupied:
					crowded = crowded or other.distance_squared_to(candidate) < 480.0 * 480.0
				if crowded or controller.map_runtime.find_cover_route(candidate, _boss_navigation_goal(), 90.0).is_empty():
					continue
				chosen = candidate
				break
			if chosen.is_finite():
				break
		if not chosen.is_finite():
			_clear_boss_warning()
			return false
		occupied.append(chosen)
		var scale := minf(2.5, 0.72 + 0.12 * float(wave - 1))
		if _boss_director.planned_boss_ids().size() > 1:
			scale *= 0.82
		var entry := {
			"boss_id": boss_id, "is_boss": true, "boss_wave": wave, "threat_cost": 12,
			"spawn_position": chosen, "position": chosen, "role": FoldlightRogueEnemyDefinition.EnemyRole.BOSS,
			"boss_options": {"health_scale": scale, "endless_roam": true, "arena_pressure": false,
				"intro_delay": float(occupied.size() - 1) * 0.65,
				"local_arena": Rect2(chosen - Vector2(900, 700), Vector2(1800, 1400)).intersection(controller.map_definition.bounds)},
		}
		var marker := FoldlightSpawnTelegraph.new()
		world.room_runtime.add_child(marker)
		marker.configure(entry, FoldlightEndlessBossDirector.WARNING_SECONDS)
		marker.scale = Vector2(2.0, 2.0)
		marker.use_external_clock()
		entry["marker"] = weakref(marker)
		_boss_entries.append(entry)
	return true


func _advance_encounters(delta: float) -> void:
	if run_ended or not _modal_kind.is_empty() or not controller.active or not combat_runtime.active or _combat_host_suspended():
		return
	if get_tree().paused or not is_finite(delta) or delta <= 0.0:
		return
	_advance_boss_encounter(delta)
	if run_ended or not _modal_kind.is_empty():
		return
	var objective := controller.objectives.get_snapshot()
	var impacts := _bombardment.advance(delta, controller.evolution.survival_seconds, player.global_position, objective.get("protected_points", PackedVector2Array()), _boss_snapshots().size())
	for impact in impacts:
		if player.global_position.distance_to(Vector2(impact.position)) <= float(impact.radius) + player.get_hit_radius():
			combat_runtime._try_hit_player(player.global_position - Vector2(impact.position))
			break


func _advance_boss_encounter(delta: float) -> void:
	_boss_placement_retry = maxf(0.0, _boss_placement_retry - minf(delta, 0.1))
	if _boss_placement_retry > 0.0:
		return
	var prior := StringName(_boss_director.get_snapshot().state)
	var level := int(controller.evolution.get_experience_snapshot().get("level", 1))
	var boss_state := _boss_director.advance(delta, level, controller.evolution.survival_seconds)
	if StringName(boss_state.state) == &"warning" and (prior != &"warning" or _boss_entries.is_empty()):
		if not _plan_boss_positions():
			_boss_director.retry_warning()
			_boss_placement_retry = 1.0
		else:
			presentation.show_notice(str(boss_state.title), "落点已标记 · 收纳弹幕，趁破绽返光")
	for entry in _boss_entries:
		var marker: Node = (entry.marker as WeakRef).get_ref()
		if is_instance_valid(marker):
			marker.set_warning_remaining(float(boss_state.warning_remaining))
	if StringName(boss_state.state) == &"ready":
		var positions_valid := _boss_entries.size() == _boss_director.planned_boss_ids().size()
		for entry in _boss_entries:
			var point := Vector2(entry.spawn_position)
			positions_valid = positions_valid and point.distance_to(player.global_position) >= 300.0 and not controller.zones.is_point_reserved(point, 96.0)
		if not positions_valid:
			_boss_director.retry_warning()
			if not _plan_boss_positions():
				_boss_placement_retry = 1.0
		else:
			# Reserve real actor slots. Only surplus distant ordinary reinforcements
			# are retired; captains and existing bosses are never removed here.
			for entry in _pending_spawns:
				_release_spawn_marker(entry)
			_pending_spawns.clear()
			var candidates := combat_runtime.enemies.duplicate()
			var live_threat := 0
			for actor in candidates:
				live_threat += _actor_threat(actor)
			var threat_limit := int(controller.evolution.get_enemy_snapshot().get("threat_limit", 104))
			var boss_threat := _boss_entries.size() * 12
			candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(player.global_position) > b.global_position.distance_squared_to(player.global_position))
			for actor in candidates:
				if combat_runtime.enemies.size() + _boss_entries.size() <= _effective_population_limit() and live_threat + boss_threat <= threat_limit:
					break
				var cost := _actor_threat(actor)
				if combat_runtime.retire_directed_enemy(actor):
					live_threat -= cost
			if combat_runtime.enemies.size() + _boss_entries.size() <= _effective_population_limit() and live_threat + boss_threat <= threat_limit:
				var entries: Array[Dictionary] = []
				for entry in _boss_entries:
					var source := entry.duplicate(true)
					source.erase("marker")
					entries.append(source)
				var spawned := combat_runtime.spawn_directed_wave(entries)
				var identities: Array[StringName] = []
				for actor in spawned:
					identities.append(StringName(actor.get("actor_id")))
				if _boss_director.confirm_spawned(identities):
					_clear_boss_warning()
					_restore_survival_music()
					_refresh_hud()
				else:
					for actor in spawned:
						combat_runtime.enemies.erase(actor)
						actor.queue_free()
					_boss_director.retry_warning()
					_boss_placement_retry = 1.0


func _boss_navigation_goal() -> Vector2:
	var point := player.global_position
	if not controller.map_runtime.is_point_blocked(point, 90.0):
		return point
	for ring in 2:
		for index in 12:
			var candidate := point + Vector2.from_angle(TAU * index / 12.0) * (128.0 + ring * 96.0)
			if not controller.map_runtime.is_point_blocked(candidate, 90.0):
				return candidate
	return point


func _update_boss_navigation() -> void:
	var goal := _boss_navigation_goal()
	for actor in combat_runtime.enemies:
		if not actor is FoldlightRogueBossActor or not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var route := controller.map_runtime.find_cover_route(actor.global_position, goal, 90.0)
		actor.set_navigation_target(route[0] if not route.is_empty() else actor.global_position)


func _actor_threat(actor: Node2D) -> int:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or float(actor.get("health")) <= 0.0:
		return 0
	var definition: Variant = actor.get("definition")
	var entry: Dictionary = actor.get_meta("directed_spawn_entry", {})
	var fallback := 12 if actor is FoldlightRogueBossActor else (int(definition.threat_cost) if definition != null else 1)
	return 6 if bool(entry.get("is_captain", false)) else int(entry.get("threat_cost", fallback))


func _report_population() -> void:
	var alive := 0
	var threat := 0
	for actor: Node2D in combat_runtime.enemies:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or float(actor.get("health")) <= 0.0:
			continue
		alive += 1
		threat += _actor_threat(actor)
	var pending_threat := 0
	for entry in _pending_spawns:
		pending_threat += 6 if bool(entry.get("is_captain", false)) else int(entry.get("threat_cost", controller.THREAT_COSTS.get(StringName(entry.get("enemy_id", &"drifter")), 1)))
	controller.report_population({"alive_count": alive, "pending_count": _pending_spawns.size() + _boss_entries.size(), "threat_total": threat, "pending_threat": pending_threat + _boss_entries.size() * 12})
	combat_runtime.directed_spawn_allowance = maxi(0, _effective_population_limit() - alive - _pending_spawns.size() - _boss_entries.size())
	combat_runtime.directed_threat_allowance = maxi(0, int(controller.evolution.get_enemy_snapshot().get("threat_limit", 104)) - threat - pending_threat - _boss_entries.size() * 12)


func _retire_distant_enemies(delta: float) -> void:
	var retained: Dictionary = {}
	var objective := controller.objectives.get_snapshot()
	for actor: Node2D in combat_runtime.enemies.duplicate():
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		if actor is FoldlightRogueBossActor:
			continue
		var entry: Dictionary = actor.get_meta("directed_spawn_entry", {})
		if bool(entry.get("is_captain", false)) or bool(entry.get("is_objective_target", false)) or (entry.has("objective_support") and StringName(entry["objective_support"]) == StringName(objective.get("id", &"")) and bool(objective.get("target_active", false))):
			continue
		if actor.global_position.distance_squared_to(player.global_position) <= DISTANT_RETIRE_DISTANCE * DISTANT_RETIRE_DISTANCE:
			continue
		var identity := actor.get_instance_id()
		var age := float(_distant_enemy_age.get(identity, 0.0)) + delta
		if age >= DISTANT_RETIRE_SECONDS:
			combat_runtime.retire_directed_enemy(actor)
		else:
			retained[identity] = age
	_distant_enemy_age = retained


func _on_projectile_captured(captured_count: int, _position: Vector2) -> void:
	controller.report_projectiles_absorbed(1)
	if _capture_sfx_cooldown <= 0.0 and _feedback_is_live():
		_capture_sfx_cooldown = 0.065
		audio_director.play_sfx(&"capture", 0.90 + minf(0.32, float(captured_count) * 0.025), -10.0)


func _on_enemy_defeated_detailed(enemy_id: StringName, entry: Dictionary) -> void:
	if bool(entry.get("is_objective_target", false)) or not bool(entry.get("grants_kill_credit", true)):
		return
	var report := entry.duplicate(true)
	report["enemy_id"] = enemy_id
	_defeat_serial += 1
	report["defeat_serial"] = _defeat_serial
	report["defeat_reason"] = &"player"
	controller.report_enemy_defeated(report)
	if bool(entry.get("is_boss", false)) and _boss_director.report_defeated(StringName(entry.get("actor_id", &"")), controller.evolution.survival_seconds):
		var wave := int(_boss_director.get_snapshot().wave_index)
		controller.queue_boss_reward(enemy_id, "首领遭遇 %d · 已击破" % wave, wave)
		_restore_survival_music()
	if _kill_shake_cooldown <= 0.0:
		var shake := 0.34 if bool(entry.get("is_captain", false)) else 0.16
		camera.add_trauma(shake * _feedback_motion_scale)
		_kill_shake_cooldown = 0.075


func _on_player_hit(health_remaining: int) -> void:
	presentation.flash_player_damage()
	audio_director.play_sfx(&"hurt", 0.96, -4.0)
	camera.add_trauma(0.62 * _feedback_motion_scale)
	camera.add_hit_kick(_feedback_motion_scale)
	if _feedback_vibration:
		Input.start_joy_vibration(0, 0.22, 0.46, 0.16)
	_refresh_hud()
	if health_remaining <= 0:
		_finish_run()


func _apply_feedback_settings() -> void:
	var profile := get_node_or_null("/root/ProfileManager")
	_feedback_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0
	_feedback_vibration = bool(profile.call("get_setting", &"vibration", true)) if profile != null else true
	player.set_feedback_motion_scale(_feedback_motion_scale)
	controller.map_runtime.set_motion_reduced(_feedback_motion_scale <= 0.0)
	if is_instance_valid(_objective_target):
		_objective_target.set_feedback_motion_scale(_feedback_motion_scale)


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
		_fold_task_id = StringName(controller.objectives.get_snapshot().get("id", &""))
		_fold_release_serial += 1
		_pending_fold_release_serial = _fold_release_serial
		audio_director.play_sfx(&"fold", 1.0, -8.0)


func _on_feedback_fold_released(captured_count: int, _charge_ratio: float) -> void:
	var task_id := _fold_task_id
	var release_id := _pending_fold_release_serial
	_fold_task_id = &""
	_pending_fold_release_serial = 0
	if not _feedback_is_live():
		return
	audio_director.play_sfx(&"release" if captured_count > 0 else &"empty", 0.90 + minf(0.25, float(captured_count) * 0.015), -7.0 if captured_count > 0 else -12.0)
	if captured_count > 0:
		camera.add_trauma(minf(0.30, 0.10 + float(captured_count) * 0.018) * _feedback_motion_scale)
		if _feedback_vibration:
			var strength := minf(0.34, 0.16 + float(captured_count) * 0.012)
			Input.start_joy_vibration(0, strength * 0.55, strength, 0.11)
		controller.report_returned_light(captured_count, task_id, release_id)


func _on_feedback_focus_empty(_captured_count: int, _charge_ratio: float) -> void:
	_fold_task_id = &""
	_pending_fold_release_serial = 0
	if _feedback_is_live():
		audio_director.play_sfx(&"empty", 0.86, -12.0)


func _on_player_evolution_changed(_snapshot: Dictionary) -> void:
	_refresh_combined_modifiers()


func _on_mission_reward_offered(_options: Array[Dictionary], _objective_snapshot: Dictionary) -> void:
	_try_present_pending_reward()


func _try_present_pending_reward() -> void:
	if run_ended or _transitioning_to_title or not controller.active or not _modal_kind.is_empty():
		return
	var pending := controller.peek_pending_reward()
	if pending.is_empty():
		return
	var options: Array[Dictionary] = []
	for option: Dictionary in pending.get("options", []):
		options.append(option.duplicate(true))
	if options.is_empty():
		return
	_modal_kind = &"objective_complete"
	_modal_options = options
	_reward_token = String(pending.get("reward_token", ""))
	_reward_context = pending.duplicate(true)
	_claiming_reward = false
	_reward_completion_remaining = OBJECTIVE_COMPLETE_SECONDS
	_reward_objective_title = str(pending.get("title", "航行补给"))
	_set_combat_suspended(true)
	presentation.show_hud()
	_refresh_hud()
	audio_director.set_music_context(&"reward")
	audio_director.play_sfx(&"ui", 1.18, -8.0)


func _reward_ui_metadata() -> Dictionary:
	return {"source": _reward_context.get("source", &"mission"), "title": _reward_objective_title, "level": _reward_context.get("level", 1), "heal_on_claim": _reward_context.get("heal_on_claim", 0), "current_health": player.health, "max_health": player.max_health}


func _reward_card_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for option: Dictionary in _modal_options:
		var choice := option.duplicate(true)
		choice["content_id"] = StringName(option.get("id", &""))
		if StringName(option.get("choice_kind", &"")) not in [&"weapon", &"active"]:
			var source := StringName(_reward_context.get("source", &"mission"))
			choice["display_rarity"] = "%s · %s" % [str(option.get("lane_title", "成长")), "击破升级" if source == &"kill_level" else ("首领战利品" if source == &"boss" else "任务强化")]
			choice["display_level"] = "刻印  Lv.%d · 本局累积" % int(option.get("next_level", 1))
			choice["accent"] = FoldlightTheme.GOLD if StringName(option.get("lane_id", &"")) == &"sustain" else FoldlightTheme.FOLD
		choices.append(choice)
	return choices


func _on_mission_reward_claimed(reward: Dictionary) -> void:
	var health_before := player.health
	if StringName(reward.get("choice_kind", &"")) == &"weapon":
		player.weapon_mount.set_weapon_levels(controller.weapon_levels)
	elif StringName(reward.get("choice_kind", &"")) == &"active":
		player.active_item_slot.acquire(FoldlightRogueContentCatalog.active_item_by_id(StringName(reward.get("id", &""))))
	controller.set_active_collection(player.active_item_slot.get_save_snapshot())
	_refresh_active_inventory()
	_refresh_combined_modifiers()
	var reward_modifiers_variant: Variant = reward.get("modifiers", {})
	var reward_modifiers := reward_modifiers_variant as Dictionary if reward_modifiers_variant is Dictionary else {}
	var healing := int(round(float(reward_modifiers.get("heal", 0.0)))) + int(reward.get("heal_on_claim", 0))
	player.health = mini(player.max_health, health_before + healing)
	var actual_heal := maxi(0, player.health - health_before)
	var title := "已获得【%s】%s  Lv.%d" % [
		String(reward.get("lane_title", "成长")),
		String(reward.get("title", "进化")),
		int(reward.get("level", 1)),
	]
	var detail := str(reward.get("description", ""))
	if healing > 0:
		detail += "\n回复生命 +%d" % actual_heal if actual_heal > 0 else "\n生命已满"
	presentation.show_notice(title, detail)


func _on_reward_chosen(reward_id: StringName) -> void:
	if run_ended or _modal_kind != &"reward" or _claiming_reward:
		return
	var offered := false
	for choice: Dictionary in _modal_options:
		if StringName(choice.get("id", &"")) == reward_id:
			offered = true
			break
	if not offered:
		return
	# Shared cards guard entry, wait for input release and finish confirmation
	# before emitting. Lock again here before synchronous controller signals.
	_claiming_reward = true
	if controller.claim_pending_reward(_reward_token, reward_id).is_empty():
		_claiming_reward = false
		presentation.show_reward(_reward_card_choices(), _reward_objective_title, _reward_ui_metadata())
		return
	if run_ended or _modal_kind != &"reward":
		return
	_modal_kind = &""
	_modal_options.clear()
	_reward_token = ""
	_reward_context.clear()
	presentation.show_hud()
	_try_present_pending_reward()
	if _modal_kind.is_empty():
		_set_combat_suspended(false)
	_refresh_hud()


func _cancel_reward_entry() -> void:
	_claiming_reward = true
	_reward_completion_remaining = 0.0
	_reward_objective_title = ""
	_reward_token = ""
	_reward_context.clear()
	_paused_modal_kind = &""
	_fold_task_id = &""
	_pending_fold_release_serial = 0
	presentation.cancel_reward_selection()


func _refresh_active_inventory() -> void:
	presentation.set_active_inventory(player.get_active_inventory_snapshot())


func _on_active_relic_selected(item_id: StringName) -> void:
	if run_ended or _transitioning_to_title or not controller.active:
		return
	var selecting_reward := _modal_kind == &"reward" and presentation.screen_kind == &"reward" and not _claiming_reward
	var selecting_pause := _modal_kind == &"pause" and presentation.screen_kind == &"pause" and _web_race_bridge == null
	if not (selecting_reward or selecting_pause) or not player.active_item_slot.select(item_id):
		return
	controller.set_active_collection(player.active_item_slot.get_save_snapshot())
	_refresh_active_inventory()
	_refresh_hud()


func _finish_run(reason: StringName = &"player_defeated") -> void:
	_cancel_reward_entry()
	_clear_pending_spawns()
	if run_ended:
		return
	run_ended = true
	player.set_play_enabled(false)
	combat_runtime.set_active(false)
	controller.exit_mode(reason)
	audio_director.set_music_context(&"defeat")
	if _web_race_bridge != null:
		_web_race_bridge.call("finish_local", &"dead", "player_defeated")
		return
	_modal_kind = &"game_over"
	_modal_options.clear()
	presentation.show_result({
		"title": "本次航行已结束" if reason == &"abandoned" else "这盏灯沉入了纸海",
		"body": "无尽挑战\n航行时间  %s\n击破敌人  %d\n威胁阶段  %d · 收纳进化  %d" % [
			_format_time(controller.evolution.survival_seconds), controller.defeated_total,
			int(controller.evolution.get_enemy_snapshot().get("stage", 0)),
			int(controller.evolution.get_player_snapshot().get("stage", 0)),
		],
		"retry_label": "再次挑战",
	})


func _set_combat_suspended(suspended: bool) -> void:
	if suspended:
		_fold_task_id = &""
		_pending_fold_release_serial = 0
		player.suspend_for_overlay()
		combat_runtime.set_active(false)
	else:
		combat_runtime.set_active(true)
		player.resume_from_overlay(0.75)
		_restore_survival_music()


func _restore_survival_music() -> void:
	# Music reads the authored map choice; it never consumes the seeded
	# simulation RNG or changes the identical battlefield used by race peers.
	var region: StringName = {
		&"ink_city": &"inverted_ink_city",
		&"sun_court": &"nameless_sun_court",
	}.get(controller.map_definition.region_style, controller.map_definition.region_style)
	audio_director.set_music_context(&"boss" if not _boss_snapshots().is_empty() else &"endless", region, _survival_music_pressure())
	_music_sample_clock = 1.0


func _survival_music_pressure() -> float:
	var stage := int(controller.evolution.get_enemy_snapshot().get("stage", 0))
	var pressure := 0.24 + minf(0.30, controller.evolution.survival_seconds / 720.0 * 0.30)
	pressure += minf(0.12, float(controller.wave_sequence) / 36.0 * 0.12)
	pressure += minf(0.20, float(combat_runtime.enemies.size()) * 0.005)
	pressure += minf(0.10, float(stage) * 0.015)
	pressure += float(_boss_snapshots().size()) * 0.12
	return clampf(pressure, 0.0, 0.96)


func _refresh_combined_modifiers() -> void:
	_combined_modifiers.clear()
	var axes: Array[Dictionary] = [
		controller.evolution.get_player_snapshot().get("total_modifiers", {}) as Dictionary,
		controller.evolution.get_mission_snapshot().get("total_modifiers", {}) as Dictionary,
		controller.evolution.get_experience_snapshot().get("total_modifiers", {}) as Dictionary,
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


func _on_objective_started(objective: Dictionary) -> void:
	_retire_objective_target()
	_storm_support_count = 0
	_storm_support_clock = 0.0
	if StringName(objective.get("kind", &"")) == &"destroy_flag":
		var target := ObjectiveTarget.new()
		target.configure(objective)
		target.damage_reported.connect(controller.report_flag_damage)
		combat_runtime.register_objective_target(target, {
			"objective_id": objective.get("id", &""),
			"target_id": objective.get("target_id", &""),
			"is_objective_target": true,
		})
		_objective_target = target


func _on_objective_failed(objective: Dictionary) -> void:
	_retire_objective_target()
	var identity := StringName(objective.get("id", &""))
	var captain_id := StringName(objective.get("target_id", &""))
	for index in range(_pending_spawns.size() - 1, -1, -1):
		var entry: Dictionary = _pending_spawns[index]
		if (bool(entry.get("is_captain", false)) and StringName(entry.get("captain_id", &"")) == captain_id) or (entry.has("objective_support") and StringName(entry["objective_support"]) == identity):
			_release_spawn_marker(entry)
			_pending_spawns.remove_at(index)
	for actor: Node2D in combat_runtime.enemies.duplicate():
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var entry: Dictionary = actor.get_meta("directed_spawn_entry", {})
		if bool(entry.get("is_captain", false)) and StringName(entry.get("captain_id", &"")) == captain_id:
			combat_runtime.retire_directed_enemy(actor, true)
	_report_population()
	if not run_ended:
		presentation.show_notice("任务超时", "本次没有任务奖励，稍后出现新目标；航行继续。")


func _retire_objective_target() -> void:
	if is_instance_valid(_objective_target) and not _objective_target.is_queued_for_deletion():
		combat_runtime.unregister_objective_target(_objective_target)
	_objective_target = null


func _update_zone_exposure(delta: float) -> void:
	var closed := controller.zones.is_point_closed(player.global_position)
	var hits := _zone_exposure.advance(delta, closed)
	_safe_route_clock = maxf(0.0, _safe_route_clock - delta)
	if hits > 0 and player.take_hit():
		# Use the same health, invulnerability and feedback as ordinary hits.
		_on_player_hit(player.health)


func _ensure_storm_support(delta: float) -> void:
	_storm_support_clock -= delta
	if _storm_support_clock > 0.0:
		return
	_storm_support_clock = 4.0
	var objective := controller.objectives.get_snapshot()
	if StringName(objective.get("kind", &"")) != &"capture_storm" or not bool(objective.get("target_active", false)):
		return
	var center := Vector2(objective.get("target_position", Vector2.ZERO))
	if player.global_position.distance_to(center) > 800.0:
		return
	_storm_support_count = 0
	for actor: Node2D in combat_runtime.enemies:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and float(actor.get("health")) > 0.0:
			var entry: Dictionary = actor.get_meta("directed_spawn_entry", {})
			if entry.get("objective_support", &"") == objective.id:
				_storm_support_count += 1
	# Real shared shooters supply absorbable bullets even in a distant district.
	# Keep at most two alive, replacing defeated shooters on a four-second cadence
	# so automatic weapons cannot permanently exhaust the task's bullet supply.
	# Actual captured projectiles remain the sole progress source.
	for pending in _pending_spawns:
		if StringName(pending.get("objective_support", &"")) == StringName(objective.id):
			_storm_support_count += 1
	var population_limit := int(controller.evolution.get_enemy_snapshot().get("population_limit", MAX_LIVE_ENEMIES))
	var slots := mini(2 - _storm_support_count, maxi(0, population_limit - 1 - combat_runtime.enemies.size() - _pending_spawns.size()))
	_report_population()
	var population := controller.get_population_snapshot()
	var spare_threat := maxi(0, int(population["threat_limit"]) - int(population["threat_total"]) - int(population["pending_threat"]))
	slots = mini(slots, spare_threat / 2)
	var entries: Array[Dictionary] = []
	for index in 32:
		if entries.size() >= slots:
			break
		var angle := TAU * float(posmod(controller.run_seed + index + _storm_support_count * 13, 32)) / 32.0
		var candidate := center + Vector2.from_angle(angle) * 540.0
		if controller.map_runtime.is_point_blocked(candidate, 48.0) or controller.zones.is_point_reserved(candidate, 48.0):
			continue
		if player.global_position.distance_to(candidate) < 360.0 or not controller.map_runtime.has_line_of_sight(candidate, center, 12.0):
			continue
		if not entries.is_empty() and candidate.distance_to(Vector2(entries[0].spawn_position)) < 420.0:
			continue
		var health_scale := maxf(3.0, float(controller.evolution.get_enemy_snapshot().get("health_multiplier", 1.0)) * 3.0)
		entries.append({"enemy_id": &"fan", "spawn_position": candidate, "objective_support": objective.id, "health_multiplier": health_scale, "is_captain": false})
	_queue_directed_spawns(entries)
	_storm_support_count += entries.size()
	_report_population()


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
			"visual_style": controller.map_definition.region_style,
		})
	return placements


func _refresh_hud() -> void:
	_update_live_objective_position()
	var enemy_state := controller.evolution.get_enemy_snapshot()
	var player_state := controller.evolution.get_player_snapshot()
	var objective := controller.objectives.get_snapshot()
	var completion_title := "任务完成 · 奖励即将展开"
	if StringName(_reward_context.get("source", &"")) == &"boss":
		completion_title = "首领击破 · 战利品即将展开"
	elif StringName(_reward_context.get("source", &"")) == &"kill_level":
		completion_title = "击破升级 · 强化即将展开"
	var context := {
		"region_text": ("好友无尽" if _web_race_bridge != null else "无尽挑战") + " / " + controller.map_definition.title,
		"voyage_text": "航行 %s  ·  击破 %d" % [_format_time(float(enemy_state.get("survival_seconds", 0.0))), controller.defeated_total],
		"objective_title": completion_title if _modal_kind == &"objective_complete" else "%s  ·  %d 秒" % [str(objective.get("title", "任务准备中")), ceili(float(objective.get("time_remaining", 0.0)))],
		"objective_detail": "航灯已响应，稍候选择本局强化。" if _modal_kind == &"objective_complete" else str(objective.get("instruction", "")),
		"objective_progress": float(objective.get("progress_ratio", 0.0)),
		"race": _web_race_bridge != null,
		"endless_navigation": true,
		"experience": controller.evolution.get_experience_snapshot(),
		"objective_feedback": _reward_ui_metadata() if _modal_kind == &"objective_complete" else {},
		"bosses": _boss_snapshots(),
		"boss_director": _boss_director.get_snapshot(),
		"bombardment": _bombardment.get_snapshot() if is_instance_valid(_bombardment) else {},
	}
	var pressure := "威胁 %d · 场上 %d\n收纳进化 %d" % [int(enemy_state.get("stage", 0)), combat_runtime.enemies.size(), int(player_state.get("stage", 0))]
	presentation.update_hud(player, {}, {}, "无尽挑战", pressure, {}, context)
	if is_instance_valid(_navigation):
		_navigation.call("update_snapshot", get_navigation_snapshot())


func _update_live_objective_position() -> void:
	var objective := controller.objectives.get_snapshot()
	if StringName(objective.get("kind", &"")) != &"defeat_captain" or not bool(objective.get("target_active", false)):
		return
	var target_id := StringName(objective.get("target_id", &""))
	for actor: Node2D in combat_runtime.enemies:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var entry: Dictionary = actor.get_meta("directed_spawn_entry", {})
		if bool(entry.get("is_captain", false)) and StringName(entry.get("captain_id", &"")) == target_id:
			controller.objectives.update_target_position(target_id, actor.global_position)
			return


func get_navigation_snapshot() -> Dictionary:
	var map := controller.map_definition
	var zone_state := controller.zones.get_snapshot()
	var state := "safe"
	var message := "青色航道不受毒潮影响 · 橙色落点需躲避"
	var remaining := float(zone_state.get("remaining", 0.0))
	if controller.zones.is_point_closed(player.global_position):
		state = "closed"
		remaining = _zone_exposure.seconds_until_damage()
		message = "关闭区域 · %.1f 秒后扣 1 格血 / 每 2 秒" % remaining
	elif controller.zones.is_point_reserved(player.global_position):
		state = "warning"
		message = "所在区域 %d 秒后关闭 · 沿青色箭头撤离" % ceili(remaining)
	elif String(zone_state.get("phase", "rest")) == "warning":
		message = "%d 秒后封区 · 避开地图上的金色预警区" % ceili(remaining)
	if state != "safe" and _safe_route_clock <= 0.0:
		_safe_route_clock = 0.5
		_safe_route_position = controller.map_runtime.get_nearest_safe_position(player.global_position, player.get_hit_radius())
	var view_size := get_viewport_rect().size / camera.zoom
	return {
		"combat_time": controller.evolution.survival_seconds,
		"motion_scale": _feedback_motion_scale,
		"map_id": map.map_id, "map_title": map.title,
		"layout_revision": map.authored_version,
		"bounds": map.bounds, "obstacles": map.walls,
		"player_position": player.global_position,
		"camera_rect": Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size),
		"zones": zone_state.get("zones", []),
		"safe_corridors": zone_state.get("safe_corridors", []),
		"refuges": zone_state.get("refuges", PackedVector2Array()),
		"objective": controller.objectives.get_snapshot(),
		"bosses": _boss_snapshots(),
		"boss_director": _boss_director.get_snapshot(),
		"bombardment": _bombardment.get_snapshot() if is_instance_valid(_bombardment) else {},
		"danger": {"state": state, "message": message, "seconds_remaining": remaining, "safe_position": _safe_route_position},
	}


func get_slice_snapshot() -> Dictionary:
	return {
		"controller": controller.get_snapshot(),
		"player_position": player.global_position,
		"player_health": player.health,
		"max_health": player.max_health,
		"enemy_count": combat_runtime.enemies.size(),
		"pending_enemy_count": _pending_spawns.size(),
		"projectile_count": combat_runtime.projectiles.size(),
		"run_ended": run_ended,
		"modal_kind": _modal_kind,
		"combat_reuse": get_combat_reuse_contract(),
		"navigation": get_navigation_snapshot(),
		"boss_director": _boss_director.get_snapshot(),
		"bosses": _boss_snapshots(),
	}


func get_combat_reuse_contract() -> Dictionary:
	var all_enemy_actors := true
	for enemy in combat_runtime.enemies:
		if not (enemy is FoldlightRogueEnemyActor or enemy is FoldlightRogueBossActor or enemy is ObjectiveTarget):
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
