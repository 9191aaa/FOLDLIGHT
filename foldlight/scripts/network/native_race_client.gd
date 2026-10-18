class_name FoldlightNativeRaceClient
extends Node

## HTTP room transport shared by native clients and the standalone web build.
## Credentials live only in memory; only the user-selected entry URL is saved.
signal room_changed(snapshot: Dictionary)
signal error_changed(message: String)
signal match_prepared(config: Dictionary)
signal page_state_changed(state: Dictionary)
signal room_left
signal busy_changed(busy: bool)

const RULES_VERSION := "endless_race_v11"
const DEFAULT_ENDPOINT := "https://foldlight-paper-sea.briny-note-8241.chatgpt.site"
const SETTINGS_FILE := "user://race_connection.cfg"
const POLL_SECONDS := 1.0
const DISCONNECT_SECONDS := 30.0

var endpoint := DEFAULT_ENDPOINT
var display_name := "折翼旅人"
var room: Dictionary = {}
var instance_id := ""
var error_message := ""
var match_loaded := false
var persistence_enabled := true
var _token := ""
var _http: HTTPRequest
var _generation := 0
var _active_generation := 0
var _action := ""
var _busy := false
var _ready_pending := false
var _ready_confirmed := false
var _report: Dictionary = {}
var _sequence := 0
var _poll_left := POLL_SECONDS
var _server_now := 0.0
var _server_tick := 0
var _last_success_tick := 0
var _lost_match := false
var _preview_cookie := ""
var _preview_cookie_origin := ""
var _pending_request: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	_http.body_size_limit = 65536
	_http.max_redirects = 0 # Never forward the player bearer token to a redirect.
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if persistence_enabled:
		var settings := ConfigFile.new()
		if settings.load(SETTINGS_FILE) == OK:
			var saved := String(settings.get_value("room", "endpoint", DEFAULT_ENDPOINT))
			if endpoint_error(saved).is_empty(): endpoint = saved
			display_name = String(settings.get_value("room", "name", display_name)).left(16)
	if OS.has_feature("web"):
		var entry: Variant = JavaScriptBridge.eval("(() => { try { let u = new URL(location.href); if (parent !== window && parent.location.origin === location.origin) u = new URL(parent.location.href); return u.origin + u.search; } catch (_) { return location.origin + location.search; } })()")
		if entry is String and endpoint_error(entry).is_empty(): endpoint = entry


static func endpoint_error(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty() or clean.length() > 2048 or clean.contains("\n") or clean.contains("\r") or clean.contains(" "):
		return "请粘贴完整的联机入口链接。"
	var host_part := clean.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	if host_part.is_empty() or host_part.contains("@"):
		return "入口链接格式不正确。"
	if not clean.begins_with("https://"):
		if not (clean.begins_with("http://127.0.0.1:") or clean.begins_with("http://localhost:")):
			return "联机入口需要 HTTPS 安全连接。"
	return ""


func configure_endpoint(value: String, pilot_name: String = "") -> bool:
	if not room.is_empty() or _busy:
		_set_error("先离开当前房间，再更换入口。")
		return false
	var problem := endpoint_error(value)
	if not problem.is_empty():
		_set_error(problem)
		return false
	if endpoint != value.strip_edges():
		_preview_cookie = ""
		_preview_cookie_origin = ""
	endpoint = value.strip_edges()
	if not pilot_name.strip_edges().is_empty(): display_name = pilot_name.strip_edges().left(16)
	if persistence_enabled:
		var settings := ConfigFile.new()
		settings.set_value("room", "endpoint", endpoint)
		settings.set_value("room", "name", display_name)
		settings.save(SETTINGS_FILE)
	_set_error("")
	return true


func api_url(path: String) -> String:
	# The signed preview query must accompany EVERY API request, not only entry.
	var without_fragment := endpoint.get_slice("#", 0)
	var query_index := without_fragment.find("?")
	var query := without_fragment.substr(query_index) if query_index >= 0 else ""
	var base := without_fragment.substr(0, query_index) if query_index >= 0 else without_fragment
	var authority_end := base.find("/", base.find("://") + 3)
	if authority_end >= 0: base = base.substr(0, authority_end)
	# EdgeOne's signature is valid for the entry path only. Its bootstrap cookie
	# authenticates API paths; retaining the signature query there gives 401.
	if _has_preview_signature(): query = ""
	return base + path + query


func _has_preview_signature() -> bool:
	var query := endpoint.get_slice("?", 1).get_slice("#", 0)
	return query.contains("eo_token=") and query.contains("eo_time=")


func create_room(pilot_name: String) -> bool:
	if not _validate_entry(pilot_name): return false
	return _request("create", "/api/rooms", {"name": display_name, "rulesVersion": RULES_VERSION})


func join_room(code: String, pilot_name: String) -> bool:
	if not _validate_entry(pilot_name): return false
	code = code.strip_edges().to_upper()
	var pattern := RegEx.new()
	pattern.compile("^[A-HJ-NP-Z2-9]{7}$")
	if pattern.search(code) == null:
		_set_error("房间码为 7 位字母或数字，不含 I、O、0、1。")
		return false
	return _request("join", "/api/rooms/" + code, {"action": "join", "name": display_name, "rulesVersion": RULES_VERSION})


func _validate_entry(pilot_name: String) -> bool:
	if _busy or not room.is_empty(): return false
	var clean := pilot_name.strip_edges()
	if clean.is_empty() or clean.length() > 16:
		_set_error("请输入 1–16 字的称呼。")
		return false
	return configure_endpoint(endpoint, clean)


func prepare_match() -> bool:
	if room.is_empty() or match_loaded or _lost_match or String(room.get("phase", "")) != "waiting": return false
	match_loaded = true
	instance_id = _uuid()
	match_prepared.emit({"roomId": room.code, "matchId": room.code, "playerId": room.selfId, "instanceId": instance_id, "seed": room.seed, "rulesVersion": RULES_VERSION})
	return true


func runtime_ready(_payload: Dictionary = {}) -> void:
	if not match_loaded or room.is_empty(): return
	_ready_pending = true
	_poll_left = 0.0


func submit_report(payload: Dictionary) -> void:
	if room.is_empty() or not match_loaded: return
	if bool(_report.get("terminal", false)): return
	_report = payload.duplicate(true)
	if bool(payload.get("terminal", false)): _poll_left = 0.0


func _process(delta: float) -> void:
	if room.is_empty(): return
	# A settled room no longer polls; its final result must not time out later.
	if room.get("phase") == "finished":
		# Deliver the server terminal state before stopping transport. The bridge
		# ignores repeated terminal states, so a live winner stops exactly once.
		page_state_changed.emit(page_state())
		return
	if match_loaded and not _lost_match:
		page_state_changed.emit(page_state())
		if _last_success_tick > 0 and (Time.get_ticks_msec() - _last_success_tick) / 1000.0 >= DISCONNECT_SECONDS:
			_lost_match = true
			_set_error("连接已中断 30 秒，本局停止计分。请离开后重新建房。")
			page_state_changed.emit({"phase": "finished", "reason": "disconnected"})
	if _lost_match: return
	_poll_left -= delta
	if _poll_left > 0.0 or _busy: return
	_poll_left = POLL_SECONDS
	if _ready_pending and not _ready_confirmed:
		_request("ready", _room_path(), {"action": "ready", "rulesVersion": RULES_VERSION, "instanceId": instance_id})
	else:
		_sequence += 1
		var state := String(_report.get("status", "waiting"))
		state = "forfeit" if state == "abandoned" else ("reward" if _report.get("pauseReason", "") == "reward" else state)
		if state not in ["alive", "reward", "paused", "dead", "forfeit"]: state = "waiting"
		_request("heartbeat", _room_path(), {"action": "heartbeat", "rulesVersion": RULES_VERSION, "instanceId": instance_id, "seq": _sequence, "elapsed": float(_report.get("survivalMs", 0)) / 1000.0, "kills": int(_report.get("kills", 0)), "health": float(_report.get("health", 1)) / maxf(1.0, float(_report.get("maxHealth", 1))), "status": state})


func page_state() -> Dictionary:
	if _lost_match: return {"phase": "finished", "reason": "disconnected"}
	var phase := String(room.get("phase", "waiting"))
	for pilot: Dictionary in room.get("players", []):
		if pilot.get("id") == room.get("selfId") and pilot.get("status") in ["forfeit", "disconnected"]:
			return {"phase": "finished", "reason": String(pilot.status)}
	return {"phase": phase, "mayStart": phase == "running" and _ready_confirmed and server_time_ms() >= float(room.get("startAt", INF)), "reason": "match_finished"}


func server_time_ms() -> float:
	return _server_now + float(Time.get_ticks_msec() - _server_tick)


func countdown_seconds() -> int:
	return maxi(0, int(ceil((float(room.get("startAt", server_time_ms())) - server_time_ms()) / 1000.0))) if room.get("startAt") != null else 0


func leave_room() -> void:
	# Cancel the current generation before sending leave; a late heartbeat must
	# never resurrect a room or begin an abandoned match.
	_generation += 1
	_http.cancel_request()
	_busy = false
	if room.is_empty():
		_clear_room()
		return
	page_state_changed.emit({"phase": "finished", "reason": "abandoned"})
	_request("leave", _room_path(), {"action": "leave"})


func _request(action: String, path: String, payload: Dictionary) -> bool:
	if _busy: return false
	if not OS.has_feature("web") and _has_preview_signature() and _preview_cookie.is_empty():
		_pending_request = {"action": action, "path": path, "payload": payload.duplicate(true)}
		_active_generation = _generation
		_action = "preview_bootstrap"
		_busy = true
		busy_changed.emit(true)
		var bootstrap_error := _http.request(endpoint.get_slice("#", 0), PackedStringArray(["Accept: text/html"]), HTTPClient.METHOD_GET)
		if bootstrap_error != OK:
			_busy = false
			busy_changed.emit(false)
			_set_error("临时入口连接失败，请粘贴最新的完整试玩链接。")
			return false
		return true
	_active_generation = _generation
	_action = action
	_busy = true
	busy_changed.emit(true)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not _token.is_empty(): headers.append("Authorization: Bearer " + _token)
	if not OS.has_feature("web") and not _preview_cookie.is_empty() and _preview_cookie_origin == api_url(""):
		headers.append("Cookie: " + _preview_cookie)
	var error := _http.request(api_url(path), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_busy = false
		busy_changed.emit(false)
		_set_error("暂时无法连接联机入口，请检查网络或更换完整链接。")
		if action == "leave": _clear_room()
		return false
	return true


func _on_request_completed(result: int, status: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active_generation != _generation: return
	var completed_action := _action
	_busy = false
	busy_changed.emit(false)
	if completed_action == "preview_bootstrap":
		_complete_preview_bootstrap(result, status, response_headers)
		return
	if completed_action == "leave":
		_clear_room()
		return
	var value: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if result != HTTPRequest.RESULT_SUCCESS or status < 200 or status >= 300 or not value is Dictionary:
		var problem := "联机入口连接失败；临时链接可能已到期，请更换完整链接。"
		if value is Dictionary and value.get("error") is String: problem = String(value.error).left(240)
		_set_error(problem)
		if status in [401, 404, 409] and not room.is_empty():
			_lost_match = true
			page_state_changed.emit({"phase": "finished", "reason": "disconnected"})
		return
	if completed_action in ["create", "join"]:
		if not value.get("token") is String or not value.get("room") is Dictionary:
			_set_error("房间响应不完整，请重新尝试。")
			return
		_token = String(value.token)
		value = value.room
	if not _valid_snapshot(value):
		_set_error("房间响应不完整，请重新尝试。")
		return
	if completed_action == "ready": _ready_confirmed = true
	room = value.duplicate(true)
	_server_now = float(room.serverNow)
	_server_tick = Time.get_ticks_msec()
	_last_success_tick = _server_tick
	if not _lost_match: _set_error("")
	room_changed.emit(room.duplicate(true))


func _complete_preview_bootstrap(result: int, status: int, headers: PackedStringArray) -> void:
	var cookies: Dictionary = {}
	for header in headers:
		if not header.to_lower().begins_with("set-cookie:"): continue
		var pair := header.substr(header.find(":") + 1).strip_edges().get_slice(";", 0)
		var cookie_name := pair.get_slice("=", 0)
		if cookie_name in ["eo_token", "eo_time"] and not pair.contains("\r") and not pair.contains("\n"):
			cookies[cookie_name] = pair
	if result not in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] or status not in [200, 301, 302, 303, 307, 308] or cookies.size() != 2:
		_pending_request = {}
		_set_error("临时入口已过期或无法验证，请粘贴最新的完整试玩链接。")
		return
	_preview_cookie = String(cookies.eo_token) + "; " + String(cookies.eo_time)
	_preview_cookie_origin = api_url("")
	var pending := _pending_request
	_pending_request = {}
	if not pending.is_empty(): _request(String(pending.action), String(pending.path), pending.payload)


func _valid_snapshot(value: Dictionary) -> bool:
	if not value.get("code") is String or not value.get("selfId") is String or not value.get("players") is Array:
		return false
	if not String(value.get("phase", "")) in ["waiting", "running", "finished"] or not _finite_number(value.get("seed")) or not _finite_number(value.get("serverNow")):
		return false
	if float(value.seed) != floorf(float(value.seed)) or int(value.seed) < 1 or int(value.seed) > 2147483647:
		return false
	if value.get("startAt") != null and not _finite_number(value.startAt): return false
	if value.phase == "running" and value.get("startAt") == null: return false
	if value.players.size() < 1 or value.players.size() > 2: return false
	var found_self := false
	for pilot: Variant in value.players:
		if not pilot is Dictionary or not pilot.get("id") is String or not pilot.get("name") is String or not _finite_number(pilot.get("elapsed")):
			return false
		if pilot.id == value.selfId: found_self = true
	return found_self


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _clear_room() -> void:
	_generation += 1
	room = {}
	_token = ""
	instance_id = ""
	match_loaded = false
	_ready_pending = false
	_ready_confirmed = false
	_report = {}
	_sequence = 0
	_lost_match = false
	_poll_left = POLL_SECONDS
	_set_error("")
	room_left.emit()


func _room_path() -> String:
	return "/api/rooms/" + String(room.get("code", ""))


func _set_error(value: String) -> void:
	if error_message == value: return
	error_message = value
	error_changed.emit(value)


static func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var value := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [value.substr(0, 8), value.substr(8, 4), value.substr(12, 4), value.substr(16, 4), value.substr(20, 12)]
