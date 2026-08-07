class_name FoldlightShearScribe
extends CharacterBody2D

signal volley_requested(snapshot: Dictionary)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

enum Phase { STALK, TELEGRAPH, RECOVER }

@export_range(0.6, 2.0, 0.05) var telegraph_duration: float = 1.15
@export_range(2.0, 8.0, 0.1) var attack_cooldown: float = 4.8
@export_range(0.4, 2.0, 0.05) var recover_duration: float = 1.0

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"shear_scribe"
var health: float = 13.0
var support_attack_multiplier: float = 1.0
var phase: Phase = Phase.STALK
var locked_direction: Vector2 = Vector2.DOWN
var _phase_remaining: float = 2.2
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


func advance_simulation(delta: float, target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0) / support_attack_multiplier
	_visual_time += safe_delta
	var offset := target_position - global_position
	match phase:
		Phase.STALK:
			var movement := offset.normalized().orthogonal() if offset.length() < 620.0 else offset.normalized()
			var speed := definition.move_speed if definition != null else 105.0
			velocity = velocity.move_toward(movement * speed, speed * 4.5 * safe_delta)
			_phase_remaining -= safe_delta
			if _phase_remaining <= 0.0:
				phase = Phase.TELEGRAPH
				locked_direction = offset.normalized() if not offset.is_zero_approx() else Vector2.DOWN
				_phase_remaining = telegraph_duration
				velocity = Vector2.ZERO
		Phase.TELEGRAPH:
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * safe_delta)
			_phase_remaining -= safe_delta
			if _phase_remaining <= 0.0:
				volley_requested.emit({
					"origin": global_position,
					"direction": locked_direction,
					"projectile_count": 4,
					"radial": true,
					"reflectable": false,
					"speed": 430.0,
					"radius": 9.0,
					"lifetime": 4.5,
					"style": &"shear_blade",
				})
				phase = Phase.RECOVER
				_phase_remaining = recover_duration
		Phase.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 700.0 * safe_delta)
			_phase_remaining -= safe_delta
			if _phase_remaining <= 0.0:
				phase = Phase.STALK
				_phase_remaining = attack_cooldown
	move_and_slide()
	queue_redraw()


func take_damage(amount: float) -> bool:
	if amount <= 0.0 or health <= 0.0:
		return false
	var applied := amount * (1.35 if phase == Phase.RECOVER else 1.0)
	health = maxf(0.0, health - applied)
	_hit_flash = 1.0
	_hit_punch = maxf(_hit_punch, 0.88)
	damaged.emit(applied, health)
	if health <= 0.0:
		defeated.emit(self)
		return true
	queue_redraw()
	return false


func set_support_buff(attack_multiplier: float) -> void:
	support_attack_multiplier = clampf(attack_multiplier, 0.55, 1.0)


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, "health": health, "maximum_health": definition.base_health if definition != null else 13.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func _draw() -> void:
	var accent := (Color(1.0, 0.42, 0.28) if phase == Phase.TELEGRAPH else Color(0.72, 0.48, 0.94)).lerp(Color.WHITE, _hit_flash * 0.78)
	var quill_sway := sin(_visual_time * (7.0 if phase == Phase.TELEGRAPH else 3.6))
	draw_set_transform(Vector2(0, quill_sway * 2.2), quill_sway * 0.065, Vector2(1.0 + _hit_punch * 0.10 + quill_sway * 0.018, 1.0 - _hit_punch * 0.06 - quill_sway * 0.02))
	var quill := PackedVector2Array([Vector2(0, -29), Vector2(16, -5), Vector2(8, 27), Vector2(0, 17), Vector2(-8, 27), Vector2(-16, -5)])
	draw_colored_polygon(quill, Color(0.08, 0.08, 0.16, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array(Array(quill) + [quill[0]]), accent, 3.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if phase == Phase.TELEGRAPH:
		var perpendicular := locked_direction.orthogonal()
		draw_line(locked_direction * -820.0, locked_direction * 820.0, Color(1.0, 0.18, 0.16, 0.30), 12.0, true)
		draw_line(perpendicular * -820.0, perpendicular * 820.0, Color(1.0, 0.18, 0.16, 0.30), 12.0, true)
		draw_line(locked_direction * -820.0, locked_direction * 820.0, Color(1.0, 0.78, 0.34, 0.85), 2.5, true)
		draw_line(perpendicular * -820.0, perpendicular * 820.0, Color(1.0, 0.78, 0.34, 0.85), 2.5, true)
	elif phase == Phase.RECOVER:
		draw_arc(Vector2.ZERO, 35.0, 0.0, TAU, 28, Color(0.38, 0.96, 0.89, 0.88), 4.0, true)
	var health_ratio := clampf(health / (definition.base_health if definition != null else 13.0), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-24, -39), Vector2(48, 4)), Color(0.02, 0.04, 0.08, 0.9), true)
	draw_rect(Rect2(Vector2(-24, -39), Vector2(48 * health_ratio, 4)), accent, true)
