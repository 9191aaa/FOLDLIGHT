class_name FoldlightCampaignCatalog
extends RefCounted

const CAMPAIGN_ID: StringName = &"main"
const CONTENT_REVISION: int = 1
const EXPECTED_ACTIVE_SECONDS: int = 7080
const MISSIONS: Array = [
	preload("res://resources/campaign/missions/c1m1_still_water.tres"),
	preload("res://resources/campaign/missions/c1m2_kite_beacons.tres"),
	preload("res://resources/campaign/missions/c1m3_echo_garden.tres"),
	preload("res://resources/campaign/missions/c1m4_ink_moon.tres"),
	preload("res://resources/campaign/missions/c2m1_lightless_escort.tres"),
	preload("res://resources/campaign/missions/c2m2_red_wheel_gate.tres"),
	preload("res://resources/campaign/missions/c2m3_four_second_return.tres"),
	preload("res://resources/campaign/missions/c2m4_sunken_bell.tres"),
	preload("res://resources/campaign/missions/c3m1_mirror_names.tres"),
	preload("res://resources/campaign/missions/c3m2_broken_isles.tres"),
	preload("res://resources/campaign/missions/c3m3_hundred_fold_night.tres"),
	preload("res://resources/campaign/missions/c3m4_nameless_sun.tres"),
]


static func mission_count() -> int:
	return MISSIONS.size()


static func mission_at(index: int) -> FoldMissionDefinition:
	if index < 0 or index >= MISSIONS.size():
		return null
	return MISSIONS[index] as FoldMissionDefinition


static func mission_by_id(mission_id: StringName) -> FoldMissionDefinition:
	for mission in MISSIONS:
		if (mission as FoldMissionDefinition).mission_id == mission_id:
			return mission as FoldMissionDefinition
	return null


static func index_of(mission_id: StringName) -> int:
	for index in MISSIONS.size():
		if (MISSIONS[index] as FoldMissionDefinition).mission_id == mission_id:
			return index
	return -1


static func next_mission_id(mission_id: StringName) -> StringName:
	var index := index_of(mission_id)
	if index < 0 or index + 1 >= MISSIONS.size():
		return &""
	return (MISSIONS[index + 1] as FoldMissionDefinition).mission_id


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var seconds := 0
	for index in MISSIONS.size():
		var mission := MISSIONS[index] as FoldMissionDefinition
		if mission == null:
			errors.append("mission %d failed to load" % index)
			continue
		var key := String(mission.mission_id)
		if seen.has(key):
			errors.append("duplicate mission id %s" % key)
		seen[key] = true
		seconds += mission.expected_seconds
		for detail in mission.validation_errors():
			errors.append("%s: %s" % [key, detail])
		if mission.chapter != int(index / 4) + 1 or mission.mission_number != index % 4 + 1:
			errors.append("%s is out of chapter order" % key)
	if seconds != EXPECTED_ACTIVE_SECONDS:
		errors.append("campaign seconds %d != %d" % [seconds, EXPECTED_ACTIVE_SECONDS])
	return errors
