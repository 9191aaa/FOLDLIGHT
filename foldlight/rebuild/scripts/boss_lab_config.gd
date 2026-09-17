class_name FoldlightBossLabConfig
extends RefCounted

const CONFIG_PATH := "res://rebuild/config/boss_profiles.json"

static func all_profiles() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("Boss Lab configuration is missing: " + CONFIG_PATH)
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(CONFIG_PATH))
	if error != OK or not parser.data is Dictionary:
		push_error("Boss Lab configuration must be valid JSON.")
		return {}
	return parser.data as Dictionary

static func profile(profile_id: StringName = &"normal") -> Dictionary:
	var data := all_profiles()
	var profiles: Dictionary = data.get("profiles", {})
	if not profiles.has(String(profile_id)):
		push_error("Unknown Boss Lab profile: " + String(profile_id))
		return {}
	var result: Dictionary = (data.get("shared", {}) as Dictionary).duplicate(true)
	result.merge(profiles[String(profile_id)] as Dictionary, true)
	result["id"] = String(profile_id)
	return result
