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
	if OS.has_feature("mobile") and not OS.has_feature("web"):
		# High-refresh phones do not need a second render for every physics
		# tick. Keep combat at its unchanged fixed rate and reduce battery heat.
		Engine.max_fps = 60
	if OS.has_feature("web") or OS.has_feature("mobile"):
		# Procedural world labels draw with ThemeDB directly, outside UI themes.
		ThemeDB.fallback_font = FoldlightTheme.body_font()
	steam_available = Engine.has_singleton("Steam")
	if steam_available:
		_steam = Engine.get_singleton("Steam")


func _notification(what: int) -> void:
	if not OS.has_feature("mobile") or OS.has_feature("web") or not is_inside_tree():
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Use the existing menu/pause path. Android Back must never close the
		# process or abandon a friend race without its existing confirmation.
		call_deferred("_dispatch_native_back")
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		var scene := get_tree().current_scene
		if scene != null:
			var ui := scene.get_node_or_null("RoguePresentation")
			if ui != null and ui.get("screen_kind") == &"hud" and not bool(ui._hud_context.get("race", false)):
				ui.pause_requested.emit()
		var profile := get_node_or_null("/root/ProfileManager")
		if profile != null:
			profile.save_profile()
			profile.save_settings()


func _dispatch_native_back() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0:
		DisplayServer.virtual_keyboard_hide()
		return
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null: touch.cancel_all(&"android_back", true)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(release)


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
