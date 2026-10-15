extends SceneTree

const Director = preload("res://scripts/endless/endless_zone_director.gd")
const Definition = preload("res://scripts/endless/endless_map_definition.gd")
const MAP = preload("res://resources/endless/maps/folded_delta.tres")
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := Director.new()
	var snapshot := director.reset(MAP, 781)
	_check(snapshot.phase == &"rest" and is_equal_approx(snapshot.remaining, 60.0), "first minute is safe exploration")
	snapshot = director.advance_to(59.999)
	_check(snapshot.warning_ids.is_empty() and snapshot.closed_ids.is_empty(), "no premature closure before sixty active seconds")
	snapshot = director.advance_to(60.0)
	var first_ids: Array = snapshot.warning_ids.duplicate()
	_check(snapshot.phase == &"warning" and snapshot.warning_ids.size() == 1 and is_equal_approx(snapshot.remaining, 12.0), "initial closure announces one area for twelve seconds")
	var selected_rect := Rect2()
	for zone: Dictionary in snapshot.zones:
		if zone.state == &"warning":
			selected_rect = zone.rect
	_check(director.is_point_reserved(selected_rect.get_center()) and not director.is_point_closed(selected_rect.get_center()), "warning reserves task sites but does not deal closure damage")
	snapshot = director.advance_to(71.999)
	_check(snapshot.phase == &"warning", "the entire warning duration is honored")
	snapshot = director.advance_to(72.0)
	_check(snapshot.phase == &"closed" and snapshot.closed_ids == first_ids and is_equal_approx(snapshot.remaining, 24.0), "the announced area closes without retargeting")
	_check(director.is_point_closed(selected_rect.get_center()), "closed area is hazardous")
	var zones_before: Array = snapshot.zones.duplicate(true)
	snapshot = director.advance_to(72.0)
	_check(snapshot.zones == zones_before, "same active clock is frozen during pause, reward and hidden UI")
	snapshot = director.advance_to(30.0)
	_check(is_equal_approx(snapshot.combat_time, 72.0) and snapshot.phase == &"closed", "stale clock cannot rewind closure exposure")
	snapshot = director.advance_to(96.0)
	_check(snapshot.phase == &"rest" and snapshot.closed_ids.is_empty() and is_equal_approx(snapshot.remaining, 10.0), "all closed water reopens for the ten-second rest")
	snapshot = director.advance_to(106.0)
	_check(snapshot.cycle == 1 and snapshot.warning_ids.size() == 1, "next round starts after rest with its own deterministic choice")
	snapshot = director.advance_to(198.0)
	_check(snapshot.phase == &"warning" and snapshot.warning_ids.size() == 2, "late rounds close at most two areas after three active minutes")
	var late_ids: Array = snapshot.warning_ids.duplicate()
	snapshot = director.advance_to(210.0)
	_check(snapshot.closed_ids == late_ids, "two-area warning also locks its announced choices")
	var refuges_safe := true
	for point in MAP.refuge_points:
		refuges_safe = refuges_safe and not director.is_point_reserved(point, 34.0)
	_check(refuges_safe, "permanent refuges remain outside every announced and closed area")
	var stepped := Director.new()
	var jumped := Director.new()
	stepped.reset(MAP, 913)
	jumped.reset(MAP, 913)
	for index in 301:
		stepped.advance_to(float(index))
	var one_jump := jumped.advance_to(300.0)
	_check(stepped.get_snapshot() == one_jump, "same seed and combat clock produce the same state regardless of frame partition")
	seed(1203)
	var expected_random := randi()
	seed(1203)
	jumped.reset(MAP, 14)
	jumped.advance_to(200.0)
	_check(randi() == expected_random, "closure selection does not consume the gameplay global random stream")
	var varied: Dictionary = {}
	for run_seed in 24:
		jumped.reset(MAP, run_seed)
		var choice: Dictionary = jumped.advance_to(60.0)
		var ids: Array = choice.warning_ids
		varied[ids[0]] = true
	_check(varied.size() >= 4, "different seeds visit multiple authored districts")
	jumped.reset(MAP, 781)
	var protected_points := PackedVector2Array([selected_rect.get_center()])
	snapshot = jumped.advance_to(60.0, protected_points)
	_check(not first_ids[0] in snapshot.warning_ids, "an already active task excludes its zone from closure selection")
	var all_protected := PackedVector2Array()
	for rect in MAP.closure_zone_rects:
		all_protected.append(rect.get_center())
	jumped.reset(MAP, 781)
	snapshot = jumped.advance_to(198.0, all_protected)
	_check(snapshot.warning_ids.is_empty(), "safety takes priority when all candidate zones host protected tasks")
	jumped.reset(MAP, 781)
	snapshot = jumped.advance_to(198.0)
	var locked: Array = snapshot.warning_ids.duplicate()
	snapshot = jumped.advance_to(199.0, all_protected)
	_check(snapshot.warning_ids == locked, "new objectives cannot silently move an already announced closure")
	var overlap := {"zones": [{"rect": Rect2(0, 0, 1000, 1000), "state": &"closed"}], "safe_corridors": [Rect2(400, 0, 200, 1000)]}
	_check(not Definition.is_point_reserved_in_snapshot(Vector2(500, 300), overlap) and Definition.is_point_reserved_in_snapshot(Vector2(300, 300), overlap), "shared damage and placement predicate gives permanent corridors precedence")
	_check(Definition.is_point_reserved_in_snapshot(Vector2(410, 300), overlap, 30.0), "objective radius may not straddle safe and closed water")
	var narrow := {"zones": [{"rect": Rect2(0, 0, 1000, 1000), "state": &"warning"}], "safe_corridors": [Rect2(460, 0, 80, 1000)]}
	_check(Definition.is_point_reserved_in_snapshot(Vector2(500, 300), narrow, 240.0), "a narrow safe sliver cannot fit a storm objective or produce a negative rectangle query")
	var narrow_definition := Definition.new()
	narrow_definition.safe_corridors = [Rect2(460, 0, 80, 1000)]
	_check(not narrow_definition.is_permanent_safe(Vector2(500, 300), 240.0), "permanent-safe test rejects a footprint wider than its corridor without geometry errors")
	var fragments := Definition.zone_fragments(Rect2(0, 0, 1000, 1000), overlap.safe_corridors)
	var area := 0.0
	var safe_not_painted := true
	for fragment in fragments:
		area += fragment.get_area()
		safe_not_painted = safe_not_painted and not fragment.has_point(Vector2(500, 300))
	_check(is_equal_approx(area, 800000.0) and safe_not_painted, "world mask subtracts the exact permanently safe area")
	director.reset(MAP, 781)
	_check(director.get_snapshot().cycle == -1 and director.get_snapshot().closed_ids.is_empty(), "restarting clears the previous area's closure state")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	print("FOLDLIGHT_ENDLESS_ZONE_DIRECTOR: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
