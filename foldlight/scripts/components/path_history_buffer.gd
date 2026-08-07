extends RefCounted

## Fixed-capacity history used by the Rewinder. Sampling mutates pre-sized
## packed arrays; a new snapshot is allocated only when an attack is locked.

var _capacity: int
var _sample_interval: float
var _points := PackedVector2Array()
var _times := PackedFloat32Array()
var _head: int = 0
var _count: int = 0
var _sample_clock: float = 0.0


func _init(capacity: int = 54, sample_interval: float = 0.08) -> void:
	_capacity = maxi(8, capacity)
	_sample_interval = maxf(0.02, sample_interval)
	_points.resize(_capacity)
	_times.resize(_capacity)


func reset(position_value: Vector2, time_value: float = 0.0) -> void:
	_head = 0
	_count = 0
	_sample_clock = 0.0
	_append(position_value, time_value)


func sample(delta: float, position_value: Vector2, time_value: float) -> void:
	_sample_clock -= delta
	if _sample_clock > 0.0:
		return
	_sample_clock += _sample_interval
	if _sample_clock <= -_sample_interval:
		_sample_clock = 0.0
	_append(position_value, time_value)


func snapshot_since(minimum_time: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for ordered_index in _count:
		var storage_index := _storage_index(ordered_index)
		if float(_times[storage_index]) >= minimum_time:
			result.append(_points[storage_index])
	return result


func point_count() -> int:
	return _count


func history_span() -> float:
	if _count < 2:
		return 0.0
	var oldest_index := _storage_index(0)
	var newest_index := _storage_index(_count - 1)
	return maxf(0.0, float(_times[newest_index]) - float(_times[oldest_index]))


func _append(position_value: Vector2, time_value: float) -> void:
	_points[_head] = position_value
	_times[_head] = time_value
	_head = (_head + 1) % _capacity
	_count = mini(_capacity, _count + 1)


func _storage_index(ordered_index: int) -> int:
	var oldest := posmod(_head - _count, _capacity)
	return (oldest + ordered_index) % _capacity
