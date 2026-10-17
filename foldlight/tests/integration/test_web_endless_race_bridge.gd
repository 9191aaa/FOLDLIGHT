extends SceneTree

## Transport is a test double, but movement, waves, defeat, rewards, equipment,
## and score time all come from the actual endless scene and shared combat.
class RecordingBridge extends "res://scripts/autoloads/web_race_bridge.gd":
	var messages: Array[Dictionary] = []
	var page_state: Dictionary = {"phase": "waiting", "mayStart": false}

	func _read_browser_boot() -> Dictionary:
		return {}

	func _read_page_state() -> Dictionary:
		return page_state

	func _send_browser(method: StringName, payload: Dictionary) -> void:
		messages.append({"method": method, "json": JSON.stringify(payload)})


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.profile["meta_upgrades"] = {"lantern_frame": 4, "wide_memory": 5, "deep_reservoir": 5, "return_edge": 5, "crease_rebuke": 1}
	var saved_profile := profile.profile.duplicate(true)
	_test_config_validation()
	var first := _create_fixture("first")
	var bridge: RecordingBridge = first.bridge
	var slice: FoldlightEndlessSliceRuntime = first.slice
	await _frames(8)
	_check(bridge.messages.size() == 2 and bridge.messages[0].method == &"ready" and bridge.last_report.status == "waiting", "loaded scene sends one ready handshake and an initial waiting report")
	_check(slice.controller.run_seed == 414141 and slice.controller.evolution.survival_seconds == 0.0 and not slice.combat_runtime.active and not slice.player.play_enabled, "same-seed battlefield is prepared with zero score and frozen combat before the page starts it")
	_check(slice.player.max_health == FoldlightPlayer.MAX_HEALTH and slice.player.get_capture_capacity() == 8 and is_equal_approx(slice.player.fold_radius_multiplier, 1.0), "maxed local profile cannot improve the race's default body")
	_check(slice.player.weapon_mount.definitions.size() == 1 and slice.player.weapon_mount.definitions[0].content_id == &"crease_lantern" and slice.player.active_item_slot.definition.content_id == &"paper_burst", "race starts with the common basic weapon and active item")
	_check(slice.presentation is FoldlightRoguePresentation, "friend race uses the same presentation as the main voyage")
	var first_spawn_positions := _enemy_positions(slice)
	bridge.accept_page_state({"phase": "running", "mayStart": false})
	_check(bridge.phase == &"waiting" and not slice.player.play_enabled, "a running room without this instance's start admission cannot start combat")
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	await _frames(12)
	_check(bridge.phase == &"running" and slice.controller.evolution.survival_seconds > 0.1 and slice.player.play_enabled, "admitted start activates real endless simulation")
	var reports_before := bridge.messages.size()
	bridge._process(0.49)
	_check(bridge.messages.size() == reports_before, "periodic reports wait for their one-second interval")
	bridge._process(0.52)
	_check(bridge.messages.size() == reports_before + 1 and bridge.last_report.survivalMs == slice.get_race_stats().survivalMs, "one-second report contains actual combat milliseconds rather than bridge wall time")
	var pause_event := InputEventAction.new()
	pause_event.action = &"pause_game"
	pause_event.pressed = true
	slice._unhandled_input(pause_event)
	_check(slice._modal_kind.is_empty() and slice.combat_runtime.active and slice.player.play_enabled, "competition Escape cannot pause combat for an advantage")
	var enemy := slice.combat_runtime.enemies[0]
	enemy.call("take_damage", 100000.0)
	bridge._process(1.01)
	_check(bridge.last_report.kills == 1 and slice.controller.defeated_total == 1, "real enemy death immediately contributes to the next report")
	var before_repeat := slice.controller.evolution.survival_seconds
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	_check(slice.controller.evolution.survival_seconds == before_repeat and slice.controller.defeated_total == 1, "repeated start polls cannot reset time or kills")
	_check(slice.start_slice(999).has("errors") and slice.controller.run_seed == 414141, "direct restart cannot obtain a second attempt in the same race")

	slice.controller._on_objective_completed({"title": "test", "completion_count": 1})
	var before_reward := slice.controller.evolution.survival_seconds
	await create_timer(1.75).timeout
	bridge._process(1.01)
	_check(slice._modal_kind == &"reward" and slice.controller.evolution.survival_seconds == before_reward and bridge.last_report.paused and bridge.last_report.pauseReason == "reward", "real reward selection stops score time while wall-clock heartbeats continue")
	slice.presentation._reward_buttons[0].pressed.emit()
	await create_timer(0.25).timeout
	await _frames(5)
	_check(slice._modal_kind.is_empty() and slice.controller.evolution.survival_seconds > before_reward, "a legal reward choice resumes the same combat clock")
	var before_death_reports := bridge.messages.size()
	slice.player.health = 1
	slice.player.invulnerability = 0.0
	slice.combat_runtime._try_hit_player(Vector2.RIGHT)
	_check(bridge.phase == &"terminal" and bridge.messages.size() == before_death_reports + 1 and bridge.last_report.status == "dead" and bridge.last_report.terminal, "real lethal combat damage immediately emits one terminal death report")
	_check(slice.presentation.screen_kind == &"result" and _result_actions_hidden(slice.presentation), "the shared race result hides retry and title actions while the webpage owns the outcome")
	var final_time := slice.controller.evolution.survival_seconds
	await _frames(6)
	bridge.accept_page_state({"phase": "running", "mayStart": true})
	bridge._process(5.0)
	_check(slice.controller.evolution.survival_seconds == final_time and bridge.messages.size() == before_death_reports + 1 and slice.start_slice().has("errors"), "dead race cannot restart or gain points from later polling")
	var durable_attempts := bridge._local_attempts.duplicate(true)
	_check(_valid_reports(bridge.messages), "reports carry immutable identity, rules, increasing sequence and nonnegative real counters")
	slice.queue_free()
	bridge.queue_free()
	await process_frame

	var refreshed := _create_fixture("first", durable_attempts)
	var refreshed_bridge: RecordingBridge = refreshed.bridge
	var refreshed_slice: FoldlightEndlessSliceRuntime = refreshed.slice
	_check(_enemy_positions(refreshed_slice) == first_spawn_positions, "independent same-seed browser instances receive the same initial wave positions")
	refreshed_bridge.accept_page_state({"phase": "running", "mayStart": true})
	_check(refreshed_bridge.last_report.status == "abandoned" and refreshed_bridge.last_report.reason == "attempt_already_started" and not refreshed_slice.player.play_enabled, "a durable started marker blocks a refreshed page from reopening the attempt")
	refreshed_slice.queue_free()
	refreshed_bridge.queue_free()
	await process_frame

	for ending in ["abandoned", "match_finished"]:
		var ending_fixture := _create_fixture(ending)
		var ending_bridge: RecordingBridge = ending_fixture.bridge
		var ending_slice: FoldlightEndlessSliceRuntime = ending_fixture.slice
		ending_bridge.accept_page_state({"phase": "running", "mayStart": true})
		await _frames(5)
		if ending == "match_finished":
			ending_slice.controller._on_objective_completed({"title": "test", "completion_count": 1})
			for transition_step in 6:
				ending_slice._advance_reward_completion(0.1)
		var score := ending_slice.controller.evolution.survival_seconds
		ending_bridge.accept_page_state({"phase": "finished", "reason": ending})
		await _frames(5)
		_check(ending_bridge.last_report.status == ("abandoned" if ending == "abandoned" else "finished") and ending_bridge.last_report.terminal and ending_slice.controller.evolution.survival_seconds == score and not ending_slice.combat_runtime.active, "page signal %s immediately freezes the real match and reports the corresponding terminal state" % ending)
		if ending == "match_finished":
			ending_slice.presentation._reward_buttons[0].pressed.emit()
			_check(not ending_slice.presentation._reward_input_guard.can_select() and ending_slice._modal_kind == &"race_finished" and not ending_slice.combat_runtime.active, "server completion during reward entry cancels shared card selection and cannot resume combat")
		ending_slice.queue_free()
		ending_bridge.queue_free()
		await process_frame
	_check(profile.profile == saved_profile, "race progression and results do not alter the existing profile")
	var autoload_bridge := root.get_node("WebRaceBridge")
	_check(autoload_bridge.configure_session(_config("autoload-entry")), "the actual autoload accepts one browser-style boot configuration")
	autoload_bridge._open_endless()
	await _frames(5)
	var booted_slice := current_scene as FoldlightEndlessSliceRuntime
	_check(booted_slice != null and booted_slice._race_prepared and booted_slice._modal_kind == &"race_waiting" and booted_slice.controller.run_seed == 414141 and booted_slice.controller.evolution.survival_seconds == 0.0, "autoload scene routing directly enters the same ready-but-frozen endless adapter")
	autoload_bridge.finish_local(&"abandoned", "test_cleanup")
	if booted_slice != null:
		booted_slice.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_WEB_ENDLESS_RACE_BRIDGE: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _test_config_validation() -> void:
	var bridge := RecordingBridge.new()
	root.add_child(bridge)
	_check(not bridge.configure_session({"roomId": "only-one-field"}) and bridge.phase == &"blocked", "incomplete multiplayer configuration fails closed instead of silently running solo")
	var invalid_seed := _config("invalid")
	invalid_seed.seed = 1.5
	_check(not bridge.configure_session(invalid_seed), "fractional seeds are rejected before creating a match")
	var old_rules := _config("old")
	old_rules.rulesVersion = "different_rules"
	_check(not bridge.configure_session(old_rules), "different competitive rule versions cannot silently share a score")
	_check(bridge.configure_session({}, true, 727) and bridge.is_web_session() and not bridge.is_race_session() and bridge.get_run_seed() == 727, "plain web endless remains a separate seeded solo mode")
	bridge.queue_free()


func _create_fixture(id: String, durable_attempts: Dictionary = {}) -> Dictionary:
	var bridge := RecordingBridge.new()
	root.add_child(bridge)
	bridge.configure_session(_config(id))
	bridge._local_attempts = durable_attempts.duplicate(true)
	bridge.set_process(false)
	var slice := load("res://scenes/endless/endless_survival_slice.tscn").instantiate() as FoldlightEndlessSliceRuntime
	root.add_child(slice)
	slice.prepare_web_race(bridge)
	return {"bridge": bridge, "slice": slice}


func _config(id: String) -> Dictionary:
	return {"roomId": id, "matchId": id, "playerId": "player-test", "instanceId": "instance-" + id, "seed": 414141, "rulesVersion": "endless_race_v6"}


func _enemy_positions(slice: FoldlightEndlessSliceRuntime) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for enemy in slice.combat_runtime.enemies:
		result.append(enemy.global_position)
	return result


func _result_actions_hidden(presentation: FoldlightRoguePresentation) -> bool:
	for button: Button in presentation._focus_groups[&"result"]:
		if button.is_visible_in_tree():
			return false
	return true


func _valid_reports(messages: Array[Dictionary]) -> bool:
	var sequence := 0
	var elapsed := 0
	for message in messages:
		if message.method != &"report":
			continue
		var payload: Dictionary = JSON.parse_string(message.json)
		if int(payload.protocol) != 1 or payload.roomId != "first" or payload.matchId != "first" or payload.playerId != "player-test" or payload.instanceId != "instance-first" or int(payload.seed) != 414141 or payload.rulesVersion != "endless_race_v6":
			return false
		if int(payload.seq) <= sequence or int(payload.survivalMs) < elapsed or int(payload.kills) < 0:
			return false
		sequence = int(payload.seq)
		elapsed = int(payload.survivalMs)
	return sequence > 1


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
