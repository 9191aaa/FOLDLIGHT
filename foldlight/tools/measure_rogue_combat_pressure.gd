extends SceneTree

## Bounded diagnostic, not a win-rate benchmark. Run with --headless --fixed-fps 60
## --path . --script tools/measure_rogue_combat_pressure.gd -- --label=current
## Real physics, movement input, weapon cadence, Fold input, captures and damage.
const SEEDS := [330031, 81002]
const SAMPLES := [&"entry", &"late_ordinary", &"first_boss"]
const POLICIES := [&"automatic", &"fold_cycle"]
const LATE_BUILD := {"rapid_crease": 1, "steady_lantern": 1, "twin_fold": 1, "returning_edge": 1}
const SOURCE_FILES := [
	"scripts/roguelite/rogue_session_controller.gd", "scripts/roguelite/encounter_director.gd",
	"scripts/roguelite/world/room_encounter_runtime.gd", "scripts/roguelite/combat/rogue_combat_runtime.gd",
	"scripts/roguelite/combat/rogue_enemy_actor.gd", "scripts/roguelite/bosses/rogue_boss_actor.gd",
	"scripts/roguelite/bosses/boss_phase_controller.gd", "scripts/roguelite/bosses/boss_arena_controller.gd",
	"resources/roguelite/bosses/reef_crown_battery.tres", "scripts/player.gd",
]

var _label := "current"
var _duration := 25.0
var _game: FoldlightGame
var _session: FoldlightRogueSessionController
var _combat: FoldlightRogueCombatRuntime
var _metrics: Dictionary
var _actors: Dictionary
var _projectiles: Array[FoldlightRogueProjectile]
var _claimed_hits: Dictionary
var _fold_held := false
var _elapsed := 0.0
var _stop_reason := ""
var _previous_position := Vector2.ZERO
var _errors: Array[String] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--seconds="):
			_duration = clampf(float(argument.trim_prefix("--seconds=")), 20.0, 30.0)
	call_deferred("_run")


func _run() -> void:
	var source_hashes := _source_hashes()
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var results: Array[Dictionary] = []
	for seed_value in SEEDS:
		for sample in SAMPLES:
			for policy in POLICIES:
				results.append(await _measure(seed_value, sample, policy))
	var report := {
		"label": _label, "seconds_per_case": _duration, "physics_hz": 60,
		"source_sha256": source_hashes, "source_changed_during_run": source_hashes != _source_hashes(),
		"notes": [
			"Diagnostic samples, not human win rates or completed-run balance claims.",
			"Generated entry/deepest non-elite non-boss/first boss; no fabricated captures, hits, damage, or phase changes.",
			"Entry uses starter build; later samples use a controlled legal four-upgrade snapshot, not a played reward history.",
			"Both policies follow the same time-indexed oval target through normal movement input; collision and Fold speed may alter actual positions.",
			"No dash or active item. Fold presses last 1.55s, followed by 1.5s release; failed/empty folds remain real outcomes.",
			"Damage is actual health lost, excluding overkill. Ordinary projectile attribution uses live per-projectile hit IDs; unmatched damage is other.",
			"Enemy remaining HP includes spawned survivors only; planned/spawned counts distinguish pending waves.",
		],
		"errors": _errors, "cases": results,
	}
	var output_dir := "res://build/combat-pressure"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var output_path := output_dir.path_join(_label + ".json")
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write pressure report: %s" % output_path)
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("PRESSURE_REPORT %s errors=%d" % [ProjectSettings.globalize_path(output_path), _errors.size()])
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	quit(0 if _errors.is_empty() else 1)


func _measure(seed_value: int, sample: StringName, policy: StringName) -> Dictionary:
	_release_inputs()
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as FoldlightGame
	root.add_child(_game)
	await process_frame
	await process_frame
	_session = _game.rogue_session
	_session.persist_profile = false
	_session._activate_gameplay()
	_session.mode = FoldlightRogueSessionController.SessionMode.RUN
	var controller := _session.run_controller
	var route := controller.route_generator.generate_route(seed_value, FoldlightRogueContentCatalog.REGIONS)
	controller.run_state.begin_run(seed_value, route)
	var region := controller.get_current_region_snapshot()
	var room_node := _choose_room(region, sample)
	controller.run_state.current_node_id = StringName(room_node.get("id", &""))
	controller.run_state.room_count = int(room_node.get("depth", 0))
	controller.run_state.upgrade_levels = {} if sample == &"entry" else LATE_BUILD.duplicate()
	controller.phase = FoldlightRogueRunController.Phase.ENTERING_ROOM
	_combat = _session.world.combat_runtime
	_elapsed = 0.0
	_stop_reason = ""
	_actors = {}
	_projectiles = []
	_claimed_hits = {}
	_metrics = {
		"seed": seed_value, "sample": sample, "policy": policy, "room": room_node.duplicate(true),
		"build": controller.run_state.upgrade_levels.duplicate(), "weapons": ["crease_lantern"],
		"hp_start": 5, "hp_end": 5, "player_hits": 0, "spawned_enemies": 0, "defeated_enemies": 0,
		"defeated_before_first_attack": 0, "enemy_attack_events": 0, "spawned_enemy_hp": 0.0,
		"hostile_shots": 0, "weapon_shots": 0, "return_shots": 0, "captures": 0,
		"fold_starts": 0, "fold_releases": 0, "released_captures": 0,
		"enemy_damage_events": 0, "weapon_hit_events": 0, "return_hit_events": 0,
		"weapon_damage": 0.0, "return_damage": 0.0, "other_damage": 0.0,
		"peak_hostile_shots": 0, "peak_hostile_within_200px": 0, "peak_live_enemies": 0,
		"distance_travelled": 0.0, "maximum_physics_delta": 0.0, "samples": [],
	}
	_combat.enemy_spawned.connect(_on_enemy_spawned)
	_combat.projectile_spawned.connect(_on_projectile_spawned)
	_combat.projectile_captured.connect(func(_count: int, _position: Vector2) -> void: _metrics["captures"] += 1)
	_combat.player_hit.connect(func(_health: int) -> void: _metrics["player_hits"] += 1)
	_game.player.fold_started.connect(func() -> void: _metrics["fold_starts"] += 1)
	_game.player.fold_released.connect(func(count: int, _ratio: float) -> void:
		_metrics["fold_releases"] += 1
		_metrics["released_captures"] += count
	)
	# End the sample on its actual clear instead of advancing into another room.
	var room := _session.world.room_runtime
	room.encounter_cleared.disconnect(_session._on_encounter_cleared)
	room.encounter_cleared.connect(func(_performance: Dictionary) -> void: _stop_reason = "cleared")
	_session._on_room_requested(room_node, region)
	_metrics["planned_enemies"] = room.encounter_runtime.total_enemy_count()
	_metrics["hp_start"] = _game.player.health
	_previous_position = _game.player.global_position
	var tick_count := roundi(_duration * 60.0)
	for tick in tick_count:
		_drive_input(float(tick) / 60.0, policy)
		await physics_frame
		await process_frame
		_elapsed = float(tick + 1) / 60.0
		_sample_pressure()
		if tick % 300 == 299:
			(_metrics["samples"] as Array).append(_live_snapshot())
		if _game.player.health <= 0:
			_stop_reason = "dead"
		if not _stop_reason.is_empty():
			break
	var result := _metrics.duplicate(true)
	result.merge(_live_snapshot(), true)
	result["stop_reason"] = "timeout" if _stop_reason.is_empty() else _stop_reason
	result["clear_seconds"] = _elapsed if _stop_reason == "cleared" else null
	result["captured_at_end"] = _game.player.captured
	if float(result["maximum_physics_delta"]) > 1.0 / 60.0 + 0.00001:
		_errors.append("%s/%s/%d exceeded 60 Hz delta" % [sample, policy, seed_value])
	print("PRESSURE seed=%d sample=%s policy=%s time=%.2f hp=%d->%d enemy_hp=%.1f/%0.1f kills=%d/%d weapon=%.1f return=%.1f captures=%d near=%d stop=%s" % [seed_value, sample, policy, _elapsed, result["hp_start"], result["hp_end"], result["enemy_hp_remaining"], result["spawned_enemy_hp"], result["defeated_enemies"], result["spawned_enemies"], result["weapon_damage"], result["return_damage"], result["captures"], result["peak_hostile_within_200px"], result["stop_reason"]])
	_session.world.deactivate()
	_game.player.set_play_enabled(false)
	_release_inputs()
	_game.queue_free()
	await process_frame
	await process_frame
	return result


func _choose_room(region: Dictionary, sample: StringName) -> Dictionary:
	var chosen: Dictionary = {}
	for node: Dictionary in region.get("nodes", []):
		var category := StringName(node.get("category", &""))
		if (sample == &"entry" and category == &"entry") or (sample == &"first_boss" and category == &"boss"):
			return node.duplicate(true)
		if sample == &"late_ordinary" and category not in [&"boss", &"elite"] and int(node.get("depth", 0)) > int(chosen.get("depth", -1)):
			chosen = node
	return chosen.duplicate(true)


func _drive_input(time: float, policy: StringName) -> void:
	var center := _session.world.room_runtime.room_bounds.get_center()
	var angle := PI * 0.5 + time * 0.20
	var target := center + Vector2(cos(angle) * 560.0, sin(angle) * 370.0)
	var offset := target - _game.player.global_position
	var input_vector := offset.normalized() * clampf(offset.length() / 65.0, 0.0, 1.0)
	Input.action_press(&"move_right", maxf(0.0, input_vector.x))
	Input.action_press(&"move_left", maxf(0.0, -input_vector.x))
	Input.action_press(&"move_down", maxf(0.0, input_vector.y))
	Input.action_press(&"move_up", maxf(0.0, -input_vector.y))
	var wants_fold := policy == &"fold_cycle" and fmod(time, 3.05) < 1.55
	if wants_fold != _fold_held:
		_fold_held = wants_fold
		var event := InputEventAction.new()
		event.action = &"fold"
		event.pressed = wants_fold
		event.strength = 1.0 if wants_fold else 0.0
		Input.parse_input_event(event)


func _release_inputs() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"fold"]:
		Input.action_release(action)
	_fold_held = false


func _on_enemy_spawned(actor: Node2D, _entry: Dictionary) -> void:
	var key := actor.get_instance_id()
	var record := {"actor": actor, "health": float(actor.get("health")), "attacked": false, "defeated": false}
	_actors[key] = record
	_metrics["spawned_enemies"] += 1
	_metrics["spawned_enemy_hp"] += record["health"]
	if actor is FoldlightRogueBossActor:
		actor.connect("damaged", func(amount: float, remaining: float, source: StringName) -> void: _record_damage(key, amount, remaining, source))
	else:
		actor.connect("damaged", func(amount: float, remaining: float) -> void: _record_damage(key, amount, remaining))
	actor.connect("defeated", func(_defeated_actor: Node2D) -> void:
		record["defeated"] = true
		_metrics["defeated_enemies"] += 1
		if not bool(record["attacked"]):
			_metrics["defeated_before_first_attack"] += 1
	)
	for signal_name in [&"attack_requested", &"volley_requested"]:
		if actor.has_signal(signal_name):
			actor.connect(signal_name, func(_snapshot: Dictionary) -> void:
				record["attacked"] = true
				_metrics["enemy_attack_events"] += 1
			)


func _on_projectile_spawned(projectile: FoldlightRogueProjectile) -> void:
	_projectiles.append(projectile)
	var kind := "hostile_shots" if projectile.hostile else ("return_shots" if projectile.style == &"return_light" else "weapon_shots")
	_metrics[kind] += 1


func _record_damage(key: int, _amount: float, remaining: float, explicit_source: StringName = &"") -> void:
	var record: Dictionary = _actors[key]
	var lost := maxf(0.0, float(record["health"]) - remaining)
	record["health"] = remaining
	_metrics["enemy_damage_events"] += 1
	var source := String(explicit_source)
	var actor_id := StringName((record["actor"] as Node2D).get("actor_id"))
	for projectile in _projectiles:
		if not is_instance_valid(projectile) or projectile.hostile or not projectile.hit_actor_ids.has(actor_id):
			continue
		var contact_key := "%d:%s" % [projectile.get_instance_id(), actor_id]
		if _claimed_hits.has(contact_key):
			continue
		_claimed_hits[contact_key] = true
		source = "return" if projectile.style == &"return_light" else "weapon"
		_metrics[source + "_hit_events"] += 1
		break
	if source not in ["weapon", "return"]:
		source = "other"
	_metrics[source + "_damage"] += lost


func _sample_pressure() -> void:
	var hostile := 0
	var near := 0
	for projectile in _combat.projectiles:
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion() or not projectile.hostile:
			continue
		hostile += 1
		if projectile.global_position.distance_to(_game.player.global_position) <= 200.0:
			near += 1
	_metrics["peak_hostile_shots"] = maxi(int(_metrics["peak_hostile_shots"]), hostile)
	_metrics["peak_hostile_within_200px"] = maxi(int(_metrics["peak_hostile_within_200px"]), near)
	_metrics["peak_live_enemies"] = maxi(int(_metrics["peak_live_enemies"]), _combat.enemies.size())
	_metrics["maximum_physics_delta"] = maxf(float(_metrics["maximum_physics_delta"]), _game.player.get_physics_process_delta_time())
	_metrics["distance_travelled"] += _previous_position.distance_to(_game.player.global_position)
	_previous_position = _game.player.global_position


func _live_snapshot() -> Dictionary:
	var remaining := 0.0
	var boss_hp: Variant = null
	for actor in _combat.enemies:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		remaining += maxf(0.0, float(actor.get("health")))
		if actor is FoldlightRogueBossActor:
			boss_hp = float(actor.get("health"))
	return {"seconds": _elapsed, "hp_end": _game.player.health, "enemy_hp_remaining": remaining, "boss_hp_remaining": boss_hp, "live_enemies": _combat.enemies.size(), "player_position": [_game.player.global_position.x, _game.player.global_position.y]}


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in SOURCE_FILES:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes
