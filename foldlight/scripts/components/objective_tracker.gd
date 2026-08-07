class_name FoldlightObjectiveTracker
extends Node

signal progress_changed(snapshot: Dictionary)
signal objective_completed(snapshot: Dictionary)
signal objective_failed(snapshot: Dictionary)

enum ObjectiveState { PENDING, ACTIVE, SUCCESS, FAILURE }

var objective_id: StringName = &"survive"
var label: String = ""
var target: float = 1.0
var progress: float = 0.0
var state: ObjectiveState = ObjectiveState.PENDING
var elapsed: float = 0.0
var duration: float = 1.0
var _large_releases: int = 0
var _kill_chain: int = 0
var _last_snapshot_key: String = ""


func begin(id: StringName, authored_target: int, authored_label: String, tide_duration: float) -> void:
	objective_id = id
	label = authored_label
	target = maxf(1.0, float(authored_target))
	progress = 0.0
	state = ObjectiveState.ACTIVE
	elapsed = 0.0
	duration = maxf(1.0, tide_duration)
	_large_releases = 0
	_kill_chain = 0
	_last_snapshot_key = ""
	_emit_progress(true)


func reset() -> void:
	objective_id = &"survive"
	label = ""
	target = 1.0
	progress = 0.0
	state = ObjectiveState.PENDING
	elapsed = 0.0
	duration = 1.0
	_large_releases = 0
	_kill_chain = 0
	_last_snapshot_key = ""


func tick(delta: float) -> void:
	if state != ObjectiveState.ACTIVE:
		return
	elapsed += maxf(0.0, delta)
	if objective_id == &"survive":
		progress = clampf(elapsed / duration, 0.0, 1.0)
	_emit_progress()


func report(event_id: StringName, amount: float = 1.0, payload: Dictionary = {}) -> void:
	if state != ObjectiveState.ACTIVE:
		return
	match objective_id:
		&"return_quota":
			if event_id == &"return_hit":
				_add_progress(amount)
		&"beacon_charge":
			if event_id == &"beacon_charge" or (event_id == &"return_hit" and bool(payload.get("near_anchor", false))):
				_add_progress(amount)
		&"cleanse":
			if event_id == &"cleanse" or (event_id == &"large_release" and int(payload.get("volley_size", 0)) >= 10):
				_add_progress(amount)
		&"escort":
			if event_id == &"escort_tick" or event_id == &"escort_repair":
				_add_progress(amount)
		&"ram_relay":
			if event_id == &"ram_relay":
				_add_progress(amount)
		&"pursuit":
			if event_id == &"courier_destroyed":
				_add_progress(amount)
		&"mastery":
			_report_mastery(event_id, amount, payload)
		_: pass


func settle_at_tide_end() -> bool:
	if state == ObjectiveState.SUCCESS:
		return true
	if state != ObjectiveState.ACTIVE:
		return false
	if objective_id == &"survive":
		progress = target
		_complete()
		return true
	state = ObjectiveState.FAILURE
	_emit_progress(true)
	objective_failed.emit(snapshot())
	return false


func force_complete() -> void:
	if state != ObjectiveState.ACTIVE:
		return
	progress = target
	_complete()


func snapshot() -> Dictionary:
	return {
		"id": objective_id,
		"label": label,
		"current": progress,
		"target": target,
		"ratio": clampf(progress / target, 0.0, 1.0),
		"state": int(state),
		"state_name": _state_name(),
	}


func _report_mastery(event_id: StringName, amount: float, payload: Dictionary) -> void:
	if event_id == &"large_release":
		var volley_size := int(payload.get("volley_size", 0))
		if volley_size >= int(payload.get("required_volley", 12)):
			_large_releases += 1
			_add_progress(1.0)
	elif event_id == &"return_kill":
		_kill_chain += int(amount)
		if _kill_chain >= int(payload.get("required_chain", 5)):
			_kill_chain = 0
			_add_progress(1.0)
	elif event_id == &"cleanse":
		_add_progress(amount)
	elif event_id == &"mastery_step":
		_add_progress(amount)


func _add_progress(amount: float) -> void:
	progress = minf(target, progress + maxf(0.0, amount))
	if progress >= target:
		_complete()
	else:
		_emit_progress()


func _complete() -> void:
	if state != ObjectiveState.ACTIVE:
		return
	state = ObjectiveState.SUCCESS
	_emit_progress(true)
	objective_completed.emit(snapshot())


func _emit_progress(force: bool = false) -> void:
	var snap := snapshot()
	var key := "%s:%d:%d" % [objective_id, int(round(progress)), int(state)]
	if force or key != _last_snapshot_key:
		_last_snapshot_key = key
		progress_changed.emit(snap)


func _state_name() -> StringName:
	match state:
		ObjectiveState.PENDING: return &"pending"
		ObjectiveState.ACTIVE: return &"active"
		ObjectiveState.SUCCESS: return &"success"
		ObjectiveState.FAILURE: return &"failure"
	return &"pending"
