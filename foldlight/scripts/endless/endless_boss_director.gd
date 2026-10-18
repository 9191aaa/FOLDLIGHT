class_name FoldlightEndlessBossDirector
extends RefCounted
## An encounter is reserved before its warning and acknowledged only after all
## actors exist. Frame stalls, reward modals and level bursts cannot stack waves.

const FIRST_LEVEL := 8
const WARNING_SECONDS := 3.0
const MINIMUM_RECOVERY := 36.0
const TIMED_ENCOUNTER_INTERVAL := 150.0
const DEEP_RECOVERY := 6.0
const DEEP_ENCOUNTER_INTERVAL := 12.0
const MAX_BOSSES := 6
const BOSS_IDS: Array[StringName] = [
	&"reef_crown_battery", &"tide_loom_mother", &"inverted_archivist",
	&"torn_page_executioner", &"origami_judge", &"eclipse_twin_bells",
	&"mirror_moth",
]

var _seed: int = 0
var _state: StringName = &"waiting"
var _wave: int = 0
var _next_level: int = FIRST_LEVEL
var _warning: float = 0.0
var _last_clear: float = -10000.0
var _clock: float = 0.0
var _level: int = 1
var _plan: Array[StringName] = []
var _alive: Dictionary = {}


func reset(run_seed: int) -> void:
	_seed = run_seed
	_state = &"waiting"
	_wave = 0
	_next_level = FIRST_LEVEL
	_warning = 0.0
	_last_clear = -10000.0
	_clock = 0.0
	_level = 1
	_plan.clear()
	_alive.clear()


func advance(delta: float, level: int, combat_seconds: float) -> Dictionary:
	_level = maxi(level, 1)
	_clock = maxf(_clock, combat_seconds)
	if _state == &"waiting":
		var earned := _level >= _next_level
		var timed := _wave > 0 and _clock - _last_clear >= encounter_interval()
		if (earned or timed) and _clock - _last_clear >= recovery_interval():
			_wave += 1
			_plan.clear()
			var level_count := 1 + maxi(0, int((_level - FIRST_LEVEL) / 6))
			var time_count := 1 + maxi(0, int((_clock - 480.0) / 360.0))
			# The first encounter always teaches one boss. Later growth opens all
			# seven identities while retaining at most six living bosses. Five
			# is coprime to seven, so each reservation contains distinct bosses.
			var count := mini(MAX_BOSSES, mini(_wave, maxi(level_count, time_count)))
			for index in count:
				_plan.append(BOSS_IDS[posmod(_seed + (_wave - 1) * 5 + index * 5, BOSS_IDS.size())])
			_state = &"warning"
			_warning = WARNING_SECONDS
	elif _state == &"warning" and is_finite(delta) and delta > 0.0:
		_warning = maxf(0.0, _warning - minf(delta, 0.1))
		if _warning <= 0.00001:
			_state = &"ready"
	return get_snapshot()


func planned_boss_ids() -> Array[StringName]:
	return _plan.duplicate()


func retry_warning() -> void:
	if _state in [&"warning", &"ready"]:
		_state = &"warning"
		_warning = WARNING_SECONDS


func confirm_spawned(actor_ids: Array[StringName]) -> bool:
	if _state != &"ready" or actor_ids.size() != _plan.size() or actor_ids.is_empty():
		return false
	_alive.clear()
	for identity in actor_ids:
		if identity == &"" or _alive.has(identity):
			_alive.clear()
			return false
		_alive[identity] = true
	_state = &"active"
	var level_step := 4 if _level < 16 else (2 if _level < 24 else 1)
	_next_level = maxi(_next_level + level_step, _level + level_step)
	return true


## Returns true once, only for the final member of an acknowledged encounter.
func report_defeated(actor_id: StringName, combat_seconds: float) -> bool:
	if _state != &"active" or not _alive.has(actor_id):
		return false
	_alive.erase(actor_id)
	if not _alive.is_empty():
		return false
	_last_clear = maxf(_clock, combat_seconds)
	_state = &"waiting"
	_plan.clear()
	return true


func get_snapshot() -> Dictionary:
	return {
		"state": _state, "next_level": _next_level, "warning_remaining": _warning,
		"wave_index": _wave, "active_count": _alive.size(), "warning_count": _plan.size() if _state in [&"warning", &"ready"] else 0,
		"capacity": MAX_BOSSES, "difficulty_tier": maxi(int(_clock / 75.0), int((_level - 1) / 2)),
		"intensity_tier": intensity_tier(), "encounter_interval": encounter_interval(),
		"recovery_interval": recovery_interval(),
		"title": "多首领来袭" if _plan.size() > 1 else "首领来袭",
		"recovery_remaining": maxf(0.0, recovery_interval() - (_clock - _last_clear)),
	}


func encounter_interval() -> float:
	return maxf(DEEP_ENCOUNTER_INTERVAL, TIMED_ENCOUNTER_INTERVAL - _pressure_depth() * 7.0)


func recovery_interval() -> float:
	return maxf(DEEP_RECOVERY, MINIMUM_RECOVERY - _pressure_depth() * 1.5)


func _pressure_depth() -> float:
	return maxf(maxf(0.0, float(_level - FIRST_LEVEL)), maxf(0.0, _clock - 480.0) / 45.0)


func intensity_tier() -> int:
	return clampi(maxi(int((_level - FIRST_LEVEL) / 6), int((_clock - 480.0) / 360.0)), 0, 5)

