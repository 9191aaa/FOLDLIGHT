class_name FoldlightMirrorMothActor
extends FoldlightRogueBossActor
## A birth-time copy of the real player's build. No profile reads, free captured
## ammunition, or shared Resource mutations. All timers use the boss combat clock.

signal mirror_action_requested(snapshot: Dictionary)

const HEALTH_PER_COPIED_HEART: float = 160.0
const RELEASE_WARNING: float = 0.65
const ACTIVE_WARNING: float = 0.65
const WEAPON_IDS: Array[StringName] = [&"crease_lantern", &"needle_orbit", &"returning_gull", &"tide_bell", &"prism_fan", &"sun_thread"]

var _mirror_build: Dictionary = {}
var _mirror_weapons: Array[Dictionary] = []
var _weapon_timers: Dictionary = {}
var _captured_shots: Array[Dictionary] = []
var _captured_ids: Dictionary = {}
var _mirror_folding: bool = false
var _fold_input: bool = false
var _fold_clock: float = 0.0
var _fold_cooldown: float = 0.0
var _release_remaining: float = 0.0
var _release_origin := Vector2.ZERO
var _release_target := Vector2.ZERO
var _return_queue: Array[Dictionary] = []
var _return_pulse_remaining: float = 0.0
var _health_scale: float = 1.0
var _active_remaining: float = 0.0
var _active_warning_remaining: float = 0.0
var _active_pending: Dictionary = {}
var _action_serial: int = 0
var _overdrive_remaining: float = 0.0
var _shield_remaining: float = 0.0
var _shield_hits: int = 0
var _mirror_invulnerability: float = 0.0
var _mirror_dash_remaining: float = 0.0
var _mirror_dash_cooldown: float = 0.0
var _mirror_dash_charges: int = 1
var _mirror_dash_maximum: int = 1
var _mirror_dash_direction := Vector2.DOWN
var _mirror_dash_path := PackedVector2Array()


func configure(new_definition: FoldlightRogueBossDefinition, bounds: Rect2, seed: int = 330031, options: Dictionary = {}) -> void:
	_mirror_build.clear()
	_mirror_weapons.clear()
	_weapon_timers.clear()
	_captured_shots.clear()
	_captured_ids.clear()
	_mirror_folding = false
	_fold_input = false
	_fold_clock = 0.0
	_fold_cooldown = 0.0
	_release_remaining = 0.0
	_return_queue.clear()
	_return_pulse_remaining = 0.0
	_active_remaining = 0.0
	_active_warning_remaining = 0.0
	_active_pending.clear()
	_action_serial = 0
	_overdrive_remaining = 0.0
	_shield_remaining = 0.0
	_shield_hits = 0
	_mirror_invulnerability = 0.0
	_mirror_dash_remaining = 0.0
	_mirror_dash_cooldown = 0.0
	_health_scale = clampf(float(options.get("health_scale", 1.0)), 0.05, 20.0)
	super.configure(new_definition, bounds, seed, options)


func configure_mirror_build(snapshot: Dictionary) -> void:
	# Reconfiguration cannot refill a wounded mirror or rewrite its identity.
	if not _mirror_build.is_empty():
		return
	_mirror_build = snapshot.duplicate(true)
	# Runtime exports resolved component values; accept their explicit names.
	for aliases: Array in [["fold_speed", "fold_move_speed"], ["capture_radius", "capture_radius_max"], ["full_charge_time", "capture_charge_time"]]:
		if not _mirror_build.has(aliases[0]) and _mirror_build.has(aliases[1]):
			_mirror_build[aliases[0]] = _mirror_build[aliases[1]]
	_mirror_weapons.clear()
	_weapon_timers.clear()
	for raw: Variant in snapshot.get("weapons", []):
		if not raw is Dictionary or not WEAPON_IDS.has(StringName(raw.get("weapon_id", &""))):
			continue
		var shot: Dictionary = raw.duplicate(true)
		var key := StringName(shot.weapon_id)
		if _weapon_timers.has(key):
			continue
		shot["weapon_level"] = clampi(int(shot.get("weapon_level", 1)), 1, 5)
		shot["fire_interval"] = _number(shot, "fire_interval", 0.55, 0.16, 10.0)
		_mirror_weapons.append(shot)
		_weapon_timers[key] = float(shot.fire_interval)
	maximum_health = _number(snapshot, "max_health", 4.0, 1.0, 40.0) * HEALTH_PER_COPIED_HEART * _health_scale
	health = maximum_health
	_active_remaining = _number(snapshot, "active_cooldown_remaining", 3.0, 0.0, 120.0)
	_mirror_dash_cooldown = _number(snapshot, "dash_cooldown_remaining", 0.0, 0.0, 20.0)
	_mirror_dash_maximum = int(_number(snapshot, "dash_charges", 1.0, 1.0, 8.0))
	_mirror_dash_charges = int(_number(snapshot, "dash_charges_remaining", _mirror_dash_maximum, 0.0, _mirror_dash_maximum))
	var shape := ($CollisionShape2D as CollisionShape2D).shape.duplicate() as CircleShape2D
	shape.radius = get_contact_radius()
	($CollisionShape2D as CollisionShape2D).shape = shape
	RenderRedraw.request(self)


func sync_mirror_input(is_folding: bool) -> void:
	# Synchronize only while combat is live. Pausing must preserve the last pose,
	# pending release and cooldown instead of manufacturing a release edge.
	if not _simulation_active or health <= 0.0 or is_queued_for_deletion():
		return
	_fold_input = is_folding
	if is_folding and not _mirror_folding and _can_act() and _fold_cooldown <= 0.0 and _release_remaining <= 0.0 and _return_queue.is_empty():
		_mirror_folding = true
		_fold_clock = 0.0
		_mirror_dash_remaining = 0.0
		_dash_active = false
	elif not is_folding and _mirror_folding:
		_end_fold()
	RenderRedraw.request(self)


func can_capture_projectile(snapshot: Dictionary) -> bool:
	if not _can_act() or not _mirror_folding or _mirror_invulnerability > 0.0 or bool(snapshot.get("hostile", false)) or bool(snapshot.get("queued_for_deletion", false)):
		return false
	if _captured_shots.size() >= int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0)):
		return false
	var capture_id := int(snapshot.get("capture_id", 0))
	if capture_id != 0 and _captured_ids.has(capture_id):
		return false
	var point: Vector2 = snapshot.get("position", snapshot.get("origin", global_position))
	return point.distance_squared_to(global_position) <= pow(get_mirror_capture_radius() + maxf(0.0, float(snapshot.get("radius", 0.0))), 2.0)


func capture_projectile(snapshot: Dictionary) -> bool:
	if not can_capture_projectile(snapshot):
		return false
	_captured_shots.append(snapshot.duplicate(true))
	var capture_id := int(snapshot.get("capture_id", 0))
	if capture_id != 0:
		_captured_ids[capture_id] = true
	RenderRedraw.request(self)
	return true


func get_mirror_capture_radius() -> float:
	var maximum := _number(_mirror_build, "capture_radius", 315.0, 40.0, 900.0)
	var minimum := _number(_mirror_build, "capture_radius_min", minf(112.0, maximum), 20.0, maximum)
	return lerpf(minimum, maximum, ease(clampf(_fold_clock / _number(_mirror_build, "full_charge_time", 1.55, 0.1, 10.0), 0.0, 1.0), 0.55))


func get_mirror_snapshot() -> Dictionary:
	return {"build": _mirror_build.duplicate(true), "weapons": _mirror_weapons.duplicate(true), "health_per_copied_heart": HEALTH_PER_COPIED_HEART,
		"folding": _mirror_folding, "captured": _captured_shots.size(), "capacity": int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0)),
		"capture_radius": get_mirror_capture_radius(), "fold_cooldown": _fold_cooldown, "release_remaining": _release_remaining, "return_queue_count": _return_queue.size(),
		"active_remaining": _active_remaining, "active_warning_remaining": _active_warning_remaining,
		"shield_hits": _shield_hits, "shield_remaining": _shield_remaining, "overdrive_remaining": _overdrive_remaining,
		"invulnerability": _mirror_invulnerability, "dash_remaining": _mirror_dash_remaining, "dash_cooldown": _mirror_dash_cooldown,
		"dash_charges": _mirror_dash_charges, "dash_maximum": _mirror_dash_maximum,
		"weapon_timers": _weapon_timers.duplicate(true), "action_serial": _action_serial}


func get_combat_snapshot() -> Dictionary:
	var result := super.get_combat_snapshot()
	# HUD, population and support queries only need live state. The complete
	# immutable loadout is available through the explicit inspection API.
	result["mirror"] = {"folding": _mirror_folding, "captured": _captured_shots.size(),
		"capacity": int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0)),
		"release_remaining": _release_remaining, "shield_hits": _shield_hits}
	return result


func advance_simulation(delta: float, player_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if not _simulation_active or health <= 0.0 or _mirror_build.is_empty() or not is_finite(delta) or delta <= 0.0 or is_queued_for_deletion():
		return
	var step := minf(delta, 0.1) * clampf(hostile_time_scale, 0.1, 2.0)
	_target_position = player_position
	_fold_cooldown = maxf(0.0, _fold_cooldown - step)
	_mirror_dash_cooldown = maxf(0.0, _mirror_dash_cooldown - step)
	if _mirror_dash_charges < _mirror_dash_maximum and _mirror_dash_cooldown <= 0.0:
		_mirror_dash_charges += 1
		if _mirror_dash_charges < _mirror_dash_maximum: _mirror_dash_cooldown = _number(_mirror_build, "dash_cooldown", 2.0, 0.2, 10.0)
	_mirror_invulnerability = maxf(0.0, _mirror_invulnerability - step)
	_shield_remaining = maxf(0.0, _shield_remaining - step)
	_overdrive_remaining = maxf(0.0, _overdrive_remaining - step)
	if _shield_remaining <= 0.0: _shield_hits = 0
	# Base advances phase transitions first, so a stagger/phase change cancels
	# a pending skill before this frame can resolve it.
	super.advance_simulation(step, player_position, 1.0)
	if not _can_act():
		return
	if _fold_input and not _mirror_folding:
		sync_mirror_input(true)
	if _mirror_folding:
		_fold_clock += step
	if _mirror_dash_remaining > 0.0:
		_mirror_dash_path.append(global_position)
		_mirror_dash_remaining = maxf(0.0, _mirror_dash_remaining - step)
		if _mirror_dash_remaining <= 0.0:
			_dash_active = false
			_emit_dash_blast()
			phase_controller.finish_active_pattern()
	if _release_remaining > 0.0:
		_release_remaining = maxf(0.0, _release_remaining - step)
		if _release_remaining <= 0.0: _release_captured_shots()
	if not _return_queue.is_empty():
		_return_pulse_remaining = maxf(0.0, _return_pulse_remaining - step)
		if _return_pulse_remaining <= 0.0: _emit_return_pulse()
	_active_remaining = maxf(0.0, _active_remaining - step)
	if _active_warning_remaining > 0.0:
		_active_warning_remaining = maxf(0.0, _active_warning_remaining - step)
		if _active_warning_remaining <= 0.0: _resolve_active()
	elif _active_remaining <= 0.0 and not _mirror_folding and _release_remaining <= 0.0:
		_begin_active()
	for shot: Dictionary in _mirror_weapons:
		var key := StringName(shot.weapon_id)
		var cadence := 2.25 if _overdrive_remaining > 0.0 else 1.0
		_weapon_timers[key] = maxf(0.0, float(_weapon_timers[key]) - step * cadence)
		if float(_weapon_timers[key]) <= 0.0 and not _mirror_folding and _release_remaining <= 0.0 and phase_controller.state == FoldlightBossPhaseController.State.ATTACK:
			# Range is copied too. The mirror must approach before a short-range
			# arsenal can fire; no off-screen prism or orbit sniping.
			if global_position.distance_to(player_position) <= _number(shot, "targeting_range", 900.0, 100.0, 5000.0):
				_emit_mirror_weapon(shot)
				_weapon_timers[key] = float(shot.fire_interval)
	RenderRedraw.request(self)


func take_damage(amount: float, source: StringName = &"weapon", incoming_velocity: Vector2 = Vector2.ZERO) -> bool:
	if _mirror_invulnerability > 0.0 or phase_controller.state == FoldlightBossPhaseController.State.INTRO:
		return false
	if _shield_hits > 0 and _shield_remaining > 0.0 and amount > 0.0:
		_shield_hits -= 1
		RenderRedraw.request(self)
		return false
	return super.take_damage(amount, source, incoming_velocity)


func _can_act() -> bool:
	return not _mirror_build.is_empty() and _simulation_active and health > 0.0 and not is_queued_for_deletion() and phase_controller.state not in [FoldlightBossPhaseController.State.INTRO, FoldlightBossPhaseController.State.STAGGERED, FoldlightBossPhaseController.State.DEFEATED] and phase_controller._transition_remaining <= 0.0


func _end_fold() -> void:
	_mirror_folding = false
	_fold_cooldown = _number(_mirror_build, "capture_cooldown", 1.5, 0.0, 10.0)
	if _captured_shots.is_empty() or not _can_act():
		return
	_release_remaining = RELEASE_WARNING
	_release_origin = global_position
	_release_target = _target_position
	telegraph_requested.emit({"pattern_id": &"mirror_return", "duration": RELEASE_WARNING, "origin": _release_origin, "target_position": _release_target,
		"accent": Color("d6a397"), "attack_lanes": [{"origin": _release_origin, "end": _release_target, "width": 40.0, "reflectable": true}]})


func _release_captured_shots() -> void:
	if not _can_act() or _captured_shots.is_empty(): return
	var shots: Array[Dictionary] = []
	var direction := _release_origin.direction_to(_release_target)
	if direction.is_zero_approx(): direction = Vector2.DOWN
	for index in _captured_shots.size():
		var angle := (float(index % 9) - float(mini(9, _captured_shots.size()) - 1) * 0.5) * 0.055
		shots.append({"direction": direction.rotated(angle), "speed": 440.0 + float(index % 3) * 22.0,
			"style": &"return_light", "damage": 1.0, "reflectable": true, "radius": 7.0, "lifetime": 3.8,
			"homing_duration": 1.4, "homing_turn_speed": 1.5, "copied_damage": float(_captured_shots[index].get("damage", 1.0))})
	# Consume before signaling. Re-entrant death/stagger cannot release twice.
	_captured_shots.clear()
	_captured_ids.clear()
	_return_queue.assign(shots)
	_return_pulse_remaining = 0.0


func _emit_return_pulse() -> void:
	var shots: Array[Dictionary] = []
	for index in mini(18, _return_queue.size()): shots.append(_return_queue.pop_front())
	_return_pulse_remaining = 0.09
	volley_requested.emit({"origin": _release_origin, "direction": _release_origin.direction_to(_release_target), "projectiles": shots, "projectile_count": shots.size(),
		"hostile": true, "reflectable": true, "mirror": true, "style": &"return_light", "telegraph": RELEASE_WARNING})


func _emit_mirror_weapon(weapon: Dictionary) -> void:
	var weapon_id := StringName(weapon.weapon_id)
	var direction := global_position.direction_to(_target_position)
	if direction.is_zero_approx(): direction = Vector2.DOWN
	if weapon_id == &"returning_gull" and not velocity.is_zero_approx(): direction = velocity.normalized()
	var count := clampi(int(weapon.get("volley_count", 1)), 1, 8)
	var shots: Array[Dictionary] = []
	var speed := _number(weapon, "projectile_speed", 800.0, 100.0, 2400.0)
	for index in count:
		var spread := 0.0
		if index > 0:
			spread = (0.30 if weapon_id == &"prism_fan" else 0.14) * float(ceili(float(index) * 0.5)) / float(ceili(float(count - 1) * 0.5)) * (1.0 if index % 2 == 1 else -1.0)
		var critical := _rng.randf() <= _number(weapon, "critical_chance", 0.0, 0.0, 0.75)
		var shot := {"direction": direction.rotated(spread), "speed": speed, "damage": 1.0,
			"copied_damage": float(weapon.get("damage", 1.0)) * (2.0 if critical else 1.0), "copied_critical": critical, "weapon_level": int(weapon.weapon_level),
			"reflectable": true, "radius": 7.0 * _number(weapon, "projectile_size_multiplier", 1.0, 0.5, 3.0),
			"pierce": clampi(int(weapon.get("pierce", 0)), 0, 12), "style": StringName(weapon.get("projectile_style", &"crease_petal")),
			"automatic_weapon_id": weapon_id, "target_position": _target_position, "lifetime": 3.0,
			"echo_chance": _number(weapon, "projectile_echo_chance", 0.0, 0.0, 0.75), "is_echo": false, "execute_damage_multiplier": _number(weapon, "execute_damage_multiplier", 1.0, 1.0, 10.0),
			"homing_duration": 0.0, "homing_turn_speed": 0.0}
		match weapon_id:
			&"crease_lantern":
				if index == 0: shot.merge({"homing_duration": 1.15, "homing_turn_speed": 1.35}, true)
			&"needle_orbit":
				shot.merge({"launch_delay": 0.65, "orbit_anchor": self, "orbit_radius": 69.0 + float(index % 2) * 12.0,
					"orbit_angle": direction.angle() + float(index) * TAU / float(count), "orbit_speed": 7.8, "lifetime": 2.3,
					"homing_duration": 0.9, "homing_turn_speed": 1.6}, true)
			&"returning_gull":
				var return_after := (_number(weapon, "targeting_range", 440.0, 100.0, 5000.0) + 32.0) / speed + 1.0 / 60.0
				shot.merge({"return_anchor": self, "return_after": return_after, "return_damage_multiplier": float(weapon.get("return_damage_multiplier", 1.0)), "lifetime": maxf(1.9, return_after * 2.0 + 0.30)}, true)
			&"tide_bell":
				shot["echo_chance"] = 0.0
				shot["area_radius"] = 125.0 * float(weapon.get("area_radius_multiplier", 1.0))
				shot["target_position"] = _target_position + direction.orthogonal() * spread * 220.0
				shot["direction"] = global_position.direction_to(shot.target_position)
			&"prism_fan": shot["lifetime"] = 0.64
			&"sun_thread": shot["execute_damage_multiplier"] = float(weapon.get("execute_damage_multiplier", 1.0))
		shots.append(shot)
	volley_requested.emit({"origin": global_position, "direction": direction, "projectiles": shots, "projectile_count": shots.size(),
		"hostile": true, "mirror": true, "reflectable": true, "weapon_id": weapon_id, "weapon_level": int(weapon.weapon_level), "telegraph": 0.70})


func _begin_active() -> void:
	var skill_id := StringName(_mirror_build.get("active_item_id", &""))
	var skill := FoldlightRogueContentCatalog.active_item_by_id(skill_id)
	if skill == null:
		_active_remaining = 2.0
		return
	_action_serial += 1
	_active_remaining = _number(_mirror_build, "active_cooldown", skill.cooldown, 0.5, 120.0)
	_active_warning_remaining = ACTIVE_WARNING
	_active_pending = {"stage": &"warning", "action": skill.effect_id, "skill_id": skill_id, "power": skill.power, "duration": skill.duration,
		"origin": global_position, "target_position": _target_position, "source_id": actor_id, "serial": _action_serial, "warning_seconds": ACTIVE_WARNING}
	telegraph_requested.emit({"pattern_id": &"mirror_active", "duration": ACTIVE_WARNING, "origin": global_position,
		"target_position": _target_position if skill.effect_id == &"hostile_slow" else global_position, "accent": Color("d2b27c"),
		"zone_radius": 260.0 if skill.effect_id == &"hostile_slow" else 330.0 if skill.effect_id == &"radial_push" else 140.0})
	mirror_action_requested.emit(_active_pending.duplicate(true))


func _resolve_active() -> void:
	if _active_pending.is_empty() or not _can_act(): return
	var event := _active_pending.duplicate(true)
	_active_pending.clear()
	event["stage"] = &"resolve"
	match StringName(event.action):
		&"cleanse_heal":
			health = minf(maximum_health, health + float(event.power) * HEALTH_PER_COPIED_HEART * _health_scale)
			_fold_cooldown = 0.0
		&"anchor_shield":
			_shield_hits = int(event.power)
			_shield_remaining = float(event.duration)
		&"weapon_overdrive": _overdrive_remaining = float(event.duration)
		&"dash_decoy":
			_mirror_invulnerability = 1.0
			_mirror_dash_cooldown = 0.0
			_mirror_dash_charges = _mirror_dash_maximum
	mirror_action_requested.emit(event)


func _on_telegraph_started(pattern_id: StringName, duration: float) -> void:
	_locked_attack_origin = global_position
	_locked_attack_target = _target_position
	_visual_direction = global_position.direction_to(_target_position)
	var warning := {"pattern_id": pattern_id, "duration": duration, "origin": global_position, "target_position": _target_position, "accent": Color("d6a397")}
	if pattern_id == &"mirror_dash" and _mirror_dash_charges > 0 and not _mirror_folding:
		var distance := _number(_mirror_build, "dash_speed", 1050.0, 300.0, 2400.0) * _number(_mirror_build, "dash_duration", 0.18, 0.05, 0.5)
		var stats: Dictionary = _mirror_build.get("build_stats", {})
		var blast_level := clampi(int(stats.get("dash_blast_level", 0)), 0, 6)
		var lane_width := maxf(get_contact_radius() * 2.0 + 16.0, 2.0 * (110.0 + 10.0 * (blast_level - 1))) if blast_level > 0 else get_contact_radius() * 2.0 + 16.0
		warning["attack_lanes"] = [{"origin": global_position, "end": global_position + _visual_direction * distance, "width": lane_width, "reflectable": false, "dash": true}]
		warning["hold_seconds"] = _number(_mirror_build, "dash_duration", 0.18, 0.05, 0.5)
	telegraph_requested.emit(warning)


func _on_attack_ready(pattern_id: StringName, _telegraph_duration: float) -> void:
	_recoil_remaining = RECOIL_SECONDS
	if pattern_id == &"mirror_dash" and _mirror_dash_charges > 0 and not _mirror_folding and _release_remaining <= 0.0:
		_mirror_dash_direction = _locked_attack_origin.direction_to(_locked_attack_target)
		if _mirror_dash_direction.is_zero_approx(): _mirror_dash_direction = Vector2.DOWN
		_mirror_dash_remaining = _number(_mirror_build, "dash_duration", 0.18, 0.05, 0.5)
		_mirror_invulnerability = maxf(_mirror_invulnerability, _number(_mirror_build, "dash_invulnerability", 0.16, 0.0, 0.6))
		_mirror_dash_path = PackedVector2Array([global_position])
		_mirror_dash_charges -= 1
		if _mirror_dash_cooldown <= 0.0: _mirror_dash_cooldown = _number(_mirror_build, "dash_cooldown", 2.0, 0.2, 10.0)
		_dash_active = true
		mirror_action_requested.emit({"stage": &"resolve", "action": &"mirror_dash", "origin": global_position, "direction": _mirror_dash_direction, "duration": _mirror_dash_remaining, "source_id": actor_id})


func _emit_dash_blast() -> void:
	var stats: Dictionary = _mirror_build.get("build_stats", {})
	var level := clampi(int(stats.get("dash_blast_level", 0)), 0, 6)
	if level <= 0 or _mirror_dash_path.size() < 2: return
	_action_serial += 1
	mirror_action_requested.emit({"stage": &"resolve", "action": &"dash_blast", "origin": global_position, "path": _mirror_dash_path,
		"radius": 110.0 + 10.0 * (level - 1), "damage": 1.0, "level": level, "source_id": actor_id, "serial": _action_serial})


func _update_movement(delta: float) -> void:
	if not _can_act():
		velocity = Vector2.ZERO
		return
	if _mirror_dash_remaining > 0.0 and _dash_active:
		velocity = _mirror_dash_direction * _number(_mirror_build, "dash_speed", 1050.0, 300.0, 2400.0)
		return
	if phase_controller.state == FoldlightBossPhaseController.State.TELEGRAPH or _release_remaining > 0.0 or _active_warning_remaining > 0.0:
		velocity = Vector2.ZERO
		return
	var offset := _target_position - global_position
	var speed := _number(_mirror_build, "fold_speed" if _mirror_folding else "move_speed", 235.0 if _mirror_folding else 430.0, 80.0, 1500.0)
	var pursuit := global_position.direction_to(_navigation_target) if _has_navigation_target and offset.length() > 360.0 else offset.normalized()
	# A close-range copied build actually closes in; longer-range builds orbit.
	var preferred := 360.0
	for weapon: Dictionary in _mirror_weapons:
		preferred = minf(preferred, float(weapon.get("targeting_range", 900.0)) * 0.65)
	var desired := pursuit * speed if offset.length() > preferred else offset.normalized().orthogonal() * speed * 0.6
	if offset.length() < 180.0: desired -= offset.normalized() * speed * 0.45
	velocity = velocity.move_toward(desired, 2100.0 * delta)


func _cancel_attack_plan() -> void:
	super._cancel_attack_plan()
	_mirror_dash_remaining = 0.0
	_release_remaining = 0.0
	_return_queue.clear()
	_return_pulse_remaining = 0.0
	_mirror_dash_path.clear()
	_mirror_folding = false
	_captured_shots.clear()
	_captured_ids.clear()
	if not _active_pending.is_empty():
		var event := _active_pending.duplicate(true)
		event["stage"] = &"cancel"
		_active_pending.clear()
		mirror_action_requested.emit(event)
	_active_warning_remaining = 0.0


func get_contact_radius() -> float:
	return 34.0 * _number(_mirror_build, "body_size_multiplier", 1.0, 0.5, 2.0)


func get_contact_sweep() -> Dictionary:
	var sweep := super.get_contact_sweep()
	if not sweep.is_empty(): sweep["radius"] = get_contact_radius()
	return sweep


func get_visual_pose() -> Dictionary:
	var pose := super.get_visual_pose()
	pose["mirror_folding"] = _mirror_folding
	pose["mirror_release"] = _release_remaining > 0.0
	pose["mirror_shield"] = _shield_hits > 0
	return pose


func _draw() -> void:
	super._draw()
	if definition == null or health <= 0.0: return
	var copper := Color("d6a397")
	if _mirror_folding:
		var radius := get_mirror_capture_radius()
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(copper, 0.60), 2.0, true)
		for index in 6:
			var point := Vector2.from_angle(float(index) * TAU / 6.0) * radius
			draw_line(point, point * 0.90, Color(copper, 0.80), 3.0, true)
		draw_string(FoldlightTheme.body_font(), Vector2(-150, 128), "镜像收纳 · %d / %d" % [_captured_shots.size(), int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0))], HORIZONTAL_ALIGNMENT_CENTER, 300, 20, copper)
	elif _release_remaining > 0.0:
		draw_string(FoldlightTheme.body_font(), Vector2(-150, 128), "复影返光 · 横向躲避", HORIZONTAL_ALIGNMENT_CENTER, 300, 20, copper)
	elif _shield_hits > 0:
		draw_arc(Vector2.ZERO, 94.0, 0.0, TAU, 32, Color("d2b27c"), 3.0, true)


static func _number(source: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = source.get(key, fallback)
	return clampf(float(value), minimum, maximum) if (value is float or value is int) and is_finite(float(value)) else fallback
