extends Control
const SkillArt = preload("res://scripts/roguelite/ui/active_skill_art.gd")
var _id: StringName = &""
var _accent: Color = FoldlightTheme.GOLD

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(30, 30)

func configure(id: StringName, accent: Color) -> void:
	if id == _id and accent == _accent: return
	_id = id
	_accent = accent
	queue_redraw()

func _draw() -> void:
	SkillArt.draw_icon(self, _id, size * 0.5, 13, _accent)
