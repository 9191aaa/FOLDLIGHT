class_name FoldlightInkDenialZone
extends Area2D

signal effect_entered(body: Node2D, movement_multiplier: float)
signal effect_exited(body: Node2D)
signal expired

var radius: float = 190.0
var duration: float = 4.5
var movement_multiplier: float = 0.62
var _remaining: float = 4.5

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 1 << 0
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
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


func advance_simulation(delta: float) -> bool:
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
	draw_circle(Vector2.ZERO, radius, Color(0.38, 0.08, 0.54, 0.20 * life_ratio))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.84, 0.38, 0.95, 0.58 * life_ratio), 3.0, true)
	for stripe in 6:
		var angle := float(stripe) / 6.0 * TAU
		draw_line(Vector2.ZERO, Vector2.from_angle(angle) * radius * 0.86, Color(0.86, 0.52, 0.94, 0.08 * life_ratio), 8.0, true)
