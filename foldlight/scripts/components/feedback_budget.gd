class_name FoldlightFeedbackBudget
extends Node

signal impact_batch_requested(weight: float, count: int)
signal hit_stop_requested(duration: float)
signal shake_requested(strength: float)

@export_range(0.02, 0.2, 0.01) var aggregation_window: float = 0.06
@export_range(0.0, 0.12, 0.005) var maximum_hit_stop: float = 0.055
@export_range(0.1, 2.0, 0.05) var maximum_shake: float = 1.0

var _window_remaining: float = 0.0
var _pending_count: int = 0
var _pending_weight: float = 0.0
var _shake_energy: float = 0.0


func register_impact(weight: float = 0.2, critical: bool = false) -> void:
	var safe_weight := clampf(weight, 0.0, 1.0)
	_pending_count += 1
	_pending_weight = minf(1.0, _pending_weight + safe_weight * 0.22)
	if _window_remaining <= 0.0:
		_window_remaining = aggregation_window
	_shake_energy = minf(maximum_shake, _shake_energy + safe_weight * (0.32 if critical else 0.035))
	if critical:
		hit_stop_requested.emit(minf(maximum_hit_stop, 0.025 + safe_weight * 0.03))
		shake_requested.emit(_shake_energy)


func tick(delta: float) -> void:
	_window_remaining = maxf(0.0, _window_remaining - delta)
	_shake_energy = maxf(0.0, _shake_energy - delta * 2.8)
	if _pending_count > 0 and _window_remaining <= 0.0:
		impact_batch_requested.emit(_pending_weight, _pending_count)
		_pending_count = 0
		_pending_weight = 0.0


func reset() -> void:
	_window_remaining = 0.0
	_pending_count = 0
	_pending_weight = 0.0
	_shake_energy = 0.0

