class_name FoldlightDemoFeedback
extends Node2D

# Render-only translation. Never move actors or the root and never use a gameplay RNG.
const MAX_SHAKE: float = 8.0
const MAX_PARTICLES: int = 160
const MAX_RINGS: int = 20
var strength: float = 0.55
var suspended: bool = false
var amplitude: float = 0.0
var shake_remaining: float = 0.0
var shake_duration: float = 0.2
var camera_offset: Vector2 = Vector2.ZERO
var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var _clock: float = 0.0
var _impact_gate: float = 0.0
var _sound_gates: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80
	_rng.seed = 9202

func set_strength(value: float) -> void:
	strength = clampf(value, 0.0, 1.0)
	reset_camera()

func set_suspended(value: bool) -> void:
	suspended = value
	if value:
		reset_camera()

func kick(power: float, duration: float = 0.18) -> void:
	if suspended or strength <= 0.0:
		return
	amplitude = minf(MAX_SHAKE, maxf(amplitude, power * strength))
	shake_duration = clampf(duration, 0.05, 0.24)
	shake_remaining = maxf(shake_remaining, shake_duration)

func reset_camera() -> void:
	amplitude = 0.0
	shake_remaining = 0.0
	camera_offset = Vector2.ZERO
	if is_inside_tree():
		get_viewport().canvas_transform = Transform2D.IDENTITY

func reset() -> void:
	reset_camera()
	particles.clear()
	rings.clear()
	_sound_gates.clear()
	_impact_gate = 0.0
	queue_redraw()

func _exit_tree() -> void:
	reset_camera()

func _process(delta: float) -> void:
	if suspended:
		return
	_clock += delta
	_impact_gate = maxf(0.0, _impact_gate - delta)
	shake_remaining = maxf(0.0, shake_remaining - delta)
	if shake_remaining > 0.0:
		var envelope: float = pow(clampf(shake_remaining / shake_duration, 0.0, 1.0), 2.0)
		var direction := Vector2(sin(_clock * 79.0), cos(_clock * 91.0)).limit_length(1.0)
		camera_offset = direction * amplitude * envelope
	else:
		amplitude = 0.0
		camera_offset = Vector2.ZERO
	get_viewport().canvas_transform = Transform2D(0.0, camera_offset)
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["age"] = float(particle["age"]) + delta
		particle["p"] = Vector2(particle["p"]) + Vector2(particle["v"]) * delta
		particle["v"] = Vector2(particle["v"]) * exp(-4.0 * delta)
		if float(particle["age"]) >= float(particle["life"]):
			particles.remove_at(index)
	for index in range(rings.size() - 1, -1, -1):
		rings[index]["age"] = float(rings[index]["age"]) + delta
		if float(rings[index]["age"]) >= float(rings[index]["life"]):
			rings.remove_at(index)
	queue_redraw()

func _sound(id: StringName, pitch: float, volume: float, interval: float = 0.08) -> void:
	if _clock < float(_sound_gates.get(id, -1.0)):
		return
	_sound_gates[id] = _clock + interval
	var audio := get_node_or_null("/root/AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.play_sfx(id, pitch, volume)

func _sparks(at: Vector2, tint: Color, count: int, speed: float) -> void:
	for index in mini(count, MAX_PARTICLES - particles.size()):
		var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		particles.append({"p": at, "v": direction * speed * _rng.randf_range(0.45, 1.0), "age": 0.0, "life": _rng.randf_range(0.22, 0.48), "color": tint, "size": _rng.randf_range(2.0, 4.5)})

func ring(at: Vector2, tint: Color, radius: float, life: float = 0.35) -> void:
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	rings.append({"p": at, "color": tint, "radius": radius, "life": life, "age": 0.0})

func captured(count: int, at: Vector2) -> void:
	_sparks(at, Color("73e2ce"), 3, 155.0)
	_sound(&"capture", 0.95 + minf(0.28, float(count) * 0.035), -21.0, 0.10)

func released(count: int, _charge: float, at: Vector2) -> void:
	if count <= 0:
		return
	kick(minf(6.0, 2.0 + float(count) * 0.4), 0.18)
	ring(at, Color("f2d28c"), 90.0 + float(count) * 8.0)
	_sparks(at, Color("f4db9b"), mini(24, count * 2), 300.0)
	_sound(&"release", 0.95, -10.0, 0.10)

func impact(_key: StringName, at: Vector2, _velocity: Vector2, damage: float) -> void:
	if _impact_gate > 0.0:
		return
	_impact_gate = 0.10
	_sparks(at, Color("ffe3a3"), 5, 200.0)
	if damage >= 1.0:
		kick(1.8, 0.09)
	_sound(&"hit", 1.10, -21.0, 0.12)

func broken(at: Vector2, is_boss: bool) -> void:
	kick(8.0 if is_boss else 3.5, 0.23 if is_boss else 0.15)
	_sparks(at, Color("f7d498"), 48 if is_boss else 16, 560.0 if is_boss else 300.0)
	ring(at, Color("6ed6c5"), 340.0 if is_boss else 95.0, 0.65 if is_boss else 0.35)
	_sound(&"victory" if is_boss else &"kill", 0.95, -10.0 if is_boss else -16.0)

func hurt(at: Vector2) -> void:
	kick(8.0, 0.22)
	_sparks(at, Color("ef8e92"), 12, 260.0)
	ring(at, Color("ef8e92"), 95.0, 0.22)
	_sound(&"hurt", 1.0, -11.0, 0.3)

func phase_changed(at: Vector2) -> void:
	kick(6.0, 0.22)
	ring(at, Color("71e3ce"), 280.0, 0.55)
	_sound(&"boss", 1.05, -16.0, 0.5)

func spawn_marker(at: Vector2) -> void:
	ring(at, Color("c7a785"), 52.0, 0.85)

func _draw() -> void:
	for particle: Dictionary in particles:
		var life: float = 1.0 - float(particle["age"]) / float(particle["life"])
		var tint: Color = particle["color"]
		tint.a = life * 0.90
		var at: Vector2 = particle["p"]
		var velocity: Vector2 = particle["v"]
		draw_line(at, at - velocity.normalized() * (3.0 + life * 11.0), tint, float(particle["size"]) * life + 0.5, true)
	for entry: Dictionary in rings:
		var progress: float = clampf(float(entry["age"]) / float(entry["life"]), 0.0, 1.0)
		var tint: Color = entry["color"]
		tint.a = pow(1.0 - progress, 2.0) * 0.65
		draw_arc(entry["p"], float(entry["radius"]) * (0.25 + 0.75 * progress), 0.0, TAU, 48, tint, 2.0 + 2.0 * (1.0 - progress), true)
