extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var file := FileAccess.open("res://scripts/autoloads/profile_manager.gd", FileAccess.READ)
	_check(file != null, "display settings implementation is readable")
	var source := file.get_as_text() if file != null else ""
	_check(not source.contains("WINDOW_MODE_EXCLUSIVE_FULLSCREEN"), "FOLDLIGHT never requests a desktop mode-changing exclusive fullscreen")
	_check(source.contains("WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED"), "fullscreen uses borderless desktop-safe mode")
	_check(source.contains("call_deferred(\"_apply_display_mode_safely\")"), "display mode changes wait until the native window exists")
	_check(source.contains("DisplayServer.window_get_mode() != target_mode"), "display mode is changed only when necessary")
	_check(source.contains("_migrate_startup_display_mode()"), "legacy fullscreen settings receive a one-time windowed migration")
	var profile_manager := FoldlightProfileManager.new()
	_check(not bool(profile_manager.settings.get("fullscreen", true)), "fresh profiles start windowed")
	profile_manager.free()
	if _failures.is_empty():
		print("FOLDLIGHT_DISPLAY_SAFETY: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_DISPLAY_SAFETY: FAIL - %s" % ", ".join(_failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
