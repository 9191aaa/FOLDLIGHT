class_name FoldlightInkDenialZone
extends Area2D

signal effect_entered(body: Node2D, movement_multiplier: float)
signal effect_exited(body: Node2D)
signal expired

const BIND_COLOR := Color("de92ca")
const BIND_SHADOW := Color("311d39")
const EFFECT_LABEL: String = "缚折 · 移速降低"

var radius: float = 190.0
var duration: float = 4.5
var movement_multiplier: float = 0.62
var _remaining: float = 4.5
var _simulation_active: bool = true
var _font: Font
var _label_width: float = 0.0
var _label_panel: StyleBoxFlat

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 1 << 0
	# The node lives with projectiles for cleanup, but its ink belongs below
	# actors and bullets and above the permanent terrain layer.
	z_as_relative = false
	z_index = -4
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Microsoft YaHei UI", "Noto Sans CJK SC"])
	_font = font
	_label_width = _font.get_string_size(EFFECT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_label_panel = StyleBoxFlat.new()
	_label_panel.bg_color = Color(BIND_SHADOW, 0.78)
	_label_panel.set_corner_radius_all(5)
	_refresh_shape()


func configure(snapshot: Dictionary) -> void:
	position = Vector2(snapshot.get("position", position))
	radius = clampf(float(snapshot.get("radius", radius)), 80.0, 210.0)
	duration = clampf(float(snapshot.get("duration", duration)), 0.5, 5.0)
	movement_multiplier = clampf(float(snapshot.get("movement_multiplier", movement_multiplier)), 0.3, 1.0)
	_remaining = duration
	if is_node_ready():
		_refresh_shape()
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	_simulation_active = value
	set_process(value)


func advance_simulation(delta: float) -> bool:
	if not _simulation_active:
		return false
	_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
	queue_redraw()
	if _remaining <= 0.0:
		expired.emit()
		return true
	return false


func _process(delta: float) -> void:
	if advance_simulation(delta):
		queue_free()


func _refresh_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle
	collision_shape.scale = Vector2.ONE


func _on_body_entered(body: Node2D) -> void:
	effect_entered.emit(body, movement_multiplier)


func _on_body_exited(body: Node2D) -> void:
	effect_exited.emit(body)


func _draw() -> void:
	var life_ratio := clampf(_remaining / maxf(duration, 0.001), 0.0, 1.0)
	var elapsed := duration - _remaining
	var pulse := 0.5 + sin(elapsed * 4.6) * 0.5
	# The boundary stays legible for the entire harmful lifetime. Only the
	# separate outer clock drains; a fading fill used to imply early safety.
	draw_circle(Vector2.ZERO, radius, Color(BIND_SHADOW, 0.26))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(BIND_SHADOW, 0.90), 8.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(BIND_COLOR, 0.84 + pulse * 0.10), 3.0, true)
	draw_arc(Vector2.ZERO, radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * life_ratio, 72, Color(BIND_COLOR, 0.62), 2.0, true)
	for ring in 2:
		var travel := fposmod(elapsed * 0.24 + float(ring) * 0.5, 1.0)
		var ring_radius := lerpf(radius - 17.0, radius * 0.30, travel)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 56, Color(BIND_COLOR, sin(travel * PI) * 0.15), 2.0, true)
	for segment in 8:
		var angle := float(segment) * TAU / 8.0
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		var tip := direction * (radius - 27.0 - pulse * 4.0)
		draw_arc(Vector2.ZERO, radius - 12.0, angle - 0.21, angle + 0.21, 10, Color(BIND_COLOR, 0.50), 2.0, true)
		draw_polyline(PackedVector2Array([tip + direction * 11.0 - side * 7.0, tip, tip + direction * 11.0 + side * 7.0]), Color(BIND_COLOR, 0.76), 2.4, true)
	# Two folded foot marks joined by a short chain identify restricted movement,
	# distinct from the drops and recovery marks of permanent wet ink.
	for side in [-1.0, 1.0]:
		var foot := Vector2(side * 19.0, -7.0)
		var fold := PackedVector2Array([foot + Vector2(-9, -17), foot + Vector2(8, -13), foot + Vector2(12, 13), foot + Vector2(-8, 13), foot + Vector2(-9, -17)])
		draw_colored_polygon(fold, Color(BIND_COLOR, 0.13))
		draw_polyline(fold, Color(BIND_COLOR, 0.88), 2.4, true)
		draw_line(foot + Vector2(-5, 4), foot + Vector2(7, -4), Color(BIND_COLOR, 0.66), 2.0, true)
	draw_line(Vector2(-12, 15), Vector2(12, 15), Color(BIND_COLOR, 0.88), 2.4, true)
	for link in [-7.0, 7.0]:
		draw_arc(Vector2(link, 15), 5.0, 0.0, TAU, 12, Color(BIND_COLOR, 0.88), 2.0, true)
	if _font != null and _label_panel != null:
		draw_style_box(_label_panel, Rect2(Vector2(-_label_width * 0.5 - 10.0, 33.0), Vector2(_label_width + 20.0, 32.0)))
		draw_string(_font, Vector2(-_label_width * 0.5, 56.0), EFFECT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(BIND_COLOR, 0.96))
