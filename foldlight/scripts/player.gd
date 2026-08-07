class_name FoldlightPlayer
extends CharacterBody2D

signal fold_started
signal fold_released(captured_count: int, charge_ratio: float)
signal focus_empty(captured_count: int, charge_ratio: float)
signal statuses_cleansed(status_ids: Array[StringName])
signal dash_started(direction: Vector2, duration: float)
signal dash_ended
signal active_item_used(item_id: StringName)

const ARENA_MIN := Vector2(120.0, 150.0)
const ARENA_MAX := Vector2(1800.0, 970.0)
const MOVE_SPEED: float = 430.0
const FOLD_SPEED: float = 235.0
const ACCELERATION: float = 2100.0
const FRICTION: float = 1750.0
const MAX_HEALTH: int = 5
const CAPTURE_CAPACITY: int = 16
const FOCUS_DRAIN: float = 0.185
const FOCUS_REGEN: float = 0.145
const FOLD_RADIUS_MIN: float = 112.0
const FOLD_RADIUS_MAX: float = 315.0
const FULL_CHARGE_TIME: float = 1.55
const ROGUELITE_HIT_RADIUS: float = 13.0
const CLASSIC_HIT_RADIUS: float = 18.0
const ROGUELITE_VISUAL_SCALE: float = 0.82
const CLASSIC_VISUAL_SCALE: float = 1.24
const HIT_REACTION_DURATION: float = 0.24
const HIT_REACTION_DISTANCE: float = 18.0

var health: int = MAX_HEALTH
var focus: float = 1.0
var folding: bool = false
var captured: int = 0
var fold_time: float = 0.0
var play_enabled: bool = false
var invulnerability: float = 0.0
var visual_flash: float = 0.0
var last_input_device: StringName = &"keyboard"
var max_health: int = MAX_HEALTH
var capture_capacity: int = CAPTURE_CAPACITY
var move_speed_multiplier: float = 1.0
var fold_speed_multiplier: float = 1.0
var fold_radius_multiplier: float = 1.0
var temporary_fold_radius_multiplier: float = 1.0
var focus_drain_multiplier: float = 1.0
var focus_regen_multiplier: float = 1.0
var play_bounds := Rect2(ARENA_MIN, ARENA_MAX - ARENA_MIN)
var roguelite_combat: bool = false
var body_size_multiplier: float = 1.0
var hit_radius: float = CLASSIC_HIT_RADIUS
var rogue_build_stats: Dictionary = {}
var damage_grace_add: float = 0.0
var fold_temporarily_locked: bool = false
var debug_invincible: bool = false

var _visual_time: float = 0.0
var _trail_clock: float = 0.0
var _trail: Array[Dictionary] = []
var _facing_angle: float = 0.0
var _last_direction := Vector2.UP
var _fold_buffer_timer: float = 0.0
var _hit_stop_timer: float = 0.0
var _dash_buffer_timer: float = 0.0
var _body_visual_scale: float = CLASSIC_VISUAL_SCALE
var _hit_reaction_remaining: float = 0.0
var _hit_reaction_direction: Vector2 = Vector2.DOWN
var _hit_visual_offset: Vector2 = Vector2.ZERO
var _hit_visual_scale: Vector2 = Vector2.ONE

@onready var status_effects: FoldlightStatusEffects = $StatusEffects
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var dash_component: FoldlightDashComponent = $DashComponent
@onready var fold_component: FoldlightFoldComponent = $FoldComponent
@onready var weapon_mount: FoldlightWeaponMount = $WeaponMount
@onready var active_item_slot: FoldlightActiveItemSlot = $ActiveItemSlot
@onready var feedback_budget: FoldlightFeedbackBudget = $FeedbackBudget


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	dash_component.dash_started.connect(_on_dash_component_started)
	dash_component.dash_ended.connect(_on_dash_component_ended)
	active_item_slot.item_used.connect(_on_active_item_slot_used)
	feedback_budget.hit_stop_requested.connect(add_hit_stop)
	_set_physical_radius(CLASSIC_HIT_RADIUS)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		last_input_device = &"gamepad"
	elif event is InputEventKey and event.pressed:
		last_input_device = &"keyboard"

	if not play_enabled:
		return
	if roguelite_combat and event.is_action_pressed(&"dash") and not event.is_echo():
		_dash_buffer_timer = 0.14
		get_viewport().set_input_as_handled()
	elif roguelite_combat and event.is_action_pressed(&"active_item") and not event.is_echo():
		request_active_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"fold") and not event.is_echo():
		if not folding and focus > 0.035 and fold_component.can_begin():
			try_begin_fold()
		elif not folding:
			_fold_buffer_timer = 0.18
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"fold"):
		_fold_buffer_timer = 0.0
		if folding:
			_release_fold(false)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	simulate_combat_cooldowns(delta)
	if _hit_stop_timer > 0.0:
		_hit_stop_timer = maxf(0.0, _hit_stop_timer - delta)
		return
	if invulnerability > 0.0:
		invulnerability = maxf(0.0, invulnerability - delta)
	if visual_flash > 0.0:
		visual_flash = maxf(0.0, visual_flash - delta * 3.8)

	if not play_enabled:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		_dash_buffer_timer = 0.0
		return
	status_effects.tick(delta)
	if _fold_buffer_timer > 0.0:
		_fold_buffer_timer = maxf(0.0, _fold_buffer_timer - delta)
		if not folding and focus > 0.055 and fold_component.can_begin() and Input.is_action_pressed(&"fold"):
			_fold_buffer_timer = 0.0
			try_begin_fold()

	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var ui_direction := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if ui_direction.length_squared() > direction.length_squared():
		direction = ui_direction
	if direction.length_squared() > 0.02:
		_last_direction = direction.normalized()
		var target_angle := _last_direction.angle() + PI * 0.5
		_facing_angle = lerp_angle(_facing_angle, target_angle, minf(1.0, delta * 7.5))
	if _dash_buffer_timer > 0.0:
		_dash_buffer_timer = maxf(0.0, _dash_buffer_timer - delta)
		if request_dash(direction):
			_dash_buffer_timer = 0.0

	var status_move_multiplier := status_effects.get_move_multiplier()
	if dash_component.is_dashing():
		velocity = dash_component.get_velocity()
	else:
		var speed := FOLD_SPEED * fold_speed_multiplier * status_move_multiplier if folding else MOVE_SPEED * move_speed_multiplier * status_move_multiplier
		if direction != Vector2.ZERO:
			velocity = velocity.move_toward(direction * speed, ACCELERATION * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	move_and_slide()
	global_position = global_position.clamp(play_bounds.position, play_bounds.end)

	if folding:
		fold_time += delta
		focus = maxf(0.0, focus - FOCUS_DRAIN * focus_drain_multiplier * delta)
		if focus <= 0.0:
			_release_fold(true)
	else:
		focus = minf(1.0, focus + FOCUS_REGEN * focus_regen_multiplier * status_effects.get_focus_regen_multiplier() * delta)

	_trail_clock -= delta
	if _trail_clock <= 0.0 and velocity.length() > 40.0:
		_trail_clock = 0.038
		_trail.push_front({"position": global_position, "life": 1.0, "angle": _facing_angle})
		if _trail.size() > 20:
			_trail.pop_back()


func _process(delta: float) -> void:
	_visual_time += delta
	_update_hit_reaction(delta)
	for point in _trail:
		point.life = float(point.life) - delta * 2.45
	while not _trail.is_empty() and float(_trail.back().life) <= 0.0:
		_trail.pop_back()
	queue_redraw()


func reset_player() -> void:
	global_position = Vector2(960.0, 650.0)
	velocity = Vector2.ZERO
	max_health = MAX_HEALTH
	capture_capacity = CAPTURE_CAPACITY
	move_speed_multiplier = 1.0
	fold_speed_multiplier = 1.0
	fold_radius_multiplier = 1.0
	temporary_fold_radius_multiplier = 1.0
	focus_drain_multiplier = 1.0
	focus_regen_multiplier = 1.0
	play_bounds = Rect2(ARENA_MIN, ARENA_MAX - ARENA_MIN)
	health = max_health
	focus = 1.0
	folding = false
	captured = 0
	fold_time = 0.0
	invulnerability = 0.0
	visual_flash = 0.0
	_fold_buffer_timer = 0.0
	_hit_stop_timer = 0.0
	_dash_buffer_timer = 0.0
	_hit_reaction_remaining = 0.0
	_hit_visual_offset = Vector2.ZERO
	_hit_visual_scale = Vector2.ONE
	status_effects.clear_all()
	_trail.clear()
	_facing_angle = 0.0
	configure_roguelite_combat(roguelite_combat)
	play_enabled = false


func set_play_enabled(enabled: bool) -> void:
	play_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_fold_buffer_timer = 0.0


## Freeze controls for a modal explanation without spending or releasing anything
## already captured. This prevents a held Fold input from getting stuck when the
## release event happens while the combat simulation is suspended.
func suspend_for_overlay() -> void:
	play_enabled = false
	velocity = Vector2.ZERO
	folding = false
	fold_time = 0.0
	_fold_buffer_timer = 0.0


func resume_from_overlay(safety_duration: float = 0.65) -> void:
	play_enabled = true
	grant_invulnerability(safety_duration)


func cancel_fold() -> void:
	folding = false
	fold_time = 0.0
	captured = 0
	_fold_buffer_timer = 0.0


func configure_roguelite_combat(enabled: bool) -> void:
	roguelite_combat = enabled
	scale = Vector2.ONE
	fold_component.configure(enabled)
	dash_component.configure(enabled)
	weapon_mount.enabled = enabled
	active_item_slot.enabled = enabled
	feedback_budget.reset()
	capture_capacity = fold_component.get_capacity()
	body_size_multiplier = 1.0
	_body_visual_scale = ROGUELITE_VISUAL_SCALE if enabled else CLASSIC_VISUAL_SCALE
	_set_physical_radius(ROGUELITE_HIT_RADIUS if enabled else CLASSIC_HIT_RADIUS)
	weapon_mount.unequip_all()
	active_item_slot.unequip()
	if enabled:
		weapon_mount.equip(FoldlightRogueContentCatalog.weapon_by_id(&"crease_lantern"))
		active_item_slot.equip(FoldlightRogueContentCatalog.active_item_by_id(&"paper_burst"))
		collision_layer = 1
		collision_mask = 1 << 2
	else:
		collision_layer = 0
		collision_mask = 0
	apply_roguelite_build({})
	queue_redraw()


func apply_roguelite_build(upgrade_levels: Dictionary) -> Dictionary:
	var stats := FoldlightBuildResolver.aggregate_stats(upgrade_levels) if roguelite_combat else {}
	return apply_roguelite_stats(stats)


## Applies an already-resolved stat snapshot.  Extra modes use this adapter to
## add progression while preserving the exact 2.0 player/components runtime.
func apply_roguelite_stats(stats: Dictionary) -> Dictionary:
	rogue_build_stats = stats.duplicate(true)
	fold_component.configure_build(stats)
	dash_component.configure_build(stats)
	weapon_mount.configure_build(stats)
	capture_capacity = fold_component.get_capacity()
	move_speed_multiplier = float(stats.get("move_speed_multiplier", 1.0)) if roguelite_combat else 1.0
	fold_speed_multiplier = 1.0 + float(stats.get("fold_move_speed_add", 0.0)) if roguelite_combat else 1.0
	fold_radius_multiplier = float(stats.get("fold_radius_multiplier", 1.0)) if roguelite_combat else 1.0
	max_health = MAX_HEALTH + int(round(float(stats.get("max_health_add", 0.0)))) if roguelite_combat else MAX_HEALTH
	health = mini(health, max_health)
	damage_grace_add = float(stats.get("damage_grace_add", 0.0)) if roguelite_combat else 0.0
	status_effects.slow_severity_multiplier = float(stats.get("ink_slow_multiplier", 1.0)) if roguelite_combat else 1.0
	set_body_size_multiplier(float(stats.get("body_size_multiplier", 1.0)) if roguelite_combat else 1.0)
	return stats


func try_begin_fold() -> bool:
	if not play_enabled or fold_temporarily_locked or folding or focus <= 0.035 or not fold_component.can_begin() or dash_component.is_dashing():
		return false
	return _begin_fold()


func release_fold_action() -> bool:
	if not folding:
		return false
	_release_fold(false)
	return true


func request_dash(requested_direction: Vector2 = Vector2.ZERO) -> bool:
	if not roguelite_combat or not play_enabled:
		return false
	if folding and captured > 0:
		return false
	if folding:
		cancel_fold()
	var resolved_direction := requested_direction.normalized() if not requested_direction.is_zero_approx() else _last_direction
	return dash_component.request(resolved_direction)


func request_active_item() -> bool:
	if not roguelite_combat or not play_enabled:
		return false
	return active_item_slot.request_use()


func tick_automatic_weapons(delta: float, has_valid_target: bool) -> void:
	weapon_mount.tick(delta, has_valid_target)


func simulate_combat_cooldowns(delta: float) -> void:
	dash_component.tick(delta)
	fold_component.tick(delta)
	active_item_slot.tick(delta)
	feedback_budget.tick(delta)


func set_body_size_multiplier(multiplier: float) -> void:
	body_size_multiplier = clampf(multiplier, 0.68, 1.45)
	var base_radius := ROGUELITE_HIT_RADIUS if roguelite_combat else CLASSIC_HIT_RADIUS
	var base_visual := ROGUELITE_VISUAL_SCALE if roguelite_combat else CLASSIC_VISUAL_SCALE
	_body_visual_scale = base_visual * body_size_multiplier
	_set_physical_radius(base_radius * body_size_multiplier)
	queue_redraw()


func get_fold_cooldown_remaining() -> float:
	return fold_component.cooldown_remaining


func get_dash_cooldown_ratio() -> float:
	return dash_component.get_cooldown_ratio()


func get_active_item_cooldown_ratio() -> float:
	return active_item_slot.get_cooldown_ratio()


func capture_one() -> bool:
	if not folding or captured >= get_capture_capacity():
		return false
	captured += 1
	visual_flash = minf(1.0, visual_flash + 0.16)
	return true


func can_capture() -> bool:
	return folding and captured < get_capture_capacity()


func get_capture_capacity() -> int:
	return capture_capacity


func get_fold_radius() -> float:
	if not folding:
		return 0.0
	var ratio := clampf(fold_time / FULL_CHARGE_TIME, 0.0, 1.0)
	return lerpf(FOLD_RADIUS_MIN, FOLD_RADIUS_MAX, ease(ratio, 0.55)) * fold_radius_multiplier * temporary_fold_radius_multiplier * status_effects.get_fold_radius_multiplier()


func get_charge_ratio() -> float:
	return clampf(fold_time / FULL_CHARGE_TIME, 0.0, 1.0)


func take_hit(impact_direction: Vector2 = Vector2.ZERO) -> bool:
	if debug_invincible or invulnerability > 0.0 or not play_enabled:
		return false
	health = maxi(0, health - 1)
	invulnerability = 1.35 + damage_grace_add
	visual_flash = 1.0
	_begin_hit_reaction(impact_direction)
	if folding:
		_release_fold(false)
	return true


func get_hit_reaction_snapshot() -> Dictionary:
	return {
		"active": _hit_reaction_remaining > 0.0,
		"remaining": _hit_reaction_remaining,
		"direction": _hit_reaction_direction,
		"offset": _hit_visual_offset,
		"visual_scale": _hit_visual_scale,
		"duration": HIT_REACTION_DURATION,
		"maximum_distance": HIT_REACTION_DISTANCE,
	}


func _begin_hit_reaction(impact_direction: Vector2) -> void:
	var direction := impact_direction.normalized()
	if direction.is_zero_approx():
		direction = -_last_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	_hit_reaction_direction = direction
	_hit_reaction_remaining = HIT_REACTION_DURATION
	# Start on the impact pose immediately. Waiting for the next process frame
	# made short hits disappear inside the invulnerability blink.
	_hit_visual_offset = direction * HIT_REACTION_DISTANCE
	_hit_visual_scale = Vector2(1.07, 0.91)
	queue_redraw()


func _update_hit_reaction(delta: float) -> void:
	if _hit_reaction_remaining <= 0.0:
		_hit_visual_offset = Vector2.ZERO
		_hit_visual_scale = Vector2.ONE
		return
	_hit_reaction_remaining = maxf(0.0, _hit_reaction_remaining - maxf(0.0, delta))
	if _hit_reaction_remaining <= 0.0:
		_hit_visual_offset = Vector2.ZERO
		_hit_visual_scale = Vector2.ONE
		return
	var progress := 1.0 - _hit_reaction_remaining / HIT_REACTION_DURATION
	var envelope := pow(1.0 - progress, 2.0)
	# Two compact reversals read as a physical hit, while the quadratic envelope
	# prevents the old 2.0-style repeated shaking from lingering.
	var oscillation := cos(progress * PI * 3.0) * envelope
	_hit_visual_offset = _hit_reaction_direction * HIT_REACTION_DISTANCE * oscillation
	_hit_visual_scale = Vector2(1.0 + oscillation * 0.07, 1.0 - oscillation * 0.09)


func get_hit_radius() -> float:
	return hit_radius


func get_capture_ratio() -> float:
	return float(captured) / float(get_capture_capacity())


func apply_status(status_id: StringName, duration: float) -> bool:
	return status_effects.apply_status(status_id, duration)


func has_status(status_id: StringName) -> bool:
	return status_effects.has_status(status_id)


func get_status_snapshots() -> Array[Dictionary]:
	return status_effects.get_snapshots()


func clear_statuses() -> void:
	status_effects.clear_all()


func add_focus(amount: float) -> void:
	focus = clampf(focus + amount, 0.0, 1.0)


func grant_invulnerability(duration: float) -> void:
	invulnerability = maxf(invulnerability, duration)


func set_debug_invincible(enabled: bool) -> void:
	debug_invincible = enabled
	if enabled:
		invulnerability = 0.0
	queue_redraw()


func is_debug_invincible() -> bool:
	return debug_invincible


func add_hit_stop(duration: float) -> void:
	_hit_stop_timer = maxf(_hit_stop_timer, duration)


func _begin_fold() -> bool:
	if fold_temporarily_locked or folding or not fold_component.can_begin() or dash_component.is_dashing():
		return false
	folding = true
	fold_time = 0.0
	fold_started.emit()
	return true


func _release_fold(from_empty: bool) -> void:
	var released_count := captured
	var released_charge := get_charge_ratio()
	var cleansed := status_effects.cleanse_from_release(released_count, released_charge)
	folding = false
	fold_time = 0.0
	captured = 0
	fold_component.on_release()
	if from_empty:
		focus_empty.emit(released_count, released_charge)
	else:
		fold_released.emit(released_count, released_charge)
	if not cleansed.is_empty():
		statuses_cleansed.emit(cleansed)


func _draw() -> void:
	_draw_trail()
	if folding:
		_draw_fold_field()
	var blink := invulnerability > 0.0 and _hit_reaction_remaining <= 0.0 and int(invulnerability * 14.0) % 2 == 0
	if blink:
		return
	draw_set_transform(_hit_visual_offset, _facing_angle, _hit_visual_scale)
	_draw_moth(Vector2.ZERO, _body_visual_scale, visual_flash)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if roguelite_combat and fold_component.cooldown_remaining > 0.0:
		var ready_ratio := 1.0 - clampf(fold_component.cooldown_remaining / maxf(0.01, fold_component.roguelite_cooldown), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 38.0, -PI * 0.5, -PI * 0.5 + TAU * ready_ratio, 32, Color(0.35, 0.86, 0.88, 0.72), 2.0, true)


func _set_physical_radius(radius: float) -> void:
	hit_radius = clampf(radius, 6.0, 28.0)
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = hit_radius


func _on_dash_component_started(direction: Vector2, duration: float) -> void:
	grant_invulnerability(dash_component.get_effective_invulnerability())
	dash_started.emit(direction, duration)


func _on_dash_component_ended() -> void:
	dash_ended.emit()


func _on_active_item_slot_used(definition: FoldlightRogueActiveItemDefinition) -> void:
	active_item_used.emit(definition.content_id)


func _draw_trail() -> void:
	for index in range(_trail.size() - 1, -1, -1):
		var point: Dictionary = _trail[index]
		var life: float = clampf(float(point.life), 0.0, 1.0)
		var local_position: Vector2 = to_local(point.position)
		var size := lerpf(3.0, 18.0, life)
		draw_circle(local_position, size * 1.8, Color(0.12, 0.82, 0.88, life * 0.035))
		draw_circle(local_position, size * 0.52, Color(0.98, 0.72, 0.30, life * 0.28))
		if index < _trail.size() - 1:
			var next_position: Vector2 = to_local(_trail[index + 1].position)
			draw_line(local_position, next_position, Color(0.25, 0.72, 0.78, life * 0.22), maxf(1.0, life * 4.0), true)


func _draw_fold_field() -> void:
	var radius := get_fold_radius()
	var charge_ratio := get_charge_ratio()
	var pulse := sin(_visual_time * (4.0 + charge_ratio * 2.0)) * (3.0 + charge_ratio * 3.0)
	for ring in 5:
		var ring_radius := radius - float(ring) * 13.0 + pulse * (1.0 - float(ring) * 0.12)
		var alpha := 0.075 - float(ring) * 0.009
		draw_circle(Vector2.ZERO, ring_radius, Color(0.16, 0.83, 0.85, alpha))
		draw_arc(Vector2.ZERO, ring_radius, -PI * 0.88 + float(ring), PI * 0.13 + float(ring), 64, Color(0.95, 0.77, 0.42, 0.38 - float(ring) * 0.045), 2.2, true)
	for crease in 8:
		var angle := float(crease) * TAU / 8.0 + _visual_time * (0.08 + charge_ratio * 0.10)
		var inner := Vector2.from_angle(angle) * 46.0
		var outer := Vector2.from_angle(angle + sin(_visual_time + crease) * 0.035) * radius
		draw_line(inner, outer, Color(0.55, 0.93, 0.88, 0.11), 1.5, true)
	# A travelling fold front makes the growing collection radius readable even
	# while the player is moving through a dense projectile field.
	var front_progress := fposmod(_visual_time * (0.72 + charge_ratio * 0.25), 1.0)
	var front_radius := lerpf(52.0, radius, front_progress)
	var front_alpha := (1.0 - front_progress) * (0.16 + charge_ratio * 0.20)
	draw_arc(Vector2.ZERO, front_radius, 0.0, TAU, 72, Color(0.46, 0.94, 0.88, front_alpha), 3.0 + charge_ratio * 2.0, true)
	for marker in 12:
		var marker_angle := float(marker) * TAU / 12.0 - _visual_time * (0.24 + charge_ratio * 0.18)
		var marker_position := Vector2.from_angle(marker_angle) * (radius - 9.0 + sin(_visual_time * 3.2 + marker) * 4.0)
		var tangent := Vector2.from_angle(marker_angle + PI * 0.5)
		var radial := Vector2.from_angle(marker_angle)
		var marker_size := 3.0 + charge_ratio * 2.0
		draw_colored_polygon(PackedVector2Array([
			marker_position + radial * marker_size,
			marker_position + tangent * marker_size * 0.75,
			marker_position - radial * marker_size,
			marker_position - tangent * marker_size * 0.75,
		]), Color(0.66, 0.98, 0.90, 0.22 + charge_ratio * 0.30))
	draw_arc(Vector2.ZERO, radius + 2.0, -PI * 0.5, -PI * 0.5 + TAU * charge_ratio, 96, Color(0.45, 0.94, 0.88, 0.48), 4.0, true)
	if charge_ratio >= 0.995:
		draw_arc(Vector2.ZERO, radius + 12.0 + sin(_visual_time * 7.0) * 4.0, 0.0, TAU, 96, Color(1.0, 0.78, 0.38, 0.48), 4.0, true)
	var filled := float(captured) / float(get_capture_capacity())
	if filled > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * filled, 80, Color(1.0, 0.72, 0.31, 0.9), 5.0, true)


func _draw_moth(origin: Vector2, scale_factor: float, flash: float) -> void:
	var move_ratio := clampf(velocity.length() / maxf(1.0, MOVE_SPEED * move_speed_multiplier), 0.0, 1.0)
	var dash_ratio := 1.0 if dash_component.is_dashing() else 0.0
	var wing_speed := 7.2 + move_ratio * 5.6 + dash_ratio * 4.0
	var wing := 1.0 + sin(_visual_time * wing_speed) * (0.08 + move_ratio * 0.07)
	if folding:
		wing = lerpf(wing, 0.76 + sin(_visual_time * 4.2) * 0.035, 0.72)
	var shadow := Color(0.0, 0.0, 0.02, 0.52)
	var paper := Color(0.94, 0.91, 0.78).lerp(Color.WHITE, flash * 0.7)
	var cool := Color(0.38, 0.88, 0.86).lerp(Color.WHITE, flash)
	var gold := Color(1.0, 0.69, 0.28)
	var idle_bob := sin(_visual_time * 3.1) * (2.4 * (1.0 - move_ratio))
	var o := origin + Vector2(0.0, idle_bob + move_ratio * 1.5)
	if dash_ratio > 0.0:
		for streak in 4:
			var x := (float(streak) - 1.5) * 11.0
			var length := 42.0 + float(streak % 2) * 22.0
			draw_line(o + Vector2(x, 24.0), o + Vector2(x * 1.35, 24.0 + length), Color(0.38, 0.94, 0.90, 0.22 + float(streak) * 0.06), 3.0, true)

	# Soft luminous silhouette.
	for glow in range(4, 0, -1):
		draw_circle(o, float(glow) * 12.0 * scale_factor, Color(cool.r, cool.g, cool.b, 0.018 * float(5 - glow)))

	var left_wing := PackedVector2Array([
		o + Vector2(-5, -11) * scale_factor,
		o + Vector2(-47 * wing, -34 - move_ratio * 7.0) * scale_factor,
		o + Vector2(-34 * wing, 7 + move_ratio * 5.0) * scale_factor,
		o + Vector2(-8, 18) * scale_factor,
	])
	var right_wing := PackedVector2Array([
		o + Vector2(5, -11) * scale_factor,
		o + Vector2(47 * wing, -34 - move_ratio * 7.0) * scale_factor,
		o + Vector2(34 * wing, 7 + move_ratio * 5.0) * scale_factor,
		o + Vector2(8, 18) * scale_factor,
	])
	draw_colored_polygon(_offset_polygon(left_wing, Vector2(4, 7)), shadow)
	draw_colored_polygon(_offset_polygon(right_wing, Vector2(4, 7)), shadow)
	draw_colored_polygon(left_wing, paper)
	draw_colored_polygon(right_wing, paper.darkened(0.06))

	# Fold facets make the silhouette read as paper, not a flat icon.
	draw_colored_polygon(PackedVector2Array([left_wing[0], left_wing[1], left_wing[2]]), Color(0.36, 0.78, 0.78, 0.44))
	draw_colored_polygon(PackedVector2Array([right_wing[0], right_wing[1], right_wing[2]]), Color(0.97, 0.64, 0.28, 0.32))
	draw_line(left_wing[0], left_wing[2], Color(0.12, 0.31, 0.38, 0.52), 1.4, true)
	draw_line(right_wing[0], right_wing[2], Color(0.12, 0.31, 0.38, 0.42), 1.4, true)

	var body := PackedVector2Array([
		o + Vector2(0, -30) * scale_factor,
		o + Vector2(10, -5) * scale_factor,
		o + Vector2(0, 29) * scale_factor,
		o + Vector2(-10, -5) * scale_factor,
	])
	draw_colored_polygon(_offset_polygon(body, Vector2(3, 6)), shadow)
	draw_colored_polygon(body, cool)
	draw_colored_polygon(PackedVector2Array([body[0], body[1], body[2]]), Color(0.84, 1.0, 0.92, 0.78))
	draw_line(body[0], body[2], Color(0.07, 0.29, 0.35, 0.52), 1.5, true)
	draw_circle(o + Vector2(0, -12) * scale_factor, 3.2 * scale_factor, gold)
	draw_arc(o, 52.0 * scale_factor, -PI * 0.12, PI * 0.12, 12, Color(gold.r, gold.g, gold.b, 0.5), 2.0, true)
	if move_ratio > 0.08:
		var tail_sway := sin(_visual_time * 9.0) * 5.0 * move_ratio
		draw_colored_polygon(PackedVector2Array([o + Vector2(-7, 20) * scale_factor, o + Vector2(tail_sway - 4, 42 + move_ratio * 8) * scale_factor, o + Vector2(0, 29) * scale_factor]), Color(0.35, 0.86, 0.82, 0.34))
		draw_colored_polygon(PackedVector2Array([o + Vector2(7, 20) * scale_factor, o + Vector2(tail_sway + 4, 42 + move_ratio * 8) * scale_factor, o + Vector2(0, 29) * scale_factor]), Color(1.0, 0.66, 0.25, 0.24))


func _offset_polygon(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point + offset)
	return result
