class_name FoldlightPaperHitReaction
extends RefCounted

## Actor-local paper deformation. No gameplay clocks, random draws or child nodes.
const Palette = preload("res://scripts/ui/foldlight_theme.gd")

var direction: Vector2 = Vector2.RIGHT
var tier: int = 0
var kind: StringName = &"weapon"
var flash: float = 0.0
var punch: float = 0.0
var remaining: float = 0.0
var pulse_count: int = 0
var _age: float = 0.0
var _duration: float = 0.0
var _retrigger_remaining: float = 0.0


func reset() -> void:
	direction = Vector2.RIGHT
	tier = 0
	kind = &"weapon"
	flash = 0.0
	punch = 0.0
	remaining = 0.0
	pulse_count = 0
	_age = 0.0
	_duration = 0.0
	_retrigger_remaining = 0.0


func trigger(incoming: Vector2, source: StringName, broken: bool = false) -> void:
	var next_tier: int = 3 if broken else (2 if source in [&"return", &"return_light"] else 1)
	# One volley reads as one impact. A stronger hit may interrupt a light tap,
	# but sustained ordinary fire cannot erase the return-light break pose.
	if not broken and remaining > 0.0 and (next_tier < tier or (next_tier == tier and _retrigger_remaining > 0.0)):
		return
	direction = incoming.normalized() if not incoming.is_zero_approx() else Vector2.RIGHT
	tier = next_tier
	kind = &"break" if broken else (&"return" if tier == 2 else &"weapon")
	_duration = 0.13 if tier == 1 else (0.24 if tier == 2 else 0.30)
	_retrigger_remaining = 0.085 if tier == 1 else _duration * 0.85
	_age = 0.0
	remaining = _duration
	pulse_count += 1
	_update_pose()


func advance(delta: float) -> void:
	var elapsed := maxf(0.0, delta)
	_age += elapsed
	remaining = maxf(0.0, remaining - elapsed)
	_retrigger_remaining = maxf(0.0, _retrigger_remaining - elapsed)
	_update_pose()


func snapshot() -> Dictionary:
	return {
		"flash": flash, "punch": punch,
		# Legacy ring key now reports only the short return-light edge arc.
		"ring": remaining / _duration if tier >= 2 and _duration > 0.0 else 0.0,
		"direction": direction, "tier": tier, "kind": kind,
		"remaining": remaining, "pulse_count": pulse_count,
	}


func _update_pose() -> void:
	if remaining <= 0.0:
		flash = 0.0
		punch = 0.0
		return
	var flash_seconds: float = 0.075 if tier == 1 else (0.14 if tier == 2 else 0.18)
	var peak_flash: float = 0.46 if tier == 1 else 1.0
	var peak_punch: float = 0.30 if tier == 1 else 1.0
	flash = peak_flash * maxf(0.0, 1.0 - _age / flash_seconds)
	# A small recoil followed by a much smaller elastic return. This transforms
	# drawing only; the body, aim origin and collision shapes never move.
	punch = peak_punch * exp(-_age * 22.0) * cos(_age * 28.0)


func draw_details(canvas: Node2D, radius: float) -> void:
	if remaining <= 0.0 or _duration <= 0.0:
		return
	var progress: float = clampf(_age / _duration, 0.0, 1.0)
	var fade: float = pow(1.0 - progress, 1.6)
	var heavy: bool = tier >= 2
	var side: Vector2 = direction.orthogonal()
	var contact: Vector2 = -direction * radius * (0.70 if not heavy else 0.45)
	var span: float = radius * (0.25 if not heavy else 0.66)
	var tear := PackedVector2Array([
		contact - side * span,
		contact - side * span * 0.36 + direction * 3.0,
		contact + direction * (-2.0 if not heavy else -5.0),
		contact + side * span * 0.42 + direction * 4.0,
		contact + side * span,
	])
	canvas.draw_polyline(tear, Color(Palette.PAPER, fade * 0.92), 1.8 if not heavy else 2.8, true)
	if heavy:
		var angle: float = (-direction).angle()
		canvas.draw_arc(Vector2.ZERO, radius + 4.0 + progress * 14.0, angle - 0.58, angle + 0.58, 15, Color(Palette.FOLD, fade * 0.50), 2.2, true)
		canvas.draw_line(contact - side * span * 0.84 + direction * 5.0, contact + side * span * 0.84 + direction * 5.0, Color(Palette.GOLD, fade * 0.56), 1.2, true)
	var shard_count: int = 2 if tier == 1 else (4 if tier == 2 else 6)
	for index in shard_count:
		var spread: float = (float(index) - float(shard_count - 1) * 0.5) * (0.86 if not heavy else 0.43)
		var outward: Vector2 = (-direction).rotated(spread)
		var travel: float = (12.0 if not heavy else 28.0) * (1.0 - pow(1.0 - progress, 2.0))
		var center: Vector2 = contact + side * spread * span * 0.60 + outward * (4.0 + travel)
		var length: float = (3.4 if not heavy else 6.0) * (1.0 - progress * 0.45)
		var across: Vector2 = outward.orthogonal() * (1.6 if not heavy else 2.7)
		var flap := PackedVector2Array([center + outward * length, center + across, center - outward * length * 0.65, center - across * 0.50])
		canvas.draw_colored_polygon(flap, Color(Palette.PAPER if index % 2 == 0 else Palette.GOLD, fade * (0.76 if not heavy else 0.90)))
		if heavy:
			canvas.draw_line(center - outward * length * 0.65, center + outward * length, Color(Palette.INK, fade * 0.52), 1.0, true)
