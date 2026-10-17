class_name FoldlightTheme
extends RefCounted

## Shared paper-and-sea vocabulary for every game mode.
## Cyan marks folded light, gold marks life, coral marks danger.
const INK := Color("091923")
const SURFACE := Color("112d38")
const SURFACE_SOFT := Color("173844")
const PAPER := Color("e6e4d5")
const MUTED := Color("91a6a7")
const FOLD := Color("77d5c6")
const GOLD := Color("d7af70")
const DANGER := Color("e08072")
const WEB_FONT: FontFile = preload("res://assets/fonts/FoldlightSansSC.woff2")


static func build() -> Theme:
	var result := Theme.new()
	result.default_font_size = 22
	result.default_font = body_font()
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", PAPER)
	result.set_color("font_pressed_color", "Button", FOLD)
	result.set_color("font_focus_color", "Button", PAPER)
	result.set_color("font_disabled_color", "Button", Color(MUTED, 0.45))
	result.set_font_size("font_size", "Button", 23)
	result.set_stylebox("normal", "Button", button_style(false))
	result.set_stylebox("hover", "Button", button_style(true))
	result.set_stylebox("pressed", "Button", button_style(true))
	result.set_stylebox("focus", "Button", focus_style())
	result.set_stylebox("disabled", "Button", button_style(false))
	result.set_stylebox("panel", "PanelContainer", panel_style())
	result.set_stylebox("background", "ProgressBar", bar_style(Color(INK, 0.84)))
	result.set_stylebox("fill", "ProgressBar", bar_style(FOLD))
	result.set_color("font_color", "ProgressBar", PAPER)
	result.set_font_size("font_size", "ProgressBar", 16)
	var separator := StyleBoxLine.new()
	separator.color = Color(MUTED, 0.20)
	separator.thickness = 1
	result.set_stylebox("separator", "HSeparator", separator)
	result.set_constant("separation", "HSeparator", 18)
	result.set_type_variation("PrimaryButton", "Button")
	result.set_font_size("font_size", "PrimaryButton", 28)
	result.set_stylebox("normal", "PrimaryButton", primary_style(false))
	result.set_stylebox("hover", "PrimaryButton", primary_style(true))
	result.set_stylebox("pressed", "PrimaryButton", primary_style(true))
	result.set_color("font_color", "PrimaryButton", PAPER)
	result.set_type_variation("FoldlightMenuButton", "Button")
	result.set_stylebox("normal", "FoldlightMenuButton", menu_style(false))
	result.set_stylebox("hover", "FoldlightMenuButton", menu_style(true))
	result.set_stylebox("pressed", "FoldlightMenuButton", menu_style(true))
	result.set_type_variation("QuietButton", "Button")
	result.set_font_size("font_size", "QuietButton", 19)
	result.set_color("font_color", "QuietButton", MUTED)
	result.set_stylebox("normal", "QuietButton", quiet_style(false))
	result.set_stylebox("hover", "QuietButton", quiet_style(true))
	result.set_stylebox("pressed", "QuietButton", quiet_style(true))
	return result


static func body_font() -> Font:
	# Browsers cannot enumerate or load installed system fonts. Ship Chinese
	# glyphs with the game while retaining the existing native desktop face.
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return WEB_FONT
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Segoe UI", "Microsoft YaHei UI", "Noto Sans CJK SC"])
	return body


static func display_font() -> Font:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return WEB_FONT
	var face := SystemFont.new()
	face.font_names = PackedStringArray(["Bahnschrift", "Aptos Display", "Segoe UI"])
	face.font_weight = 300
	return face


static func button_style(hovered: bool) -> StyleBoxFlat:
	var box := _box(Color(SURFACE_SOFT if hovered else SURFACE, 0.96), 22.0, 14.0)
	box.border_color = Color(FOLD, 0.65 if hovered else 0.22)
	box.set_border_width_all(1)
	return box


static func primary_style(hovered: bool) -> StyleBoxFlat:
	var box := _box(Color("24514f") if hovered else Color("183d40"), 28.0, 16.0)
	box.border_color = Color(FOLD, 0.85 if hovered else 0.55)
	box.border_width_left = 4
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	return box


static func menu_style(hovered: bool) -> StyleBoxFlat:
	var box := _box(Color(SURFACE, 0.72) if hovered else Color.TRANSPARENT, 28.0, 8.0)
	box.border_color = Color(FOLD if hovered else MUTED, 0.56 if hovered else 0.18)
	box.border_width_bottom = 1
	return box


static func quiet_style(hovered: bool) -> StyleBoxFlat:
	return _box(Color(SURFACE, 0.65) if hovered else Color.TRANSPARENT, 10.0, 9.0)


static func focus_style() -> StyleBoxFlat:
	var box := _box(Color.TRANSPARENT, 0.0, 0.0)
	box.border_color = FOLD
	box.set_border_width_all(2)
	box.set_expand_margin_all(4.0)
	return box


static func panel_style() -> StyleBoxFlat:
	var box := _box(Color(SURFACE, 0.96), 28.0, 24.0)
	box.border_color = Color(MUTED, 0.23)
	box.set_border_width_all(1)
	box.shadow_color = Color(INK, 0.38)
	box.shadow_size = 12
	return box


static func bar_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(1)
	return box


static func comfort_accent(source: Color) -> Color:
	if source.a <= 0.0:
		return source
	var saturation_cap := 0.64
	var value_cap := 0.84
	if source.h >= 0.70 and source.h <= 0.92:
		saturation_cap = 0.44
		value_cap = 0.72
	elif source.h >= 0.035 and source.h <= 0.14:
		saturation_cap = 0.58
		value_cap = 0.80
	return Color.from_hsv(source.h, minf(source.s, saturation_cap), minf(source.v, value_cap), source.a)


static func _box(background: Color, horizontal_margin: float, vertical_margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(2)
	box.content_margin_left = horizontal_margin
	box.content_margin_right = horizontal_margin
	box.content_margin_top = vertical_margin
	box.content_margin_bottom = vertical_margin
	return box
