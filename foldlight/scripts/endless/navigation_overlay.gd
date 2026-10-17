class_name FoldlightEndlessNavigationOverlay
extends Control
## Read-only projection of the endless adapter's authoritative world snapshot.
## No independent clock: pause, rewards and race waiting freeze with the source.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const REWARD_FEEDBACK = preload("res://scripts/roguelite/ui/reward_feedback_text.gd")

class MapGeometry extends Control:
	var walls: Array[PackedVector2Array] = []
	var corridors: Array[Rect2] = []
	var refuges: PackedVector2Array = []
	var draw_count := 0
	func _draw() -> void:
		draw_count += 1
		for rect in corridors:
			draw_rect(rect, Color(Palette.FOLD, 0.10))
		for polygon in walls:
			if polygon.size() < 3: continue
			draw_colored_polygon(polygon, Palette.SURFACE_SOFT.lightened(0.12))
			var border := polygon.duplicate()
			border.append(border[0])
			draw_polyline(border, Color(Palette.PAPER, 0.58), 1.5, true)
		for point in refuges:
			draw_circle(point, 4.0, Palette.FOLD)

class MapMarkers extends Control:
	var surface: Control
	func _draw() -> void:
		if is_instance_valid(surface): surface.draw_markers(self)

class MapSurface extends Control:
	signal toggled
	var snapshot: Dictionary = {}
	var bounds := Rect2(0, 0, 1, 1)
	var chart := Rect2()
	var mobile := false
	var expanded := false
	var geometry: MapGeometry
	var markers: MapMarkers
	var geometry_key := ""
	var rebuild_count := 0
	var title_label: Label
	var footer: Label
	var _font: Font
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_font = Palette.body_font()
		geometry = MapGeometry.new()
		geometry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(geometry)
		markers = MapMarkers.new()
		markers.surface = self
		markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(markers)
		title_label = Label.new()
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_label.add_theme_color_override("font_color", Palette.PAPER)
		add_child(title_label)
		footer = Label.new()
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_theme_color_override("font_color", Palette.MUTED)
		add_child(footer)
		resized.connect(_rebuild_geometry)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed and not event.canceled:
			toggled.emit()
			accept_event()
		elif event is InputEventMouseButton:
			# A raw touch has already toggled the map. Its emulated mouse cannot
			# toggle again, and no global combat action is synthesized.
			if event.device == InputEvent.DEVICE_ID_EMULATION:
				accept_event()
			elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				toggled.emit()
				accept_event()
	func configure(value: Dictionary, touch: bool, large: bool) -> void:
		snapshot = value
		bounds = value.get("bounds", Rect2(0, 0, 1, 1))
		mobile = touch
		expanded = large
		var next_key := "%s:%s:%s:%s:%s" % [value.get("map_id", ""), value.get("layout_revision", 0), bounds, size, expanded]
		if geometry_key != next_key:
			geometry_key = next_key
			_rebuild_geometry()
		title_label.text = "%s · 收起地图" % str(value.get("map_title", "全域地图")) if expanded else "%s  ↗" % str(value.get("map_title", "全域地图"))
		title_label.add_theme_font_size_override("font_size", 32 if mobile else 20)
		title_label.position = Vector2(14, 7)
		title_label.size = Vector2(maxf(1, size.x - 28), 44 if mobile else 30)
		footer.text = "战斗继续 · 青开 / 金警 / 红关" if mobile else "战斗继续 · 青色开放 / 金色预警 / 珊瑚关闭"
		footer.add_theme_font_size_override("font_size", 32 if mobile else 20)
		footer.position = Vector2(18, size.y - 44)
		footer.size = Vector2(maxf(1, size.x - 36), 40)
		footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		footer.visible = expanded
		queue_redraw()
		markers.queue_redraw()
	func project(point: Vector2) -> Vector2:
		return chart.position + (point - bounds.position) * (chart.size / bounds.size)
	func project_rect(rect: Rect2) -> Rect2:
		return Rect2(project(rect.position), rect.size * (chart.size / bounds.size))
	func zone_patches(rect: Rect2) -> Array[Rect2]:
		# Always-open corridors carve the exact same holes in the warning/closed
		# projection as they do in the runtime's exposure check.
		var parts: Array[Rect2] = [rect]
		for corridor: Rect2 in geometry.corridors:
			var next: Array[Rect2] = []
			for part in parts:
				var cut := part.intersection(corridor)
				if not cut.has_area():
					next.append(part)
					continue
				for piece: Rect2 in [Rect2(part.position, Vector2(part.size.x, cut.position.y - part.position.y)),
					Rect2(Vector2(part.position.x, cut.end.y), Vector2(part.size.x, part.end.y - cut.end.y)),
					Rect2(Vector2(part.position.x, cut.position.y), Vector2(cut.position.x - part.position.x, cut.size.y)),
					Rect2(Vector2(cut.end.x, cut.position.y), Vector2(part.end.x - cut.end.x, cut.size.y))]:
					if piece.has_area(): next.append(piece)
			parts = next
		return parts
	func _rebuild_geometry() -> void:
		if geometry == null or size.x <= 1 or size.y <= 1 or bounds.size.x <= 0 or bounds.size.y <= 0: return
		var inset := Rect2(Vector2(14, 52 if mobile else 38), Vector2(maxf(1, size.x - 28), maxf(1, size.y - (104 if expanded else 64) if mobile else size.y - (86 if expanded else 50))))
		var scale_factor := minf(inset.size.x / bounds.size.x, inset.size.y / bounds.size.y)
		chart = Rect2(inset.get_center() - bounds.size * scale_factor * 0.5, bounds.size * scale_factor)
		geometry.walls.clear()
		geometry.corridors.clear()
		geometry.refuges.clear()
		for obstacle: Variant in snapshot.get("obstacles", []):
			var polygon := PackedVector2Array()
			if obstacle is Rect2:
				var rect: Rect2 = obstacle
				polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			elif obstacle is PackedVector2Array:
				polygon = obstacle
			var projected := PackedVector2Array()
			for point in polygon: projected.append(project(point))
			if projected.size() >= 3: geometry.walls.append(projected)
		for corridor: Rect2 in snapshot.get("safe_corridors", []): geometry.corridors.append(project_rect(corridor))
		for refuge: Vector2 in snapshot.get("refuges", []): geometry.refuges.append(project(refuge))
		rebuild_count += 1
		geometry.queue_redraw()
		if markers != null: markers.queue_redraw()
		queue_redraw()
	func _draw() -> void:
		if chart.size.x <= 0 or chart.size.y <= 0: return
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.92))
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(Palette.FOLD, 0.35), false, 1.5)
		draw_rect(chart, Color(Palette.SURFACE, 0.94))
		var clock := float(snapshot.get("combat_time", 0.0))
		var motion := clampf(float(snapshot.get("motion_scale", 1.0)), 0.0, 1.0)
		for zone: Dictionary in snapshot.get("zones", []):
			var state := StringName(zone.get("state", &"open"))
			var rect := project_rect(zone.get("rect", Rect2())).intersection(chart)
			if not rect.has_area(): continue
			var color := Palette.FOLD if state == &"open" else (Palette.GOLD if state == &"warning" else Palette.DANGER)
			var pulse := (0.5 + sin(clock * 4.0) * 0.5) * motion if state == &"warning" else 0.0
			for part: Rect2 in zone_patches(rect):
				draw_rect(part, Color(color, (0.07 if state == &"open" else 0.23) + pulse * 0.10))
				draw_rect(part, Color(color, 0.80 if state != &"open" else 0.22), false, 2.0)
				if state == &"closed":
					draw_line(part.position, part.end, Color(color, 0.55), 2.0, true)
					draw_line(Vector2(part.end.x, part.position.y), Vector2(part.position.x, part.end.y), Color(color, 0.55), 2.0, true)
	func draw_markers(canvas: CanvasItem) -> void:
		if chart.size.x <= 0 or chart.size.y <= 0: return
		var camera: Rect2 = snapshot.get("camera_rect", Rect2())
		if camera.has_area(): canvas.draw_rect(project_rect(camera).intersection(chart), Color(Palette.PAPER, 0.50), false, 1.0)
		var objective: Dictionary = snapshot.get("objective", {})
		for target: Dictionary in objective.get("targets", []):
			if bool(target.get("active", false)) or bool(target.get("completed", false)):
				var point := project(target.get("position", bounds.get_center()))
				canvas.draw_circle(point, 5, Palette.MUTED if bool(target.get("completed", false)) else Palette.GOLD)
		if bool(objective.get("target_active", false)):
			var point := project(objective.get("target_position", bounds.get_center()))
			var diamond := PackedVector2Array([point + Vector2(0, -10), point + Vector2(10, 0), point + Vector2(0, 10), point + Vector2(-10, 0), point + Vector2(0, -10)])
			canvas.draw_polyline(diamond, Palette.GOLD, 3, true)
		var danger: Dictionary = snapshot.get("danger", {})
		if StringName(danger.get("state", &"safe")) in [&"warning", &"closed"] and danger.get("safe_position") is Vector2:
			var safe := project(danger["safe_position"])
			canvas.draw_circle(safe, 11, Color(Palette.FOLD, 0.22))
			canvas.draw_arc(safe, 10, 0, TAU, 16, Palette.FOLD, 2.0, true)
		var player := project(snapshot.get("player_position", bounds.get_center()))
		canvas.draw_circle(player, 10, Palette.INK)
		canvas.draw_circle(player, 6, Palette.PAPER)

var _snapshot: Dictionary = {}
var _objective_feedback: Dictionary = {}
var _mobile := false
var _safe_top := 150.0
var _expanded := false
var _hud_visible := true
var _map: MapSurface
var _task: PanelContainer
var _task_title: Label
var _task_time: Label
var _task_instruction: Label
var _task_progress: Label
var _task_bar: ProgressBar
var _danger: Label
var _indicator_text: Label
var _indicator_point := Vector2.ZERO
var _indicator_direction := Vector2.ZERO
var _indicator_color := Palette.GOLD
var _indicator_kind: StringName = &""

func _ready() -> void:
	name = "EndlessNavigation"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map = MapSurface.new()
	_map.name = "NavigationMap"
	_map.toggled.connect(_toggle_map)
	add_child(_map)
	_task = PanelContainer.new()
	_task.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Palette.panel_style()
	style.bg_color = Color(Palette.INK, 0.88)
	style.border_color = Color(Palette.GOLD, 0.35)
	style.set_content_margin_all(0)
	_task.add_theme_stylebox_override("panel", style)
	add_child(_task)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_task.add_child(content)
	_task_title = _label(content, 26, Palette.GOLD)
	_task_time = _label(content, 24, Palette.PAPER)
	_task_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_task_instruction = _label(content, 21, Palette.PAPER)
	_task_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_instruction.max_lines_visible = 2
	_task_progress = _label(content, 21, Palette.MUTED)
	_task_bar = ProgressBar.new()
	_task_bar.show_percentage = false
	_task_bar.step = 0.0
	_task_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_task_bar.add_theme_stylebox_override("background", Palette.bar_style(Palette.SURFACE))
	_task_bar.add_theme_stylebox_override("fill", Palette.bar_style(Palette.GOLD))
	content.add_child(_task_bar)
	_danger = _label(self, 26, Palette.DANGER)
	_danger.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator_text = _label(self, 26, Palette.GOLD)
	_indicator_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_layout)
	_layout()
	set_process(false)

func update_snapshot(value: Dictionary) -> void:
	var bounds: Rect2 = value.get("bounds", Rect2())
	if not bounds.has_area():
		_snapshot = {}
		hide()
		return
	_snapshot = value.duplicate(true)
	visible = _hud_visible
	if not is_node_ready(): return
	_refresh_task()
	_map.configure(_snapshot, _mobile, _expanded)
	_refresh_indicator()
	queue_redraw()

func set_touch_layout(enabled: bool, safe_top: float = 150.0) -> void:
	_mobile = enabled
	_safe_top = maxf(0, safe_top)
	if is_node_ready(): _layout()

func set_objective_feedback(value: Dictionary) -> void:
	if _objective_feedback == value: return
	_objective_feedback = value.duplicate(true)
	if is_node_ready() and not _snapshot.is_empty(): _refresh_task()

func set_hud_visible(enabled: bool) -> void:
	_hud_visible = enabled
	visible = enabled and not _snapshot.is_empty()
	if not enabled and _expanded:
		_expanded = false
		if is_node_ready(): _layout()

func get_navigation_snapshot() -> Dictionary:
	var objective: Dictionary = _snapshot.get("objective", {})
	var zone_counts := {"open": 0, "warning": 0, "closed": 0}
	for zone: Dictionary in _snapshot.get("zones", []):
		var state := str(zone.get("state", "open"))
		if zone_counts.has(state): zone_counts[state] += 1
	return {"mobile": _mobile, "expanded": _expanded, "map_rect": _map.get_global_rect() if _map else Rect2(),
		"task_rect": _task.get_global_rect() if _task else Rect2(), "map_bounds": _map.bounds if _map else Rect2(),
		"map_title": str(_snapshot.get("map_title", "")), "zone_counts": zone_counts,
		"objective_id": objective.get("id", &""), "objective_kind": objective.get("kind", &""),
		"status": objective.get("status", &""), "target_active": bool(objective.get("target_active", false)),
		"progress": objective.get("progress", 0), "required": objective.get("required", 0),
		"chart_rect": _map.chart if _map else Rect2(), "geometry_rebuilds": _map.rebuild_count if _map else 0,
		"wall_count": _map.geometry.walls.size() if _map and _map.geometry else 0,
		"task_title": _task_title.text if _task_title else "", "progress_text": _task_progress.text if _task_progress else "",
		"instruction_text": _task_instruction.text if _task_instruction else "", "objective_feedback": _objective_feedback.duplicate(true),
		"time_text": _task_time.text if _task_time else "", "danger_text": _danger.text if _danger else "",
		"indicator_kind": _indicator_kind, "indicator_mode": _indicator_kind, "indicator_direction": _indicator_direction, "indicator_position": _indicator_point,
		"player_map_position": _map.project(_snapshot.get("player_position", _map.bounds.position)) if _map and not _snapshot.is_empty() else Vector2.ZERO}

func _toggle_map() -> void:
	if not is_visible_in_tree() or not _hud_visible: return
	_expanded = not _expanded
	_layout()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and _expanded:
		_expanded = false
		_layout()

func _layout() -> void:
	if _map == null: return
	if _mobile:
		_map.position = Vector2(600, _safe_top + 362) if _expanded else Vector2(44, _safe_top + 170)
		_map.size = Vector2(720, 380) if _expanded else Vector2(360, maxf(120, minf(200, 560 - _map.position.y)))
		_task.position = Vector2(560, _safe_top + 64)
		_task.size = Vector2(1150, 112)
		_danger.position = Vector2(560, _safe_top + 186)
		_danger.size = Vector2(1150, 76)
		var touch := get_node_or_null("/root/TouchControls")
		var insets: Vector4 = touch.get_layout_snapshot().get("safe_insets", Vector4.ZERO) if touch != null else Vector4.ZERO
		if not _expanded: _map.position.x += insets.x
		_task.position.x = maxf(560.0, insets.x + 416.0)
		_task.size.x = minf(1150.0, get_viewport_rect().size.x - insets.z - 44.0 - _task.position.x)
		_danger.position.x = _task.position.x
		_danger.size.x = _task.size.x
	else:
		_map.position = Vector2(700, 240) if _expanded else Vector2(1510, 150)
		_map.size = Vector2(1130, 600) if _expanded else Vector2(366, 245)
		_task.position = Vector2(44, 150)
		_task.size = Vector2(620, 194)
		_danger.position = Vector2(680, 150)
		_danger.size = Vector2(800, 76)
	_danger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_danger.max_lines_visible = 2
	var width := _task.size.x
	_task_title.position = Vector2(16, 6 if _mobile else 10)
	_task_title.size = Vector2(width - (182 if _mobile else 166), 44)
	_task_time.position = Vector2(width - 154, 6 if _mobile else 10)
	_task_time.size = Vector2(138, 44)
	_task_instruction.position = Vector2(16, 48 if _mobile else 58)
	_task_instruction.size = Vector2(width - 32, 40 if _mobile else 62)
	_task_instruction.max_lines_visible = 1 if _mobile else 2
	_task_progress.position = Vector2(16, 90 if _mobile else 130)
	_task_progress.size = Vector2(width - 32, 40)
	_task_progress.visible = not _mobile
	_task_bar.position = Vector2(16, _task.size.y - 16)
	_task_bar.size = Vector2(width - 32, 7)
	for label in [_task_title, _task_time, _task_instruction, _task_progress, _danger, _indicator_text]:
		label.add_theme_font_size_override("font_size", 32 if _mobile else (26 if label in [_task_title, _danger, _indicator_text] else 21))
	if not _snapshot.is_empty():
		_refresh_task()
		_map.configure(_snapshot, _mobile, _expanded)
		_refresh_indicator()
	queue_redraw()

func _refresh_task() -> void:
	var objective: Dictionary = _snapshot.get("objective", {})
	var state := StringName(objective.get("status", &"active"))
	var prefix := "任务"
	if state == &"completed": prefix = "任务完成"
	elif state == &"failed": prefix = "任务超时"
	elif state == &"intermission": prefix = "下一任务"
	_task_title.text = "%s · %s" % [prefix, str(objective.get("title", "准备中"))]
	_task_title.add_theme_color_override("font_color", Palette.DANGER if state == &"failed" else (Palette.FOLD if state == &"completed" else Palette.GOLD))
	_task_time.text = "%d 秒" % ceili(maxf(0, float(objective.get("time_remaining", 0)))) if state == &"active" else "已完成" if state == &"completed" else "未达成" if state == &"failed" else "准备中"
	_task_instruction.text = str(objective.get("instruction", "留意下一道任务指引。"))
	if _mobile and state == &"active":
		match StringName(objective.get("kind", &"")):
			&"capture_point": _task_instruction.text = "圈内驻守；每返4弹助燃2秒，最多6秒。"
			&"defeat_captain": _task_instruction.text = "沿金色指引击破金冠队长；普通敌人不计。"
			&"destroy_flag": _task_instruction.text = "靠近红金火力旗，用自动攻击或返光摧毁。"
			&"relay_route": _task_instruction.text = "依次抵达三个信标，每站驻留 1.2 秒。"
			&"capture_storm": _task_instruction.text = "青圈内按住收纳 12 发敌弹；圈外不计。"
			&"clear_swarm": _task_instruction.text = "任意海域击破 10 名敌人；火力旗不计。"
	var progress := maxf(0, float(objective.get("progress", 0)))
	var required := maxf(0.001, float(objective.get("required", 1)))
	_task_progress.text = str(objective.get("progress_text", "%s / %s" % [String.num(progress, 1), String.num(required, 1)]))
	if _mobile and state == &"active":
		# Keep full progress in the shared snapshot; only the mobile heading gets
		# a short count so the facility has more room beneath the two-line HUD.
		var compact := "%d/%d" % [int(progress), int(required)]
		match StringName(objective.get("kind", &"")):
			&"capture_point": compact = "%.1f/%.0f秒" % [progress, required]
			&"relay_route": compact = "%d/%d站 · %.1f/1.2秒" % [int(progress), int(required), float(objective.get("waypoint_hold", 0.0))]
			&"destroy_flag": compact = "%.0f/%.0f" % [progress, required]
		_task_title.text += "  " + compact
	_task_bar.value = clampf(progress / required, 0, 1) * 100
	if state in [&"failed", &"completed", &"intermission"]:
		var next_seconds := ceili(maxf(0, float(objective.get("intermission_remaining", 0))))
		_task_time.text = "%d 秒" % next_seconds if next_seconds > 0 else "准备中"
		var next_hint := "%d 秒后出现新目标" % next_seconds if next_seconds > 0 else "新目标准备中"
		_task_instruction.text = ("本次无奖励 · " if state == &"failed" else "继续航行 · ") + next_hint
		_task_progress.text = "无需操作，下一任务自动出现。"
	var feedback_source := StringName(_objective_feedback.get("source", &""))
	if feedback_source in [&"mission", &"kill_level"]:
		var mission := feedback_source == &"mission"
		_task_title.text = "任务完成 · %s" % str(_objective_feedback.get("title", objective.get("title", ""))) if mission else "击破升级 · Lv.%d" % maxi(1, int(_objective_feedback.get("level", 1)))
		_task_title.add_theme_color_override("font_color", Palette.FOLD if mission else Palette.GOLD)
		_task_time.text = "待领奖" if mission else "待强化"
		_task_instruction.text = "任务补给即将展开" if mission else "成长奖励即将展开"
		var heal_hint := REWARD_FEEDBACK.heal_on_claim(_objective_feedback)
		if not heal_hint.is_empty(): _task_instruction.text += " · " + heal_hint
		_task_progress.text = "选择一项任务奖励，继续航行。" if mission else "当前任务保留，选择强化后继续。"
		if mission: _task_bar.value = 100.0
	var danger: Dictionary = _snapshot.get("danger", {})
	var danger_state := StringName(danger.get("state", &"safe"))
	var global_warning := false
	for zone: Dictionary in _snapshot.get("zones", []):
		if StringName(zone.get("state", &"open")) == &"warning": global_warning = true
	_danger.visible = danger_state in [&"warning", &"closed"] or global_warning
	var fallback := "金色预警区即将关闭，请留意航路"
	if danger_state == &"closed": fallback = "此处已关闭，正在扣血 · 沿青色方向撤离"
	elif danger_state == &"warning": fallback = "此处 %d 秒后关闭 · 沿青色方向撤离" % ceili(maxf(0, float(danger.get("seconds_remaining", 0))))
	_danger.text = str(danger.get("message", fallback))
	_danger.add_theme_color_override("font_color", Palette.DANGER if danger_state == &"closed" else Palette.GOLD)

func _refresh_indicator() -> void:
	_indicator_kind = &""
	_indicator_text.hide()
	if _expanded: return
	var player: Vector2 = _snapshot.get("player_position", Vector2.ZERO)
	var target := player
	var danger: Dictionary = _snapshot.get("danger", {})
	var objective: Dictionary = _snapshot.get("objective", {})
	if StringName(danger.get("state", &"safe")) in [&"warning", &"closed"] and danger.get("safe_position") is Vector2:
		target = danger["safe_position"]
		_indicator_kind = &"safe"
		_indicator_color = Palette.FOLD
	elif bool(objective.get("target_active", false)) and objective.get("target_position") is Vector2:
		target = objective["target_position"]
		var camera_rect: Rect2 = _snapshot.get("camera_rect", Rect2())
		if camera_rect.has_point(target): return
		_indicator_kind = &"objective"
		_indicator_color = Palette.GOLD
	else: return
	var delta := target - player
	if delta.length_squared() <= 1:
		_indicator_kind = &""
		return
	_indicator_direction = delta.normalized()
	var center := Vector2(960, maxf(680, _safe_top + 470) if _mobile else 550)
	var extent := Vector2(250, 100) if _mobile else Vector2(650, 270)
	var factor := minf(extent.x / maxf(absf(_indicator_direction.x), 0.001), extent.y / maxf(absf(_indicator_direction.y), 0.001))
	_indicator_point = center + _indicator_direction * factor
	# The adapter may provide the first safe-path waypoint around a wall, rather
	# than the final refuge. Describe that direction without promising immunity.
	_indicator_text.text = "%s · 距离 %d" % ["撤离航点" if _indicator_kind == &"safe" else "任务目标", roundi(delta.length())]
	_indicator_text.position = _indicator_point + Vector2(-160, 34)
	if _mobile: _indicator_text.position.x = clampf(_indicator_text.position.x, 600, 1000)
	_indicator_text.size = Vector2(320, 44)
	_indicator_text.add_theme_color_override("font_color", _indicator_color)
	_indicator_text.show()

func _draw() -> void:
	if _indicator_kind.is_empty() or not _hud_visible: return
	var direction := _indicator_direction
	var side := direction.orthogonal()
	var tip := _indicator_point + direction * 25
	var tail := _indicator_point - direction * 20
	draw_circle(_indicator_point, 34, Color(Palette.INK, 0.72))
	draw_colored_polygon(PackedVector2Array([tip, tail + side * 15, _indicator_point - direction * 8, tail - side * 15]), _indicator_color)

func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Palette.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Palette.INK)
	label.add_theme_constant_override("outline_size", 4)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label
