extends CanvasLayer

## Touch owns its own contacts and player state; it never mutates Input actions.
signal touch_mode_changed(enabled: bool)
signal layout_changed

const Surface = preload("res://scripts/ui/touch_controls_view.gd")
const POLL_INTERVAL: float = 0.10
const STICK_RADIUS: float = 124.0
const STICK_TRAVEL: float = 100.0
const STICK_DEADZONE: float = 0.13
const WEB_STATE_SCRIPT: String = "(function(){if(window.FoldlightTouch&&window.FoldlightTouch.getState)return window.FoldlightTouch.getState();return JSON.stringify({enabled:!!(navigator.maxTouchPoints>0&&window.matchMedia&&matchMedia('(pointer:coarse)').matches),cancelEpoch:0,suspended:false,safeArea:{},viewport:{width:innerWidth,height:innerHeight}});})()"

var _owner_ref: WeakRef
var _player_ref: WeakRef
var _context_enabled: bool = false
var _active: bool = false
var _touch_mode: bool = false
var _native_touch: bool = false
var _real_touch_seen: bool = false
var _host_layout: StringName = &""
var _host_suspended: bool = false
var _host_cancel_epoch: int = -1
var _cancel_epoch: int = 0
var _held_touches: Dictionary = {}
var _owned_touches: Dictionary = {}
var _last_observed_event: int = 0
var _stick_index: int = -1
var _stick_vector: Vector2 = Vector2.ZERO
var _safe_insets: Vector4 = Vector4.ZERO
var _poll_remaining: float = 0.0
var _surface: Control
var _bridge_callback: JavaScriptObject
var _inspect_callback: JavaScriptObject
var _bridge_subscribed: bool = false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = Surface.new()
	_surface.name = "TouchSurface"
	_surface.controller = self
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.focus_mode = Control.FOCUS_NONE
	add_child(_surface)
	get_viewport().size_changed.connect(_on_viewport_changed)
	_native_touch = OS.has_feature("mobile") and not OS.has_feature("web")
	_set_touch_mode(_native_touch)
	_poll_host()
	_surface.size = get_viewport().get_visible_rect().size
	_refresh_active()


func set_context(owner: Node, player: Node, enabled: bool) -> void:
	if _owner() == owner and _player() == player and _context_enabled == enabled:
		_refresh_active()
		return
	cancel_all(&"context_change")
	_owner_ref = weakref(owner) if is_instance_valid(owner) else null
	_player_ref = weakref(player) if is_instance_valid(player) else null
	_context_enabled = enabled
	if is_instance_valid(owner):
		var owner_exit := _on_context_exit.bind(owner.get_instance_id())
		if not owner.tree_exiting.is_connected(owner_exit):
			owner.tree_exiting.connect(owner_exit)
	if is_instance_valid(player):
		var player_exit := _on_player_exit.bind(player.get_instance_id())
		if not player.tree_exiting.is_connected(player_exit):
			player.tree_exiting.connect(player_exit)
	_refresh_active()


func clear_context(owner: Node) -> void:
	if _owner() != owner:
		return
	cancel_all(&"context_exit")
	_owner_ref = null
	_player_ref = null
	_context_enabled = false
	_refresh_active()


func cancel_for_player(player: Node) -> void:
	if _player() == player:
		cancel_all(&"player_suspended")
		_refresh_active()


func is_touch_mode() -> bool:
	return _touch_mode


func has_held_touches() -> bool:
	return not _held_touches.is_empty()


func get_held_touch_count() -> int:
	return _held_touches.size()


func get_cancel_epoch() -> int:
	return _cancel_epoch


## Guards call this before consuming a raw touch so releases cannot be lost
## to another _input handler. Re-observing the same event is harmless.
func observe_touch(event: InputEventScreenTouch) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or event.get_instance_id() == _last_observed_event:
		return
	_last_observed_event = event.get_instance_id()
	if event.canceled:
		cancel_all(&"touchcancel", true)
	elif event.pressed:
		_held_touches[event.index] = true
		_real_touch_seen = true
		if _host_layout == &"":
			_set_touch_mode(true)
	else:
		_held_touches.erase(event.index)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		observe_touch(event)
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.canceled:
			return
		_refresh_active()
		if event.pressed:
			if _active:
				_begin_contact(event.index, event.position)
		else:
			_end_contact(event.index)
		# Raw touches continue to menu/reward guards, even while a control owns it.
	elif event is InputEventScreenDrag and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _active and event.index == _stick_index:
			_update_stick(event.position)
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# Only suppress the mouse duplicate over live combat controls. Menus keep
		# normal Godot touch-to-mouse GUI behavior and desktop mice stay untouched.
		if _active and _control_at(event.position) != &"":
			get_viewport().set_input_as_handled()


func _begin_contact(index: int, point: Vector2) -> void:
	if _owned_touches.has(index):
		return
	var action := _control_at(point)
	if action == &"" or _owned_touches.values().has(action):
		return
	_owned_touches[index] = action
	var player := _player()
	match action:
		&"move":
			_stick_index = index
			_update_stick(point)
		&"fold":
			player.call("set_touch_fold_pressed", true)
		&"dash":
			player.call("request_touch_dash")
		&"active":
			player.call("request_touch_active_item")
	_surface.queue_redraw()


func _end_contact(index: int) -> void:
	var action: StringName = _owned_touches.get(index, &"")
	_owned_touches.erase(index)
	var player := _player()
	if action == &"move":
		_stick_index = -1
		_stick_vector = Vector2.ZERO
		if is_instance_valid(player):
			player.call("set_touch_movement", Vector2.ZERO)
	elif action == &"fold" and is_instance_valid(player):
		if _active:
			player.call("set_touch_fold_pressed", false)
		else:
			player.call("cancel_touch_input")
	if _surface != null:
		_surface.queue_redraw()


func _update_stick(point: Vector2) -> void:
	var offset := point - Vector2(get_layout_snapshot()["move"])
	var amount := clampf(offset.length() / STICK_TRAVEL, 0.0, 1.0)
	_stick_vector = Vector2.ZERO if amount <= STICK_DEADZONE else offset.normalized() * ((amount - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))
	var player := _player()
	if is_instance_valid(player):
		player.call("set_touch_movement", _stick_vector)
	_surface.queue_redraw()


func cancel_all(_reason: StringName = &"cancel", forget_contacts: bool = false) -> void:
	_owned_touches.clear()
	_stick_index = -1
	_stick_vector = Vector2.ZERO
	var player := _player()
	if is_instance_valid(player) and player.has_method("cancel_touch_input"):
		player.call("cancel_touch_input")
	if forget_contacts:
		_held_touches.clear()
		_cancel_epoch += 1
	if _surface != null:
		_surface.queue_redraw()


func get_layout_snapshot() -> Dictionary:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var left := minf(120.0, _safe_insets.x)
	var right := minf(120.0, _safe_insets.z)
	var bottom := minf(110.0, _safe_insets.w)
	return {"move": Vector2(245.0 + left, size.y - 220.0 - bottom), "move_radius": STICK_RADIUS,
		"fold": Vector2(size.x - 235.0 - right, size.y - 225.0 - bottom), "fold_radius": 108.0,
		"dash": Vector2(size.x - 455.0 - right, size.y - 165.0 - bottom), "dash_radius": 79.0,
		"active": Vector2(size.x - 310.0 - right, size.y - 445.0 - bottom), "active_radius": 76.0,
		"size": size, "active_controls": _active, "stick": _stick_vector,
		"pressed": _owned_touches.values(), "safe_insets": _safe_insets}


func _control_at(point: Vector2) -> StringName:
	var layout := get_layout_snapshot()
	for action in [&"fold", &"dash", &"active", &"move"]:
		if point.distance_to(Vector2(layout[action])) <= float(layout[String(action) + "_radius"]):
			return action
	return &""


func get_player() -> Node:
	return _player()


func _owner() -> Node:
	return _owner_ref.get_ref() as Node if _owner_ref != null else null


func _player() -> Node:
	return _player_ref.get_ref() as Node if _player_ref != null else null


func _refresh_active() -> void:
	var owner := _owner()
	var player := _player()
	var enabled := _touch_mode and not _host_suspended and _context_enabled and is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion() and is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and bool(player.get("play_enabled"))
	if enabled and owner is CanvasLayer:
		enabled = owner.visible
	elif enabled and owner is CanvasItem:
		enabled = owner.is_visible_in_tree()
	if _active and not enabled:
		cancel_all(&"inactive")
	_active = enabled
	if _surface != null:
		_surface.visible = _active


func _set_touch_mode(value: bool) -> void:
	if _touch_mode == value:
		return
	_touch_mode = value
	touch_mode_changed.emit(value)
	_refresh_active()


func _process(delta: float) -> void:
	_refresh_active()
	_poll_remaining -= delta
	if _poll_remaining <= 0.0:
		_poll_remaining = POLL_INTERVAL
		_poll_host()
		if _active:
			_surface.queue_redraw()


func _poll_host() -> void:
	if _native_touch:
		_refresh_native_safe_area()
		return
	if not OS.has_feature("web"):
		return
	var raw: Variant = JavaScriptBridge.eval(WEB_STATE_SCRIPT, true)
	if raw is String:
		var state: Variant = JSON.parse_string(raw)
		if state is Dictionary:
			apply_host_state(state)
	if not _bridge_subscribed:
		var bridge := JavaScriptBridge.get_interface("FoldlightTouch")
		if bridge != null and bool(JavaScriptBridge.eval("!!(window.FoldlightTouch&&typeof window.FoldlightTouch.subscribe==='function')", true)):
			_bridge_callback = JavaScriptBridge.create_callback(_on_host_callback)
			bridge.subscribe(_bridge_callback)
			if bool(JavaScriptBridge.eval("typeof window.FoldlightTouch.setInspector==='function'", true)):
				_inspect_callback = JavaScriptBridge.create_callback(_on_inspection_request)
				bridge.setInspector(_inspect_callback)
			_bridge_subscribed = true


## The display safe rectangle is in physical pixels. Remove the letterbox
## before converting to the fixed design viewport, so a notch inside a black
## side bar does not needlessly compress every HUD and touch control.
static func native_safe_insets(window_size: Vector2, viewport_size: Vector2, safe_rect: Rect2) -> Vector4:
	if window_size.x <= 0.0 or window_size.y <= 0.0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or not safe_rect.has_area():
		return Vector4.ZERO
	var scale_factor := minf(window_size.x / viewport_size.x, window_size.y / viewport_size.y)
	var content := Rect2((window_size - viewport_size * scale_factor) * 0.5, viewport_size * scale_factor)
	var safe := content.intersection(safe_rect)
	if not safe.has_area():
		return Vector4.ZERO
	return Vector4(maxf(0.0, safe.position.x - content.position.x), maxf(0.0, safe.position.y - content.position.y), maxf(0.0, content.end.x - safe.end.x), maxf(0.0, content.end.y - safe.end.y)) / scale_factor


func _refresh_native_safe_area() -> void:
	var physical_safe := Rect2(DisplayServer.get_display_safe_area())
	physical_safe.position -= Vector2(DisplayServer.window_get_position())
	var next := native_safe_insets(Vector2(DisplayServer.window_get_size()), get_viewport().get_visible_rect().size, physical_safe)
	if not _safe_insets.is_equal_approx(next):
		_safe_insets = next
		layout_changed.emit()


func _on_host_callback(arguments: Array) -> void:
	if arguments.is_empty() or not arguments[0] is String:
		return
	var state: Variant = JSON.parse_string(arguments[0])
	if state is Dictionary:
		apply_host_state(state)


func get_debug_snapshot() -> Dictionary:
	var snapshot := {"touch_mode": _touch_mode, "active": _active, "held_touch_count": _held_touches.size(), "owned_touch_count": _owned_touches.size(), "cancel_epoch": _cancel_epoch, "suspended": _host_suspended}
	var layout := get_layout_snapshot()
	snapshot["viewport"] = {"width": layout["size"].x, "height": layout["size"].y}
	var controls := {}
	for action in ["move", "fold", "dash", "active"]:
		var point: Vector2 = layout[action]
		controls[action] = {"x": point.x, "y": point.y, "radius": layout[action + "_radius"]}
	snapshot["controls"] = controls
	var player := _player()
	if is_instance_valid(player):
		snapshot["player_position"] = {"x": player.global_position.x, "y": player.global_position.y}
		snapshot["folding"] = player.get("folding")
		snapshot["captured"] = player.get("captured")
		snapshot["dashing"] = player.dash_component.is_dashing()
		snapshot["dash_cooldown"] = player.dash_component.cooldown_remaining
		snapshot["dash_charges"] = player.dash_component.charges
		snapshot["active_cooldown"] = player.active_item_slot.cooldown_remaining
		snapshot["play_enabled"] = player.get("play_enabled")
	var owner := _owner()
	if is_instance_valid(owner):
		snapshot["screen_kind"] = owner.get("screen_kind")
		if owner.has_method("get_touch_debug_buttons"):
			snapshot["buttons"] = owner.call("get_touch_debug_buttons")
		if owner.has_method("get_endless_navigation_snapshot"):
			var navigation: Dictionary = owner.call("get_endless_navigation_snapshot")
			for key: Variant in navigation:
				var value: Variant = navigation[key]
				if value is Rect2:
					navigation[key] = {"x": value.position.x, "y": value.position.y, "width": value.size.x, "height": value.size.y}
				elif value is Vector2:
					navigation[key] = {"x": value.x, "y": value.y}
			snapshot["navigation"] = navigation
		var runtime := owner.get_parent()
		if runtime != null and runtime.has_method("get_race_stats"):
			snapshot["survival"] = runtime.call("get_race_stats")
	return snapshot


func _on_inspection_request(_arguments: Array) -> void:
	var bridge := JavaScriptBridge.get_interface("FoldlightTouch")
	if bridge != null:
		bridge.publishInspection(JSON.stringify(get_debug_snapshot()))


func apply_host_state(state: Dictionary) -> void:
	# The webpage locks one layout for this engine. Touchscreen laptops must
	# not replace its desktop UI merely because a real finger touched a menu.
	var layout := StringName(str(state.get("layout", "")))
	var mode_changed := false
	if layout in [&"mobile", &"desktop"]:
		_host_layout = layout
		mode_changed = _touch_mode != (layout == &"mobile")
	var epoch := int(state.get("cancelEpoch", 0))
	if mode_changed or (_host_cancel_epoch >= 0 and epoch != _host_cancel_epoch):
		# Retire owners before notifying UI; a late release from the previous
		# layout must never become Fold's normal release/return-light action.
		cancel_all(&"host_cancel", true)
	_host_cancel_epoch = epoch
	_host_suspended = bool(state.get("suspended", false))
	var safe: Dictionary = state.get("safeArea", {})
	var viewport: Dictionary = state.get("viewport", {})
	var size := get_viewport().get_visible_rect().size
	var factor := maxf(size.x / maxf(1.0, float(viewport.get("width", size.x))), size.y / maxf(1.0, float(viewport.get("height", size.y))))
	var previous_insets := _safe_insets
	_safe_insets = Vector4(float(safe.get("left", 0.0)), float(safe.get("top", 0.0)), float(safe.get("right", 0.0)), float(safe.get("bottom", 0.0))) * factor
	var touch_mode := _host_layout == &"mobile" if _host_layout != &"" else (_native_touch or _real_touch_seen or bool(state.get("enabled", false)))
	_set_touch_mode(touch_mode)
	_refresh_active()
	if not previous_insets.is_equal_approx(_safe_insets):
		layout_changed.emit()


func _on_viewport_changed() -> void:
	cancel_all(&"viewport_changed", true)
	if _surface != null:
		_surface.size = get_viewport().get_visible_rect().size
		_surface.queue_redraw()
	layout_changed.emit()


func _on_context_exit(instance_id: int) -> void:
	var owner := _owner()
	if is_instance_valid(owner) and owner.get_instance_id() == instance_id:
		clear_context(owner)


func _on_player_exit(instance_id: int) -> void:
	var player := _player()
	if is_instance_valid(player) and player.get_instance_id() == instance_id:
		cancel_all(&"player_exit")
		_player_ref = null
		_refresh_active()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_all(&"focus_lost", true)
