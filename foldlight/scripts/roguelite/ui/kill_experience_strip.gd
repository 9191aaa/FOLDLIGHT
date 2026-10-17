extends Control
## Read-only kill growth. No UI clock or interpolated gameplay values.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
var _snapshot: Dictionary = {}
var _mobile := false
var _font: Font = Palette.body_font()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(snapshot: Dictionary, mobile: bool = false) -> void:
	visible = not snapshot.is_empty()
	if _snapshot == snapshot and _mobile == mobile: return
	_snapshot = snapshot.duplicate(true)
	_mobile = mobile
	queue_redraw()

func get_display_snapshot() -> Dictionary:
	return {"experience": _snapshot.duplicate(true), "mobile": _mobile,
		"title": _title(), "guidance": _guidance(), "visible": visible}

func _title() -> String:
	var level := maxi(1, int(_snapshot.get("level", 1)))
	var xp := maxi(0, int(_snapshot.get("xp_in_level", 0)))
	var required := maxi(1, int(_snapshot.get("xp_to_next", 1)))
	var pending := maxi(0, int(_snapshot.get("pending_levels", 0)))
	if _mobile:
		return "Lv.%d · 待领%d次升级" % [level, pending] if pending > 0 else "Lv.%d %d/%d · 击破升级" % [level, xp, required]
	return "击破成长 · Lv.%d    经验 %d / %d" % [level, xp, required]

func _guidance() -> String:
	var pending := maxi(0, int(_snapshot.get("pending_levels", 0)))
	if pending > 0: return "已获得 %d 次升级 · 将依次选择强化" % pending
	return "再获得 %d 经验升级 · 击破敌人积累" % maxi(0, int(_snapshot.get("xp_to_next", 1)) - int(_snapshot.get("xp_in_level", 0)))

func _draw() -> void:
	if _snapshot.is_empty(): return
	var title := _title()
	var font_size := 30 if _mobile else 23
	while font_size > 26 and _mobile and _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
		font_size -= 1
	draw_string_outline(_font, Vector2(0, 32 if _mobile else 24), title, HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size, 5, Palette.INK)
	draw_string(_font, Vector2(0, 32 if _mobile else 24), title, HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size, Palette.PAPER)
	var track := Rect2(0, 48 if _mobile else 36, size.x, 7 if _mobile else 6)
	draw_rect(track, Color(Palette.INK, 0.92))
	var ratio := clampf(float(_snapshot.get("xp_in_level", 0)) / maxf(1, float(_snapshot.get("xp_to_next", 1))), 0, 1)
	var fill := Rect2(track.position, Vector2(track.size.x * ratio, track.size.y))
	draw_rect(fill, Palette.GOLD)
	if not _mobile:
		draw_string(_font, Vector2(0, 67), _guidance(), HORIZONTAL_ALIGNMENT_LEFT, size.x, 18, Palette.MUTED)
