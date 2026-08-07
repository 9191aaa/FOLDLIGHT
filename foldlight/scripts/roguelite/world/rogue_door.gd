class_name FoldlightRogueDoor
extends Node2D

signal entered(exit_id: StringName)

var exit_id: StringName = &""
var locked: bool = false
var outward_normal: Vector2 = Vector2.RIGHT
var doorway_width: float = 190.0

@onready var gate_body: StaticBody2D = $GateBody
@onready var gate_shape: CollisionShape2D = $GateBody/CollisionShape2D
@onready var exit_area: Area2D = $ExitArea
@onready var exit_shape: CollisionShape2D = $ExitArea/CollisionShape2D


func _ready() -> void:
	gate_body.collision_layer = 1 << 2
	gate_body.collision_mask = 1 << 0
	exit_area.collision_layer = 1 << 5
	exit_area.collision_mask = 1 << 0
	exit_area.body_entered.connect(_on_body_entered)
	_refresh_shapes()
	set_locked(locked)


func configure(snapshot: Dictionary) -> void:
	exit_id = StringName(snapshot.get("id", &"exit"))
	position = Vector2(snapshot.get("position", position))
	outward_normal = Vector2(snapshot.get("normal", Vector2.RIGHT)).normalized()
	if outward_normal.is_zero_approx():
		outward_normal = Vector2.RIGHT
	doorway_width = clampf(float(snapshot.get("width", doorway_width)), 120.0, 300.0)
	rotation = outward_normal.angle()
	if is_node_ready():
		_refresh_shapes()
	queue_redraw()


func set_locked(value: bool) -> void:
	locked = value
	if not is_node_ready():
		return
	gate_shape.set_deferred("disabled", not locked)
	exit_shape.set_deferred("disabled", locked)
	queue_redraw()


func _refresh_shapes() -> void:
	var gate_rectangle := RectangleShape2D.new()
	gate_rectangle.size = Vector2(34.0, doorway_width)
	gate_shape.shape = gate_rectangle
	gate_shape.scale = Vector2.ONE
	var trigger_rectangle := RectangleShape2D.new()
	trigger_rectangle.size = Vector2(96.0, doorway_width)
	exit_shape.shape = trigger_rectangle
	exit_shape.position = Vector2(44.0, 0.0)
	exit_shape.scale = Vector2.ONE


func _on_body_entered(_body: Node2D) -> void:
	if not locked:
		entered.emit(exit_id)


func _draw() -> void:
	var half_width := doorway_width * 0.5
	if locked:
		draw_rect(Rect2(Vector2(-17, -half_width), Vector2(34, doorway_width)), Color(0.12, 0.20, 0.29, 0.96), true)
		for bar in 5:
			var y := lerpf(-half_width + 14.0, half_width - 14.0, float(bar) / 4.0)
			draw_line(Vector2(-13, y), Vector2(13, y), Color(1.0, 0.42, 0.28, 0.92), 5.0, true)
		draw_line(Vector2.ZERO, Vector2(42, 0), Color(1.0, 0.50, 0.31, 0.52), 3.0, true)
	else:
		draw_line(Vector2(0, -half_width), Vector2(0, -half_width + 54.0), Color(0.40, 0.94, 0.85, 0.86), 7.0, true)
		draw_line(Vector2(0, half_width), Vector2(0, half_width - 54.0), Color(0.40, 0.94, 0.85, 0.86), 7.0, true)
		draw_polyline(PackedVector2Array([Vector2(18, -11), Vector2(35, 0), Vector2(18, 11)]), Color(0.72, 1.0, 0.92, 0.88), 4.0, true)
