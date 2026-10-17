class_name FoldlightBossPhaseController
extends Node

signal phase_changed(phase_index: int)
signal telegraph_started(pattern_id: StringName, duration: float)
signal attack_ready(pattern_id: StringName, telegraph_duration: float)
signal stagger_started(duration: float)
signal stagger_ended

enum State { INTRO, TELEGRAPH, RECOVERY, STAGGERED, DEFEATED, ATTACK }

var state: State = State.INTRO
var phase_index: int = 0
var current_pattern: StringName = &""
var definition: FoldlightRogueBossDefinition

const TELEGRAPH_SECONDS := [1.05, 1.0, 0.95]
const RECOVERY_SECONDS := [1.05, 0.95, 0.85]
const BLACK_GOLD_WARNING_BONUS := 0.22
const PHASE_TRANSITION_SECONDS := 1.5

var _remaining: float = 1.35
var _attack_cursor: int = 0
var _last_telegraph_duration: float = 0.9
var _pending_phase: int = -1
var _state_duration: float = 1.35
var _transition_remaining: float = 0.0


func configure(new_definition: FoldlightRogueBossDefinition, intro_delay: float = 0.0) -> void:
	definition = new_definition
	state = State.INTRO
	phase_index = 0
	current_pattern = &""
	_remaining = 1.35 + clampf(intro_delay, 0.0, 2.0)
	_attack_cursor = 0
	_last_telegraph_duration = 0.9
	_pending_phase = -1
	_state_duration = _remaining
	_transition_remaining = 0.0


func advance_simulation(delta: float, health_ratio: float) -> void:
	if definition == null or state == State.DEFEATED:
		return
	_update_phase(health_ratio)
	_remaining -= maxf(0.0, delta)
	_transition_remaining = maxf(0.0, _transition_remaining - maxf(0.0, delta))
	if _remaining > 0.0:
		return
	match state:
		State.INTRO, State.RECOVERY:
			_begin_telegraph()
		State.TELEGRAPH:
			var active_seconds := definition.get_active_seconds(current_pattern)
			# Enter the active state before notifying the actor; a synchronous
			# stagger/defeat callback must not be overwritten after the signal.
			state = State.ATTACK if active_seconds > 0.0 else State.RECOVERY
			_remaining = active_seconds if active_seconds > 0.0 else _recovery_seconds()
			_state_duration = _remaining
			attack_ready.emit(current_pattern, _last_telegraph_duration)
		State.ATTACK:
			state = State.RECOVERY
			_remaining = _recovery_seconds()
			_state_duration = _remaining
		State.STAGGERED:
			stagger_ended.emit()
			if _pending_phase > phase_index:
				_apply_phase(_pending_phase)
			else:
				state = State.RECOVERY
				_remaining = _recovery_seconds()
				_state_duration = _remaining


func enter_stagger(duration: float) -> void:
	if state == State.DEFEATED:
		return
	state = State.STAGGERED
	_remaining = maxf(0.2, duration)
	_state_duration = _remaining
	_transition_remaining = 0.0
	stagger_started.emit(_remaining)


func mark_defeated() -> void:
	state = State.DEFEATED
	_remaining = 0.0
	_transition_remaining = 0.0


func get_state_snapshot() -> Dictionary:
	return {"state": state, "phase": phase_index, "pattern_id": current_pattern, "remaining": maxf(0.0, _remaining), "pending_phase": _pending_phase}


func get_presentation_snapshot() -> Dictionary:
	# Read-only animation progress shares the combat clock. Rendering cannot
	# advance an attack, shorten its warning or consume the pattern RNG.
	return {
		"state": state,
		"progress": clampf(1.0 - _remaining / maxf(0.001, _state_duration), 0.0, 1.0),
		"transition_active": _transition_remaining > 0.0,
		"transition": clampf(1.0 - _transition_remaining / PHASE_TRANSITION_SECONDS, 0.0, 1.0),
	}


func _update_phase(health_ratio: float) -> void:
	var next_phase := 0
	for threshold in definition.phase_thresholds:
		if health_ratio <= threshold:
			next_phase += 1
	if next_phase <= phase_index:
		return
	if state == State.STAGGERED:
		# Crossing a health threshold is a reward for a good reflection. Finish
		# that earned damage window before changing arena rules or adding support.
		_pending_phase = maxi(_pending_phase, next_phase)
		return
	_apply_phase(next_phase)


func _apply_phase(next_phase: int) -> void:
	phase_index = mini(next_phase, definition.phase_thresholds.size())
	_pending_phase = -1
	state = State.RECOVERY
	_remaining = PHASE_TRANSITION_SECONDS
	_state_duration = _remaining
	_transition_remaining = _remaining
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
	_last_telegraph_duration = float(TELEGRAPH_SECONDS[mini(phase_index, 2)])
	if definition.telegraph_seconds > 0.0:
		_last_telegraph_duration = definition.telegraph_seconds
	if current_pattern in [&"black_lane", &"margin_cut", &"unreflectable_cut", &"shrinking_frame"]:
		_last_telegraph_duration += BLACK_GOLD_WARNING_BONUS
	state = State.TELEGRAPH
	_remaining = _last_telegraph_duration
	_state_duration = _remaining
	telegraph_started.emit(current_pattern, _last_telegraph_duration)


func _recovery_seconds() -> float:
	return definition.recovery_seconds if definition.recovery_seconds > 0.0 else float(RECOVERY_SECONDS[mini(phase_index, 2)])
