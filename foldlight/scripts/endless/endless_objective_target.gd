extends StaticBody2D

## A real, stationary combat target. It shares projectile/AOE collision and
## damage feedback with enemies, but never deals contact damage or counts a kill.
signal damage_reported(target_id: StringName, actual_damage: float)
signal destroyed(target_id: StringName)
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
var _draw_clock: float = 0.0


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
		set_feedback_motion_scale(float(profile.get_setting("screen_shake", 0.7)))
	queue_redraw()


func set_feedback_motion_scale(value: float) -> void:
	_motion_scale = clampf(value, 0.0, 1.0)
	queue_redraw()


func configure(snapshot: Dictionary) -> void:
	target_id = StringName(snapshot.get("target_id", &""))
	actor_id = target_id
	target_position = Vector2(snapshot.get("target_position", Vector2.ZERO))
	maximum_health = maxf(1.0, float(snapshot.get("required", 60.0)))
	health = clampf(maximum_health - float(snapshot.get("progress", 0.0)), 0.0, maximum_health)
	_defeat_emitted = false
	_hit_flash = 0.0
	_visual_time = 0.0
	_draw_clock = 0.0
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
	_draw_clock += delta
	if _draw_clock >= 0.05 and (_motion_scale > 0.0 or had_flash):
		_draw_clock = fmod(_draw_clock, 0.05)
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
		# Health subtraction and accumulated task damage can differ by a final
		# floating-point epsilon. Physical death is authoritative for completion.
		destroyed.emit(target_id)
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


func get_art_snapshot() -> Dictionary:
	var ratio := clampf(health / maxf(1.0, maximum_health), 0.0, 1.0)
	return {"health_ratio": ratio, "damage_stage": mini(3, int((1.0 - ratio) * 4.0)), "collision_radius": HIT_RADIUS}


func _draw() -> void:
	var gold := Color("edc675")
	var red := Color("f58b73")
	var paper := Color("fff0cd")
	var sway := sin(_visual_time * 2.1) * 3.0 * _motion_scale
	var art := get_art_snapshot()
	var stage := int(art.damage_stage)
	var flash := clampf(_hit_flash * 4.0, 0.0, 0.7)
	var shadow := PackedVector2Array([Vector2(-43, 25), Vector2(-7, -1), Vector2(43, 22), Vector2(6, 48)])
	draw_colored_polygon(shadow, Color("07171d", 0.55))
	var base := PackedVector2Array([Vector2(-39, 16), Vector2(-5, -11), Vector2(38, 13), Vector2(1, 40)])
	draw_colored_polygon(base, Color("374844").lerp(paper, flash * 0.5))
	draw_colored_polygon(PackedVector2Array([base[0], base[1], base[3]]), Color("526358"))
	draw_polyline(PackedVector2Array([base[0], base[1], base[2], base[3], base[0]]), Color(gold, 0.7), 1.6, true)
	# Paper armour sits inside the unchanged 42px combat hitbox. Missing panels
	# and creases are selected from actual health, never proximity or timers.
	for side in [-1.0, 1.0]:
		var outer := Vector2(side * 30, 4)
		var plate := PackedVector2Array([Vector2(side * 7, -31), outer, Vector2(side * 24, 27), Vector2(side * 5, 17)])
		var tint := red.darkened(0.48 if side < 0 else 0.63).lerp(paper, flash)
		draw_colored_polygon(plate, tint)
		draw_line(plate[0], plate[2], Color(gold, 0.60), 1.3, true)
		if stage >= 1:
			draw_polyline(PackedVector2Array([plate[0].lerp(outer, 0.48), Vector2(side * 12, 0), Vector2(side * 24, 8), Vector2(side * 15, 21)]), Color("101d22"), 3.5, true)
		if stage >= 2:
			draw_colored_polygon(PackedVector2Array([outer, outer + Vector2(-side * 12, -9), outer + Vector2(-side * 10, 10)]), Color("13232a"))
	draw_line(Vector2(-7, 20), Vector2(-7, -69), paper.darkened(0.18), 4.0, true)
	var pennant := PackedVector2Array([Vector2(-6, -69), Vector2(44 + sway, -54), Vector2(27 + sway, -34), Vector2(-6, -40)])
	if stage >= 2:
		pennant = PackedVector2Array([pennant[0], pennant[1], Vector2(30 + sway, -48), Vector2(21 + sway, -45), Vector2(25 + sway, -37), pennant[3]])
	draw_colored_polygon(pennant, red.darkened(0.18).lerp(paper, flash))
	draw_colored_polygon(PackedVector2Array([pennant[0], pennant[1], Vector2(-6, -50)]), Color(gold.darkened(0.26), 0.90))
	draw_line(pennant[0], pennant[1], gold, 1.5, true)
	if stage >= 3:
		draw_line(Vector2(-4, -65), Vector2(11 + sway, -44), Color("16252b"), 4.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -15), Vector2(11, -1), Vector2(0, 14), Vector2(-11, -1)]), red.lerp(paper, flash))
	draw_rect(Rect2(-43, 59, 86, 5), Color("263843"))
	draw_rect(Rect2(-43, 59, 86 * float(art.health_ratio), 5), gold)
	if _font != null:
		draw_string(_font, Vector2(-44, 89), "火力旗 · %.0f" % health, HORIZONTAL_ALIGNMENT_CENTER, 88, 17, paper)
