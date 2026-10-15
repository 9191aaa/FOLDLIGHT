class_name FoldlightRouteAtlas
extends Control
## A browsable chart. Selection never starts a room: the presentation owns its
## existing keyboard/gamepad destination buttons and the explicit confirmation.

signal node_selected(id: StringName)
signal node_hovered(id: StringName)

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const PreviewData = preload("res://scripts/roguelite/ui/route_preview_data.gd")
const Landmark = preload("res://scripts/roguelite/ui/route_landmark.gd")
const Seascape = preload("res://scripts/visuals/paper_seascape.gd")
const MIN_ZOOM := 0.38
const MAX_ZOOM := 1.85
const COLUMN_SPACING := 308.0
const BRANCH_SPACING := 270.0
const PICK_RADIUS := 82.0
const DRAG_THRESHOLD := 7.0

class Seafloor extends Control:
	var region_id: StringName = &"paper_reef"
	var route_mark: int = 0
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
		Seascape.draw_region(self, Rect2(Vector2.ZERO, Vector2(size.x, maxf(1, size.y - 112))), region_id, route_mark)

var selected_node_id: StringName = &""
var current_node_id: StringName = &""
var hovered_node_id: StringName = &""
var zoom: float = 1.0
var pan := Vector2.ZERO

var _snapshot: Dictionary = {}
var _nodes: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _positions: Dictionary = {}
var _edges: Array[Dictionary] = []
var _available: Array[String] = []
var _cleared: Array[StringName] = []
var _world_bounds := Rect2(-140, -230, 280, 460)
var _current_depth: int = 0
var _max_depth: int = 1
var _time: float = 0.0
var _unfold: float = 1.0
var _entrance: Tween
var _focus_motion: Tween
var _pressed_position := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _pointer_down: bool = false
var _drag_started: bool = false
var _drag_button: MouseButton = MOUSE_BUTTON_NONE
var _hover_strength: Dictionary = {}
var _needs_initial_fit: bool = false
var _font: Font
var _preview_box := StyleBoxFlat.new()
var _view_mode: StringName = &"ahead"
var _motion_scale: float = 1.0
var _context: Dictionary = {}
var _seafloor: Seafloor
var _redraw_elapsed: float = 0.0
var _draw_count: int = 0
var _touch_layout := false
var _touch_index := -1


func set_touch_layout(enabled: bool) -> void:
	_touch_layout = enabled
	_touch_index = -1
	_pointer_down = false
	_drag_started = false
	queue_redraw()


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_box.bg_color = Color(Palette.INK, 0.96)
	_preview_box.set_border_width_all(1)
	_preview_box.shadow_color = Color(0, 0, 0, 0.20)
	_preview_box.shadow_size = 9


func _ready() -> void:
	_font = get_theme_default_font()
	_seafloor = Seafloor.new()
	_seafloor.name = "StaticSeafloor"
	_seafloor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seafloor.show_behind_parent = true
	add_child(_seafloor)
	_refresh_seafloor()
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	visibility_changed.connect(_on_visibility_changed)
	if _needs_initial_fit:
		_fit_view()
		_play_entrance()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_touch_index = -1
		_pointer_down = false
		_drag_started = false
		_drag_button = MOUSE_BUTTON_NONE
		_set_hover(&"")


## Snapshot follows the route generator: nodes[{id, depth, category, risk, exits}].
## The caller-provided exits array is the sole authority for reachability.
func configure(snapshot: Dictionary, current_id: StringName, exits: Array[String]) -> void:
	_snapshot = snapshot.duplicate(true)
	_context = (_snapshot.get("context", {}) as Dictionary).duplicate(true)
	_motion_scale = clampf(float(_context.get("motion_scale", 1.0)), 0.0, 1.0)
	_view_mode = &"ahead"
	current_node_id = current_id
	_available = exits.duplicate()
	_cleared.clear()
	var cleared_source: Variant = _snapshot.get("cleared_node_ids", [])
	if cleared_source is Array:
		for id: Variant in cleared_source:
			_cleared.append(StringName(id))
	_nodes.clear()
	_by_id.clear()
	_positions.clear()
	_edges.clear()
	_hover_strength.clear()
	selected_node_id = &""
	hovered_node_id = &""
	_pointer_down = false
	_drag_started = false
	_max_depth = 1
	var source: Variant = _snapshot.get("nodes", [])
	if source is Array:
		for value: Variant in source:
			if not value is Dictionary:
				continue
			var node: Dictionary = value
			var id := StringName(node.get("id", &""))
			if id.is_empty() or _by_id.has(id):
				continue
			_nodes.append(node)
			_by_id[id] = node
			_max_depth = maxi(_max_depth, int(node.get("depth", 0)))
	_current_depth = int((_by_id.get(current_id, {}) as Dictionary).get("depth", 0))
	_layout_nodes()
	_build_edges()
	if _by_id.has(current_node_id):
		selected_node_id = current_node_id
	for id in _available:
		if _by_id.has(StringName(id)):
			selected_node_id = StringName(id)
			break
	_needs_initial_fit = true
	if is_inside_tree():
		_refresh_seafloor()
		_fit_view()
		_play_entrance()
	set_process(is_visible_in_tree() and _motion_scale > 0.0)
	_refresh_static_hover()
	queue_redraw()


## Programmatic selection for the existing destination buttons. It deliberately
## does not emit node_selected, so focus synchronization cannot recurse.
func focus_destination(id: StringName) -> void:
	if not _by_id.has(id):
		return
	selected_node_id = id
	_refresh_static_hover()
	if is_inside_tree() and size.x > 1.0 and size.y > 1.0:
		var screen := get_node_screen_position(id)
		var safe_rect := Rect2(Vector2(130, 110), Vector2(maxf(1, size.x - 260), maxf(1, size.y - 270)))
		if not safe_rect.has_point(screen):
			_animate_pan(Vector2(size.x * 0.5, (size.y - 110) * 0.5) - (_positions[id] as Vector2) * zoom)
	queue_redraw()


func recenter() -> void:
	_view_mode = &"overview"
	_fit_view()


func focus_ahead() -> void:
	_view_mode = &"ahead"
	_fit_view()


func _fit_view() -> void:
	if size.x < 1.0 or size.y < 1.0:
		_needs_initial_fit = true
		return
	_stop_focus_motion()
	var bounds := _world_bounds
	if _view_mode == &"ahead":
		var first := true
		var start_depth := maxi(0, mini(_current_depth - 1, _max_depth - 2))
		var end_depth := mini(_max_depth, maxi(_current_depth + 2, 2))
		for node in _nodes:
			var depth := int(node.get("depth", 0))
			if depth < start_depth or depth > end_depth: continue
			var rect := Rect2((_positions[StringName(node["id"])] as Vector2) - Vector2(120, 115), Vector2(240, 245))
			bounds = rect if first else bounds.merge(rect)
			first = false
	var available_size := Vector2(maxf(120, size.x - 132), maxf(130, size.y - 240))
	zoom = clampf(minf(available_size.x / maxf(1, bounds.size.x), available_size.y / maxf(1, bounds.size.y)), MIN_ZOOM, 1.30 if _view_mode == &"ahead" else 1.05)
	pan = Vector2(size.x * 0.5, (size.y - 110) * 0.5 + 12) - bounds.get_center() * zoom
	_needs_initial_fit = false
	queue_redraw()


## Toolbar zoom uses the chart center; the mouse wheel uses the pointer instead.
func zoom_by(factor: float) -> void:
	_zoom_at(factor, size * 0.5)


func is_destination_reachable(id: StringName) -> bool:
	return _by_id.has(id) and String(id) in _available


func get_node_screen_position(id: StringName) -> Vector2:
	if not _positions.has(id):
		return Vector2(-10000, -10000)
	return _map_to_screen(_positions[id])


func get_node_preview(id: StringName = &"") -> Dictionary:
	if id.is_empty():
		id = selected_node_id
	if not _by_id.has(id):
		return {}
	var node: Dictionary = _by_id[id]
	var category := StringName(node.get("category", &"combat"))
	var state := "可前往 · 在手记下方确认出发" if is_destination_reachable(id) else "远方折点 · 目前仅可查看"
	if id == current_node_id:
		state = "当前位置 · 此处已澄清"
	elif id in _cleared:
		state = "已经澄清 · 无法再次抵达"
	elif int(node.get("depth", 0)) < _current_depth:
		state = "早期折点 · 本次无法返回"
	elif int(node.get("depth", 0)) == _current_depth:
		state = "另一支航路 · 目前无法抵达"
	var result := PreviewData.describe(node, _context, is_destination_reachable(id), int(_snapshot.get("index", 0)))
	result.merge({
		"id": id,
		"category": category,
		"depth": int(node.get("depth", 0)),
		"risk": int(node.get("risk", 1)),
		"reachable": is_destination_reachable(id),
		"current": id == current_node_id,
		"cleared": id in _cleared,
		"status": state,
	}, true)
	return result


func get_view_state() -> Dictionary:
	return {"zoom": zoom, "pan": pan, "selected_node_id": selected_node_id, "hovered_node_id": hovered_node_id, "node_count": _nodes.size(), "dragging": _drag_started, "unfold": _unfold, "view_mode": _view_mode, "motion_scale": _motion_scale, "clock": _time, "current_depth": _current_depth, "max_depth": _max_depth, "draw_count": _draw_count, "seafloor_draw_count": _seafloor.draw_count if is_instance_valid(_seafloor) else 0}


func get_journey_snapshot() -> Dictionary:
	var sailed_edges: Array[Dictionary] = []
	for edge in _edges:
		if StringName(edge["from"]) in _cleared and StringName(edge["to"]) in _cleared:
			sailed_edges.append({"from": edge["from"], "to": edge["to"]})
	return {"current_step": _current_depth + 1, "total_steps": _max_depth + 1, "remaining_steps": maxi(0, _max_depth - _current_depth), "sailed_edges": sailed_edges, "context": _context.duplicate(true)}


func _layout_nodes() -> void:
	var depths: Dictionary = {}
	for node in _nodes:
		var depth := int(node.get("depth", 0))
		if not depths.has(depth):
			depths[depth] = []
		(depths[depth] as Array).append(node)
	var first := true
	for depth: int in depths:
		var siblings: Array = depths[depth]
		siblings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
		for index in siblings.size():
			var node: Dictionary = siblings[index]
			var id := StringName(node.get("id", &""))
			var branch := float(index) - float(siblings.size() - 1) * 0.5
			var y := branch * BRANCH_SPACING + sin(float(depth) * 1.18) * 65.0
			var position := Vector2(float(depth) * COLUMN_SPACING, y)
			_positions[id] = position
			var rect := Rect2(position - Vector2(120, 115), Vector2(240, 245))
			_world_bounds = rect if first else _world_bounds.merge(rect)
			first = false
	if first:
		_world_bounds = Rect2(-140, -160, 280, 320)


func _build_edges() -> void:
	for node in _nodes:
		var id := StringName(node.get("id", &""))
		var exits: Variant = node.get("exits", [])
		if not exits is Array:
			continue
		for exit_id: Variant in exits:
			var destination := StringName(exit_id)
			if not _positions.has(destination):
				continue
			var a: Vector2 = _positions[id]
			var b: Vector2 = _positions[destination]
			var path := PackedVector2Array()
			for sample in 25:
				var t := float(sample) / 24.0
				path.append(a.bezier_interpolate(a + Vector2(110, 0), b - Vector2(110, 0), b, t))
			_edges.append({"from": id, "to": destination, "path": path})


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _motion_scale <= 0.0:
		return
	_time += minf(delta, 0.1) * _motion_scale
	for node in _nodes:
		var id := StringName(node.get("id", &""))
		var target := 1.0 if id == hovered_node_id or id == selected_node_id else 0.0
		_hover_strength[id] = move_toward(float(_hover_strength.get(id, 0.0)), target, delta * 6.0) if _motion_scale > 0.0 else target
	_redraw_elapsed += delta
	if _redraw_elapsed >= 1.0 / 30.0:
		_redraw_elapsed = fmod(_redraw_elapsed, 1.0 / 30.0)
		queue_redraw()


func _refresh_static_hover() -> void:
	if _motion_scale > 0.0:
		return
	for node in _nodes:
		var id := StringName(node.get("id", &""))
		_hover_strength[id] = 1.0 if id == hovered_node_id or id == selected_node_id else 0.0


func _refresh_seafloor() -> void:
	if not is_instance_valid(_seafloor): return
	var region_id := StringName(_snapshot.get("id", &"paper_reef"))
	var route_mark := int(_snapshot.get("route_mark", 0))
	if _seafloor.size == size and _seafloor.region_id == region_id and _seafloor.route_mark == route_mark:
		return
	_seafloor.size = size
	_seafloor.region_id = region_id
	_seafloor.route_mark = route_mark
	_seafloor.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _touch_layout and event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_stop_focus_motion()
			_pressed_position = event.position
			_pointer_down = true
			_drag_started = false
		elif not event.pressed and event.index == _touch_index:
			if not _drag_started and not event.canceled:
				var id := _node_at(event.position)
				if not id.is_empty():
					selected_node_id = id
					_refresh_static_hover()
					queue_redraw()
					node_selected.emit(id)
			_touch_index = -1
			_pointer_down = false
			_drag_started = false
		accept_event()
		return
	if _touch_layout and event is InputEventScreenDrag:
		if event.index == _touch_index:
			if event.position.distance_to(_pressed_position) >= 20: _drag_started = true
			if _drag_started:
				_view_mode = &"manual"
				pan += event.relative
				_clamp_pan()
				queue_redraw()
			accept_event()
		return
	# Native raw touch owns chart gestures; its emulated mouse must not select twice.
	if _touch_layout and event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		_last_pointer = mouse.position
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(1.12 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, mouse.position)
			accept_event()
		elif mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if mouse.pressed:
				_stop_focus_motion()
				_pressed_position = mouse.position
				_pointer_down = true
				_drag_started = mouse.button_index == MOUSE_BUTTON_MIDDLE
				_drag_button = mouse.button_index
			elif _pointer_down and mouse.button_index == _drag_button:
				if not _drag_started:
					var id := _node_at(mouse.position)
					if not id.is_empty():
						selected_node_id = id
						_refresh_static_hover()
						queue_redraw()
						node_selected.emit(id)
				_pointer_down = false
				_drag_started = false
				_drag_button = MOUSE_BUTTON_NONE
				_update_hover(mouse.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_last_pointer = motion.position
		if _pointer_down:
			if motion.position.distance_to(_pressed_position) >= DRAG_THRESHOLD:
				_drag_started = true
			if _drag_started:
				_view_mode = &"manual"
				pan += motion.relative
				_clamp_pan()
				queue_redraw()
				_set_hover(&"")
				mouse_default_cursor_shape = Control.CURSOR_DRAG
			accept_event()
		else:
			_update_hover(motion.position)
	elif event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
		accept_event()
	elif event is InputEventPanGesture:
		_stop_focus_motion()
		pan -= (event as InputEventPanGesture).delta * 24.0
		_clamp_pan()
		_view_mode = &"manual"
		queue_redraw()
		accept_event()


func _zoom_at(factor: float, anchor: Vector2) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	_stop_focus_motion()
	_view_mode = &"manual"
	var world_point := (anchor - pan) / zoom
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	pan = anchor - world_point * zoom
	_clamp_pan()
	_update_hover(_last_pointer)
	queue_redraw()


func _clamp_pan() -> void:
	# Keep at least the nearest island recoverable even after a very long drag.
	var margin := Vector2(100, 90)
	pan.x = clampf(pan.x, margin.x - _world_bounds.end.x * zoom, size.x - margin.x - _world_bounds.position.x * zoom)
	pan.y = clampf(pan.y, margin.y - _world_bounds.end.y * zoom, size.y - margin.y - _world_bounds.position.y * zoom)


func _node_at(point: Vector2) -> StringName:
	if point.y >= size.y - 112:
		return _minimap_node_at(point)
	var nearest: StringName = &""
	var distance := maxf(60.0 if _touch_layout else 28.0, PICK_RADIUS * zoom)
	for node in _nodes:
		var id := StringName(node.get("id", &""))
		var delta := point.distance_to(get_node_screen_position(id))
		if delta < distance:
			distance = delta
			nearest = id
	return nearest


func _update_hover(point: Vector2) -> void:
	var id := _node_at(point) if Rect2(Vector2.ZERO, size).has_point(point) else &""
	_set_hover(id)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not id.is_empty() else Control.CURSOR_DRAG


func _set_hover(id: StringName) -> void:
	if hovered_node_id == id:
		return
	hovered_node_id = id
	_refresh_static_hover()
	queue_redraw()
	node_hovered.emit(id)


func _map_to_screen(point: Vector2) -> Vector2:
	return pan + point * zoom + Vector2(0, (1.0 - _unfold) * 24.0 * _motion_scale)


func _animate_pan(destination: Vector2) -> void:
	_stop_focus_motion()
	if _motion_scale <= 0.0:
		pan = destination
		return
	_focus_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_motion.tween_property(self, "pan", destination, 0.38)


func _stop_focus_motion() -> void:
	if _focus_motion != null and _focus_motion.is_valid():
		_focus_motion.kill()


func _play_entrance() -> void:
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	if _motion_scale <= 0.0:
		_unfold = 1.0
		return
	_unfold = 0.0
	_entrance = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entrance.tween_property(self, "_unfold", 1.0, 0.62)


func _on_resized() -> void:
	_refresh_seafloor()
	if _needs_initial_fit or _view_mode in [&"ahead", &"overview"]:
		_fit_view()
	else:
		_clamp_pan()
	queue_redraw()


func _on_mouse_exited() -> void:
	_set_hover(&"")


func _on_visibility_changed() -> void:
	_touch_index = -1
	set_process(is_visible_in_tree() and _motion_scale > 0.0)
	if not is_visible_in_tree():
		_stop_focus_motion()
		if _entrance != null and _entrance.is_valid(): _entrance.kill()
		_unfold = 1.0
		_pointer_down = false
		_drag_started = false
		_set_hover(&"")


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	_draw_count += 1
	if _font == null:
		_font = get_theme_default_font()
	PaperArt.draw_tide(self, size, _time * 0.4, 5, 0.62)
	_draw_chart_details()
	if _nodes.is_empty():
		_draw_text("航图尚未展开", Vector2(size.x * 0.5 - 100, size.y * 0.5), 24, Palette.MUTED)
		return
	for edge in _edges:
		_draw_edge(edge)
	for node in _nodes:
		_draw_island(node)
	_draw_compass()
	_draw_chart_caption()
	_draw_minimap()
	if not hovered_node_id.is_empty() and not _drag_started:
		_draw_preview(hovered_node_id, true)
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(Palette.FOLD, 0.19), false, 1.0, true)


func _draw_chart_details() -> void:
	# Quiet chart meridians and paper seams shift with the viewport, giving scale
	# to the ocean without suggesting additional selectable destinations.
	for line in 9:
		var x := fposmod(float(line) * 260.0 * zoom + pan.x * 0.22, size.x + 280.0) - 140.0
		var points := PackedVector2Array([Vector2(x, 0), Vector2(x + 60, size.y * 0.48), Vector2(x + 22, size.y)])
		draw_polyline(points, Color(Palette.PAPER, 0.018), 1.0, true)
	for mark in 25:
		var x := fposmod(float(mark * 179 + 71) + pan.x * 0.12, maxf(1, size.x))
		var y := fposmod(float(mark * 137 + 53) + pan.y * 0.12, maxf(1, size.y))
		draw_line(Vector2(x, y), Vector2(x + 8, y - 1), Color(Palette.FOLD, 0.045), 1.0, true)
	# Sounding lines follow the authored island positions. They describe the
	# shoals around real destinations, not additional selectable locations.
	for node in _nodes:
		var center := get_node_screen_position(StringName(node["id"]))
		for ring in 3:
			var contour := PackedVector2Array()
			for step in 41:
				var angle := float(step) * TAU / 40.0
				var radius := (103.0 + float(ring) * 29.0 + sin(angle * 3.0 + float(node.get("depth", 0))) * 12.0) * zoom
				contour.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.54 + 19.0 * zoom))
			draw_polyline(contour, Color(Palette.FOLD, 0.065 - float(ring) * 0.012), 1.0, true)


func _draw_edge(edge: Dictionary) -> void:
	var from_id := StringName(edge["from"])
	var to_id := StringName(edge["to"])
	var reachable := from_id == current_node_id and is_destination_reachable(to_id)
	var selected := reachable and to_id == selected_node_id
	var sailed := from_id in _cleared and (to_id in _cleared or to_id == current_node_id)
	var alpha := (0.82 if reachable else (0.65 if sailed else 0.22)) * _unfold
	var color := Palette.GOLD if sailed else Palette.FOLD
	var path := PackedVector2Array()
	for point: Vector2 in edge["path"]:
		path.append(_map_to_screen(point))
	draw_polyline(path, Color(Palette.INK, 0.60 * _unfold), 8.0 if selected else 5.0, true)
	var visible_path := PackedVector2Array()
	for index in maxi(2, int(ceil(float(path.size()) * _unfold))):
		visible_path.append(path[mini(index, path.size() - 1)])
	draw_polyline(visible_path, Color(color, alpha), (3.0 if selected else 2.2) if reachable else (2.0 if sailed else 1.0), true)
	if reachable:
		for mote in 2:
			var progress := fposmod(_time * 0.16 + float(mote) * 0.5, 1.0)
			var sample := progress * float(path.size() - 1)
			var index := mini(int(sample), path.size() - 2)
			var point := path[index].lerp(path[index + 1], sample - float(index))
			var direction := path[index].direction_to(path[index + 1])
			draw_line(point - direction * 8.0, point + direction * 5.0, Color(color, 0.62 * _unfold), 2.0, true)


func _draw_island(node: Dictionary) -> void:
	var id := StringName(node.get("id", &""))
	var center := get_node_screen_position(id)
	if not Rect2(Vector2(-150, -150), size + Vector2(300, 300)).has_point(center):
		return
	var category := StringName(node.get("category", &"combat"))
	var hovered := float(_hover_strength.get(id, 0.0))
	var reachable := is_destination_reachable(id)
	var current := id == current_node_id
	var color := _category_color(category)
	var radius := (80.0 if category == &"boss" else 66.0) * zoom * lerpf(0.86, 1.0, _unfold)
	center.y -= hovered * 5.0 * _motion_scale
	var base := Palette.SURFACE_SOFT.lerp(color, 0.16 if reachable or current else 0.06)
	var opacity := (1.0 if reachable or current else 0.72) * _unfold
	var island := PackedVector2Array([
		center + Vector2(-1.10, 0.03) * radius, center + Vector2(-0.63, -0.40) * radius,
		center + Vector2(0.02, -0.55) * radius, center + Vector2(0.88, -0.21) * radius,
		center + Vector2(1.12, 0.19) * radius, center + Vector2(0.38, 0.56) * radius,
		center + Vector2(-0.55, 0.44) * radius,
	])
	var shadow := PackedVector2Array()
	for point in island:
		shadow.append(point + Vector2(0, 12 + hovered * 3) * zoom)
	draw_colored_polygon(shadow, Color(Palette.INK.darkened(0.25), opacity))
	draw_colored_polygon(island, Color(base, opacity))
	var fold := center + Vector2(0.10, 0.04) * radius
	draw_colored_polygon(PackedVector2Array([island[0], island[1], island[2], fold]), Color(base.lightened(0.10), opacity))
	draw_colored_polygon(PackedVector2Array([island[2], island[3], island[4], fold]), Color(base.lightened(0.035), opacity))
	draw_colored_polygon(PackedVector2Array([island[4], island[5], island[6], fold]), Color(base.darkened(0.18), opacity))
	var outline := island.duplicate()
	outline.append(island[0])
	draw_polyline(outline, Color(color, (0.32 + hovered * 0.34) * _unfold), 1.2, true)
	draw_line(island[2], fold, Color(Palette.PAPER, 0.13 * _unfold), 1.0, true)
	if selected_node_id == id:
		draw_arc(center, radius * 1.28, -PI * 0.88, -PI * 0.15, 24, Color(Palette.GOLD, 0.72 * _unfold), 1.5, true)
		draw_arc(center, radius * 1.28, PI * 0.12, PI * 0.85, 24, Color(Palette.GOLD, 0.72 * _unfold), 1.5, true)
	Landmark.draw(self, center - Vector2(0, radius * 0.25), category, maxf(0.50, zoom * 1.08), opacity)
	if current:
		PaperArt.draw_moth(self, center - Vector2(0, radius * 1.18 + sin(_time * 1.5) * 3.0 * _motion_scale), 0.28 + zoom * 0.14, 1.0)
	elif id in _cleared:
		draw_line(center + Vector2(-9, -1) * zoom, center + Vector2(-2, 6) * zoom, Palette.GOLD, 2.0, true)
		draw_line(center + Vector2(-2, 6) * zoom, center + Vector2(12, -10) * zoom, Palette.GOLD, 2.0, true)
	var font_size := 32 if _touch_layout else int(clampf(21.0 * zoom, 15.0, 25.0))
	var title := _category_title(category)
	var width := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_draw_text(title, center + Vector2(-width * 0.5, radius + 22.0), font_size, Color(Palette.PAPER, (0.96 if reachable or current else 0.62) * _unfold))
	if not _touch_layout and (reachable or current or id in _cleared):
		var tag := "此刻" if current else ("可抵达" if reachable else "已澄清")
		var tag_width := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_draw_text(tag, center + Vector2(-tag_width * 0.5, radius + 39), 12, Color(Palette.FOLD if current else Palette.GOLD, _unfold))
	if not _touch_layout and reachable and zoom >= 0.7:
		var info := get_node_preview(id)
		var reward_text := "武器" if info.get("reward_kind") == &"weapon" else ("主动道具" if info.get("reward_kind") == &"active" else ("强化＋主动" if info.get("reward_kind") == &"first_active" else ("终潮" if category == &"boss" else "强化")))
		var caption := "威胁 %d  /  %s" % [int(node.get("risk", 1)), reward_text]
		var caption_width := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_draw_text(caption, center + Vector2(-caption_width * 0.5, radius + 61), 15, Color(Palette.MUTED, _unfold))


func _draw_compass() -> void:
	var center := Vector2(size.x - 56, 58)
	var color := Color(Palette.GOLD, 0.33)
	draw_line(center + Vector2(0, -23), center + Vector2(0, 23), color, 1.0, true)
	draw_line(center + Vector2(-23, 0), center + Vector2(23, 0), color, 1.0, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -21), center + Vector2(4, 5), center, center + Vector2(-4, 5)]), color)
	draw_arc(center, 16, 0, TAU, 32, Color(Palette.GOLD, 0.12), 1.0, true)


func _draw_chart_caption() -> void:
	var chapter := int(_snapshot.get("index", 0)) + 1
	if _touch_layout:
		_draw_text("海域 %02d  /  %s" % [chapter, "前方航路" if _view_mode == &"ahead" else "航图"], Vector2(28, 44), 32, Palette.FOLD)
		return
	_draw_text("海域 %02d  /  %s" % [chapter, "前方航路" if _view_mode == &"ahead" else ("完整航图" if _view_mode == &"overview" else "自由阅图")], Vector2(28, 37), 17, Palette.FOLD)
	_draw_text("第 %d / %d 折点  ·  距终潮 %d 航段" % [_current_depth + 1, _max_depth + 1, maxi(0, _max_depth - _current_depth)], Vector2(28, 66), 17, Palette.MUTED)


func _minimap_rect() -> Rect2:
	return Rect2(Vector2(28, size.y - 82), Vector2(maxf(1, size.x - 56), 57))


func _minimap_position(id: StringName) -> Vector2:
	var rect := _minimap_rect()
	var point: Vector2 = _positions.get(id, Vector2.ZERO)
	return rect.position + Vector2((point.x - _world_bounds.position.x) / maxf(1, _world_bounds.size.x) * rect.size.x, (point.y - _world_bounds.position.y) / maxf(1, _world_bounds.size.y) * rect.size.y)


func _minimap_node_at(point: Vector2) -> StringName:
	var nearest: StringName = &""
	var distance := 60.0 if _touch_layout else 18.0
	for node in _nodes:
		var id := StringName(node["id"])
		var candidate := point.distance_to(_minimap_position(id))
		if candidate < distance:
			distance = candidate
			nearest = id
	return nearest


func _draw_minimap() -> void:
	var top := size.y - 112
	draw_rect(Rect2(Vector2(0, top), Vector2(size.x, 112)), Color(Palette.INK, 0.96))
	draw_line(Vector2(24, top), Vector2(size.x - 24, top), Color(Palette.FOLD, 0.18), 1.0)
	_draw_text("全程航迹", Vector2(28, top + 30), 28 if _touch_layout else 14, Palette.MUTED)
	if not _touch_layout:
		_draw_text("金线 已航行   ·   青线 可前往", Vector2(maxf(190, size.x - 290), top + 23), 14, Palette.MUTED)
	for edge in _edges:
		var from_id := StringName(edge["from"])
		var to_id := StringName(edge["to"])
		var sailed := from_id in _cleared and to_id in _cleared
		var reachable := from_id == current_node_id and is_destination_reachable(to_id)
		draw_line(_minimap_position(from_id), _minimap_position(to_id), Color(Palette.GOLD if sailed else Palette.FOLD, 0.75 if sailed or reachable else 0.24), 2 if sailed or reachable else 1, true)
	for node in _nodes:
		var id := StringName(node["id"])
		var point := _minimap_position(id)
		var active := id == current_node_id or is_destination_reachable(id)
		var color := Palette.GOLD if id in _cleared or node.get("category") == "boss" else Palette.FOLD
		draw_circle(point, 4 if active else 3, Color(color, 1 if active or id in _cleared else 0.43))
		if id == current_node_id: draw_arc(point, 8, 0, TAU, 20, Palette.PAPER, 1.4, true)
		if id == selected_node_id: draw_arc(point, 10, -PI * 0.75, PI * 0.75, 20, Palette.GOLD, 1.0, true)


func _draw_preview(id: StringName, is_hover: bool) -> void:
	var preview := get_node_preview(id)
	if preview.is_empty():
		return
	var width := minf(338.0, size.x - 24.0)
	var height := 128.0
	var position := Vector2(22, 47)
	if is_hover:
		position = get_node_screen_position(id) + Vector2(55, -90)
		if position.x + width > size.x - 14:
			position.x = get_node_screen_position(id).x - width - 55
		position.x = clampf(position.x, 12, maxf(12, size.x - width - 12))
		position.y = clampf(position.y, 12, maxf(12, size.y - height - 125))
	var rect := Rect2(position, Vector2(width, height))
	_preview_box.border_color = Color(_category_color(preview["category"]), 0.42)
	draw_style_box(_preview_box, rect)
	_draw_text(String(preview["title"]), position + Vector2(16, 28), 21, Palette.PAPER)
	_draw_text("第 %d 折点  ·  威胁 %d" % [int(preview["depth"]) + 1, int(preview["risk"])], position + Vector2(16, 52), 14, Palette.GOLD)
	_draw_text(String(preview["reward"]), position + Vector2(16, 79), 15, Palette.MUTED)
	_draw_text(String(preview["status"]), position + Vector2(16, 109), 14, Palette.FOLD if bool(preview["reachable"]) else Palette.MUTED)


func _draw_text(text: String, position: Vector2, font_size: int, color: Color) -> void:
	draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _category_color(category: StringName) -> Color:
	match category:
		&"combat", &"elite": return Palette.DANGER
		&"boss", &"cache", &"shop": return Palette.GOLD
		&"event": return Palette.PAPER
		_: return Palette.FOLD


func _category_title(category: StringName) -> String:
	match category:
		&"entry": return "入潮口"
		&"combat": return "交锋房"
		&"elite": return "高压房"
		&"boss": return "终潮庭"
		&"rest": return "静水泊"
		&"shop": return "漂灯市"
		&"forge": return "折纸坊"
		&"cache": return "藏光室"
		&"event": return "异潮室"
		_: return "无名折点"
