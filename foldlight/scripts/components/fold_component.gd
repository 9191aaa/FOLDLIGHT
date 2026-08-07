class_name FoldlightFoldComponent
extends Node

signal cooldown_started(duration: float)
signal readiness_changed(ready: bool)

@export_range(0.0, 4.0, 0.05) var roguelite_cooldown: float = 1.5
@export_range(1, 32, 1) var roguelite_capacity: int = 8
@export_range(1, 32, 1) var classic_capacity: int = 16

var roguelite_enabled: bool = false
var cooldown_remaining: float = 0.0
var cooldown_multiplier: float = 1.0
var capacity_add: int = 0


func configure(for_roguelite: bool) -> void:
	roguelite_enabled = for_roguelite
	cooldown_remaining = 0.0
	readiness_changed.emit(true)


func configure_build(stats: Dictionary) -> void:
	cooldown_multiplier = clampf(float(stats.get("fold_cooldown_multiplier", 1.0)), 0.25, 2.0)
	capacity_add = clampi(int(round(float(stats.get("capture_capacity", 0.0)))), 0, 12)


func tick(delta: float) -> void:
	var was_ready := can_begin()
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if was_ready != can_begin():
		readiness_changed.emit(can_begin())


func can_begin() -> bool:
	return cooldown_remaining <= 0.0


func on_release() -> void:
	if not roguelite_enabled or roguelite_cooldown <= 0.0:
		return
	var effective_cooldown := roguelite_cooldown * cooldown_multiplier
	cooldown_remaining = effective_cooldown
	cooldown_started.emit(effective_cooldown)
	readiness_changed.emit(false)


func get_capacity() -> int:
	return roguelite_capacity + capacity_add if roguelite_enabled else classic_capacity


func reset() -> void:
	cooldown_remaining = 0.0
