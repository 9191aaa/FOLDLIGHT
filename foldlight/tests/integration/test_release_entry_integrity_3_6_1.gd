extends SceneTree

## Guards the formal release entry against opt-in demo dependencies.  A missing
## script in the exported main scene makes release builds exit before rendering.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	_check(not main_text.is_empty(), "formal main scene is readable")
	_check("scripts/demos/" not in main_text, "formal main scene has no demo script dependency")
	_check("PixelDemoBootstrap" not in main_text, "formal main scene has no demo routing node")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_check(main_scene != null, "formal main scene loads as a PackedScene")
	if main_scene != null:
		var instance := main_scene.instantiate()
		_check(instance != null, "formal main scene instantiates")
		if instance != null:
			instance.free()

	var export_text := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("scripts/demos/*" in export_text, "formal export excludes abandoned demo scripts")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_RELEASE_ENTRY_3_6_1: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_RELEASE_ENTRY_3_6_1: FAIL - %s" % ", ".join(_failures))
		quit(1)
