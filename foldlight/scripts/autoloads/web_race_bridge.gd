class_name FoldlightWebRaceBridge
extends Node

## The embedding page owns rooms, authentication, HTTP and the server clock.
## This adapter only starts one real survival attempt and reports its counters.
signal ready_sent(payload: Dictionary)
signal report_sent(payload: Dictionary)
signal phase_changed(phase: StringName)

const PROTOCOL: int = 1
const RULES_VERSION: String = "endless_race_v8"
const ENDLESS_SCENE: String = "res://scenes/endless/endless_survival_slice.tscn"
const REPORT_INTERVAL: float = 1.0
const STATE_INTERVAL: float = 0.25

var phase: StringName = &"disabled"
var config: Dictionary = {}
var last_report: Dictionary = {}
var _web_session: bool = false
var _race_requested: bool = false
var _solo_seed: int = 20260728
var _runtime: Node
var _ready_sent: bool = false
var _sequence: int = 0
var _report_clock: float = 0.0
var _state_clock: float = 0.0
var _local_attempts: Dictionary = {}
var _boot_error: String = ""
var native_client: Node
var native_lobby: CanvasLayer
var _native_session := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var boot := _read_browser_boot()
	var race_value: Variant = boot.get("config", {})
	var race_config: Dictionary = race_value if race_value is Dictionary else {"invalid": true}
	configure_session(race_config, bool(boot.get("solo", false)), int(boot.get("seed", _solo_seed)))
	if name == "WebRaceBridge" and not _race_requested:
		native_client = preload("res://scripts/network/native_race_client.gd").new()
		add_child(native_client)
		native_client.match_prepared.connect(_start_native_match)
		native_client.page_state_changed.connect(accept_page_state)
		native_client.room_left.connect(_leave_native_match)
		ready_sent.connect(func(payload: Dictionary) -> void:
			if _native_session: native_client.runtime_ready(payload))
		report_sent.connect(func(payload: Dictionary) -> void:
			if _native_session: native_client.submit_report(payload))
		native_lobby = preload("res://scripts/network/native_race_lobby.gd").new()
		native_lobby.bridge = self
		native_lobby.client = native_client
		add_child(native_lobby)
	if _web_session:
		call_deferred("_open_endless")


func configure_session(race_config: Dictionary, solo_requested: bool = false, solo_seed: int = 20260728) -> bool:
	# Configuration is immutable once a runtime has attached. A web page cannot
	# reset counters by swapping its config or replaying a running state.
	if _runtime != null or _ready_sent or phase in [&"running", &"terminal"]:
		return false
	_race_requested = not race_config.is_empty()
	_web_session = _race_requested or solo_requested
	_solo_seed = clampi(solo_seed, 1, 2147483647)
	config = race_config.duplicate(true)
	_boot_error = _validate_config(config) if _race_requested else ""
	phase = &"blocked" if not _boot_error.is_empty() else (&"waiting" if _race_requested else &"disabled")
	return _boot_error.is_empty()


func is_web_session() -> bool:
	return _web_session


func is_race_session() -> bool:
	return _race_requested


func is_native_session() -> bool:
	return _native_session


func show_native_lobby() -> void:
	if native_lobby != null: native_lobby.open()


func is_lobby_open() -> bool:
	return native_lobby != null and native_lobby.captures_menu_input()


func request_native_leave() -> void:
	if _native_session and native_lobby != null: native_lobby.request_leave_confirmation()


func _start_native_match(value: Dictionary) -> void:
	if not configure_session(value):
		native_client._set_error("本局不能重新开始，请离开后创建新房间。")
		return
	_native_session = true
	call_deferred("_open_endless")


func _leave_native_match() -> void:
	if not _native_session: return
	_native_session = false
	_runtime = null
	_ready_sent = false
	_race_requested = false
	_web_session = false
	_sequence = 0
	_report_clock = 0.0
	_state_clock = 0.0
	config = {}
	last_report = {}
	_boot_error = ""
	phase = &"disabled"
	phase_changed.emit(phase)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


func get_run_seed() -> int:
	return int(config.get("seed", _solo_seed)) if _boot_error.is_empty() else _solo_seed


func bind_runtime(runtime: Node) -> bool:
	if not _race_requested or _runtime != null or _ready_sent:
		return false
	_runtime = runtime
	if not _boot_error.is_empty():
		finish_local(&"abandoned", _boot_error)
		return false
	_ready_sent = true
	var payload := _identity()
	ready_sent.emit(payload.duplicate(true))
	_send_browser(&"ready", payload)
	_emit_report(&"waiting")
	_report_clock = REPORT_INTERVAL
	_state_clock = 0.0
	return true


func _process(delta: float) -> void:
	if not _ready_sent or not is_instance_valid(_runtime) or phase == &"terminal":
		return
	_state_clock -= delta
	if _state_clock <= 0.0:
		_state_clock = STATE_INTERVAL
		if not _native_session: accept_page_state(_read_page_state())
	if phase == &"terminal":
		return
	_report_clock -= delta
	if _report_clock <= 0.0:
		_report_clock = REPORT_INTERVAL
		_emit_report(&"alive" if phase == &"running" else &"waiting")


func accept_page_state(state: Dictionary) -> void:
	if not _ready_sent or not is_instance_valid(_runtime) or phase == &"terminal":
		return
	var page_phase := String(state.get("phase", ""))
	if page_phase == "finished":
		var reason := String(state.get("reason", "match_finished"))
		finish_local(&"abandoned" if reason in ["abandoned", "forfeit", "disconnected"] else &"finished", reason)
	elif page_phase == "running" and phase == &"waiting" and state.get("mayStart", false) == true:
		if not _claim_local_attempt():
			finish_local(&"abandoned", "attempt_already_started")
			return
		phase = &"running"
		_runtime.call("begin_web_race")
		phase_changed.emit(phase)
		_emit_report(&"alive")
		_report_clock = REPORT_INTERVAL


func finish_local(status: StringName, reason: String) -> void:
	if phase == &"terminal" or not _race_requested:
		return
	if status not in [&"dead", &"abandoned", &"finished"]:
		status = &"abandoned"
	phase = &"terminal"
	if is_instance_valid(_runtime):
		_runtime.call("stop_web_race", reason)
	_emit_report(status, reason, true)
	phase_changed.emit(phase)


func _emit_report(status: StringName, reason: String = "", terminal: bool = false) -> void:
	var stats: Dictionary = _runtime.call("get_race_stats") if is_instance_valid(_runtime) else {}
	_sequence += 1
	var payload := _identity()
	payload.merge({
		"seq": _sequence,
		"status": String(status),
		"survivalMs": maxi(0, int(stats.get("survivalMs", 0))),
		"kills": maxi(0, int(stats.get("kills", 0))),
		"health": maxi(0, int(stats.get("health", 0))),
		"maxHealth": maxi(1, int(stats.get("maxHealth", 1))),
		"paused": bool(stats.get("paused", true)),
		"pauseReason": String(stats.get("pauseReason", "waiting")),
		"terminal": terminal,
		"reason": reason,
	})
	last_report = payload.duplicate(true)
	report_sent.emit(payload.duplicate(true))
	_send_browser(&"report", payload)


func _identity() -> Dictionary:
	var result := {"protocol": PROTOCOL, "rulesVersion": RULES_VERSION}
	for key in ["roomId", "matchId", "playerId", "instanceId", "seed"]:
		result[key] = config.get(key, "" if key != "seed" else 0)
	return result


func _validate_config(value: Dictionary) -> String:
	for key in ["roomId", "matchId", "playerId", "instanceId"]:
		if not value.get(key) is String or String(value[key]).strip_edges().is_empty() or String(value[key]).length() > 160:
			return "invalid_race_identity"
	if String(value.get("rulesVersion", "")) != RULES_VERSION:
		return "unsupported_rules"
	var seed_value: Variant = value.get("seed")
	if (not seed_value is int and not seed_value is float) or not is_finite(float(seed_value)) or float(seed_value) != floorf(float(seed_value)) or int(seed_value) < 1 or int(seed_value) > 2147483647:
		return "invalid_seed"
	return ""


func _claim_local_attempt() -> bool:
	var key := "foldlight.race.started:%s:%s" % [String(config["matchId"]), String(config["playerId"])]
	if _local_attempts.has(key):
		return false
	if OS.has_feature("web"):
		# Godot 4.6 eval returns JS booleans through a uint32_t Variant, so use
		# an explicit string result across this boundary instead of bool equality.
		var claimed: Variant = JavaScriptBridge.eval("(() => { try { const key = %s; if (sessionStorage.getItem(key)) return 'already_started'; sessionStorage.setItem(key, 'started'); return 'claimed'; } catch (_) { return 'claimed'; } })()" % JSON.stringify(key))
		if not claimed is String or claimed != "claimed":
			return false
	# The server must still reject a refreshed instanceId. Browser storage is a
	# second local guard, never the authority for admission or the final score.
	_local_attempts[key] = true
	return true


func _read_browser_boot() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var text: Variant = JavaScriptBridge.eval("(() => { const page = window.FoldlightRace; const query = new URLSearchParams(window.location.search); return JSON.stringify({config: page && page.config ? page.config : {}, solo: query.get('web_endless') === '1', seed: Number(query.get('seed')) || 20260728}); })()")
	return _parse_dictionary(text)


func _read_page_state() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var text: Variant = JavaScriptBridge.eval("(() => { try { const page = window.FoldlightRace; if (!page) return '{}'; const state = typeof page.getState === 'function' ? page.getState() : page.state; return typeof state === 'string' ? state : JSON.stringify(state || {}); } catch (_) { return '{}'; } })()")
	return _parse_dictionary(text)


func _parse_dictionary(text: Variant) -> Dictionary:
	if not text is String:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _send_browser(method: StringName, payload: Dictionary) -> void:
	if _native_session or not OS.has_feature("web") or method not in [&"ready", &"report"]:
		return
	# Encode the JSON payload as a JavaScript string literal; never interpolate
	# room or player identifiers into executable source.
	var argument := JSON.stringify(JSON.stringify(payload))
	JavaScriptBridge.eval("(() => { try { const page = window.FoldlightRace; if (page && typeof page.%s === 'function') page.%s(%s); } catch (_) {} })()" % [String(method), String(method), argument])


func _open_endless() -> void:
	if not _web_session:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == ENDLESS_SCENE:
		return
	var error := get_tree().change_scene_to_file(ENDLESS_SCENE)
	if error != OK:
		finish_local(&"abandoned", "scene_load_failed")
