class_name FoldlightRogueUITheme
extends RefCounted

## Compatibility entry point for existing roguelite scenes and resources.
## Palette and widget styling are owned by the shared game theme.
const SharedTheme = preload("res://scripts/ui/foldlight_theme.gd")
const INK := SharedTheme.INK
const SURFACE := SharedTheme.SURFACE
const SURFACE_SOFT := SharedTheme.SURFACE_SOFT
const PAPER := SharedTheme.PAPER
const MUTED := SharedTheme.MUTED
const FOLD := SharedTheme.FOLD
const GOLD := SharedTheme.GOLD
const DANGER := SharedTheme.DANGER


static func build() -> Theme:
	return SharedTheme.build()


static func bar_style(color: Color) -> StyleBoxFlat:
	return SharedTheme.bar_style(color)


static func comfort_accent(source: Color) -> Color:
	return SharedTheme.comfort_accent(source)
