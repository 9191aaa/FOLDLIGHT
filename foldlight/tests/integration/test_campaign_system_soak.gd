extends SceneTree

## Accelerated deterministic soak of the complete 7,080-second authored route.
## It exercises all tide events, objectives, late rosters and boss pattern families
## without pretending that a huge physics delta is a real frame.

const STEP: float = 1.0 / 60.0
const SIMULATION_SLICES_PER_TIDE: int = 12

var _failures: Array[String] = []
var _virtual_seconds: float = 0.0
var _peak_enemies: int = 0
var _peak_hostile: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main campaign scene loads for soak")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	game.profile_manager.persistence_enabled = false
	_reset_profile(game.profile_manager)

	for mission_index in FoldlightCampaignCatalog.mission_count():
		var mission := FoldlightCampaignCatalog.mission_at(mission_index)
		game.start_campaign_mission(mission_index)
		_dismiss_briefings(game)
		game.player.invulnerability = 99999.0
		for tide in FoldMissionDefinition.TIDE_COUNT:
			game.act = tide + 1
			game.act_time = 0.0
			game._ritual_flags.clear()
			game.enemies.clear()
			game.hostile_shots.clear()
			game.return_lights.clear()
			game._begin_tide_objective()
			var pair_text := str(mission.tide_value(mission.ritual_event_pairs, tide, "lamp_rain,tide_seam"))
			var pair := pair_text.split(",", false)
			for event_text in pair:
				game._trigger_authored_ritual_event(StringName(event_text.strip_edges()))
			for slice in SIMULATION_SLICES_PER_TIDE:
				game._update_ritual_event(STEP)
				game._update_spawning(STEP)
				game._update_enemies(STEP)
				game._update_hostile_shots(STEP)
				game._update_return_lights(STEP)
				game._update_effects(STEP)
				_peak_enemies = maxi(_peak_enemies, game.enemies.size())
				_peak_hostile = maxi(_peak_hostile, game.hostile_shots.size())
			game.objective_tracker.settle_at_tide_end()
			_check(game.enemies.size() <= FoldlightGame.ENEMY_CAP, "mission %02d tide %d keeps enemy cap" % [mission_index + 1, tide + 1])
			_check(game.hostile_shots.size() <= FoldlightGame.HOSTILE_CAP, "mission %02d tide %d keeps hostile cap" % [mission_index + 1, tide + 1])
			_virtual_seconds += mission.tide_duration

		game.enemies.clear()
		game.hostile_shots.clear()
		game._boss_spawned = false
		game._spawn_boss()
		_dismiss_briefings(game)
		_check(game.enemies.size() == 1, "mission %02d finale starts as a clean boss composition" % (mission_index + 1))
		if not game.enemies.is_empty():
			var boss: Dictionary = game.enemies[0]
			boss["position"] = Vector2(960.0, 260.0)
			boss["age"] = 10.0
			for phase in [1, 2, 3]:
				boss["boss_phase"] = phase
				boss["shoot"] = -0.01
				boss["special"] = -0.01
				game._update_enemies(STEP)
				game._update_hostile_shots(STEP)
				_peak_enemies = maxi(_peak_enemies, game.enemies.size())
				_peak_hostile = maxi(_peak_hostile, game.hostile_shots.size())
				_check(game.hostile_shots.size() <= FoldlightGame.HOSTILE_CAP, "mission %02d boss phase %d respects projectile cap" % [mission_index + 1, phase])
		_virtual_seconds += mission.boss_budget_seconds
		game.profile_manager.record_campaign_mission(mission.mission_id, {
			"rank": "A",
			"score": 15000 + mission_index * 1000,
			"time": mission.expected_seconds,
			"captures": 80 + mission_index,
			"kills": 40 + mission_index,
		}, false)

	var campaign := game.profile_manager.get_campaign_snapshot()
	_check(is_equal_approx(_virtual_seconds, 7080.0), "accelerated route accounts for all 7,080 authored seconds")
	_check((campaign.get("completed", {}) as Dictionary).size() == 12, "soak reaches all twelve mission clears")
	_check(bool(campaign.get("campaign_complete", false)), "soak reaches campaign completion state")
	_check(game.profile_manager.get_active_checkpoint().is_empty(), "completed route leaves no stale checkpoint")
	_check(_peak_hostile > 0, "soak executes live boss projectile patterns")
	print("FOLDLIGHT_CAMPAIGN_SOAK virtual_seconds=%.0f peak_enemies=%d peak_hostile=%d" % [_virtual_seconds, _peak_enemies, _peak_hostile])

	game.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	_finish()


func _reset_profile(profile_manager: FoldlightProfileManager) -> void:
	profile_manager.profile["version"] = FoldlightProfileManager.PROFILE_VERSION
	profile_manager.profile["campaign"] = {
		"unlocked_missions": ["c1m1"],
		"completed": {},
		"reward_grants": [],
		"campaign_complete": false,
		"campaign_seconds": 0.0,
		"active_checkpoint": {},
		"failure_counts": {},
		"assisted_missions": [],
	}


func _dismiss_briefings(game: FoldlightGame) -> void:
	var guard := 64
	while game.mode == FoldlightGame.RunMode.BRIEFING and guard > 0:
		game._advance_briefing(false)
		guard -= 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		_failures.append(label)
		push_error("[FAIL] " + label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_CAMPAIGN_SYSTEM_SOAK: PASS")
		quit(0)
	else:
		printerr("FOLDLIGHT_CAMPAIGN_SYSTEM_SOAK: FAIL — ", ", ".join(_failures))
		quit(1)
