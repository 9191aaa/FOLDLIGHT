class_name FoldlightBossPhaseController
extends Node

signal phase_changed(phase_index: int)
signal telegraph_started(pattern_id: StringName, duration: float)
signal attack_ready(pattern_id: StringName, telegraph_duration: float)
signal stagger_started(duration: float)
signal stagger_ended

enum State { INTRO, TELEGRAPH, RECOVERY, STAGGERED, DEFEATED }

var state: State = State.INTRO
var phase_index: int = 0
var current_pattern: StringName = &""
var definition: FoldlightRogueBossDefinition

var _remaining: float = 1.1
var _attack_cursor: int = 0
var _last_telegraph_duration: float = 0.9


func configure(new_definition: FoldlightRogueBossDefinition) -> void:
	definition = new_definition
	state = State.INTRO
	phase_index = 0
	current_pattern = &""
	_remaining = 1.1
	_attack_cursor = 0
	_last_telegraph_duration = 0.9


func advance_simulation(delta: float, health_ratio: float) -> void:
	if definition == null or state == State.DEFEATED:
		return
	_update_phase(health_ratio)
	_remaining -= maxf(0.0, delta)
	if _remaining > 0.0:
		return
	match state:
		State.INTRO, State.RECOVERY:
			_begin_telegraph()
		State.TELEGRAPH:
			attack_ready.emit(current_pattern, _last_telegraph_duration)
			state = State.RECOVERY
			_remaining = maxf(0.42, 0.72 - float(phase_index) * 0.10)
		State.STAGGERED:
			stagger_ended.emit()
			state = State.RECOVERY
			_remaining = 0.72


func enter_stagger(duration: float) -> void:
	if state == State.DEFEATED:
		return
	state = State.STAGGERED
	_remaining = maxf(0.2, duration)
	stagger_started.emit(_remaining)


func mark_defeated() -> void:
	state = State.DEFEATED
	_remaining = 0.0


func get_state_snapshot() -> Dictionary:
	return {"state": state, "phase": phase_index, "pattern_id": current_pattern, "remaining": maxf(0.0, _remaining)}


func _update_phase(health_ratio: float) -> void:
	var next_phase := 0
	for threshold in definition.phase_thresholds:
		if health_ratio <= threshold:
			next_phase += 1
	if next_phase <= phase_index:
		return
	phase_index = mini(next_phase, definition.phase_thresholds.size())
	state = State.RECOVERY
	_remaining = 1.15
	phase_changed.emit(phase_index)


func _begin_telegraph() -> void:
	if definition.pattern_ids.is_empty():
		return
	# Bosses begin with both an ammunition opportunity and a movement check;
	# later phases add the arena/summon pattern instead of finally becoming live.
	var available_count := mini(definition.pattern_ids.size(), phase_index + 2)
	var pattern_index := (_attack_cursor + phase_index) % available_count
	current_pattern = definition.pattern_ids[pattern_index]
	_attack_cursor += 1
	_last_telegraph_duration = maxf(0.58, 0.94 - float(phase_index) * 0.10)
	state = State.TELEGRAPH
	_remaining = _last_telegraph_duration
	telegraph_started.emit(current_pattern, _last_telegraph_duration)
