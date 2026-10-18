class_name FoldlightMirrorSpellField
extends Node2D

const RenderRedraw = preload("res://scripts/visuals/render_redraw.gd")
const INK := Color("d3a291")

var source_id: StringName = &""
var actor_id: StringName = &"mirror_decoy"
var serial: int = 0
var action: StringName = &""
var radius: float = 140.0
var power: float = 1.0
var duration: float = 1.0
var remaining: float = 1.0
var warning_remaining: float = 0.65
var waiting_for_actor: bool = true
var resolved: bool = false
var damage_consumed: bool = false
var _visual_clock: float = 0.0


func configure(snapshot: Dictionary) -> void:
	source_id = StringName(snapshot.get("source_id", &""))
	serial = int(snapshot.get("serial", 0))
	action = StringName(snapshot.get("action", &""))
	global_position = Vector2(snapshot.get("position", Vector2.ZERO))
	radius = clampf(float(snapshot.get("radius", 140.0)), 24.0, 430.0)
	power = float(snapshot.get("power", 1.0))
	duration = clampf(float(snapshot.get("duration", 1.0)), 0.2, 6.0)
	remaining = duration
	warning_remaining = maxf(0.0, float(snapshot.get("warning", 0.65)))
	waiting_for_actor = bool(snapshot.get("waiting_for_actor", true))
	resolved = false
	damage_consumed = false
	set_process(false)
	set_physics_process(false)
	z_index = -2
	RenderRedraw.request(self)


func resolve() -> void:
	resolved = true
	warning_remaining = 0.0
	remaining = duration
	RenderRedraw.request(self)


func advance_simulation(delta: float) -> bool:
	var step := clampf(delta, 0.0, 0.1)
	if not resolved:
		warning_remaining = maxf(0.0, warning_remaining - step)
		if warning_remaining <= 0.0 and not waiting_for_actor:
			resolve()
	else:
		remaining = maxf(0.0, remaining - step)
	_visual_clock += step
	if _visual_clock >= 0.1:
		_visual_clock = 0.0
		RenderRedraw.request(self)
	return resolved and remaining <= 0.0


func contains_point(point: Vector2) -> bool:
	return global_position.distance_squared_to(point) <= radius * radius


func _draw() -> void:
	var tint := Color("c3a9bd") if action == &"hostile_slow" else INK
	var alpha := 0.88 if resolved else 0.64
	draw_circle(Vector2.ZERO, radius, Color("18262c", 0.28 if resolved else 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color("112229", 0.9), 7.0, true)
	if resolved:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint, alpha), 2.4, true)
	else:
		for segment in 12:
			var angle := TAU * float(segment) / 12.0
			draw_arc(Vector2.ZERO, radius, angle, angle + TAU / 18.0, 5, Color(tint, alpha), 2.0, true)
	var ratio := remaining / duration if resolved else 1.0 - warning_remaining / 0.65
	draw_arc(Vector2.ZERO, radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(ratio, 0.0, 1.0), 40, Color(tint, 0.5), 1.5, true)
	# Split paper seal distinguishes copied skills from beneficial cyan ground.
	for side in [-1.0, 1.0]:
		var center := Vector2(side * 11.0, 0)
		var wings := PackedVector2Array([center + Vector2(0, -19), center + Vector2(side * 17, 12), center + Vector2(-side * 5, 3), center + Vector2(0, -19)])
		draw_colored_polygon(wings, Color(tint, 0.18))
		draw_polyline(wings, Color(tint, 0.84), 2.0, true)
	var label := "镜潮 · 减速" if action == &"hostile_slow" else ("镜步 · 诱饵" if action == &"dash_decoy" else ("镜钟 · 爆破" if action == &"bell_blast" else "镜技 · 返弹"))
	draw_string(FoldlightTheme.body_font(), Vector2(-64, 43), label, HORIZONTAL_ALIGNMENT_CENTER, 128, 18, Color(tint, 0.94))
