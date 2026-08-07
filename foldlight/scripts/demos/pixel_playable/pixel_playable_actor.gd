class_name FoldlightPixelPlayableActor
extends CharacterBody2D

signal died(actor)
signal damaged(actor, amount: int, impact_direction: Vector2)

enum ActorKind {
	PLAYER,
	TURRET,
	CRAB,
	WARDEN,
	SKIFF,
	BOSS,
}

const ATLAS_GRID := Vector2i(3, 2)

var actor_kind: ActorKind = ActorKind.PLAYER
var atlas_texture: Texture2D
var atlas_cell: int = 0
var visual_size := Vector2(138.0, 138.0)
var hit_radius: float = 24.0
var max_health: int = 6
var health: int = 6
var move_speed: float = 330.0
var is_player: bool = false
var is_boss: bool = false
var alive: bool = true
var hit_flash: float = 0.0
var hit_kick: float = 0.0
var last_impact_direction := Vector2.ZERO
var invulnerability: float = 0.0
var visual_time: float = 0.0
var play_bounds := Rect2(28.0, 70.0, 1198.0, 608.0)


func configure(
		kind: ActorKind,
		texture: Texture2D,
		cell: int,
		requested_visual_size: Vector2,
		requested_radius: float,
		requested_health: int,
		requested_speed: float,
		requested_bounds: Rect2
	) -> void:
	actor_kind = kind
	atlas_texture = texture
	atlas_cell = cell
	visual_size = requested_visual_size
	hit_radius = requested_radius
	max_health = requested_health
	health = requested_health
	move_speed = requested_speed
	play_bounds = requested_bounds
	is_player = actor_kind == ActorKind.PLAYER
	is_boss = actor_kind == ActorKind.BOSS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_collision_shape()
	queue_redraw()


func tick_status(delta: float) -> void:
	visual_time += delta
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	hit_kick = maxf(0.0, hit_kick - delta * 8.5)
	invulnerability = maxf(0.0, invulnerability - delta)
	z_index = clampi(int(global_position.y), 0, 4000)
	queue_redraw()


func move_controlled(direction: Vector2, delta: float, speed_override: float = -1.0) -> void:
	var target_speed := move_speed if speed_override < 0.0 else speed_override
	if direction.length_squared() > 0.001:
		velocity = velocity.move_toward(direction.normalized() * target_speed, 1900.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 2200.0 * delta)
	move_and_slide()
	global_position = global_position.clamp(play_bounds.position, play_bounds.end).round()


func move_ai(direction: Vector2, delta: float, speed_multiplier: float = 1.0) -> void:
	var desired := direction.normalized() * move_speed * speed_multiplier if direction.length_squared() > 0.001 else Vector2.ZERO
	velocity = velocity.move_toward(desired, 1050.0 * delta)
	move_and_slide()
	global_position = global_position.clamp(play_bounds.position, play_bounds.end).round()


func take_damage(amount: int, impact_direction: Vector2 = Vector2.ZERO) -> bool:
	if not alive or amount <= 0:
		return false
	health = maxi(0, health - amount)
	hit_flash = 1.0
	hit_kick = 1.0
	last_impact_direction = impact_direction.normalized()
	damaged.emit(self, amount, impact_direction)
	if health <= 0:
		alive = false
		died.emit(self)
	queue_redraw()
	return true


func heal(amount: int) -> bool:
	if not alive or amount <= 0 or health >= max_health:
		return false
	health = mini(max_health, health + amount)
	queue_redraw()
	return true


func get_health_ratio() -> float:
	return float(health) / float(maxi(1, max_health))


func _setup_collision_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	collision.shape = circle


func _atlas_region() -> Rect2:
	if atlas_texture == null or atlas_cell < 0 or atlas_cell >= ATLAS_GRID.x * ATLAS_GRID.y:
		return Rect2()
	var cell_size := atlas_texture.get_size() / Vector2(ATLAS_GRID)
	var column := atlas_cell % ATLAS_GRID.x
	var row := atlas_cell / ATLAS_GRID.x
	return Rect2(Vector2(column, row) * cell_size, cell_size)


func _draw() -> void:
	if atlas_texture == null:
		return
	var bob := sin(visual_time * (3.1 if is_boss else 5.0) + float(atlas_cell)) * (2.0 if is_boss else 1.5)
	var kick := -last_impact_direction * hit_kick * (12.0 if is_boss else 7.0)
	var sprite_origin := Vector2(0.0, bob) + kick
	var shadow_width := visual_size.x * (0.29 if is_boss else 0.22)
	var shadow_y := visual_size.y * (0.19 if is_boss else 0.16)
	draw_set_transform(Vector2(0.0, shadow_y), 0.0, Vector2(1.7, 0.48))
	draw_circle(Vector2.ZERO, shadow_width, Color(0.01, 0.025, 0.035, 0.42))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var destination := Rect2(sprite_origin - visual_size * 0.5, visual_size)
	var tint := Color.WHITE
	if hit_flash > 0.0:
		tint = Color(1.0, lerpf(1.0, 0.42, hit_flash), lerpf(1.0, 0.34, hit_flash), 1.0)
	draw_texture_rect_region(atlas_texture, destination, _atlas_region(), tint)

	if not is_player and not is_boss and alive and health < max_health:
		var bar_width := visual_size.x * 0.42
		var bar_position := Vector2(-bar_width * 0.5, -visual_size.y * 0.34)
		draw_rect(Rect2(bar_position, Vector2(bar_width, 5.0)), Color(0.02, 0.035, 0.04, 0.82))
		draw_rect(Rect2(bar_position + Vector2(1, 1), Vector2((bar_width - 2.0) * get_health_ratio(), 3.0)), Color("f2c15e"))

