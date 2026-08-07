extends SceneTree

## Standalone pixel-demo launch contract. The production path is inert unless
## an export explicitly carries the `pixel_demo` custom feature.

const BOOTSTRAP_SCRIPT := preload("res://scripts/demos/pixel_demo_bootstrap.gd")
const RELEASE_SCENE_PATH := "res://scenes/main.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ordinary_probe := func(_feature: StringName) -> bool: return false
	var demo_probe := func(feature: StringName) -> bool: return feature == &"pixel_demo"

	_check(
		BOOTSTRAP_SCRIPT.resolve_initial_scene(RELEASE_SCENE_PATH, ordinary_probe) == RELEASE_SCENE_PATH,
		"ordinary builds preserve the release entry scene"
	)
	_check(
		BOOTSTRAP_SCRIPT.resolve_initial_scene(RELEASE_SCENE_PATH, demo_probe) == BOOTSTRAP_SCRIPT.DEMO_SCENE_PATH,
		"the pixel_demo feature resolves directly to the isolated demo scene"
	)

	var ordinary_bootstrap := BOOTSTRAP_SCRIPT.new() as Node
	ordinary_bootstrap.feature_probe_override = ordinary_probe
	root.add_child(ordinary_bootstrap)
	await process_frame
	await process_frame
	var ordinary_contract: Dictionary = ordinary_bootstrap.call("get_bootstrap_contract")
	_check(not bool(ordinary_contract.get("route_attempted", true)), "ordinary runtime performs no scene-route attempt")
	_check(current_scene == null, "ordinary runtime leaves the active scene untouched")
	_check(not bool(ordinary_contract.get("changes_display_mode", true)), "bootstrap never changes the display mode")
	ordinary_bootstrap.queue_free()
	await process_frame

	var requested_paths: Array[String] = []
	var route_results: Array[Error] = []
	var demo_bootstrap := BOOTSTRAP_SCRIPT.new() as Node
	demo_bootstrap.feature_probe_override = demo_probe
	demo_bootstrap.demo_route_requested.connect(func(path: String) -> void: requested_paths.append(path))
	demo_bootstrap.demo_route_committed.connect(
		func(_path: String, error: Error) -> void: route_results.append(error)
	)
	root.add_child(demo_bootstrap)
	await process_frame
	await process_frame
	await process_frame

	_check(requested_paths == [BOOTSTRAP_SCRIPT.DEMO_SCENE_PATH], "feature-enabled runtime requests exactly one demo route")
	_check(route_results == [OK], "standalone demo scene change is accepted by the engine")
	_check(current_scene != null and current_scene.scene_file_path == BOOTSTRAP_SCRIPT.DEMO_SCENE_PATH, "feature-enabled runtime enters the pixel demo scene")
	if current_scene != null:
		var playable_contract := current_scene.call("get_playable_contract") as Dictionary
		_check(playable_contract.get("base_resolution") == Vector2i(1254, 705), "routed scene exposes the native 1254x705 playable canvas")
		_check(bool(playable_contract.get("playable", false)), "routed scene is a playable two-room demo")

	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PIXEL_DEMO_STANDALONE_1_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PIXEL_DEMO_STANDALONE_1_0: FAIL - %s" % ", ".join(_failures))
		quit(1)
