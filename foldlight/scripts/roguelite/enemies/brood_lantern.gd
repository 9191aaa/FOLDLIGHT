class_name FoldlightBroodLantern
extends StaticBody2D

signal spawn_requested(snapshot: Dictionary)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

@export_range(3.0, 9.0, 0.1) var spawn_interval: float = 5.8
@export_range(0.5, 2.0, 0.05) var telegraph_duration: float = 1.15
@export_range(1, 4, 1) var brood_count: int = 2

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"brood_lantern"
var health: float = 16.0
var support_attack_multiplier: float = 1.0
var _spawn_remaining: float = 3.2
var _visual_time: float = 0.0
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 3)
	queue_redraw()


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 16.0
	queue_redraw()


func advance_simulation(delta: float, _target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0) / support_attack_multiplier
	_visual_time += safe_delta
	_spawn_remaining -= safe_delta
	if _spawn_remaining <= 0.0:
		var positions: Array[Vector2] = []
		for index in brood_count:
			var angle := float(index) / float(maxi(1, brood_count)) * TAU + _visual_time
			positions.append(global_position + Vector2.from_angle(angle) * 88.0)
		spawn_requested.emit({"source_id": actor_id, "enemy_id": &"paper_drifter", "positions": positions, "maximum": 6})
		_spawn_remaining = spawn_interval
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


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.TURRET, "health": health, "maximum_health": definition.base_health if definition != null else 16.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func _draw() -> void:
	var warning := _spawn_remaining <= telegraph_duration
	var accent := (Color(1.0, 0.47, 0.28) if warning else Color(0.96, 0.73, 0.30)).lerp(Color.WHITE, _hit_flash * 0.78)
	for ring in range(4, 0, -1):
		draw_circle(Vector2.ZERO, 24.0 + float(ring) * 7.0, Color(accent.r, accent.g, accent.b, 0.022 * float(5 - ring)))
	var breathe := sin(_visual_time * 3.2)
	draw_set_transform(Vector2(0, breathe * 2.0), breathe * 0.035, Vector2(1.0 + _hit_punch * 0.10 + breathe * 0.025, 1.0 - _hit_punch * 0.06 - breathe * 0.02))
	var lantern := PackedVector2Array([Vector2(0, -29), Vector2(24, -6), Vector2(17, 25), Vector2(-17, 25), Vector2(-24, -6)])
	draw_colored_polygon(lantern, Color(0.10, 0.08, 0.16, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array(Array(lantern) + [lantern[0]]), accent, 4.0, true)
	draw_circle(Vector2.ZERO, 9.0 + sin(_visual_time * 6.0) * 2.0, Color(1.0, 0.78, 0.34, 0.82))
	for seed in 3:
		var angle := _visual_time * 1.8 + float(seed) * TAU / 3.0
		draw_circle(Vector2.from_angle(angle) * 38.0, 4.5, Color(0.42, 0.96, 0.87, 0.78))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if warning:
		var ratio := 1.0 - clampf(_spawn_remaining / telegraph_duration, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 49.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, Color(1.0, 0.34, 0.22, 0.92), 5.0, true)
	var health_ratio := clampf(health / (definition.base_health if definition != null else 16.0), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-25, -40), Vector2(50, 4)), Color(0.02, 0.04, 0.08, 0.9), true)
	draw_rect(Rect2(Vector2(-25, -40), Vector2(50 * health_ratio, 4)), accent, true)
