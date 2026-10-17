extends Control
## The same combat data, condensed above the two dedicated thumb zones.
signal pause_requested
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const WEAPON_ARSENAL = preload("res://scripts/roguelite/ui/weapon_arsenal_strip.gd")
var health: Label
var voyage: Label
var fold: Label
var status: Label
var boss: Label
var objective: Label
var health_bar: ProgressBar
var focus_bar: ProgressBar
var charge_bar: ProgressBar
var boss_bar: ProgressBar
var pause_button: Button
var arsenal: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health = _text(Vector2(44, 130), Vector2(340, 48), 38, Palette.GOLD)
	health_bar = _bar(Rect2(44, 184, 340, 12), Palette.GOLD)
	voyage = _text(Vector2(420, 130), Vector2(920, 44), 32, Palette.PAPER)
	arsenal = WEAPON_ARSENAL.new()
	arsenal.name = "MobileWeaponArsenal"
	arsenal.position = voyage.position
	arsenal.size = Vector2(voyage.size.x, 58)
	add_child(arsenal)
	status = _text(Vector2(1380, 130), Vector2(340, 44), 32, Palette.FOLD)
	fold = _text(Vector2(44, 212), Vector2(540, 44), 34, Palette.PAPER)
	focus_bar = _bar(Rect2(44, 263, 380, 12), Palette.FOLD)
	charge_bar = _bar(Rect2(44, 283, 380, 10), Palette.GOLD)
	boss = _text(Vector2(620, 212), Vector2(1080, 44), 32, Palette.GOLD)
	boss_bar = _bar(Rect2(620, 264, 1080, 12), Palette.FOLD)
	objective = _text(Vector2(620, 212), Vector2(1080, 76), 32, Palette.GOLD)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_button = Button.new()
	pause_button.name = "TouchPauseButton"
	pause_button.text = "暂停"
	pause_button.position = Vector2(1756, 130)
	pause_button.custom_minimum_size = Vector2(120, 120)
	pause_button.size = Vector2(120, 120)
	pause_button.add_theme_font_size_override("font_size", 34)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	add_child(pause_button)
	apply_safe_area(Vector4.ZERO)

func apply_safe_area(insets: Vector4) -> void:
	if health == null: return
	var left := 44.0 + insets.x
	var right := 44.0 + insets.z
	var width := get_viewport_rect().size.x
	for node: Control in [health, health_bar, fold, focus_bar, charge_bar]:
		node.position.x = left
	pause_button.position.x = width - right - 120.0
	status.position.x = pause_button.position.x - 376.0
	status.size.x = 340.0
	voyage.position.x = left + 376.0
	voyage.size.x = maxf(200.0, status.position.x - voyage.position.x - 32.0)
	# This is the existing voyage slot, ending before the navigation task panel.
	# Adding another HUD row below it would cover the task or the minimap.
	arsenal.position = voyage.position
	arsenal.size = Vector2(voyage.size.x, 58)
	for node: Control in [boss, boss_bar, objective]:
		node.position.x = left + 576.0
		node.size.x = maxf(300.0, pause_button.position.x - node.position.x - 44.0)

func update_from(source: Node) -> void:
	for child in get_children(): child.show()
	health.text = source._hud_health.text
	health.add_theme_color_override("font_color", source._hud_health.get_theme_color("font_color"))
	health_bar.max_value = source._hud_health_bar.max_value
	health_bar.value = source._hud_health_bar.value
	voyage.text = source._hud_region.text + "  ·  " + source._hud_room.text
	voyage.hide()
	arsenal.configure(source._hud_inventory, source._hud_resonance, true)
	# The first line reports current pressure; the secondary evolution count
	# belongs to the result screen and must not spill under the task panel.
	status.text = source._hud_status.text.get_slice("\n", 0)
	fold.text = source._hud_fold.text.replace("折域  ·  ", "").replace("折域回折  ", "回折 ")
	focus_bar.value = source._hud_focus_bar.value
	charge_bar.value = source._hud_charge_bar.value
	charge_bar.visible = source._hud_charge_row.visible
	boss.text = source._boss_label.text
	boss.visible = source._boss_label.visible
	boss_bar.visible = boss.visible
	boss_bar.max_value = source._boss_bar.max_value
	boss_bar.value = source._boss_bar.value
	objective.visible = source._hud_objective.visible
	objective.text = source._hud_objective.text + "  " + source._hud_objective_detail.text
	pause_button.visible = not bool(source._hud_context.get("race", false))


func set_tutorial_mode(active: bool) -> void:
	if active:
		for child in get_children():
			if child != pause_button: child.hide()

func _text(point: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var value := Label.new()
	value.position = point
	value.size = extent
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	value.add_theme_color_override("font_outline_color", Palette.INK)
	value.add_theme_constant_override("outline_size", 6)
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(value)
	return value

func _bar(rect: Rect2, color: Color) -> ProgressBar:
	var value := ProgressBar.new()
	value.position = rect.position
	value.size = rect.size
	value.show_percentage = false
	value.step = 0.0
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_theme_stylebox_override("background", Palette.bar_style(Color(Palette.INK, 0.9)))
	value.add_theme_stylebox_override("fill", Palette.bar_style(color))
	add_child(value)
	return value
