class_name FoldlightProfileManager
extends Node

const PROFILE_VERSION: int = 6
const PROFILE_PATH: String = "user://profile.json"
const PROFILE_BACKUP_PATH: String = "user://profile.json.bak"
const PROFILE_TEMP_PATH: String = "user://profile.json.tmp"
const SETTINGS_PATH: String = "user://settings.cfg"

const META_CATALOG: Array[Dictionary] = [
	{
		"id": &"lantern_frame",
		"title": "灯　骨",
		"description": "每两级增加一瓣生命，并强化开局无伤时间",
		"max_level": 4,
		"base_cost": 3,
		"accent": Color(1.0, 0.70, 0.29),
	},
	{
		"id": &"wide_memory",
		"title": "潮　忆",
		"description": "每级永久扩大 4% 折域半径",
		"max_level": 5,
		"base_cost": 2,
		"accent": Color(0.30, 0.88, 0.86),
	},
	{
		"id": &"deep_reservoir",
		"title": "深　匣",
		"description": "每级增加 1 枚收纳上限并加快折息恢复",
		"max_level": 5,
		"base_cost": 2,
		"accent": Color(0.48, 0.72, 0.96),
	},
	{
		"id": &"return_edge",
		"title": "返　锋",
		"description": "每级加快返光；满级时返光伤害永久 +1",
		"max_level": 5,
		"base_cost": 3,
		"accent": Color(0.92, 0.34, 0.61),
	},
	{
		"id": &"crease_rebuke",
		"title": "折　界　棘",
		"description": "松开折域时，穿过圆界的冲角与回痕会受创并露出破绽",
		"max_level": 1,
		"base_cost": 8,
		"accent": Color(0.88, 0.42, 0.74),
	},
]

var settings: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.78,
	"sfx_volume": 0.92,
	"fullscreen": false,
	# 3.7 performs a one-time safe-window migration. Older builds could restore
	# borderless fullscreen during autoload startup, which caused a visible mode
	# switch (and was unstable on at least one Windows graphics stack).
	"display_safe_mode_migrated": false,
	"vibration": true,
	"screen_shake": 1.0,
	"high_contrast": false,
}

var profile: Dictionary = {
	"version": PROFILE_VERSION,
	"best_score": 0,
	"best_rank": "—",
	"best_time": 0.0,
	"total_runs": 0,
	"victories": 0,
	"total_captures": 0,
	"total_kills": 0,
	"discovered_doctrines": [],
	"discovered_enemies": [],
	"achievements": {},
	"glimmer": 0,
	"last_glimmer_reward": 0,
	"meta_upgrades": {
		"lantern_frame": 0,
		"wide_memory": 0,
		"deep_reservoir": 0,
		"return_edge": 0,
		"crease_rebuke": 0,
	},
	"tutorial_complete": false,
	"challenge": {
		"runs": 0,
		"best_time": 0.0,
		"best_score": 0,
		"best_tier": 0,
		"total_events": 0,
	},
	"roguelite": {
		"prologue_complete": false,
		"runs": 0,
		"victories": 0,
		"best_time": 0.0,
		"best_region": 0,
		"highest_pressure": 0,
		"unlocked_weapons": ["crease_lantern", "needle_orbit", "returning_gull"],
		"unlocked_active_items": ["paper_burst", "mirror_step", "ink_wash"],
		"unlocked_upgrades": ["steady_lantern", "rapid_crease", "twin_fold", "wide_return", "quiet_hinge", "dense_fold", "swift_wing", "long_glide", "slipstream", "thick_paper", "calm_current", "tiny_silhouette"],
		"recent_unlocks": [],
		"discovered_rooms": [],
		"discovered_enemies": [],
		"discovered_bosses": [],
		"active_run": {},
	},
	"story_flags": {},
	"acknowledged_intros": [],
	"highest_tide": 0,
	"chapter_one_complete": false,
	"campaign": {
		"unlocked_missions": ["c1m1"],
		"completed": {},
		"reward_grants": [],
		"campaign_complete": false,
		"campaign_seconds": 0.0,
		"active_checkpoint": {},
		"failure_counts": {},
		"assisted_missions": [],
	},
}

var persistence_enabled: bool = true
var future_profile_read_only: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	persistence_enabled = not OS.get_cmdline_user_args().has("--test-mode")
	if persistence_enabled:
		load_settings()
		load_profile()
		_migrate_startup_display_mode()
	apply_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK:
		return
	for key in settings.keys():
		settings[key] = config.get_value("settings", key, settings[key])


func save_settings() -> bool:
	if not persistence_enabled:
		return true
	var config := ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("ProfileManager: failed to save settings (%s)" % error_string(error))
		return false
	return true


func apply_settings() -> void:
	_set_bus_linear(&"Master", float(settings["master_volume"]))
	_set_bus_linear(&"Music", float(settings["music_volume"]))
	_set_bus_linear(&"SFX", float(settings["sfx_volume"]))
	if DisplayServer.get_name().to_lower() != "headless":
		# Defer the native window transition until the first frame has created a
		# stable window. Applying it from an autoload's _ready() caused a startup
		# access violation on one Windows machine in an older build.
		call_deferred("_apply_display_mode_safely")


func _migrate_startup_display_mode() -> void:
	if bool(settings.get("display_safe_mode_migrated", false)):
		return
	settings["fullscreen"] = false
	settings["display_safe_mode_migrated"] = true
	if persistence_enabled:
		save_settings()


func _apply_display_mode_safely() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var fullscreen: bool = bool(settings["fullscreen"])
	# Borderless fullscreen follows the desktop mode and cannot switch the
	# monitor's physical resolution. Exclusive fullscreen is forbidden.
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func set_setting(key: StringName, value: Variant) -> void:
	var text_key := String(key)
	if not settings.has(text_key):
		push_warning("ProfileManager: unknown setting '%s'" % key)
		return
	settings[text_key] = value
	apply_settings()
	save_settings()


func get_setting(key: StringName, fallback: Variant = null) -> Variant:
	return settings.get(String(key), fallback)


func load_profile() -> void:
	var parsed := _read_profile_dictionary(PROFILE_PATH)
	if parsed.is_empty() and FileAccess.file_exists(PROFILE_BACKUP_PATH):
		push_warning("ProfileManager: primary profile is invalid; recovering backup")
		parsed = _read_profile_dictionary(PROFILE_BACKUP_PATH)
	if parsed.is_empty():
		return
	var source_version := int(parsed.get("version", 0))
	if source_version > PROFILE_VERSION:
		future_profile_read_only = true
		push_warning("ProfileManager: profile version %d is newer than supported version %d; refusing to overwrite" % [source_version, PROFILE_VERSION])
		return
	var migrated := _migrate_profile(parsed)
	for key in profile.keys():
		if migrated.has(key):
			profile[key] = migrated[key]


func save_profile() -> bool:
	if not persistence_enabled:
		return true
	if future_profile_read_only:
		push_warning("ProfileManager: save refused because a newer profile version was detected")
		return false
	var payload := profile.duplicate(true)
	payload["version"] = PROFILE_VERSION
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var file := FileAccess.open(PROFILE_TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("ProfileManager: failed to open temporary profile for writing")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	if _read_profile_dictionary(PROFILE_TEMP_PATH).is_empty():
		push_error("ProfileManager: temporary profile verification failed")
		return false
	var profile_absolute := ProjectSettings.globalize_path(PROFILE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(PROFILE_BACKUP_PATH)
	var temp_absolute := ProjectSettings.globalize_path(PROFILE_TEMP_PATH)
	if FileAccess.file_exists(PROFILE_PATH):
		if FileAccess.file_exists(PROFILE_BACKUP_PATH):
			DirAccess.remove_absolute(backup_absolute)
		var backup_error := DirAccess.copy_absolute(profile_absolute, backup_absolute)
		if backup_error != OK:
			push_error("ProfileManager: failed to create profile backup (%s)" % error_string(backup_error))
			return false
		var remove_error := DirAccess.remove_absolute(profile_absolute)
		if remove_error != OK:
			push_error("ProfileManager: failed to replace existing profile (%s)" % error_string(remove_error))
			return false
	var rename_error := DirAccess.rename_absolute(temp_absolute, profile_absolute)
	if rename_error != OK:
		push_error("ProfileManager: failed to commit temporary profile (%s)" % error_string(rename_error))
		if FileAccess.file_exists(PROFILE_BACKUP_PATH) and not FileAccess.file_exists(PROFILE_PATH):
			DirAccess.copy_absolute(backup_absolute, profile_absolute)
		return false
	profile["version"] = PROFILE_VERSION
	return true


func _read_profile_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	return (parsed as Dictionary).duplicate(true)


func record_run(won: bool, score: int, rank: String, run_time: float, captures: int, kills: int, no_hit: bool, reached_tide: int = 1) -> int:
	profile["total_runs"] = int(profile["total_runs"]) + 1
	profile["total_captures"] = int(profile["total_captures"]) + captures
	profile["total_kills"] = int(profile["total_kills"]) + kills
	if score > int(profile["best_score"]):
		profile["best_score"] = score
		profile["best_rank"] = rank
	if won:
		profile["victories"] = int(profile["victories"]) + 1
		if float(profile["best_time"]) <= 0.0 or run_time < float(profile["best_time"]):
			profile["best_time"] = run_time
		unlock_achievement(&"first_dawn")
	if no_hit and won:
		unlock_achievement(&"uncreased")
	if captures >= 120:
		unlock_achievement(&"paper_storm")
	if rank == "S":
		unlock_achievement(&"perfect_fold")
	profile["highest_tide"] = maxi(int(profile.get("highest_tide", 0)), reached_tide)
	if won:
		profile["chapter_one_complete"] = true
	var reward := 1 + int(kills / 10) + int(captures / 48)
	if won:
		reward += 6
	match rank:
		"S": reward += 4
		"A": reward += 2
		"B": reward += 1
		_: pass
	reward = clampi(reward, 1, 24)
	profile["glimmer"] = int(profile.get("glimmer", 0)) + reward
	profile["last_glimmer_reward"] = reward
	var platform_bridge := get_node_or_null("/root/PlatformBridge") as FoldlightPlatformBridge
	if platform_bridge:
		platform_bridge.submit_integer_stat(&"total_runs", int(profile["total_runs"]))
		platform_bridge.submit_integer_stat(&"best_score", int(profile["best_score"]))
		platform_bridge.submit_integer_stat(&"total_captures", int(profile["total_captures"]))
	save_profile()
	return reward


func get_meta_level(upgrade_id: StringName) -> int:
	var upgrades: Dictionary = profile.get("meta_upgrades", {})
	return int(upgrades.get(String(upgrade_id), 0))


func get_meta_cost(upgrade_id: StringName) -> int:
	for definition in META_CATALOG:
		if StringName(definition["id"]) == upgrade_id:
			var level := get_meta_level(upgrade_id)
			return int(definition["base_cost"]) + level * 2
	return 0


func get_meta_catalog_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var glimmer := int(profile.get("glimmer", 0))
	for definition in META_CATALOG:
		var snapshot := definition.duplicate(true)
		var upgrade_id := StringName(definition["id"])
		var level := get_meta_level(upgrade_id)
		var max_level := int(definition["max_level"])
		var cost := get_meta_cost(upgrade_id)
		snapshot["level"] = level
		snapshot["cost"] = cost
		snapshot["maxed"] = level >= max_level
		snapshot["affordable"] = level < max_level and glimmer >= cost
		result.append(snapshot)
	return result


func purchase_meta_upgrade(upgrade_id: StringName, persist: bool = true) -> bool:
	var definition: Dictionary = {}
	for candidate in META_CATALOG:
		if StringName(candidate["id"]) == upgrade_id:
			definition = candidate
			break
	if definition.is_empty():
		push_warning("ProfileManager: unknown meta upgrade '%s'" % upgrade_id)
		return false
	var level := get_meta_level(upgrade_id)
	if level >= int(definition["max_level"]):
		return false
	var cost := get_meta_cost(upgrade_id)
	var glimmer := int(profile.get("glimmer", 0))
	if glimmer < cost:
		return false
	var upgrades: Dictionary = profile.get("meta_upgrades", {}).duplicate(true)
	var previous_upgrades := upgrades.duplicate(true)
	var previous_glimmer := glimmer
	upgrades[String(upgrade_id)] = level + 1
	profile["meta_upgrades"] = upgrades
	profile["glimmer"] = glimmer - cost
	if persist and not save_profile():
		profile["meta_upgrades"] = previous_upgrades
		profile["glimmer"] = previous_glimmer
		return false
	return true


func get_campaign_snapshot() -> Dictionary:
	return (profile.get("campaign", {}) as Dictionary).duplicate(true)


func mark_tutorial_complete(persist: bool = true) -> bool:
	profile["tutorial_complete"] = true
	return not persist or save_profile()


func get_challenge_snapshot() -> Dictionary:
	return (profile.get("challenge", {}) as Dictionary).duplicate(true)


func get_roguelite_snapshot() -> Dictionary:
	return (profile.get("roguelite", {}) as Dictionary).duplicate(true)


func mark_prologue_complete(persist: bool = true) -> bool:
	var rogue: Dictionary = profile.get("roguelite", {}).duplicate(true)
	rogue["prologue_complete"] = true
	profile["roguelite"] = rogue
	return not persist or save_profile()


func commit_roguelite_checkpoint(checkpoint: Dictionary, persist: bool = true) -> bool:
	if checkpoint.is_empty() or int(checkpoint.get("version", 0)) != FoldlightRogueRunState.SNAPSHOT_VERSION:
		return false
	if int(checkpoint.get("seed", 0)) == 0 or StringName(checkpoint.get("current_node_id", &"")).is_empty():
		return false
	var rogue: Dictionary = profile.get("roguelite", {}).duplicate(true)
	rogue["active_run"] = checkpoint.duplicate(true)
	profile["roguelite"] = rogue
	return not persist or save_profile()


func clear_roguelite_checkpoint(persist: bool = true) -> bool:
	var rogue: Dictionary = profile.get("roguelite", {}).duplicate(true)
	rogue["active_run"] = {}
	profile["roguelite"] = rogue
	return not persist or save_profile()


func unlock_roguelite_content(collection_key: StringName, content_id: StringName, persist: bool = true) -> bool:
	var allowed := [&"unlocked_weapons", &"unlocked_active_items", &"unlocked_upgrades"]
	if not allowed.has(collection_key) or content_id.is_empty():
		return false
	var rogue: Dictionary = profile.get("roguelite", {}).duplicate(true)
	var entries: Array = (rogue.get(String(collection_key), []) as Array).duplicate()
	if not entries.has(String(content_id)):
		entries.append(String(content_id))
	rogue[String(collection_key)] = entries
	profile["roguelite"] = rogue
	return not persist or save_profile()


func record_roguelite_run(result: Dictionary, persist: bool = true) -> int:
	var rogue: Dictionary = profile.get("roguelite", {}).duplicate(true)
	var won := bool(result.get("won", false))
	var run_time := maxf(0.0, float(result.get("time", 0.0)))
	var region := clampi(int(result.get("region", 1)), 1, 3)
	var pressure := maxi(0, int(result.get("pressure", 0)))
	rogue["runs"] = int(rogue.get("runs", 0)) + 1
	rogue["victories"] = int(rogue.get("victories", 0)) + (1 if won else 0)
	rogue["best_region"] = maxi(int(rogue.get("best_region", 0)), region)
	rogue["highest_pressure"] = maxi(int(rogue.get("highest_pressure", 0)), pressure)
	if won and (float(rogue.get("best_time", 0.0)) <= 0.0 or run_time < float(rogue.get("best_time", 0.0))):
		rogue["best_time"] = run_time
	rogue["active_run"] = {}
	rogue = FoldlightRogueUnlockCatalog.apply_eligible(rogue)
	profile["roguelite"] = rogue
	profile["total_runs"] = int(profile.get("total_runs", 0)) + 1
	profile["victories"] = int(profile.get("victories", 0)) + (1 if won else 0)
	profile["total_captures"] = int(profile.get("total_captures", 0)) + maxi(0, int(result.get("captures", 0)))
	profile["total_kills"] = int(profile.get("total_kills", 0)) + maxi(0, int(result.get("kills", 0)))
	var reward := clampi(1 + int(result.get("rooms", 0)) / 3 + region * 2 + (5 if won else 0), 1, 24)
	profile["glimmer"] = int(profile.get("glimmer", 0)) + reward
	profile["last_glimmer_reward"] = reward
	if persist and not save_profile():
		push_error("ProfileManager: roguelite result could not be persisted")
	return reward


func record_challenge_run(result: Dictionary, persist: bool = true) -> int:
	var challenge: Dictionary = profile.get("challenge", {}).duplicate(true)
	var run_time := maxf(0.0, float(result.get("time", 0.0)))
	var run_score := maxi(0, int(result.get("score", 0)))
	var run_tier := maxi(1, int(result.get("tier", 1)))
	var run_events := maxi(0, int(result.get("events", 0)))
	challenge["runs"] = int(challenge.get("runs", 0)) + 1
	challenge["best_time"] = maxf(float(challenge.get("best_time", 0.0)), run_time)
	challenge["best_score"] = maxi(int(challenge.get("best_score", 0)), run_score)
	challenge["best_tier"] = maxi(int(challenge.get("best_tier", 0)), run_tier)
	challenge["total_events"] = int(challenge.get("total_events", 0)) + run_events
	profile["challenge"] = challenge
	profile["total_runs"] = int(profile.get("total_runs", 0)) + 1
	profile["total_captures"] = int(profile.get("total_captures", 0)) + maxi(0, int(result.get("captures", 0)))
	profile["total_kills"] = int(profile.get("total_kills", 0)) + maxi(0, int(result.get("kills", 0)))
	if run_score > int(profile.get("best_score", 0)):
		profile["best_score"] = run_score
		profile["best_rank"] = "∞"
	var reward := clampi(1 + int(run_time / 90.0) + int(run_tier / 3), 1, 28)
	profile["glimmer"] = int(profile.get("glimmer", 0)) + reward
	profile["last_glimmer_reward"] = reward
	if run_time >= 300.0:
		unlock_achievement(&"endless_five")
	if persist and not save_profile():
		push_error("ProfileManager: challenge result could not be persisted")
	return reward


func is_mission_unlocked(mission_id: StringName) -> bool:
	var campaign: Dictionary = profile.get("campaign", {})
	var unlocked: Array = campaign.get("unlocked_missions", ["c1m1"])
	return unlocked.has(String(mission_id))


func get_active_checkpoint() -> Dictionary:
	var campaign: Dictionary = profile.get("campaign", {})
	return (campaign.get("active_checkpoint", {}) as Dictionary).duplicate(true)


func commit_campaign_checkpoint(checkpoint: Dictionary, persist: bool = true) -> bool:
	if checkpoint.is_empty():
		return false
	var mission_id := StringName(checkpoint.get("mission_id", &""))
	if FoldlightCampaignCatalog.mission_by_id(mission_id) == null:
		push_warning("ProfileManager: refused checkpoint for unknown mission '%s'" % mission_id)
		return false
	var campaign: Dictionary = profile.get("campaign", {}).duplicate(true)
	campaign["active_checkpoint"] = checkpoint.duplicate(true)
	profile["campaign"] = campaign
	return not persist or save_profile()


func clear_campaign_checkpoint(persist: bool = true) -> bool:
	var campaign: Dictionary = profile.get("campaign", {}).duplicate(true)
	campaign["active_checkpoint"] = {}
	profile["campaign"] = campaign
	return not persist or save_profile()


func record_campaign_failure(mission_id: StringName, persist: bool = true) -> int:
	var campaign: Dictionary = profile.get("campaign", {}).duplicate(true)
	var failures: Dictionary = campaign.get("failure_counts", {}).duplicate(true)
	var key := String(mission_id)
	var count := int(failures.get(key, 0)) + 1
	failures[key] = count
	campaign["failure_counts"] = failures
	profile["campaign"] = campaign
	if persist:
		save_profile()
	return count


func enable_campaign_assist(mission_id: StringName, persist: bool = true) -> bool:
	var campaign: Dictionary = profile.get("campaign", {}).duplicate(true)
	var assisted: Array = campaign.get("assisted_missions", []).duplicate()
	var key := String(mission_id)
	if not assisted.has(key):
		assisted.append(key)
	campaign["assisted_missions"] = assisted
	profile["campaign"] = campaign
	return not persist or save_profile()


func is_campaign_assisted(mission_id: StringName) -> bool:
	var campaign: Dictionary = profile.get("campaign", {})
	return (campaign.get("assisted_missions", []) as Array).has(String(mission_id))


func record_campaign_mission(mission_id: StringName, result: Dictionary, persist: bool = true) -> int:
	var mission := FoldlightCampaignCatalog.mission_by_id(mission_id)
	if mission == null:
		push_warning("ProfileManager: refused result for unknown mission '%s'" % mission_id)
		return 0
	var campaign: Dictionary = profile.get("campaign", {}).duplicate(true)
	var completed: Dictionary = campaign.get("completed", {}).duplicate(true)
	var key := String(mission_id)
	var existing: Dictionary = (completed.get(key, {}) as Dictionary).duplicate(true)
	var result_time := maxf(0.0, float(result.get("time", 0.0)))
	var result_score := maxi(0, int(result.get("score", 0)))
	var result_rank := str(result.get("rank", "C"))
	profile["total_runs"] = int(profile.get("total_runs", 0)) + 1
	profile["victories"] = int(profile.get("victories", 0)) + 1
	profile["total_captures"] = int(profile.get("total_captures", 0)) + maxi(0, int(result.get("captures", 0)))
	profile["total_kills"] = int(profile.get("total_kills", 0)) + maxi(0, int(result.get("kills", 0)))
	if result_score > int(profile.get("best_score", 0)):
		profile["best_score"] = result_score
		profile["best_rank"] = result_rank
	if float(profile.get("best_time", 0.0)) <= 0.0 or (result_time > 0.0 and result_time < float(profile.get("best_time", 0.0))):
		profile["best_time"] = result_time
	unlock_achievement(&"first_dawn")
	if existing.is_empty() or result_score > int(existing.get("best_score", 0)):
		existing["rank"] = result_rank
		existing["best_score"] = result_score
	if float(existing.get("best_time", 0.0)) <= 0.0 or (result_time > 0.0 and result_time < float(existing.get("best_time", 0.0))):
		existing["best_time"] = result_time
	existing["clears"] = int(existing.get("clears", 0)) + 1
	completed[key] = existing
	campaign["completed"] = completed
	var unlocked: Array = campaign.get("unlocked_missions", ["c1m1"]).duplicate()
	var next_id := FoldlightCampaignCatalog.next_mission_id(mission_id)
	if not next_id.is_empty() and not unlocked.has(String(next_id)):
		unlocked.append(String(next_id))
	campaign["unlocked_missions"] = unlocked
	campaign["active_checkpoint"] = {}
	campaign["campaign_seconds"] = float(campaign.get("campaign_seconds", 0.0)) + result_time
	if (mission as FoldMissionDefinition).campaign_finale:
		campaign["campaign_complete"] = true
	var reward_grants: Array = campaign.get("reward_grants", []).duplicate()
	var reward_id := "main:%s:first_clear" % key
	var reward := 0
	if not reward_grants.has(reward_id):
		reward_grants.append(reward_id)
		reward = (mission as FoldMissionDefinition).base_glimmer_reward
		profile["glimmer"] = int(profile.get("glimmer", 0)) + reward
	campaign["reward_grants"] = reward_grants
	var failures: Dictionary = campaign.get("failure_counts", {}).duplicate(true)
	failures[key] = 0
	campaign["failure_counts"] = failures
	profile["campaign"] = campaign
	if persist and not save_profile():
		push_error("ProfileManager: campaign result could not be persisted")
	return reward


func has_story_seen(story_id: StringName) -> bool:
	var flags: Dictionary = profile.get("story_flags", {})
	return bool(flags.get(String(story_id), false))


func mark_story_seen(story_id: StringName, persist: bool = true) -> void:
	var flags: Dictionary = profile.get("story_flags", {}).duplicate(true)
	flags[String(story_id)] = true
	profile["story_flags"] = flags
	if persist:
		save_profile()


func has_acknowledged_intro(intro_id: StringName) -> bool:
	var acknowledged: Array = profile.get("acknowledged_intros", [])
	return acknowledged.has(String(intro_id))


func acknowledge_intro(intro_id: StringName, persist: bool = true) -> void:
	var acknowledged: Array = profile.get("acknowledged_intros", []).duplicate()
	if acknowledged.has(String(intro_id)):
		return
	acknowledged.append(String(intro_id))
	profile["acknowledged_intros"] = acknowledged
	if persist:
		save_profile()


func discover_doctrine(doctrine_id: StringName) -> void:
	var discovered: Array = profile["discovered_doctrines"]
	if not discovered.has(String(doctrine_id)):
		discovered.append(String(doctrine_id))
		profile["discovered_doctrines"] = discovered
		save_profile()


func discover_enemy(enemy_id: StringName) -> void:
	var discovered: Array = profile["discovered_enemies"]
	if not discovered.has(String(enemy_id)):
		discovered.append(String(enemy_id))
		profile["discovered_enemies"] = discovered
		save_profile()


func unlock_achievement(achievement_id: StringName) -> bool:
	var achievements: Dictionary = profile["achievements"]
	if bool(achievements.get(String(achievement_id), false)):
		return false
	achievements[String(achievement_id)] = true
	profile["achievements"] = achievements
	var platform_bridge := get_node_or_null("/root/PlatformBridge") as FoldlightPlatformBridge
	if platform_bridge:
		platform_bridge.submit_achievement(achievement_id)
	return true


func get_public_snapshot() -> Dictionary:
	return profile.duplicate(true)


func _migrate_profile(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var version := int(result.get("version", 0))
	if version < 1:
		result["achievements"] = result.get("achievements", {})
		result["discovered_doctrines"] = result.get("discovered_doctrines", [])
		version = 1
	if version < 2:
		result["discovered_enemies"] = []
		result["best_time"] = 0.0
		version = 2
	if version < 3:
		result["glimmer"] = int(result.get("glimmer", 0))
		result["last_glimmer_reward"] = 0
		result["meta_upgrades"] = result.get("meta_upgrades", {})
		result["story_flags"] = result.get("story_flags", {})
		result["acknowledged_intros"] = result.get("acknowledged_intros", [])
		result["highest_tide"] = int(result.get("highest_tide", 0))
		result["chapter_one_complete"] = bool(result.get("chapter_one_complete", false))
		version = 3
	if version < 4:
		var unlocked: Array = ["c1m1"]
		var completed: Dictionary = {}
		if bool(result.get("chapter_one_complete", false)):
			completed["c1m1"] = {
				"rank": str(result.get("best_rank", "—")),
				"best_score": int(result.get("best_score", 0)),
				"best_time": float(result.get("best_time", 0.0)),
				"clears": maxi(1, int(result.get("victories", 1))),
			}
			unlocked.append("c1m2")
		result["campaign"] = {
			"unlocked_missions": unlocked,
			"completed": completed,
			"reward_grants": [],
			"campaign_complete": false,
			"campaign_seconds": float(result.get("best_time", 0.0)) if not completed.is_empty() else 0.0,
			"active_checkpoint": {},
			"failure_counts": {},
			"assisted_missions": [],
		}
		version = 4
	if version < 5:
		result["tutorial_complete"] = bool(result.get("tutorial_complete", false))
		result["challenge"] = result.get("challenge", {})
		version = 5
	if version < 6:
		result["roguelite"] = result.get("roguelite", {})
		version = 6
	var upgrades: Dictionary = result.get("meta_upgrades", {})
	for definition in META_CATALOG:
		var upgrade_key := String(definition["id"])
		upgrades[upgrade_key] = clampi(int(upgrades.get(upgrade_key, 0)), 0, int(definition["max_level"]))
	result["meta_upgrades"] = upgrades
	result["acknowledged_intros"] = result.get("acknowledged_intros", [])
	result["campaign"] = _normalize_campaign(result.get("campaign", {}))
	result["tutorial_complete"] = bool(result.get("tutorial_complete", false))
	result["challenge"] = _normalize_challenge(result.get("challenge", {}))
	result["roguelite"] = _normalize_roguelite(result.get("roguelite", {}))
	result["version"] = version
	return result


func _normalize_campaign(source: Variant) -> Dictionary:
	var campaign: Dictionary = (source as Dictionary).duplicate(true) if source is Dictionary else {}
	var unlocked: Array = campaign.get("unlocked_missions", ["c1m1"])
	var normalized_unlocked: Array[String] = []
	for mission_id in unlocked:
		var key := String(mission_id)
		if FoldlightCampaignCatalog.mission_by_id(StringName(key)) != null and not normalized_unlocked.has(key):
			normalized_unlocked.append(key)
	if normalized_unlocked.is_empty():
		normalized_unlocked.append("c1m1")
	campaign["unlocked_missions"] = normalized_unlocked
	campaign["completed"] = campaign.get("completed", {}) if campaign.get("completed", {}) is Dictionary else {}
	campaign["reward_grants"] = campaign.get("reward_grants", []) if campaign.get("reward_grants", []) is Array else []
	campaign["campaign_complete"] = bool(campaign.get("campaign_complete", false))
	campaign["campaign_seconds"] = maxf(0.0, float(campaign.get("campaign_seconds", 0.0)))
	campaign["active_checkpoint"] = campaign.get("active_checkpoint", {}) if campaign.get("active_checkpoint", {}) is Dictionary else {}
	campaign["failure_counts"] = campaign.get("failure_counts", {}) if campaign.get("failure_counts", {}) is Dictionary else {}
	campaign["assisted_missions"] = campaign.get("assisted_missions", []) if campaign.get("assisted_missions", []) is Array else []
	return campaign


func _normalize_challenge(source: Variant) -> Dictionary:
	var challenge: Dictionary = (source as Dictionary).duplicate(true) if source is Dictionary else {}
	challenge["runs"] = maxi(0, int(challenge.get("runs", 0)))
	challenge["best_time"] = maxf(0.0, float(challenge.get("best_time", 0.0)))
	challenge["best_score"] = maxi(0, int(challenge.get("best_score", 0)))
	challenge["best_tier"] = maxi(0, int(challenge.get("best_tier", 0)))
	challenge["total_events"] = maxi(0, int(challenge.get("total_events", 0)))
	return challenge


func _normalize_roguelite(source: Variant) -> Dictionary:
	var rogue: Dictionary = (source as Dictionary).duplicate(true) if source is Dictionary else {}
	rogue["prologue_complete"] = bool(rogue.get("prologue_complete", false))
	rogue["runs"] = maxi(0, int(rogue.get("runs", 0)))
	rogue["victories"] = clampi(int(rogue.get("victories", 0)), 0, int(rogue["runs"]))
	rogue["best_time"] = maxf(0.0, float(rogue.get("best_time", 0.0)))
	rogue["best_region"] = clampi(int(rogue.get("best_region", 0)), 0, 3)
	rogue["highest_pressure"] = maxi(0, int(rogue.get("highest_pressure", 0)))
	rogue["unlocked_weapons"] = _normalize_string_array(rogue.get("unlocked_weapons", []), FoldlightRogueUnlockCatalog.STARTER_WEAPONS)
	rogue["unlocked_active_items"] = _normalize_string_array(rogue.get("unlocked_active_items", []), FoldlightRogueUnlockCatalog.STARTER_ACTIVE_ITEMS)
	rogue["unlocked_upgrades"] = _normalize_string_array(rogue.get("unlocked_upgrades", []), FoldlightRogueUnlockCatalog.STARTER_UPGRADES)
	rogue["recent_unlocks"] = rogue.get("recent_unlocks", []) if rogue.get("recent_unlocks", []) is Array else []
	rogue["discovered_rooms"] = _normalize_string_array(rogue.get("discovered_rooms", []), [])
	rogue["discovered_enemies"] = _normalize_string_array(rogue.get("discovered_enemies", []), [])
	rogue["discovered_bosses"] = _normalize_string_array(rogue.get("discovered_bosses", []), [])
	rogue["active_run"] = (rogue.get("active_run", {}) as Dictionary).duplicate(true) if rogue.get("active_run", {}) is Dictionary else {}
	return rogue


func _normalize_string_array(source: Variant, required: Array[String]) -> Array[String]:
	var normalized: Array[String] = []
	if source is Array:
		for value: Variant in source:
			var key := String(value)
			if not key.is_empty() and not normalized.has(key):
				normalized.append(key)
	for key in required:
		if not normalized.has(key):
			normalized.append(key)
	return normalized


func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var safe_value := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, safe_value <= 0.001)
	if safe_value > 0.001:
		AudioServer.set_bus_volume_db(index, linear_to_db(safe_value))
