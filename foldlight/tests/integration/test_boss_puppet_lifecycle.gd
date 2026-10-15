extends SceneTree

## Exercise the actual boss clock and production combat ownership. Presentation
## may observe the fight, but cannot shorten warnings, hold a dead actor alive,
## advance while paused, or leak a visual remnant into the next room.
const BOSS_SCENE: PackedScene = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
const Puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
const BOUNDS := Rect2(0, 0, 2880, 1620)
const STEP: float = 1.0 / 60.0
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	profile.set_setting(&"screen_shake", 1.0)
	for definition in FoldlightRogueContentCatalog.BOSSES:
		_test_actor_clock(definition)
	await process_frame
	await _test_runtime_remnant(false)
	await _test_runtime_remnant(true)
	_test_reduced_motion(profile)
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_BOSS_PUPPET_LIFECYCLE: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)


func _boss(definition: FoldlightRogueBossDefinition) -> FoldlightRogueBossActor:
	var actor := BOSS_SCENE.instantiate() as FoldlightRogueBossActor
	root.add_child(actor)
	actor.configure(definition, BOUNDS, 20261015)
	return actor


func _test_actor_clock(definition: FoldlightRogueBossDefinition) -> void:
	var actor := _boss(definition)
	var label := String(definition.content_id) + ": "
	var target := BOUNDS.get_center() + Vector2(0, 430)
	var collisions := actor.get_node("CollisionShape2D") as CollisionShape2D
	var shape := collisions.shape as CircleShape2D
	var volleys: Array[Dictionary] = []
	actor.volley_requested.connect(func(value: Dictionary) -> void: volleys.append(value.duplicate(true)))
	_check(is_equal_approx(shape.radius, 52.0) and actor.scale == Vector2.ONE and collisions.position == Vector2.ZERO, label + "paper model keeps the original physical hit circle")
	_check(actor.get_node_or_null("Aura") == null and actor.get_node_or_null("PhaseParticles") == null, label + "no independent TIME shader or particle clock runs behind pause")
	_check(is_zero_approx(float(actor.get_visual_pose()["intro"])), label + "entrance begins folded during the existing harmless introduction")
	for tick in 40:
		actor.advance_simulation(STEP, target)
	_check(float(actor.get_visual_pose()["intro"]) > 0.45 and float(actor.get_visual_pose()["intro"]) < 0.55 and volleys.is_empty(), label + "unfolding follows the original 1.35-second introduction")
	for tick in 90:
		if actor.phase_controller.state != FoldlightBossPhaseController.State.INTRO:
			break
		actor.advance_simulation(STEP, target)
	var original_direction := Vector2(actor.get_visual_pose()["direction"])
	var warned_origin := actor.global_position
	for tick in 30:
		actor.advance_simulation(STEP, target + Vector2(800, 0))
	var charged := actor.get_visual_pose()
	_check(float(charged["charge"]) > 0.4 and float(charged["charge"]) < 0.6 and volleys.is_empty(), label + "charge builds inside the actual warning, never fires early")
	_check(Vector2(charged["direction"]).is_equal_approx(original_direction) and actor.global_position.is_equal_approx(warned_origin), label + "visual charge shares the locked warning aim and stationary origin")
	var phase_before := actor.phase_controller.get_state_snapshot()
	var pose_before := actor.get_visual_pose()
	var arena_before := actor.arena_controller.get_rule_snapshot()
	actor.set_simulation_active(false)
	for tick in 120:
		actor.advance_simulation(STEP, target)
	_check(actor.get_visual_pose() == pose_before and actor.phase_controller.get_state_snapshot() == phase_before and actor.arena_controller.get_rule_snapshot() == arena_before, label + "pause freezes pose, warning and arena together")
	actor.set_simulation_active(true)
	for tick in 120:
		if not volleys.is_empty():
			break
		actor.advance_simulation(STEP, target + Vector2(800, 0))
	if volleys.is_empty():
		_check(false, label + "resumed warning reaches its real attack")
		actor.queue_free()
		return
	_check(float(actor.get_visual_pose()["recoil"]) > 0.99 and float(actor.get_visual_pose()["charge"]) == 0.0, label + "recoil begins only when the real attack fires")
	_check(Vector2(volleys[0]["direction"]).is_equal_approx(original_direction) and Vector2(volleys[0]["origin"]).is_equal_approx(warned_origin), label + "animation cannot redirect a released attack")
	for tick in 20:
		actor.advance_simulation(STEP, target)
	_check(is_zero_approx(float(actor.get_visual_pose()["recoil"])), label + "recoil resolves within its 0.30-second visual budget")
	actor.take_damage(30.0, &"return", Vector2.UP)
	for tick in 12:
		actor.advance_simulation(STEP, target)
	_check(actor.phase_controller.state == FoldlightBossPhaseController.State.STAGGERED and is_equal_approx(float(actor.get_visual_pose()["stagger"]), 1.0), label + "earned return-light break lowers the articulated model")
	actor.health = definition.base_health * 0.3
	actor.advance_simulation(STEP, target)
	_check(actor.phase_controller.phase_index == 0 and not bool(actor.get_visual_pose()["transition_active"]), label + "phase animation waits for the full earned break window")
	for tick in 300:
		if actor.phase_controller.state != FoldlightBossPhaseController.State.STAGGERED:
			break
		actor.advance_simulation(STEP, target)
	var transition := actor.get_visual_pose()
	_check(int(transition["phase"]) == 2 and bool(transition["transition_active"]) and is_zero_approx(float(transition["transition"])), label + "phase rearrangement starts with the original transition grace")
	var volley_count := volleys.size()
	for tick in 44:
		actor.advance_simulation(STEP, target)
	_check(float(actor.get_visual_pose()["transition"]) > 0.45 and float(actor.get_visual_pose()["transition"]) < 0.55 and volleys.size() == volley_count, label + "phase pose spans the full 1.5-second nonfiring transition")
	var rng_state := actor._rng.state
	var health_before := actor.health
	phase_before = actor.phase_controller.get_state_snapshot()
	for read in 30:
		Puppet.get_part_transforms(actor.actor_id, actor.get_visual_pose())
	_check(actor._rng.state == rng_state and actor.health == health_before and actor.phase_controller.get_state_snapshot() == phase_before, label + "repeated visual sampling consumes no RNG or simulation state")
	_check(actor.scale == Vector2.ONE and collisions.position == Vector2.ZERO and is_equal_approx(shape.radius, 52.0), label + "all animations leave collision transforms unchanged")
	actor.queue_free()


func _test_runtime_remnant(aftermath: bool) -> void:
	var room := (load("res://scenes/roguelite/room_runtime.tscn") as PackedScene).instantiate() as FoldlightRoomRuntime
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	var combat := FoldlightRogueCombatRuntime.new()
	root.add_child(room)
	root.add_child(player)
	root.add_child(combat)
	room.configure_room(&"boss_presentation", BOUNDS.size, [], FoldlightTheme.GOLD)
	player.configure_roguelite_combat(true)
	player.set_play_enabled(false)
	player.set_physics_process(false)
	combat.bind(room, player)
	combat.set_active(true)
	combat.set_physics_process(false)
	var actors := combat.spawn_directed_wave([{"boss_id": &"reef_crown_battery", "spawn_position": BOUNDS.get_center()}])
	var actor := actors[0] as FoldlightRogueBossActor
	var defeats: Array[StringName] = []
	combat.enemy_defeated.connect(func(id: StringName) -> void: defeats.append(id))
	var point := actor.global_position
	actor.take_damage(actor.health + 1.0, &"weapon", Vector2.UP)
	actor.take_damage(1000.0, &"weapon", Vector2.UP)
	var remnants := _remnants(room)
	_check(defeats.size() == 1 and not combat.enemies.has(actor) and actor.is_queued_for_deletion(), "death retires and scores the real actor immediately and exactly once")
	_check(remnants.size() == 1 and remnants[0].get_parent() == room and remnants[0].global_position.is_equal_approx(point), "death snapshot is one independent visual directly owned by the room")
	if remnants.is_empty():
		combat.queue_free()
		room.queue_free()
		player.queue_free()
		await process_frame
		return
	var remnant: Node2D = remnants[0]
	_check(remnant.get_child_count() == 0 and not remnant is CollisionObject2D and not remnant.has_method("take_damage"), "death paper has no hitbox, damage path, actor children or loot")
	if aftermath:
		combat.begin_boss_aftermath(point)
	else:
		combat.set_active(false)
	var frozen := _remnant_state(remnant)
	# Flush Node.queue_free at a frame boundary before checking object validity;
	# a timer can expire earlier within the very frame that queued the deletion.
	await process_frame
	await process_frame
	await create_timer(0.06).timeout
	_check(not is_instance_valid(actor) and _remnant_state(remnant) == frozen, "frozen visual outlives the freed actor without a stale reference or running clock")
	if aftermath:
		combat.advance_aftermath_feedback(0.40)
		_check(is_equal_approx(float(remnant.get_lifecycle_snapshot()["elapsed"]), 0.40) and not combat.active and combat.enemies.is_empty(), "aftermath advances only the death paper while combat remains suspended")
		for tick in 14:
			combat.advance_aftermath_feedback(0.10)
		_check(remnant.is_queued_for_deletion() and not remnant.visible, "paper death finishes before the existing 2.2-second explicit confirmation")
	else:
		combat.advance_aftermath_feedback(0.40)
		_check(_remnant_state(remnant) == frozen, "ordinary pause feedback cannot accidentally advance an endless death remnant")
		combat.set_active(true)
		combat.set_physics_process(false)
		await create_timer(0.06).timeout
		_check(float(remnant.get_lifecycle_snapshot()["elapsed"]) > 0.0, "endless resume lets the same death remnant continue naturally")
		combat.set_active(false)
		combat.clear_combat()
		_check(remnant.is_queued_for_deletion() and not remnant.visible, "changing rooms clears even a paused remnant immediately")
	await process_frame
	_check(_remnants(room).is_empty(), "no death paper survives its lifetime or room cleanup")
	combat.queue_free()
	room.queue_free()
	player.queue_free()
	await process_frame


func _test_reduced_motion(profile: FoldlightProfileManager) -> void:
	profile.set_setting(&"screen_shake", 0.0)
	var actor := _boss(FoldlightRogueContentCatalog.boss_by_id(&"origami_judge"))
	var first := actor.get_visual_pose()
	_check(float(first["motion_scale"]) == 0.0 and float(first["intro"]) == 1.0 and float(first["time"]) == 0.0, "reduced motion shows the full readable silhouette immediately")
	var base_transforms := Puppet.get_part_transforms(actor.actor_id, first)
	for tick in 100:
		actor.advance_simulation(STEP, BOUNDS.get_center() + Vector2(0, 430))
	actor.take_damage(30.0, &"return")
	for tick in 15:
		actor.advance_simulation(STEP, BOUNDS.get_center() + Vector2(0, 430))
	_check(Puppet.get_part_transforms(actor.actor_id, actor.get_visual_pose()) == base_transforms and float(actor.get_visual_pose()["stagger"]) == 1.0, "reduced motion removes paper displacement while preserving real break status for color cues")
	actor.take_damage(actor.health + 1.0)
	var remnants := _remnants(root)
	_check(remnants.size() == 1 and is_equal_approx(float(remnants[0].get_lifecycle_snapshot()["lifetime"]), 0.45), "reduced motion uses a short quiet death fade")
	for remnant: Node2D in remnants:
		remnant.set_simulation_active(false)
		remnant.advance_simulation(0.50)
		_check(remnant.is_queued_for_deletion(), "quiet death also cleans itself up")
	actor.queue_free()
	profile.set_setting(&"screen_shake", 1.0)


func _remnants(container: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child in container.get_children():
		if child.is_in_group(&"boss_remnants") and not child.is_queued_for_deletion():
			result.append(child as Node2D)
	return result


func _remnant_state(remnant: Node2D) -> Dictionary:
	var result: Dictionary = remnant.get_lifecycle_snapshot()
	# An already-queued initial paint may execute after pause; only simulation
	# state must freeze, not the render server's first submission counter.
	result.erase("draw_count")
	return result


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)
