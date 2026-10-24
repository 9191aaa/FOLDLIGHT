extends SceneTree

## Actual renderer + shared scenes. Mobile mode is selected explicitly for
## desktop visual QA; this does not substitute for Android hardware testing.
## Set FOLDLIGHT_RACE_TEST_ENDPOINT to include real HTTP room/race captures.
const OUTPUT := "res://build/test-runtime/native-mobile-captures"
const Client = preload("res://scripts/network/native_race_client.gd")
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var profile := root.get_node("ProfileManager")
	profile.persistence_enabled = false
	profile.profile["roguelite"]["prologue_complete"] = true
	var touch := root.get_node("TouchControls")
	touch._set_touch_mode(true)
	change_scene_to_file("res://scenes/main.tscn")
	await _settle()
	await _save("01_mobile_title")
	var bridge := root.get_node("WebRaceBridge")
	var host: Node = bridge.native_client
	host.persistence_enabled = false
	var endpoint := OS.get_environment("FOLDLIGHT_RACE_TEST_ENDPOINT")
	if not endpoint.is_empty(): host.configure_endpoint(endpoint)
	bridge.show_native_lobby()
	await _save("02_mobile_lobby_top")
	bridge.native_lobby._scroll.scroll_vertical = 10000
	await _save("03_mobile_lobby_bottom")
	bridge.native_lobby._request_back()
	change_scene_to_file("res://scenes/endless/endless_survival_slice.tscn")
	await _settle()
	var solo: Node = current_scene
	solo.player.set_debug_invincible(true)
	await create_timer(1.0).timeout
	await _save("04_mobile_solo_hud")
	solo._pause_game()
	await _save("05_mobile_solo_pause")
	solo._resume_game()
	solo.controller._on_objective_completed({"completion_count": 1, "title": "潮汐驻守"})
	await _save("06_mobile_solo_reward")
	solo._return_to_title()
	await _settle()
	if not endpoint.is_empty():
		var guest := Client.new()
		guest.persistence_enabled = false
		root.add_child(guest)
		guest.configure_endpoint(endpoint)
		bridge.show_native_lobby()
		host.create_room("纸海旅人")
		if await _until(func() -> bool: return not host.room.is_empty(), 18.0):
			guest.join_room(String(host.room.code), "远方的朋友")
			if await _until(func() -> bool: return not guest.room.is_empty() and host.room.players.size() == 2, 18.0):
				await _save("07_mobile_live_room")
				host.prepare_match()
				guest.prepare_match()
				guest.runtime_ready()
				if await _until(func() -> bool: return bridge.phase == &"running", 18.0):
					var race: Node = current_scene
					race.player.set_debug_invincible(true)
					guest.submit_report({"status": "alive", "survivalMs": 0, "health": 6, "maxHealth": 6})
					await _save("08_mobile_live_race_hud")
					race.controller._on_objective_completed({"completion_count": 1, "title": "潮汐驻守"})
					await _save("09_mobile_live_race_reward")
					bridge.request_native_leave()
					await _save("10_mobile_race_leave_confirmation")
				else: _fail("Live HTTP countdown did not admit race")
			else: _fail("Live HTTP join failed")
		else: _fail("Live HTTP create failed")
		guest.leave_room()
		host.leave_room()
		await _until(func() -> bool: return host.room.is_empty() and guest.room.is_empty(), 15.0)
		guest.queue_free()
	root.get_node("AudioDirector").shutdown()
	print("FOLDLIGHT_NATIVE_MOBILE_CAPTURE: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)

func _settle() -> void:
	for index in 5: await process_frame

func _save(label: String) -> void:
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUTPUT).path_join(label + ".png")
	if root.get_texture().get_image().save_png(path) != OK: _fail("Capture failed: " + label)
	else: print("CAPTURED " + label)

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false

func _fail(message: String) -> void:
	_failures += 1
	push_error(message)
