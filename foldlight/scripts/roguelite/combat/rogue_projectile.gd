class_name FoldlightRogueProjectile
extends Node2D

var velocity: Vector2 = Vector2.ZERO
var hostile: bool = false
var reflectable: bool = true
var damage: float = 1.0
var radius: float = 7.0
var lifetime: float = 4.0
var pierce_remaining: int = 0
var style: StringName = &"crease_petal"
var projectile_color: Color = Color(0.68, 0.27, 0.70)
var projectile_kind: int = 0
var target_position: Vector2 = Vector2.ZERO
var age: float = 0.0
var fold_slowed: bool = false
var hit_actor_ids: Dictionary = {}
var echo_chance: float = 0.0
var execute_damage_multiplier: float = 1.0
var is_echo: bool = false
var high_contrast: bool = false
var homing_target: Node2D
var homing_strength: float = 0.0
var homing_range: float = 1500.0
var homing_speed: float = 0.0
var navigation_waypoints: PackedVector2Array = PackedVector2Array()
var navigation_waypoint_index: int = 0
var navigation_repath_interval: float = 0.24
var navigation_repath_remaining: float = 0.0
var return_relay_used: bool = false
var return_chain_remaining: int = 0
var launch_delay: float = 0.0
var orbit_anchor: Node2D
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0
var orbit_speed: float = 4.2
var curve: float = 0.0
var status_id: StringName = &""
var status_duration: float = 0.0
var automatic_weapon_id: StringName = &""
var area_radius: float = 150.0
var destination_reached: bool = false
var explosion_resolved: bool = false
var return_damage_multiplier: float = 1.0
var return_after: float = 0.65
var return_anchor: Node2D
var _leg_pierce_budget: int = 0
var _leg_exhausted: bool = false
var _has_returned: bool = false
var _trail_clock: float = 0.0
var _trail_points: Array[Vector2] = []
var _previous_global_position: Vector2 = Vector2.ZERO
var _return_relay_pulse_remaining: float = 0.0
var _visual_redraw_requests: int = 0

const RETURN_RELAY_PULSE_DURATION: float = 0.24


func configure(snapshot: Dictionary) -> void:
	global_position = Vector2(snapshot.get("origin", global_position))
	velocity = Vector2(snapshot.get("velocity", velocity))
	hostile = bool(snapshot.get("hostile", hostile))
	reflectable = bool(snapshot.get("reflectable", reflectable))
	damage = maxf(0.1, float(snapshot.get("damage", damage)))
	radius = clampf(float(snapshot.get("radius", radius)), 3.0, 22.0)
	lifetime = clampf(float(snapshot.get("lifetime", lifetime)), 0.2, 8.0)
	pierce_remaining = clampi(int(snapshot.get("pierce", pierce_remaining)), 0, 12)
	style = StringName(snapshot.get("style", style))
	projectile_color = Color(snapshot.get("color", projectile_color))
	projectile_kind = clampi(int(snapshot.get("kind", projectile_kind)), 0, 2)
	target_position = Vector2(snapshot.get("target_position", target_position))
	echo_chance = clampf(float(snapshot.get("echo_chance", echo_chance)), 0.0, 0.75)
	execute_damage_multiplier = maxf(1.0, float(snapshot.get("execute_damage_multiplier", execute_damage_multiplier)))
	is_echo = bool(snapshot.get("is_echo", false))
	var target_variant: Variant = snapshot.get("homing_target")
	homing_target = target_variant as Node2D if target_variant is Node2D else null
	homing_strength = clampf(float(snapshot.get("homing_strength", 0.0)), 0.0, 14.0)
	homing_range = clampf(float(snapshot.get("homing_range", 1500.0)), 120.0, 2400.0)
	homing_speed = clampf(float(snapshot.get("homing_speed", 0.0)), 0.0, 1600.0)
	var waypoint_variant: Variant = snapshot.get("navigation_waypoints", PackedVector2Array())
	navigation_waypoints = PackedVector2Array(waypoint_variant) if waypoint_variant is PackedVector2Array else PackedVector2Array()
	navigation_waypoint_index = 0
	navigation_repath_interval = clampf(float(snapshot.get("navigation_repath_interval", 0.24)), 0.14, 0.50)
	navigation_repath_remaining = clampf(float(snapshot.get("navigation_repath_delay", navigation_repath_interval)), 0.0, navigation_repath_interval)
	return_relay_used = bool(snapshot.get("return_relay_used", false))
	return_chain_remaining = maxi(0, int(snapshot.get("return_chain_remaining", 0)))
	_return_relay_pulse_remaining = 0.0
	launch_delay = clampf(float(snapshot.get("launch_delay", 0.0)), 0.0, 1.2)
	var anchor_variant: Variant = snapshot.get("orbit_anchor")
	orbit_anchor = anchor_variant as Node2D if anchor_variant is Node2D else null
	orbit_radius = clampf(float(snapshot.get("orbit_radius", 0.0)), 0.0, 160.0)
	orbit_angle = float(snapshot.get("orbit_angle", velocity.angle()))
	orbit_speed = clampf(float(snapshot.get("orbit_speed", 4.2)), -12.0, 12.0)
	curve = clampf(float(snapshot.get("curve", 0.0)), -2.0, 2.0)
	status_id = StringName(snapshot.get("status", &""))
	status_duration = maxf(0.0, float(snapshot.get("status_duration", 0.0)))
	automatic_weapon_id = StringName(snapshot.get("automatic_weapon_id", &""))
	area_radius = clampf(float(snapshot.get("area_radius", 150.0)), 60.0, 260.0)
	return_damage_multiplier = clampf(float(snapshot.get("return_damage_multiplier", 1.0)), 1.0, 2.0)
	return_after = clampf(float(snapshot.get("return_after", 0.65)), 0.1, 3.6)
	var return_anchor_variant: Variant = snapshot.get("return_anchor")
	return_anchor = return_anchor_variant as Node2D if return_anchor_variant is Node2D else null
	_leg_pierce_budget = pierce_remaining
	_leg_exhausted = false
	_has_returned = false
	destination_reached = false
	explosion_resolved = false
	if launch_delay > 0.0 and is_instance_valid(orbit_anchor):
		global_position = orbit_anchor.global_position + Vector2.from_angle(orbit_angle) * orbit_radius
	_previous_global_position = global_position
	_trail_points.clear()
	_visual_redraw_requests = 0
	var profile_manager := get_node_or_null("/root/ProfileManager")
	high_contrast = bool(profile_manager.call("get_setting", &"high_contrast", false)) if profile_manager != null else false
	sync_visual_direction()
	_queue_visual_redraw()


func advance_simulation(delta: float, time_scale: float = 1.0) -> bool:
	var step := maxf(0.0, delta) * clampf(time_scale, 0.1, 2.0)
	age += step
	lifetime -= step
	_return_relay_pulse_remaining = maxf(0.0, _return_relay_pulse_remaining - step)
	var movement_step := step
	if launch_delay > 0.0:
		var orbit_step := minf(movement_step, launch_delay)
		launch_delay = maxf(0.0, launch_delay - orbit_step)
		orbit_angle += orbit_speed * orbit_step
		if is_instance_valid(orbit_anchor):
			global_position = orbit_anchor.global_position + Vector2.from_angle(orbit_angle) * orbit_radius
		movement_step -= orbit_step
		if movement_step <= 0.0:
			_refresh_moving_visual()
			return lifetime <= 0.0
	_previous_global_position = global_position
	if homing_strength > 0.0 and is_instance_valid(homing_target):
		_advance_navigation_waypoint()
		var homing_position := homing_target.global_position
		if navigation_waypoint_index < navigation_waypoints.size():
			homing_position = navigation_waypoints[navigation_waypoint_index]
		var offset := homing_position - global_position
		if offset.length() <= homing_range and not offset.is_zero_approx():
			var speed := homing_speed if homing_speed > 0.0 else maxf(1.0, velocity.length())
			var desired := offset.normalized() * speed
			velocity = velocity.lerp(desired, clampf(homing_strength * movement_step, 0.0, 0.92)).normalized() * speed
	if style == &"returning_gull" and age >= return_after and not _has_returned:
		velocity = -velocity
		_has_returned = true
		# A gull can strike once on its outward leg and once on its return.
		# Per-leg pierce is still bounded; stationary overlap never repeats damage.
		hit_actor_ids.clear()
		pierce_remaining = _leg_pierce_budget
		_leg_exhausted = false
		damage *= return_damage_multiplier
	if style == &"returning_gull" and _has_returned and is_instance_valid(return_anchor):
		var return_offset := return_anchor.global_position - global_position
		if return_offset.length() <= maxf(22.0, velocity.length() * movement_step):
			return true
		velocity = velocity.lerp(return_offset.normalized() * velocity.length(), clampf(9.0 * movement_step, 0.0, 1.0)).normalized() * velocity.length()
	if not is_zero_approx(curve):
		velocity = velocity.rotated(curve * movement_step)
	if style == &"tide_bell" and not hostile and not is_echo and global_position.distance_to(target_position) <= maxf(radius, velocity.length() * movement_step):
		global_position = target_position
		destination_reached = true
	else:
		global_position += velocity * movement_step
	_trail_clock -= movement_step
	if _trail_clock <= 0.0 and (style == &"return_light" or homing_strength > 0.0):
		_trail_clock = 0.035
		_trail_points.push_front(global_position)
		if _trail_points.size() > 9:
			_trail_points.pop_back()
	_refresh_moving_visual()
	return lifetime <= 0.0


func _uses_rotating_hostile_visual() -> bool:
	return hostile and style != &"return_light" and style != &"sun_thread" and style != &"tide_bell"


func sync_visual_direction() -> void:
	# Hostile paper shapes never change after configuration. Let the canvas
	# transform rotate their retained commands, rather than rebuilding hundreds
	# of outlines and PackedArrays on every physics tick. Simulation still uses
	# world-space velocity/radius, exactly as before.
	if _uses_rotating_hostile_visual():
		rotation = velocity.angle() + sin(age * 5.0) * 0.08
	elif not hostile and style in [&"crease_petal", &"needle_orbit", &"returning_gull", &"prism_fan", &"sun_thread"]:
		rotation = velocity.angle() if launch_delay <= 0.0 else orbit_angle + PI * 0.5
	else:
		rotation = 0.0


func _refresh_moving_visual() -> void:
	sync_visual_direction()
	# Only returned light has a changing trail/relay pulse. Other friendly
	# silhouettes and hostile outlines are static geometry moved by Node2D.
	if style == &"return_light":
		_queue_visual_redraw()


func _queue_visual_redraw() -> void:
	_visual_redraw_requests += 1
	queue_redraw()


func get_visual_budget_snapshot() -> Dictionary:
	return {"redraw_requests": _visual_redraw_requests, "cached_geometry": style != &"return_light"}


func set_homing_target(target: Node2D) -> void:
	homing_target = target


func set_navigation_route(target: Node2D, waypoints: PackedVector2Array, refresh_delay: float = -1.0) -> void:
	homing_target = target
	navigation_waypoints = waypoints
	navigation_waypoint_index = 0
	_advance_navigation_waypoint()
	navigation_repath_remaining = navigation_repath_interval if refresh_delay < 0.0 else clampf(refresh_delay, 0.0, navigation_repath_interval)


func can_activate_return_relay() -> bool:
	return style == &"return_light" and not is_echo and not return_relay_used


func can_activate_return_chain() -> bool:
	return style == &"return_light" and not is_echo and return_chain_remaining > 0


func activate_return_chain(target: Node2D, waypoints: PackedVector2Array) -> bool:
	if not can_activate_return_chain() or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	return_chain_remaining -= 1
	_return_relay_pulse_remaining = RETURN_RELAY_PULSE_DURATION
	set_navigation_route(target, waypoints, navigation_repath_interval)
	var aim_position := target.global_position
	if navigation_waypoint_index < navigation_waypoints.size():
		aim_position = navigation_waypoints[navigation_waypoint_index]
	var chain_direction := global_position.direction_to(aim_position)
	var chain_speed := maxf(1.0, homing_speed if homing_speed > 0.0 else velocity.length())
	if not chain_direction.is_zero_approx():
		velocity = chain_direction * chain_speed
	return true


func activate_return_relay(target: Node2D, waypoints: PackedVector2Array) -> bool:
	if not can_activate_return_relay() or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	return_relay_used = true
	_return_relay_pulse_remaining = RETURN_RELAY_PULSE_DURATION
	set_navigation_route(target, waypoints, navigation_repath_interval)
	var aim_position := target.global_position
	if navigation_waypoint_index < navigation_waypoints.size():
		aim_position = navigation_waypoints[navigation_waypoint_index]
	var relay_direction := global_position.direction_to(aim_position)
	var relay_speed := maxf(1.0, homing_speed if homing_speed > 0.0 else velocity.length())
	if not relay_direction.is_zero_approx():
		velocity = relay_direction * relay_speed
	var relay_distance := 0.0
	var previous_point := global_position
	for waypoint_index in range(navigation_waypoint_index, navigation_waypoints.size()):
		var waypoint := navigation_waypoints[waypoint_index]
		relay_distance += previous_point.distance_to(waypoint)
		previous_point = waypoint
	var required_lifetime := relay_distance / relay_speed + 0.75
	lifetime = maxf(lifetime, clampf(required_lifetime, 0.8, 5.6))
	_trail_clock = 0.0
	_queue_visual_redraw()
	return true


func advance_navigation_refresh(delta: float) -> void:
	navigation_repath_remaining = maxf(0.0, navigation_repath_remaining - maxf(0.0, delta))


func navigation_refresh_due() -> bool:
	return navigation_repath_remaining <= 0.0


func request_navigation_refresh() -> void:
	navigation_repath_remaining = 0.0


func recover_from_solid(obstacle_center: Vector2) -> void:
	# A route may become stale when its target crosses behind cover. Return light is
	# stored player power, so recover it to the last safe sample instead of erasing it.
	global_position = _previous_global_position
	var escape_direction := obstacle_center.direction_to(global_position)
	if escape_direction.is_zero_approx():
		escape_direction = -velocity.normalized()
	if escape_direction.is_zero_approx():
		escape_direction = Vector2.UP
	var tangent := escape_direction.orthogonal()
	if tangent.dot(velocity) < 0.0:
		tangent = -tangent
	velocity = (tangent * 0.72 + escape_direction * 0.28).normalized() * maxf(1.0, velocity.length())
	request_navigation_refresh()
	_queue_visual_redraw()


func has_valid_homing_target() -> bool:
	return is_instance_valid(homing_target) and not homing_target.is_queued_for_deletion()


func consume_pierce() -> bool:
	if pierce_remaining > 0:
		pierce_remaining -= 1
		return false
	if style == &"returning_gull" and not is_echo:
		_leg_exhausted = true
		return false
	return true


func can_hit_actor() -> bool:
	return not _leg_exhausted


func get_navigation_snapshot() -> Dictionary:
	return {
		"waypoint_count": navigation_waypoints.size(),
		"waypoint_index": navigation_waypoint_index,
		"repath_interval": navigation_repath_interval,
		"repath_remaining": navigation_repath_remaining,
		"trail_samples": _trail_points.size(),
		"relay_used": return_relay_used,
		"relay_pulse": _return_relay_pulse_remaining,
	}


func _advance_navigation_waypoint() -> void:
	while navigation_waypoint_index < navigation_waypoints.size():
		var waypoint := navigation_waypoints[navigation_waypoint_index]
		var arrival_radius := maxf(26.0, radius * 2.8)
		if global_position.distance_squared_to(waypoint) > arrival_radius * arrival_radius:
			break
		navigation_waypoint_index += 1


func _draw() -> void:
	var color := Color(1.0, 0.96, 0.80) if high_contrast and hostile and reflectable else projectile_color
	if not hostile and automatic_weapon_id.is_empty():
		color = Color(0.38, 0.96, 0.86)
	if style == &"return_light":
		_draw_classic_return_light()
	elif style == &"sun_thread":
		draw_line(Vector2(-27, 0), Vector2(21, 0), Color(color, 0.25), 8.0, true)
		draw_line(Vector2(-24, 0), Vector2(21, 0), color, 3.2, true)
		draw_line(Vector2(-9, 0), Vector2(19, 0), Color(1.0, 0.96, 0.77), 1.2, true)
	elif style == &"tide_bell":
		draw_circle(Vector2.ZERO, radius + 5.0, Color(color, 0.20))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 16, color, 3.0, true)
	elif hostile:
		_draw_classic_hostile(color)
	elif style == &"needle_orbit":
		draw_line(Vector2(-15, 0), Vector2(12, 0), Color(color, 0.26), 6.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(15, 0), Vector2(-9, 3), Vector2(-5, 0), Vector2(-9, -3)]), color)
	elif style == &"returning_gull":
		draw_polyline(PackedVector2Array([Vector2(-13, -11), Vector2(8, 0), Vector2(-13, 11)]), color, 4.0, true)
		draw_line(Vector2(-4, 0), Vector2(12, 0), Color(0.95, 1.0, 0.91), 2.0, true)
	elif style == &"prism_fan":
		draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(-7, 6), Vector2(-3, 0), Vector2(-7, -6)]), color)
		draw_line(Vector2(-2, 0), Vector2(8, 0), Color(1.0, 0.94, 1.0), 1.5, true)
	else:
		var diamond := PackedVector2Array([Vector2(radius, 0), Vector2(0, radius * 0.65), Vector2(-radius, 0), Vector2(0, -radius * 0.65)])
		draw_colored_polygon(diamond, color)


func get_visual_contract() -> Dictionary:
	if style == &"return_light":
		return {
			"version": &"classic_2_0_exact",
			"motif": &"gold_diamond_return",
			"length": 11.0,
			"width": 5.0,
			"trail": 28.0,
			"trajectory_samples": 9,
			"trajectory_animated": true,
		}
	if hostile:
		return {
			"version": &"classic_2_0_exact",
			"motif": &"hostile_fold_petal",
			"length": 18.0 if not reflectable else (12.0 if projectile_kind == 0 else 9.0),
			"width": 8.0 if not reflectable else 6.0,
			"reflectable": reflectable,
		}
	return {"version": &"roguelite_extension", "motif": style}


func _draw_classic_hostile(color: Color) -> void:
	var forward := Vector2.RIGHT
	var side := Vector2.DOWN
	var length := 18.0 if not reflectable else (12.0 if projectile_kind == 0 else 9.0)
	var width := 8.0 if not reflectable else 6.0
	var petal := PackedVector2Array([
		forward * length,
		side * width,
		-forward * length * 0.72,
		-side * width,
	])
	var stroke_color := Color(1.0, 0.50, 0.16, 0.98) if not reflectable else Color(color.r, color.g, color.b, 0.94)
	draw_polyline(PackedVector2Array([petal[0], petal[1], petal[2], petal[3], petal[0]]), stroke_color, 2.4, true)
	draw_line(-forward * 2.2, forward * 3.4, Color(0.06, 0.012, 0.025, 1.0) if not reflectable else Color(1.0, 0.82, 0.70, 0.96), 2.0, true)
	if not reflectable:
		draw_line(-side * 7.0, side * 7.0, Color(1.0, 0.66, 0.20, 0.98), 2.0, true)
		draw_line(-forward * 13.0, -forward * 25.0, Color(0.94, 0.16, 0.18, 0.78), 2.0, true)
	if not status_id.is_empty():
		var status_mark_color := Color(0.46, 0.92, 0.92, 0.94) if status_id == &"wet_ink" else (Color(0.98, 0.48, 0.58, 0.94) if status_id == &"bound_crease" else Color(0.72, 0.54, 1.0, 0.94))
		draw_line(-side * 5.0, side * 5.0, status_mark_color, 2.0, true)


func _draw_classic_return_light() -> void:
	var direction := velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	_draw_return_trajectory(direction)
	if _return_relay_pulse_remaining > 0.0:
		var relay_progress := 1.0 - _return_relay_pulse_remaining / RETURN_RELAY_PULSE_DURATION
		var relay_alpha := pow(1.0 - relay_progress, 1.35)
		var relay_radius := lerpf(radius + 7.0, radius + 34.0, ease(relay_progress, -1.6))
		draw_circle(Vector2.ZERO, relay_radius * 0.72, Color(1.0, 0.72, 0.25, relay_alpha * 0.12))
		draw_arc(Vector2.ZERO, relay_radius, 0.0, TAU, 28, Color(1.0, 0.84, 0.42, relay_alpha * 0.94), lerpf(5.4, 1.8, relay_progress), true)
	draw_line(-direction * 28.0, Vector2.ZERO, Color(0.32, 0.91, 0.85, 0.34), 5.0, true)
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.71, 0.27, 0.06))
	var side := direction.rotated(PI * 0.5)
	var diamond := PackedVector2Array([direction * 11.0, side * 5.0, -direction * 11.0, -side * 5.0])
	draw_colored_polygon(diamond, Color(1.0, 0.78, 0.38, 0.96))
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)


func _draw_return_trajectory(direction: Vector2) -> void:
	if _trail_points.size() < 2:
		return
	var local_trail := PackedVector2Array()
	for point in _trail_points:
		local_trail.append(to_local(point))
	for index in range(local_trail.size() - 1):
		var progress := float(index) / float(maxi(1, local_trail.size() - 1))
		var alpha := lerpf(0.52, 0.045, progress)
		var relay_boost := 1.72 if _return_relay_pulse_remaining > 0.0 else 1.0
		var width := lerpf(5.4, 1.2, progress) * relay_boost
		var trail_color := Color(1.0, 0.78, 0.32, alpha * 1.18) if _return_relay_pulse_remaining > 0.0 else Color(0.32, 0.92, 0.84, alpha)
		draw_line(local_trail[index], local_trail[index + 1], trail_color, width, true)
	# Two offset gold threads make sharp route changes readable without adding nodes.
	var side := direction.orthogonal()
	draw_line(-direction * 18.0 + side * 3.0, -direction * 34.0 + side, Color(1.0, 0.72, 0.28, 0.42), 1.8, true)
	draw_line(-direction * 18.0 - side * 3.0, -direction * 34.0 - side, Color(1.0, 0.72, 0.28, 0.28), 1.4, true)
