class_name FoldlightRewardCard
extends Button

## A reward stays a Button so keyboard navigation and upgrade metadata retain
## the same contract. Only its visual surface moves inside the stable hit area.
signal selection_confirmed(upgrade_id: StringName)

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const CONFIRM_SECONDS: float = 0.20

var title_label: Label
var description_label: Label
var rarity_label: Label
var level_label: Label
var _action_label: Label
var _content: Control
var _accent: Color = Palette.FOLD
var _symbol: StringName = &"prism"
var _content_id: StringName = &""
var _slot: int = 0
var _clock: float = 0.0
var _reveal: float = 1.0
var _attention: float = 0.0
var _confirm: float = 0.0
var _dim: float = 1.0
var _hovered: bool = false
var _locked: bool = false
var _confirming: bool = false
var _entrance_tween: Tween
var _attention_tween: Tween
var _confirm_tween: Tween
var _dim_tween: Tween
var _touch_layout := false


func set_touch_layout(enabled: bool) -> void:
	_touch_layout = enabled
	custom_minimum_size = Vector2(550, 710) if enabled else Vector2(420, 520)
	for pair: Array in [[title_label, 40, 31], [description_label, 34, 21], [rarity_label, 32, 18], [level_label, 30, 17], [_action_label, 32, 18]]:
		(pair[0] as Label).add_theme_font_size_override("font_size", pair[1] if enabled else pair[2])
	_update_content_layout()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(420, 520)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_build_content()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_refresh_attention)
	focus_exited.connect(_refresh_attention)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_update_content_layout)
	set_process(false)


func configure(choice: Dictionary, index: int) -> void:
	cancel_motion()
	_slot = index
	_clock = float(index) * 1.7
	_content_id = StringName(choice.get("content_id", &""))
	set_meta("upgrade_id", _content_id)
	_accent = Palette.comfort_accent(Color(choice.get("accent", Palette.FOLD)))
	_symbol = _resolve_symbol(choice)
	title_label.text = str(choice.get("title", "无名折痕"))
	description_label.text = str(choice.get("description", ""))
	rarity_label.text = str(choice.get("display_rarity", "折痕"))
	rarity_label.add_theme_color_override("font_color", _accent.lightened(0.14))
	level_label.text = "刻印  %d / %d" % [int(choice.get("next_level", 1)), int(choice.get("maximum_level", 1))]
	_action_label.text = "刻下折痕  →"
	tooltip_text = "%s：%s" % [title_label.text, description_label.text]
	_locked = false
	_confirming = false
	_hovered = false
	_attention = 0.0
	_confirm = 0.0
	_dim = 1.0
	disabled = false
	_update_content_layout()
	queue_redraw()


func reveal(delay: float = 0.0) -> void:
	_kill(_entrance_tween)
	_set_reveal(0.0)
	set_process(is_visible_in_tree())
	_entrance_tween = _motion()
	_entrance_tween.tween_interval(delay)
	_entrance_tween.tween_method(_set_reveal, 0.0, 1.0, 0.36)
	_refresh_attention()


func set_selection_available(available: bool) -> void:
	if _locked or _confirming:
		return
	disabled = not available
	_action_label.text = "刻下折痕  →" if available else "细看折痕…"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW


func confirm_selection() -> bool:
	if _locked or _confirming or disabled or not is_visible_in_tree() or _content_id.is_empty():
		return false
	_confirming = true
	_locked = true
	_kill(_entrance_tween)
	_set_reveal(1.0)
	_kill(_attention_tween)
	_attention = 1.0
	_action_label.text = "折痕已刻下"
	_kill(_confirm_tween)
	_confirm_tween = _motion()
	_confirm_tween.tween_method(_set_confirm, 0.0, 1.0, CONFIRM_SECONDS)
	_confirm_tween.tween_callback(_finish_confirmation)
	return true


func lock_choice(selected: bool) -> void:
	_locked = true
	disabled = true
	if not selected:
		_kill(_attention_tween)
		_kill(_dim_tween)
		_dim_tween = _motion()
		_dim_tween.tween_method(_set_dim, _dim, 0.40, CONFIRM_SECONDS)


func cancel_motion() -> void:
	_kill(_entrance_tween)
	_kill(_attention_tween)
	_kill(_confirm_tween)
	_kill(_dim_tween)
	_confirming = false
	_locked = true
	disabled = true
	set_process(false)


func get_presentation_snapshot() -> Dictionary:
	return {"content_id": _content_id, "symbol": _symbol, "reveal": _reveal,
		"attention": _attention, "confirming": _confirming, "locked": _locked}


func _process(delta: float) -> void:
	_clock += minf(delta, 0.10)
	queue_redraw()


func _draw() -> void:
	if _content == null or _reveal <= 0.001:
		return
	var opacity := _reveal * _dim
	var lift := _surface_offset()
	draw_set_transform(Vector2(0, lift))
	var w := size.x
	var h := size.y
	var cut := 24.0
	var shape := PackedVector2Array([Vector2.ZERO, Vector2(w - cut, 0), Vector2(w, cut), Vector2(w, h), Vector2(0, h)])
	var shadow := shape.duplicate()
	for index in shadow.size():
		shadow[index] += Vector2(0, 10.0 + _attention * 8.0)
	draw_colored_polygon(shadow, Color(Palette.INK, 0.65 * opacity))
	var base := Palette.SURFACE.lerp(Palette.SURFACE_SOFT, _attention * 0.65)
	draw_colored_polygon(shape, Color(base, opacity * 0.98))
	# A thin paper edge and a turned corner give the card an actual material.
	draw_polyline(PackedVector2Array([Vector2(0, h), Vector2.ZERO, Vector2(w - cut, 0), Vector2(w, cut), Vector2(w, h), Vector2(0, h)]), Color(_accent, (0.30 + _attention * 0.48) * opacity), 1.3, true)
	draw_colored_polygon(PackedVector2Array([Vector2(w - cut, 0), Vector2(w - cut, cut), Vector2(w, cut)]), Color(_accent, (0.16 + _attention * 0.12) * opacity))
	draw_line(Vector2(30, 260), Vector2(w - 30, 260), Color(_accent, 0.20 * opacity), 1.0, true)
	draw_line(Vector2(30, h - 78), Vector2(w - 30, h - 78), Color(Palette.MUTED, 0.16 * opacity), 1.0, true)
	_draw_paper_grain(w, h, opacity)
	var emblem_center := Vector2(w * 0.5, 154.0 + sin(_clock * 1.1) * 3.0)
	_draw_emblem_field(emblem_center, opacity)
	_draw_symbol(emblem_center, 1.0 + _attention * 0.045 + sin(_confirm * PI) * 0.055, opacity)
	if _attention > 0.001:
		var flow := fposmod(_clock * 0.28, 1.0)
		var start := Vector2(30 + flow * (w - 100), 260)
		draw_line(start, start + Vector2(42, 0), Color(_accent, _attention * 0.78 * opacity), 2.0, true)
	if _confirm > 0.0:
		var flare := sin(_confirm * PI)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.PAPER, flare * 0.08 * opacity))
		draw_arc(emblem_center, 83.0 + _confirm * 28.0, -PI, PI, 72, Color(Palette.PAPER, (1.0 - _confirm) * opacity), 2.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_paper_grain(w: float, h: float, opacity: float) -> void:
	for index in 17:
		var x := 20.0 + fposmod(float(index * 83 + _slot * 23), w - 45.0)
		var y := 24.0 + fposmod(float(index * 137), h - 50.0)
		draw_line(Vector2(x, y), Vector2(x + 4.0, y - 1.0), Color(Palette.PAPER, 0.045 * opacity), 1.0)


func _draw_emblem_field(center: Vector2, opacity: float) -> void:
	var diamond := PackedVector2Array([center + Vector2(0, -98), center + Vector2(112, 0), center + Vector2(0, 98), center + Vector2(-112, 0), center + Vector2(0, -98)])
	draw_polyline(diamond, Color(_accent, (0.10 + _attention * 0.06) * opacity), 1.0, true)
	draw_arc(center, 87, -PI * 0.85, PI * 0.15, 40, Color(_accent, 0.15 * opacity), 1, true)
	for index in 3:
		var angle := _clock * 0.10 + float(index) * TAU / 3.0
		var point := center + Vector2.from_angle(angle) * (91.0 + index * 5.0)
		draw_circle(point, 1.6, Color(_accent, (0.25 + _attention * 0.28) * opacity))


func _draw_symbol(center: Vector2, scale_factor: float, opacity: float) -> void:
	var light := Palette.PAPER.lerp(_accent, 0.20)
	var middle := _accent.lerp(Palette.PAPER, 0.10)
	var shade := _accent.darkened(0.44)
	match _symbol:
		&"wings":
			_facet(center, scale_factor, [Vector2(-90, -48), Vector2(-8, -18), Vector2(-24, 55)], light, opacity)
			_facet(center, scale_factor, [Vector2(-90, -48), Vector2(-24, 55), Vector2(-48, 4)], middle, opacity)
			_facet(center, scale_factor, [Vector2(90, -48), Vector2(8, -18), Vector2(24, 55)], middle, opacity)
			_facet(center, scale_factor, [Vector2(90, -48), Vector2(24, 55), Vector2(48, 4)], shade, opacity)
			_facet(center, scale_factor, [Vector2(0, -60), Vector2(13, 4), Vector2(0, 72), Vector2(-13, 4)], light, opacity)
		&"lantern":
			_facet(center, scale_factor, [Vector2(0, -78), Vector2(49, -22), Vector2(35, 48), Vector2(0, 76)], light, opacity)
			_facet(center, scale_factor, [Vector2(0, -78), Vector2(-49, -22), Vector2(-35, 48), Vector2(0, 76)], shade, opacity)
			_facet(center, scale_factor, [Vector2(0, -48), Vector2(22, -13), Vector2(0, 43), Vector2(-22, -13)], middle, opacity)
			draw_line(center + Vector2(-35, 48) * scale_factor, center + Vector2(35, 48) * scale_factor, Color(Palette.GOLD, opacity), 2, true)
		&"spark":
			_facet(center, scale_factor, [Vector2(-17, -79), Vector2(55, -29), Vector2(8, -1), Vector2(25, 80), Vector2(-49, 17), Vector2(-4, -12)], middle, opacity)
			_facet(center, scale_factor, [Vector2(-17, -79), Vector2(8, -1), Vector2(55, -29)], light, opacity)
			_facet(center, scale_factor, [Vector2(-49, 17), Vector2(8, -1), Vector2(25, 80)], shade, opacity)
		&"seal":
			_facet(center, scale_factor, [Vector2(-59, -62), Vector2(42, -62), Vector2(59, -43), Vector2(59, 62), Vector2(-59, 62)], light, opacity)
			_facet(center, scale_factor, [Vector2(-59, -62), Vector2(0, 7), Vector2(-59, 62)], shade, opacity)
			_facet(center, scale_factor, [Vector2(59, -43), Vector2(0, 7), Vector2(59, 62)], middle, opacity)
			_facet(center, scale_factor, [Vector2(0, -30), Vector2(22, 0), Vector2(0, 36), Vector2(-22, 0)], _accent.darkened(0.30), opacity)
		&"orbit":
			for index in 6:
				var angle := float(index) * TAU / 6.0 + PI / 6.0
				var a := Vector2.from_angle(angle) * 74
				var b := Vector2.from_angle(angle + 0.67) * 68
				var inner := Vector2.from_angle(angle + 0.4) * 35
				_facet(center, scale_factor, [a, b, inner], light if index % 2 == 0 else middle, opacity)
			draw_circle(center, 8, Color(Palette.GOLD, opacity))
		_:
			_facet(center, scale_factor, [Vector2(0, -82), Vector2(-62, -2), Vector2(0, 78)], shade, opacity)
			_facet(center, scale_factor, [Vector2(0, -82), Vector2(62, -2), Vector2(0, 78)], light, opacity)
			_facet(center, scale_factor, [Vector2(0, -82), Vector2(-25, -5), Vector2(0, 30), Vector2(25, -5)], middle, opacity)
			_facet(center, scale_factor, [Vector2(-62, -2), Vector2(0, 30), Vector2(0, 78)], _accent, opacity)


func _facet(center: Vector2, scale_factor: float, points: Array[Vector2], color: Color, opacity: float) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(center + point * scale_factor)
	var shadow := polygon.duplicate()
	for index in shadow.size():
		shadow[index] += Vector2(3, 5)
	draw_colored_polygon(shadow, Color(Palette.INK, opacity * 0.32))
	draw_colored_polygon(polygon, Color(color, opacity))
	draw_line(polygon[0], polygon[1], Color(Palette.PAPER, opacity * 0.35), 1.0, true)


func _resolve_symbol(choice: Dictionary) -> StringName:
	var id := String(choice.get("content_id", ""))
	var kind := StringName(choice.get("choice_kind", &"upgrade"))
	# Weapon and active-item drafts can contain three entries of the same kind;
	# their authored identities still need different silhouettes.
	var authored: Dictionary = {
		"crease_lantern": &"lantern", "needle_orbit": &"orbit", "returning_gull": &"wings",
		"tide_bell": &"seal", "prism_fan": &"prism", "sun_thread": &"spark",
		"paper_burst": &"spark", "mirror_step": &"wings", "ink_wash": &"lantern",
		"crease_anchor": &"seal", "tide_clock": &"orbit", "sun_stamp": &"prism",
	}
	if authored.has(id):
		return StringName(authored[id])
	if kind == &"weapon" or bool(choice.get("offensive", false)):
		return &"spark"
	if kind == &"active":
		return &"orbit"
	if id.contains("burden") or id.contains("curse") or id.contains("contract"):
		return &"seal"
	if id.contains("step") or id.contains("wing") or id.contains("dash") or id.contains("kinetic") or id.contains("silhouette"):
		return &"wings" if not id.contains("silhouette") else &"prism"
	if id.contains("lantern") or id.contains("health") or id.contains("heal") or id.contains("steady") or id.contains("heart"):
		return &"lantern"
	if id.contains("return") or id.contains("surge") or id.contains("fire") or id.contains("sharp"):
		return &"spark"
	if id.contains("current") or id.contains("focus") or id.contains("echo"):
		return &"orbit"
	return &"prism"


func _build_content() -> void:
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	rarity_label = _label(18, _accent)
	rarity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label = _label(31, Palette.PAPER)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description_label = _label(21, Palette.MUTED)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_label = _label(17, Palette.MUTED)
	_action_label = _label(18, Palette.PAPER)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_update_content_layout()


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)
	return label


func _update_content_layout() -> void:
	if _content == null:
		return
	_content.position = Vector2(0, _surface_offset())
	_content.size = size
	_content.modulate.a = _reveal * _dim
	var width := maxf(1.0, size.x - 64)
	rarity_label.position = Vector2(32, 25)
	rarity_label.size = Vector2(width, 28)
	title_label.position = Vector2(32, 281)
	title_label.size = Vector2(width, 45)
	description_label.position = Vector2(32, 337)
	description_label.size = Vector2(width, maxf(80.0, size.y - 425))
	level_label.position = Vector2(32, size.y - 57)
	level_label.size = Vector2(130, 28)
	_action_label.position = Vector2(170, size.y - 57)
	_action_label.size = Vector2(maxf(1, size.x - 202), 28)
	if _touch_layout:
		rarity_label.size.y = 44
		title_label.size.y = 60
		description_label.position.y = 352
		description_label.size.y = maxf(150, size.y - 450)
		level_label.position.y = size.y - 62
		level_label.size = Vector2(210, 44)
		_action_label.position = Vector2(250, size.y - 62)
		_action_label.size = Vector2(maxf(1, size.x - 282), 44)


func _surface_offset() -> float:
	return (1.0 - _reveal) * 32.0 - _attention * 8.0 - sin(_confirm * PI) * 4.0


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_attention()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_attention()


func _refresh_attention() -> void:
	if _locked or not is_visible_in_tree():
		return
	_kill(_attention_tween)
	_attention_tween = _motion()
	_attention_tween.tween_method(_set_attention, _attention, 1.0 if (_hovered or has_focus()) else 0.0, 0.18)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		cancel_motion()


func _finish_confirmation() -> void:
	if _confirming and is_visible_in_tree():
		_confirming = false
		selection_confirmed.emit(_content_id)


func _set_reveal(value: float) -> void:
	_reveal = value
	_update_content_layout()
	queue_redraw()


func _set_attention(value: float) -> void:
	_attention = value
	_update_content_layout()
	queue_redraw()


func _set_confirm(value: float) -> void:
	_confirm = value
	_update_content_layout()
	queue_redraw()


func _set_dim(value: float) -> void:
	_dim = value
	_update_content_layout()
	queue_redraw()


func _motion() -> Tween:
	return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
