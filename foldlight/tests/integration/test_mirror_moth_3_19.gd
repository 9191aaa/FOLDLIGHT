extends SceneTree

const MIRROR = preload("res://scenes/roguelite/bosses/mirror_moth_actor.tscn")
const DEFINITION = preload("res://resources/roguelite/bosses/mirror_moth.tres")
const STEP: float = 1.0 / 60.0
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	await _test_copy_and_arsenal()
	await _test_observed_release_and_receipts()
	await _test_skills_and_lifecycle()
	await _test_dash_and_pose()
	await _test_mirror_lifecycle()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_MIRROR_MOTH_3_19: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _build(weapons: bool = true) -> Dictionary:
	var mount := FoldlightWeaponMount.new()
	root.add_child(mount)
	var stats := {"weapon_damage_multiplier": 2.4, "weapon_interval_multiplier": 0.72, "projectile_speed_multiplier": 1.15, "dash_blast_level": 3}
	mount.configure_build(stats)
	var shots: Array[Dictionary] = []
	var levels := {}
	if weapons:
		for id: StringName in FoldlightMirrorMothActor.WEAPON_IDS:
			var definition := FoldlightRogueContentCatalog.weapon_by_id(id)
			mount.equip(definition, 5)
			shots.append(mount.make_shot_snapshot(definition))
			levels[String(id)] = 5
	mount.queue_free()
	return {"weapons": shots, "weapon_levels": levels, "build_stats": stats, "max_health": 4,
		"move_speed": 516.0, "fold_move_speed": 260.0, "dash_speed": 1300.0, "dash_duration": 0.26, "dash_cooldown": 1.6,
		"capture_capacity": 32, "capture_radius_max": 400.0, "capture_radius_min": 140.0, "capture_charge_time": 1.3, "capture_cooldown": 0.6,
		"active_item_id": &"", "owned_active_items": [&"paper_burst", &"ink_wash"], "active_cooldown": 18.0,
		"provenance": {"kind": "actual_player_build", "version": "3.19.0", "seed": 319}}


func _actor(build: Dictionary) -> FoldlightMirrorMothActor:
	var actor := MIRROR.instantiate() as FoldlightMirrorMothActor
	root.add_child(actor)
	actor.configure(DEFINITION, Rect2(0,0,6400,4000), 319, {"arena_pressure": false, "endless_roam": true})
	actor.position = Vector2(3000,2000)
	actor.configure_mirror_build(build)
	return actor


func _live(actor: FoldlightMirrorMothActor) -> void:
	actor.phase_controller.state = FoldlightBossPhaseController.State.ATTACK
	actor.phase_controller.current_pattern = &"mirror_pressure"
	actor.phase_controller._remaining = 100.0
	actor.phase_controller._transition_remaining = 0.0


func _test_copy_and_arsenal() -> void:
	var build := _build()
	var actor := _actor(build)
	var state := actor.get_mirror_snapshot()
	_check(state.weapons == build.weapons and state.build.weapon_levels == build.weapon_levels, "copies all six actual weapon snapshots and levels without substituting a generic volley")
	_check(actor.maximum_health == 640.0 and state.health_per_copied_heart == 160.0, "copies four-heart maximum using an explicit boss HP conversion")
	build.weapons[0]["damage"] = 9999.0
	build.build_stats["weapon_interval_multiplier"] = 0.01
	state.build["max_health"] = 99
	_check(actor.get_mirror_snapshot().weapons[0].damage != 9999.0 and actor.get_mirror_snapshot().build.max_health == 4, "birth snapshot and exposed inspection snapshot are both isolated deep copies")
	actor.configure_mirror_build({"max_health": 40})
	_check(actor.maximum_health == 640.0, "a repeated configure call cannot heal or rewrite a live mirror")
	_live(actor)
	var events: Array[Dictionary] = []
	actor.volley_requested.connect(func(event: Dictionary) -> void: events.append(event))
	for weapon: Dictionary in actor._mirror_weapons:
		actor._emit_mirror_weapon(weapon)
	var patterns: Dictionary = {}
	for event: Dictionary in events: patterns[StringName(event.weapon_id)] = event
	_check(patterns.size() == 6, "each actually equipped weapon emits its own attack")
	_check(float(patterns[&"crease_lantern"].projectiles[0].homing_duration) == 1.15 and float(patterns[&"crease_lantern"].projectiles[1].homing_duration) == 0.0, "fold lantern aimed beam tracks for a finite duration while bonus lanes remain separate")
	_check(float(patterns[&"needle_orbit"].projectiles[0].launch_delay) == 0.65 and patterns[&"needle_orbit"].projectiles[0].orbit_anchor == actor, "level-five orbit needles have a real orbit anchor and delayed launch")
	_check(patterns[&"returning_gull"].projectiles.size() == 2 and patterns[&"returning_gull"].projectiles[0].return_anchor == actor and float(patterns[&"returning_gull"].projectiles[0].return_damage_multiplier) == 1.35, "gulls preserve twin volley, measured turnaround and enhanced return metadata")
	_check(float(patterns[&"tide_bell"].projectiles[0].area_radius) == 187.5, "level-five bell copies the actual larger blast radius")
	_check(patterns[&"prism_fan"].projectiles.size() == 5 and float(patterns[&"prism_fan"].projectiles[0].lifetime) == 0.64, "fan retains five separate short-range rays")
	_check(int(patterns[&"sun_thread"].projectiles[0].pierce) == 4 and float(patterns[&"sun_thread"].projectiles[0].speed) > 1300.0, "sun thread copies upgraded pierce and actual boosted projectile speed")
	var all_hearts := true
	for event: Dictionary in events:
		for shot: Dictionary in event.projectiles: all_hearts = all_hearts and shot.damage == 1.0 and shot.copied_damage > 0.0
	_check(all_hearts, "copied combat power is inspectable while all hostile hits map to one player heart")
	events.clear()
	actor.sync_mirror_input(true)
	for weapon: Dictionary in actor._mirror_weapons: actor._weapon_timers[StringName(weapon.weapon_id)] = 0.0
	actor.advance_simulation(STEP, actor.position + Vector2(100,0))
	_check(events.size() == 6 and not actor.get_mirror_snapshot().folding, "holding player fold leaves the complete copied six-weapon arsenal firing on its own timers")
	actor.queue_free()
	await process_frame


func _test_observed_release_and_receipts() -> void:
	var actor := _actor(_build(false))
	actor.sync_mirror_input(true)
	_check(not actor.observe_player_release(8, 1) and not actor.can_capture_projectile({"position": actor.position, "hostile": false}), "intro ignores release events and cannot silently consume friendly projectiles")
	_live(actor)
	actor._target_position = actor.position + Vector2(300,0)
	actor.sync_mirror_input(true)
	_check(not actor.get_mirror_snapshot().folding and actor.get_mirror_capture_radius() == 0.0 and not actor.capture_projectile({"position": actor.position}), "holding player fold never opens a mirror collector or intercepts a friendly shot")
	var volleys: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	actor.volley_requested.connect(func(event: Dictionary) -> void: volleys.append(event))
	actor.telegraph_requested.connect(func(event: Dictionary) -> void: warnings.append(event))
	_check(actor.observe_player_release(32, 10) and actor.observe_player_release(5, 11), "each actual player release queues its own exact return count")
	_check(not actor.observe_player_release(32, 10) and not actor.observe_player_release(5, 11) and not actor.observe_player_release(1, 9), "duplicate and older event serials cannot replay returned ammunition")
	_check(not actor.observe_player_release(0, 12) and not actor.observe_player_release(97, 12), "empty and invalid counts cannot create a return volley")
	_check(actor.observe_player_release(96, 12) and actor.get_mirror_snapshot().pending_release_events.size() == 2, "a later real 96-shot release stays exact even when the birth snapshot capacity was 32")
	_check(warnings.size() == 1 and warnings[0].duration == 0.8 and warnings[0].projectile_count == 32 and actor.get_mirror_snapshot().release_count == 32, "first FIFO event gives a clearly counted full 0.8-second warning")
	actor.sync_mirror_input(false)
	for tick in 47: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(volleys.is_empty() and actor.get_mirror_snapshot().release_remaining > 0.0, "no projectile is requested during the first 47 simulation ticks of the warning")
	actor.set_simulation_active(false)
	var frozen := actor.get_mirror_snapshot()
	actor.sync_mirror_input(true)
	actor.advance_simulation(3.0, Vector2.ZERO)
	_check(not actor.observe_player_release(7, 13) and frozen == actor.get_mirror_snapshot(), "pause freezes queued releases, copied skills and all weapon timers")
	actor.set_simulation_active(true)
	for tick in 2: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(volleys.size() == 1 and volleys[0].projectile_count == 18 and actor.get_mirror_snapshot().return_queue_count == 32, "requesting a bounded first batch does not consume unacknowledged ammunition")
	var first_request := int(volleys[0].mirror_return_request_id)
	for tick in 30: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(volleys.size() == 1 and actor.get_mirror_snapshot().return_queue_count == 32, "missing runtime acknowledgement never repeats or silently discards a batch")
	_check(not actor.acknowledge_mirror_return(first_request + 1, 18) and not actor.acknowledge_mirror_return(first_request, 19), "unknown receipts and oversized successful counts are rejected")
	_check(actor.acknowledge_mirror_return(first_request, 0), "full global projectile budget acknowledges zero actual spawns")
	for tick in 6: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(volleys.size() == 2 and actor.get_mirror_snapshot().return_queue_count == 32 and volleys[1].projectiles == volleys[0].projectiles, "budget exhaustion retries the same intact prefix after the retry interval")
	var second_request := int(volleys[1].mirror_return_request_id)
	_check(actor.acknowledge_mirror_return(second_request, 7) and actor.get_mirror_snapshot().return_queue_count == 25 and not actor.acknowledge_mirror_return(second_request, 7), "partial receipt consumes only seven real spawns and duplicate receipt cannot consume again")
	var returned_by_event := {10: 7, 11: 0, 12: 0}
	var indexes: Array[String] = []
	for index in 7: indexes.append("10:%d" % index)
	var acknowledged := 2
	var bounded := true
	for tick in 240:
		actor.advance_simulation(STEP, actor.position + Vector2(300,0))
		while acknowledged < volleys.size():
			var event: Dictionary = volleys[acknowledged]
			acknowledged += 1
			var serial := int(event.mirror_release_serial)
			bounded = bounded and event.projectiles.size() <= 18
			for shot: Dictionary in event.projectiles:
				indexes.append("%d:%d" % [serial, int(shot.mirror_release_index)])
				bounded = bounded and shot.echo_chance == 0.0 and shot.homing_duration == 1.4
			returned_by_event[serial] = int(returned_by_event[serial]) + event.projectiles.size()
			actor.acknowledge_mirror_return(int(event.mirror_return_request_id), event.projectiles.size())
	var unique_indexes := {}
	for key: String in indexes: unique_indexes[key] = true
	_check(returned_by_event == {10: 32, 11: 5, 12: 96} and unique_indexes.size() == 133 and indexes.size() == 133 and bounded, "FIFO returns all 133 actual shots once across independent 32/5/96 events, partial receipts and bounded chunks")
	_check(warnings.size() == 3 and warnings[1].projectile_count == 5 and warnings[2].projectile_count == 96 and warnings[1].duration == 0.8 and warnings[2].duration == 0.8, "every queued release retains its own full counted warning")
	_check(actor.get_mirror_snapshot().return_queue_count == 0 and actor.get_mirror_snapshot().pending_release_events.is_empty() and actor.get_mirror_snapshot().release_count == 0, "successful receipts leave no invented or permanently stuck pending ammunition")
	actor.observe_player_release(8, 13)
	actor.observe_player_release(6, 14)
	for tick in 49: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	var stale_request := int(volleys[-1].mirror_return_request_id)
	actor.phase_controller.enter_stagger(2.0)
	_check(actor.get_mirror_snapshot().return_queue_count == 0 and actor.get_mirror_snapshot().release_remaining == 0.0 and actor.get_mirror_snapshot().pending_release_events.is_empty(), "earned return stagger cancels both the active volley and queued events synchronously")
	_check(not actor.acknowledge_mirror_return(stale_request, 8), "receipt from an interrupted return cannot revive or consume a later volley")
	_live(actor)
	_check(not actor.observe_player_release(6, 14), "stagger cancellation retains the monotonic event guard against replay")
	actor.queue_free()
	await process_frame


func _test_skills_and_lifecycle() -> void:
	for skill_id: StringName in [&"paper_burst", &"mirror_step", &"ink_wash", &"crease_anchor", &"tide_clock", &"sun_stamp"]:
		var build := _build(false)
		build["active_item_id"] = skill_id
		build["active_cooldown_remaining"] = 0.0
		var actor := _actor(build)
		_live(actor)
		actor.health = actor.maximum_health * 0.8
		var events: Array[Dictionary] = []
		actor.mirror_action_requested.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
		var locked := actor.position + Vector2(300,0)
		actor.advance_simulation(STEP, locked)
		_check(events.size() == 1 and events[0].stage == &"warning" and events[0].skill_id == skill_id, "%s starts an explicit warning before its copied skill" % skill_id)
		for tick in 42: actor.advance_simulation(STEP, actor.position + Vector2(-300,0))
		_check(events.size() == 2 and events[1].stage == &"resolve" and events[1].target_position == locked and events[1].serial == events[0].serial, "%s resolves once at its originally warned target" % skill_id)
		match skill_id:
			&"ink_wash": _check(actor.health == actor.maximum_health, "healing skill restores copied heart-equivalent health without exceeding maximum")
			&"crease_anchor":
				var health_before := actor.health
				for index in 4: actor.take_damage(10.0)
				actor.take_damage(10.0)
				_check(actor.health == health_before - 10.0, "anchor blocks exactly four real hits before breaking")
			&"sun_stamp": _check(actor.get_mirror_snapshot().overdrive_remaining > 5.0, "sun stamp gives its six-second actual cadence buff")
			&"mirror_step": _check(actor.get_mirror_snapshot().invulnerability > 0.0 and actor.get_mirror_snapshot().dash_cooldown == 0.0, "mirror step restores dash and grants its actual one-second immunity")
		actor._active_remaining = 0.0
		actor._begin_active()
		var spent := actor._active_remaining
		actor.phase_controller.enter_stagger(1.0)
		_check(events[-1].stage == &"cancel" and actor._active_remaining == spent and actor._active_pending.is_empty(), "%s interruption cancels the pending effect without refunding cooldown" % skill_id)
		actor.queue_free()
		await process_frame


func _test_dash_and_pose() -> void:
	var actor := _actor(_build(false))
	_live(actor)
	actor._target_position = actor.position + Vector2(600,0)
	var events: Array[Dictionary] = []
	actor.mirror_action_requested.connect(func(event: Dictionary) -> void: events.append(event))
	actor._on_telegraph_started(&"mirror_dash", 0.7)
	actor._on_attack_ready(&"mirror_dash", 0.7)
	_check(actor._mirror_dash_remaining == 0.26 and actor._mirror_dash_cooldown == 1.6, "mirror uses copied dash duration and cooldown")
	actor._update_movement(STEP)
	_check(is_equal_approx(actor.velocity.length(),1300.0), "mirror uses copied physical dash speed")
	actor._mirror_dash_path = PackedVector2Array([actor.position, actor.position + Vector2(338,0)])
	actor._emit_dash_blast()
	_check(events[-1].action == &"dash_blast" and events[-1].level == 3 and events[-1].path.size() == 2, "copied dash explosion provides the actual path and actual upgrade level")
	var puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
	var open := actor.get_visual_pose()
	open["motion_scale"] = 0.0
	actor.sync_mirror_input(true)
	var held := actor.get_visual_pose()
	held["motion_scale"] = 0.0
	_check(puppet.get_part_transforms(&"mirror_moth",open) == puppet.get_part_transforms(&"mirror_moth",held) and not held.mirror_folding, "holding player fold never changes the mirror into an active collector silhouette")
	_check(puppet.get_visual_contract(&"mirror_moth").part_count == 6, "mirror moth uses six cached articulated paper parts")
	actor.queue_free()
	await process_frame


func _check(value: bool, label: String) -> void:
	checks += 1
	print(("[PASS] " if value else "[FAIL] ") + label)
	if not value: failures.append(label)


func _test_mirror_lifecycle() -> void:
	var build := _build(false)
	build["dash_charges"] = 3
	build["body_size_multiplier"] = 0.75
	var actor := _actor(build)
	var events: Array[Dictionary] = []
	actor.volley_requested.connect(func(event: Dictionary) -> void: events.append(event))
	var radius := (actor.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	_check(is_equal_approx(radius.radius, 25.5) and actor.get_mirror_snapshot().dash_charges == 3, "copied body size and all three dash charges reach actual combat components")
	for tick in 40: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(float(actor.get_visual_pose().intro) > 0.45 and float(actor.get_visual_pose().intro) < 0.55 and events.is_empty(), "mirror intro unfolds over the shared harmless 1.35-second clock")
	var before := actor.health
	actor.take_damage(10000.0)
	_check(actor.health == before, "intro cannot be damaged before the copied encounter is ready")
	_live(actor)
	actor.observe_player_release(8, 30)
	actor.observe_player_release(5, 31)
	for tick in 49: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	var phase_request := int(actor.get_mirror_snapshot().return_pending_request)
	actor.health = actor.maximum_health * 0.3
	actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(actor.phase_controller.phase_index == 2 and actor._release_remaining == 0.0 and actor._return_queue.is_empty() and actor._release_events.is_empty(), "mirror phase change cancels active and queued returns before crossing into the new phase")
	_check(phase_request > 0 and not actor.acknowledge_mirror_return(phase_request, 8) and actor.get_mirror_snapshot().last_release_serial == 31, "phase cancellation invalidates outstanding receipts while retaining event deduplication")
	actor.phase_controller._transition_remaining = 0.0
	_live(actor)
	actor.observe_player_release(7, 32)
	for tick in 49: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	var death_request := int(actor.get_mirror_snapshot().return_pending_request)
	actor.take_damage(actor.maximum_health * 2.0)
	_check(actor.health <= 0.0 and actor.phase_controller.state == FoldlightBossPhaseController.State.DEFEATED and actor._death_remnant_spawned, "real mirror death enters shared defeat and creates its articulated remnant")
	_check(not actor.observe_player_release(5, 33) and not actor.acknowledge_mirror_return(death_request, 7) and actor._return_queue.is_empty(), "dead mirror rejects release events and late receipts after clearing pending ammunition")
	actor.configure(DEFINITION, Rect2(0,0,6400,4000), 320, {"arena_pressure":false})
	var fresh := _build(false)
	fresh["max_health"] = 6
	actor.configure_mirror_build(fresh)
	_check(actor.maximum_health == 960.0 and actor._return_queue.is_empty() and actor._release_events.is_empty() and actor._last_release_serial == 0 and actor._active_pending.is_empty() and actor._mirror_dash_maximum == 1 and not actor._death_remnant_spawned, "full run reconfigure clears old identity, queued events and copied charges before a fresh birth snapshot")
	_live(actor)
	actor.observe_player_release(3, 1)
	for tick in 49: actor.advance_simulation(STEP, actor.position + Vector2(300,0))
	_check(actor.get_mirror_snapshot().return_pending_request > death_request and not actor.acknowledge_mirror_return(death_request, 3) and actor.get_mirror_snapshot().return_queue_count == 3, "request IDs remain unique across reconfigure so an old run cannot acknowledge new ammunition")
	actor.queue_free()
	await process_frame
