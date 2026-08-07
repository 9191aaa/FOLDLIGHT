class_name FoldlightRogueEnemyActor
extends CharacterBody2D

signal attack_requested(snapshot: Dictionary)
signal player_pressure_requested(snapshot: Dictionary)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

enum ActionState { APPROACH, TELEGRAPH, CHARGE, RECOVER }
enum MirrorState { SEEK, FOLD, RELEASE }
enum RewindState { ROAM, TELEGRAPH, REWIND, RECOVER }

const CLASSIC_RADII: Dictionary = {
	&"drifter": 27.0,
	&"fan": 34.0,
	&"weaver": 38.0,
	&"ram": 42.0,
	&"bloomer": 45.0,
	&"leech": 43.0,
	&"mirror": 48.0,
	&"rewinder": 45.0,
}
const CLASSIC_VISUAL_VERSION: StringName = &"classic_2_0_exact"

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"enemy"
var health: float = 1.0
var action_state: ActionState = ActionState.APPROACH
var target_position: Vector2 = Vector2.ZERO
var locked_direction: Vector2 = Vector2.RIGHT
var support_attack_multiplier: float = 1.0
var classic_archetype: StringName = &"drifter"
var arena_center: Vector2 = Vector2(960.0, 535.0)

var mirror_state: MirrorState = MirrorState.SEEK
var stored_light: int = 0
var rewind_state: RewindState = RewindState.ROAM

var _attack_remaining: float = 0.8
var _special_remaining: float = 3.6
var _skill_charge: float = 0.0
var _state_remaining: float = 0.0
var _age: float = 0.0
var _phase: float = 0.0
var _flash: float = 0.0
var _hit_punch: float = 0.0
var _hit_ring: float = 0.0
var _hit_direction: Vector2 = Vector2.ZERO
var _mirror_remaining: float = 2.4
var _path_sample_remaining: float = 0.08
var _path_history: Array[Vector2] = []
var _rewind_path: Array[Vector2] = []
var _rewind_index: int = -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	queue_redraw()


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	classic_archetype = _resolve_classic_archetype(definition.content_id if definition != null else &"drifter")
	health = definition.base_health if definition != null else 1.0
	_rng.seed = hash(String(actor_id))
	_attack_remaining = _rng.randf_range(0.75, 1.8)
	_special_remaining = _rng.randf_range(2.0, 3.8)
	_phase = _rng.randf_range(0.0, TAU)
	_mirror_remaining = _rng.randf_range(2.2, 3.0)
	if classic_archetype == &"ram":
		_state_remaining = _rng.randf_range(1.7, 2.5)
	elif classic_archetype == &"rewinder":
		_state_remaining = _rng.randf_range(4.2, 5.0)
	_path_history.clear()
	_rewind_path.clear()
	_rewind_index = -1
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is CircleShape2D:
		collision.shape = collision.shape.duplicate()
		(collision.shape as CircleShape2D).radius = get_contact_radius()
	queue_redraw()


func advance_simulation(delta: float, new_target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if definition == null or health <= 0.0:
		return
	var safe_delta := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	target_position = new_target_position
	_age += safe_delta
	_flash = maxf(0.0, _flash - safe_delta * 5.5)
	_hit_punch = maxf(0.0, _hit_punch - safe_delta * 6.8)
	_hit_ring = maxf(0.0, _hit_ring - safe_delta * 4.6)
	match classic_archetype:
		&"drifter":
			_advance_drifter(safe_delta)
		&"fan":
			_advance_fan(safe_delta)
		&"weaver":
			_advance_weaver(safe_delta)
		&"ram":
			_advance_ram(safe_delta)
		&"bloomer":
			_advance_bloomer(safe_delta)
		&"leech":
			_advance_leech(safe_delta)
		&"mirror":
			_advance_mirror(safe_delta)
		&"rewinder":
			_advance_rewinder(safe_delta)
		_:
			_advance_drifter(safe_delta)
	move_and_slide()
	queue_redraw()


func take_damage(amount: float) -> bool:
	if health <= 0.0 or amount <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	_flash = 1.0
	_hit_punch = 1.0
	_hit_ring = 1.0
	if _hit_direction.is_zero_approx():
		_hit_direction = target_position.direction_to(global_position)
		if _hit_direction.is_zero_approx():
			_hit_direction = Vector2.from_angle(_phase)
	damaged.emit(amount, health)
	if health <= 0.0:
		defeated.emit(self)
		return true
	queue_redraw()
	return false


func take_projectile_damage(amount: float, incoming_velocity: Vector2, _style: StringName) -> bool:
	if not incoming_velocity.is_zero_approx():
		_hit_direction = incoming_velocity.normalized()
	return take_damage(amount)


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _flash, "punch": _hit_punch, "ring": _hit_ring, "direction": _hit_direction}


func set_support_buff(attack_multiplier: float) -> void:
	support_attack_multiplier = clampf(attack_multiplier, 0.55, 1.0)
	queue_redraw()


func get_combat_snapshot() -> Dictionary:
	return {
		"id": actor_id,
		"position": global_position,
		"alive": health > 0.0,
		"role": definition.role if definition != null else FoldlightRogueEnemyDefinition.EnemyRole.FODDER,
		"health": health,
		"maximum_health": definition.base_health if definition != null else 1.0,
		"classic_archetype": classic_archetype,
		"mirror_state": mirror_state,
		"stored_light": stored_light,
		"rewind_state": rewind_state,
		"records_rewind_path": classic_archetype == &"rewinder",
		"contact_dangerous": is_contact_dangerous(),
		"visual_version": CLASSIC_VISUAL_VERSION,
	}


func get_classic_contract() -> Dictionary:
	return {
		"version": CLASSIC_VISUAL_VERSION,
		"archetype": classic_archetype,
		"health": definition.base_health if definition != null else 1.0,
		"radius": get_contact_radius(),
		"attack_timer_range": _classic_attack_timer_range(),
		"arena_anchor": arena_center,
		"behavior": _classic_behavior_contract(),
	}


func set_arena_center(value: Vector2) -> void:
	arena_center = value


func get_contact_radius() -> float:
	return float(CLASSIC_RADII.get(classic_archetype, 27.0))


func is_contact_dangerous() -> bool:
	if classic_archetype == &"ram":
		return action_state == ActionState.CHARGE
	if classic_archetype == &"rewinder":
		return rewind_state == RewindState.REWIND
	return true


func can_intercept_return_light() -> bool:
	return classic_archetype == &"mirror" and mirror_state == MirrorState.FOLD and stored_light < 18


func capture_return_light() -> bool:
	if not can_intercept_return_light():
		return false
	stored_light = mini(18, stored_light + 1)
	_flash = 0.72
	queue_redraw()
	return true


func _resolve_classic_archetype(content_id: StringName) -> StringName:
	match content_id:
		&"paper_drifter": return &"drifter"
		&"needle_skiff": return &"fan"
		&"reef_ram": return &"ram"
		_: return content_id


func _advance_drifter(delta: float) -> void:
	var offset := target_position - global_position
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	var drift := direction.orthogonal() * sin(_age * 1.8 + _phase) * 34.0
	velocity = velocity.lerp(direction * definition.move_speed + drift, minf(1.0, delta * 1.8))
	_tick_attack(delta)
	if _attack_remaining <= 0.0:
		_emit_classic_aimed([{"offset": 0.0, "speed": 160.0, "curve": 0.0}], Color(0.68, 0.27, 0.70))
		_attack_remaining = _rng.randf_range(1.65, 2.3) * support_attack_multiplier


func _advance_fan(delta: float) -> void:
	var offset := target_position - global_position
	var distance := offset.length()
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	var radial := direction * clampf((distance - 520.0) * 0.32, -72.0, 72.0)
	var orbit := direction.orthogonal() * (64.0 + sin(_phase) * 14.0)
	velocity = velocity.lerp(radial + orbit, minf(1.0, delta * 2.2))
	_tick_attack(delta)
	if _attack_remaining <= 0.0:
		var shots: Array[Dictionary] = []
		for shot_index in 5:
			var offset_angle := (float(shot_index) - 2.0) * 0.19
			shots.append({"offset": offset_angle, "speed": 152.0 + absf(offset_angle) * 44.0, "curve": offset_angle * 0.08})
		_emit_classic_aimed(shots, Color(0.82, 0.25, 0.61))
		_attack_remaining = _rng.randf_range(2.2, 2.75) * support_attack_multiplier


func _advance_weaver(delta: float) -> void:
	var anchor := arena_center + Vector2.from_angle(_age * 0.24 + _phase) * 470.0
	velocity = velocity.lerp((anchor - global_position).limit_length(definition.move_speed), minf(1.0, delta * 1.9))
	_tick_attack(delta)
	_special_remaining -= delta
	if _skill_charge > 0.0:
		_skill_charge = maxf(0.0, _skill_charge - delta)
		velocity *= 0.55
		if _skill_charge <= 0.0:
			var seal_shots: Array[Dictionary] = []
			for shot_index in 3:
				var offset_angle := (float(shot_index) - 1.0) * 0.22
				seal_shots.append({"offset": offset_angle, "speed": 208.0 + absf(offset_angle) * 38.0, "curve": -offset_angle * 0.08})
			_emit_classic_aimed(seal_shots, Color(1.0, 0.42, 0.16), false, 2, &"paper_seal")
			_special_remaining = 6.6
	elif _special_remaining <= 0.0:
		_skill_charge = 0.95
	elif _attack_remaining <= 0.0:
		var angle := _age * 2.08 + _phase
		_emit_classic_absolute([{"angle": angle, "speed": 146.0, "curve": 0.31}], Color(0.47, 0.37, 0.83), true, 1, &"hostile_petal", &"veiled_fold", 5.2)
		_attack_remaining = 0.46 * support_attack_multiplier


func _advance_ram(delta: float) -> void:
	match action_state:
		ActionState.APPROACH:
			var offset := target_position - global_position
			var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
			var radial := direction * clampf((offset.length() - 470.0) * 0.28, -62.0, 82.0)
			var orbit := direction.orthogonal() * sin(_age * 0.9 + _phase) * 72.0
			velocity = velocity.lerp(radial + orbit, minf(1.0, delta * 2.0))
			_state_remaining -= delta
			if _state_remaining <= 0.0:
				action_state = ActionState.TELEGRAPH
				locked_direction = direction
				_state_remaining = 0.95
		ActionState.TELEGRAPH:
			_state_remaining -= delta
			if _state_remaining > 0.65:
				var offset := target_position - global_position
				if not offset.is_zero_approx():
					locked_direction = offset.normalized()
			velocity = velocity.move_toward(Vector2.ZERO, 720.0 * delta)
			if _state_remaining <= 0.0:
				action_state = ActionState.CHARGE
				_state_remaining = 0.72
				velocity = locked_direction * 840.0
		ActionState.CHARGE:
			velocity = locked_direction * 840.0
			_state_remaining -= delta
			if _state_remaining <= 0.0:
				action_state = ActionState.RECOVER
				_state_remaining = 0.78
		ActionState.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 980.0 * delta)
			_state_remaining -= delta
			if _state_remaining <= 0.0:
				action_state = ActionState.APPROACH
				_state_remaining = _rng.randf_range(2.0, 2.8) * support_attack_multiplier


func _advance_bloomer(delta: float) -> void:
	var anchor := arena_center + Vector2.from_angle(_phase) * 420.0
	velocity = velocity.lerp((anchor - global_position).limit_length(definition.move_speed), minf(1.0, delta * 1.6))
	_tick_attack(delta)
	if _attack_remaining <= 0.0:
		var shots: Array[Dictionary] = []
		for shot_index in 9:
			shots.append({"angle": _age * 0.31 + float(shot_index) * TAU / 9.0, "speed": 112.0, "curve": sin(float(shot_index) * 1.7) * 0.055})
		_emit_classic_absolute(shots, Color(0.58, 0.31, 0.79))
		_attack_remaining = 2.65 * support_attack_multiplier


func _advance_leech(delta: float) -> void:
	var offset := target_position - global_position
	var distance := offset.length()
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	var movement := direction * clampf((distance - 225.0) * 0.52, -84.0, 116.0)
	movement += direction.orthogonal() * sin(_age * 1.4 + _phase) * 54.0
	velocity = velocity.lerp(movement, minf(1.0, delta * 2.1))
	if distance < 245.0:
		player_pressure_requested.emit({"focus_delta": -delta * 0.040, "status": &"wet_ink", "status_duration": 0.28})
	_tick_attack(delta)
	if _attack_remaining <= 0.0:
		var shots: Array[Dictionary] = []
		for offset_angle in [-0.20, 0.0, 0.20]:
			shots.append({"offset": offset_angle, "speed": 164.0, "curve": float(offset_angle) * 0.14})
		_emit_classic_aimed(shots, Color(0.86, 0.22, 0.58), true, 0, &"hostile_petal", &"wet_ink", 5.4)
		_attack_remaining = 2.25 * support_attack_multiplier


func _advance_mirror(delta: float) -> void:
	var offset := target_position - global_position
	var distance := offset.length()
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	var movement := direction * clampf((distance - 410.0) * 0.38, -86.0, 108.0)
	movement += direction.orthogonal() * (58.0 + sin(_age * 1.2 + _phase) * 18.0)
	_tick_attack(delta)
	_mirror_remaining -= delta
	match mirror_state:
		MirrorState.SEEK:
			velocity = velocity.lerp(movement, minf(1.0, delta * 2.0))
			if _attack_remaining <= 0.0:
				_emit_classic_aimed([
					{"offset": -0.12, "speed": 172.0, "curve": 0.0192},
					{"offset": 0.12, "speed": 172.0, "curve": -0.0192},
				], Color(0.28, 0.72, 0.80))
				_attack_remaining = 1.75 * support_attack_multiplier
			if _mirror_remaining <= 0.0:
				mirror_state = MirrorState.FOLD
				_mirror_remaining = 1.85
		MirrorState.FOLD:
			velocity = velocity.lerp(movement * 0.24, minf(1.0, delta * 2.0))
			if _mirror_remaining <= 0.0:
				mirror_state = MirrorState.RELEASE
				_mirror_remaining = 0.55
				if stored_light > 0:
					var count := mini(12, stored_light)
					var span := minf(1.05, 0.12 * float(count - 1))
					var shots: Array[Dictionary] = []
					for shot_index in count:
						var ratio := 0.5 if count == 1 else float(shot_index) / float(count - 1)
						var offset_angle := lerpf(-span * 0.5, span * 0.5, ratio)
						shots.append({"offset": offset_angle, "speed": 186.0 + float(stored_light) * 3.0, "curve": -offset_angle * 0.10})
					_emit_classic_aimed(shots, Color(0.28, 0.80, 0.82), true, 0, &"hostile_petal", &"veiled_fold", 5.0)
					stored_light = 0
		MirrorState.RELEASE:
			velocity = velocity.lerp(movement * 0.55, minf(1.0, delta * 2.0))
			if _mirror_remaining <= 0.0:
				mirror_state = MirrorState.SEEK
				_mirror_remaining = 2.65


func _advance_rewinder(delta: float) -> void:
	match rewind_state:
		RewindState.ROAM:
			var offset := target_position - global_position
			var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
			var orbit := direction.orthogonal() * (88.0 + sin(_age * 1.1 + _phase) * 24.0)
			velocity = velocity.lerp(direction * 78.0 + orbit, minf(1.0, delta * 2.3))
			_path_sample_remaining -= delta
			if _path_sample_remaining <= 0.0:
				while _path_sample_remaining <= 0.0:
					_path_sample_remaining += 0.08
				_path_history.append(global_position)
				if _path_history.size() > 54:
					_path_history.pop_front()
			_state_remaining -= delta
			if _state_remaining <= 0.0 and _path_history.size() >= 48:
				rewind_state = RewindState.TELEGRAPH
				_state_remaining = 1.20
				_rewind_path = _path_history.duplicate()
				_rewind_index = _rewind_path.size() - 1
		RewindState.TELEGRAPH:
			velocity = velocity.move_toward(Vector2.ZERO, 760.0 * delta)
			_state_remaining -= delta
			if _state_remaining <= 0.0:
				rewind_state = RewindState.REWIND
				_state_remaining = 5.2
		RewindState.REWIND:
			_state_remaining -= delta
			while _rewind_index >= 0 and global_position.distance_to(_rewind_path[_rewind_index]) <= maxf(20.0, 900.0 * delta * 1.25):
				_rewind_index -= 1
			if _rewind_index < 0 or _state_remaining <= 0.0:
				rewind_state = RewindState.RECOVER
				_state_remaining = 0.85
				velocity *= 0.12
			else:
				var destination := _rewind_path[_rewind_index]
				velocity = global_position.direction_to(destination) * 900.0
		RewindState.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 1050.0 * delta)
			_state_remaining -= delta
			if _state_remaining <= 0.0:
				rewind_state = RewindState.ROAM
				_state_remaining = _rng.randf_range(4.4, 5.3) * support_attack_multiplier
				_path_history.clear()
				_rewind_path.clear()
				_rewind_index = -1


func _tick_attack(delta: float) -> void:
	_attack_remaining -= delta


func _classic_attack_timer_range() -> Vector2:
	match classic_archetype:
		&"drifter": return Vector2(1.65, 2.3)
		&"fan": return Vector2(2.2, 2.75)
		&"weaver": return Vector2(0.46, 0.46)
		&"ram": return Vector2(2.0, 2.8)
		&"bloomer": return Vector2(2.65, 2.65)
		&"leech": return Vector2(2.25, 2.25)
		&"mirror": return Vector2(1.75, 1.75)
		&"rewinder": return Vector2(4.4, 5.3)
	return Vector2.ONE


func _classic_behavior_contract() -> Dictionary:
	match classic_archetype:
		&"drifter": return {"move_speed": 63.0, "drift": 34.0, "lerp": 1.8, "shot_speed": 160.0}
		&"fan": return {"preferred_distance": 520.0, "radial_factor": 0.32, "radial_limit": 72.0, "orbit": 64.0, "shot_count": 5}
		&"weaver": return {"orbit_radius": 470.0, "move_limit": 105.0, "shot_curve": 0.31, "seal_charge": 0.95, "seal_count": 3}
		&"ram": return {"stalk_distance": 470.0, "telegraph": 0.95, "aim_window": 0.30, "charge_speed": 840.0, "charge_time": 0.72, "recover": 0.78}
		&"bloomer": return {"anchor_radius": 420.0, "shot_count": 9, "shot_speed": 112.0, "curve": 0.055}
		&"leech": return {"preferred_distance": 225.0, "drain_radius": 245.0, "drain_rate": 0.040, "shot_count": 3, "shot_speed": 164.0}
		&"mirror": return {"preferred_distance": 410.0, "fold_time": 1.85, "release_time": 0.55, "intercept_radius": 138.0, "stored_limit": 18}
		&"rewinder": return {"sample_interval": 0.08, "history_samples": 54, "telegraph": 1.20, "rewind_speed": 900.0, "recover": 0.85}
	return {}


func _emit_classic_aimed(shots: Array[Dictionary], color: Color, reflectable: bool = true, kind: int = 0, style: StringName = &"hostile_petal", status: StringName = &"", status_duration: float = 0.0) -> void:
	var offset := target_position - global_position
	var base_angle := offset.angle() if not offset.is_zero_approx() else PI * 0.5
	var absolute_shots: Array[Dictionary] = []
	var minimum_offset := 0.0
	var maximum_offset := 0.0
	for index in shots.size():
		var shot := shots[index]
		var shot_offset := float(shot.get("offset", 0.0))
		if index == 0:
			minimum_offset = shot_offset
			maximum_offset = shot_offset
		else:
			minimum_offset = minf(minimum_offset, shot_offset)
			maximum_offset = maxf(maximum_offset, shot_offset)
		absolute_shots.append({
			"direction": Vector2.from_angle(base_angle + shot_offset),
			"speed": float(shot.get("speed", 160.0)),
			"curve": float(shot.get("curve", 0.0)),
		})
	attack_requested.emit({
		"origin": global_position,
		"direction": Vector2.from_angle(base_angle),
		"projectile_count": absolute_shots.size(),
		"spread_radians": maximum_offset - minimum_offset,
		"reflectable": reflectable,
		"speed": float(shots[0].get("speed", 160.0)) if not shots.is_empty() else 160.0,
		"kind": kind,
		"radius": 10.0 if kind == 0 else 8.5,
		"lifetime": 11.0,
		"style": style,
		"color": color,
		"status": status,
		"status_duration": status_duration,
		"projectiles": absolute_shots,
		"classic_contract": CLASSIC_VISUAL_VERSION,
	})


func _emit_classic_absolute(shots: Array[Dictionary], color: Color, reflectable: bool = true, kind: int = 0, style: StringName = &"hostile_petal", status: StringName = &"", status_duration: float = 0.0) -> void:
	var absolute_shots: Array[Dictionary] = []
	for shot in shots:
		absolute_shots.append({
			"direction": Vector2.from_angle(float(shot.get("angle", 0.0))),
			"speed": float(shot.get("speed", 160.0)),
			"curve": float(shot.get("curve", 0.0)),
		})
	attack_requested.emit({
		"origin": global_position,
		"direction": absolute_shots[0].get("direction", Vector2.DOWN) if not absolute_shots.is_empty() else Vector2.DOWN,
		"projectile_count": absolute_shots.size(),
		"radial": absolute_shots.size() > 1,
		"reflectable": reflectable,
		"speed": float(shots[0].get("speed", 160.0)) if not shots.is_empty() else 160.0,
		"kind": kind,
		"radius": 10.0 if kind == 0 else 8.5,
		"lifetime": 11.0,
		"style": style,
		"color": color,
		"status": status,
		"status_duration": status_duration,
		"projectiles": absolute_shots,
		"classic_contract": CLASSIC_VISUAL_VERSION,
	})


func _draw() -> void:
	if definition == null:
		return
	var spawn_scale := maxf(0.055, ease(clampf(_age / 0.52, 0.0, 1.0), -2.0))
	var dark := Color(0.035, 0.025, 0.075).lerp(Color.WHITE, _flash * 0.72)
	var ink := Color(0.70, 0.18, 0.54).lerp(Color.WHITE, _flash)
	if _hit_ring > 0.0:
		var ring_progress := 1.0 - _hit_ring
		var ring_radius := get_contact_radius() + 5.0 + ring_progress * 34.0
		draw_circle(Vector2.ZERO, ring_radius * 0.72, Color(1.0, 0.65, 0.22, _hit_ring * 0.075))
		draw_arc(Vector2.ZERO, ring_radius, -PI * 0.88, PI * 0.88, 32, Color(1.0, 0.86, 0.52, _hit_ring * 0.92), 4.6 - ring_progress * 2.2, true)
		draw_arc(Vector2.ZERO, ring_radius - 8.0, PI * 0.16, PI * 1.12, 22, Color(0.38, 0.96, 0.90, _hit_ring * 0.58), 2.2, true)
		for shard in 4:
			var shard_direction := _hit_direction.rotated((float(shard) - 1.5) * 0.42)
			draw_line(shard_direction * 10.0, shard_direction * (24.0 + ring_progress * 30.0), Color(1.0, 0.70, 0.26, _hit_ring * 0.84), 3.4, true)
	var movement_ratio := clampf(velocity.length() / maxf(1.0, definition.move_speed if definition != null else 100.0), 0.0, 1.4)
	var idle_wave := sin(_age * (2.8 + movement_ratio * 1.4) + _phase)
	var animation_offset := Vector2(0.0, idle_wave * (1.8 + movement_ratio * 0.7))
	var animation_scale := Vector2(1.0 + idle_wave * 0.018, 1.0 - idle_wave * 0.028)
	var movement_tilt := clampf(velocity.x / 700.0, -0.12, 0.12)
	var punch_offset := _hit_direction * _hit_punch * 11.0
	var punch_scale := Vector2(1.0 + _hit_punch * 0.12, 1.0 - _hit_punch * 0.08)
	draw_set_transform(punch_offset + animation_offset, movement_tilt, punch_scale * animation_scale)
	if support_attack_multiplier < 0.99:
		draw_arc(Vector2.ZERO, get_contact_radius() + 9.0, 0.0, TAU, 32, Color(1, 0.76, 0.24, 0.72), 2.5, true)
	match classic_archetype:
		&"drifter": _draw_drifter(spawn_scale, dark, ink)
		&"fan": _draw_fan(spawn_scale, dark)
		&"weaver": _draw_weaver(spawn_scale, dark, ink)
		&"ram": _draw_ram(spawn_scale, dark)
		&"bloomer": _draw_bloomer(spawn_scale)
		&"leech": _draw_leech(spawn_scale)
		&"mirror": _draw_mirror(spawn_scale)
		&"rewinder": _draw_rewinder(spawn_scale)
		_: _draw_drifter(spawn_scale, dark, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _skill_charge > 0.0:
		_draw_sealed_charge(get_contact_radius(), _skill_charge)


func _draw_drifter(spawn_scale: float, dark: Color, ink: Color) -> void:
	for petal in 6:
		var angle := float(petal) * TAU / 6.0 + _age * 0.34
		var center := Vector2.from_angle(angle) * 14.0 * spawn_scale
		var points := _diamond(center, angle, 27.0 * spawn_scale, 12.0 * spawn_scale)
		draw_colored_polygon(points, dark)
		draw_polyline(_closed(points), Color(ink.r, ink.g, ink.b, 0.52), 1.4, true)
	draw_circle(Vector2.ZERO, 9.0 * spawn_scale, ink)
	draw_circle(Vector2.ZERO, 3.0 * spawn_scale, Color(1.0, 0.68, 0.30))


func _draw_fan(spawn_scale: float, dark: Color) -> void:
	var rotation := global_position.direction_to(target_position).angle() + PI * 0.5
	var left := _rotated_points(rotation, [Vector2(0,-38), Vector2(-42,25), Vector2(0,12)])
	var right := _rotated_points(rotation, [Vector2(0,-38), Vector2(42,25), Vector2(0,12)])
	draw_colored_polygon(_scaled_points(left, spawn_scale), dark)
	draw_colored_polygon(_scaled_points(right, spawn_scale), Color(0.10, 0.06, 0.17).lerp(Color.WHITE, _flash * 0.7))
	draw_line(left[0], left[1], Color(0.88, 0.24, 0.54, 0.76), 2.0, true)
	draw_line(right[0], right[1], Color(0.40, 0.68, 0.82, 0.72), 2.0, true)
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.69, 0.28))


func _draw_weaver(spawn_scale: float, dark: Color, ink: Color) -> void:
	for ring in 3:
		var radius := (14.0 + ring * 10.0) * spawn_scale
		draw_arc(Vector2.ZERO, radius, _age * (0.7 + ring * 0.2), _age * (0.7 + ring * 0.2) + PI * 1.35, 30, Color(0.54, 0.31 + ring * 0.08, 0.78, 0.72 - ring * 0.14), 4.2 - ring, true)
	for spoke in 4:
		var angle := _age * -0.6 + spoke * PI * 0.5
		draw_line(Vector2.from_angle(angle) * 7.0, Vector2.from_angle(angle) * 35.0 * spawn_scale, Color(ink.r, ink.g, ink.b, 0.42), 2.0, true)
	draw_circle(Vector2.ZERO, 7.0, dark)
	draw_circle(Vector2.ZERO, 2.8, Color(1.0, 0.72, 0.32))
	if _skill_charge > 0.0:
		draw_arc(Vector2.ZERO, 48.0 + _skill_charge * 24.0, -PI, PI, 40, Color(1.0, 0.48, 0.20, 0.72), 3.0, true)


func _draw_ram(spawn_scale: float, dark: Color) -> void:
	var direction := locked_direction if action_state in [ActionState.TELEGRAPH, ActionState.CHARGE] else velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var rotation := direction.angle()
	if action_state == ActionState.TELEGRAPH:
		var warning_ratio := clampf(_state_remaining / 0.95, 0.0, 1.0)
		draw_line(Vector2.ZERO, direction * 1280.0, Color(0.68, 0.06, 0.18, 0.075 + (1.0 - warning_ratio) * 0.045), 68.0, true)
		draw_dashed_line(Vector2.ZERO, direction * 1280.0, Color(1.0, 0.66, 0.24, 0.58), 2.5, 22.0, true)
		for warning_arc in 3:
			draw_arc(Vector2.ZERO, 62.0 + warning_ratio * 68.0 + warning_arc * 10.0, rotation - 0.68, rotation + 0.68, 28, Color(1.0, 0.48, 0.24, 0.42 - warning_arc * 0.09), 2.0, true)
	var body := _scaled_points(_rotated_points(rotation, [Vector2(48,0), Vector2(3,31), Vector2(-36,18), Vector2(-25,0), Vector2(-36,-18), Vector2(3,-31)]), spawn_scale)
	draw_colored_polygon(body, dark)
	draw_polyline(_closed(body), Color(0.90, 0.23, 0.49, 0.72), 2.2, true)
	draw_line(-direction * 22.0, direction * 34.0, Color(0.98, 0.69, 0.29, 0.72), 2.0, true)
	if action_state == ActionState.RECOVER:
		draw_circle(Vector2.ZERO, 12.0 + sin(_age * 8.0) * 2.0, Color(1.0, 0.70, 0.28, 0.72), false, 3.0, true)


func _draw_bloomer(spawn_scale: float) -> void:
	for petal in 8:
		var angle := float(petal) * TAU / 8.0 + _age * (0.20 if petal % 2 == 0 else -0.16)
		var origin := Vector2.from_angle(angle) * 25.0 * spawn_scale
		var shape := _diamond(origin, angle, 23.0 * spawn_scale, 9.0 * spawn_scale)
		draw_colored_polygon(shape, Color(0.075, 0.045, 0.13).lerp(Color.WHITE, _flash * 0.64))
		draw_polyline(_closed(shape), Color(0.55, 0.34, 0.81, 0.64), 1.5, true)
	draw_circle(Vector2.ZERO, 14.0 * spawn_scale, Color(0.52, 0.22, 0.66).lerp(Color.WHITE, _flash))
	draw_circle(Vector2.ZERO, 4.2 * spawn_scale, Color(1.0, 0.70, 0.29))


func _draw_leech(spawn_scale: float) -> void:
	var rotation := global_position.direction_to(target_position).angle()
	var outer := _scaled_points(_rotated_points(rotation, [Vector2(42,0), Vector2(10,33), Vector2(-34,26), Vector2(-18,0), Vector2(-34,-26), Vector2(10,-33)]), spawn_scale)
	draw_colored_polygon(outer, Color(0.06, 0.025, 0.11).lerp(Color.WHITE, _flash * 0.68))
	draw_polyline(_closed(outer), Color(0.90, 0.23, 0.55, 0.76), 2.1, true)
	draw_circle(Vector2.from_angle(rotation) * 10.0, 7.0, Color(0.12, 0.75, 0.76))
	if global_position.distance_to(target_position) < 245.0:
		draw_dashed_line(Vector2.ZERO, to_local(target_position), Color(0.88, 0.25, 0.58, 0.22 + sin(_age * 9.0) * 0.08), 2.0, 12.0, true)


func _draw_mirror(spawn_scale: float) -> void:
	var rotation := global_position.direction_to(target_position).angle() + PI * 0.5
	var left := _scaled_points(_rotated_points(rotation, [Vector2(-4,-17), Vector2(-53,-38), Vector2(-37,11), Vector2(-8,28)]), spawn_scale)
	var right := _scaled_points(_rotated_points(rotation, [Vector2(4,-17), Vector2(53,-38), Vector2(37,11), Vector2(8,28)]), spawn_scale)
	draw_colored_polygon(left, Color(0.025, 0.10, 0.13).lerp(Color.WHITE, _flash * 0.64))
	draw_colored_polygon(right, Color(0.07, 0.035, 0.12).lerp(Color.WHITE, _flash * 0.64))
	draw_polyline(_closed(left), Color(0.30, 0.88, 0.86, 0.72), 2.0, true)
	draw_polyline(_closed(right), Color(0.94, 0.52, 0.42, 0.62), 2.0, true)
	draw_circle(Vector2.ZERO, 8.0 * spawn_scale, Color(1.0, 0.68, 0.30))
	if mirror_state == MirrorState.FOLD:
		var counter_radius := 138.0 + minf(24.0, float(stored_light) * 2.0)
		for ring in 3:
			var radius := counter_radius - ring * 13.0 + sin(_age * 5.0 + ring) * 3.0
			draw_arc(Vector2.ZERO, radius, -PI * 0.92 + ring, PI * 0.16 + ring, 64, Color(0.30, 0.88, 0.86, 0.58 - ring * 0.13), 3.0 - ring * 0.5, true)
			draw_circle(Vector2.ZERO, radius, Color(0.18, 0.78, 0.80, 0.018))
		for pip in mini(12, stored_light):
			var angle := float(pip) * TAU / float(maxi(1, mini(12, stored_light))) + _age * 0.8
			draw_circle(Vector2.from_angle(angle) * 110.0, 4.2, Color(1.0, 0.73, 0.30, 0.88))
	elif mirror_state == MirrorState.RELEASE:
		for ray in 8:
			var ray_angle := float(ray) * TAU / 8.0 + _age
			draw_line(Vector2.from_angle(ray_angle) * 32.0, Vector2.from_angle(ray_angle) * 76.0, Color(0.40, 0.94, 0.88, 0.38), 2.0, true)


func _draw_rewinder(spawn_scale: float) -> void:
	if _rewind_path.size() >= 2:
		var local_path := PackedVector2Array()
		for point in _rewind_path:
			local_path.append(to_local(point))
		draw_polyline(local_path, Color(0.38, 0.04, 0.22, 0.24 if rewind_state == RewindState.TELEGRAPH else 0.16), 15.0, true)
		draw_polyline(local_path, Color(1.0, 0.50, 0.25, 0.62 if rewind_state == RewindState.TELEGRAPH else 0.38), 2.2, true)
		var arrow_step := maxi(1, int(local_path.size() / 6))
		for arrow_index in range(local_path.size() - 1, 0, -arrow_step):
			var arrow_direction := local_path[arrow_index].direction_to(local_path[maxi(0, arrow_index - 1)])
			draw_line(local_path[arrow_index], local_path[arrow_index] + arrow_direction * 18.0, Color(1.0, 0.64, 0.28, 0.56), 3.0, true)
	for loop_index in 5:
		var angle := _age * (-1.4 if rewind_state == RewindState.REWIND else 0.46) + float(loop_index) * TAU / 5.0
		var center := Vector2.from_angle(angle) * 27.0 * spawn_scale
		var shape := _diamond(center, angle + PI * 0.5, 22.0 * spawn_scale, 7.0 * spawn_scale)
		draw_colored_polygon(shape, Color(0.07, 0.025, 0.10).lerp(Color.WHITE, _flash * 0.64))
		draw_polyline(_closed(shape), Color(0.94, 0.35, 0.48, 0.62), 1.5, true)
	draw_circle(Vector2.ZERO, 13.0 * spawn_scale, Color(0.96, 0.48, 0.25).lerp(Color.WHITE, _flash))
	draw_circle(Vector2.ZERO, 4.0 * spawn_scale, Color(1.0, 0.82, 0.46))
	if rewind_state == RewindState.TELEGRAPH:
		draw_arc(Vector2.ZERO, 54.0 + _state_remaining * 34.0, -PI, PI, 48, Color(1.0, 0.48, 0.24, 0.78), 3.0, true)


func _draw_sealed_charge(enemy_radius: float, remaining: float) -> void:
	var ratio := clampf(remaining / 1.05, 0.0, 1.0)
	var closing_radius := enemy_radius + 28.0 + ratio * 76.0
	draw_circle(Vector2.ZERO, enemy_radius + 17.0, Color(0.015, 0.008, 0.025, 0.36 * (1.0 - ratio)))
	draw_arc(Vector2.ZERO, closing_radius, 0.0, TAU, 72, Color(1.0, 0.43, 0.16, 0.82), 3.0, true)
	draw_arc(Vector2.ZERO, closing_radius - 9.0, _age * 1.8, _age * 1.8 + PI * 1.42, 48, Color(0.10, 0.02, 0.04, 0.92), 4.5, true)
	for nail_index in 6:
		var angle := float(nail_index) * TAU / 6.0 + _age * 0.18
		var nail_center := Vector2.from_angle(angle) * closing_radius
		var nail := _diamond(nail_center, angle + PI, 13.0, 4.2)
		draw_colored_polygon(nail, Color(0.035, 0.012, 0.025, 0.96))
		draw_polyline(_closed(nail), Color(1.0, 0.54, 0.18, 0.88), 1.7, true)


func _diamond(center: Vector2, angle: float, length: float, width: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle)
	var side := forward.orthogonal()
	return PackedVector2Array([center + forward * length, center + side * width, center - forward * length, center - side * width])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _rotated_points(angle: float, source: Array[Vector2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in source:
		result.append(point.rotated(angle))
	return result


func _scaled_points(points: PackedVector2Array, scale_factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * scale_factor)
	return result
