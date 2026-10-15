extends RefCounted

## One combat/input vocabulary for the voyage, endless and friend race.
## This describes existing actions; it never changes combat or save data.
const KEYBOARD_MOVE: String = "WASD / 方向键  移动"
const GAMEPAD_MOVE: String = "左摇杆 / 十字键  移动"
const KEYBOARD_FOLD: String = "按住 SPACE / E  收纳 · 松开  返光"
const GAMEPAD_FOLD: String = "按住 A  收纳 · 松开 A  返光"
const KEYBOARD_DASH: String = "SHIFT  冲刺"
const GAMEPAD_DASH: String = "B  冲刺"
const KEYBOARD_ACTIVE: String = "Q  主动技能"
const GAMEPAD_ACTIVE: String = "X  主动技能"
const TOUCH_MOVE: String = "左侧摇杆  移动"
const TOUCH_FOLD: String = "按住收纳 · 松开返光"
const TOUCH_DASH: String = "点按冲刺"
const TOUCH_ACTIVE: String = "点按技能"
const AUTOMATIC_ATTACK: String = "武器自动寻敌攻击 · 返光自动追踪"
const TUTORIAL_SKIP_HINT: String = "F / LB  跳过并开始"


static func movement_vector(touch_vector: Vector2 = Vector2.ZERO) -> Vector2:
	return (Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") + touch_vector).limit_length(1.0)


static func device_for_event(event: InputEvent, current: StringName = &"keyboard") -> StringName:
	if event is InputEventScreenTouch and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		return &"touch"
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return current
	if event is InputEventJoypadButton and event.is_pressed():
		return &"gamepad"
	if event is InputEventJoypadMotion:
		# A connected controller's idle drift must not replace keyboard prompts.
		var deadzone := InputMap.action_get_deadzone(&"move_left")
		if absf(event.axis_value) > deadzone:
			return &"gamepad"
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		return &"keyboard"
	elif event is InputEventMouseButton and event.is_pressed():
		return &"keyboard"
	return current


static func navigation_step(event: InputEvent, horizontal: bool = true) -> int:
	if not event.is_pressed() or event.is_echo():
		return 0
	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		return -1
	if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		return 1
	if horizontal:
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			return -1
		if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			return 1
	return 0


static func combat_hint(gamepad: bool = false) -> String:
	return "   ".join([
		GAMEPAD_MOVE if gamepad else KEYBOARD_MOVE,
		GAMEPAD_FOLD if gamepad else KEYBOARD_FOLD,
		GAMEPAD_DASH if gamepad else KEYBOARD_DASH,
		GAMEPAD_ACTIVE if gamepad else KEYBOARD_ACTIVE,
	])


static func menu_hint(gamepad: bool = false) -> String:
	return "左摇杆 / 十字键  选择    A  确认    B / Start  返回" if gamepad else "WASD / 方向键  选择    SPACE / E / Enter  确认    Esc  返回"


static func tutorial_controls(step: int, gamepad: bool = false) -> String:
	match step:
		0:
			return "%s     %s" % [GAMEPAD_MOVE if gamepad else KEYBOARD_MOVE, GAMEPAD_DASH if gamepad else KEYBOARD_DASH]
		1:
			return GAMEPAD_FOLD if gamepad else KEYBOARD_FOLD
		_:
			return "自动武器  自动攻击     %s" % (GAMEPAD_ACTIVE if gamepad else KEYBOARD_ACTIVE)
