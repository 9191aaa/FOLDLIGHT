class_name FoldlightPixelPlayableProjectile
extends Node2D

signal expired(projectile)

enum Faction {
	PLAYER,
	ENEMY,
}

var faction: Faction = Faction.ENEMY
var velocity := Vector2.ZERO
var speed: float = 420.0
var damage: int = 1
var radius: float = 8.0
var reflectable: bool = true
var life_remaining: float = 7.0
var homing_target: Node2D
var homing_strength: float = 0.0
var consumed: bool = false
var visual_time: float = 0.0


func configure(
		requested_faction: Faction,
		requested_position: Vector2,
		requested_velocity: Vector2,
		requested_damage: int,
		requested_radius: float,
		requested_reflectable: bool,
		requested_life: float = 7.0
	) -> void:
	faction = requested_faction
	global_position = requested_position.round()
	velocity = requested_velocity
	speed = requested_velocity.length()
	damage = requested_damage
	radius = requested_radius
	reflectable = requested_reflectable
	life_remaining = requested_life
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _physics_process(delta: float) -> void:
	if consumed:
		return
	visual_time += delta
	life_remaining -= delta
	if life_remaining <= 0.0:
		consume()
		return
	if homing_strength > 0.0 and is_instance_valid(homing_target):
		var desired_direction := global_position.direction_to(homing_target.global_position)
		if desired_direction.length_squared() > 0.001:
			var desired_velocity := desired_direction * maxf(1.0, speed)
			velocity = velocity.lerp(desired_velocity, clampf(homing_strength * delta, 0.0, 1.0))
	global_position += velocity * delta
	queue_redraw()


func reflect_toward(target: Node2D, reflected_speed: float = 720.0) -> void:
	faction = Faction.PLAYER
	reflectable = false
	homing_target = target
	homing_strength = 5.5
	var direction := global_position.direction_to(target.global_position) if is_instance_valid(target) else -velocity.normalized()
	velocity = direction * reflected_speed
	speed = reflected_speed
	damage = 6
	life_remaining = 4.0
	queue_redraw()


func consume() -> void:
	if consumed:
		return
	consumed = true
	expired.emit(self)
	queue_free()


func _draw() -> void:
	var direction := velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var tail := -direction
	if faction == Faction.PLAYER:
		_draw_player_shot(tail)
	elif reflectable:
		_draw_reflectable_shot(tail)
	else:
		_draw_forbidden_shot(tail)


func _draw_player_shot(tail: Vector2) -> void:
	draw_line(tail * 28.0, tail * 8.0, Color(0.18, 0.92, 0.89, 0.32), 5.0, false)
	draw_line(tail * 20.0, Vector2.ZERO, Color("9ff8de"), 3.0, false)
	var diamond := PackedVector2Array([Vector2(0, -7), Vector2(9, 0), Vector2(0, 7), Vector2(-9, 0)])
	draw_colored_polygon(diamond, Color("f5e7ae"))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("21424a"), 2.0, false)
	draw_rect(Rect2(-2, -2, 4, 4), Color("31ddc8"))


func _draw_reflectable_shot(tail: Vector2) -> void:
	draw_line(tail * 20.0, tail * 5.0, Color(0.20, 0.96, 0.93, 0.23), 5.0, false)
	var pulse := 1.0 + sin(visual_time * 9.0) * 0.08
	var diamond := PackedVector2Array([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)])
	for index in diamond.size():
		diamond[index] *= pulse
	draw_colored_polygon(diamond, Color("4af4dc"))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("d8fff1"), 2.0, false)
	draw_rect(Rect2(-2, -2, 4, 4), Color.WHITE)


func _draw_forbidden_shot(tail: Vector2) -> void:
	draw_line(tail * 17.0, tail * 5.0, Color(1.0, 0.24, 0.10, 0.22), 6.0, false)
	draw_rect(Rect2(-9, -9, 18, 18), Color("25151c"))
	draw_rect(Rect2(-7, -7, 14, 14), Color("ff5b3f"))
	draw_rect(Rect2(-3, -3, 6, 6), Color("ffd06a"))

