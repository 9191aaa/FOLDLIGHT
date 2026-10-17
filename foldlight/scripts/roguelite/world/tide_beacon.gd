class_name FoldlightTideBeacon
extends Area2D

## A room-local, pass-through Fold amplifier. Combat owns projectile conversion;
## this scene owns proximity, charging and its readable state.
signal pulse_requested(beacon: FoldlightTideBeacon)

const PaperArt = preload("res://scripts/visuals/paper_art.gd")
const PULSE_DURATION: float = 0.72

@export var charge_seconds: float = 0.42
@export var capture_radius: float = 620.0
@export var capture_limit: int = 8

var consumed: bool = false
var simulation_enabled: bool = false
var charge: float = 0.0
var nearby_player: FoldlightPlayer
var _clock: float = 0.0
var _retry_remaining: float = 0.0
var _pulse_remaining: float = 0.0
var _captured_count: int = 0
var _streams: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_interaction_active(value: bool) -> void:
	simulation_enabled = value
	queue_redraw()


func can_pulse(player: FoldlightPlayer) -> bool:
	return simulation_enabled and not consumed and player == nearby_player and is_instance_valid(player) and player.play_enabled and player.can_capture() and charge >= charge_seconds


func resolve_pulse(origins: PackedVector2Array) -> void:
	if origins.is_empty() or consumed:
		return
	consumed = true
	_captured_count = origins.size()
	_pulse_remaining = PULSE_DURATION
	_streams.clear()
	for origin in origins:
		_streams.append(to_local(origin))
	queue_redraw()


func _physics_process(delta: float) -> void:
	# Session modals stop combat. Freeze both charge and pulse while they are up.
	if not simulation_enabled:
		return
	_clock += delta
	_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
	_retry_remaining = maxf(0.0, _retry_remaining - delta)
	if not consumed:
		if is_instance_valid(nearby_player) and nearby_player.play_enabled and nearby_player.can_capture():
			charge = minf(charge_seconds, charge + delta)
			if charge >= charge_seconds and _retry_remaining <= 0.0:
				_retry_remaining = 0.24
				pulse_requested.emit(self)
		else:
			charge = 0.0
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is FoldlightPlayer:
		nearby_player = body as FoldlightPlayer


func _on_body_exited(body: Node2D) -> void:
	if body == nearby_player:
		nearby_player = null
		charge = 0.0


func _draw() -> void:
	var near := is_instance_valid(nearby_player)
	var light := PaperArt.GOLD if not consumed else PaperArt.FOLD.darkened(0.45)
	var breath := 0.72 + sin(_clock * 2.0) * 0.12
	draw_circle(Vector2(0, 10), 72.0, Color(PaperArt.INK, 0.44))
	draw_arc(Vector2.ZERO, 104.0, 0.0, TAU, 64, Color(light, 0.20 if near else 0.09), 1.5, true)
	# Soft current trails point toward the lantern without covering hostile shots.
	if not consumed:
		for index in 6:
			var phase := fmod(_clock * 0.18 + float(index) / 6.0, 1.0)
			var angle := float(index) * TAU / 6.0 + phase * 0.16
			var radius := lerpf(290.0, 84.0, phase)
			draw_arc(Vector2.ZERO, radius, angle, angle + 0.14, 8, Color(light, sin(phase * PI) * 0.10), 1.3, true)
	var base := PackedVector2Array([Vector2(-56, 21), Vector2(0, -4), Vector2(56, 21), Vector2(0, 47)])
	draw_colored_polygon(base, Color("263e43"))
	draw_colored_polygon(PackedVector2Array([base[0], base[1], base[3]]), Color("354c4c"))
	draw_polyline(PackedVector2Array([base[0], base[1], base[2], base[3], base[0]]), Color(light, 0.36), 1.4, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-13, 18), Vector2(-9, -55), Vector2(9, -55), Vector2(15, 18), Vector2(0, 28)]), Color("546a63"))
	draw_line(Vector2(0, -46), Vector2(0, 22), Color(PaperArt.PAPER, 0.27), 2.0, true)
	var flame := PackedVector2Array([Vector2(0, -112), Vector2(31, -73), Vector2(0, -35), Vector2(-31, -73)])
	if not consumed:
		draw_circle(Vector2(0, -73), 50.0, Color(light, 0.055 * breath))
		draw_circle(Vector2(0, -73), 35.0, Color(light, 0.09 * breath))
	draw_colored_polygon(flame, Color(light, 0.88 if not consumed else 0.35))
	draw_colored_polygon(PackedVector2Array([flame[0], flame[1], flame[2]]), Color(PaperArt.PAPER, 0.62 if not consumed else 0.12))
	draw_polyline(PackedVector2Array([flame[0], flame[1], flame[2], flame[3], flame[0]]), Color(light, breath), 2.0, true)
	if charge > 0.0 and not consumed:
		draw_arc(Vector2.ZERO, 113.0, -PI * 0.5, -PI * 0.5 + TAU * charge / charge_seconds, 64, Color(PaperArt.GOLD, 0.86), 3.0, true)
	if _pulse_remaining > 0.0:
		var progress := 1.0 - _pulse_remaining / PULSE_DURATION
		draw_arc(Vector2.ZERO, lerpf(70.0, capture_radius, progress), 0.0, TAU, 96, Color(PaperArt.GOLD, (1.0 - progress) * 0.46), 3.0, true)
		for origin in _streams:
			var head := origin.lerp(Vector2(0, -73), ease(progress, 0.5))
			var tail := origin.lerp(Vector2(0, -73), maxf(0.0, progress - 0.14))
			draw_line(tail, head, Color(PaperArt.PAPER, 1.0 - progress), 3.0, true)
	var font := ThemeDB.fallback_font
	var label := "引潮灯" if not consumed else "潮息 · 已用"
	draw_string(font, Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x * 0.5, 78), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(light, 0.9))
	if near and simulation_enabled:
		var hint := "按住折翼 · 收拢附近敌弹"
		if consumed:
			hint = "+%d 收纳 · 松开折翼返光" % _captured_count if nearby_player.captured > 0 else "本房已引潮 · 灯火暂息"
		elif nearby_player.captured >= nearby_player.get_capture_capacity():
			hint = "收纳已满 · 松开折翼返光"
		elif charge >= charge_seconds:
			hint = "等待可收弹 · 黑金弹不可收"
		draw_string(font, Vector2(-font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, 106), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(PaperArt.PAPER, 0.88))
