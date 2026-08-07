class_name FoldlightBellBinder
extends CharacterBody2D

signal tethers_changed(target_ids: Array[StringName])
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

@export_range(200.0, 800.0, 10.0) var tether_radius: float = 520.0
@export_range(1, 3, 1) var maximum_tethers: int = 2
@export_range(0.5, 1.0, 0.01) var attack_interval_multiplier: float = 0.78
@export_range(1.0, 1.5, 0.01) var move_speed_multiplier: float = 1.12

var _tether_ids: Array[StringName] = []
var _tether_positions: Array[Vector2] = []
var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"bell_binder"
var health: float = 11.0
var _hit_flash: float = 0.0
var _hit_punch: float = 0.0
var _visual_time: float = 0.0


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 11.0
	queue_redraw()


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	queue_redraw()


func update_tethers(candidates: Array[Dictionary]) -> void:
	var valid: Array[Dictionary] = []
	for candidate in candidates:
		var candidate_id := StringName(candidate.get("id", &""))
		var candidate_position := Vector2(candidate.get("position", Vector2.ZERO))
		var role := int(candidate.get("role", FoldlightRogueEnemyDefinition.EnemyRole.FODDER))
		if candidate_id.is_empty() or not bool(candidate.get("alive", true)):
			continue
		if role == FoldlightRogueEnemyDefinition.EnemyRole.BUFFER:
			continue
		var distance := global_position.distance_to(candidate_position)
		if distance <= tether_radius:
			var snapshot := candidate.duplicate(true)
			snapshot["distance"] = distance
			valid.append(snapshot)
	valid.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("distance", INF)) < float(b.get("distance", INF)))
	var next_ids: Array[StringName] = []
	var next_positions: Array[Vector2] = []
	for index in mini(maximum_tethers, valid.size()):
		next_ids.append(StringName(valid[index].get("id", &"")))
		next_positions.append(Vector2(valid[index].get("position", Vector2.ZERO)))
	if next_ids != _tether_ids:
		_tether_ids = next_ids
		_tether_positions = next_positions
		tethers_changed.emit(get_tether_ids())
	else:
		_tether_positions = next_positions
	queue_redraw()


func get_tether_ids() -> Array[StringName]:
	return _tether_ids.duplicate()


func get_buff_snapshot() -> Dictionary:
	return {
		"source_role": FoldlightRogueEnemyDefinition.EnemyRole.BUFFER,
		"attack_interval_multiplier": attack_interval_multiplier,
		"move_speed_multiplier": move_speed_multiplier,
		"target_ids": get_tether_ids(),
	}


func advance_simulation(delta: float, player_position: Vector2, ally_center: Vector2, hostile_time_scale: float = 1.0) -> void:
	_hit_flash = maxf(0.0, _hit_flash - maxf(0.0, delta) * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - maxf(0.0, delta) * 8.5)
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	_visual_time += safe_delta
	var away := global_position - player_position
	var desired := Vector2.ZERO
	if away.length() < 330.0:
		desired = away.normalized()
	elif global_position.distance_to(ally_center) > 320.0:
		desired = global_position.direction_to(ally_center)
	velocity = velocity.move_toward(desired * (definition.move_speed if definition != null else 102.0), 520.0 * safe_delta)
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


func set_support_buff(_attack_multiplier: float) -> void:
	pass


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, "health": health, "maximum_health": definition.base_health if definition != null else 11.0}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_punch}


func _draw() -> void:
	for target_position in _tether_positions:
		var endpoint := to_local(target_position)
		draw_dashed_line(Vector2.ZERO, endpoint, Color(0.98, 0.78, 0.25, 0.78), 3.0, 12.0, true)
		draw_circle(endpoint, 7.0, Color(1.0, 0.88, 0.44, 0.66))
	for ring in range(3, 0, -1):
		draw_circle(Vector2.ZERO, 24.0 + float(ring) * 7.0, Color(1.0, 0.72, 0.22, 0.035 * float(4 - ring)))
	var sway := sin(_visual_time * 3.4)
	draw_set_transform(Vector2(0, sway * 2.5), sway * 0.055, Vector2(1.0 + _hit_punch * 0.10, 1.0 - _hit_punch * 0.06) * Vector2(1.0 + sway * 0.018, 1.0 - sway * 0.025))
	var bell := PackedVector2Array([Vector2(-22, 17), Vector2(-15, -12), Vector2(0, -25), Vector2(15, -12), Vector2(22, 17)])
	draw_colored_polygon(bell, Color(0.13, 0.12, 0.20, 0.98).lerp(Color.WHITE, _hit_flash * 0.64))
	draw_polyline(PackedVector2Array([bell[0], bell[1], bell[2], bell[3], bell[4]]), Color(1.0, 0.76, 0.28).lerp(Color.WHITE, _hit_flash * 0.78), 4.0, true)
	draw_line(Vector2(-25, 18), Vector2(25, 18), Color(1.0, 0.90, 0.54), 4.0, true)
	draw_circle(Vector2(0, 24), 5.0, Color(1.0, 0.72, 0.24))
	draw_arc(Vector2.ZERO, 31.0 + sin(_visual_time * 5.0) * 3.0, -PI * 0.82, PI * 0.18, 24, Color(1.0, 0.82, 0.38, 0.36), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
