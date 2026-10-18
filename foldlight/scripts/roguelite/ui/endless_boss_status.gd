extends Control
## One read-only rail for the shared desktop/mobile HUD. No independent clock:
## warnings and health freeze with the authoritative combat snapshot.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const MAX_BARS := 6
var _director: Dictionary = {}
var _bosses: Array[Dictionary] = []
var _mobile := false
var _font: Font = Palette.body_font()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(director: Dictionary, bosses: Array, mobile: bool) -> void:
	visible = not director.is_empty()
	var next: Array[Dictionary] = []
	for item: Variant in bosses:
		if not item is Dictionary or bool(item.get("defeated", false)): continue
		if float(item.get("health", 0.0)) <= 0.0: continue
		next.append(item.duplicate(true))
		if next.size() == MAX_BARS: break
	if _director == director and _bosses == next and _mobile == mobile: return
	_director = director.duplicate(true)
	_bosses = next
	_mobile = mobile
	queue_redraw()

func layout_in_viewport(view_size: Vector2, touch: Dictionary = {}) -> void:
	var row_count := ceili(float(_bosses.size()) / 2.0) if _bosses.size() > 3 else _bosses.size()
	var height := (44.0 + row_count * 44.0) if _mobile else (36.0 + row_count * 36.0)
	if _mobile:
		var insets: Vector4 = touch.get("safe_insets", Vector4.ZERO)
		var left := Vector2(touch.get("move", Vector2(245 + insets.x, 0))).x + float(touch.get("move_radius", 124)) + 32
		var right := Vector2(touch.get("dash", Vector2(view_size.x - 455 - insets.z, 0))).x - float(touch.get("dash_radius", 79)) - 32
		var width := minf(920, maxf(1, right - left))
		size = Vector2(width, height)
		position = Vector2((left + right - width) * 0.5, view_size.y - maxf(24, insets.w + 24) - height)
	else:
		size = Vector2(780, height)
		position = Vector2(690, 238)

func get_display_snapshot() -> Dictionary:
	return {"director": _director.duplicate(true), "bosses": _bosses.duplicate(true),
		"header": _header(), "visible": visible, "mobile": _mobile, "rect": get_global_rect(),
		"rows": _bosses.size(), "columns": 2 if _bosses.size() > 3 else 1,
		"grid_rows": ceili(float(_bosses.size()) / 2.0) if _bosses.size() > 3 else _bosses.size(),
		"health_values": _bosses.map(func(b: Dictionary) -> Vector2: return Vector2(float(b.get("health", 0)), float(b.get("maximum_health", 1))))}

func _header() -> String:
	# Director tiers start at zero; the player sees the first difficulty as one.
	var tier := maxi(0, int(_director.get("difficulty_tier", 0))) + 1
	var state := StringName(_director.get("state", &"idle"))
	var next_level := maxi(1, int(_director.get("next_level", 8)))
	if state in [&"warning", &"ready"]:
		var count := maxi(1, int(_director.get("warning_count", 1)))
		var title := "%d只首领来袭" % count if count > 1 else str(_director.get("title", "首领来袭"))
		return "%s · %.1f秒 · 保持移动" % [title, maxf(0, float(_director.get("warning_remaining", 0)))]
	var lockdown: Dictionary = _director.get("lockdown", {})
	if not _bosses.is_empty():
		if StringName(lockdown.get("state", &"idle")) == &"approach":
			return "围猎封锁 %d秒 · 击破首领解除" % ceili(float(lockdown.get("remaining", 90)))
		if StringName(lockdown.get("state", &"idle")) == &"warning":
			return "围猎 %d秒后封圈 · 返回红色边界内" % ceili(float(lockdown.get("remaining", 8)))
		if StringName(lockdown.get("state", &"idle")) == &"active":
			return "围猎封锁 · 圈外每2秒扣1格血"
	if _bosses.size() >= maxi(1, int(_director.get("capacity", MAX_BARS))):
		return "难度 %d · 下波 Lv.%d · 先击破首领" % [tier, next_level]
	return "难度 %d · 下波首领 Lv.%d%s" % [tier, next_level, " · 在场 %d 只" % _bosses.size() if not _bosses.is_empty() else ""]

func _draw() -> void:
	if _director.is_empty(): return
	var warning := StringName(_director.get("state", &"idle")) in [&"warning", &"ready"]
	var accent := Palette.DANGER if warning else Palette.GOLD
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.86 if not _bosses.is_empty() else 0.66))
	draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(accent, 0.65), 2, true)
	# A folded tip carries the warning colour, avoiding another screen-wide banner.
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(12, 0), Vector2(0, 12)]), accent)
	var header_font := 30 if _mobile else 22
	var header_y := 32.0 if _mobile else 27.0
	draw_string(_font, Vector2(16, header_y), _header(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, header_font, accent)
	var row_height := 44.0 if _mobile else 36.0
	var start := 44.0 if _mobile else 36.0
	var columns := 2 if _bosses.size() > 3 else 1
	var cell_width := size.x / float(columns)
	for index in _bosses.size():
		var boss := _bosses[index]
		var current := maxf(0, float(boss.get("health", 0)))
		var maximum := maxf(1, float(boss.get("maximum_health", 1)))
		var name_text := str(boss.get("title", "首领"))
		var hp_text := "%d / %d" % [ceili(current), ceili(maximum)]
		var mirror: Dictionary = boss.get("mirror", {})
		if bool(mirror.get("folding", false)):
			hp_text = "收纳 %d/%d" % [int(mirror.get("captured", 0)), int(mirror.get("capacity", 8))]
		elif float(mirror.get("release_remaining", 0.0)) > 0.0:
			hp_text = "返光 %.1fs" % float(mirror.release_remaining)
		var row_y := start + int(index / columns) * row_height
		var row_x := (index % columns) * cell_width
		var font_size := (26 if _mobile else 18) if columns == 2 else (30 if _mobile else 22)
		var hp_width := _font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(_font, Vector2(row_x + 16, row_y + 27), name_text, HORIZONTAL_ALIGNMENT_LEFT, cell_width - hp_width - 42, font_size, Palette.PAPER)
		draw_string(_font, Vector2(row_x + cell_width - hp_width - 16, row_y + 27), hp_text, HORIZONTAL_ALIGNMENT_LEFT, hp_width, font_size, Palette.MUTED)
		var track := Rect2(row_x + 16, row_y + row_height - 7, cell_width - 32, 4)
		draw_rect(track, Color(Palette.PAPER, 0.12))
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(current / maximum, 0, 1), 4)), Palette.DANGER)
