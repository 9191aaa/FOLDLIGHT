class_name FoldlightRogueSessionController
extends Node

enum SessionMode { INACTIVE, TITLE, RUN, PROLOGUE, RESULT }

const WORLD_SIZE := Vector2(2880.0, 1620.0)
const PLAYER_START := Vector2(1440.0, 1180.0)
const ENDLESS_SURVIVAL_SCENE := "res://scenes/endless/endless_survival_slice.tscn"
const PAPER_REEF_ENEMY_TIERS: Array[Array] = [
	[&"drifter", &"fan"],
	[&"ram", &"bloomer"],
	[&"weaver", &"paper_turret"],
]
const PROLOGUE_STEPS: Array[Dictionary] = [
	{"title": "移动与冲刺", "body": "移动一小段，再用一次 2.0 秒冷却的冲刺。"},
	{"title": "收纳与追踪", "body": "按住折域收纳普通弹，松开后追踪返航；击杀普通敌人会接力一次，黑金弹不可反射。"},
	{"title": "自动火力与地形", "body": "靠近敌人后武器会自动开火。利用墙体挡弹，青金地形有利，墨色与刺纸地形有害。"},
]

var mode: SessionMode = SessionMode.INACTIVE
var current_room_node: Dictionary = {}
var current_region_snapshot: Dictionary = {}
var current_region_definition: FoldlightRogueRegionDefinition
var current_wave_text: String = ""
var _active: bool = false
var persist_profile: bool = true
var _hud_tick: float = 0.0
var _result_committed: bool = false
var _prologue_step_index: int = 0
var _prologue_distance: float = 0.0
var _prologue_dash_complete: bool = false
var _prologue_last_position := Vector2.ZERO
var _prologue_volley_timer: float = 0.0
var _prologue_encounter_started: bool = false
var _pending_reward_kinds: Dictionary = {}
var _paused: bool = false
var _pending_kill_sfx: int = 0
var _kill_sfx_cooldown: float = 0.0
var _feedback_shake_cooldown: float = 0.0
var _capture_sfx_cooldown: float = 0.0
var _mechanic_intro_queue: Array[Dictionary] = []
var _mechanic_intro_active: bool = false
var _current_room_template: Dictionary = {}
var _pending_reward_sequence: Array[StringName] = []
var _current_reward_kind: StringName = &""
var _current_reward_title: String = ""
var _kill_combo_count: int = 0
var _kill_combo_timer: float = 0.0
var _kill_shake_cooldown: float = 0.0

@onready var player: FoldlightPlayer = get_parent().get_node("Player")
@onready var run_controller: FoldlightRogueRunController = get_parent().get_node("RogueRunController")
@onready var world: FoldlightRogueWorld = get_parent().get_node("RogueWorld")
@onready var presentation: FoldlightRoguePresentation = get_parent().get_node("RoguePresentation")
@onready var encounter_director: FoldlightEncounterDirector = $EncounterDirector
@onready var reward_director: FoldlightRewardDirector = $RewardDirector
@onready var mechanic_tracker: FoldlightMechanicIntroductionTracker = $MechanicIntroductionTracker
@onready var profile_manager: FoldlightProfileManager = get_node("/root/ProfileManager") as FoldlightProfileManager
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run_controller.room_requested.connect(_on_room_requested)
	run_controller.room_cleared.connect(_on_run_room_cleared)
	run_controller.checkpoint_ready.connect(_on_checkpoint_ready)
	run_controller.route_choice_requested.connect(_on_route_choice_requested)
	run_controller.run_finished.connect(_on_run_finished)
	world.room_runtime.encounter_cleared.connect(_on_encounter_cleared)
	world.room_runtime.encounter_runtime.wave_started.connect(_on_wave_started)
	world.combat_runtime.player_hit.connect(_on_player_hit)
	world.combat_runtime.projectile_captured.connect(_on_projectile_captured)
	world.combat_runtime.enemy_defeated.connect(_on_enemy_defeated)
	world.combat_runtime.enemy_spawned.connect(_on_enemy_spawned)
	mechanic_tracker.card_requested.connect(_on_mechanic_card_requested)
	presentation.mechanic_card_dismissed.connect(_on_mechanic_card_dismissed)
	presentation.new_run_requested.connect(_on_new_run_requested)
	presentation.continue_requested.connect(continue_run)
	presentation.prologue_requested.connect(start_prologue)
	presentation.prologue_skip_requested.connect(_on_prologue_skip_requested)
	presentation.classic_requested.connect(_on_classic_requested)
	presentation.endless_requested.connect(_on_endless_requested)
	presentation.quit_requested.connect(func() -> void: get_tree().quit())
	presentation.settings_requested.connect(_on_settings_requested)
	presentation.resume_requested.connect(_resume_game)
	presentation.abandon_requested.connect(_on_abandon_requested)
	presentation.setting_adjust_requested.connect(_on_setting_adjust_requested)
	presentation.settings_back_requested.connect(_on_settings_back_requested)
	presentation.reward_chosen.connect(_on_reward_chosen)
	presentation.route_chosen.connect(_on_route_chosen)
	presentation.retry_requested.connect(start_new_run)
	presentation.title_requested.connect(enter_title)
	player.dash_started.connect(_on_player_dash_started)
	player.fold_started.connect(_on_player_fold_started)
	player.fold_released.connect(_on_player_fold_released)
	player.active_item_used.connect(_on_player_active_item_used)
	player.focus_empty.connect(_on_player_focus_empty)
	player.statuses_cleansed.connect(_on_player_statuses_cleansed)
	player.feedback_budget.impact_batch_requested.connect(_on_feedback_impact_batch)
	call_deferred("enter_title")


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"pause_game"):
		if _paused:
			_resume_game()
		elif mode in [SessionMode.RUN, SessionMode.PROLOGUE] and presentation.screen_kind == &"hud":
			_pause_game()
		elif presentation.screen_kind == &"settings":
			_on_settings_back_requested(presentation._settings_return)
		get_viewport().set_input_as_handled()
		return
	if presentation.screen_kind != &"hud" and _is_gameplay_input(event):
		# Modal screens own navigation. Absorb both keyboard and mapped gamepad
		# combat actions so they cannot reach the player or the legacy root.
		get_viewport().set_input_as_handled()


func _is_gameplay_input(event: InputEvent) -> bool:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"fold", &"dash", &"active_item"]:
		if event.is_action_pressed(action):
			return true
	return false


func _process(delta: float) -> void:
	if not _active:
		return
	if _paused:
		return
	_kill_sfx_cooldown = maxf(0.0, _kill_sfx_cooldown - delta)
	_feedback_shake_cooldown = maxf(0.0, _feedback_shake_cooldown - delta)
	_capture_sfx_cooldown = maxf(0.0, _capture_sfx_cooldown - delta)
	_kill_shake_cooldown = maxf(0.0, _kill_shake_cooldown - delta)
	_kill_combo_timer = maxf(0.0, _kill_combo_timer - delta)
	if _kill_combo_timer <= 0.0:
		_kill_combo_count = 0
	if _pending_kill_sfx > 0 and _kill_sfx_cooldown <= 0.0:
		audio_director.play_sfx(&"kill", 0.94 + minf(0.18, float(_pending_kill_sfx) * 0.025), -6.0)
		_pending_kill_sfx = 0
		_kill_sfx_cooldown = 0.085
	if _can_advance_encounter():
		world.room_runtime.advance_encounter(delta)
	if mode == SessionMode.RUN and run_controller.phase in [FoldlightRogueRunController.Phase.ENTERING_ROOM, FoldlightRogueRunController.Phase.COMBAT]:
		run_controller.run_state.elapsed += delta
	elif mode == SessionMode.PROLOGUE:
		_update_prologue(delta)
	_hud_tick -= delta
	if _hud_tick <= 0.0 and presentation.screen_kind == &"hud":
		_hud_tick = 0.08
		_refresh_hud()


func enter_title() -> void:
	_active = true
	_paused = false
	mode = SessionMode.TITLE
	_result_committed = false
	world.deactivate()
	player.cancel_fold()
	player.set_play_enabled(false)
	player.visible = false
	var legacy_hud := get_parent().get_node_or_null("HUD")
	if legacy_hud != null:
		legacy_hud.hide()
	presentation.show()
	presentation.show_title(profile_manager.get_roguelite_snapshot())
	audio_director.set_intensity(0.045)


func deactivate_for_classic() -> void:
	_active = false
	_paused = false
	mode = SessionMode.INACTIVE
	presentation.hide()
	world.deactivate()
	player.configure_roguelite_combat(false)
	player.reset_player()
	player.visible = true


func _on_endless_requested() -> void:
	# The survival slice owns a much larger authored world and its own camera.
	# Changing scenes keeps campaign/roguelite combat nodes from processing in
	# parallel and gives the mode a clean, deterministic return path to title.
	_enter_modal_safety()
	var error := get_tree().change_scene_to_file(ENDLESS_SURVIVAL_SCENE)
	if error != OK:
		push_error("Unable to open endless survival scene: %s" % error_string(error))
		player.resume_from_overlay(0.35)
		presentation.show_title(profile_manager.get_roguelite_snapshot())


func start_new_run() -> void:
	_activate_gameplay()
	mode = SessionMode.RUN
	_result_committed = false
	if persist_profile:
		profile_manager.clear_roguelite_checkpoint()
	var snapshot := run_controller.start_new_run()
	if persist_profile and not snapshot.is_empty():
		snapshot["session_phase"] = "room"
		profile_manager.commit_roguelite_checkpoint(snapshot)


func continue_run() -> void:
	var rogue := profile_manager.get_roguelite_snapshot()
	var checkpoint_variant: Variant = rogue.get("active_run", {})
	if not checkpoint_variant is Dictionary or (checkpoint_variant as Dictionary).is_empty():
		start_new_run()
		return
	_activate_gameplay()
	mode = SessionMode.RUN
	_result_committed = false
	var checkpoint := checkpoint_variant as Dictionary
	if not run_controller.restore_run(checkpoint):
		if persist_profile:
			profile_manager.clear_roguelite_checkpoint()
		start_new_run()
		return
	_restore_pending_session(checkpoint)


func start_prologue() -> void:
	_activate_gameplay()
	mode = SessionMode.PROLOGUE
	_result_committed = false
	_prologue_step_index = 0
	_prologue_distance = 0.0
	_prologue_dash_complete = false
	_prologue_volley_timer = 1.2
	_prologue_encounter_started = false
	current_region_definition = FoldlightRogueContentCatalog.REGIONS[0]
	current_region_snapshot = {"title": "纸礁浅海", "id": "paper_reef", "index": 0, "nodes": []}
	current_room_node = {"id": "prologue_lantern_school", "category": "entry", "risk": 1, "exits": []}
	var errors := world.load_room(player, &"prologue_lantern_school", WORLD_SIZE, _terrain_layout(&"paper_reef", &"entry", 0), current_region_definition.accent, 20260727)
	if not errors.is_empty():
		push_error("RogueSession: prologue room failed: %s" % "; ".join(errors))
		enter_title()
		return
	world.activate()
	world.combat_runtime.apply_run_build({})
	player.global_position = PLAYER_START
	player.health = player.max_health
	player.grant_invulnerability(60.0)
	player.set_play_enabled(true)
	_prologue_last_position = player.global_position
	presentation.show_prologue_step(1, PROLOGUE_STEPS.size(), str(PROLOGUE_STEPS[0]["title"]), str(PROLOGUE_STEPS[0]["body"]))
	audio_director.set_intensity(0.10)


func _activate_gameplay() -> void:
	_active = true
	_paused = false
	var legacy_hud := get_parent().get_node_or_null("HUD")
	if legacy_hud != null:
		legacy_hud.hide()
	presentation.show()
	player.set_play_enabled(false)
	player.reset_player()
	player.configure_roguelite_combat(true)
	player.visible = true
	player.global_position = PLAYER_START
	mechanic_tracker.restore_introduced([])
	_mechanic_intro_queue.clear()
	_mechanic_intro_active = false


func _on_new_run_requested() -> void:
	var rogue := profile_manager.get_roguelite_snapshot()
	if not bool(rogue.get("prologue_complete", false)):
		start_prologue()
	else:
		start_new_run()


func _on_classic_requested() -> void:
	deactivate_for_classic()
	if get_parent().has_method("activate_classic_campaign"):
		get_parent().call("activate_classic_campaign")


func _on_room_requested(room_node: Dictionary, region_snapshot: Dictionary) -> void:
	if mode != SessionMode.RUN:
		return
	current_room_node = room_node.duplicate(true)
	current_region_snapshot = region_snapshot.duplicate(true)
	current_region_definition = FoldlightRogueContentCatalog.REGIONS[clampi(run_controller.run_state.current_region, 0, FoldlightRogueContentCatalog.REGIONS.size() - 1)]
	var room_id := StringName(room_node.get("id", &"room"))
	var category := StringName(room_node.get("category", &"combat"))
	_current_room_template = {}
	var terrain: Array[Dictionary] = []
	if category == &"boss":
		terrain = _boss_terrain_layout(current_region_definition.content_id)
	else:
		_current_room_template = FoldlightRogueRoomTemplateCatalog.select_template(
			current_region_definition.content_id,
			run_controller.run_state.seed,
			room_id,
			category,
			int(room_node.get("depth", 0))
		)
		for placement_variant: Variant in _current_room_template.get("terrain", []):
			if placement_variant is Dictionary:
				terrain.append((placement_variant as Dictionary).duplicate(true))
	var errors := world.load_room(player, room_id, WORLD_SIZE, terrain, current_region_definition.accent, run_controller.run_state.seed + run_controller.run_state.room_count * 7919, current_region_definition.backdrop_style)
	if not errors.is_empty():
		push_error("RogueSession: room configuration failed: %s" % "; ".join(errors))
		run_controller.fail_run(&"invalid_room")
		return
	world.activate()
	player.global_position = PLAYER_START
	world.combat_runtime.apply_run_build(run_controller.run_state.upgrade_levels)
	_equip_run_loadout()
	player.health = clampi(run_controller.run_state.health, 1, player.max_health)
	if run_controller.run_state.current_region > 0 and category == &"entry":
		world.combat_runtime.grant_region_shield(run_controller.run_state.glimmer)
	player.grant_invulnerability(1.0)
	player.set_play_enabled(true)
	current_wave_text = ""
	presentation.show_hud()
	var plan := _boss_plan(room_node) if category == &"boss" else _encounter_plan(room_node)
	var begin_errors := world.room_runtime.begin_encounter(plan)
	if not begin_errors.is_empty():
		push_error("RogueSession: encounter failed: %s" % "; ".join(begin_errors))
		run_controller.fail_run(&"invalid_encounter")
		return
	run_controller.begin_combat()
	audio_director.set_intensity(0.18 + float(run_controller.run_state.current_region) * 0.13 + (0.18 if category == &"boss" else 0.0))
	if category == &"boss":
		audio_director.play_sfx(&"boss", 1.0, -2.0)


func _encounter_plan(room_node: Dictionary) -> Dictionary:
	var encounter_id := current_region_definition.encounter_ids[0] if not current_region_definition.encounter_ids.is_empty() else &"reef_crossfire"
	var base_definition := FoldlightRogueContentCatalog.encounter_by_id(encounter_id)
	if base_definition == null:
		return {"errors": ["missing encounter definition"], "entries": []}
	var definition := base_definition.duplicate(true) as FoldlightRogueEncounterDefinition
	var category := StringName(room_node.get("category", &"combat"))
	var depth := int(room_node.get("depth", 0))
	var staged_enemy_ids := _enemy_ids_for_room(current_region_definition.content_id, depth, category)
	if not staged_enemy_ids.is_empty():
		definition.enemy_ids = staged_enemy_ids
	var multiplier := {
		&"entry": 0.82,
		&"rest": 0.78,
		&"cache": 0.86,
		&"shop": 0.90,
		&"forge": 0.96,
		&"event": 1.06,
		&"elite": 1.25,
	}.get(category, 1.0) as float
	definition.threat_budget = maxi(22, int(round(float(current_region_definition.base_threat_budget + int(room_node.get("risk", 1))) * multiplier * 1.10)))
	definition.minimum_enemy_count = clampi(int(round(float(base_definition.minimum_enemy_count) * multiplier * 1.10)), 16, 32)
	definition.wave_count = 4 if category == &"elite" or run_controller.run_state.current_region > 0 else 3
	return encounter_director.compose_encounter(
		definition,
		FoldlightRogueContentCatalog.ENEMIES,
		run_controller.run_state.seed ^ hash(String(room_node.get("id", "room"))),
		run_controller.run_state.current_region + 1,
		_spawn_slots(),
		PLAYER_START,
		world.room_runtime.get_solid_terrain_bounds(22.0)
	)


func _enemy_ids_for_room(region_id: StringName, depth: int, category: StringName) -> Array[StringName]:
	if region_id != &"paper_reef":
		return []
	var result: Array[StringName] = []
	var highest_tier := clampi(depth / 2, 0, PAPER_REEF_ENEMY_TIERS.size() - 1)
	for tier_index in highest_tier + 1:
		for enemy_id: StringName in PAPER_REEF_ENEMY_TIERS[tier_index]:
			result.append(enemy_id)
	if category == &"elite" and depth >= 5:
		result.append(&"brood_lantern")
	return result


func _boss_plan(room_node: Dictionary) -> Dictionary:
	var boss_id := StringName(room_node.get("boss_id", &""))
	return {
		"encounter_id": StringName("boss_%s" % String(boss_id)),
		# The opening camera is clamped near the player's southern entry. Spawn
		# inside that first composition so the boss, warning and health bar are all
		# readable before the player has to advance into danger.
		"entries": [{"boss_id": boss_id, "wave": 0, "spawn_position": Vector2(1440, 720), "role": FoldlightRogueEnemyDefinition.EnemyRole.BOSS, "threat_cost": 99}],
		"errors": [],
	}


func _on_encounter_cleared(performance: Dictionary) -> void:
	_enter_modal_safety()
	current_wave_text = "房间澄清"
	if mode == SessionMode.PROLOGUE:
		if _prologue_step_index == PROLOGUE_STEPS.size() - 1:
			_finish_prologue()
		return
	if mode != SessionMode.RUN:
		return
	run_controller.complete_room(performance)


func _on_run_room_cleared(room_node: Dictionary, performance: Dictionary) -> void:
	_enter_modal_safety()
	run_controller.run_state.health = player.health
	run_controller.run_state.max_health = player.max_health
	var duration := maxf(1.0, float(performance.get("duration", 1.0)))
	var pace_bonus := 2 if duration < 75.0 else 0
	var base_glimmer := 4 + int(room_node.get("risk", 1)) + pace_bonus
	run_controller.run_state.glimmer += int(round(float(base_glimmer) * world.combat_runtime.get_glimmer_gain_multiplier()))
	if StringName(room_node.get("category", &"")) == &"boss":
		world.combat_runtime.grant_region_shield(run_controller.run_state.glimmer)
		return
	var rogue := profile_manager.get_roguelite_snapshot()
	_current_reward_kind = &""
	_pending_reward_sequence.clear()
	_current_reward_title = _category_display(StringName(room_node.get("category", &"combat")))
	if run_controller.run_state.room_count == 2 and run_controller.run_state.active_item_id.is_empty():
		_pending_reward_sequence = [&"upgrade", &"active"]
		_show_next_reward_stage(rogue)
		audio_director.set_intensity(0.07)
		return
	var choices := _draft_room_reward(StringName(room_node.get("category", &"combat")), rogue)
	if choices.is_empty():
		run_controller.open_route_choice()
		return
	presentation.show_reward(choices, _category_display(StringName(room_node.get("category", &"combat"))))
	audio_director.set_intensity(0.07)


func _on_reward_chosen(upgrade_id: StringName) -> void:
	if mode != SessionMode.RUN or run_controller.phase != FoldlightRogueRunController.Phase.REWARD:
		return
	var reward_kind := StringName(_pending_reward_kinds.get(String(upgrade_id), &"upgrade"))
	match reward_kind:
		&"weapon":
			_apply_weapon_choice(upgrade_id)
		&"active":
			_apply_active_choice(upgrade_id)
		_:
			if not reward_director.apply_upgrade_choice(run_controller.run_state, upgrade_id):
				return
			world.combat_runtime.apply_run_build(run_controller.run_state.upgrade_levels, upgrade_id)
	run_controller.run_state.health = player.health
	run_controller.run_state.max_health = player.max_health
	_current_reward_kind = &""
	if not _pending_reward_sequence.is_empty():
		_show_next_reward_stage(profile_manager.get_roguelite_snapshot())
		_commit_reward_checkpoint()
		return
	run_controller.open_route_choice()


func _on_route_choice_requested(exits: Array[String]) -> void:
	_enter_modal_safety()
	presentation.show_route(current_region_snapshot, StringName(current_room_node.get("id", &"")), exits)


func _on_route_chosen(destination_id: StringName) -> void:
	if mode == SessionMode.RUN:
		run_controller.choose_exit(destination_id)


func _on_checkpoint_ready(snapshot: Dictionary) -> void:
	if mode == SessionMode.RUN:
		if persist_profile:
			var enriched := snapshot.duplicate(true)
			if StringName(enriched.get("session_phase", &"")) == &"reward" and not _current_reward_kind.is_empty():
				enriched["reward_current_kind"] = String(_current_reward_kind)
				enriched["reward_sequence"] = _string_array(_pending_reward_sequence)
				enriched["reward_title"] = _current_reward_title
			profile_manager.commit_roguelite_checkpoint(enriched)


func _restore_pending_session(checkpoint: Dictionary) -> void:
	var phase_hint := StringName(checkpoint.get("session_phase", &"room"))
	if phase_hint == &"room":
		return
	current_room_node = run_controller.get_current_room_node()
	current_region_snapshot = run_controller.get_current_region_snapshot()
	current_region_definition = FoldlightRogueContentCatalog.REGIONS[clampi(run_controller.run_state.current_region, 0, FoldlightRogueContentCatalog.REGIONS.size() - 1)]
	world.deactivate()
	player.apply_roguelite_build(run_controller.run_state.upgrade_levels)
	_equip_run_loadout()
	player.health = clampi(run_controller.run_state.health, 1, player.max_health)
	player.set_play_enabled(false)
	player.visible = false
	if phase_hint == &"reward":
		_current_reward_kind = StringName(checkpoint.get("reward_current_kind", &""))
		_pending_reward_sequence = _name_array(checkpoint.get("reward_sequence", []))
		_current_reward_title = str(checkpoint.get("reward_title", _category_display(StringName(current_room_node.get("category", &"combat")))))
		if _current_reward_kind.is_empty() and run_controller.run_state.room_count == 2 and run_controller.run_state.active_item_id.is_empty():
			_pending_reward_sequence = [&"upgrade", &"active"]
			_show_next_reward_stage(profile_manager.get_roguelite_snapshot())
		else:
			var choices := _draft_room_reward(StringName(current_room_node.get("category", &"combat")), profile_manager.get_roguelite_snapshot(), _current_reward_kind)
			presentation.show_reward(choices, _reward_stage_title(_current_reward_kind, _current_reward_title))
	else:
		var exits: Array[String] = []
		for value: Variant in current_room_node.get("exits", []):
			exits.append(String(value))
		presentation.show_route(current_region_snapshot, StringName(current_room_node.get("id", &"")), exits)
	audio_director.set_intensity(0.06)


func _on_run_finished(result: Dictionary) -> void:
	if mode != SessionMode.RUN:
		return
	mode = SessionMode.RESULT
	world.deactivate()
	player.set_play_enabled(false)
	player.visible = false
	var completed := result.duplicate(true)
	completed["glimmer"] = run_controller.run_state.glimmer
	if persist_profile and not _result_committed:
		profile_manager.record_roguelite_run(completed)
		_result_committed = true
	presentation.show_result(completed)
	audio_director.set_intensity(0.04)
	audio_director.play_sfx(&"victory" if bool(completed.get("won", false)) else &"hurt", 1.0, -2.0)


func _on_player_hit(health_remaining: int) -> void:
	audio_director.play_sfx(&"hurt", 0.96, -4.0)
	if presentation.has_method("flash_player_damage"):
		presentation.call("flash_player_damage")
	var shake_setting := float(profile_manager.get_setting(&"screen_shake", 1.0))
	# 0.38 was effectively a one-pixel nudge after the camera's squared trauma
	# curve. 0.62 produces a short ~3-4 px kick while the player body carries
	# the more readable local recoil.
	world.camera.add_trauma(0.62 * shake_setting)
	world.camera.add_hit_kick(shake_setting)
	if bool(profile_manager.get_setting(&"vibration", true)):
		Input.start_joy_vibration(0, 0.22, 0.46, 0.16)
	if health_remaining > 0:
		return
	if mode == SessionMode.PROLOGUE:
		start_prologue()
	elif mode == SessionMode.RUN:
		run_controller.run_state.health = 0
		run_controller.fail_run(&"lantern_extinguished")


func _on_enemy_defeated(enemy_id: StringName) -> void:
	_pending_kill_sfx += 1
	if _kill_combo_timer <= 0.0:
		_kill_combo_count = 0
	_kill_combo_count += 1
	_kill_combo_timer = 1.25
	if _kill_shake_cooldown <= 0.0:
		var is_boss := FoldlightRogueContentCatalog.boss_by_id(enemy_id) != null
		var combo_step := 0.04 if _kill_combo_count >= 5 else 0.0
		combo_step += 0.05 if _kill_combo_count >= 10 else 0.0
		var trauma := 0.52 if is_boss else minf(0.30, 0.16 + float(_kill_combo_count) * 0.008 + combo_step)
		world.camera.add_trauma(trauma * float(profile_manager.get_setting(&"screen_shake", 1.0)))
		_kill_shake_cooldown = 0.075
	if mode == SessionMode.RUN:
		run_controller.run_state.glimmer += 4 if FoldlightRogueContentCatalog.boss_by_id(enemy_id) != null else 1


func _on_enemy_spawned(_actor: Node2D, entry: Dictionary) -> void:
	var definition := FoldlightRogueContentCatalog.enemy_by_id(StringName(entry.get("enemy_id", &"")))
	if definition != null:
		mechanic_tracker.request_introduction(definition)
	if _actor is FoldlightRogueBossActor:
		var boss_actor := _actor as FoldlightRogueBossActor
		mechanic_tracker.request_boss_introduction(boss_actor.definition)
		if boss_actor.definition != null and boss_actor.definition.content_id == &"inverted_archivist":
			boss_actor.call_deferred("request_opening_support")
		boss_actor.phase_changed.connect(func(_phase: int) -> void:
			world.camera.add_trauma(0.24 * float(profile_manager.get_setting(&"screen_shake", 1.0)))
		)


func _on_mechanic_card_requested(snapshot: Dictionary) -> void:
	# Deterministic simulation suites opt out of profile persistence and modal
	# presentation; real runs always keep this enabled.
	if not persist_profile:
		return
	var content_id := StringName(snapshot.get("content_id", &""))
	var intro_id := _mechanic_intro_key(snapshot)
	if content_id.is_empty() or profile_manager.has_acknowledged_intro(intro_id):
		return
	_mechanic_intro_queue.append(snapshot.duplicate(true))
	if not _mechanic_intro_active:
		_show_next_mechanic_briefing()


func _show_next_mechanic_briefing() -> void:
	if _mechanic_intro_queue.is_empty():
		_finish_mechanic_briefings()
		return
	_mechanic_intro_active = true
	_enter_modal_safety()
	presentation.show_mechanic_card(_mechanic_intro_queue[0])
	audio_director.set_intensity(0.035)


func _on_mechanic_card_dismissed(content_id: StringName) -> void:
	if not _mechanic_intro_active:
		return
	if not content_id.is_empty():
		var current_snapshot := _mechanic_intro_queue[0] if not _mechanic_intro_queue.is_empty() else {"content_id": content_id, "preview_kind": &"enemy"}
		profile_manager.acknowledge_intro(_mechanic_intro_key(current_snapshot), persist_profile)
	if not _mechanic_intro_queue.is_empty():
		_mechanic_intro_queue.pop_front()
	if _mechanic_intro_queue.is_empty():
		_finish_mechanic_briefings()
	else:
		presentation.show_mechanic_card(_mechanic_intro_queue[0])


func _mechanic_intro_key(snapshot: Dictionary) -> StringName:
	return StringName("rogue_threat_v3:%s:%s" % [String(snapshot.get("preview_kind", &"enemy")), String(snapshot.get("content_id", &""))])


func _finish_mechanic_briefings() -> void:
	if not _mechanic_intro_active:
		return
	_mechanic_intro_active = false
	world.combat_runtime.set_active(true)
	player.resume_from_overlay(0.75)
	if mode == SessionMode.PROLOGUE:
		var step := PROLOGUE_STEPS[_prologue_step_index]
		presentation.show_prologue_step(_prologue_step_index + 1, PROLOGUE_STEPS.size(), str(step["title"]), str(step["body"]))
	else:
		presentation.show_hud()
	audio_director.set_intensity(0.18 + float(run_controller.run_state.current_region) * 0.13)


func _on_wave_started(wave_number: int, total_waves: int) -> void:
	current_wave_text = "第 %d / %d 波" % [wave_number, total_waves]


func _refresh_hud() -> void:
	var snapshot := run_controller.run_state.make_checkpoint() if mode == SessionMode.RUN else {"room_count": 0, "glimmer": 0}
	var region_title := current_region_definition.title if current_region_definition != null else "纸礁浅海"
	var boss_snapshot := _boss_hud_snapshot()
	presentation.update_hud(player, snapshot, current_room_node, region_title, current_wave_text, boss_snapshot)


func _boss_hud_snapshot() -> Dictionary:
	for enemy in world.combat_runtime.enemies:
		if enemy is FoldlightRogueBossActor and is_instance_valid(enemy):
			var boss := enemy as FoldlightRogueBossActor
			var snapshot := boss.get_combat_snapshot()
			snapshot["title"] = boss.definition.title
			snapshot["phase"] = boss.phase_controller.phase_index + 1
			return snapshot
	return {}


func _draft_room_reward(category: StringName, rogue: Dictionary, forced_kind: StringName = &"") -> Array[Dictionary]:
	_pending_reward_kinds.clear()
	var choices: Array[Dictionary] = []
	var reward_kind := forced_kind
	if reward_kind.is_empty():
		reward_kind = &"weapon" if category == &"forge" else (&"active" if category == &"shop" else &"upgrade")
	if reward_kind == &"weapon":
		for weapon_id in _name_array(rogue.get("unlocked_weapons", [])):
			var weapon := FoldlightRogueContentCatalog.weapon_by_id(weapon_id)
			if weapon == null:
				continue
			choices.append({"content_id": weapon.content_id, "choice_kind": &"weapon", "title": weapon.title, "description": weapon.description, "rarity": 1, "accent": weapon.accent, "next_level": 1, "maximum_level": 1, "offensive": true})
	elif reward_kind == &"active":
		for item_id in _name_array(rogue.get("unlocked_active_items", [])):
			var item := FoldlightRogueContentCatalog.active_item_by_id(item_id)
			if item == null:
				continue
			choices.append({"content_id": item.content_id, "choice_kind": &"active", "title": item.title, "description": item.description, "rarity": 1, "accent": item.accent, "next_level": 1, "maximum_level": 1, "offensive": item.effect_id in [&"radial_push", &"anchor_shield", &"weapon_overdrive"]})
	else:
		var unlocked := _name_array(rogue.get("unlocked_upgrades", []))
		choices = reward_director.draft_upgrades(run_controller.run_state.seed, run_controller.run_state.room_count, run_controller.run_state.upgrade_levels, unlocked, 3)
		for choice in choices:
			choice["choice_kind"] = &"upgrade"
	choices = _sample_reward_choices(choices)
	for choice in choices:
		_pending_reward_kinds[String(choice.get("content_id", &""))] = StringName(choice.get("choice_kind", &"upgrade"))
	return choices


func _show_next_reward_stage(rogue: Dictionary) -> void:
	if _pending_reward_sequence.is_empty():
		run_controller.open_route_choice()
		return
	_current_reward_kind = _pending_reward_sequence.pop_front()
	var choices := _draft_room_reward(StringName(current_room_node.get("category", &"combat")), rogue, _current_reward_kind)
	if choices.is_empty():
		_show_next_reward_stage(rogue)
		return
	presentation.show_reward(choices, _reward_stage_title(_current_reward_kind, _current_reward_title))


func _reward_stage_title(kind: StringName, room_title: String) -> String:
	match kind:
		&"upgrade": return "%s · 先选一项强化" % room_title
		&"active": return "%s · 再带走一件主动道具" % room_title
		&"weapon": return "%s · 选择自动武器" % room_title
	return room_title


func _commit_reward_checkpoint() -> void:
	if not persist_profile:
		return
	var snapshot := run_controller.run_state.make_checkpoint()
	snapshot["session_phase"] = "reward"
	snapshot["reward_current_kind"] = String(_current_reward_kind)
	snapshot["reward_sequence"] = _string_array(_pending_reward_sequence)
	snapshot["reward_title"] = _current_reward_title
	profile_manager.commit_roguelite_checkpoint(snapshot)


func _sample_reward_choices(source: Array[Dictionary]) -> Array[Dictionary]:
	if source.size() <= 3:
		return source
	var shuffled: Array[Dictionary] = source.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_controller.run_state.seed ^ run_controller.run_state.room_count * 2654435761
	for index in range(shuffled.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var temp: Dictionary = shuffled[index]
		shuffled[index] = shuffled[swap]
		shuffled[swap] = temp
	var result: Array[Dictionary] = []
	for index in 3:
		result.append(shuffled[index])
	if result.any(func(choice: Dictionary) -> bool: return bool(choice.get("offensive", false))):
		return result
	for choice in shuffled:
		if bool(choice.get("offensive", false)):
			result[2] = choice
			break
	return result


func _apply_weapon_choice(weapon_id: StringName) -> void:
	if FoldlightRogueContentCatalog.weapon_by_id(weapon_id) == null:
		return
	if run_controller.run_state.weapon_ids.has(weapon_id):
		run_controller.run_state.weapon_ids.erase(weapon_id)
	if run_controller.run_state.weapon_ids.size() >= 2:
		run_controller.run_state.weapon_ids.remove_at(0)
	run_controller.run_state.weapon_ids.append(weapon_id)
	_equip_run_loadout()


func _apply_active_choice(item_id: StringName) -> void:
	var definition := FoldlightRogueContentCatalog.active_item_by_id(item_id)
	if definition == null:
		return
	run_controller.run_state.active_item_id = item_id
	player.active_item_slot.replace(definition)


func _equip_run_loadout() -> void:
	player.weapon_mount.unequip_all()
	for weapon_id in run_controller.run_state.weapon_ids:
		player.weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(weapon_id))
	player.active_item_slot.unequip()
	var active := FoldlightRogueContentCatalog.active_item_by_id(run_controller.run_state.active_item_id)
	if active != null:
		player.active_item_slot.replace(active)


func _update_prologue(delta: float) -> void:
	if _prologue_step_index == 0:
		_prologue_distance += player.global_position.distance_to(_prologue_last_position)
		_prologue_last_position = player.global_position
		current_wave_text = "移动 %d%%  ·  冲刺 %s" % [int(clampf(_prologue_distance / 280.0, 0.0, 1.0) * 100.0), "完成" if _prologue_dash_complete else "未完成"]
		_try_complete_prologue_movement()
	elif _prologue_step_index == 1:
		_prologue_volley_timer -= delta
		if _prologue_volley_timer <= 0.0:
			_prologue_volley_timer = 1.7
			var origin := player.global_position + Vector2.from_angle(randf() * TAU) * 420.0
			world.combat_runtime.spawn_hostile_volley({"origin": origin, "direction": origin.direction_to(player.global_position), "projectile_count": 5, "spread_radians": 0.42, "speed": 175.0, "reflectable": true, "damage": 0.0, "lifetime": 4.0})


func _advance_prologue_step() -> void:
	_prologue_step_index += 1
	if _prologue_step_index >= PROLOGUE_STEPS.size():
		_finish_prologue()
		return
	var step := PROLOGUE_STEPS[_prologue_step_index]
	presentation.show_prologue_step(_prologue_step_index + 1, PROLOGUE_STEPS.size(), str(step["title"]), str(step["body"]))
	current_wave_text = ""
	if _prologue_step_index == 1:
		_prologue_volley_timer = 0.35
	elif _prologue_step_index == 2:
		_start_prologue_encounter()


func _try_complete_prologue_movement() -> void:
	if mode == SessionMode.PROLOGUE and _prologue_step_index == 0 and _prologue_distance >= 280.0 and _prologue_dash_complete:
		_advance_prologue_step()


func _on_player_dash_started(_direction: Vector2, _duration: float) -> void:
	audio_director.play_sfx(&"ui", 0.72, -8.0)
	if mode == SessionMode.PROLOGUE and _prologue_step_index == 0:
		_prologue_dash_complete = true
		_try_complete_prologue_movement()


func _on_player_fold_released(captured_count: int, _charge_ratio: float) -> void:
	audio_director.play_sfx(&"release", 0.90 + minf(0.35, float(captured_count) * 0.015), -5.0)
	if captured_count > 0:
		var feedback_strength := minf(0.30, 0.10 + float(captured_count) * 0.018)
		world.camera.add_trauma(feedback_strength * float(profile_manager.get_setting(&"screen_shake", 1.0)))
		if bool(profile_manager.get_setting(&"vibration", true)):
			var rumble_strength := minf(0.34, 0.16 + float(captured_count) * 0.012)
			Input.start_joy_vibration(0, rumble_strength * 0.55, rumble_strength, 0.11)
	if mode == SessionMode.PROLOGUE and _prologue_step_index == 1 and captured_count >= 2:
		_advance_prologue_step()


func _on_projectile_captured(captured_count: int, _position: Vector2) -> void:
	if _capture_sfx_cooldown > 0.0:
		return
	_capture_sfx_cooldown = 0.055
	audio_director.play_sfx(&"capture", 0.88 + float(captured_count) * 0.025, -4.0)


func _on_player_active_item_used(_item_id: StringName) -> void:
	audio_director.play_sfx(&"act", 1.0, -5.0)
	if mode == SessionMode.PROLOGUE and _prologue_step_index == 2:
		current_wave_text = "主动技能已就绪 · 清理剩余敌人"


func _on_player_fold_started() -> void:
	audio_director.play_sfx(&"fold", 1.0, -7.0)


func _on_player_focus_empty(_captured_count: int, _charge_ratio: float) -> void:
	audio_director.play_sfx(&"empty", 0.86, -8.0)


func _on_player_statuses_cleansed(status_ids: Array[StringName]) -> void:
	if not status_ids.is_empty():
		audio_director.play_sfx(&"capture", 1.28, -7.0)


func _on_feedback_impact_batch(weight: float, count: int) -> void:
	audio_director.play_sfx(&"hit", clampf(0.90 + weight * 0.16 + float(count) * 0.003, 0.90, 1.16), -8.5)
	if _feedback_shake_cooldown <= 0.0:
		world.camera.add_trauma(minf(0.17, 0.045 + weight * 0.065) * float(profile_manager.get_setting(&"screen_shake", 1.0)))
		_feedback_shake_cooldown = 0.10


func _start_prologue_encounter() -> void:
	if _prologue_encounter_started:
		return
	_prologue_encounter_started = true
	player.invulnerability = 1.0
	var entries: Array[Dictionary] = [
		{"enemy_id": &"drifter", "wave": 0, "spawn_position": Vector2(780, 450), "role": 0, "threat_cost": 1},
		{"enemy_id": &"drifter", "wave": 0, "spawn_position": Vector2(2100, 450), "role": 0, "threat_cost": 1},
		{"enemy_id": &"fan", "wave": 0, "spawn_position": Vector2(1440, 380), "role": 1, "threat_cost": 2},
		{"enemy_id": &"drifter", "wave": 1, "spawn_position": Vector2(740, 980), "role": 0, "threat_cost": 1},
		{"enemy_id": &"ram", "wave": 1, "spawn_position": Vector2(2140, 920), "role": 2, "threat_cost": 3},
		{"enemy_id": &"paper_turret", "wave": 1, "spawn_position": Vector2(2460, 360), "role": 3, "threat_cost": 3},
	]
	var errors := world.room_runtime.begin_encounter({"encounter_id": &"prologue_final", "entries": entries, "errors": []})
	if not errors.is_empty():
		push_error("RogueSession: prologue encounter failed")


func _finish_prologue() -> void:
	mode = SessionMode.RESULT
	if persist_profile:
		profile_manager.mark_prologue_complete()
	world.deactivate()
	player.set_play_enabled(false)
	player.visible = false
	presentation.hide_prologue_step()
	presentation.show_result({"won": true}, true)
	audio_director.set_intensity(0.04)
	audio_director.play_sfx(&"victory", 1.0, -2.0)


func _on_prologue_skip_requested() -> void:
	if mode != SessionMode.PROLOGUE:
		return
	if persist_profile:
		profile_manager.mark_prologue_complete()
	presentation.hide_prologue_step()
	world.deactivate()
	start_new_run()


func _terrain_layout(region_id: StringName, category: StringName, depth: int) -> Array[Dictionary]:
	if category == &"boss":
		return _boss_terrain_layout(region_id)
	var templates := FoldlightRogueRoomTemplateCatalog.templates_for_region(region_id)
	var template := templates[posmod(depth, maxi(1, templates.size()))] if not templates.is_empty() else {}
	var result: Array[Dictionary] = []
	for placement_variant: Variant in template.get("terrain", []):
		if placement_variant is Dictionary:
			result.append((placement_variant as Dictionary).duplicate(true))
	return result


func _legacy_terrain_layout(region_id: StringName, category: StringName, depth: int) -> Array[Dictionary]:
	if category == &"boss":
		return _boss_terrain_layout(region_id)
	var base: Array[Dictionary] = []
	match region_id:
		&"inverted_ink_city":
			base = [
				_terrain("city_wall_a", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(880, 560), Vector2(390, 78), -0.18),
				_terrain("city_wall_b", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(1980, 850), Vector2(420, 78), 0.18),
				_terrain("city_pillar", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1440, 790), Vector2(170, 170)),
				_terrain("city_pillar_north", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1460, 280), Vector2(128, 128)),
				_terrain("city_ink_left", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(610, 1140), Vector2(500, 210)),
				_terrain("city_ink_right", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(2280, 420), Vector2(430, 190)),
				_terrain("city_current", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1450, 1220), Vector2(760, 145), 0.0, 0.82, Vector2.LEFT if depth % 2 == 0 else Vector2.RIGHT),
				_terrain("city_sun_refuge", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(2320, 1230), Vector2(330, 150), 0.0, 1.0),
				_terrain("city_thorn_cut", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(560, 350), Vector2(300, 120), -0.12, 1.0),
			]
		&"nameless_sun_court":
			base = [
				_terrain("sun_wall_left", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(920, 800), Vector2(500, 72), PI * 0.5),
				_terrain("sun_wall_right", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(1960, 800), Vector2(500, 72), PI * 0.5),
				_terrain("sun_pillar_top", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1440, 430), Vector2(155, 155)),
				_terrain("sun_pillar_low", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1440, 1190), Vector2(155, 155)),
				_terrain("sun_pillar_west", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(520, 810), Vector2(128, 128)),
				_terrain("sun_current", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1440, 810), Vector2(760, 180), 0.0, 1.0 + depth * 0.06, Vector2.RIGHT if depth % 2 == 0 else Vector2.LEFT),
				_terrain("sun_current_north", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1440, 250), Vector2(650, 130), 0.0, 0.72, Vector2.LEFT if depth % 2 == 0 else Vector2.RIGHT),
				_terrain("sun_blessing_west", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(520, 1220), Vector2(360, 160), 0.0, 1.15),
				_terrain("sun_blessing_east", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(2360, 440), Vector2(360, 160), 0.0, 1.15),
				_terrain("sun_ink_eclipse", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(2300, 1190), Vector2(360, 160)),
				_terrain("sun_thorn_verdict", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(600, 370), Vector2(340, 130), 0.16, 1.2),
			]
		_:
			base = [
				_terrain("reef_wall_left", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(820, 790), Vector2(420, 76), -0.28),
				_terrain("reef_wall_right", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(2050, 690), Vector2(420, 76), 0.28),
				_terrain("reef_pillar_top", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1440, 430), Vector2(145, 145)),
				_terrain("reef_pillar_low", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(1440, 1160), Vector2(145, 145)),
				_terrain("reef_pillar_west", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(470, 430), Vector2(125, 125)),
				_terrain("reef_current", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1440, 800), Vector2(650, 150), 0.0, 0.85, Vector2.RIGHT),
				_terrain("reef_current_south", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1850, 1260), Vector2(520, 130), 0.0, 0.72, Vector2.LEFT),
				_terrain("reef_sun_shoal", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(610, 1220), Vector2(360, 155), 0.0, 1.0),
				_terrain("reef_thorn_bed", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(2380, 1110), Vector2(330, 125), -0.14, 0.9),
			]
	var category_offset := absi(String(category).hash()) % 3
	return _apply_terrain_variant(base, posmod(depth + category_offset, 3))


func _boss_terrain_layout(region_id: StringName) -> Array[Dictionary]:
	match region_id:
		&"inverted_ink_city":
			return [
				_terrain("city_boss_seal_west", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(420, 460), Vector2(168, 168)),
				_terrain("city_boss_seal_east", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(2460, 1160), Vector2(168, 168)),
				_terrain("city_boss_roof_north", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(1440, 250), Vector2(540, 72), 0.0),
				_terrain("city_boss_roof_west", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(410, 920), Vector2(360, 70), PI * 0.5),
				_terrain("city_boss_ink_south", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(890, 1320), Vector2(470, 160), -0.08),
				_terrain("city_boss_ink_north", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(2160, 390), Vector2(400, 145), 0.14),
				_terrain("city_boss_refuge", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(2250, 1320), Vector2(360, 150)),
				_terrain("city_boss_cut", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(650, 310), Vector2(280, 115), -0.2, 1.0),
			]
		&"nameless_sun_court":
			return [
				_terrain("court_boss_gate_west", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(390, 810), Vector2(470, 72), PI * 0.5),
				_terrain("court_boss_gate_east", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(2490, 810), Vector2(470, 72), PI * 0.5),
				_terrain("court_boss_orbit_nw", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(760, 390), Vector2(150, 150)),
				_terrain("court_boss_orbit_se", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(2140, 1230), Vector2(150, 150)),
				_terrain("court_boss_procession", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1440, 1380), Vector2(860, 135), 0.0, 0.9, Vector2.RIGHT),
				_terrain("court_boss_mercy", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(670, 1230), Vector2(330, 145), 0.0, 1.15),
				_terrain("court_boss_eclipse", FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, Vector2(2210, 400), Vector2(340, 150)),
				_terrain("court_boss_verdict", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(1440, 260), Vector2(410, 115), 0.0, 1.2),
			]
		_:
			# The tide pulse needs an open centre. Cover and blessings live near
			# the perimeter so the player can read and use the new angular gap.
			return [
				_terrain("reef_boss_pillar_west", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(400, 720), Vector2(150, 150)),
				_terrain("reef_boss_pillar_east", FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, Vector2(2480, 900), Vector2(150, 150)),
				_terrain("reef_boss_breakwater_nw", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(760, 280), Vector2(350, 68), -0.20),
				_terrain("reef_boss_breakwater_ne", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, Vector2(2120, 280), Vector2(350, 68), 0.20),
				_terrain("reef_boss_current_south", FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE, Vector2(1440, 1390), Vector2(760, 120), 0.0, 0.72, Vector2.RIGHT),
				_terrain("reef_boss_sun_west", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(610, 1280), Vector2(330, 145), 0.0, 1.0),
				_terrain("reef_boss_sun_east", FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, Vector2(2270, 1280), Vector2(330, 145), 0.0, 1.0),
				_terrain("reef_boss_thorn_west", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(230, 1160), Vector2(240, 115), PI * 0.5, 0.82),
				_terrain("reef_boss_thorn_east", FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, Vector2(2650, 460), Vector2(240, 115), PI * 0.5, 0.82),
			]


func _apply_terrain_variant(source: Array[Dictionary], variant: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = source.duplicate(true)
	var center := WORLD_SIZE * 0.5
	for index in result.size():
		var placement := result[index]
		var point := Vector2(placement.get("position", center))
		var offset := point - center
		if variant == 1:
			point = center + Vector2(offset.y * 1.28, -offset.x * 0.50)
			placement["rotation"] = float(placement.get("rotation", 0.0)) + PI * 0.5
		elif variant == 2:
			point = center + Vector2(-offset.x * 0.92, offset.y * 0.86)
			point += Vector2(sin(float(index) * 1.73) * 105.0, cos(float(index) * 1.21) * 80.0)
			placement["rotation"] = -float(placement.get("rotation", 0.0)) + (0.12 if index % 2 == 0 else -0.12)
		point = point.clamp(Vector2(190, 190), WORLD_SIZE - Vector2(190, 190))
		var kind := int(placement.get("kind", FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL))
		if kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR] and point.distance_to(PLAYER_START) < 240.0:
			point.y = maxf(260.0, point.y - 360.0)
		elif point.distance_to(PLAYER_START) < 150.0:
			point.x = clampf(point.x + 260.0, 190.0, WORLD_SIZE.x - 190.0)
		placement["position"] = point
		if variant > 0:
			placement["id"] = "%s_v%d" % [str(placement.get("id", "terrain")), variant]
		result[index] = placement
	return result


func _terrain(id: String, kind: int, position_value: Vector2, size_value: Vector2, rotation_value: float = 0.0, strength: float = 1.0, direction: Vector2 = Vector2.RIGHT) -> Dictionary:
	return {"id": id, "kind": kind, "position": position_value, "size": size_value, "rotation": rotation_value, "strength": strength, "direction": direction}


func _spawn_slots() -> Array[Dictionary]:
	if not _current_room_template.is_empty():
		var authored: Array[Dictionary] = []
		for slot_variant: Variant in _current_room_template.get("spawn_slots", []):
			if slot_variant is Dictionary:
				authored.append((slot_variant as Dictionary).duplicate(true))
		return authored
	return [
		{"id": &"g01", "kind": &"ground", "position": Vector2(420, 330)}, {"id": &"g02", "kind": &"ground", "position": Vector2(820, 360)},
		{"id": &"g03", "kind": &"ground", "position": Vector2(1260, 300)}, {"id": &"g04", "kind": &"ground", "position": Vector2(1660, 320)},
		{"id": &"g05", "kind": &"ground", "position": Vector2(2100, 360)}, {"id": &"g06", "kind": &"ground", "position": Vector2(2480, 330)},
		{"id": &"g07", "kind": &"ground", "position": Vector2(430, 760)}, {"id": &"g08", "kind": &"ground", "position": Vector2(2440, 760)},
		{"id": &"g09", "kind": &"ground", "position": Vector2(520, 1240)}, {"id": &"g10", "kind": &"ground", "position": Vector2(920, 1300)},
		{"id": &"g11", "kind": &"ground", "position": Vector2(1840, 1300)}, {"id": &"g12", "kind": &"ground", "position": Vector2(2360, 1220)},
		{"id": &"g13", "kind": &"ground", "position": Vector2(310, 520)}, {"id": &"g14", "kind": &"ground", "position": Vector2(2580, 520)},
		{"id": &"g15", "kind": &"ground", "position": Vector2(710, 890)}, {"id": &"g16", "kind": &"ground", "position": Vector2(2160, 930)},
		{"id": &"g17", "kind": &"ground", "position": Vector2(1180, 1420)}, {"id": &"g18", "kind": &"ground", "position": Vector2(1710, 1420)},
		{"id": &"t01", "kind": &"turret", "position": Vector2(250, 260)}, {"id": &"t02", "kind": &"turret", "position": Vector2(2630, 260)},
		{"id": &"t03", "kind": &"turret", "position": Vector2(250, 1360)}, {"id": &"t04", "kind": &"turret", "position": Vector2(2630, 1360)},
		{"id": &"t05", "kind": &"turret", "position": Vector2(360, 810)}, {"id": &"t06", "kind": &"turret", "position": Vector2(2520, 810)},
	]


func _name_array(source: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if source is Array:
		for value: Variant in source:
			result.append(StringName(value))
	return result


func _string_array(source: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in source:
		result.append(String(value))
	return result


func _category_display(category: StringName) -> String:
	return {&"entry": "入潮口", &"combat": "交锋房", &"elite": "高压房", &"cache": "藏光室", &"event": "异潮室", &"forge": "折纸坊", &"shop": "漂灯市", &"rest": "静水泊"}.get(category, "房间")


func _can_advance_encounter() -> bool:
	if not world.visible or presentation.screen_kind != &"hud":
		return false
	if mode == SessionMode.PROLOGUE:
		return true
	return mode == SessionMode.RUN and run_controller.phase in [FoldlightRogueRunController.Phase.ENTERING_ROOM, FoldlightRogueRunController.Phase.COMBAT]


func _enter_modal_safety() -> void:
	player.suspend_for_overlay()
	world.combat_runtime.set_active(false)


func _pause_game() -> void:
	if _paused or mode not in [SessionMode.RUN, SessionMode.PROLOGUE]:
		return
	_paused = true
	_enter_modal_safety()
	presentation.show_pause()
	audio_director.set_intensity(0.045)


func is_paused() -> bool:
	return _paused and presentation.screen_kind == &"pause"


func set_browse_mode_enabled(enabled: bool) -> void:
	player.set_debug_invincible(enabled)
	presentation.set_browse_mode_enabled(enabled)


func _resume_game() -> void:
	if not _paused:
		return
	_paused = false
	world.combat_runtime.set_active(true)
	player.resume_from_overlay(0.6)
	if mode == SessionMode.PROLOGUE:
		var step := PROLOGUE_STEPS[_prologue_step_index]
		presentation.show_prologue_step(_prologue_step_index + 1, PROLOGUE_STEPS.size(), str(step["title"]), str(step["body"]))
	else:
		presentation.show_hud()
	audio_director.set_intensity(0.18 + float(run_controller.run_state.current_region) * 0.13)


func _on_abandon_requested() -> void:
	if not _paused:
		return
	_paused = false
	if mode == SessionMode.RUN:
		run_controller.fail_run(&"abandoned")
	else:
		enter_title()


func _on_settings_requested() -> void:
	var return_screen := &"pause" if _paused else &"title"
	presentation.show_settings(profile_manager.settings.duplicate(true), return_screen)


func _on_settings_back_requested(return_screen: StringName) -> void:
	if return_screen == &"pause" and _paused:
		presentation.show_pause()
	else:
		presentation.show_title(profile_manager.get_roguelite_snapshot())


func _on_setting_adjust_requested(setting_key: StringName, direction: int) -> void:
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
	presentation.refresh_settings(profile_manager.settings)
	audio_director.play_sfx(&"ui", 1.0 + float(direction) * 0.06, -7.0)
