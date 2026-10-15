extends StaticBody2D

## A real, stationary combat target. It shares projectile/AOE collision and
## damage feedback with enemies, but never deals contact damage or counts a kill.
signal damage_reported(target_id: StringName, actual_damage: float)
signal defeated(actor: Node2D)

const SharedTheme = preload("res://scripts/ui/foldlight_theme.gd")
const HIT_RADIUS: float = 42.0

var definition: FoldlightRogueEnemyDefinition
var actor_id: StringName = &""
var target_id: StringName = &""
var target_position: Vector2 = Vector2.ZERO
var health: float = 1.0
var maximum_health: float = 1.0
var _simulation_active: bool = false
var _defeat_emitted: bool = false
var _visual_time: float = 0.0
var _hit_flash: float = 0.0
var _hit_direction: Vector2 = Vector2.UP
var _motion_scale: float = 1.0
var _font: Font


func _init() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	add_child(shape)


func _ready() -> void:
	_font = SharedTheme.body_font()
	var profile := get_node_or_null("/root/ProfileManager") as FoldlightProfileManager
	if profile != null:
		_motion_scale = clampf(float(profile.get_setting("screen_shake", 0.7)), 0.0, 1.0)
	queue_redraw()


func configure(snapshot: Dictionary) -> void:
	target_id = StringName(snapshot.get("target_id", &""))
	actor_id = target_id
	target_position = Vector2(snapshot.get("target_position", Vector2.ZERO))
	maximum_health = maxf(1.0, float(snapshot.get("required", 60.0)))
	health = clampf(maximum_health - float(snapshot.get("progress", 0.0)), 0.0, maximum_health)
	_defeat_emitted = false
	definition = FoldlightRogueEnemyDefinition.new()
	definition.content_id = &"endless_fire_flag"
	definition.title = "火力旗"
	definition.base_health = maximum_health
	definition.stationary = true
	definition.move_speed = 0.0
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	_simulation_active = value


func advance_simulation(delta: float, _target: Vector2 = Vector2.ZERO, _hostile_time_scale: float = 1.0) -> void:
	if not _simulation_active or delta <= 0.0 or not is_finite(delta):
		return
	var had_flash := _hit_flash > 0.0
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_visual_time += delta * _motion_scale
	if _motion_scale > 0.0 or had_flash:
		queue_redraw()


func take_damage(amount: float) -> bool:
	if not _simulation_active or _defeat_emitted or is_queued_for_deletion() or health <= 0.0 or not is_finite(amount) or amount <= 0.0:
		return false
	var actual_damage := minf(amount, health)
	health -= actual_damage
	_hit_flash = 0.18
	queue_redraw()
	# Resolve state before notifying listeners, which can synchronously pause.
	var lethal := health <= 0.0
	if lethal:
		_defeat_emitted = true
	damage_reported.emit(target_id, actual_damage)
	if lethal:
		defeated.emit(self)
	# Shared combat interprets this return value as defeat, not hit acceptance.
	return lethal


func take_projectile_damage(amount: float, velocity: Vector2, _style: StringName) -> bool:
	if not velocity.is_zero_approx():
		_hit_direction = velocity.normalized()
	return take_damage(amount)


func get_combat_snapshot() -> Dictionary:
	return {"actor_id": actor_id, "position": global_position, "health": health, "maximum_health": maximum_health, "alive": health > 0.0, "is_objective_target": true}


func get_hit_feedback_snapshot() -> Dictionary:
	return {"direction": _hit_direction, "flash": _hit_flash}


func _draw() -> void:
	var gold := Color("edc675")
	var red := Color("f58b73")
	var paper := Color("fff0cd")
	var sway := sin(_visual_time * 2.1) * 3.0 * _motion_scale
	draw_circle(Vector2.ZERO, 48.0, Color(gold, 0.08))
	draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 32, Color(gold, 0.65), 2.0, true)
	draw_line(Vector2(-10, 27), Vector2(-10, -57), paper, 4.0, true)
	var pennant := PackedVector2Array([Vector2(-9, -57), Vector2(43 + sway, -43), Vector2(25 + sway, -26), Vector2(-9, -32)])
	draw_colored_polygon(pennant, red.lerp(paper, clampf(_hit_flash * 4.0, 0.0, 0.7)))
	draw_polyline(PackedVector2Array([pennant[0], pennant[1], pennant[2], pennant[3], pennant[0]]), gold, 2.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-29, 21), Vector2(0, -10), Vector2(28, 21), Vector2(0, 38)]), Color("273e4b"))
	draw_polyline(PackedVector2Array([Vector2(-29, 21), Vector2(0, -10), Vector2(28, 21), Vector2(0, 38), Vector2(-29, 21)]), gold, 2.0, true)
	draw_circle(Vector2(0, 16), 10.0, red.lerp(paper, clampf(_hit_flash * 5.0, 0.0, 1.0)))
	draw_rect(Rect2(-43, 60, 86, 5), Color("263843"))
	draw_rect(Rect2(-43, 60, 86 * clampf(health / maximum_health, 0.0, 1.0), 5), gold)
	if _font != null:
		draw_string(_font, Vector2(-44, 89), "火力旗 · %.0f" % health, HORIZONTAL_ALIGNMENT_CENTER, 88, 17, paper)
