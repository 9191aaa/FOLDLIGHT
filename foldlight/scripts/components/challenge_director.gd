class_name FoldlightChallengeDirector
extends Node

signal event_started(snapshot: Dictionary)
signal draft_requested()
signal tier_changed(tier: int)

const TIER_SECONDS: float = 45.0
const DRAFT_SECONDS: float = 75.0
const EXPANSION_SECONDS: float = 600.0
const START_BOUNDS := Rect2(400.0, 230.0, 1120.0, 620.0)
const FULL_BOUNDS := Rect2(76.0, 122.0, 1768.0, 840.0)

const POSITIVE_EVENTS: Array[Dictionary] = [
	{"id": &"lantern_rain", "title": "灯雨归航", "detail": "一圈慢弹化为可收纳灯瓣", "duration": 8.0, "accent": Color(1.0, 0.72, 0.28)},
	{"id": &"clear_sky", "title": "纸海放晴", "detail": "抹去半场敌弹并获得额外分数", "duration": 4.0, "accent": Color(0.42, 0.92, 0.84)},
	{"id": &"wide_fold", "title": "潮界舒展", "detail": "折域边界暂时扩大 28%", "duration": 14.0, "accent": Color(0.30, 0.88, 0.86)},
	{"id": &"slow_tide", "title": "静潮一息", "detail": "所有敌弹暂时减速", "duration": 12.0, "accent": Color(0.48, 0.72, 0.96)},
	{"id": &"dawn_breath", "title": "余晖回身", "detail": "回复一瓣生命并补满折息", "duration": 5.0, "accent": Color(1.0, 0.56, 0.42)},
	{"id": &"golden_cache", "title": "金线遗藏", "detail": "立即获得潮分与一轮返光弹药", "duration": 7.0, "accent": Color(1.0, 0.80, 0.34)},
]

const NEGATIVE_EVENTS: Array[Dictionary] = [
	{"id": &"black_squall", "title": "黑潮骤雨", "detail": "四面同时落下高速弹雨", "duration": 10.0, "accent": Color(0.88, 0.22, 0.50)},
	{"id": &"elite_hunt", "title": "双煞追灯", "detail": "两名带词缀的精英进入潮界", "duration": 9.0, "accent": Color(0.94, 0.38, 0.34)},
	{"id": &"crosswind", "title": "折向横风", "detail": "敌弹持续向东偏航", "duration": 14.0, "accent": Color(0.50, 0.42, 0.92)},
	{"id": &"sealed_storm", "title": "封钉风暴", "detail": "不可收纳的黑金封钉穿过战场", "duration": 10.0, "accent": Color(0.92, 0.50, 0.24)},
	{"id": &"narrow_fold", "title": "潮纸收紧", "detail": "折域边界暂时缩小 24%", "duration": 12.0, "accent": Color(0.72, 0.26, 0.72)},
	{"id": &"haste_tide", "title": "急潮催行", "detail": "敌弹与敌群暂时加速", "duration": 12.0, "accent": Color(0.96, 0.28, 0.36)},
]

var active: bool = false
var elapsed: float = 0.0
var tier: int = 1
var current_event: Dictionary = {}
var events_seen: int = 0

var _next_event_at: float = 20.0
var _next_draft_at: float = DRAFT_SECONDS
var _draft_waiting: bool = false
var _negative_streak: int = 0
var _recent_ids: Array[StringName] = []
var _rng := RandomNumberGenerator.new()


func start(seed: int) -> void:
	active = true
	elapsed = 0.0
	tier = 1
	current_event.clear()
	events_seen = 0
	_next_event_at = 20.0
	_next_draft_at = DRAFT_SECONDS
	_draft_waiting = false
	_negative_streak = 0
	_recent_ids.clear()
	_rng.seed = seed


func reset() -> void:
	active = false
	elapsed = 0.0
	tier = 1
	current_event.clear()
	events_seen = 0
	_draft_waiting = false
	_recent_ids.clear()


func tick(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	var next_tier := 1 + int(elapsed / TIER_SECONDS)
	if next_tier != tier:
		tier = next_tier
		tier_changed.emit(tier)
	if not current_event.is_empty():
		current_event["remaining"] = maxf(0.0, float(current_event.get("remaining", 0.0)) - delta)
		if float(current_event["remaining"]) <= 0.0:
			current_event.clear()
	if elapsed >= _next_event_at:
		_begin_random_event()
		_next_event_at = elapsed + _rng.randf_range(24.0, 36.0)
	if not _draft_waiting and elapsed >= _next_draft_at:
		_draft_waiting = true
		draft_requested.emit()


func complete_draft() -> void:
	if not _draft_waiting:
		return
	_draft_waiting = false
	_next_draft_at += DRAFT_SECONDS


func get_arena_bounds() -> Rect2:
	var ratio := clampf(elapsed / EXPANSION_SECONDS, 0.0, 1.0)
	ratio = ease(ratio, 0.72)
	return Rect2(START_BOUNDS.position.lerp(FULL_BOUNDS.position, ratio), START_BOUNDS.size.lerp(FULL_BOUNDS.size, ratio))


func get_fold_radius_scale() -> float:
	var event_id := StringName(current_event.get("id", &""))
	if event_id == &"wide_fold":
		return 1.28
	if event_id == &"narrow_fold":
		return 0.76
	return 1.0


func get_shot_speed_scale() -> float:
	var event_id := StringName(current_event.get("id", &""))
	if event_id == &"slow_tide":
		return 0.70
	if event_id == &"haste_tide":
		return 1.22
	return 1.0


func get_enemy_speed_scale() -> float:
	return 1.18 if StringName(current_event.get("id", &"")) == &"haste_tide" else 1.0


func get_crosswind_force() -> float:
	return 86.0 if StringName(current_event.get("id", &"")) == &"crosswind" else 0.0


func snapshot() -> Dictionary:
	return {
		"active": active,
		"elapsed": elapsed,
		"tier": tier,
		"events_seen": events_seen,
		"arena_ratio": clampf(elapsed / EXPANSION_SECONDS, 0.0, 1.0),
		"next_event": maxf(0.0, _next_event_at - elapsed),
		"next_draft": maxf(0.0, _next_draft_at - elapsed),
		"event": current_event.duplicate(true),
	}


func _begin_random_event() -> void:
	var negative := _rng.randf() < 0.54
	if _negative_streak >= 2:
		negative = false
	var catalog := NEGATIVE_EVENTS if negative else POSITIVE_EVENTS
	var candidates: Array[Dictionary] = []
	for definition in catalog:
		if not _recent_ids.has(StringName(definition["id"])):
			candidates.append(definition)
	if candidates.is_empty():
		candidates.assign(catalog)
	var chosen := candidates[_rng.randi_range(0, candidates.size() - 1)].duplicate(true)
	chosen["polarity"] = &"negative" if negative else &"positive"
	chosen["remaining"] = float(chosen.get("duration", 8.0))
	current_event = chosen
	events_seen += 1
	_negative_streak = _negative_streak + 1 if negative else 0
	_recent_ids.append(StringName(chosen["id"]))
	while _recent_ids.size() > 2:
		_recent_ids.pop_front()
	event_started.emit(chosen.duplicate(true))
