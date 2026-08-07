extends SceneTree

## High-density hand-painted top-down RPG pixel-art delivery contract.
## The room must be reproducible from shared textures/atlases; full-frame
## screenshots are not accepted as the playable background implementation.

const WATER_TILE_PATH := "res://assets/demos/pixel/paper_reef_water_tile.png"
const TERRAIN_ATLAS_PATH := "res://assets/demos/pixel/paper_reef_terrain_atlas.png"
const ACTOR_ATLAS_PATH := "res://assets/demos/pixel/paper_reef_actor_atlas.png"
const ROOM_ONE_PATH := "res://assets/demos/pixel_playable/room_one_clean_v1.png"
const BOSS_WATER_PATH := "res://assets/demos/pixel_playable/boss_water_v1.png"
const DEMO_SCENE_PATH := "res://scenes/demos/pixel_playable_demo.tscn"
const RELEASE_SCENE_PATH := "res://scenes/main.tscn"
const MINIMUM_CANVAS := Vector2i(640, 360)
const ART_ASSETS: Array[Dictionary] = [
	{"path": WATER_TILE_PATH, "label": "paper-reef water tile"},
	{"path": TERRAIN_ATLAS_PATH, "label": "paper-reef terrain atlas"},
	{"path": ACTOR_ATLAS_PATH, "label": "paper-reef actor atlas"},
	{"path": ROOM_ONE_PATH, "label": "authored room-one backdrop"},
	{"path": BOSS_WATER_PATH, "label": "boss-room water backdrop"},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var readable_hashes := PackedStringArray()
	for asset in ART_ASSETS:
		var path := String(asset.get("path", ""))
		var label := String(asset.get("label", "pixel-art asset"))
		var texture := _load_required_texture(path, label)
		if texture != null:
			_check(_texture_meets_minimum_size(texture), "%s has sufficient source resolution" % label)
		if FileAccess.file_exists(path):
			var digest := FileAccess.get_sha256(path)
			_check(not digest.is_empty(), "%s has a readable SHA-256 digest" % label)
			if not digest.is_empty():
				readable_hashes.append(digest)
	var unique_hashes := {}
	for digest in readable_hashes:
		unique_hashes[digest] = true
	_check(readable_hashes.size() == ART_ASSETS.size() and unique_hashes.size() == ART_ASSETS.size(), "all playable art sources are distinct readable deliveries")

	await _validate_modular_demo_contract()

	_check(
		String(ProjectSettings.get_setting("application/run/main_scene", "")) == RELEASE_SCENE_PATH,
		"formal build keeps the production main scene"
	)
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene.pixel_demo", "")) == DEMO_SCENE_PATH,
		"pixel_demo feature override points directly to the isolated demo scene"
	)
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width.pixel_demo", 0)) == 1254, "pixel_demo keeps a native 1254-pixel logical width")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_height.pixel_demo", 0)) == 705, "pixel_demo keeps a DPI-exact 705-pixel logical height")
	_check(int(ProjectSettings.get_setting("display/window/size/window_width_override.pixel_demo", 0)) == 1254, "pixel_demo opens at the exact native width")
	_check(int(ProjectSettings.get_setting("display/window/size/window_height_override.pixel_demo", 0)) == 705, "pixel_demo opens at the exact native height")
	_check(not bool(ProjectSettings.get_setting("display/window/size/resizable.pixel_demo", true)), "pixel_demo window cannot be resized into a blurred fractional scale")
	_check(String(ProjectSettings.get_setting("display/window/stretch/scale_mode.pixel_demo", "")) == "integer", "pixel_demo requests integer-only viewport scaling")
	_check(int(ProjectSettings.get_setting("display/window/size/mode", -1)) == 0, "pixel_demo inherits the safe windowed display mode")
	_validate_export_presets()
	_finish()


func _load_required_texture(path: String, label: String) -> Texture2D:
	_check(FileAccess.file_exists(path), "%s exists at %s" % [label, path])
	if not FileAccess.file_exists(path):
		return null
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	_check(texture != null, "%s imports and loads as Texture2D" % label)
	return texture


func _texture_meets_minimum_size(texture: Texture2D) -> bool:
	var width := texture.get_width()
	var height := texture.get_height()
	if width == height:
		return mini(width, height) >= MINIMUM_CANVAS.x
	return width >= MINIMUM_CANVAS.x and height >= MINIMUM_CANVAS.y


func _validate_modular_demo_contract() -> void:
	var packed := ResourceLoader.load(DEMO_SCENE_PATH, "PackedScene") as PackedScene
	_check(packed != null, "pixel demo scene remains loadable")
	if packed == null:
		return
	var demo := packed.instantiate()
	_check(demo != null, "pixel demo scene instantiates for art-contract inspection")
	if demo == null:
		return
	root.add_child(demo)
	await process_frame
	var contract := demo.call("get_playable_contract") as Dictionary
	_check(bool(contract.get("playable", false)), "demo is gameplay rather than a static composition")
	_check(bool(contract.get("terrain_recomposable", false)), "demo declares its terrain recomposable from shared pieces")
	_check(bool(contract.get("terrain_modules_native_scale", false)), "terrain modules are drawn at native scale")
	_check((contract.get("terrain_vocabulary", []) as Array).size() == 6, "terrain atlas exposes six understandable reusable modules")
	_check(not bool(contract.get("background_resampling", true)), "backdrops use 1:1 source crops without resampling")
	demo.queue_free()
	await process_frame


func _validate_export_presets() -> void:
	var presets := ConfigFile.new()
	var load_error := presets.load("res://export_presets.cfg")
	_check(load_error == OK, "export preset configuration is readable")
	if load_error != OK:
		return

	var release_section := _find_preset_section(presets, "Windows Desktop")
	var demo_section := _find_preset_section(presets, "Pixel Demo Windows")
	_check(not release_section.is_empty(), "formal Windows export preset remains available")
	_check(not demo_section.is_empty(), "dedicated pixel-demo export preset remains available")
	if not release_section.is_empty():
		var release_features := _feature_tokens(String(presets.get_value(release_section, "custom_features", "")))
		_check(not release_features.has("pixel_demo"), "formal Windows preset never carries the pixel_demo feature")
	if not demo_section.is_empty():
		var demo_features := _feature_tokens(String(presets.get_value(demo_section, "custom_features", "")))
		_check(demo_features.has("pixel_demo"), "dedicated preset carries the pixel_demo custom feature")


func _find_preset_section(presets: ConfigFile, preset_name: String) -> String:
	for section in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if String(presets.get_value(section, "name", "")) == preset_name:
			return section
	return ""


func _feature_tokens(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_token in value.split(",", false):
		var token := raw_token.strip_edges()
		if not token.is_empty():
			result.append(token)
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_PIXEL_DEMO_HD_ART_2_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_PIXEL_DEMO_HD_ART_2_0: FAIL - %s" % ", ".join(_failures))
		quit(1)
