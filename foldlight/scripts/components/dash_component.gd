class_name FoldlightDashComponent
extends Node

signal dash_started(direction: Vector2, duration: float)
signal dash_ended
signal readiness_changed(ready: bool)

@export_range(0.05, 0.5, 0.01) var dash_duration: float = 0.18
@export_range(300.0, 1800.0, 10.0) var dash_speed: float = 1050.0
@export_range(0.2, 5.0, 0.05) var base_cooldown: float = 2.0
@export_range(0.0, 0.4, 0.01) var invulnerability_duration: float = 0.16

var enabled: bool = false
var cooldown_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var duration_add: float = 0.0
var invulnerability_add: float = 0.0
var maximum_charges: int = 1
var charges: int = 1
var cooldown_remaining: float = 0.0
var dash_remaining: float = 0.0
var direction: Vector2 = Vector2.RIGHT


func configure(active: bool, new_cooldown_multiplier: float = 1.0) -> void:
	enabled = active
	cooldown_multiplier = clampf(new_cooldown_multiplier, 0.25, 2.0)
	reset()


func configure_build(stats: Dictionary) -> void:
	cooldown_multiplier = clampf(float(stats.get("dash_cooldown_multiplier", 1.0)), 0.25, 2.0)
	speed_multiplier = clampf(float(stats.get("dash_speed_multiplier", 1.0)), 0.6, 1.8)
	duration_add = clampf(float(stats.get("dash_duration_add", 0.0)), 0.0, 0.16)
	invulnerability_add = clampf(float(stats.get("dash_invulnerability_add", 0.0)), 0.0, 0.12)
	var previous_maximum := maximum_charges
	maximum_charges = clampi(1 + int(round(float(stats.get("dash_charge_add", 0.0)))), 1, 3)
	charges = clampi(charges + maximum_charges - previous_maximum, 0, maximum_charges)
	if charges <= 0 and cooldown_remaining <= 0.0:
		cooldown_remaining = base_cooldown * cooldown_multiplier


func request(requested_direction: Vector2) -> bool:
	if not enabled or charges <= 0 or dash_remaining > 0.0:
		return false
	direction = requested_direction.normalized() if not requested_direction.is_zero_approx() else Vector2.RIGHT
	var effective_duration := get_effective_duration()
	dash_remaining = effective_duration
	charges -= 1
	if charges < maximum_charges and cooldown_remaining <= 0.0:
		cooldown_remaining = base_cooldown * cooldown_multiplier
	dash_started.emit(direction, effective_duration)
	readiness_changed.emit(false)
	return true


func tick(delta: float) -> void:
	var was_dashing := dash_remaining > 0.0
	var was_ready := is_ready()
	dash_remaining = maxf(0.0, dash_remaining - delta)
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if enabled and charges < maximum_charges and cooldown_remaining <= 0.0:
		charges += 1
		if charges < maximum_charges:
			cooldown_remaining = base_cooldown * cooldown_multiplier
	if was_dashing and dash_remaining <= 0.0:
		dash_ended.emit()
	if was_ready != is_ready():
		readiness_changed.emit(is_ready())


func is_ready() -> bool:
	return enabled and charges > 0 and dash_remaining <= 0.0


func is_dashing() -> bool:
	return enabled and dash_remaining > 0.0


func get_velocity() -> Vector2:
	return direction * dash_speed * speed_multiplier if is_dashing() else Vector2.ZERO


func get_effective_duration() -> float:
	return dash_duration + duration_add


func get_effective_invulnerability() -> float:
	return invulnerability_duration + invulnerability_add


func get_cooldown_ratio() -> float:
	var duration := base_cooldown * cooldown_multiplier
	return clampf(cooldown_remaining / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func refund_cooldown(fraction: float) -> void:
	if charges >= maximum_charges:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - base_cooldown * cooldown_multiplier * clampf(fraction, 0.0, 1.0))
	if cooldown_remaining <= 0.0:
		charges += 1
		if charges < maximum_charges:
			cooldown_remaining = base_cooldown * cooldown_multiplier


func reset() -> void:
	cooldown_remaining = 0.0
	dash_remaining = 0.0
	direction = Vector2.RIGHT
	charges = maximum_charges
