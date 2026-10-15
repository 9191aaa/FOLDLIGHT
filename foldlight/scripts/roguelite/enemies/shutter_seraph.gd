class_name FoldlightShutterSeraph
extends CharacterBody2D

signal volley_requested(snapshot: Dictionary)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

enum Phase { CLOSED, CHARGING, FIRING, CLOSING }

const CLOSED_DURATION: float = 2.4
const CHARGE_DURATION: float = 0.8
const FIRE_DURATION: float = 2.4
const CLOSE_DURATION: float = 0.4
const VOLLEYS_PER_GROUP: int = 5
const MAX_GROUP_TURN: float = 0.24

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"shutter_seraph"
var health: float = 14.0
var phase: Phase = Phase.CLOSED
var locked_direction: Vector2 = Vector2.DOWN
var _phase_remaining: float = CLOSED_DURATION
var _shot_remaining: float = 0.0
var _volleys_fired: int = 0
var _visual_time: float = 0.0
var _shield_flash: float = 0.0
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0
var _hit_direction: Vector2 = Vector2.UP
var _motion_scale: float = 1.0


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	_refresh_motion_setting()
	queue_redraw()


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 14.0
	phase = Phase.CLOSED
	_phase_remaining = CLOSED_DURATION
	_shot_remaining = 0.0
	_volleys_fired = 0
	_visual_time = 0.0
	_shield_flash = 0.0
	_hit_flash = 0.0
	_hit_punch = 0.0
	velocity = Vector2.ZERO
	queue_redraw()


func advance_simulation(delta: float, target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if health <= 0.0:
		return
	# A stalled frame cannot skip the warning or discharge an accumulated burst.
	# All clocks, movement and visuals are advanced solely by the combat runtime.
	var step := clampf(maxf(0.0, delta) * clampf(hostile_time_scale, 0.0, 2.0), 0.0, 0.1)
	if step <= 0.0:
		return
	_visual_time += step * _motion_scale
	_shield_flash = maxf(0.0, _shield_flash - step * 6.0)
	_hit_flash = maxf(0.0, _hit_flash - step * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - step * 8.5)
	_phase_remaining -= step
	var offset := target_position - global_position
	match phase:
		Phase.CLOSED:
			var approach := offset.normalized() if not offset.is_zero_approx() else Vector2.DOWN
			var orbit := approach.orthogonal() * (1.0 if hash(actor_id) % 2 == 0 else -1.0)
			var movement := orbit if offset.length() < 580.0 else approach
			if offset.length() < 300.0:
				movement = (orbit - approach).normalized()
			var speed := definition.move_speed if definition != null else 92.0
			velocity = velocity.move_toward(movement * speed, speed * 4.5 * step)
			if _phase_remaining <= 0.00001:
				phase = Phase.CHARGING
				_phase_remaining = CHARGE_DURATION
				locked_direction = approach
				velocity = Vector2.ZERO
		Phase.CHARGING:
			velocity = Vector2.ZERO
			if _phase_remaining <= 0.00001:
				phase = Phase.FIRING
				_phase_remaining = FIRE_DURATION
				_volleys_fired = 0
				_shot_remaining = _shot_interval()
				_fire_volley(target_position)
		Phase.FIRING:
			velocity = Vector2.ZERO
			_shot_remaining -= step
			if _phase_remaining <= 0.00001:
				phase = Phase.CLOSING
				_phase_remaining = CLOSE_DURATION
			elif _shot_remaining <= 0.00001:
				_shot_remaining += _shot_interval()
				_fire_volley(target_position)
		Phase.CLOSING:
			velocity = Vector2.ZERO
			if _phase_remaining <= 0.00001:
				phase = Phase.CLOSED
				_phase_remaining = CLOSED_DURATION
	move_and_slide()
	queue_redraw()


func _shot_interval() -> float:
	return clampf(definition.attack_interval if definition != null else 0.12, 0.10, 0.14)


func _fire_volley(target_position: Vector2) -> void:
	if _volleys_fired > 0 and _volleys_fired % VOLLEYS_PER_GROUP == 0:
		var offset := target_position - global_position
		if not offset.is_zero_approx():
			locked_direction = locked_direction.rotated(clampf(locked_direction.angle_to(offset), -MAX_GROUP_TURN, MAX_GROUP_TURN))
	_volleys_fired += 1
	volley_requested.emit({
		"origin": global_position + locked_direction * 34.0,
		"direction": locked_direction,
		"projectile_count": 5,
		"spread_radians": 0.96,
		"reflectable": true,
		"speed": 245.0,
		"radius": 5.5,
		"lifetime": 3.6,
		"style": &"hostile_petal",
	})


func is_damageable() -> bool:
	return health > 0.0 and phase == Phase.FIRING


func set_simulation_active(value: bool) -> void:
	if value:
		_refresh_motion_setting()


func _refresh_motion_setting() -> void:
	var profile := get_node_or_null("/root/ProfileManager")
	_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0


func take_damage(amount: float) -> bool:
	if amount <= 0.0 or health <= 0.0:
		return false
	if not is_damageable():
		_shield_flash = 1.0
		queue_redraw()
		return false
	var applied := minf(health, amount)
	health -= applied
	_hit_flash = 1.0
	_hit_punch = 0.9
	damaged.emit(applied, health)
	queue_redraw()
	if health <= 0.0:
		defeated.emit(self)
		return true
	return false


func take_projectile_damage(amount: float, incoming_velocity: Vector2, _style: StringName) -> bool:
	if not incoming_velocity.is_zero_approx():
		_hit_direction = incoming_velocity.normalized()
	return take_damage(amount)


func get_contact_radius() -> float:
	return 30.0


func get_phase_snapshot() -> Dictionary:
	return {"phase": phase, "remaining": _phase_remaining, "damageable": is_damageable(), "volleys": _volleys_fired, "direction": locked_direction, "visual_time": _visual_time, "shield_flash": _shield_flash}


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.ELITE, "health": health, "maximum_health": _maximum_health()}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch, "direction": _hit_direction, "shield_flash": _shield_flash}


func _maximum_health() -> float:
	return float(get_meta("directed_maximum_health", definition.base_health if definition != null else 14.0))


func _draw() -> void:
	var firing := phase == Phase.FIRING
	var openness := 1.0 if firing else (clampf(_phase_remaining / CLOSE_DURATION, 0.0, 1.0) if phase == Phase.CLOSING and _motion_scale > 0.0 else 0.0)
	var shield := Color("90b4d2").lerp(Color.WHITE, _shield_flash * 0.8)
	var core := Color("f7ce87").lerp(Color.WHITE, _hit_flash * 0.9)
	var edge := core if firing else shield
	var pulse := sin(_visual_time * (18.0 if phase == Phase.CHARGING else 4.0)) * _motion_scale
	var punch := _hit_punch * _motion_scale
	draw_set_transform(Vector2(0, sin(_visual_time * 2.8) * 2.0 * _motion_scale), 0.0, Vector2(1.0 + punch * 0.08, 1.0 - punch * 0.05))
	for side in [-1.0, 1.0]:
		for feather in 3:
			var reach := 27.0 + openness * (47.0 - feather * 9.0)
			var y := -22.0 + feather * 16.0
			var wing := PackedVector2Array([Vector2(side * 8, y - 9), Vector2(side * reach, y - 22.0 - openness * 9.0), Vector2(side * (reach - 5.0), y + 6), Vector2(side * 13, y + 20)])
			draw_colored_polygon(wing, Color("192d48").lerp(Color("53627a"), openness * 0.6 + _shield_flash * 0.25))
			draw_polyline(PackedVector2Array(Array(wing) + [wing[0]]), Color(edge, 0.95 - feather * 0.1), 2.0, true)
			draw_line(Vector2(side * 12, y), Vector2(side * (reach - 6), y - 8), Color(edge, 0.35), 1.0, true)
	var body := PackedVector2Array([Vector2(0, -33), Vector2(19, -8), Vector2(15, 25), Vector2(0, 39), Vector2(-15, 25), Vector2(-19, -8)])
	draw_colored_polygon(body, Color("182335").lerp(Color("6f493c"), openness))
	draw_polyline(PackedVector2Array(Array(body) + [body[0]]), edge, 2.5, true)
	if firing:
		draw_circle(Vector2.ZERO, 20.0 + pulse * 1.8, Color(core, 0.14))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -18), Vector2(10, 0), Vector2(0, 18), Vector2(-10, 0)]), core)
		draw_arc(Vector2.ZERO, 26.0, -2.5, -0.65, 14, Color(core, 0.85), 2.0, true)
		draw_arc(Vector2.ZERO, 26.0, 0.65, 2.5, 14, Color(core, 0.85), 2.0, true)
	else:
		# The closed seam and complete shield ring remain legible while closing.
		draw_line(Vector2(0, -24), Vector2(0, 26), shield, 3.5, true)
		draw_arc(Vector2.ZERO, 37.0 + _shield_flash * 4.0 * _motion_scale, 0, TAU, 32, Color(shield, 0.45 + _shield_flash * 0.5), 2.5, true)
		for y in [-13.0, 0.0, 13.0]:
			draw_line(Vector2(-6, y - 4), Vector2(6, y + 4), shield, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if phase == Phase.CHARGING:
		var progress := 1.0 - clampf(_phase_remaining / CHARGE_DURATION, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 50.0 - progress * 7.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, Color("f58b73"), 3.5, true)
		for angle in [-0.48, 0.0, 0.48]:
			var ray := locked_direction.rotated(angle)
			draw_line(ray * 43.0, ray * (130.0 + progress * 80.0), Color(0.96, 0.63, 0.47, 0.28 + progress * 0.24), 2.0, true)
	var health_ratio := clampf(health / maxf(1.0, _maximum_health()), 0.0, 1.0)
	draw_rect(Rect2(-28, -62, 56, 4), Color("101b2b"))
	draw_rect(Rect2(-28, -62, 56 * health_ratio, 4), edge)
