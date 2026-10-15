extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var exposure := FoldlightEndlessZoneExposure.new()
	exposure.reset()
	check(exposure.advance(1.9, true) == 0, "entering a closed zone provides two seconds to leave")
	check(exposure.advance(0.1, true) == 1, "first damage is due exactly at the grace boundary")
	check(exposure.advance(1.9, true) == 0, "hazard cannot drain health every physics frame")
	check(exposure.advance(0.1, true) == 1, "sustained exposure damages once every two seconds")
	exposure.advance(0.5, false)
	check(exposure.advance(1.9, true) == 0, "leaving for safety resets entry grace")
	var remaining := exposure.seconds_until_damage()
	check(exposure.advance(0.0, true) == 0 and is_equal_approx(remaining, exposure.seconds_until_damage()), "paused effective time cannot consume evacuation grace")
	var stepped := FoldlightEndlessZoneExposure.new()
	stepped.reset()
	var hits := 0
	for index in 600:
		hits += stepped.advance(1.0 / 60.0, true)
	var coarse := FoldlightEndlessZoneExposure.new()
	coarse.reset()
	check(hits == 5 and coarse.advance(10.0, true) == hits, "damage cadence is independent of simulation step size")
	print("FOLDLIGHT_ENDLESS_ZONE_EXPOSURE: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		failures.append(label)
		push_error("[FAIL] " + label)
