class_name FoldlightTerrainHint
extends Node2D

## One contextual, non-interactive world label. Terrain owns all effect wording.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const NEAR_DISTANCE: float = 140.0
const POLL_INTERVAL: float = 0.10
const FONT_SIZE: int = 21

var _room: Node2D
var _player: FoldlightPlayer
var _target: FoldlightTerrainPiece
var _active: bool = false
var _alpha: float = 0.0
var _clock: float = 0.0
var _poll_remaining: float = 0.0
var _text: String = ""
var _polarity: StringName = &"neutral"
var _color: Color = Palette.MUTED
var _inside: bool = false
var _font: Font
var _panel: StyleBoxFlat


func _ready() -> void:
	# Hostile projectiles remain above the label; its anchor avoids the player.
	z_index = 1
	_font = FoldlightTheme.body_font()
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color(Palette.INK, 0.90)
	_panel.set_corner_radius_all(5)
	_panel.set_border_width_all(1)
	visible = false
	set_process(false)


func bind(room: Node2D, player: FoldlightPlayer) -> void:
	_room = room
	_player = player
	_target = null
	_alpha = 0.0
	_clock = 0.0
	_poll_remaining = 0.0
	_text = ""
	_inside = false
	visible = false
	modulate.a = 0.0


func set_active(value: bool) -> void:
	_active = value
	set_process(value)
	if not value:
		# Keep fade progress frozen while the world is behind a modal.
		visible = false
	else:
		_poll_remaining = 0.0


func get_hint_snapshot() -> Dictionary:
	return {"active": _active, "visible": visible, "alpha": _alpha, "clock": _clock,
		"placement_id": _target.placement_id if is_instance_valid(_target) else &"",
		"text": _text, "polarity": _polarity, "inside": _inside, "position": global_position}


func _process(delta: float) -> void:
	if not _active or not is_instance_valid(_room) or not is_instance_valid(_player) or not _player.play_enabled:
		visible = false
		return
	_clock += delta
	_poll_remaining -= delta
	if _poll_remaining <= 0.0:
		_poll_remaining = POLL_INTERVAL
		_refresh_target()
	var target_alpha := 1.0 if is_instance_valid(_target) else 0.0
	_alpha = move_toward(_alpha, target_alpha, delta * 5.0)
	modulate.a = _alpha
	visible = _alpha > 0.001 and not _text.is_empty()
	queue_redraw()


func _refresh_target() -> void:
	var best: FoldlightTerrainPiece
	var best_score := INF
	var old_score := INF
	for piece: FoldlightTerrainPiece in _room.call("get_terrain_pieces"):
		if piece.kind not in [FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL,
			FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE,
			FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH,
			FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER]:
			continue
		var distance := _edge_distance(piece, _player.global_position)
		if distance > NEAR_DISTANCE:
			continue
		var semantic := piece.get_readability()
		var inside := piece.contains_world_point(_player.global_position)
		var polarity := StringName(semantic.get("polarity", &"neutral"))
		var priority := int({&"hazard": 0, &"debuff": 1, &"benefit": 2, &"directional": 3}.get(polarity, 4))
		# Priority bands exceed proximity and hysteresis combined: an old debuff
		# label can never suppress an equally active damage hazard.
		var score := distance + float(priority) * 1000.0 - (10000.0 if inside else 0.0)
		if piece == _target:
			old_score = score
		if score < best_score:
			best_score = score
			best = piece
	# A small preference for the existing label prevents flicker between neighbors.
	if is_instance_valid(_target) and old_score <= best_score + 18.0 and old_score < INF:
		best = _target
	if best != _target and best != null:
		_alpha = 0.0
	_target = best
	if not is_instance_valid(_target):
		_inside = false
		return
	var semantic := _target.get_readability()
	var label := str(semantic.get("label", ""))
	var detail := str(semantic.get("detail", ""))
	_text = label + (" · " + detail if not detail.is_empty() else "")
	_polarity = StringName(semantic.get("polarity", &"neutral"))
	_color = Color(semantic.get("color", Palette.MUTED))
	_inside = _target.contains_world_point(_player.global_position)
	_panel.border_color = Color(_color, 0.65 if _inside else 0.42)
	_update_anchor()


func _edge_distance(piece: FoldlightTerrainPiece, point: Vector2) -> float:
	var local_point := piece.to_local(point)
	var half_size := piece.piece_size * 0.5
	var nearest := local_point.clamp(-half_size, half_size)
	return point.distance_to(piece.to_global(nearest))


func _update_anchor() -> void:
	var half_size := _target.piece_size * 0.5
	var top := INF
	var bottom := -INF
	for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)]:
		var world_corner := _target.to_global(corner)
		top = minf(top, world_corner.y)
		bottom = maxf(bottom, world_corner.y)
	global_position = Vector2(_target.global_position.x, top - 30.0)
	var label_rect := _label_rect()
	var world_rect := Rect2(global_position + label_rect.position, label_rect.size).grow(_player.get_hit_radius() + 16.0)
	if world_rect.has_point(_player.global_position):
		global_position.y = bottom + 30.0
	# Never inherit the terrain's tilt: text stays horizontal in world space.
	global_rotation = 0.0


func _label_rect() -> Rect2:
	var width := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 42.0
	return Rect2(Vector2(-width * 0.5, -19.0), Vector2(width, 38.0))


func _draw() -> void:
	if _font == null or _panel == null or _text.is_empty():
		return
	var rect := _label_rect()
	draw_style_box(_panel, rect)
	var icon := Vector2(rect.position.x + 17.0, 0)
	if _polarity == &"benefit":
		draw_circle(icon, 2.5, _color)
		for ray in 6:
			var direction := Vector2.from_angle(float(ray) * TAU / 6.0)
			draw_line(icon + direction * 4.5, icon + direction * 6.0, _color, 1.5, true)
	elif _polarity == &"hazard":
		draw_colored_polygon(PackedVector2Array([icon + Vector2(0, -6), icon + Vector2(5, 4), icon + Vector2(-5, 4)]), _color)
	elif _polarity == &"debuff":
		draw_polyline(PackedVector2Array([icon + Vector2(-4, -2), icon + Vector2(0, 3), icon + Vector2(4, -2)]), _color, 2.0, true)
	else:
		draw_polyline(PackedVector2Array([icon + Vector2(0, -5), icon + Vector2(5, 0), icon + Vector2(0, 5), icon + Vector2(-5, 0), icon + Vector2(0, -5)]), _color, 1.5, true)
	draw_string(_font, Vector2(rect.position.x + 31.0, 7.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.PAPER)
