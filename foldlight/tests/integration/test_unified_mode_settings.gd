extends SceneTree

## Real scene replacements and native GUI input prove both current modes share
## one menu/settings contract, while modal time remains outside survival score.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	# This suite writes the real settings path only in the runner's isolated data.
	var isolated := OS.get_environment("APPDATA").replace("\\", "/").contains("/build/")
	_check(isolated, "settings persistence regression uses isolated application data")
	if not isolated:
		quit(1)
		return
	profile.persistence_enabled = true
	var original_settings := profile.settings.duplicate(true)
	profile.profile["roguelite"]["prologue_complete"] = true
	_check(change_scene_to_file("res://scenes/main.tscn") == OK, "the voyage opens as the actual SceneTree scene")
	await _settle()
	var game := current_scene as FoldlightGame
	_check(game != null, "the thin application shell owns the voyage")
	if game == null:
		quit(1)
		return
	var session := game.rogue_session
	session.persist_profile = false
	var ui := session.presentation
	_check(game.get_node_or_null("HUD") == null and game.get_node_or_null("ChallengeDirector") == null and not game.has_method("activate_classic_campaign"), "retired story and old challenge cannot run behind the shared title")
	var story_entry := false
	for button: Button in ui._title_screen.focus_buttons:
		story_entry = story_entry or button.text.contains("故事") or button.text.contains("战役")
	_check(not story_entry, "the title exposes current modes without a hidden story action")
	ui._title_primary.pressed.emit()
	await _settle()
	while session._mechanic_intro_active:
		session._on_mechanic_card_dismissed(ui._mechanic_intro_content_id)
	session.player.set_debug_invincible(true)
	_check(session.mode == FoldlightRogueSessionController.SessionMode.RUN and ui.screen_kind == &"hud", "the primary title action enters live voyage combat")
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui.screen_kind == &"pause" and not session.player.play_enabled, "keyboard Escape pauses the voyage through real input")
	_key(KEY_S)
	_check(root.gui_get_focus_owner() == ui._focus_groups[&"pause"][1], "WASD menu navigation reaches Settings once")
	_joy(JOY_BUTTON_A)
	await _settle()
	_check(ui.screen_kind == &"settings", "gamepad confirmation opens the same settings panel")
	_key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == ui._settings_buttons[1], "arrow navigation moves once to music volume")
	var old_music := float(profile.get_setting(&"music_volume"))
	_key(KEY_LEFT)
	var selected_music := float(profile.get_setting(&"music_volume"))
	_check(selected_music < old_music and ui._settings_buttons[1].text.contains("%"), "settings input changes the real music setting and visible value")
	var saved := ConfigFile.new()
	_check(saved.load(profile.SETTINGS_PATH) == OK and is_equal_approx(float(saved.get_value("settings", "music_volume", -1.0)), selected_music), "the shared settings action persists music volume to disk")
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui.screen_kind == &"pause" and not session.player.play_enabled, "Escape from voyage settings returns to pause before combat")
	(ui._focus_groups[&"pause"][0] as Button).pressed.emit()
	_check(ui.screen_kind == &"hud" and session.player.play_enabled, "Continue resumes the same voyage after settings")
	game.return_to_main_menu()
	await _settle()
	var old_game: WeakRef = weakref(game)
	var endless_button: Button
	for button: Button in ui._title_screen.focus_buttons:
		if button.name == "EndlessButton":
			endless_button = button
	_check(endless_button != null, "the retained endless mode has a real title action")
	if endless_button == null:
		quit(1)
		return
	endless_button.pressed.emit()
	await _settle()
	var slice := current_scene as FoldlightEndlessSliceRuntime
	_check(slice != null and old_game.get_ref() == null, "entering endless replaces and frees the previous mode")
	if slice == null:
		quit(1)
		return
	ui = slice.presentation
	slice.player.set_debug_invincible(true)
	_check(ui.scene_file_path == "res://scenes/roguelite/ui/rogue_presentation.tscn" and ui.screen_kind == &"hud", "endless instantiates the exact shared presentation scene")
	_check(not ui._hud_objective.text.is_empty() and ui._hud_health.text.contains("/"), "endless retains objective and health information in the common HUD")
	_joy(JOY_BUTTON_START)
	await _settle()
	_check(slice._modal_kind == &"pause" and ui.screen_kind == &"pause", "gamepad Start opens the common pause menu in endless")
	_key(KEY_S)
	_key(KEY_ENTER)
	await _settle()
	_check(slice._modal_kind == &"settings" and ui.screen_kind == &"settings", "endless pause provides the same Settings action")
	_check(is_equal_approx(float(profile.get_setting(&"music_volume")), selected_music), "scene replacement preserves the voyage's audio setting")
	var before := slice.controller.evolution.survival_seconds
	var position := slice.player.global_position
	slice.player.dash_component.cooldown_remaining = 1.4
	slice.player.fold_component.cooldown_remaining = 1.2
	for frame in 12:
		await physics_frame
	_check(is_equal_approx(slice.controller.evolution.survival_seconds, before) and slice.player.global_position == position, "settings does not advance endless survival time or movement")
	_check(is_equal_approx(slice.player.dash_component.cooldown_remaining, 1.4) and is_equal_approx(slice.player.fold_component.cooldown_remaining, 1.2), "settings cannot recharge dash or Fold behind the menu")
	ui._settings_buttons[5].grab_focus()
	var old_contrast := bool(profile.get_setting(&"high_contrast"))
	_key(KEY_ENTER)
	_check(bool(profile.get_setting(&"high_contrast")) != old_contrast, "endless uses the common accessibility setting action")
	_key(KEY_ESCAPE)
	await _settle()
	_check(slice._modal_kind == &"pause" and not slice.player.play_enabled, "Escape from endless settings returns to pause without starting its score clock")
	(ui._focus_groups[&"pause"][0] as Button).pressed.emit()
	_check(slice._modal_kind.is_empty() and slice.player.play_enabled, "Continue resumes endless through the shared pause button")
	var old_slice: WeakRef = weakref(slice)
	slice._return_to_title()
	await _settle()
	_check(current_scene is FoldlightGame and old_slice.get_ref() == null, "endless returns to one clean voyage title and releases its world")
	game = current_scene as FoldlightGame
	game.rogue_session.presentation.settings_requested.emit()
	await _settle()
	_check(game.rogue_session.presentation.screen_kind == &"settings" and bool(profile.get_setting(&"high_contrast")) != old_contrast, "the final title retains settings changed in endless")
	saved = ConfigFile.new()
	_check(saved.load(profile.SETTINGS_PATH) == OK and bool(saved.get_value("settings", "high_contrast", old_contrast)) != old_contrast, "endless accessibility changes survive an actual disk reload")
	profile.settings = original_settings
	profile.save_settings()
	profile.apply_settings()
	current_scene.queue_free()
	await _settle()
	print("FOLDLIGHT_UNIFIED_MODE_SETTINGS: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _joy(code: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _check(ok: bool, description: String) -> void:
	if ok:
		print("[PASS] " + description)
	else:
		failures.append(description)
		push_error("[FAIL] " + description)
