class_name FoldlightPrismBulwark
extends CharacterBody2D

signal prism_broken(position: Vector2, duration: float)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

@export_range(1.0, 6.0, 0.1) var broken_duration: float = 3.2
@export_range(0.05, 0.8, 0.05) var frontal_damage_multiplier: float = 0.18

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"prism_bulwark"
var health: float = 12.0
var support_attack_multiplier: float = 1.0
var prism_active: bool = true
var facing_direction: Vector2 = Vector2.DOWN
var _broken_remaining: float = 0.0
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
	health = definition.base_health if definition != null else 12.0
	queue_redraw()


func advance_simulation(delta: float, target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	_visual_time += safe_delta
	var offset := target_position - global_position
	if not offset.is_zero_approx():
		facing_direction = offset.normalized()
	var desired := Vector2.ZERO
	if offset.length() > 390.0:
		desired = facing_direction
	elif offset.length() < 270.0:
		desired = -facing_direction
	else:
		desired = facing_direction.orthogonal() * (1.0 if String(actor_id).hash() % 2 == 0 else -1.0)
	var speed := definition.move_speed if definition != null else 96.0
	velocity = velocity.move_toward(desired * speed, speed * 5.0 * safe_delta)
	move_and_slide()
	if not prism_active:
		_broken_remaining = maxf(0.0, _broken_remaining - safe_delta)
		if _broken_remaining <= 0.0:
			prism_active = true
	queue_redraw()


func take_projectile_damage(amount: float, incoming_velocity: Vector2, style: StringName) -> bool:
	var applied := amount
	if style == &"return_light" and prism_active:
		prism_active = false
		_broken_remaining = broken_duration
		applied *= 1.8
		prism_broken.emit(global_position, broken_duration)
	elif prism_active and not incoming_velocity.is_zero_approx():
		var toward_source := -incoming_velocity.normalized()
		if toward_source.dot(facing_direction) > 0.05:
			applied *= frontal_damage_multiplier
	elif not prism_active:
		applied *= 1.35
	return _apply_damage(applied)


func take_damage(amount: float) -> bool:
	return _apply_damage(amount * (0.65 if prism_active else 1.2))


func _apply_damage(amount: float) -> bool:
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


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, "health": health, "maximum_health": definition.base_health if definition != null else 12.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func _draw() -> void:
	var accent := (Color(0.42, 0.90, 1.0) if prism_active else Color(1.0, 0.70, 0.28)).lerp(Color.WHITE, _hit_flash * 0.78)
	for ring in range(3, 0, -1):
		draw_circle(Vector2.ZERO, 24.0 + float(ring) * 8.0, Color(accent.r, accent.g, accent.b, 0.025 * float(4 - ring)))
	var stride := sin(_visual_time * 4.1)
	draw_set_transform(Vector2(0, stride * 2.0), stride * 0.035, Vector2(1.0 + _hit_punch * 0.10 + stride * 0.016, 1.0 - _hit_punch * 0.06 - stride * 0.022))
	var body := PackedVector2Array([Vector2(0, -25), Vector2(22, -11), Vector2(22, 14), Vector2(0, 27), Vector2(-22, 14), Vector2(-22, -11)])
	draw_colored_polygon(body, Color(0.07, 0.12, 0.20, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array(Array(body) + [body[0]]), accent, 3.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var angle := facing_direction.angle()
	if prism_active:
		draw_arc(Vector2.ZERO, 38.0, angle - 1.08, angle + 1.08, 28, Color(0.48, 0.96, 1.0, 0.92), 6.0, true)
		draw_arc(Vector2.ZERO, 45.0, angle - 1.08, angle + 1.08, 28, Color(0.90, 0.76, 1.0, 0.38), 2.0, true)
	else:
		var ratio := _broken_remaining / maxf(0.01, broken_duration)
		draw_arc(Vector2.ZERO, 40.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 28, Color(1.0, 0.69, 0.26, 0.8), 3.0, true)
	var health_ratio := clampf(health / (definition.base_health if definition != null else 12.0), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-24, -36), Vector2(48, 4)), Color(0.02, 0.04, 0.08, 0.9), true)
	draw_rect(Rect2(Vector2(-24, -36), Vector2(48 * health_ratio, 4)), accent, true)
