class_name FoldlightRogueUITheme

## A deliberately small semantic palette.  Cyan is reserved for actions and
## reflectable light; gold is reserved for life, rewards and danger.
const INK := Color(0.012, 0.022, 0.042, 0.98)
const SURFACE := Color(0.022, 0.044, 0.064, 0.95)
const SURFACE_SOFT := Color(0.030, 0.060, 0.076, 0.86)
const PAPER := Color(0.84, 0.90, 0.87, 1.0)
const MUTED := Color(0.49, 0.61, 0.62, 1.0)
const FOLD := Color(0.34, 0.78, 0.74, 1.0)
const GOLD := Color(0.84, 0.61, 0.32, 1.0)
const DANGER := Color(0.86, 0.37, 0.31, 1.0)


## Keeps authored region identity while preventing large purple/orange UI and
## briefing surfaces from becoming tiring during long survival sessions.
static func comfort_accent(source: Color) -> Color:
	if source.a <= 0.0:
		return source
	var hue := source.h
	var saturation_cap := 0.64
	var value_cap := 0.84
	if hue >= 0.70 and hue <= 0.92:
		saturation_cap = 0.44
		value_cap = 0.72
	elif hue >= 0.035 and hue <= 0.14:
		saturation_cap = 0.58
		value_cap = 0.80
	return Color.from_hsv(hue, minf(source.s, saturation_cap), minf(source.v, value_cap), source.a)


static func bar_style(color: Color) -> StyleBoxFlat:
	return _bar_box(color)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 24
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.62))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_font_size("font_size", "Button", 24)
	theme.set_stylebox("normal", "Button", _button_box(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.82), Color(0.17, 0.34, 0.38, 0.66), 2))
	theme.set_stylebox("hover", "Button", _button_box(Color(SURFACE_SOFT.r, SURFACE_SOFT.g, SURFACE_SOFT.b, 0.98), Color(FOLD.r, FOLD.g, FOLD.b, 0.82), 3))
	theme.set_stylebox("pressed", "Button", _button_box(Color(0.05, 0.20, 0.20, 0.96), FOLD, 4))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_stylebox("disabled", "Button", _button_box(Color(0.025, 0.035, 0.055, 0.64), Color(0.25, 0.30, 0.34, 0.48), 1))
	theme.set_color("font_disabled_color", "Button", Color(0.38, 0.44, 0.47, 0.9))
	theme.set_stylebox("panel", "PanelContainer", _panel_box())
	theme.set_stylebox("background", "ProgressBar", _bar_box(Color(0.018, 0.032, 0.058, 0.82)))
	theme.set_stylebox("fill", "ProgressBar", _bar_box(FOLD))
	theme.set_color("font_color", "ProgressBar", PAPER)
	theme.set_font_size("font_size", "ProgressBar", 17)
	return theme


static func _button_box(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = border_width + 2
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 12
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 12
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 11.0
	box.content_margin_bottom = 11.0
	return box


static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = FOLD
	box.set_border_width_all(3)
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 14
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 14
	box.expand_margin_left = 5.0
	box.expand_margin_top = 5.0
	box.expand_margin_right = 5.0
	box.expand_margin_bottom = 5.0
	return box


static func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = Color(0.26, 0.70, 0.68, 0.45)
	box.border_width_left = 2
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 2
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 20
	box.corner_radius_bottom_left = 20
	box.corner_radius_bottom_right = 4
	box.content_margin_left = 28.0
	box.content_margin_top = 24.0
	box.content_margin_right = 28.0
	box.content_margin_bottom = 24.0
	return box


static func _bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	return box
