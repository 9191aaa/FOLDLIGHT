class_name FoldlightMiasmaWraith
extends FoldlightRogueEnemyActor

signal poison_requested(snapshot: Dictionary)

const CLOUD_INTERVAL: float = 2.2
const CLOUD_RADIUS: float = 112.0
const CLOUD_WARNING: float = 0.85
const CLOUD_DURATION: float = 5.5
const CLOUD_TICK_INTERVAL: float = 1.6
const PAPER_COLOR := Color("a9b58c")
const INK_COLOR := Color("243a34")

var _cloud_remaining: float = 1.4
var _cloud_serial: int = 0
var _simulation_active: bool = true
var _motion_scale: float = 1.0


func _ready() -> void:
	super._ready()
	set_simulation_active(_simulation_active)


func configure(new_definition: FoldlightRogueEnemyDefinition, new_actor_id: StringName) -> void:
	super.configure(new_definition, new_actor_id)
	_cloud_remaining = 1.4
	_cloud_serial = 0
	velocity = Vector2.ZERO
	set_simulation_active(true)


func set_simulation_active(value: bool) -> void:
	_simulation_active = value
	if value:
		var profile := get_node_or_null("/root/ProfileManager") if is_inside_tree() else null
		_motion_scale = clampf(float(profile.call("get_setting", &"screen_shake", 1.0)), 0.0, 1.0) if profile != null else 1.0


func advance_simulation(delta: float, new_target_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if not _simulation_active or definition == null or health <= 0.0:
		return
	var step := clampf(maxf(0.0, delta) * clampf(hostile_time_scale, 0.0, 2.0), 0.0, 0.1)
	if step <= 0.0:
		return
	target_position = new_target_position
	_age += step
	_hit_reaction.advance(step)
	_flash = _hit_reaction.flash
	var toward := global_position.direction_to(target_position)
	var distance := global_position.distance_to(target_position)
	var radial := clampf((distance - 225.0) / 150.0, -0.55, 1.0)
	var tangent := toward.orthogonal() * sin(_age * 0.8 + _phase) * 0.38
	var desired := (toward * radial + tangent).limit_length() * definition.move_speed * command_move_multiplier
	velocity = velocity.move_toward(desired, definition.move_speed * 3.0 * step)
	move_and_slide()
	_cloud_remaining = maxf(0.0, _cloud_remaining - step)
	if _cloud_remaining <= 0.00001:
		_cloud_serial += 1
		poison_requested.emit({
			"position": global_position, "source_id": actor_id, "serial": _cloud_serial,
			"radius": CLOUD_RADIUS, "warning_duration": CLOUD_WARNING,
			"duration": CLOUD_DURATION, "tick_interval": CLOUD_TICK_INTERVAL, "damage": 1,
		})
		_cloud_remaining = CLOUD_INTERVAL * support_attack_multiplier
	RenderRedraw.request(self)


func get_contact_radius() -> float:
	return 29.0


func get_combat_snapshot() -> Dictionary:
	var result := super.get_combat_snapshot()
	result["classic_archetype"] = &"miasma_wraith"
	result["visual_version"] = &"miasma_paper_3_18"
	result["maximum_health"] = float(get_meta("directed_maximum_health", definition.base_health if definition != null else 10.0))
	result["cloud_remaining"] = _cloud_remaining
	result["cloud_serial"] = _cloud_serial
	return result


func _draw() -> void:
	var paper := PAPER_COLOR.lerp(Color("e3e4cc"), _flash * 0.45)
	var sway := sin(_age * 1.6 + _phase) * 2.0 * _motion_scale
	draw_set_transform(Vector2(0.0, sway), 0.0, Vector2.ONE)
	# Split folded skirt and a dark hood read as a carrier, without particles.
	var mantle := PackedVector2Array([Vector2(0, -39), Vector2(31, -9), Vector2(23, 29), Vector2(9, 18), Vector2(0, 40), Vector2(-13, 20), Vector2(-27, 31), Vector2(-32, -7)])
	draw_colored_polygon(mantle, INK_COLOR)
	draw_polyline(PackedVector2Array(Array(mantle) + [mantle[0]]), Color(paper, 0.92), 2.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -36), Vector2(21, -6), Vector2(3, 18), Vector2(-8, -10)]), Color("526951"))
	draw_line(Vector2(0, -33), Vector2(0, 30), Color(paper, 0.42), 1.5, true)
	draw_line(Vector2(-24, -2), Vector2(-13, 22), Color(paper, 0.45), 1.5, true)
	draw_line(Vector2(25, -2), Vector2(11, 23), Color(paper, 0.45), 1.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -24), Vector2(12, -6), Vector2(0, 5), Vector2(-12, -6)]), Color("101f23"))
	draw_line(Vector2(-7, -8), Vector2(-2, -6), paper, 2.5, true)
	draw_line(Vector2(2, -6), Vector2(7, -8), paper, 2.5, true)
	# A fixed three-leaf glyph matches the poison boundary's centre mark.
	for index in 3:
		var direction := Vector2.from_angle(-PI * 0.5 + index * TAU / 3.0)
		var side := direction.orthogonal()
		var center := Vector2(0, 18)
		draw_colored_polygon(PackedVector2Array([center + direction * 12.0, center + direction * 4.0 + side * 4.0, center, center + direction * 4.0 - side * 4.0]), Color(paper, 0.83))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var maximum := float(get_meta("directed_maximum_health", definition.base_health if definition != null else 10.0))
	draw_rect(Rect2(-24, 47, 48, 3), Color("13242b"))
	draw_rect(Rect2(-24, 47, 48 * clampf(health / maxf(1.0, maximum), 0.0, 1.0), 3), paper)
