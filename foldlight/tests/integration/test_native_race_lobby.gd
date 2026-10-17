extends SceneTree

const Client = preload("res://scripts/network/native_race_client.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bridge := root.get_node("WebRaceBridge")
	var client: Node = bridge.native_client
	var lobby: Node = bridge.native_lobby
	client.persistence_enabled = false
	_check(client.configure_endpoint("https://test.edgeone.cool/play.html?eo_token=abcdef&eo_time=123#anchor"), "signed preview entry is accepted as an editable endpoint")
	_check(client.api_url("/api/rooms") == "https://test.edgeone.cool/api/rooms", "preview path signature is removed from API paths before cookie authentication")
	client._complete_preview_bootstrap(HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, 302, PackedStringArray(["Set-Cookie: eo_token=abcdef; Path=/; HttpOnly", "Set-Cookie: eo_time=123; Path=/", "Set-Cookie: unrelated=do-not-forward; Path=/"]))
	_check(client._preview_cookie == "eo_token=abcdef; eo_time=123" and client._preview_cookie_origin == "https://test.edgeone.cool", "bootstrap accepts only the two preview cookies for the selected origin")
	_check(client.configure_endpoint("https://other.example") and client._preview_cookie.is_empty(), "changing service origin discards all preview credentials")
	_check(not client.configure_endpoint("https://example.org\r\nCookie: x"), "header injection cannot enter endpoint state")
	bridge.show_native_lobby()
	await process_frame
	_check(bridge.is_lobby_open() and lobby._margin.visible, "one in-game lobby opens without replacing the title scene")
	_check(lobby._scroll.follow_focus and lobby._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "lobby follows keyboard focus with vertical scrolling only")
	var touch := root.get_node("TouchControls")
	touch._set_touch_mode(true)
	lobby._layout()
	await process_frame
	_check(lobby._create_button.custom_minimum_size.y >= 120 and lobby._endpoint.get_theme_font_size("font_size") >= 36, "mobile form uses large touch targets and readable editable text")
	_check(lobby._margin.get_theme_constant("margin_left") >= 64, "mobile form stays inside its landscape safe margin")
	lobby.set_process(false)
	lobby._keyboard_height = 520.0
	lobby._layout()
	await process_frame
	lobby._scroll.ensure_control_visible(lobby._code)
	await process_frame
	_check(lobby._scroll.get_global_rect().end.y <= root.get_visible_rect().size.y - 520.0, "soft keyboard shrinks the usable form instead of covering its inputs")
	_check(lobby._scroll.get_global_rect().encloses(lobby._code.get_global_rect()), "focused room code can scroll completely above the keyboard")
	lobby._keyboard_height = 0.0
	lobby._layout()
	lobby.set_process(true)
	lobby._request_back()
	_check(not bridge.is_lobby_open() and not lobby._root.visible, "closing an empty lobby restores single-player input")
	client.room = {"code": "ABC2345", "selfId": "self", "seed": 91, "phase": "waiting", "startAt": null, "serverNow": 1000, "players": [{"id": "self", "name": "我", "elapsed": 0, "status": "waiting", "ready": false, "connected": true}]}
	client.set_process(false)
	bridge.show_native_lobby()
	lobby._request_back()
	_check(lobby._confirming and not client.room.is_empty(), "leaving a room requires explicit confirmation")
	lobby._cancel_leave()
	_check(not lobby._confirming and not client.room.is_empty(), "cancelled leave retains the current room")
	client._lost_match = true
	_check(client.page_state().phase == "finished" and client.page_state().reason == "disconnected", "timed-out transport cannot admit combat from an old running snapshot")
	client._clear_room()
	client.room = {"code": "ABC2345", "selfId": "self", "seed": 91, "phase": "finished", "startAt": 500, "serverNow": 1000, "players": [{"id": "self", "name": "我", "elapsed": 0, "status": "alive", "ready": true, "connected": true}], "result": {"winner": "self", "draw": false}}
	client.match_loaded = true
	client._last_success_tick = 1
	client._set_error("")
	var final_states: Array[Dictionary] = []
	client.page_state_changed.connect(func(state: Dictionary) -> void: final_states.append(state.duplicate(true)))
	client._process(0.0)
	_check(final_states.size() == 1 and final_states[0].phase == "finished" and final_states[0].reason == "match_finished", "finished server snapshot reaches a live runtime before transport stops")
	# The timeout uses the monotonic clock, not delta. Wait beyond its real
	# positive-timestamp guard so this check would fail before the fix.
	await create_timer(maxf(0.01, 31.0 - float(Time.get_ticks_msec()) / 1000.0)).timeout
	client._process(31.0)
	_check(not client._lost_match and client.error_message.is_empty(), "finished room keeps its result after the last successful heartbeat ages out")
	_check(final_states.size() == 2 and final_states[1].reason == "match_finished", "repeated finished notifications retain the server result without becoming disconnects")
	client._clear_room()
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_NATIVE_RACE_LOBBY: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	if value: print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
