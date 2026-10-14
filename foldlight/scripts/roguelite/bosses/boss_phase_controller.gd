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

const TELEGRAPH_SECONDS := [1.05, 1.0, 0.95]
const RECOVERY_SECONDS := [1.05, 0.95, 0.85]
const BLACK_GOLD_WARNING_BONUS := 0.22
const PHASE_TRANSITION_SECONDS := 1.5

var _remaining: float = 1.35
var _attack_cursor: int = 0
var _last_telegraph_duration: float = 0.9
var _pending_phase: int = -1


func configure(new_definition: FoldlightRogueBossDefinition) -> void:
	definition = new_definition
	state = State.INTRO
	phase_index = 0
	current_pattern = &""
	_remaining = 1.35
	_attack_cursor = 0
	_last_telegraph_duration = 0.9
	_pending_phase = -1


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
			_remaining = float(RECOVERY_SECONDS[mini(phase_index, 2)])
		State.STAGGERED:
			stagger_ended.emit()
			if _pending_phase > phase_index:
				_apply_phase(_pending_phase)
			else:
				state = State.RECOVERY
				_remaining = float(RECOVERY_SECONDS[mini(phase_index, 2)])


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
	return {"state": state, "phase": phase_index, "pattern_id": current_pattern, "remaining": maxf(0.0, _remaining), "pending_phase": _pending_phase}


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
	if current_pattern in [&"black_lane", &"margin_cut", &"unreflectable_cut", &"shrinking_frame"]:
		_last_telegraph_duration += BLACK_GOLD_WARNING_BONUS
	state = State.TELEGRAPH
	_remaining = _last_telegraph_duration
	telegraph_started.emit(current_pattern, _last_telegraph_duration)
