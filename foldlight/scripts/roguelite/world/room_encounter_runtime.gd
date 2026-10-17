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
var reinforcement_interval: float = 0.0
var maximum_active_enemies: int = 0

var state: State = State.IDLE
var active_enemy_count: int = 0
var defeated_enemy_count: int = 0
var elapsed: float = 0.0
var current_wave: int = -1

var _waves: Array[Array] = []
var _state_remaining: float = 0.0
var _encounter_id: StringName = &""
var _wave_elapsed: float = 0.0
var _spawn_player: Node2D
var _spawn_bounds: Rect2
var _spawn_blockers: Array[Rect2] = []


func configure(plan: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	reset()
	reinforcement_interval = maxf(0.0, float(plan.get("reinforcement_interval", 0.0)))
	reinforcement_threshold = clampi(int(plan.get("reinforcement_threshold", 4)), 1, 6)
	# Only the main expedition opts into the 16-unit reservation cap. Legacy
	# plans keep their authored wave capacity and kill-only scheduling.
	maximum_active_enemies = clampi(int(plan.get("maximum_active_enemies", 0)), 0, 32)
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
		elif maximum_active_enemies > 0 and _waves[wave_index].size() > maximum_active_enemies:
			errors.append("encounter wave exceeds its active-unit limit")
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
	elif state == State.ACTIVE:
		_wave_elapsed += safe_delta
		_try_reinforce()


func notify_enemy_defeated(count: int = 1) -> bool:
	if not state in [State.ACTIVE, State.TELEGRAPHING] or count <= 0:
		return false
	var removed := mini(count, active_enemy_count)
	active_enemy_count -= removed
	defeated_enemy_count += removed
	if state == State.TELEGRAPHING:
		return true
	if current_wave + 1 < _waves.size():
		_try_reinforce()
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
	_wave_elapsed = 0.0
	_waves.clear()


func set_spawn_safety(player: Node2D, bounds: Rect2, blockers: Array[Rect2]) -> void:
	_spawn_player = player
	_spawn_bounds = bounds
	_spawn_blockers = blockers.duplicate()


func projected_enemy_count() -> int:
	var pending := _waves[current_wave].size() if state == State.TELEGRAPHING and current_wave >= 0 else 0
	return active_enemy_count + pending


func _try_reinforce() -> void:
	if state != State.ACTIVE or current_wave + 1 >= _waves.size():
		return
	var due := reinforcement_interval > 0.0 and _wave_elapsed >= reinforcement_interval
	if active_enemy_count > reinforcement_threshold and not due:
		return
	# This guard applies to kill-triggered and timed waves alike. Telegraphing
	# reserves the whole next wave; no second wave can be queued meanwhile.
	if maximum_active_enemies > 0 and active_enemy_count + _waves[current_wave + 1].size() > maximum_active_enemies:
		return
	_begin_wave(current_wave + 1)


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
	_relocate_close_spawns(_waves[current_wave])
	state = State.TELEGRAPHING
	_state_remaining = maxf(0.7, telegraph_duration)
	wave_started.emit(current_wave + 1, _waves.size())
	for entry_variant: Variant in _waves[current_wave]:
		spawn_telegraph_requested.emit((entry_variant as Dictionary).duplicate(true), _state_remaining)


func _spawn_current_wave() -> void:
	state = State.ACTIVE
	_wave_elapsed = 0.0
	active_enemy_count += _waves[current_wave].size()
	for entry_variant: Variant in _waves[current_wave]:
		enemy_spawn_requested.emit((entry_variant as Dictionary).duplicate(true))
	if active_enemy_count <= 0:
		if current_wave + 1 < _waves.size():
			_try_reinforce()
		else:
			_finish_encounter()


func _relocate_close_spawns(wave: Array) -> void:
	if not is_instance_valid(_spawn_player) or not _spawn_bounds.has_area():
		return
	var reserved: Array[Vector2] = []
	for entry: Dictionary in wave:
		reserved.append(Vector2(entry.get("spawn_position", Vector2.ZERO)))
	for index in wave.size():
		var entry: Dictionary = wave[index]
		var origin := Vector2(entry.get("spawn_position", Vector2.ZERO))
		if origin.distance_to(_spawn_player.global_position) >= 180.0:
			continue
		# Reposition before showing the warning. Landing always uses the warned
		# position, even if the player subsequently walks into that warning.
		for candidate_index in 48:
			var radius := 250.0 + float(candidate_index / 16) * 100.0
			var angle := float(candidate_index % 16) * TAU / 16.0
			var candidate := _spawn_player.global_position + Vector2.from_angle(angle) * radius
			if not _spawn_bounds.has_point(candidate):
				continue
			var safe := true
			for blocker in _spawn_blockers:
				if FoldlightEncounterDirector.distance_to_rect(candidate, blocker) < 100.0:
					safe = false
					break
			for other_index in reserved.size():
				if other_index != index and candidate.distance_to(reserved[other_index]) < 72.0:
					safe = false
					break
			if safe:
				entry["spawn_position"] = candidate
				reserved[index] = candidate
				break


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
