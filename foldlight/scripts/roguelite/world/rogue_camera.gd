class_name FoldlightRogueCamera
extends Camera2D

const HIT_KICK_DURATION: float = 0.14

@export var design_view_size: Vector2 = Vector2(1920.0, 1080.0)
@export_range(1.0, 20.0, 0.5) var follow_speed: float = 8.0
@export_range(0.0, 160.0, 4.0) var look_ahead_distance: float = 54.0
@export_range(0.1, 4.0, 0.1) var trauma_decay: float = 1.8

var target: Node2D
var room_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(2880, 1620))
var _previous_target_position: Vector2 = Vector2.ZERO
var _look_ahead: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
var _hit_kick_remaining: float = 0.0
var _hit_kick_strength: float = 0.0
var _hit_kick_sign: float = 1.0


func _ready() -> void:
	position_smoothing_enabled = false
	_noise.seed = 3003
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


func configure(new_target: Node2D, bounds: Rect2) -> void:
	target = new_target
	room_bounds = bounds
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	if target != null:
		_previous_target_position = target.global_position
		position = _clamp_camera_center(target.global_position)
	reset_physics_interpolation()


func set_active(active: bool) -> void:
	enabled = active
	set_process(active)
	if not active:
		offset = Vector2.ZERO
		rotation = 0.0
		_hit_kick_remaining = 0.0
		_hit_kick_strength = 0.0


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func add_hit_kick(strength: float = 1.0) -> void:
	var safe_strength := clampf(strength, 0.0, 1.0)
	if safe_strength <= 0.0:
		return
	_hit_kick_remaining = HIT_KICK_DURATION
	_hit_kick_strength = maxf(_hit_kick_strength, safe_strength)
	_hit_kick_sign *= -1.0


func force_follow(weight: float = 1.0) -> void:
	if target == null:
		return
	var desired := _clamp_camera_center(target.global_position)
	position = position.lerp(desired, clampf(weight, 0.0, 1.0))


func _process(delta: float) -> void:
	if target == null or not enabled:
		return
	var movement := target.global_position - _previous_target_position
	_previous_target_position = target.global_position
	var desired_ahead := movement.normalized() * look_ahead_distance if movement.length_squared() > 1.0 else Vector2.ZERO
	_look_ahead = _look_ahead.lerp(desired_ahead, clampf(delta * 5.0, 0.0, 1.0))
	var desired := _clamp_camera_center(target.global_position + _look_ahead)
	position = position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	_update_shake(delta)


func _clamp_camera_center(desired: Vector2) -> Vector2:
	var half_view := design_view_size * 0.5 / zoom
	var minimum := room_bounds.position + half_view
	var maximum := room_bounds.end - half_view
	if minimum.x > maximum.x:
		minimum.x = room_bounds.get_center().x
		maximum.x = minimum.x
	if minimum.y > maximum.y:
		minimum.y = room_bounds.get_center().y
		maximum.y = minimum.y
	return desired.clamp(minimum, maximum)


func _update_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	_hit_kick_remaining = maxf(0.0, _hit_kick_remaining - delta)
	if _trauma <= 0.0 and _hit_kick_remaining <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		_hit_kick_strength = 0.0
		return
	_noise_time += delta * 48.0
	var strength := _trauma * _trauma
	offset = Vector2(_noise.get_noise_2d(_noise_time, 0.0) * 9.0, _noise.get_noise_2d(0.0, _noise_time) * 7.0) * strength
	rotation = deg_to_rad(0.8) * _noise.get_noise_2d(_noise_time, _noise_time) * strength
	if _hit_kick_remaining > 0.0:
		var progress := 1.0 - _hit_kick_remaining / HIT_KICK_DURATION
		var envelope := pow(1.0 - progress, 2.0)
		var kick := cos(progress * PI * 2.5) * envelope * _hit_kick_strength
		offset += Vector2(4.8 * _hit_kick_sign, 2.2) * kick
		rotation += deg_to_rad(0.18) * kick * _hit_kick_sign
