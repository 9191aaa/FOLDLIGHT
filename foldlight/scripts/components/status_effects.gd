class_name FoldlightStatusEffects
extends Node

## Player-owned negative status component. The player remains authoritative for
## movement/focus; this component only owns timers, multipliers and cleanse rules.

signal status_applied(status_id: StringName, was_new: bool)
signal status_cleared(status_id: StringName)

const STATUS_DATA: Dictionary = {
	&"wet_ink": {
		"title": "湿墨",
		"detail": "折息恢复 -45%",
		"counter": "返还 6 光洗净",
		"color": Color(0.30, 0.78, 0.88),
	},
	&"bound_crease": {
		"title": "缚折",
		"detail": "移动速度 -30%",
		"counter": "返还 3 光挣脱",
		"color": Color(0.94, 0.42, 0.56),
	},
	&"veiled_fold": {
		"title": "墨覆",
		"detail": "折域半径 -28%",
		"counter": "蓄满返还洗去",
		"color": Color(0.62, 0.42, 0.90),
	},
	&"sunlit": {
		"title": "日照",
		"detail": "移动 +18% · 折息恢复 +60%",
		"counter": "离开日纹后短暂保留",
		"color": Color(1.0, 0.72, 0.28),
	},
}

var _timers: Dictionary = {}
var slow_severity_multiplier: float = 1.0


func tick(delta: float) -> void:
	for status_id: StringName in _timers.keys():
		var remaining := maxf(0.0, float(_timers[status_id]) - delta)
		if remaining <= 0.0:
			_clear_status(status_id)
		else:
			_timers[status_id] = remaining


func apply_status(status_id: StringName, duration: float) -> bool:
	if not STATUS_DATA.has(status_id) or duration <= 0.0:
		return false
	var was_new := not _timers.has(status_id)
	_timers[status_id] = maxf(float(_timers.get(status_id, 0.0)), duration)
	status_applied.emit(status_id, was_new)
	return was_new


func clear_all() -> void:
	var active_ids := _timers.keys()
	_timers.clear()
	for status_id: StringName in active_ids:
		status_cleared.emit(status_id)


func cleanse_from_release(captured_count: int, charge_ratio: float) -> Array[StringName]:
	var cleared: Array[StringName] = []
	if captured_count >= 6 and _timers.has(&"wet_ink"):
		cleared.append(&"wet_ink")
	if captured_count >= 3 and _timers.has(&"bound_crease"):
		cleared.append(&"bound_crease")
	if charge_ratio >= 0.92 and _timers.has(&"veiled_fold"):
		cleared.append(&"veiled_fold")
	for status_id in cleared:
		_clear_status(status_id)
	return cleared


func has_status(status_id: StringName) -> bool:
	return _timers.has(status_id)


func get_move_multiplier() -> float:
	var multiplier := lerpf(1.0, 0.70, clampf(slow_severity_multiplier, 0.0, 1.0)) if _timers.has(&"bound_crease") else 1.0
	if _timers.has(&"sunlit"):
		multiplier *= 1.18
	return multiplier


func get_focus_regen_multiplier() -> float:
	var multiplier := 0.55 if _timers.has(&"wet_ink") else 1.0
	if _timers.has(&"sunlit"):
		multiplier *= 1.6
	return multiplier


func get_fold_radius_multiplier() -> float:
	return 0.72 if _timers.has(&"veiled_fold") else 1.0


func get_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for status_id: StringName in STATUS_DATA.keys():
		if not _timers.has(status_id):
			continue
		var data: Dictionary = STATUS_DATA[status_id]
		snapshots.append({
			"id": status_id,
			"title": data["title"],
			"detail": data["detail"],
			"counter": data["counter"],
			"color": data["color"],
			"remaining": float(_timers[status_id]),
		})
	return snapshots


func _clear_status(status_id: StringName) -> void:
	if not _timers.erase(status_id):
		return
	status_cleared.emit(status_id)
