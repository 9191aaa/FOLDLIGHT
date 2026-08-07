class_name FoldlightPlatformBridge
extends Node

## Optional Steamworks adapter. The complete game remains runnable without the SDK;
## when a Steam singleton is present, local achievements and stats are mirrored.

signal achievement_submitted(achievement_id: StringName, platform_available: bool)

const STEAM_ACHIEVEMENT_IDS: Dictionary = {
	"first_dawn": "FIRST_DAWN",
	"uncreased": "UNCREASED",
	"paper_storm": "PAPER_STORM",
	"perfect_fold": "PERFECT_FOLD",
}

var steam_available: bool = false
var _steam: Object


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	steam_available = Engine.has_singleton("Steam")
	if steam_available:
		_steam = Engine.get_singleton("Steam")


func submit_achievement(achievement_id: StringName) -> bool:
	if not steam_available or _steam == null:
		achievement_submitted.emit(achievement_id, false)
		return false
	var steam_id := String(STEAM_ACHIEVEMENT_IDS.get(String(achievement_id), String(achievement_id).to_upper()))
	var accepted := true
	if _steam.has_method("setAchievement"):
		accepted = bool(_steam.call("setAchievement", steam_id))
	if accepted and _steam.has_method("storeStats"):
		_steam.call("storeStats")
	achievement_submitted.emit(achievement_id, true)
	return accepted


func submit_integer_stat(stat_name: StringName, value: int) -> bool:
	if not steam_available or _steam == null or not _steam.has_method("setStatInt"):
		return false
	var accepted := bool(_steam.call("setStatInt", String(stat_name).to_upper(), value))
	if accepted and _steam.has_method("storeStats"):
		_steam.call("storeStats")
	return accepted
