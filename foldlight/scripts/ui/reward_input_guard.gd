extends Node

## Both reward presentations must finish opening and observe neutral input
## before giving Controls focus. In particular, a held ui_accept must never
## become a Button release on the newly opened reward.
signal state_changed

const READ_SECONDS: float = 1.0
const NEUTRAL_SECONDS: float = 0.12
const AXIS_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"ui_left", &"ui_right", &"ui_up", &"ui_down",
]

var _surface: Control
var _active: bool = false
var _ready_for_choice: bool = false
var _elapsed: float = 0.0
var _read_seconds: float = READ_SECONDS
var _neutral_elapsed: float = 0.0
var _held_touches: Dictionary = {}
var _last_hint: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func begin(surface: Control, read_seconds: float = READ_SECONDS) -> void:
	cancel()
	_surface = surface
	_surface.visibility_changed.connect(_on_surface_visibility_changed)
	_active = true
	_elapsed = 0.0
	_read_seconds = maxf(READ_SECONDS, read_seconds)
	_neutral_elapsed = 0.0
	set_process(true)
	_last_hint = get_hint()
	state_changed.emit()


func cancel() -> void:
	if is_instance_valid(_surface) and _surface.visibility_changed.is_connected(_on_surface_visibility_changed):
		_surface.visibility_changed.disconnect(_on_surface_visibility_changed)
	_surface = null
	_active = false
	_ready_for_choice = false
	set_process(false)


func can_select() -> bool:
	return _active and _ready_for_choice and is_instance_valid(_surface) and _surface.is_visible_in_tree()


func get_hint() -> String:
	if _elapsed < _read_seconds:
		return "折痕正在展开 · 请稍候"
	return "松开按键、鼠标或摇杆，再作选择"


func _process(delta: float) -> void:
	if not is_instance_valid(_surface) or not _surface.is_visible_in_tree():
		cancel()
		return
	# A delayed frame or returning from a background window cannot skip the
	# entire reading period. Stick actions use their authored deadzones.
	var step := minf(delta, 0.10)
	_elapsed += step
	_neutral_elapsed = 0.0 if _has_held_input() else _neutral_elapsed + step
	if _elapsed >= _read_seconds and _neutral_elapsed >= NEUTRAL_SECONDS:
		_ready_for_choice = true
		set_process(false)
		state_changed.emit()
	elif get_hint() != _last_hint:
		_last_hint = get_hint()
		state_changed.emit()


func _input(event: InputEvent) -> void:
	# Track touch even outside the modal; Input.is_anything_pressed covers
	# keys, mouse, joy buttons and synthetic actions, but not active touches.
	if event is InputEventScreenTouch:
		if event.pressed:
			_held_touches[event.index] = true
		else:
			_held_touches.erase(event.index)
	if not _active:
		return
	if event.is_echo():
		get_viewport().set_input_as_handled()
		return
	if _ready_for_choice:
		return
	# Pause/cancel retains its existing owner. Consume both press and release
	# before GUI dispatch, not just the presentation's _unhandled_input path.
	if event.is_action(&"pause_game") or event.is_action(&"ui_cancel"):
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction or event is InputEventScreenTouch:
		# Analog devices can emit small drift changes every frame. Neutral is
		# judged by action deadzones in _process, not by the existence of noise.
		if not event is InputEventJoypadMotion:
			_neutral_elapsed = 0.0
		get_viewport().set_input_as_handled()


func _has_held_input() -> bool:
	if Input.is_anything_pressed() or not _held_touches.is_empty():
		return true
	for action in AXIS_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func _on_surface_visibility_changed() -> void:
	if not _surface.is_visible_in_tree():
		cancel()
