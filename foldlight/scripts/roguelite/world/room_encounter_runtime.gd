class_name FoldlightRoomEncounterRuntime
extends Node

signal combat_lock_changed(locked: bool)
signal wave_started(wave_number: int, total_waves: int)
signal spawn_telegraph_requested(entry: Dictionary, duration: float)
signal enemy_spawn_requested(entry: Dictionary)
signal encounter_cleared(performance: Dictionary)

enum State { IDLE, TELEGRAPHING, ACTIVE, INTERMISSION, CLEARED }

@export_range(0.25, 1.5, 0.05) var telegraph_duration: float = 0.7
@export_range(0.2, 2.0, 0.05) var intermission_duration: float = 0.85
@export_range(1, 6, 1) var reinforcement_threshold: int = 4

var state: State = State.IDLE
var active_enemy_count: int = 0
var defeated_enemy_count: int = 0
var elapsed: float = 0.0
var current_wave: int = -1

var _waves: Array[Array] = []
var _state_remaining: float = 0.0
var _encounter_id: StringName = &""


func configure(plan: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	reset()
	var plan_errors_variant: Variant = plan.get("errors", [])
	if plan_errors_variant is Array:
		for error_variant: Variant in plan_errors_variant:
			errors.append(String(error_variant))
	var entries_variant: Variant = plan.get("entries", [])
	if not entries_variant is Array or (entries_variant as Array).is_empty():
		errors.append("encounter plan needs at least one entry")
		return errors
	_encounter_id = StringName(plan.get("encounter_id", &""))
	var highest_wave := 0
	for entry_variant: Variant in entries_variant:
		if not entry_variant is Dictionary:
			errors.append("encounter entry must be a dictionary snapshot")
			continue
		var entry := entry_variant as Dictionary
		highest_wave = maxi(highest_wave, int(entry.get("wave", 0)))
	for _wave in highest_wave + 1:
		_waves.append([])
	for entry_variant: Variant in entries_variant:
		if not entry_variant is Dictionary:
			continue
		var entry := (entry_variant as Dictionary).duplicate(true)
		var wave_index := int(entry.get("wave", 0))
		if wave_index < 0 or wave_index >= _waves.size():
			errors.append("encounter entry has an invalid wave index")
			continue
		_waves[wave_index].append(entry)
	for wave_index in range(_waves.size() - 1, -1, -1):
		if _waves[wave_index].is_empty():
			_waves.remove_at(wave_index)
	if _waves.is_empty():
		errors.append("encounter plan has no populated waves")
	return errors


func begin() -> bool:
	if _waves.is_empty() or state != State.IDLE:
		return false
	elapsed = 0.0
	defeated_enemy_count = 0
	combat_lock_changed.emit(true)
	_begin_wave(0)
	return true


func advance_simulation(delta: float) -> void:
	if state in [State.IDLE, State.CLEARED]:
		return
	var safe_delta := maxf(0.0, delta)
	elapsed += safe_delta
	if state == State.TELEGRAPHING:
		_state_remaining -= safe_delta
		if _state_remaining <= 0.0:
			_spawn_current_wave()
	elif state == State.INTERMISSION:
		_state_remaining -= safe_delta
		if _state_remaining <= 0.0:
			_begin_wave(current_wave + 1)


func notify_enemy_defeated(count: int = 1) -> bool:
	if not state in [State.ACTIVE, State.TELEGRAPHING] or count <= 0:
		return false
	var removed := mini(count, active_enemy_count)
	active_enemy_count -= removed
	defeated_enemy_count += removed
	if state == State.TELEGRAPHING:
		return true
	if current_wave + 1 < _waves.size() and active_enemy_count <= reinforcement_threshold:
		_begin_wave(current_wave + 1)
	elif active_enemy_count <= 0:
		_finish_encounter()
	return true


func reset() -> void:
	state = State.IDLE
	active_enemy_count = 0
	defeated_enemy_count = 0
	elapsed = 0.0
	current_wave = -1
	_state_remaining = 0.0
	_encounter_id = &""
	_waves.clear()


func total_enemy_count() -> int:
	var total := 0
	for wave in _waves:
		total += wave.size()
	return total


func _begin_wave(wave_index: int) -> void:
	if wave_index < 0 or wave_index >= _waves.size():
		_finish_encounter()
		return
	current_wave = wave_index
	state = State.TELEGRAPHING
	_state_remaining = telegraph_duration
	wave_started.emit(current_wave + 1, _waves.size())
	for entry_variant: Variant in _waves[current_wave]:
		spawn_telegraph_requested.emit((entry_variant as Dictionary).duplicate(true), telegraph_duration)


func _spawn_current_wave() -> void:
	state = State.ACTIVE
	active_enemy_count += _waves[current_wave].size()
	for entry_variant: Variant in _waves[current_wave]:
		enemy_spawn_requested.emit((entry_variant as Dictionary).duplicate(true))
	if active_enemy_count <= 0:
		_finish_encounter()


func _finish_encounter() -> void:
	state = State.CLEARED
	active_enemy_count = 0
	combat_lock_changed.emit(false)
	encounter_cleared.emit({
		"encounter_id": _encounter_id,
		"duration": elapsed,
		"defeated": defeated_enemy_count,
		"waves": _waves.size(),
	})
