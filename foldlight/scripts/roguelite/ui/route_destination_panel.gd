extends VBoxContainer
## One continuous field note, with native labels and launch controls supplied by
## the presentation. The illustration never changes the selectable hit areas.

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const Landmark = preload("res://scripts/roguelite/ui/route_landmark.gd")

class Illustration extends Control:
	var category: StringName = &"combat"
	var phase: float = 0.0
	var motion_scale: float = 1.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visibility_changed.connect(func() -> void: set_process(is_visible_in_tree() and motion_scale > 0.0))
	func _process(delta: float) -> void:
		if not is_visible_in_tree() or motion_scale <= 0.0: return
		phase += minf(delta, 0.1) * motion_scale
		queue_redraw()
	func _draw() -> void:
		var center := size * Vector2(0.5, 0.59)
		var color := Landmark.color_for(category)
		for line in 3:
			var y := center.y + 20 + float(line) * 13
			draw_polyline(PackedVector2Array([Vector2(10, y + 8), Vector2(size.x * 0.35, y), Vector2(size.x * 0.70, y + 4), Vector2(size.x - 10, y - 5)]), Color(color, 0.09 - float(line) * 0.02), 1, true)
		var island := PackedVector2Array([center + Vector2(-102, 8), center + Vector2(-56, -13), center + Vector2(54, -18), center + Vector2(108, 11), center + Vector2(29, 37), center + Vector2(-65, 31)])
		draw_colored_polygon(island, Palette.SURFACE_SOFT.lerp(color, 0.13))
		draw_colored_polygon(PackedVector2Array([island[0], island[1], island[2], center]), Palette.SURFACE_SOFT.lerp(color, 0.24))
		var outline := island.duplicate()
		outline.append(island[0])
		draw_polyline(outline, Color(color, 0.39), 1.2, true)
		Landmark.draw(self, center - Vector2(0, 12 + sin(phase * 1.4) * 2 * motion_scale), category, 1.25)

var title_label: Label
var body_label: Label
var status_label: Label
var reward_label: Label
var risk_label: Label
var context_label: Label
var illustration: Illustration
var _snapshot: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	context_label = _label("", 18, Palette.GOLD)
	add_child(context_label)
	illustration = Illustration.new()
	illustration.custom_minimum_size.y = 148
	add_child(illustration)
	title_label = _label("", 29, Palette.PAPER)
	add_child(title_label)
	status_label = _label("", 16, Palette.FOLD)
	add_child(status_label)
	body_label = _label("", 19, Palette.MUTED)
	body_label.custom_minimum_size.y = 76
	add_child(body_label)
	risk_label = _label("", 18, Palette.DANGER)
	add_child(risk_label)
	var divider := HSeparator.new()
	add_child(divider)
	add_child(_label("澄清所得", 15, Palette.MUTED))
	reward_label = _label("", 23, Palette.GOLD)
	add_child(reward_label)


func configure(preview: Dictionary, context: Dictionary) -> void:
	_snapshot = preview.duplicate(true)
	title_label.text = str(preview.get("title", "无名折点"))
	status_label.text = str(preview.get("status", "目前仅可查看"))
	status_label.add_theme_color_override("font_color", Palette.FOLD if bool(preview.get("reachable", false)) else Palette.MUTED)
	body_label.text = str(preview.get("description", ""))
	var waves := int(preview.get("waves", 0))
	risk_label.text = "威胁 %d  ·  %s" % [int(preview.get("risk", 1)), "%d 波敌潮" % waves if waves > 0 else "首领战"]
	reward_label.text = str(preview.get("reward", "一道局内强化"))
	context_label.text = "灯芯 %d / %d     微光 %d" % [int(context.get("health", 0)), int(context.get("max_health", 0)), int(context.get("glimmer", 0))] if context.has("health") else "看清下一站，再启航。"
	illustration.category = StringName(preview.get("category", &"combat"))
	illustration.motion_scale = clampf(float(context.get("motion_scale", 1.0)), 0.0, 1.0)
	illustration.set_process(illustration.is_visible_in_tree() and illustration.motion_scale > 0.0)
	illustration.queue_redraw()


func get_preview_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
