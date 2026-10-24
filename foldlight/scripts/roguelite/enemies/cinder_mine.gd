class_name FoldlightCinderMine
extends CharacterBody2D

const RenderRedraw = preload("res://scripts/visuals/render_redraw.gd")

signal blast_requested(snapshot: Dictionary)
signal damaged(amount: float, health_remaining: float)
signal defeated(actor: Node2D)

enum Phase { APPROACH, CHARGING, SPENT }

const LABEL_FONT: Font = preload("res://assets/fonts/FoldlightSansSC.woff2")

@export_range(0.5, 3.0, 0.1) var charge_duration: float = 1.5
@export_range(80.0, 240.0, 5.0) var blast_radius: float = 160.0
@export_range(100.0, 280.0, 5.0) var trigger_distance: float = 185.0
@export_range(0.1, 2.0, 0.1) var spawn_grace: float = 0.6

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &"cinder_mine"
var health: float = 5.0
var phase: Phase = Phase.APPROACH
var command_move_multiplier: float = 1.0
var _remaining: float = 0.0
var _arming_remaining: float = 0.0
var _visual_time: float = 0.0
var _motion_scale: float = 1.0
var _hit_flash: float = 0.0
var _hit_direction := Vector2.UP


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	set_simulation_active(true)


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	definition = new_definition
	actor_id = new_actor_id
	health = definition.base_health if definition != null else 5.0
	phase = Phase.APPROACH
	command_move_multiplier = 1.0
	_remaining = 0.0
	_arming_remaining = spawn_grace
	_visual_time = 0.0
	_hit_flash = 0.0
	velocity = Vector2.ZERO
	set_meta("defeat_reason", &"damage")
	set_meta("grants_kill_credit", true)
	RenderRedraw.request(self)


func advance_simulation(delta: float, target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if health <= 0.0 or phase == Phase.SPENT:
		return
	# Never consume a complete warning in one stalled mobile/browser frame.
	var step := clampf(maxf(0.0, delta) * clampf(hostile_time_scale, 0.0, 2.0), 0.0, 0.1)
	if step <= 0.0:
		return
	_visual_time += step * _motion_scale
	_hit_flash = maxf(0.0, _hit_flash - step * 6.0)
	match phase:
		Phase.APPROACH:
			_arming_remaining = maxf(0.0, _arming_remaining - step)
			var offset := target_position - global_position
			var speed := (definition.move_speed if definition != null else 280.0) * command_move_multiplier
			velocity = velocity.move_toward(offset.normalized() * speed, speed * 4.0 * step)
			if _arming_remaining <= 0.00001 and offset.length() <= trigger_distance:
				phase = Phase.CHARGING
				_remaining = charge_duration
				velocity = Vector2.ZERO
		Phase.CHARGING:
			# The danger circle is anchored for its entire countdown, including
			# when the player dashes behind it or leaves its range.
			velocity = Vector2.ZERO
			_remaining = maxf(0.0, _remaining - step)
			if _remaining <= 0.00001:
				phase = Phase.SPENT
				health = 0.0
				set_meta("defeat_reason", &"self_detonation")
				set_meta("grants_kill_credit", false)
				blast_requested.emit({"origin": global_position, "radius": blast_radius, "source_id": actor_id})
				defeated.emit(self)
				return
	move_and_slide()
	RenderRedraw.request(self)


func take_damage(amount: float) -> bool:
	if health <= 0.0 or amount <= 0.0 or phase == Phase.SPENT:
		return false
	var applied := minf(health, amount)
	health -= applied
	_hit_flash = 1.0
	damaged.emit(applied, health)
	if health <= 0.0:
		# Destruction disarms the fuse. A death never schedules another blast.
		phase = Phase.SPENT
		_remaining = 0.0
		velocity = Vector2.ZERO
		defeated.emit(self)
		return true
	RenderRedraw.request(self)
	return false


func take_projectile_damage(amount: float, incoming_velocity: Vector2, _style: StringName) -> bool:
	if not incoming_velocity.is_zero_approx():
		_hit_direction = incoming_velocity.normalized()
	return take_damage(amount)


func is_contact_dangerous() -> bool:
	# There is no hidden touch hit before the fully telegraphed explosion.
	return false


func get_contact_radius() -> float:
	return 25.0


func set_command_buff(snapshot: Dictionary) -> void:
	# A commander accelerates pursuit, never the committed fuse: the anchored
	# blast retains its complete readable escape window at every difficulty.
	command_move_multiplier = clampf(float(snapshot.get("move_multiplier", 1.0)), 1.0, 2.2)


func set_simulation_active(value: bool) -> void:
	if value:
		var profile := get_node_or_null("/root/ProfileManager")
		_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0


func get_phase_snapshot() -> Dictionary:
	return {"phase": phase, "remaining": _remaining, "radius": blast_radius, "anchored": phase == Phase.CHARGING, "visual_time": _visual_time}


func get_combat_snapshot() -> Dictionary:
	return {"id": actor_id, "position": global_position, "alive": health > 0.0, "role": FoldlightRogueEnemyDefinition.EnemyRole.CHARGER, "health": health, "maximum_health": _maximum_health(), "contact_dangerous": false}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"flash": _hit_flash, "punch": _hit_flash * 0.7, "direction": _hit_direction}


func _maximum_health() -> float:
	return float(get_meta("directed_maximum_health", definition.base_health if definition != null else 5.0))


func _draw() -> void:
	if phase == Phase.SPENT:
		return
	var charging := phase == Phase.CHARGING
	var progress := 1.0 - clampf(_remaining / charge_duration, 0.0, 1.0) if charging else 0.0
	var ember := Color("f3a66a").lerp(Color("fff0cf"), _hit_flash * 0.85)
	var danger := Color("f17665")
	if charging:
		# Fixed boundary, hatching, and a countdown remain clear without motion.
		draw_circle(Vector2.ZERO, blast_radius, Color(danger, 0.075 + progress * 0.06))
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 64, Color(danger, 0.85), 2.0, true)
		draw_arc(Vector2.ZERO, blast_radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, ember, 4.0, true)
		for index in 12:
			var ray := Vector2.from_angle(float(index) * TAU / 12.0)
			draw_line(ray * (blast_radius - 14.0), ray * blast_radius, Color(danger, 0.8), 2.0, true)
		var caption := "自爆 %.1fs" % _remaining
		var font := LABEL_FONT
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_rect(Rect2(Vector2(-text_size.x * 0.5 - 7, -79), Vector2(text_size.x + 14, 25)), Color("192331"))
		draw_string(font, Vector2(-text_size.x * 0.5, -61), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ember)
	var breathe := sin(_visual_time * 4.0) * 1.8 * _motion_scale
	draw_set_transform(Vector2(0, breathe if not charging else 0.0), 0.0, Vector2.ONE)
	for side in [-1.0, 1.0]:
		var fin := PackedVector2Array([Vector2(side * 15, -21), Vector2(side * (40 + progress * 5), -6), Vector2(side * 25, 27), Vector2(side * 9, 14)])
		draw_colored_polygon(fin, Color("503b3e"))
		draw_polyline(PackedVector2Array(Array(fin) + [fin[0]]), Color(ember, 0.75), 1.8, true)
		draw_line(fin[0], fin[2], Color(ember, 0.32), 1.0, true)
	var body := PackedVector2Array([Vector2(0, -34), Vector2(24, 0), Vector2(0, 35), Vector2(-24, 0)])
	draw_colored_polygon(body, Color("382f3b").lerp(Color("825044"), progress))
	draw_polyline(PackedVector2Array(Array(body) + [body[0]]), ember, 2.5, true)
	draw_line(Vector2(0, -30), Vector2(0, 31), Color(ember, 0.4), 1.5, true)
	var core := PackedVector2Array([Vector2(0, -14), Vector2(9, 1), Vector2(0, 16), Vector2(-9, 1)])
	draw_colored_polygon(core, danger.lerp(ember, progress))
	for index in 3:
		var live := not charging or progress < float(3 - index) / 3.0
		draw_line(Vector2(-9 + index * 9, -41), Vector2(-9 + index * 9, -35), ember if live else Color("55454b"), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ratio := clampf(health / maxf(1.0, _maximum_health()), 0.0, 1.0)
	draw_rect(Rect2(-23, 43, 46, 3), Color("172332"))
	draw_rect(Rect2(-23, 43, 46 * ratio, 3), ember)
