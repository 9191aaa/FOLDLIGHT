class_name FoldlightRoomBackdrop
extends Node2D

const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const Seascape = preload("res://scripts/visuals/paper_seascape.gd")
const SeaMotion = preload("res://scripts/visuals/paper_sea_motion.gd")
var world_size := Vector2(2880, 1620)
var accent: Color = PaperArt.FOLD
var room_id: StringName = &""
var style_id: StringName = &"paper_reef"
var _ambient_time: float = 0.0
var _motion_active: bool = false
var _redraw_clock: float = 0.0
var _placements: Array[Dictionary] = []
var _motion: Node2D
var _static_draw_count: int = 0


func configure(new_room_id: StringName, new_size: Vector2, new_accent: Color, new_style_id: StringName = &"") -> void:
	room_id = new_room_id
	world_size = new_size
	accent = new_accent
	style_id = new_style_id if not new_style_id.is_empty() else _infer_style(new_room_id)
	_ambient_time = 0.0
	_redraw_clock = 0.0
	if not is_instance_valid(_motion):
		_motion = SeaMotion.new()
		_motion.name = "LocalSeaMotion"
		# Above the endless static ground (-20), below interactive terrain (-10).
		_motion.z_as_relative = false
		_motion.z_index = -19
		add_child(_motion)
	_motion.configure(world_size, style_id, absi(String(room_id).hash()))
	queue_redraw()


func configure_ground(placements: Array[Dictionary]) -> void:
	_placements = placements.duplicate(true)
	queue_redraw()


func bind_observer(player: Node2D) -> void:
	if is_instance_valid(_motion):
		_motion.bind_observer(player)


func set_motion_active(value: bool) -> void:
	_motion_active = value
	set_process(value)


func _process(delta: float) -> void:
	if not _motion_active:
		return
	var profile := get_node_or_null("/root/ProfileManager")
	var motion_scale := clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0
	if motion_scale <= 0.0:
		return
	_ambient_time += delta * motion_scale
	_redraw_clock += delta
	if _redraw_clock >= 0.05 and is_instance_valid(_motion):
		_redraw_clock = fmod(_redraw_clock, 0.05)
		_motion.advance_to(_ambient_time)


func get_visual_contract() -> Dictionary:
	var motifs: Array[StringName]
	var base := Color("0b2029")
	match style_id:
		&"ink_city":
			motifs = [&"inverted_skyline", &"hanging_bridges", &"seal_windows"]
			base = Color("101e2a")
		&"sun_court":
			motifs = [&"eclipse_disc", &"radial_mosaic", &"processional_rays"]
			base = Color("182426")
		_: motifs = [&"layered_tide_wash", &"folded_reef_silhouette", &"paper_moon", &"foam_stitches"]
	return {"style": style_id, "motifs": motifs, "base": base, "central_relief": true, "cached_ground": true, "static_draw_count": _static_draw_count}


func _infer_style(value: StringName) -> StringName:
	var text := String(value)
	if "city" in text or text.begins_with("r2"): return &"ink_city"
	if "sun" in text or text.begins_with("r3"): return &"sun_court"
	return &"paper_reef"


func _draw() -> void:
	_static_draw_count += 1
	Seascape.draw_region(self, Rect2(Vector2.ZERO, world_size), style_id, absi(String(room_id).hash()))
	Seascape.draw_foundations(self, _placements, style_id)
