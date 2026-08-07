class_name FoldlightTipQueue
extends Node

## Two independent, queue-driven teaching lanes. Enemy dossiers and effect
## counters may be visible together, while tips in the same lane never overwrite.

@export var default_duration: float = 5.6
@export var fade_in_duration: float = 0.24
@export var fade_out_duration: float = 0.52

const CHANNELS: Array[StringName] = [&"enemy", &"effect"]

var _queues: Dictionary = {
	&"enemy": [],
	&"effect": [],
}
var _active: Dictionary = {}
var _remaining: Dictionary = {}
var _seen: Dictionary = {}


func reset() -> void:
	for channel in CHANNELS:
		var queue: Array = _queues[channel]
		queue.clear()
	_active.clear()
	_remaining.clear()
	_seen.clear()


func tick(delta: float) -> void:
	for channel in CHANNELS:
		if _active.has(channel):
			var remaining := maxf(0.0, float(_remaining.get(channel, 0.0)) - delta)
			if remaining <= 0.0:
				_active.erase(channel)
				_remaining.erase(channel)
			else:
				_remaining[channel] = remaining
		if not _active.has(channel):
			_activate_next(channel)


func enqueue_once(channel: StringName, tip_id: StringName, data: Dictionary) -> bool:
	if not _queues.has(channel):
		push_warning("Unknown teaching tip channel: %s" % channel)
		return false
	var seen_key := StringName("%s:%s" % [channel, tip_id])
	if _seen.has(seen_key):
		return false
	_seen[seen_key] = true
	var entry := data.duplicate(true)
	entry["id"] = tip_id
	entry["channel"] = channel
	entry["duration"] = maxf(1.0, float(entry.get("duration", default_duration)))
	var queue: Array = _queues[channel]
	queue.append(entry)
	_activate_next(channel)
	return true


func get_snapshot(channel: StringName) -> Dictionary:
	if not _active.has(channel):
		return {}
	var entry: Dictionary = _active[channel]
	var remaining := float(_remaining.get(channel, 0.0))
	var duration := maxf(0.001, float(entry.get("duration", default_duration)))
	var elapsed := duration - remaining
	entry["alpha"] = clampf(minf(elapsed / maxf(0.001, fade_in_duration), remaining / maxf(0.001, fade_out_duration)), 0.0, 1.0)
	var queue: Array = _queues[channel]
	entry["queued"] = queue.size()
	return entry


func has_seen(channel: StringName, tip_id: StringName) -> bool:
	return _seen.has(StringName("%s:%s" % [channel, tip_id]))


func _activate_next(channel: StringName) -> void:
	if _active.has(channel):
		return
	var queue: Array = _queues[channel]
	if queue.is_empty():
		return
	var entry: Dictionary = queue.pop_front()
	_active[channel] = entry
	_remaining[channel] = float(entry.get("duration", default_duration))
