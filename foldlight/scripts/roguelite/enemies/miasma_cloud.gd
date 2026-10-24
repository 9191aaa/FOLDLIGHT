class_name FoldlightMiasmaCloud
extends Node2D

const RenderRedraw = preload("res://scripts/visuals/render_redraw.gd")

const MIST_COLOR := Color("a9b58c")
const SHADOW_COLOR := Color("172b29")
const WARNING_DRAW_INTERVAL: float = 0.1
const ACTIVE_DRAW_INTERVAL: float = 0.15
const DEFAULT_DURATION: float = 60.0

var source_id: StringName = &""
var radius: float = 112.0
var warning_duration: float = 0.85
var duration: float = DEFAULT_DURATION
var tick_interval: float = 1.6
var damage: int = 1
var _warning_remaining: float = 0.85
var _remaining: float = DEFAULT_DURATION
var _hit_remaining: float = 0.0
var _draw_remaining: float = 0.0
var _simulation_active: bool = true
var _expired: bool = false


func _ready() -> void:
	# Combat alone advances this clock, including pause/rotation/reward guards.
	set_process(false)
	set_physics_process(false)
	z_as_relative = false
	z_index = -3


func configure(snapshot: Dictionary) -> void:
	global_position = Vector2(snapshot.get("position", global_position))
	source_id = StringName(snapshot.get("source_id", &""))
	radius = clampf(float(snapshot.get("radius", 112.0)), 70.0, 150.0)
	warning_duration = clampf(float(snapshot.get("warning_duration", 0.85)), 0.7, 2.0)
	duration = clampf(float(snapshot.get("duration", DEFAULT_DURATION)), 1.0, 90.0)
	tick_interval = clampf(float(snapshot.get("tick_interval", 1.6)), 1.2, 3.0)
	damage = 1
	_warning_remaining = warning_duration
	_remaining = duration
	_hit_remaining = 0.0
	_draw_remaining = 0.0
	_expired = false
	_simulation_active = true
	RenderRedraw.request(self)


func refresh_duration(seconds: float = DEFAULT_DURATION) -> bool:
	# A carrier crossing its own trail refreshes the same visible area. Never
	# grow the radius, restart its warning, or grant an extra damage tick.
	if _expired or not _simulation_active:
		return false
	var refreshed := clampf(seconds, 1.0, 90.0)
	duration = maxf(duration, refreshed)
	_remaining = maxf(_remaining, refreshed)
	RenderRedraw.request(self)
	return true


func set_simulation_active(value: bool) -> void:
	_simulation_active = value


func advance_simulation(delta: float) -> bool:
	if _expired:
		return true
	if not _simulation_active:
		return false
	# A stalled browser frame cannot skip the visible warning or tick damage.
	var step := clampf(delta, 0.0, 0.1)
	if step <= 0.0:
		return false
	var was_warning := _warning_remaining > 0.00001
	var active_step := step
	if _warning_remaining > 0.0:
		var warning_step := minf(active_step, _warning_remaining)
		_warning_remaining = maxf(0.0, _warning_remaining - warning_step)
		active_step -= warning_step
	_remaining = maxf(0.0, _remaining - active_step)
	_hit_remaining = maxf(0.0, _hit_remaining - active_step)
	_expired = _remaining <= 0.00001
	_draw_remaining -= step
	var changed_phase := was_warning != (_warning_remaining > 0.00001)
	if _draw_remaining <= 0.0 or _expired or changed_phase:
		_draw_remaining = WARNING_DRAW_INTERVAL if _warning_remaining > 0.00001 else ACTIVE_DRAW_INTERVAL
		RenderRedraw.request(self)
	return _expired


func consume_damage_at(world_position: Vector2) -> bool:
	if _expired or not _simulation_active or _warning_remaining > 0.00001 or _hit_remaining > 0.00001:
		return false
	if global_position.distance_squared_to(world_position) > radius * radius:
		return false
	_hit_remaining = tick_interval
	return true


func get_hazard_snapshot() -> Dictionary:
	return {"source_id": source_id, "position": global_position, "radius": radius,
		"warning_remaining": _warning_remaining, "remaining": _remaining, "duration": duration,
		"tick_remaining": _hit_remaining, "damage": damage, "expired": _expired,
		"dangerous": not _expired and _warning_remaining <= 0.00001,
		"simulation_active": _simulation_active, "fill_alpha": 0.12,
		"outline_alpha": 0.88, "visual_version": &"miasma_readable_3_19"}


func _draw() -> void:
	if _expired:
		return
	var warning := _warning_remaining > 0.00001
	var clock_ratio := 1.0 - _warning_remaining / warning_duration if warning else _remaining / duration
	# Stable alpha and an opaque dark backing prevent bright overlap and shimmer.
	draw_circle(Vector2.ZERO, radius, Color(SHADOW_COLOR, 0.22 if warning else 0.38))
	if not warning:
		draw_circle(Vector2.ZERO, radius - 4.0, Color(MIST_COLOR, 0.12))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(SHADOW_COLOR, 0.95), 6.0, true)
	if warning:
		for index in 12:
			var angle := float(index) * TAU / 12.0
			draw_arc(Vector2.ZERO, radius, angle, angle + TAU / 18.0, 4, Color(MIST_COLOR, 0.88), 2.2, true)
	else:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(MIST_COLOR, 0.88), 2.5, true)
		# Short inward hatching identifies the harmful side of the boundary.
		for index in 8:
			var ray := Vector2.from_angle(float(index) * TAU / 8.0)
			draw_line(ray * (radius - 12.0), ray * (radius - 4.0), Color(MIST_COLOR, 0.50), 2.0, true)
	draw_arc(Vector2.ZERO, radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * clock_ratio, 40, Color(MIST_COLOR, 0.62), 2.0, true)
	for index in 3:
		var direction := Vector2.from_angle(-PI * 0.5 + index * TAU / 3.0)
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([direction * 20.0, direction * 7.0 + side * 7.0, Vector2.ZERO, direction * 7.0 - side * 7.0]), Color(MIST_COLOR, 0.55))
