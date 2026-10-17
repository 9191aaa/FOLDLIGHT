class_name FoldlightEndlessZoneExposure
extends RefCounted

## Receives only effective combat time: UI pauses never consume evacuation time.
var exposure_seconds: float = 0.0
var _next_hit: float = 2.0
var grace_seconds: float = 2.0
var interval_seconds: float = 2.0


func reset(grace: float = 2.0, interval: float = 2.0) -> void:
	grace_seconds = maxf(0.1, grace)
	interval_seconds = maxf(0.1, interval)
	exposure_seconds = 0.0
	_next_hit = grace_seconds


func advance(delta: float, inside_closed_zone: bool) -> int:
	if delta <= 0.0:
		return 0
	if not inside_closed_zone:
		exposure_seconds = 0.0
		_next_hit = grace_seconds
		return 0
	exposure_seconds += delta
	var hits := 0
	while exposure_seconds + 0.00001 >= _next_hit:
		hits += 1
		_next_hit += interval_seconds
	return hits


func seconds_until_damage() -> float:
	return maxf(0.0, _next_hit - exposure_seconds)
