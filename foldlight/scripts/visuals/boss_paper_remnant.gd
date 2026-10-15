extends Node2D

## Pure visual snapshot: no actor references, collisions, signals, loot or RNG.
## Normal combat advances this node; the existing boss-clear presentation can
## explicitly advance it while combat itself is suspended.
const Puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
const LIFETIME: float = 1.60
const QUIET_LIFETIME: float = 0.45
const DRAW_INTERVAL: float = 1.0 / 30.0

var _boss_id: StringName = &""
var _pose: Dictionary = {}
var _elapsed: float = 0.0
var _lifetime: float = LIFETIME
var _simulation_active: bool = true
var _draw_clock: float = 0.0
var _draw_count: int = 0


func _ready() -> void:
	add_to_group(&"boss_remnants")
	z_index = 1


func configure(boss_id: StringName, pose: Dictionary) -> void:
	_boss_id = boss_id
	_pose = pose.duplicate(true)
	_pose["intro"] = 1.0
	_pose["charge"] = 0.0
	_pose["recoil"] = 0.0
	_pose["stagger"] = 0.0
	_pose["transition"] = 1.0
	_pose["transition_active"] = false
	_pose["flash"] = 0.0
	_pose["death"] = 0.0
	_elapsed = 0.0
	_draw_clock = 0.0
	_lifetime = QUIET_LIFETIME if float(_pose.get("motion_scale", 1.0)) <= 0.0 else LIFETIME
	queue_redraw()


func set_simulation_active(value: bool) -> void:
	_simulation_active = value
	set_process(value)


func _process(delta: float) -> void:
	if _simulation_active:
		advance_simulation(delta)


func advance_simulation(delta: float) -> void:
	if is_queued_for_deletion() or _pose.is_empty():
		return
	_elapsed = minf(_lifetime, _elapsed + maxf(0.0, delta))
	var progress := clampf(_elapsed / _lifetime, 0.0, 1.0)
	_pose["death"] = progress
	modulate.a = 1.0 - smoothstep(0.35, 1.0, progress)
	if _elapsed >= _lifetime:
		hide()
		queue_free()
		return
	_draw_clock += maxf(0.0, delta)
	if _draw_clock >= DRAW_INTERVAL:
		_draw_clock = fmod(_draw_clock, DRAW_INTERVAL)
		queue_redraw()


func get_lifecycle_snapshot() -> Dictionary:
	return {"id": _boss_id, "elapsed": _elapsed, "lifetime": _lifetime,
		"active": _simulation_active, "draw_count": _draw_count,
		"pose": _pose.duplicate(true), "damaging": false}


func _draw() -> void:
	if _pose.is_empty():
		return
	_draw_count += 1
	Puppet.draw_puppet(self, _boss_id, _pose)
