class_name FoldlightMirrorMothActor
extends FoldlightRogueBossActor
## A birth-time copy of the real player's build. Return volleys observe actual
## player release events; the mirror never intercepts friendly projectiles.
## All timers and queued returns use the boss combat clock.

signal mirror_action_requested(snapshot: Dictionary)

const HEALTH_PER_COPIED_HEART: float = 160.0
const RELEASE_WARNING: float = 0.8
const ACTIVE_WARNING: float = 0.65
const WEAPON_IDS: Array[StringName] = [&"crease_lantern", &"needle_orbit", &"returning_gull", &"tide_bell", &"prism_fan", &"sun_thread"]

var _mirror_build: Dictionary = {}
var _mirror_weapons: Array[Dictionary] = []
var _weapon_timers: Dictionary = {}
var _release_events: Array[Dictionary] = []
var _last_release_serial: int = 0
var _release_event_serial: int = 0
var _release_count: int = 0
var _release_remaining: float = 0.0
var _release_origin := Vector2.ZERO
var _release_target := Vector2.ZERO
var _return_queue: Array[Dictionary] = []
var _return_pulse_remaining: float = 0.0
var _return_request_serial: int = 0
var _return_pending_request: int = 0
var _return_pending_count: int = 0
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
	_release_events.clear()
	_last_release_serial = 0
	_release_event_serial = 0
	_release_count = 0
	_release_remaining = 0.0
	_return_queue.clear()
	_return_pulse_remaining = 0.0
	_return_pending_request = 0
	_return_pending_count = 0
	# Keep request serials unique across reuse of this actor. A delayed runtime
	# receipt from the prior run must never acknowledge a new run's volley.
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


func sync_mirror_input(_is_folding: bool) -> void:
	# Compatibility only: folding input no longer opens an enemy collector.
	pass


func can_capture_projectile(_snapshot: Dictionary) -> bool:
	return false


func capture_projectile(_snapshot: Dictionary) -> bool:
	return false


func get_mirror_capture_radius() -> float:
	return 0.0


func observe_player_release(count: int, event_serial: int) -> bool:
	# Count comes from the actual player's collector release, never from held
	# input or this birth snapshot's capacity. FIFO preserves rapid distinct events.
	if count < 1 or count > 96 or event_serial <= _last_release_serial or not _can_act():
		return false
	_last_release_serial = event_serial
	_release_events.append({"count": count, "serial": event_serial})
	if _release_event_serial == 0:
		_begin_next_release()
	RenderRedraw.request(self)
	return true


func acknowledge_mirror_return(request_id: int, spawned_count: int) -> bool:
	# Runtime acknowledges only the successfully spawned prefix. Pending shots
	# remain owned here while the shared projectile budget is full.
	if request_id <= 0 or request_id != _return_pending_request or spawned_count < 0 or spawned_count > _return_pending_count:
		return false
	_return_pending_request = 0
	_return_pending_count = 0
	for index in spawned_count:
		_return_queue.pop_front()
	if _return_queue.is_empty():
		_release_event_serial = 0
		_release_count = 0
	RenderRedraw.request(self)
	return true


func get_mirror_snapshot() -> Dictionary:
	return {"build": _mirror_build.duplicate(true), "weapons": _mirror_weapons.duplicate(true), "health_per_copied_heart": HEALTH_PER_COPIED_HEART,
		"folding": false, "captured": 0, "capacity": int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0)),
		"capture_radius": 0.0, "fold_cooldown": 0.0, "release_remaining": _release_remaining, "return_queue_count": _return_queue.size(),
		"release_count": _release_count, "release_event_serial": _release_event_serial, "last_release_serial": _last_release_serial,
		"pending_release_events": _release_events.duplicate(true), "return_pending_request": _return_pending_request, "return_pending_count": _return_pending_count,
		"active_remaining": _active_remaining, "active_warning_remaining": _active_warning_remaining,
		"shield_hits": _shield_hits, "shield_remaining": _shield_remaining, "overdrive_remaining": _overdrive_remaining,
		"invulnerability": _mirror_invulnerability, "dash_remaining": _mirror_dash_remaining, "dash_cooldown": _mirror_dash_cooldown,
		"dash_charges": _mirror_dash_charges, "dash_maximum": _mirror_dash_maximum,
		"weapon_timers": _weapon_timers.duplicate(true), "action_serial": _action_serial}


func get_combat_snapshot() -> Dictionary:
	var result := super.get_combat_snapshot()
	# HUD, population and support queries only need live state. The complete
	# immutable loadout is available through the explicit inspection API.
	result["mirror"] = {"folding": false, "captured": 0,
		"capacity": int(_number(_mirror_build, "capture_capacity", 8.0, 1.0, 96.0)),
		"release_remaining": _release_remaining, "release_count": _release_count, "return_queue_count": _return_queue.size(),
		"pending_release_event_count": _release_events.size(), "shield_hits": _shield_hits}
	return result


func advance_simulation(delta: float, player_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if not _simulation_active or health <= 0.0 or _mirror_build.is_empty() or not is_finite(delta) or delta <= 0.0 or is_queued_for_deletion():
		return
	var step := minf(delta, 0.1) * clampf(hostile_time_scale, 0.1, 2.0)
	_target_position = player_position
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
	if _mirror_dash_remaining > 0.0:
		_mirror_dash_path.append(global_position)
		_mirror_dash_remaining = maxf(0.0, _mirror_dash_remaining - step)
		if _mirror_dash_remaining <= 0.0:
			_dash_active = false
			_emit_dash_blast()
			phase_controller.finish_active_pattern()
	if _release_event_serial == 0 and not _release_events.is_empty():
		# Starting a queued warning consumes none of its duration this step.
		_begin_next_release()
	elif _release_remaining > 0.0:
		_release_remaining = maxf(0.0, _release_remaining - step)
		if _release_remaining <= 0.0: _prepare_return_shots()
	if not _return_queue.is_empty() and _return_pending_request == 0:
		_return_pulse_remaining = maxf(0.0, _return_pulse_remaining - step)
		if _return_pulse_remaining <= 0.0: _emit_return_pulse()
	# Runtime listeners can synchronously pause combat or defeat/stagger this
	# source. Never continue into a skill or weapon cast after that interruption.
	if not _can_act(): return
	_active_remaining = maxf(0.0, _active_remaining - step)
	if _active_warning_remaining > 0.0:
		_active_warning_remaining = maxf(0.0, _active_warning_remaining - step)
		if _active_warning_remaining <= 0.0: _resolve_active()
	elif _active_remaining <= 0.0 and _release_remaining <= 0.0:
		_begin_active()
	for shot: Dictionary in _mirror_weapons:
		if not _can_act(): break
		var key := StringName(shot.weapon_id)
		var cadence := 2.25 if _overdrive_remaining > 0.0 else 1.0
		_weapon_timers[key] = maxf(0.0, float(_weapon_timers[key]) - step * cadence)
		if float(_weapon_timers[key]) <= 0.0 and _release_remaining <= 0.0 and phase_controller.state == FoldlightBossPhaseController.State.ATTACK:
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


func _begin_next_release() -> void:
	if not _can_act() or _release_events.is_empty() or _release_event_serial != 0: return
	var event: Dictionary = _release_events.pop_front()
	_release_event_serial = int(event.serial)
	_release_count = int(event.count)
	_release_remaining = RELEASE_WARNING
	_release_origin = global_position
	_release_target = _target_position
	_mirror_dash_remaining = 0.0
	_dash_active = false
	telegraph_requested.emit({"pattern_id": &"mirror_return", "duration": RELEASE_WARNING, "origin": _release_origin, "target_position": _release_target,
		"projectile_count": _release_count, "mirror_release_serial": _release_event_serial,
		"accent": Color("d6a397"), "attack_lanes": [{"origin": _release_origin, "end": _release_target, "width": 40.0, "reflectable": true}]})


func _prepare_return_shots() -> void:
	if not _can_act() or _release_count <= 0: return
	var direction := _release_origin.direction_to(_release_target)
	if direction.is_zero_approx(): direction = Vector2.DOWN
	for index in _release_count:
		var angle := (float(index % 9) - float(mini(9, _release_count) - 1) * 0.5) * 0.055
		_return_queue.append({"direction": direction.rotated(angle), "speed": 440.0 + float(index % 3) * 22.0,
			"style": &"return_light", "damage": 1.0, "reflectable": true, "radius": 7.0, "lifetime": 3.8,
			"homing_duration": 1.4, "homing_turn_speed": 1.5, "echo_chance": 0.0, "is_echo": false,
			"mirror_release_serial": _release_event_serial, "mirror_release_index": index})
	_return_pulse_remaining = 0.0


func _emit_return_pulse() -> void:
	if not _can_act() or _return_pending_request != 0 or _return_queue.is_empty(): return
	var shots: Array[Dictionary] = []
	for index in mini(18, _return_queue.size()): shots.append(_return_queue[index].duplicate())
	_return_request_serial += 1
	_return_pending_request = _return_request_serial
	_return_pending_count = shots.size()
	_return_pulse_remaining = 0.09
	volley_requested.emit({"origin": _release_origin, "direction": _release_origin.direction_to(_release_target), "projectiles": shots, "projectile_count": shots.size(),
		"hostile": true, "reflectable": true, "mirror": true, "style": &"return_light", "telegraph": RELEASE_WARNING,
		"mirror_return_request_id": _return_pending_request, "mirror_release_serial": _release_event_serial})


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
	if not _can_act(): return
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
	if pattern_id == &"mirror_dash" and _mirror_dash_charges > 0:
		var distance := _number(_mirror_build, "dash_speed", 1050.0, 300.0, 2400.0) * _number(_mirror_build, "dash_duration", 0.18, 0.05, 0.5)
		var stats: Dictionary = _mirror_build.get("build_stats", {})
		var blast_level := clampi(int(stats.get("dash_blast_level", 0)), 0, 6)
		var lane_width := maxf(get_contact_radius() * 2.0 + 16.0, 2.0 * (110.0 + 10.0 * (blast_level - 1))) if blast_level > 0 else get_contact_radius() * 2.0 + 16.0
		warning["attack_lanes"] = [{"origin": global_position, "end": global_position + _visual_direction * distance, "width": lane_width, "reflectable": false, "dash": true}]
		warning["hold_seconds"] = _number(_mirror_build, "dash_duration", 0.18, 0.05, 0.5)
	telegraph_requested.emit(warning)


func _on_attack_ready(pattern_id: StringName, _telegraph_duration: float) -> void:
	_recoil_remaining = RECOIL_SECONDS
	if pattern_id == &"mirror_dash" and _mirror_dash_charges > 0 and _release_remaining <= 0.0:
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
	var speed := _number(_mirror_build, "move_speed", 430.0, 80.0, 1500.0)
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
	_release_events.clear()
	_release_event_serial = 0
	_release_count = 0
	_return_queue.clear()
	_return_pulse_remaining = 0.0
	_return_pending_request = 0
	_return_pending_count = 0
	_mirror_dash_path.clear()
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
	pose["mirror_folding"] = false
	pose["mirror_release"] = _release_remaining > 0.0
	pose["mirror_shield"] = _shield_hits > 0
	return pose


func _draw() -> void:
	super._draw()
	if definition == null or health <= 0.0: return
	var copper := Color("d6a397")
	if _release_remaining > 0.0:
		var progress := 1.0 - _release_remaining / RELEASE_WARNING
		draw_arc(Vector2.ZERO, 76.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, Color(copper, 0.80), 3.0, true)
		draw_string(FoldlightTheme.body_font(), Vector2(-180, 128), "延迟返光 · %d 发 · 横向躲避" % _release_count, HORIZONTAL_ALIGNMENT_CENTER, 360, 20, copper)
	elif not _return_queue.is_empty():
		draw_string(FoldlightTheme.body_font(), Vector2(-150, 128), "复影返光 · 待发 %d" % _return_queue.size(), HORIZONTAL_ALIGNMENT_CENTER, 300, 20, copper)
	elif _shield_hits > 0:
		draw_arc(Vector2.ZERO, 94.0, 0.0, TAU, 32, Color("d2b27c"), 3.0, true)


static func _number(source: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = source.get(key, fallback)
	return clampf(float(value), minimum, maximum) if (value is float or value is int) and is_finite(float(value)) else fallback
