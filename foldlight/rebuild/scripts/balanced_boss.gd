class_name FoldlightBalancedBoss
extends FoldlightRogueBossActor

signal clear_hostiles_requested
signal pattern_announced(pattern_id: StringName, phase: int)

enum Rhythm { INTRO, WARNING, BURST, RECOVERY, BREAK, TRANSITION, DEFEATED }
var rhythm: Rhythm = Rhythm.INTRO
var settings: Dictionary = {}
var phase: int = 0
var remaining: float = 1.5
var pattern: StringName = &""
var pattern_cursor: int = 0
var burst_cursor: int = 0
var locked_angle: float = PI * 0.5
var gap_angle: float = PI * 0.5
var total_damage: float = 0.0
var return_damage: float = 0.0
var weapon_damage: float = 0.0
var breaks_opened: int = 0
var _warning_total: float = 1.0

func configure_lab(profile: Dictionary, bounds: Rect2, seed: int = 20260917) -> void:
	settings = profile.duplicate(true)
	var source := FoldlightRogueContentCatalog.boss_by_id(&"reef_crown_battery")
	var lab_definition := source.duplicate(true) as FoldlightRogueBossDefinition
	lab_definition.base_health = float(settings["boss_health"])
	lab_definition.phase_thresholds = PackedFloat32Array([float(settings["phase_threshold"])])
	lab_definition.return_damage_outside_stagger = 1.0
	lab_definition.return_window_fraction = 1.0
	lab_definition.return_window_seconds = float(settings["stagger_seconds"])
	super.configure(lab_definition, bounds, seed)
	collision_layer = 0
	collision_mask = 0
	arena_controller.visible = false
	phase = 0
	rhythm = Rhythm.INTRO
	remaining = float(settings["intro_seconds"])
	pattern_cursor = 0
	burst_cursor = 0
	return_meter = 0.0
	total_damage = 0.0
	return_damage = 0.0
	weapon_damage = 0.0
	breaks_opened = 0
	_sync_visual_state()

func advance_simulation(delta: float, player_position: Vector2, hostile_time_scale: float = 1.0) -> void:
	if settings.is_empty() or rhythm == Rhythm.DEFEATED:
		return
	var step := maxf(0.0, delta) * clampf(hostile_time_scale, 0.1, 2.0)
	_target_position = player_position
	_visual_time += step
	_hit_flash = maxf(0.0, _hit_flash - step * 5.0)
	_hit_punch = maxf(0.0, _hit_punch - step * 8.0)
	_hit_ring = maxf(0.0, _hit_ring - step * 5.2)
	velocity = Vector2.ZERO
	remaining -= step
	var transitions := 0
	while remaining <= 0.0 and transitions < 32 and rhythm != Rhythm.DEFEATED:
		var overshoot := -remaining
		_advance_rhythm()
		remaining -= overshoot
		transitions += 1
	_sync_visual_state()
	queue_redraw()

func _advance_rhythm() -> void:
	match rhythm:
		Rhythm.INTRO, Rhythm.RECOVERY, Rhythm.BREAK, Rhythm.TRANSITION:
			_begin_warning()
		Rhythm.WARNING:
			rhythm = Rhythm.BURST
			burst_cursor = 0
			_emit_burst()
			burst_cursor += 1
			remaining = float(settings["burst_interval"])
		Rhythm.BURST:
			if burst_cursor < _burst_count():
				_emit_burst()
				burst_cursor += 1
				remaining = float(settings["burst_interval"])
			else:
				rhythm = Rhythm.RECOVERY
				remaining = _phase_number("recovery_seconds")

func _begin_warning() -> void:
	clear_hostiles_requested.emit()
	var cycles: Array = settings["phase_cycles"]
	var cycle: Array = cycles[phase]
	pattern = StringName(cycle[pattern_cursor % cycle.size()])
	pattern_cursor += 1
	locked_angle = global_position.direction_to(_target_position).angle()
	var gap_offset := 0.55 if phase == 0 else 0.75
	gap_angle = locked_angle + gap_offset * (1.0 if pattern_cursor % 2 == 0 else -1.0)
	rhythm = Rhythm.WARNING
	_warning_total = _phase_number("telegraph_seconds")
	remaining = _warning_total
	pattern_announced.emit(pattern, phase)

func _phase_number(key: String) -> float:
	var values: Array = settings[key]
	return float(values[phase])

func _burst_count() -> int:
	if pattern == &"petal_salvo": return int(_phase_number("salvo_bursts"))
	if pattern == &"black_lane": return int(_phase_number("black_bursts"))
	return 1

func _emit_burst() -> void:
	var shots: Array[Dictionary] = []
	var is_black := pattern == &"black_lane"
	var speed := _phase_number("black_speed" if is_black else "petal_speed")
	if pattern == &"tide_fan":
		var count := int(_phase_number("ring_count"))
		var half_gap := float(settings["ring_gap_half_angle"])
		for index in count:
			var angle := gap_angle + float(index) * TAU / float(count)
			if absf(angle_difference(gap_angle, angle)) <= half_gap: continue
			shots.append({"direction": Vector2.from_angle(angle), "speed": speed})
	else:
		var count := int(_phase_number("black_count" if is_black else "salvo_count"))
		var spread := _phase_number("black_spread" if is_black else "salvo_spread")
		var offset := float(burst_cursor) * (0.08 if is_black else 0.14)
		for index in count:
			var unit := float(index) / float(maxi(1, count - 1)) - 0.5
			shots.append({"direction": Vector2.from_angle(locked_angle + unit * spread + offset), "speed": speed})
	volley_requested.emit({"origin":global_position,"projectiles":shots,"reflectable":not is_black,"damage":1.0,"radius":8.0 if is_black else 7.0,"lifetime":float(settings["projectile_lifetime"]),"style":&"black_gold_cut" if is_black else &"reef_petal","color":Color(1.0,0.74,0.30) if is_black else Color(0.71,0.36,0.75)})

func take_damage(amount: float, source: StringName = &"weapon") -> bool:
	if settings.is_empty() or rhythm == Rhythm.DEFEATED or amount <= 0.0 or not is_finite(amount): return false
	var multiplier := float(settings["stagger_return_multiplier"]) if source == &"return" and rhythm == Rhythm.BREAK else 1.0
	var applied := minf(health, amount * multiplier)
	health = maxf(0.0, health - applied)
	total_damage += applied
	if source == &"return": return_damage += applied
	else: weapon_damage += applied
	_hit_flash = 1.0
	_hit_punch = 0.88
	_hit_ring = 1.0
	damaged.emit(applied, health, source)
	if health <= 0.0:
		rhythm = Rhythm.DEFEATED
		phase_controller.mark_defeated()
		clear_hostiles_requested.emit()
		defeated.emit(self)
		return true
	if phase == 0 and health <= definition.base_health * float(settings["phase_threshold"]):
		phase = 1
		pattern_cursor = 0
		rhythm = Rhythm.TRANSITION
		remaining = float(settings["phase_transition_seconds"])
		return_meter = 0.0
		clear_hostiles_requested.emit()
		phase_changed.emit(phase)
	elif source == &"return" and rhythm not in [Rhythm.BREAK, Rhythm.TRANSITION]:
		return_meter += amount
		if return_meter >= float(settings["stagger_threshold"]):
			return_meter = 0.0
			rhythm = Rhythm.BREAK
			remaining = float(settings["stagger_seconds"])
			breaks_opened += 1
			clear_hostiles_requested.emit()
			stagger_started.emit(remaining)
	_sync_visual_state()
	queue_redraw()
	return false

func get_contact_radius() -> float: return 90.0
func is_contact_dangerous() -> bool: return rhythm in [Rhythm.BURST, Rhythm.RECOVERY]

func get_lab_snapshot() -> Dictionary:
	var caption := "READY"
	match rhythm:
		Rhythm.INTRO: caption = "Collect petals. Release to attack."
		Rhythm.WARNING: caption = "DODGE - black/gold cannot be captured" if pattern == &"black_lane" else "COLLECT - prepare your Fold"
		Rhythm.BURST: caption = "DODGE" if pattern == &"black_lane" else "COLLECT - release before you overcommit"
		Rhythm.RECOVERY: caption = "REPOSITION" if pattern == &"black_lane" else "RELEASE - send the light back"
		Rhythm.BREAK: caption = "OPEN CORE - reflected damage x%.2f" % float(settings["stagger_return_multiplier"])
		Rhythm.TRANSITION: caption = "PHASE 2 - same rules, a little faster"
		Rhythm.DEFEATED: caption = "CLEAR"
	return {"health":health,"maximum_health":definition.base_health,"phase":phase+1,"rhythm":rhythm,"pattern":pattern,"remaining":maxf(0.0,remaining),"caption":caption,"stagger_ratio":clampf(return_meter/float(settings["stagger_threshold"]),0.0,1.0),"return_damage":return_damage,"weapon_damage":weapon_damage,"breaks_opened":breaks_opened}

func _sync_visual_state() -> void:
	phase_controller.phase_index = phase
	phase_controller.current_pattern = pattern
	match rhythm:
		Rhythm.INTRO, Rhythm.TRANSITION: phase_controller.state = FoldlightBossPhaseController.State.INTRO
		Rhythm.WARNING, Rhythm.BURST: phase_controller.state = FoldlightBossPhaseController.State.TELEGRAPH
		Rhythm.BREAK: phase_controller.state = FoldlightBossPhaseController.State.STAGGERED
		Rhythm.DEFEATED: phase_controller.state = FoldlightBossPhaseController.State.DEFEATED
		_: phase_controller.state = FoldlightBossPhaseController.State.RECOVERY

func _draw() -> void:
	super._draw()
	if not settings.is_empty() and rhythm != Rhythm.DEFEATED:
		var core_color := Color(1.0,0.69,0.28,0.85) if is_contact_dangerous() else Color(0.42,0.75,0.74,0.4)
		draw_arc(Vector2.ZERO,get_contact_radius(),0.0,TAU,64,core_color,2.5,true)
	if settings.is_empty() or rhythm != Rhythm.WARNING: return
	var progress := 1.0 - clampf(remaining/_warning_total,0.0,1.0)
	if pattern == &"black_lane":
		var spread := _phase_number("black_spread")
		var count := int(_phase_number("black_count"))
		for burst in _burst_count():
			for index in count:
				var unit := float(index)/float(maxi(1,count-1))-0.5
				var direction := Vector2.from_angle(locked_angle+unit*spread+float(burst)*0.08)
				draw_line(direction*68.0,direction*1700.0,Color(1.0,0.72,0.25,0.40+progress*0.4),3.0,true)
	elif pattern == &"tide_fan":
		var gap := float(settings["ring_gap_half_angle"])
		for side in [-1.0,1.0]:
			var direction := Vector2.from_angle(gap_angle+side*gap)
			draw_line(direction*100.0,direction*1400.0,Color(0.44,0.95,0.87,0.48),3.0,true)
	else:
		var direction := Vector2.from_angle(locked_angle)
		draw_line(direction*95.0,direction*660.0,Color(0.76,0.45,0.85,0.45),3.0,true)
