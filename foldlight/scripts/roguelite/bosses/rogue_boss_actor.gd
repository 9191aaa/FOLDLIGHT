class_name FoldlightRogueBossActor
extends CharacterBody2D

const HitReaction = preload("res://scripts/visuals/paper_hit_reaction.gd")
const Puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
const REMNANT = preload("res://scripts/visuals/boss_paper_remnant.gd")
const RECOIL_SECONDS: float = 0.30

signal damaged(amount: float, health_remaining: float, source: StringName)
signal defeated(actor: Node2D)
signal phase_changed(phase_index: int)
signal telegraph_requested(snapshot: Dictionary)
signal volley_requested(snapshot: Dictionary)
signal minion_requested(snapshot: Dictionary)
signal zone_requested(snapshot: Dictionary)
signal arena_hit_requested
signal stagger_started(duration: float)

var definition: FoldlightRogueBossDefinition
var actor_id: StringName = &"boss"
var health: float = 1.0
var return_meter: float = 0.0

var _room_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(2880, 1620))
var _target_position: Vector2 = Vector2.ZERO
var _locked_attack_origin: Vector2 = Vector2.ZERO
var _locked_attack_target: Vector2 = Vector2.ZERO
var _attack_locked: bool = false
var _return_window_budget: float = 0.0
var _arena_damage_remaining: float = 0.0
var _hit_reaction := HitReaction.new()
var _visual_time: float = 0.0
var _motion_scale: float = 1.0
var _recoil_remaining: float = 0.0
var _stagger_pose: float = 0.0
var _visual_direction := Vector2.DOWN
var _simulation_active: bool = true
var _death_remnant_spawned: bool = false
var _rng := RandomNumberGenerator.new()

@onready var phase_controller: FoldlightBossPhaseController = $PhaseController
@onready var arena_controller: FoldlightBossArenaController = $ArenaController


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	phase_controller.phase_changed.connect(_on_phase_changed)
	phase_controller.telegraph_started.connect(_on_telegraph_started)
	phase_controller.attack_ready.connect(_on_attack_ready)
	phase_controller.stagger_started.connect(_on_stagger_started)
	queue_redraw()


func configure(new_definition: FoldlightRogueBossDefinition, bounds: Rect2, seed: int = 330031) -> void:
	definition = new_definition
	actor_id = definition.content_id if definition != null else &"boss"
	health = definition.base_health if definition != null else 1.0
	_hit_reaction.reset()
	_visual_time = 0.0
	_recoil_remaining = 0.0
	_stagger_pose = 0.0
	_visual_direction = Vector2.DOWN
	_simulation_active = true
	_death_remnant_spawned = false
	_refresh_motion_setting()
	_room_bounds = bounds
	_rng.seed = seed
	return_meter = 0.0
	_return_window_budget = 0.0
	_attack_locked = false
	_arena_damage_remaining = 0.0
	global_position = bounds.get_center()
	phase_controller.configure(definition)
	arena_controller.configure(definition.arena_rule, bounds)
	queue_redraw()


func advance_simulation(delta: float, player_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if definition == null or health <= 0.0 or not _simulation_active:
		return
	_refresh_motion_setting()
	_hit_reaction.advance(maxf(0.0, delta))
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	_visual_time += safe_delta
	_recoil_remaining = maxf(0.0, _recoil_remaining - safe_delta)
	_target_position = player_position
	phase_controller.advance_simulation(safe_delta, health / definition.base_health)
	var stagger_target := 1.0 if phase_controller.state == FoldlightBossPhaseController.State.STAGGERED else 0.0
	_stagger_pose = move_toward(_stagger_pose, stagger_target, safe_delta * 6.0)
	arena_controller.set_pressure_suspended(phase_controller.state in [FoldlightBossPhaseController.State.INTRO, FoldlightBossPhaseController.State.STAGGERED])
	arena_controller.advance_simulation(safe_delta, player_position)
	_update_movement(safe_delta)
	_arena_damage_remaining = maxf(0.0, _arena_damage_remaining - safe_delta)
	if not arena_controller.is_player_safe(player_position) and _arena_damage_remaining <= 0.0:
		_arena_damage_remaining = 0.72
		arena_hit_requested.emit()
	move_and_slide()
	_clamp_to_active_arena()
	queue_redraw()


func take_damage(amount: float, source: StringName = &"weapon", incoming_velocity: Vector2 = Vector2.ZERO) -> bool:
	if definition == null or health <= 0.0 or amount <= 0.0:
		return false
	var applied := amount
	var was_staggered: bool = phase_controller.state == FoldlightBossPhaseController.State.STAGGERED
	if source == &"return":
		if phase_controller.state == FoldlightBossPhaseController.State.STAGGERED:
			applied = minf(amount, _return_window_budget)
			_return_window_budget = maxf(0.0, _return_window_budget - applied)
		else:
			applied = minf(amount * definition.return_damage_outside_stagger, definition.base_health * 0.12)
			return_meter += amount
			# A full basic store (8 charged lights, 22.4 damage) must be enough
			# to earn a window even against the final boss's larger health pool.
			if return_meter >= clampf(definition.base_health * 0.025, 18.0, 22.0):
				return_meter = 0.0
				phase_controller.enter_stagger(definition.return_window_seconds)
	if applied <= 0.0:
		return false
	health = maxf(0.0, health - applied)
	var impact_direction: Vector2 = incoming_velocity
	if impact_direction.is_zero_approx():
		impact_direction = _target_position.direction_to(global_position)
	var opened_window: bool = not was_staggered and phase_controller.state == FoldlightBossPhaseController.State.STAGGERED
	_hit_reaction.trigger(impact_direction, source, health <= 0.0 or opened_window)
	damaged.emit(applied, health, source)
	if health <= 0.0:
		phase_controller.mark_defeated()
		_spawn_death_remnant()
		defeated.emit(self)
		return true
	queue_redraw()
	return false


func set_support_buff(_attack_multiplier: float) -> void:
	pass


func request_opening_support() -> void:
	if definition != null and definition.content_id == &"inverted_archivist":
		_request_archivist_support()


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.BOSS, "health": health, "maximum_health": definition.base_health if definition != null else 1.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return _hit_reaction.snapshot()


func set_simulation_active(value: bool) -> void:
	_simulation_active = value


func _refresh_motion_setting() -> void:
	var profile := get_node_or_null("/root/ProfileManager")
	_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0


func get_visual_pose() -> Dictionary:
	var state := phase_controller.get_presentation_snapshot()
	var intro := float(state["progress"]) if phase_controller.state == FoldlightBossPhaseController.State.INTRO else 1.0
	return {
		"phase": phase_controller.phase_index,
		"time": _visual_time if _motion_scale > 0.0 else 0.0,
		"motion_scale": _motion_scale,
		"intro": intro if _motion_scale > 0.0 else 1.0,
		"charge": float(state["progress"]) if phase_controller.state == FoldlightBossPhaseController.State.TELEGRAPH else 0.0,
		"recoil": pow(_recoil_remaining / RECOIL_SECONDS, 2.0),
		"stagger": _stagger_pose,
		"transition": float(state["transition"]),
		"transition_active": bool(state["transition_active"]),
		"death": 0.0,
		"direction": _visual_direction,
		"flash": _hit_reaction.flash,
		"accent": definition.accent if definition != null else FoldlightTheme.GOLD,
	}


func _spawn_death_remnant() -> void:
	if _death_remnant_spawned or not is_inside_tree():
		return
	_death_remnant_spawned = true
	var holder: Node = get_parent()
	var ancestor := holder
	while ancestor != null:
		if ancestor is FoldlightRoomRuntime:
			holder = ancestor
			break
		ancestor = ancestor.get_parent()
	if holder == null:
		return
	var remnant := REMNANT.new()
	remnant.name = "BossPaperRemnant"
	holder.add_child(remnant)
	remnant.global_transform = global_transform
	remnant.configure(actor_id, get_visual_pose())
	remnant.set_simulation_active(_simulation_active)


func _update_movement(delta: float) -> void:
	if phase_controller.state == FoldlightBossPhaseController.State.TELEGRAPH:
		# The warning and the volley share one origin and one target. Keeping the
		# body still also prevents a mobile boss firing behind its drawn warning.
		velocity = Vector2.ZERO
		return
	if phase_controller.state in [FoldlightBossPhaseController.State.INTRO, FoldlightBossPhaseController.State.STAGGERED]:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		return
	match definition.content_id:
		&"reef_crown_battery":
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		&"inverted_archivist":
			var offset := _target_position - global_position
			var desired := offset.normalized().orthogonal() * 92.0
			if offset.length() > 690.0:
				desired += offset.normalized() * 65.0
			elif offset.length() < 480.0:
				desired -= offset.normalized() * 80.0
			velocity = velocity.move_toward(desired, 360.0 * delta)
		&"origami_judge":
			var frame_center := arena_controller.safe_rect.get_center()
			velocity = velocity.move_toward(global_position.direction_to(frame_center) * 76.0, 300.0 * delta)


func _clamp_to_active_arena() -> void:
	var legal_bounds := _room_bounds.grow(-100.0)
	if definition != null and definition.arena_rule == &"moving_safe_frame":
		# The judge must obey the same moving frame it imposes on the player.
		# Clamping after move_and_slide closes the one-frame escape visible in 3.0.
		legal_bounds = arena_controller.safe_rect.grow(-86.0)
	global_position = global_position.clamp(legal_bounds.position + Vector2.ONE, legal_bounds.end - Vector2.ONE)


func _on_phase_changed(new_phase: int) -> void:
	_attack_locked = false
	arena_controller.set_phase(new_phase)
	if definition.content_id == &"reef_crown_battery":
		_request_reef_support()
	elif definition.content_id == &"inverted_archivist":
		_request_archivist_support()
	_recoil_remaining = 0.0
	phase_changed.emit(new_phase)


func _on_telegraph_started(pattern_id: StringName, duration: float) -> void:
	_locked_attack_origin = global_position
	_locked_attack_target = _target_position
	_visual_direction = _locked_attack_origin.direction_to(_locked_attack_target)
	if _visual_direction.is_zero_approx():
		_visual_direction = Vector2.DOWN
	_attack_locked = true
	telegraph_requested.emit({"pattern_id": pattern_id, "duration": duration, "origin": _locked_attack_origin, "target_position": _locked_attack_target, "accent": definition.accent, "phase": phase_controller.phase_index, "spread_radians": _black_gold_spread(pattern_id), "zone_radius": 165.0 if pattern_id == &"ink_partition" else 0.0})


func _on_stagger_started(duration: float) -> void:
	_attack_locked = false
	_recoil_remaining = 0.0
	_return_window_budget = definition.base_health * definition.return_window_fraction
	arena_controller.set_pressure_suspended(true)
	stagger_started.emit(duration)


func _on_attack_ready(pattern_id: StringName, telegraph_duration: float) -> void:
	_recoil_remaining = RECOIL_SECONDS
	match definition.content_id:
		&"reef_crown_battery":
			_emit_reef_pattern(pattern_id, telegraph_duration)
		&"inverted_archivist":
			_emit_archivist_pattern(pattern_id, telegraph_duration)
		&"origami_judge":
			_emit_judge_pattern(pattern_id, telegraph_duration)
	_attack_locked = false


func _emit_reef_pattern(pattern_id: StringName, telegraph: float) -> void:
	match pattern_id:
		&"petal_salvo":
			var salvo := _volley_snapshot(6 + phase_controller.phase_index, 310.0 + phase_controller.phase_index * 18.0, 0.92, true, &"reef_petal", telegraph, false)
			salvo["burst_count"] = 3
			salvo["burst_interval"] = 0.28
			salvo["burst_angle_step"] = 0.08
			volley_requested.emit(salvo)
			_request_reef_support()
		&"tide_fan":
			var tide_fan := _volley_snapshot(9 + phase_controller.phase_index * 2, 285.0 + phase_controller.phase_index * 14.0, TAU, true, &"crown_ring", telegraph, true)
			tide_fan["burst_count"] = 2
			tide_fan["burst_interval"] = 0.36
			tide_fan["burst_angle_step"] = PI / float(9 + phase_controller.phase_index * 2)
			tide_fan["curve"] = 0.18
			volley_requested.emit(tide_fan)
		&"black_lane":
			_emit_aimed_volley(3 + phase_controller.phase_index, 425.0 + phase_controller.phase_index * 16.0, _black_gold_spread(pattern_id), false, &"black_gold_cut", telegraph)
		&"turret_crown":
			var crown := _volley_snapshot(12 + phase_controller.phase_index, 295.0, TAU, true, &"crown_ring", telegraph, true)
			crown["burst_count"] = 2
			crown["burst_interval"] = 0.34
			crown["burst_angle_step"] = 0.11
			volley_requested.emit(crown)
			minion_requested.emit({
				"enemy_id": &"paper_turret",
				"maximum": 2,
				"total_maximum": 4,
				"positions": [Vector2(_room_bounds.position.x + 220.0, _room_bounds.position.y + 240.0), Vector2(_room_bounds.end.x - 220.0, _room_bounds.position.y + 240.0)],
			})
		_:
			push_warning("Reef Crown: unknown pattern %s" % pattern_id)


func _request_reef_support() -> void:
	var support_ids: Array[StringName]
	match phase_controller.phase_index:
		0:
			support_ids = [&"drifter", &"fan"]
		1:
			support_ids = [&"ram", &"bloomer"]
		_:
			support_ids = [&"weaver", &"drifter"]
	minion_requested.emit({
		"enemy_ids": support_ids,
		"maximum": 2 if phase_controller.phase_index < 2 else 3,
		"total_maximum": 3 if phase_controller.phase_index < 2 else 4,
		"positions": [
			Vector2(_room_bounds.position.x + 380.0, _room_bounds.position.y + 360.0),
			Vector2(_room_bounds.end.x - 380.0, _room_bounds.position.y + 360.0),
			Vector2(_room_bounds.position.x + 440.0, _room_bounds.end.y - 330.0),
			Vector2(_room_bounds.end.x - 440.0, _room_bounds.end.y - 330.0),
		],
	})


func _emit_archivist_pattern(pattern_id: StringName, telegraph: float) -> void:
	match pattern_id:
		&"ledger_petals":
			volley_requested.emit(_volley_snapshot(12 + phase_controller.phase_index * 2, 310.0 + phase_controller.phase_index * 14.0, TAU, true, &"ledger_petal", telegraph, true))
			_request_archivist_support()
		&"ink_partition":
			_emit_aimed_volley(8 + phase_controller.phase_index * 2, 340.0, 0.82, true, &"ink_petal", telegraph)
			zone_requested.emit({"position": _locked_attack_target if _attack_locked else _target_position, "radius": 165.0, "duration": 3.6, "movement_multiplier": 0.72})
		&"margin_cut":
			_emit_aimed_volley(6 + phase_controller.phase_index * 2, 450.0, _black_gold_spread(pattern_id), false, &"black_gold_cut", telegraph)


func _request_archivist_support() -> void:
	var support_ids: Array[StringName] = [&"ink_warden", &"bell_binder"]
	if phase_controller.phase_index == 0:
		support_ids = [&"shear_scribe", &"ink_warden"]
	minion_requested.emit({
		"enemy_ids": support_ids,
		"maximum": 2 if phase_controller.phase_index == 0 else 3,
		"total_maximum": 3 if phase_controller.phase_index < 2 else 4,
		# Central positions keep projectile sources visible and prevent the fight
		# from degenerating into off-screen edge fire.
		"positions": [
			_room_bounds.get_center() + Vector2(-520, -270),
			_room_bounds.get_center() + Vector2(520, -270),
			_room_bounds.get_center() + Vector2(-560, 300),
			_room_bounds.get_center() + Vector2(560, 300),
		],
	})


func _emit_judge_pattern(pattern_id: StringName, telegraph: float) -> void:
	match pattern_id:
		&"judgement_petals":
			volley_requested.emit(_volley_snapshot(16 + phase_controller.phase_index, 370.0 + phase_controller.phase_index * 18.0, TAU, true, &"judgement_petal", telegraph, true))
		&"unreflectable_cut":
			_emit_aimed_volley(8 + phase_controller.phase_index * 2, 485.0 + phase_controller.phase_index * 15.0, _black_gold_spread(pattern_id), false, &"black_gold_cut", telegraph)
		&"shrinking_frame":
			volley_requested.emit(_volley_snapshot(18, 395.0, TAU, true, &"frame_petal", telegraph, true))
			_emit_aimed_volley(3, 500.0, _black_gold_spread(pattern_id), false, &"black_gold_cut", telegraph)


func _black_gold_spread(pattern_id: StringName) -> float:
	return float({&"black_lane": 0.30, &"margin_cut": 0.58, &"unreflectable_cut": 0.68, &"shrinking_frame": 0.24}.get(pattern_id, 0.0))


func _emit_aimed_volley(count: int, speed: float, spread: float, reflectable: bool, style: StringName, telegraph: float) -> void:
	volley_requested.emit(_volley_snapshot(count, speed, spread, reflectable, style, telegraph, false))


func _volley_snapshot(count: int, speed: float, spread: float, reflectable: bool, style: StringName, telegraph: float, radial: bool) -> Dictionary:
	var origin := _locked_attack_origin if _attack_locked else global_position
	var target := _locked_attack_target if _attack_locked else _target_position
	var direction := origin.direction_to(target)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return {
		"origin": origin,
		"direction": direction,
		"projectile_count": clampi(count, 1, 18),
		"spread_radians": spread,
		"reflectable": reflectable,
		"speed": speed,
		"damage": 1.0,
		"radius": 8.0 if reflectable else 10.0,
		"lifetime": 6.2,
		"style": style,
		"radial": radial,
		"telegraph": telegraph,
	}


func _draw() -> void:
	if definition == null or health <= 0.0:
		return
	var pose := get_visual_pose()
	var punch := _hit_reaction.punch * _motion_scale
	var hit_offset := _hit_reaction.direction * punch * 4.5
	var hit_scale := Vector2(1.0 + punch * 0.055, 1.0 - punch * 0.035)
	# Pose transforms are visual only: the actual body and 52px hit circle stay
	# at the authored attack origin throughout charge, recoil and unfolding.
	draw_set_transform(hit_offset, 0.0, hit_scale)
	Puppet.draw_puppet(self, actor_id, pose)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _motion_scale > 0.0:
		_hit_reaction.draw_details(self, 68.0)
	var bounds := Puppet.get_visual_bounds(actor_id)
	var health_ratio := clampf(health / definition.base_health, 0.0, 1.0)
	var accent := definition.accent.lerp(Color.WHITE, _hit_reaction.flash * 0.62)
	if phase_controller.state == FoldlightBossPhaseController.State.STAGGERED:
		accent = FoldlightTheme.FOLD
	var bar_width := minf(212.0, bounds.size.x * 0.72)
	var bar_origin := Vector2(-bar_width * 0.5, bounds.position.y - 18.0)
	draw_rect(Rect2(bar_origin, Vector2(bar_width, 8.0)), FoldlightTheme.INK, true)
	draw_rect(Rect2(bar_origin, Vector2(bar_width * health_ratio, 8.0)), accent, true)
	# Three small paper tabs communicate the permanent phase even with motion
	# reduced to zero, without adding a flashing halo around the hurt area.
	for index in 3:
		var color := accent if index <= phase_controller.phase_index else Color(accent, 0.22)
		draw_rect(Rect2(bar_origin + Vector2(float(index) * 12.0, -7.0), Vector2(8.0, 3.0)), color, true)
