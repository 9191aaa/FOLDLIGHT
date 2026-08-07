class_name FoldlightPixelDemoBootstrap
extends Node

## Small, opt-in launch router for the standalone pixel-art presentation build.
##
## Add this node to the release entry scene and give the dedicated export preset
## the custom feature `pixel_demo`. Builds without that feature do nothing.

signal demo_route_requested(scene_path: String)
signal demo_route_committed(scene_path: String, error: Error)

const FEATURE_NAME: StringName = &"pixel_demo"
const DEMO_SCENE_PATH: String = "res://scenes/demos/pixel_playable_demo.tscn"

## Test seam only. Production leaves this invalid and reads OS.has_feature().
var feature_probe_override: Callable = Callable()

var _route_attempted: bool = false
var _last_route_error: Error = OK


func _ready() -> void:
	# Scene changes are deferred so this bootstrap is safe whether it is a child
	# of the entry scene or an autoload-style integration node.
	call_deferred("_route_from_runtime_feature")


func _route_from_runtime_feature() -> bool:
	if _route_attempted or not should_launch_pixel_demo(feature_probe_override):
		return false
	_route_attempted = true
	demo_route_requested.emit(DEMO_SCENE_PATH)
	_last_route_error = get_tree().change_scene_to_file(DEMO_SCENE_PATH)
	demo_route_committed.emit(DEMO_SCENE_PATH, _last_route_error)
	return _last_route_error == OK


func get_bootstrap_contract() -> Dictionary:
	return {
		"feature": FEATURE_NAME,
		"demo_scene": DEMO_SCENE_PATH,
		"opt_in": true,
		"ordinary_build_side_effects": false,
		"changes_display_mode": false,
		"route_attempted": _route_attempted,
		"last_route_error": _last_route_error,
	}


static func should_launch_pixel_demo(feature_probe: Callable = Callable()) -> bool:
	if feature_probe.is_valid():
		return bool(feature_probe.call(FEATURE_NAME))
	return OS.has_feature(FEATURE_NAME)


static func resolve_initial_scene(default_scene_path: String, feature_probe: Callable = Callable()) -> String:
	if should_launch_pixel_demo(feature_probe):
		return DEMO_SCENE_PATH
	return default_scene_path
