class_name FoldlightPaperTurret
extends StaticBody2D

signal volley_requested(snapshot: Dictionary)
signal phase_changed(phase: Phase)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

enum Phase { TELEGRAPH, VOLLEY, EXPOSED }

@export_range(0.3, 2.0, 0.05) var telegraph_duration: float = 0.9
@export_range(0.05, 0.5, 0.01) var volley_duration: float = 0.12
@export_range(0.5, 3.0, 0.05) var exposed_duration: float = 1.15
@export_range(3, 7, 2) var projectile_count: int = 5

var phase: Phase = Phase.TELEGRAPH
var target_direction: Vector2 = Vector2.RIGHT
var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"paper_turret"
var health: float = 14.0
var support_attack_multiplier: float = 1.0
var _phase_remaining: float = 0.9
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0
var _visual_time: float = 0.0


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 3) | (1 << 0)
	_phase_remaining = telegraph_duration
	queue_redraw()


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 14.0
	queue_redraw()


func advance_simulation(delta: float, target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	_visual_time += maxf(0.0, delta)
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	if phase == Phase.TELEGRAPH:
		var direction := target_position - global_position
		if not direction.is_zero_approx():
			target_direction = direction.normalized()
	_phase_remaining -= maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0) / support_attack_multiplier
	while _phase_remaining <= 0.0:
		var overflow := -_phase_remaining
		match phase:
			Phase.TELEGRAPH:
				phase = Phase.VOLLEY
				_phase_remaining = volley_duration - overflow
				volley_requested.emit({
					"origin": global_position,
					"direction": target_direction,
					"projectile_count": projectile_count,
					"spread_radians": 0.46,
					"reflectable": true,
					"speed": 310.0,
				})
			Phase.VOLLEY:
				phase = Phase.EXPOSED
				_phase_remaining = exposed_duration - overflow
			Phase.EXPOSED:
				phase = Phase.TELEGRAPH
				_phase_remaining = telegraph_duration - overflow
		phase_changed.emit(phase)
		if _phase_remaining > 0.0:
			break
	queue_redraw()


func damage_multiplier() -> float:
	return 1.65 if phase == Phase.EXPOSED else 1.0


func take_damage(amount: float) -> bool:
	if amount <= 0.0 or health <= 0.0:
		return false
	var applied := amount * damage_multiplier()
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
	queue_redraw()


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.TURRET, "health": health, "maximum_health": definition.base_health if definition != null else 14.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func telegraph_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"direction": target_direction,
		"remaining": maxf(0.0, _phase_remaining),
		"duration": telegraph_duration if phase == Phase.TELEGRAPH else exposed_duration,
	}


func _draw() -> void:
	var glow := Color(1.0, 0.30, 0.22, 0.20) if phase == Phase.TELEGRAPH else Color(0.30, 0.90, 0.88, 0.16)
	for ring in range(4, 0, -1):
		draw_circle(Vector2.ZERO, 25.0 + float(ring) * 6.0, Color(glow, glow.a / float(ring)))
	var mechanical_pulse := sin(_visual_time * (8.0 if phase == Phase.TELEGRAPH else 3.2))
	draw_set_transform(Vector2(0, mechanical_pulse * 1.4), mechanical_pulse * 0.045, Vector2(1.0 + _hit_punch * 0.10 + mechanical_pulse * 0.02, 1.0 - _hit_punch * 0.06 - mechanical_pulse * 0.02))
	var body_color := (Color(0.94, 0.38, 0.28) if phase != Phase.EXPOSED else Color(0.35, 0.88, 0.82)).lerp(Color.WHITE, _hit_flash * 0.78)
	var diamond := PackedVector2Array([Vector2(0, -25), Vector2(27, 0), Vector2(0, 25), Vector2(-27, 0)])
	draw_colored_polygon(diamond, Color(0.08, 0.10, 0.18, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), body_color, 4.0, true)
	draw_circle(Vector2.ZERO, 8.0, body_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if phase == Phase.TELEGRAPH:
		draw_line(target_direction * 25.0, target_direction * 620.0, Color(1.0, 0.25, 0.20, 0.28), 8.0, true)
		draw_line(target_direction * 25.0, target_direction * 620.0, Color(1.0, 0.82, 0.55, 0.76), 2.0, true)
	elif phase == Phase.EXPOSED:
		draw_arc(Vector2.ZERO, 34.0, -PI, PI, 24, Color(0.53, 1.0, 0.90, 0.92), 3.0, true)
	if support_attack_multiplier < 0.99:
		draw_arc(Vector2.ZERO, 39.0, 0.0, TAU, 24, Color(1, 0.76, 0.24, 0.82), 3.0, true)
