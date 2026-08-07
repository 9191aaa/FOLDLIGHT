class_name FoldlightRogueBossActor
extends CharacterBody2D

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
var _return_window_budget: float = 0.0
var _arena_damage_remaining: float = 0.0
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0
var _hit_ring: float = 0.0
var _visual_time: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var phase_controller: FoldlightBossPhaseController = $PhaseController
@onready var arena_controller: FoldlightBossArenaController = $ArenaController
@onready var aura: Polygon2D = $Aura
@onready var phase_particles: GPUParticles2D = $PhaseParticles


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
	_room_bounds = bounds
	_rng.seed = seed
	return_meter = 0.0
	_return_window_budget = 0.0
	global_position = bounds.get_center()
	phase_controller.configure(definition)
	arena_controller.configure(definition.arena_rule, bounds)
	var material := aura.material as ShaderMaterial
	if material != null:
		material = material.duplicate() as ShaderMaterial
		aura.material = material
		material.set_shader_parameter("accent", definition.accent)
		material.set_shader_parameter("intensity", 0.42)
	queue_redraw()


func advance_simulation(delta: float, player_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if definition == null or health <= 0.0:
		return
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.0)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.0)
	_hit_ring = maxf(0.0, _hit_ring - maxf(0.0, delta) * 5.2)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	_visual_time += safe_delta
	_target_position = player_position
	phase_controller.advance_simulation(safe_delta, health / definition.base_health)
	arena_controller.advance_simulation(safe_delta, player_position)
	_update_movement(safe_delta)
	_arena_damage_remaining = maxf(0.0, _arena_damage_remaining - safe_delta)
	if not arena_controller.is_player_safe(player_position) and _arena_damage_remaining <= 0.0:
		_arena_damage_remaining = 0.72
		arena_hit_requested.emit()
	move_and_slide()
	_clamp_to_active_arena()
	queue_redraw()


func take_damage(amount: float, source: StringName = &"weapon") -> bool:
	if definition == null or health <= 0.0 or amount <= 0.0:
		return false
	var applied := amount
	if source == &"return":
		if phase_controller.state == FoldlightBossPhaseController.State.STAGGERED:
			applied = minf(amount, _return_window_budget)
			_return_window_budget = maxf(0.0, _return_window_budget - applied)
		else:
			applied = minf(amount * definition.return_damage_outside_stagger, definition.base_health * 0.12)
			return_meter += amount
			if return_meter >= maxf(18.0, definition.base_health * 0.025):
				return_meter = 0.0
				phase_controller.enter_stagger(definition.return_window_seconds)
	if applied <= 0.0:
		return false
	health = maxf(0.0, health - applied)
	_hit_flash = 1.0
	_hit_punch = maxf(_hit_punch, 0.88)
	_hit_ring = 1.0
	damaged.emit(applied, health, source)
	if health <= 0.0:
		phase_controller.mark_defeated()
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
	return {"flash": _hit_flash, "punch": _hit_punch, "ring": _hit_ring}


func _update_movement(delta: float) -> void:
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
	arena_controller.set_phase(new_phase)
	if definition.content_id == &"reef_crown_battery":
		_request_reef_support()
	elif definition.content_id == &"inverted_archivist":
		_request_archivist_support()
	phase_particles.restart()
	phase_particles.emitting = true
	var material := aura.material as ShaderMaterial
	if material != null:
		var tween := create_tween()
		tween.tween_method(func(value: float) -> void: material.set_shader_parameter("intensity", value), 0.9, 0.52 + float(new_phase) * 0.12, 0.42)
	phase_changed.emit(new_phase)


func _on_telegraph_started(pattern_id: StringName, duration: float) -> void:
	telegraph_requested.emit({"pattern_id": pattern_id, "duration": duration, "origin": global_position, "target_position": _target_position, "accent": definition.accent, "phase": phase_controller.phase_index})


func _on_stagger_started(duration: float) -> void:
	_return_window_budget = definition.base_health * definition.return_window_fraction
	stagger_started.emit(duration)


func _on_attack_ready(pattern_id: StringName, telegraph_duration: float) -> void:
	match definition.content_id:
		&"reef_crown_battery":
			_emit_reef_pattern(pattern_id, telegraph_duration)
		&"inverted_archivist":
			_emit_archivist_pattern(pattern_id, telegraph_duration)
		&"origami_judge":
			_emit_judge_pattern(pattern_id, telegraph_duration)


func _emit_reef_pattern(pattern_id: StringName, telegraph: float) -> void:
	match pattern_id:
		&"petal_salvo":
			var salvo := _volley_snapshot(7 + phase_controller.phase_index, 350.0 + phase_controller.phase_index * 18.0, 0.92, true, &"reef_petal", telegraph, false)
			salvo["burst_count"] = 3
			salvo["burst_interval"] = 0.18
			salvo["burst_angle_step"] = 0.08
			volley_requested.emit(salvo)
			_request_reef_support()
		&"tide_fan":
			var tide_fan := _volley_snapshot(12 + phase_controller.phase_index * 2, 305.0 + phase_controller.phase_index * 16.0, TAU, true, &"crown_ring", telegraph, true)
			tide_fan["burst_count"] = 2
			tide_fan["burst_interval"] = 0.28
			tide_fan["burst_angle_step"] = PI / float(12 + phase_controller.phase_index * 2)
			tide_fan["curve"] = 0.18
			volley_requested.emit(tide_fan)
		&"black_lane":
			_emit_aimed_volley(5 + phase_controller.phase_index, 455.0 + phase_controller.phase_index * 20.0, 0.38, false, &"black_gold_cut", telegraph)
		&"turret_crown":
			var crown := _volley_snapshot(14 + phase_controller.phase_index, 320.0, TAU, true, &"crown_ring", telegraph, true)
			crown["burst_count"] = 2
			crown["burst_interval"] = 0.24
			crown["burst_angle_step"] = 0.11
			volley_requested.emit(crown)
			minion_requested.emit({
				"enemy_id": &"paper_turret",
				"maximum": 2,
				"total_maximum": 6,
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
		"maximum": 4,
		"total_maximum": 6,
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
			volley_requested.emit(_volley_snapshot(13 + phase_controller.phase_index * 2, 330.0 + phase_controller.phase_index * 16.0, TAU, true, &"ledger_petal", telegraph, true))
			_request_archivist_support()
		&"ink_partition":
			_emit_aimed_volley(9 + phase_controller.phase_index * 2, 365.0, 0.82, true, &"ink_petal", telegraph)
			zone_requested.emit({"position": _target_position, "radius": 205.0, "duration": 4.6, "movement_multiplier": 0.62})
		&"margin_cut":
			_emit_aimed_volley(7 + phase_controller.phase_index * 2, 490.0, 0.72, false, &"black_gold_cut", telegraph)


func _request_archivist_support() -> void:
	var support_ids: Array[StringName] = [&"ink_warden", &"bell_binder"]
	if phase_controller.phase_index == 0:
		support_ids = [&"shear_scribe", &"ink_warden"]
	minion_requested.emit({
		"enemy_ids": support_ids,
		"maximum": 4 + phase_controller.phase_index,
		"total_maximum": 6,
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
			_emit_aimed_volley(8 + phase_controller.phase_index * 2, 535.0 + phase_controller.phase_index * 20.0, 0.82, false, &"black_gold_cut", telegraph)
		&"shrinking_frame":
			volley_requested.emit(_volley_snapshot(18, 395.0, TAU, true, &"frame_petal", telegraph, true))
			_emit_aimed_volley(4, 580.0, 0.28, false, &"black_gold_cut", telegraph)


func _emit_aimed_volley(count: int, speed: float, spread: float, reflectable: bool, style: StringName, telegraph: float) -> void:
	volley_requested.emit(_volley_snapshot(count, speed, spread, reflectable, style, telegraph, false))


func _volley_snapshot(count: int, speed: float, spread: float, reflectable: bool, style: StringName, telegraph: float, radial: bool) -> Dictionary:
	var direction := global_position.direction_to(_target_position)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return {
		"origin": global_position,
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
	if definition == null:
		return
	var accent := definition.accent.lerp(Color.WHITE, _hit_flash * 0.76)
	var phase := phase_controller.phase_index
	var is_reef_crown := definition.content_id == &"reef_crown_battery"
	var silhouette_radius := 108.0 if is_reef_crown else 66.0
	if _hit_ring > 0.0:
		var ring_progress := 1.0 - _hit_ring
		draw_arc(Vector2.ZERO, silhouette_radius + ring_progress * 34.0, -PI * 0.88, PI * 0.88, 36, Color(1.0, 0.84, 0.48, _hit_ring * 0.78), 5.0 - ring_progress * 1.8, false)
	var boss_breathe := sin(_visual_time * (2.2 + float(phase) * 0.25))
	var boss_offset := Vector2(0.0, boss_breathe * (2.0 if is_reef_crown else 4.0))
	var boss_scale := Vector2(1.0 + _hit_punch * 0.08 + boss_breathe * 0.012, 1.0 - _hit_punch * 0.05 - boss_breathe * 0.018)
	draw_set_transform(boss_offset, boss_breathe * (0.008 if is_reef_crown else 0.022), boss_scale)
	for ring in range(4 + phase, 0, -1):
		draw_circle(Vector2.ZERO, (76.0 if is_reef_crown else 44.0) + float(ring) * 9.0, Color(accent, 0.018 * float(6 - mini(ring, 5))))
	match definition.content_id:
		&"reef_crown_battery":
			# A wide, top-heavy mobile fortress.  Hard blocks and four legs keep
			# the boss readable above the reef terrain at normal play scale.
			draw_rect(Rect2(Vector2(-101.0, 48.0), Vector2(202.0, 34.0)), Color("151b1c"), true)
			var crown := PackedVector2Array([
				Vector2(-92, 48), Vector2(-82, -45), Vector2(-55, -72),
				Vector2(-30, -30), Vector2(0, -94), Vector2(30, -30),
				Vector2(56, -76), Vector2(84, -46), Vector2(92, 48),
			])
			var crown_fill := Color("8b7958").lerp(Color.WHITE, _hit_flash * 0.58)
			draw_colored_polygon(crown, crown_fill)
			var crown_inset := PackedVector2Array([
				Vector2(-72, 34), Vector2(-55, -40), Vector2(-24, 18),
				Vector2(0, -78), Vector2(25, 18), Vector2(56, -45), Vector2(72, 34),
			])
			draw_colored_polygon(crown_inset, Color("d2bd83").lerp(Color.WHITE, _hit_flash * 0.46))
			draw_polyline(PackedVector2Array(Array(crown) + [crown[0]]), accent, 7.0, false)
			# Side batteries foreshadow turret-crown summons.
			for turret_x in [-72.0, 72.0]:
				draw_rect(Rect2(Vector2(turret_x - 17.0, -42.0), Vector2(34.0, 47.0)), Color("55433a"), true)
				draw_rect(Rect2(Vector2(turret_x - 27.0, -52.0), Vector2(54.0, 13.0)), Color("d96c3f"), true)
				draw_rect(Rect2(Vector2(turret_x - 7.0, -67.0), Vector2(14.0, 18.0)), Color("f4e8c7"), true)
			# Black-gold core is the break window target.
			draw_rect(Rect2(Vector2(-32.0, -13.0), Vector2(64.0, 55.0)), Color("190e20"), true)
			draw_rect(Rect2(Vector2(-22.0, -4.0), Vector2(44.0, 36.0)), Color("713d36"), true)
			draw_rect(Rect2(Vector2(-13.0, 4.0), Vector2(26.0, 18.0)), Color("f4bd58"), true)
			draw_rect(Rect2(Vector2(-5.0, 9.0), Vector2(10.0, 8.0)), Color.WHITE, true)
			for leg_x in [-72.0, -25.0, 25.0, 72.0]:
				draw_rect(Rect2(Vector2(leg_x - 9.0, 78.0), Vector2(18.0, 25.0 + absf(leg_x) * 0.12)), Color("3c3531"), true)
			for phase_mark in phase + 1:
				draw_rect(Rect2(Vector2(-18.0 + phase_mark * 18.0, 58.0), Vector2(10.0, 7.0)), accent, true)
		&"inverted_archivist":
			var book := Rect2(Vector2(-50, -42), Vector2(100, 84))
			draw_rect(book, Color(0.11, 0.06, 0.18, 0.98).lerp(Color.WHITE, _hit_flash * 0.58), true)
			draw_rect(book, accent, false, 6.0, true)
			draw_line(Vector2(0, -40), Vector2(0, 40), Color(0.96, 0.70, 1.0), 4.0, true)
			for page in 4:
				var page_angle := _visual_time * 0.36 + float(page) * TAU / 4.0
				var page_center := Vector2.from_angle(page_angle) * 78.0
				var page_shape := PackedVector2Array([page_center + Vector2(-13,-7), page_center + Vector2(14,-4), page_center + Vector2(10,8), page_center + Vector2(-11,6)])
				draw_colored_polygon(page_shape, Color(0.82, 0.54, 0.90, 0.18))
				draw_polyline(PackedVector2Array(Array(page_shape) + [page_shape[0]]), Color(accent, 0.38), 1.5, true)
		&"origami_judge":
			var judge := PackedVector2Array([Vector2(0, -58), Vector2(48, -22), Vector2(38, 48), Vector2(0, 30), Vector2(-38, 48), Vector2(-48, -22)])
			draw_colored_polygon(judge, Color(0.16, 0.08, 0.08, 0.98).lerp(Color.WHITE, _hit_flash * 0.58))
			draw_polyline(PackedVector2Array(Array(judge) + [judge[0]]), accent, 6.0, true)
			draw_colored_polygon(PackedVector2Array([judge[0], judge[1], judge[3]]), Color(0.96, 0.48, 0.16, 0.26))
			draw_colored_polygon(PackedVector2Array([judge[0], judge[3], judge[5]]), Color(1.0, 0.78, 0.34, 0.18))
			draw_line(judge[0], judge[3], Color(1.0, 0.82, 0.48, 0.58), 2.0, true)
			for seal in 4 + phase:
				var seal_angle := -_visual_time * 0.42 + float(seal) * TAU / float(4 + phase)
				var seal_center := Vector2.from_angle(seal_angle) * (78.0 + sin(_visual_time * 2.8 + seal) * 5.0)
				var seal_shape := PackedVector2Array([seal_center + Vector2(0,-7), seal_center + Vector2(7,0), seal_center + Vector2(0,7), seal_center + Vector2(-7,0)])
				draw_colored_polygon(seal_shape, Color(0.18, 0.02, 0.03, 0.88))
				draw_polyline(PackedVector2Array(Array(seal_shape) + [seal_shape[0]]), Color(1.0, 0.62, 0.20, 0.72), 1.8, true)
	if phase_controller.state == FoldlightBossPhaseController.State.STAGGERED:
		draw_arc(Vector2.ZERO, 116.0 if is_reef_crown else 70.0, 0.0, TAU, 40, Color(0.52, 1.0, 0.88, 0.96), 8.0, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var health_ratio := clampf(health / definition.base_health, 0.0, 1.0)
	var bar_width := 212.0 if is_reef_crown else 144.0
	var bar_y := -124.0 if is_reef_crown else -82.0
	draw_rect(Rect2(Vector2(-bar_width * 0.5, bar_y), Vector2(bar_width, 10.0)), Color(0.03, 0.04, 0.08, 0.94), true)
	draw_rect(Rect2(Vector2(-bar_width * 0.5, bar_y), Vector2(bar_width * health_ratio, 10.0)), accent, true)
