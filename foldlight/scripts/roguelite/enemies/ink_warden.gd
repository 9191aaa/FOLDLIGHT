class_name FoldlightInkWarden
extends CharacterBody2D

signal zone_requested(snapshot: Dictionary)
signal cast_state_changed(casting: bool)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

@export_range(0.4, 2.0, 0.05) var telegraph_duration: float = 0.85
@export_range(100.0, 260.0, 5.0) var zone_radius: float = 190.0
@export_range(1.0, 5.0, 0.1) var zone_duration: float = 4.5
@export_range(2.0, 8.0, 0.1) var cast_cooldown: float = 5.6
@export_range(0.3, 0.9, 0.05) var movement_multiplier: float = 0.62

var is_casting: bool = false
var target_position: Vector2 = Vector2.ZERO
var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"ink_warden"
var health: float = 13.0
var support_attack_multiplier: float = 1.0
var _cast_remaining: float = 0.0
var _cooldown_remaining: float = 0.0
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0
var _visual_time: float = 0.0


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	queue_redraw()


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 13.0
	queue_redraw()


func begin_cast(new_target_position: Vector2) -> bool:
	if is_casting or _cooldown_remaining > 0.0:
		return false
	target_position = new_target_position
	is_casting = true
	_cast_remaining = telegraph_duration
	cast_state_changed.emit(true)
	queue_redraw()
	return true


func force_ready() -> void:
	_cooldown_remaining = 0.0


func advance_simulation(delta: float, suggested_target: Vector2, hostile_time_scale: float = 1.0) -> void:
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0) / support_attack_multiplier
	_visual_time += safe_delta
	if is_casting:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * safe_delta)
		_cast_remaining -= safe_delta
		if _cast_remaining <= 0.0:
			is_casting = false
			_cooldown_remaining = cast_cooldown
			zone_requested.emit({
				"position": target_position,
				"radius": zone_radius,
				"duration": zone_duration,
				"movement_multiplier": movement_multiplier,
			})
			cast_state_changed.emit(false)
	else:
		var away := global_position - suggested_target
		var movement := away.normalized() if away.length() < 420.0 else global_position.direction_to(suggested_target).orthogonal()
		velocity = velocity.move_toward(movement * (definition.move_speed if definition != null else 88.0), 440.0 * safe_delta)
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - safe_delta)
		if _cooldown_remaining <= 0.0:
			begin_cast(suggested_target)
	move_and_slide()
	queue_redraw()


func take_damage(amount: float) -> bool:
	if amount <= 0.0 or health <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	_hit_flash = 1.0
	_hit_punch = maxf(_hit_punch, 0.88)
	damaged.emit(amount, health)
	if health <= 0.0:
		defeated.emit(self)
		return true
	queue_redraw()
	return false


func set_support_buff(attack_multiplier: float) -> void:
	support_attack_multiplier = clampf(attack_multiplier, 0.55, 1.0)
	queue_redraw()


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, "health": health, "maximum_health": definition.base_health if definition != null else 13.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func _draw() -> void:
	for ring in range(4, 0, -1):
		draw_circle(Vector2.ZERO, 22.0 + float(ring) * 7.0, Color(0.72, 0.28, 0.88, 0.025 * float(5 - ring)))
	var hover := sin(_visual_time * (4.8 if is_casting else 2.9))
	draw_set_transform(Vector2(0, hover * 2.8), hover * 0.04, Vector2(1.0 + _hit_punch * 0.10 + hover * 0.02, 1.0 - _hit_punch * 0.06 - hover * 0.025))
	var body := PackedVector2Array([Vector2(0, -27), Vector2(23, -8), Vector2(16, 24), Vector2(-16, 24), Vector2(-23, -8)])
	draw_colored_polygon(body, Color(0.12, 0.07, 0.20, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[0]]), Color(0.76, 0.35, 0.91).lerp(Color.WHITE, _hit_flash * 0.78), 4.0, true)
	draw_circle(Vector2.ZERO, 7.0, Color(0.97, 0.66, 1.0))
	for mote in 3:
		var mote_angle := _visual_time * 0.9 + float(mote) * TAU / 3.0
		draw_circle(Vector2.from_angle(mote_angle) * 34.0, 3.0, Color(0.88, 0.42, 1.0, 0.54))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if is_casting:
		var local_target := to_local(target_position)
		draw_dashed_line(Vector2.ZERO, local_target, Color(0.92, 0.46, 1.0, 0.64), 3.0, 14.0, true)
		draw_circle(local_target, zone_radius, Color(0.56, 0.10, 0.72, 0.12))
		draw_arc(local_target, zone_radius, 0.0, TAU, 48, Color(0.94, 0.48, 1.0, 0.84), 4.0, true)
