class_name FoldlightSpawnTelegraph
extends Node2D

var duration: float = 0.7
var remaining: float = 0.7
var accent: Color = Color(0.96, 0.48, 0.28)


func configure(snapshot: Dictionary, new_duration: float) -> void:
	position = Vector2(snapshot.get("spawn_position", position))
	duration = maxf(0.1, new_duration)
	remaining = duration
	var role := int(snapshot.get("role", FoldlightRogueEnemyDefinition.EnemyRole.FODDER))
	if role == FoldlightRogueEnemyDefinition.EnemyRole.BUFFER:
		accent = Color(1.0, 0.76, 0.24)
	elif role == FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER:
		accent = Color(0.78, 0.34, 0.96)
	queue_redraw()


func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	queue_redraw()
	if remaining <= 0.0:
		queue_free()


func _draw() -> void:
	var ratio := clampf(remaining / duration, 0.0, 1.0)
	var radius := lerpf(24.0, 54.0, ratio)
	draw_circle(Vector2.ZERO, radius, Color(accent, 0.08 + (1.0 - ratio) * 0.10))
	draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - ratio), 32, Color(accent, 0.88), 4.0, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color(accent, 0.72), 2.0, true)
	draw_line(Vector2(0, -12), Vector2(0, 12), Color(accent, 0.72), 2.0, true)

