extends Control
## One inventory view for both modes. Mobile keeps the same symbols and levels,
## while the pause sheet carries the full names and combat roles.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")

var _inventory: Array[Dictionary] = []
var _resonance: Dictionary = {}
var _mobile := false
var _flash := 0.0
var _flash_tween: Tween
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Palette.body_font()
	resized.connect(queue_redraw)
	visibility_changed.connect(_on_visibility_changed)


func configure(inventory: Array[Dictionary], resonance: Dictionary, mobile: bool = false) -> void:
	var just_activated := bool(resonance.get("active", false)) and not bool(_resonance.get("active", false))
	_inventory = inventory.duplicate(true)
	_resonance = resonance.duplicate(true)
	_mobile = mobile
	var lines := PackedStringArray()
	for entry: Dictionary in _inventory:
		lines.append("%s Lv.%d · %s" % [entry.get("title", ""), int(entry.get("level", 1)), entry.get("role", "")])
	lines.append("累计返还 8 枚收纳的弹幕，所有自动武器共鸣 3 秒：伤害与攻速 +20%。")
	tooltip_text = "\n".join(lines)
	if just_activated and is_visible_in_tree():
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash = 1.0
		_flash_tween = create_tween()
		_flash_tween.tween_method(_set_flash, 1.0, 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	queue_redraw()


func get_display_snapshot() -> Dictionary:
	return {"inventory": _inventory.duplicate(true), "resonance": _resonance.duplicate(true), "mobile": _mobile, "rect": get_global_rect()}


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash = 0.0


func _draw() -> void:
	if _font == null or size.x <= 0:
		return
	var active := bool(_resonance.get("active", false))
	var accent := Palette.GOLD if active else Palette.FOLD
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.GOLD, _flash * 0.09))
	var charge := int(_resonance.get("charge", 0))
	var required := maxi(1, int(_resonance.get("required", 8)))
	var remaining := float(_resonance.get("remaining", 0.0))
	var ratio := clampf(remaining / maxf(0.01, float(_resonance.get("duration", 3.0))), 0.0, 1.0) if active else clampf(float(charge) / required, 0.0, 1.0)
	if _mobile:
		_draw_mobile(accent, active, charge, required, remaining, ratio)
	else:
		_draw_desktop(accent, active, charge, required, remaining, ratio)


func _draw_desktop(accent: Color, active: bool, charge: int, required: int, remaining: float, _ratio: float) -> void:
	var column := size.x / 3.0
	for index in mini(6, _inventory.size()):
		var entry := _inventory[index]
		var center := Vector2(column * (index % 3) + 14.0, 17.0 + 31.0 * floori(float(index) / 3.0))
		var color := Palette.comfort_accent(Color(entry.get("accent", Palette.FOLD)))
		_draw_symbol(StringName(entry.get("id", &"")), center, 10.0, color)
		draw_string(_font, center + Vector2(20, 7), "%s L%d" % [entry.get("title", ""), int(entry.get("level", 1))], HORIZONTAL_ALIGNMENT_LEFT, column - 40.0, 19, Palette.PAPER)
	var text := "共鸣 %.1fs · 伤害 / 攻速 +20%%" % remaining if active else "返光共鸣 %d / %d" % [charge, required]
	draw_string(_font, Vector2(0, size.y - 11), text, HORIZONTAL_ALIGNMENT_LEFT, size.x, 16, accent)


func _draw_mobile(accent: Color, active: bool, charge: int, required: int, remaining: float, ratio: float) -> void:
	var meter_width := 200.0
	var column := maxf(1.0, (size.x - meter_width - 18.0) / 6.0)
	for index in mini(6, _inventory.size()):
		var entry := _inventory[index]
		var color := Palette.comfort_accent(Color(entry.get("accent", Palette.FOLD)))
		var center := Vector2(column * index + 18, 23)
		_draw_symbol(StringName(entry.get("id", &"")), center, 16.0, color)
		draw_string(_font, center + Vector2(24, 11), "L%d" % int(entry.get("level", 1)), HORIZONTAL_ALIGNMENT_LEFT, column - 43, 32, Palette.PAPER)
	var start := size.x - meter_width
	var text := "共鸣 %.1fs" % remaining if active else "返光 %d/%d" % [charge, required]
	draw_string(_font, Vector2(start, 32), text, HORIZONTAL_ALIGNMENT_LEFT, meter_width, 29, accent)
	_draw_meter(Rect2(start, 45, meter_width, 5), ratio, accent)


func _draw_meter(rect: Rect2, ratio: float, accent: Color) -> void:
	draw_rect(rect, Color(Palette.INK, 0.82))
	if ratio > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), accent)


func _draw_symbol(id: StringName, center: Vector2, radius: float, color: Color) -> void:
	match id:
		&"needle_orbit":
			draw_arc(center, radius * 0.75, 0, TAU, 18, color, 2.0, true)
			for index in 3:
				var direction := Vector2.from_angle(float(index) * TAU / 3.0)
				draw_line(center + direction * radius * 0.4, center + direction * radius * 1.15, color, 2.0, true)
		&"returning_gull":
			draw_polyline(PackedVector2Array([center + Vector2(-radius, -radius * 0.5), center + Vector2(0, radius * 0.3), center + Vector2(radius, -radius * 0.5)]), color, 3.0, true)
			draw_line(center + Vector2(0, radius * 0.3), center + Vector2(0, radius), color, 2.0, true)
		&"tide_bell":
			draw_arc(center + Vector2(0, radius * 0.2), radius * 0.85, PI, TAU, 14, color, 2.0, true)
			draw_line(center + Vector2(-radius, radius * 0.35), center + Vector2(radius, radius * 0.35), color, 2.0, true)
			draw_circle(center + Vector2(0, radius * 0.75), radius * 0.17, color)
		&"prism_fan":
			for index in 3:
				var angle := -PI * 0.5 + (index - 1) * 0.7
				draw_line(center + Vector2(0, radius * 0.8), center + Vector2.from_angle(angle) * radius, color, 2.5, true)
		&"sun_thread":
			draw_line(center + Vector2(-radius, radius), center + Vector2(radius, -radius), color, 3.0, true)
			draw_circle(center, radius * 0.28, Palette.PAPER)
		_:
			var diamond := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.65, 0), center + Vector2(0, radius), center + Vector2(-radius * 0.65, 0), center + Vector2(0, -radius)])
			draw_colored_polygon(diamond, Color(color, 0.25))
			draw_polyline(diamond, color, 2.0, true)
