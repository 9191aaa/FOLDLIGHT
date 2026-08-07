class_name FoldlightRegionOnePixelDemo
extends Control

signal room_state_changed(room_state: StringName)
signal exit_requested

const DESIGN_SIZE := Vector2(640.0, 360.0)
const STATE_STANDARD: StringName = &"standard_room"
const STATE_BOSS: StringName = &"boss_room"
const WATER_TILE_PATH := "res://assets/demos/pixel/paper_reef_water_tile.png"
const TERRAIN_ATLAS_PATH := "res://assets/demos/pixel/paper_reef_terrain_atlas.png"
const ACTOR_ATLAS_PATH := "res://assets/demos/pixel/paper_reef_actor_atlas.png"
const ATLAS_GRID := Vector2i(3, 2)

const STANDARD_TERRAIN_LAYOUT: Array[Dictionary] = [
	{"cell": 0, "rect": Rect2(20, 45, 210, 92)},
	{"cell": 1, "rect": Rect2(438, 42, 182, 86)},
	{"cell": 2, "rect": Rect2(48, 238, 150, 102)},
	{"cell": 3, "rect": Rect2(454, 232, 158, 110)},
	{"cell": 4, "rect": Rect2(242, 258, 144, 86)},
	{"cell": 5, "rect": Rect2(218, 72, 210, 76)},
]
const BOSS_TERRAIN_LAYOUT: Array[Dictionary] = [
	{"cell": 0, "rect": Rect2(8, 48, 250, 102)},
	{"cell": 1, "rect": Rect2(382, 46, 250, 104)},
	{"cell": 2, "rect": Rect2(12, 246, 188, 100)},
	{"cell": 3, "rect": Rect2(438, 242, 190, 104)},
	{"cell": 4, "rect": Rect2(248, 264, 144, 80)},
	{"cell": 5, "rect": Rect2(162, 74, 316, 96)},
]
const STANDARD_ACTOR_LAYOUT: Array[Dictionary] = [
	{"cell": 0, "rect": Rect2(286, 166, 68, 68)},
	{"cell": 1, "rect": Rect2(402, 160, 62, 62)},
	{"cell": 2, "rect": Rect2(168, 154, 66, 66)},
	{"cell": 3, "rect": Rect2(486, 174, 68, 68)},
	{"cell": 4, "rect": Rect2(372, 248, 58, 58)},
]
const BOSS_ACTOR_LAYOUT: Array[Dictionary] = [
	{"cell": 0, "rect": Rect2(190, 210, 72, 72)},
	{"cell": 2, "rect": Rect2(112, 156, 60, 60)},
	{"cell": 4, "rect": Rect2(500, 232, 62, 62)},
	{"cell": 5, "rect": Rect2(336, 112, 178, 178)},
]

const INK := Color("071016")
const PAPER := Color("f4e8c7")
const MUTED := Color("9fb3ae")
const STANDARD_ACCENT := Color("3fc7af")
const BOSS_ACCENT := Color("e47755")

var room_state: StringName = STATE_STANDARD
var auto_cycle: bool = true
var _state_elapsed: float = 0.0
var _last_timer_second: int = -1
var _integer_scale: int = 1
var _canvas_origin: Vector2 = Vector2.ZERO
var _water_texture: Texture2D
var _terrain_texture: Texture2D
var _actor_texture: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_modular_textures()
	get_viewport().size_changed.connect(_update_integer_layout)
	_update_integer_layout()
	set_process(true)
	set_process_unhandled_input(true)
	if OS.has_feature(&"pixel_demo"):
		print("FOLDLIGHT_PIXEL_DEMO_READY scene=%s canvas=%dx%d modular_terrain=true display_mode_change=false" % [scene_file_path, int(DESIGN_SIZE.x), int(DESIGN_SIZE.y)])


func _process(delta: float) -> void:
	_state_elapsed += delta
	if auto_cycle and _state_elapsed >= 9.0:
		set_room_state(STATE_BOSS if room_state == STATE_STANDARD else STATE_STANDARD)
	var timer_second := maxi(0, 9 - int(_state_elapsed))
	if timer_second != _last_timer_second:
		_last_timer_second = timer_second
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_game"):
		_request_exit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		auto_cycle = false
		set_room_state(STATE_STANDARD)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		auto_cycle = false
		set_room_state(STATE_BOSS)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"fold"):
		auto_cycle = false
		set_room_state(STATE_BOSS if room_state == STATE_STANDARD else STATE_STANDARD)
		get_viewport().set_input_as_handled()


func set_room_state(next_state: StringName) -> void:
	if next_state != STATE_STANDARD and next_state != STATE_BOSS:
		return
	if room_state == next_state:
		return
	room_state = next_state
	_state_elapsed = 0.0
	_last_timer_second = -1
	room_state_changed.emit(room_state)
	queue_redraw()


func get_room_state() -> StringName:
	return room_state


func get_visual_contract() -> Dictionary:
	return {
		"base_resolution": Vector2i(640, 360),
		"integer_scale": _integer_scale,
		"texture_filter": &"nearest",
		"states": [STATE_STANDARD, STATE_BOSS],
		"isolated_demo": true,
		"changes_display_mode": false,
		"art_direction": &"high_density_handpainted_topdown_rpg_pixel",
		"background_mode": &"modular_texture_atlas",
		"terrain_reproducible": true,
		"shared_terrain_assets": true,
		"legacy_full_frame_backgrounds": false,
		"water_fill": &"shared_cover_texture",
		"atlas_grid": ATLAS_GRID,
		"assets": {
			"water": WATER_TILE_PATH,
			"terrain": TERRAIN_ATLAS_PATH,
			"actors": ACTOR_ATLAS_PATH,
		},
		"loaded_texture_count": int(_water_texture != null) + int(_terrain_texture != null) + int(_actor_texture != null),
		"terrain_layouts": {
			STATE_STANDARD: STANDARD_TERRAIN_LAYOUT,
			STATE_BOSS: BOSS_TERRAIN_LAYOUT,
		},
		"controls": {
			"standard_room": [&"move_left", &"ui_left"],
			"boss_room": [&"move_right", &"ui_right"],
			"toggle_room": [&"fold", &"ui_accept"],
			"exit_demo": [&"ui_cancel", &"pause_game"],
		},
		"exit_only_when_standalone": true,
		"layers": [&"shared_water_base", &"terrain_atlas", &"actor_atlas", &"minimal_hud"],
	}


func get_integer_layout_for_size(viewport_size: Vector2) -> Dictionary:
	var safe_size := Vector2(maxf(1.0, viewport_size.x), maxf(1.0, viewport_size.y))
	var scale_value := maxi(1, int(floor(minf(safe_size.x / DESIGN_SIZE.x, safe_size.y / DESIGN_SIZE.y))))
	var origin := ((safe_size - DESIGN_SIZE * float(scale_value)) * 0.5).floor()
	return {"scale": scale_value, "origin": origin, "canvas_size": DESIGN_SIZE * float(scale_value)}


func get_atlas_cell_region_for_size(source_size: Vector2, cell_index: int) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or cell_index < 0 or cell_index >= ATLAS_GRID.x * ATLAS_GRID.y:
		return Rect2()
	var cell_size := (source_size / Vector2(ATLAS_GRID)).floor()
	var column := cell_index % ATLAS_GRID.x
	var row := cell_index / ATLAS_GRID.x
	return Rect2(Vector2(column, row) * cell_size, cell_size)


func get_cover_region_for_size(source_size: Vector2) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Rect2()
	var cover_scale := maxf(DESIGN_SIZE.x / source_size.x, DESIGN_SIZE.y / source_size.y)
	var visible_size := DESIGN_SIZE / cover_scale
	var source_origin := ((source_size - visible_size) * 0.5).floor()
	return Rect2(source_origin, visible_size.floor())


func _request_exit() -> void:
	exit_requested.emit()
	if get_tree().current_scene == self:
		get_tree().quit()


func _load_modular_textures() -> void:
	_water_texture = _load_texture_if_available(WATER_TILE_PATH)
	_terrain_texture = _load_texture_if_available(TERRAIN_ATLAS_PATH)
	_actor_texture = _load_texture_if_available(ACTOR_ATLAS_PATH)


func _load_texture_if_available(path: String) -> Texture2D:
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D


func _update_integer_layout() -> void:
	var layout := get_integer_layout_for_size(get_viewport_rect().size)
	_integer_scale = int(layout.get("scale", 1))
	_canvas_origin = layout.get("origin", Vector2.ZERO) as Vector2
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("020609"))
	draw_set_transform(_canvas_origin, 0.0, Vector2.ONE * float(_integer_scale))
	_draw_pixel_canvas()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pixel_canvas() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("102c34"))
	_draw_water_base()
	var terrain_layout := STANDARD_TERRAIN_LAYOUT if room_state == STATE_STANDARD else BOSS_TERRAIN_LAYOUT
	var actor_layout := STANDARD_ACTOR_LAYOUT if room_state == STATE_STANDARD else BOSS_ACTOR_LAYOUT
	_draw_atlas_layout(_terrain_texture, terrain_layout)
	_draw_atlas_layout(_actor_texture, actor_layout)
	_draw_minimal_hud()


func _draw_water_base() -> void:
	if _water_texture == null:
		return
	var source_region := get_cover_region_for_size(_water_texture.get_size())
	draw_texture_rect_region(_water_texture, Rect2(Vector2.ZERO, DESIGN_SIZE), source_region)


func _draw_atlas_layout(texture: Texture2D, layout: Array[Dictionary]) -> void:
	if texture == null:
		return
	for item in layout:
		var source_region := get_atlas_cell_region_for_size(texture.get_size(), int(item.get("cell", -1)))
		var target_rect := item.get("rect", Rect2()) as Rect2
		if source_region.has_area() and target_rect.has_area():
			draw_texture_rect_region(texture, target_rect, source_region)


func _draw_minimal_hud() -> void:
	draw_rect(Rect2(8, 8, 624, 30), Color(INK, 0.90))
	_draw_default_text(Vector2(18, 27), "FOLDLIGHT · 模块化像素地形", PAPER, 9)
	_draw_room_tab(Rect2(277, 12, 92, 22), "A / ←  普通房", room_state == STATE_STANDARD, STANDARD_ACCENT)
	_draw_room_tab(Rect2(373, 12, 92, 22), "D / →  BOSS", room_state == STATE_BOSS, BOSS_ACCENT)
	_draw_default_text(Vector2(485, 27), "E / A 切换", MUTED, 7)
	_draw_default_text(Vector2(566, 27), "Esc / B", MUTED, 7)
	var room_title := "潮纸浅滩 · 普通拼图" if room_state == STATE_STANDARD else "礁冠炮城 · 首领拼图"
	var accent := STANDARD_ACCENT if room_state == STATE_STANDARD else BOSS_ACCENT
	draw_rect(Rect2(8, 326, 218, 26), Color(INK, 0.86))
	draw_rect(Rect2(8, 326, 4, 26), accent)
	_draw_default_text(Vector2(19, 343), room_title, PAPER, 9)
	var cycle_label := "自动 %02d" % maxi(0, 9 - int(_state_elapsed)) if auto_cycle else "手动浏览"
	draw_rect(Rect2(552, 330, 80, 22), Color(INK, 0.82))
	_draw_default_text(Vector2(566, 345), cycle_label, MUTED, 7)


func _draw_room_tab(rect: Rect2, label: String, selected: bool, accent: Color) -> void:
	draw_rect(rect, Color("111d21"))
	if selected:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), accent)
		draw_rect(Rect2(rect.position + Vector2(2, 4), rect.size - Vector2(4, 6)), Color(accent, 0.30))
	_draw_default_text(rect.position + Vector2(7, 15), label, PAPER if selected else MUTED, 7)


func _draw_default_text(position: Vector2, text_value: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font, position.round(), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
