extends SceneTree

## Player-feedback contract for 3.1: rooms stay populated, Fold pays off as
## homing return light, movement has meaningful cadence, items swing fights,
## and both the enemy and terrain vocabularies materially expand.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_dense_plan()
	_test_overlapping_reinforcements()
	await _test_homing_return()
	_test_dash_and_items()
	_test_new_content()
	_finish()


func _test_dense_plan() -> void:
	var director := FoldlightEncounterDirector.new()
	root.add_child(director)
	var definition := FoldlightRogueContentCatalog.encounter_by_id(&"reef_crossfire")
	var plan := director.compose_encounter(definition, FoldlightRogueContentCatalog.ENEMIES, 310031, 1, _make_slots(), Vector2(1440, 1180))
	var entries := plan.get("entries", []) as Array
	var opening_count := entries.filter(func(entry: Dictionary) -> bool: return int(entry.get("wave", -1)) == 0).size()
	_check((plan.get("errors", []) as Array).is_empty(), "dense region-one plan remains valid and deterministic")
	_check(entries.size() >= 16, "an ordinary opening-region room contains at least sixteen enemies")
	_check(opening_count >= 8, "the opening wave presents at least eight simultaneous targets")
	director.queue_free()


func _test_overlapping_reinforcements() -> void:
	var runtime := FoldlightRoomEncounterRuntime.new()
	root.add_child(runtime)
	var entries: Array[Dictionary] = [
		{"enemy_id": &"paper_drifter", "wave": 0},
		{"enemy_id": &"paper_drifter", "wave": 0},
		{"enemy_id": &"paper_drifter", "wave": 1},
		{"enemy_id": &"needle_skiff", "wave": 1},
	]
	_check(runtime.configure({"encounter_id": &"overlap", "entries": entries, "errors": []}).is_empty() and runtime.begin(), "overlap fixture begins")
	runtime.advance_simulation(runtime.telegraph_duration + 0.01)
	_check(runtime.active_enemy_count == 2, "opening overlap fixture spawns normally")
	runtime.notify_enemy_defeated()
	_check(runtime.state == FoldlightRoomEncounterRuntime.State.TELEGRAPHING, "next wave starts telegraphing before the field is empty")
	runtime.advance_simulation(runtime.telegraph_duration + 0.01)
	_check(runtime.active_enemy_count == 3, "reinforcement adds to surviving enemies instead of replacing them")
	runtime.queue_free()


func _test_homing_return() -> void:
	var projectile_scene := load("res://scenes/roguelite/combat/rogue_projectile.tscn") as PackedScene
	var projectile := projectile_scene.instantiate() as FoldlightRogueProjectile
	var target := Node2D.new()
	root.add_child(target)
	root.add_child(projectile)
	target.global_position = Vector2(300, 180)
	projectile.configure({
		"origin": Vector2.ZERO,
		"velocity": Vector2.RIGHT * 700.0,
		"hostile": false,
		"style": &"return_light",
		"homing_target": target,
		"homing_strength": 8.0,
		"lifetime": 2.0,
	})
	projectile.advance_simulation(0.1)
	_check(projectile.velocity.y > 20.0, "return light visibly curves toward its assigned target")
	var homing_variant: Variant = projectile.get("homing_strength")
	_check(homing_variant is float and float(homing_variant) >= 6.0, "return projectile exposes a strong bounded homing contract")
	projectile.queue_free()
	target.queue_free()
	await process_frame


func _test_dash_and_items() -> void:
	var dash := FoldlightDashComponent.new()
	root.add_child(dash)
	_check(is_equal_approx(dash.base_cooldown, 2.0), "base dash cooldown is exactly two seconds")
	var paper_burst := FoldlightRogueContentCatalog.active_item_by_id(&"paper_burst")
	var mirror_step := FoldlightRogueContentCatalog.active_item_by_id(&"mirror_step")
	var ink_wash := FoldlightRogueContentCatalog.active_item_by_id(&"ink_wash")
	var anchor := FoldlightRogueContentCatalog.active_item_by_id(&"crease_anchor")
	var tide_clock := FoldlightRogueContentCatalog.active_item_by_id(&"tide_clock")
	var sun_stamp := FoldlightRogueContentCatalog.active_item_by_id(&"sun_stamp")
	_check(paper_burst.power >= 4.0, "Paper Burst has room-swinging damage instead of a token push")
	_check(mirror_step.duration >= 3.5, "Mirror Step creates a meaningful reposition window")
	_check(ink_wash.power >= 2.0, "Ink Wash restores enough health to matter")
	_check(anchor.power >= 4.0 and anchor.duration >= 4.0, "Crease Anchor protects through a real danger sequence")
	_check(tide_clock.power <= 0.40 and tide_clock.duration >= 4.5, "Tide Clock strongly controls a crowded room")
	_check(sun_stamp.power >= 2.0 and sun_stamp.duration >= 5.0, "Sun Stamp delivers a visible weapon overdrive")
	dash.queue_free()


func _test_new_content() -> void:
	_check(FoldlightRogueContentCatalog.ENEMIES.size() >= 9, "enemy catalog adds three distinct mechanic enemies")
	_check(FoldlightRogueContentCatalog.enemy_by_id(&"prism_bulwark") != null, "catalog includes the Return-breakable Prism Bulwark")
	_check(FoldlightRogueContentCatalog.enemy_by_id(&"brood_lantern") != null, "catalog includes the stationary Brood Lantern")
	_check(FoldlightRogueContentCatalog.enemy_by_id(&"shear_scribe") != null, "catalog includes the unreflectable Shear Scribe")
	_check(load("res://scenes/roguelite/enemies/prism_bulwark.tscn") is PackedScene, "Prism Bulwark has a dedicated scene")
	_check(load("res://scenes/roguelite/enemies/brood_lantern.tscn") is PackedScene, "Brood Lantern has a dedicated scene")
	_check(load("res://scenes/roguelite/enemies/shear_scribe.tscn") is PackedScene, "Shear Scribe has a dedicated scene")
	_check(FoldlightRogueTerrainDefinition.TerrainKind.size() >= 6, "terrain vocabulary adds positive and double-edged fields")
	_check(FoldlightRogueContentCatalog.validation_errors().is_empty(), "expanded content catalog remains internally valid")


func _make_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for wave_row in 3:
		for column in 10:
			var index := wave_row * 10 + column
			slots.append({"id": StringName("g%02d" % index), "kind": &"ground", "position": Vector2(280 + column * 255, 260 + wave_row * 520)})
	for index in 6:
		slots.append({"id": StringName("t%02d" % index), "kind": &"turret", "position": Vector2(180 if index % 2 == 0 else 2700, 220 + (index / 2) * 560)})
	return slots


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_JOY_REWORK_3_1: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_JOY_REWORK_3_1: FAIL — %s" % ", ".join(_failures))
		quit(1)
