class_name FoldlightGame
extends Node2D

## Application shell. The voyage session owns play, menus and presentation.
## Endless uses the same player and presentation in its dedicated world scene.
const PAUSE_BROWSE_CODE: Array[StringName] = [&"ui_up", &"ui_up", &"ui_down", &"ui_down", &"ui_left", &"ui_right", &"ui_left", &"ui_right"]

@onready var player: FoldlightPlayer = $Player
@onready var rogue_session: FoldlightRogueSessionController = $RogueSession
@onready var audio_director: FoldlightAudioDirector = get_node("/root/AudioDirector") as FoldlightAudioDirector
@onready var profile_manager: FoldlightProfileManager = get_node("/root/ProfileManager") as FoldlightProfileManager

var _pause_browse_code_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.set_feedback_motion_scale(float(profile_manager.get_setting(&"screen_shake", 1.0)))
	# Shared menus consume navigation before it reaches this application shell.
	rogue_session.presentation.pause_navigation.connect(_track_pause_browse_code)
	rogue_session.presentation.resume_requested.connect(_reset_pause_browse_code)
	rogue_session.presentation.settings_requested.connect(_reset_pause_browse_code)
	rogue_session.presentation.abandon_requested.connect(_reset_pause_browse_code)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and not _is_pause_screen_active():
		_reset_pause_browse_code()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"mute_audio") and not event.is_echo():
		get_viewport().set_input_as_handled()
		audio_director.toggle_mute()


func return_to_main_menu() -> void:
	_pause_browse_code_index = 0
	rogue_session.enter_title()


func _track_pause_browse_code(event: InputEventKey) -> void:
	if event.is_echo() or not event.pressed:
		return
	if not _is_pause_screen_active():
		_pause_browse_code_index = 0
		return
	var direction: StringName = &""
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action):
			direction = action
			break
	if direction.is_empty():
		return
	if direction == PAUSE_BROWSE_CODE[_pause_browse_code_index]:
		_pause_browse_code_index += 1
	else:
		_pause_browse_code_index = 1 if direction == PAUSE_BROWSE_CODE[0] else 0
	if _pause_browse_code_index >= PAUSE_BROWSE_CODE.size():
		_pause_browse_code_index = 0
		_enable_browse_invincibility()


func _is_pause_screen_active() -> bool:
	return rogue_session != null and rogue_session.is_paused()


func _reset_pause_browse_code() -> void:
	_pause_browse_code_index = 0


func _enable_browse_invincibility() -> void:
	rogue_session.set_browse_mode_enabled(true)
