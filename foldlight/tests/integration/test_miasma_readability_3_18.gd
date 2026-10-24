extends SceneTree

const Cloud = preload("res://scripts/roguelite/enemies/miasma_cloud.gd")
const Wraith = preload("res://scripts/roguelite/enemies/miasma_wraith.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	await _test_wraith()
	_test_cloud()
	_test_projectile_readability()
	_test_introductions()
	await _test_combat_ownership()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("FOLDLIGHT_MIASMA_READABILITY_3_18: " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_wraith() -> void:
	var definition := FoldlightRogueContentCatalog.enemy_by_id(&"miasma_wraith")
	_check(definition != null and definition.validation_errors().is_empty(), "poison carrier exists in the shared catalog with an introduction and counterplay")
	var actor := FoldlightRogueEnemyFactory.create(definition, &"readability_wraith") as Wraith
	_check(actor != null, "shared enemy factory creates the actual poison carrier")
	if actor == null:
		return
	root.add_child(actor)
	actor.position = Vector2(600, 500)
	await process_frame
	var events: Array[Dictionary] = []
	actor.poison_requested.connect(func(snapshot: Dictionary) -> void: events.append(snapshot))
	for index in 14:
		actor.advance_simulation(0.1, Vector2(1000, 500))
	_check(events.size() == 1 and StringName(events[0].get("source_id", &"")) == &"readability_wraith", "carrier emits one owned cloud after its spawn grace")
	_check(is_equal_approx(float(events[0].get("warning_duration", 0.0)), 0.85) and is_equal_approx(float(events[0].get("radius", 0.0)), 112.0), "new cloud advertises its warning and exact damage boundary")
	_check(is_equal_approx(float(events[0].get("duration", 0.0)), 60.0), "carrier emits the authored sixty-second toxic trail")
	var paused_clock := float(actor.get_combat_snapshot()["cloud_remaining"])
	actor.set_simulation_active(false)
	actor.advance_simulation(9.0, Vector2(1000, 500))
	_check(events.size() == 1 and is_equal_approx(paused_clock, float(actor.get_combat_snapshot()["cloud_remaining"])), "paused carrier cannot spawn or consume its next-cloud timer")
	actor.set_simulation_active(true)
	actor.advance_simulation(9.0, Vector2(1000, 500))
	_check(events.size() == 1 and float(actor.get_combat_snapshot()["cloud_remaining"]) > 2.0, "a stalled frame cannot create a backlog of clouds")
	actor.take_damage(999.0)
	for index in 30:
		actor.advance_simulation(0.1, Vector2(1000, 500))
	_check(events.size() == 1, "dead carrier never leaves post-mortem clouds")
	actor.queue_free()
	await process_frame


func _test_cloud() -> void:
	var cloud := Cloud.new()
	root.add_child(cloud)
	cloud.configure({"position": Vector2(450, 300), "source_id": &"cloud_owner"})
	_check(not cloud.is_processing() and not cloud.is_physics_processing(), "cloud has no independent timer that can escape combat pause")
	_check(not cloud.consume_damage_at(cloud.position), "cloud warning is harmless even at its centre")
	cloud.advance_simulation(12.0)
	_check(float(cloud.get_hazard_snapshot()["warning_remaining"]) >= 0.74, "stalled frame preserves a visible warning")
	cloud.set_simulation_active(false)
	var before_pause := cloud.get_hazard_snapshot()
	for index in 20:
		cloud.advance_simulation(0.1)
	_check(cloud.get_hazard_snapshot() == before_pause and not cloud.consume_damage_at(cloud.position), "paused warning and damage stay frozen")
	cloud.set_simulation_active(true)
	for index in 8:
		cloud.advance_simulation(0.1)
	_check(bool(cloud.get_hazard_snapshot()["dangerous"]), "cloud becomes harmful only after its warning")
	_check(not cloud.consume_damage_at(cloud.position + Vector2(112.01, 0)), "outside the drawn boundary remains safe")
	_check(cloud.consume_damage_at(cloud.position + Vector2(111.99, 0)), "inside the boundary causes exactly one damage opportunity")
	_check(not cloud.consume_damage_at(cloud.position), "same cloud cannot damage again in the same frame")
	for index in 15:
		cloud.advance_simulation(0.1)
	_check(not cloud.consume_damage_at(cloud.position), "cloud retains its authored damage cooldown")
	cloud.advance_simulation(0.1)
	_check(cloud.consume_damage_at(cloud.position), "standing in the cloud permits the next tick after 1.6 seconds")
	cloud.set_simulation_active(false)
	_check(not cloud.consume_damage_at(cloud.position), "active poison cannot damage during paused or reward phases")
	cloud.set_simulation_active(true)
	for index in 60:
		cloud.advance_simulation(0.1)
	_check(not bool(cloud.get_hazard_snapshot()["expired"]), "poison remains after the former short-lived cloud would disappear")
	for index in 600:
		cloud.advance_simulation(0.1)
	_check(bool(cloud.get_hazard_snapshot()["expired"]) and not cloud.consume_damage_at(cloud.position), "expired poison never retains an invisible damage area")
	_check(is_equal_approx(float(cloud.get_hazard_snapshot()["fill_alpha"]), 0.12) and float(cloud.get_hazard_snapshot()["outline_alpha"]) >= 0.85, "poison uses quiet fill and a persistent legible boundary")
	cloud.queue_free()


func _test_projectile_readability() -> void:
	var snapshot := {"origin": Vector2(100, 100), "velocity": Vector2(230, 120), "radius": 9.0, "damage": 3.0, "hostile": true, "style": &"hostile_petal", "lifetime": 8.0, "curve": 0.45, "color": Color.MAGENTA}
	var normal := FoldlightRogueProjectile.new()
	var reduced := FoldlightRogueProjectile.new()
	root.add_child(normal)
	root.add_child(reduced)
	normal.configure(snapshot)
	reduced.configure(snapshot)
	normal.set_visual_preferences(false, false)
	reduced.set_visual_preferences(true, true)
	for index in 120:
		normal.advance_simulation(1.0 / 60.0, 0.7)
		reduced.advance_simulation(1.0 / 60.0, 0.7)
	_check(normal.position.is_equal_approx(reduced.position) and normal.velocity.is_equal_approx(reduced.velocity), "reduced motion and high contrast retain identical curved bullet paths")
	_check(normal.radius == reduced.radius and normal.damage == reduced.damage and normal.lifetime == reduced.lifetime and normal.reflectable == reduced.reflectable, "visual options do not change hitbox, damage, lifetime or capture eligibility")
	_check(is_equal_approx(normal.rotation, normal.velocity.angle()), "hostile outline points along actual travel without a cosmetic wobble")
	var hostile_ink: Color = normal.get_readability_snapshot()["color"]
	_check(hostile_ink.s < 0.40 and hostile_ink.a >= 0.95, "arbitrary neon source colors become a stable low-saturation but opaque threat color")
	_check(bool(normal.get_readability_snapshot()["has_dark_outline"]) and not bool(normal.get_readability_snapshot()["halo"]), "hostile core keeps separation from scenery without luminous haze")
	var friendly := FoldlightRogueProjectile.new()
	root.add_child(friendly)
	friendly.configure({"hostile": false, "style": &"prism_fan", "color": Color.MAGENTA})
	var friendly_ink: Color = friendly.get_readability_snapshot()["color"]
	_check(friendly_ink.g > friendly_ink.r and hostile_ink.r > hostile_ink.g and normal.z_index > friendly.z_index, "cool friendly shots stay visually behind warm hostile shots")
	friendly.configure({"hostile": false, "style": &"return_light", "velocity": Vector2(800, 0)})
	friendly.set_visual_preferences(false, false)
	var trajectory := friendly.get_readability_snapshot()
	_check(float(trajectory["maximum_trail_distance"]) <= 48.0 and float(trajectory["maximum_trail_alpha"]) <= 0.28 and int(trajectory["extra_trail_threads"]) == 0, "returned light no longer draws long bright doubled ribbons")
	friendly.set_visual_preferences(true, false)
	_check(is_zero_approx(float(friendly.get_readability_snapshot()["maximum_trail_distance"])) and not bool(friendly.get_visual_contract()["trajectory_animated"]), "reduced motion removes decorative return trails while retaining the projectile")
	normal.queue_free()
	reduced.queue_free()
	friendly.queue_free()


func _test_combat_ownership() -> void:
	var world := load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame

	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	player.set_physics_process(false)
	world.load_room(player, &"miasma_ownership", Vector2(2880, 1620), [], Color.WHITE, 318)
	world.activate()
	world.set_physics_process(false)
	var combat := world.combat_runtime
	combat.set_physics_process(false)
	combat.set_process(false)
	player.global_position = Vector2(700, 800)
	var first := combat._spawn_enemy_from_entry({"enemy_id": &"miasma_wraith", "spawn_position": Vector2(1800, 800)}, false) as Wraith
	var second := combat._spawn_enemy_from_entry({"enemy_id": &"miasma_wraith", "spawn_position": Vector2(2000, 800)}, false) as Wraith
	first.poison_requested.emit({"position": player.global_position, "source_id": second.actor_id})
	_check(combat.get_poison_snapshot().size() == 1 and StringName(combat.get_poison_snapshot()[0]["source_id"]) == first.actor_id, "real actor signal binds cloud ownership and ignores a spoofed payload owner")
	first.poison_requested.emit({"position": player.global_position + Vector2(20, 0)})
	_check(combat.get_poison_snapshot().size() == 1, "stationary or trapped carriers cannot stack overlapping own clouds")
	var initial_health := player.health
	player.invulnerability = 0.0
	combat._update_poison_damage()
	_check(player.health == initial_health, "shared combat damage respects cloud warning")
	combat.set_active(false)
	var paused := combat.get_poison_snapshot()
	combat._process(3.0)
	combat._update_poison_damage()
	_check(combat.get_poison_snapshot() == paused and player.health == initial_health, "combat pause freezes both poison visual clock and damage")
	combat.set_active(true)
	for index in 9:
		combat._process(0.1)
	combat._update_poison_damage()
	_check(player.health == initial_health - 1, "poison uses shared player damage for one heart after the complete warning")
	combat._update_poison_damage()
	_check(player.health == initial_health - 1, "multiple damage checks cannot duplicate the first poison tick")
	combat.effect_suspension_guard = func() -> bool: return true
	var guarded := combat.get_poison_snapshot()
	for index in 20:
		combat._process(0.1)
	player.invulnerability = 0.0
	combat._update_poison_damage()
	_check(combat.get_poison_snapshot() == guarded and player.health == initial_health - 1, "rotation or reward suspension freezes poison even while the runtime remains active")
	combat.effect_suspension_guard = Callable()
	for index in 22:
		first.poison_requested.emit({"position": Vector2(200 + index * 120, 300)})
	_check(combat.get_poison_snapshot().size() == 23, "one moving carrier leaves a visible lasting trail")
	second.poison_requested.emit({"position": Vector2(1900, 300)})
	_check(combat.get_poison_snapshot().size() == 24, "a second carrier reaches the bounded twenty-four cloud budget")
	var full_trail := combat.get_poison_snapshot()
	second.poison_requested.emit({"position": Vector2(2500, 1200)})
	_check(combat.get_poison_snapshot() == full_trail, "budget saturation skips a new cloud instead of erasing the persistent old trail")
	first.take_damage(999.0)
	_check(combat.get_poison_snapshot() == full_trail, "killing a carrier stops new poison but does not erase its existing trail")
	first.poison_requested.emit({"position": Vector2(1400, 1100)})
	_check(combat.get_poison_snapshot() == full_trail, "a stale signal from a dead carrier cannot create more poison")
	_check(combat.retire_directed_enemy(second) and combat.get_poison_snapshot() == full_trail, "distance recycling preserves the already visible hazard without kill credit")
	combat.clear_combat()
	_check(combat.get_poison_snapshot().is_empty(), "room teardown clears every lingering trail including trails whose sources are gone")
	world.queue_free()
	player.queue_free()
	await process_frame


func _test_introductions() -> void:
	var tracker := FoldlightMechanicIntroductionTracker.new()
	root.add_child(tracker)
	var miasma := tracker.request_introduction(FoldlightRogueContentCatalog.enemy_by_id(&"miasma_wraith"))
	_check(StringName(miasma.get("attack_style", &"")) == &"poison_trail" and str(miasma.get("counterplay", "")).contains("绕行") and str(miasma.get("rule", "")).contains("60"), "poison introduction teaches persistence after death and visible routes around the trail")
	for content_id in [&"tide_loom_mother", &"torn_page_executioner"]:
		var boss := FoldlightRogueContentCatalog.boss_by_id(content_id)
		var intro := tracker.request_boss_introduction(boss)
		var expected := &"command_swarm" if content_id == &"tide_loom_mother" else &"relentless_charge"
		_check(StringName(intro.get("attack_style", &"")) == expected, "%s teaches its actual 3.18 signature" % content_id)
		_check(str(intro.get("rule", "")).length() <= 60 and str(intro.get("counterplay", "")).length() <= 60, "%s keeps each mobile instruction brief" % content_id)
		_check(tracker.request_boss_introduction(boss).is_empty(), "%s introduction remains once per run" % content_id)
	tracker.queue_free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	print(("[PASS] " if condition else "[FAIL] ") + message)
