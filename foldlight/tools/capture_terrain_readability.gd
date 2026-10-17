extends SceneTree

## GPU capture harness using the real room, player, effects, and HUD. Run with
## -- --baseline to render a saved old terrain subclass, or -- --quick for stills.
## APPDATA / LOCALAPPDATA must be isolated by the launching process.
const OUTPUT := "res://captures/terrain_readability"
const BASELINE_SCRIPT := "res://build/test-runtime/terrain-readability/baseline_terrain.gd"
const REGIONS: Array[StringName] = [&"paper_reef", &"ink_city", &"sun_court"]
const TITLES: Array[String] = ["纸礁浅海", "倒悬墨城", "日轮庭院"]
const ZONE_IDS: Array[StringName] = [&"sun", &"ink", &"thorn", &"current"]
const ZONE_NAMES: Array[String] = ["日纹 · 回息加速", "湿墨 · 回息减缓", "刺纸 · 触碰伤害", "潮流 · 定向推移"]
const KINDS: Array[int] = [FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH, FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL, FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER, FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE]
const CENTERS: Array[Vector2] = [Vector2(1110, 670), Vector2(1770, 670), Vector2(1110, 1040), Vector2(1770, 1040)]
const SIZES: Array[Vector2] = [Vector2(360, 190), Vector2(360, 190), Vector2(360, 170), Vector2(500, 130)]

var _world: FoldlightRogueWorld
var _player: FoldlightPlayer
var _hud: FoldlightRoguePresentation
var _baseline: bool = false
var _quick: bool = false
var _errors: int = 0
var _region_index: int = 0
var _records: Array[Dictionary] = []
var _baseline_script: GDScript


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	_baseline = OS.get_cmdline_user_args().has("--baseline")
	_quick = OS.get_cmdline_user_args().has("--quick")
	var profile := root.get_node("ProfileManager") as FoldlightProfileManager
	profile.persistence_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	if _baseline:
		if not FileAccess.file_exists(BASELINE_SCRIPT):
			push_error("Baseline requires the original terrain drawing subclass at " + BASELINE_SCRIPT)
			quit(1)
			return
		_baseline_script = load(BASELINE_SCRIPT) as GDScript
		if _baseline_script == null:
			quit(1)
			return
	_world = load("res://scenes/roguelite/rogue_world.tscn").instantiate() as FoldlightRogueWorld
	_player = load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	_hud = load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	root.add_child(_world)
	root.add_child(_player)
	root.add_child(_hud)
	await process_frame
	_player.configure_roguelite_combat(true)
	_player.set_play_enabled(true)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hud.show_hud()
	for region in REGIONS.size():
		_region_index = region
		await _load_region(REGIONS[region])
		await _position_player(Vector2(1440, 850), 0.7)
		_update_hud("地形观察  ·  晒纸 / 墨池 / 荆棘 / 潮流")
		await _save(String(REGIONS[region]) + "/overview")
		for zone in ZONE_IDS.size():
			var approach := CENTERS[zone] - Vector2(SIZES[zone].x * 0.5 + 54.0, 0)
			_reset_player_effects()
			await _position_player(approach, 0.65)
			_update_hud("接近  ·  " + ZONE_NAMES[zone])
			await _save("%s/%s_approach" % [REGIONS[region], ZONE_IDS[zone]], zone)
			await _position_player(CENTERS[zone] + Vector2(-44, 18), 0.24)
			_update_hud("进入  ·  " + ZONE_NAMES[zone])
			await _save("%s/%s_inside" % [REGIONS[region], ZONE_IDS[zone]], zone)
			if not _quick:
				await _capture_motion(zone, approach)
	if not _baseline and not _quick:
		await _capture_direction_checks()
	_world.queue_free()
	_player.queue_free()
	_hud.queue_free()
	await process_frame
	_world = null
	_player = null
	_hud = null
	if not _baseline and not _quick:
		await _capture_actual_room()
	var report := FileAccess.open(_output_dir().path_join("capture_report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"variant": "baseline" if _baseline else "after", "viewport": root.get_texture().get_size(), "captures": _records, "errors": _errors}, "\t"))
	report.close()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	await process_frame
	print("TERRAIN_READABILITY_CAPTURE: %s (%d images)" % ["PASS" if _errors == 0 else "FAIL", _records.size()])
	quit(0 if _errors == 0 else 1)


func _load_region(region: StringName) -> void:
	var placements: Array[Dictionary] = []
	for zone in ZONE_IDS.size():
		placements.append({"id": ZONE_IDS[zone], "kind": KINDS[zone], "position": CENTERS[zone], "size": SIZES[zone], "direction": Vector2.RIGHT, "strength": 1.0, "visual_style": region})
	placements.append({"id": &"cover_left", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(810, 740), "size": Vector2(80, 300), "visual_style": region})
	placements.append({"id": &"cover_top", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1450, 470), "size": Vector2(240, 64), "visual_style": region})
	placements.append({"id": &"prism", "kind": FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR, "position": Vector2(2200, 840), "size": Vector2(112, 112), "visual_style": region})
	var errors := _world.load_room(_player, StringName("terrain_" + String(region)), Vector2(2880, 1620), placements, FoldlightTheme.FOLD, 20261014, region)
	if not errors.is_empty():
		_errors += errors.size()
		push_error("Terrain QA room failed: " + ", ".join(errors))
	_world.activate()
	_world.combat_runtime.set_physics_process(false)
	_world.camera.target = null
	_world.camera.position = Vector2(1440, 810)
	_world.camera.zoom = Vector2.ONE
	_world.camera.set_process(false)
	_world.camera.force_update_scroll()
	var hint := _world.room_runtime.get_node_or_null("TerrainHint")
	if hint != null:
		hint.set_process(false)
	for piece in _world.room_runtime.get_terrain_pieces():
		if _baseline:
			var placement := {"id": piece.placement_id, "kind": piece.kind, "position": piece.position, "size": piece.piece_size, "rotation": piece.rotation, "strength": piece.effect_strength, "direction": piece.effect_direction, "visual_style": piece.visual_style}
			piece.queue_free()
			var baseline_piece := _baseline_script.new() as FoldlightTerrainPiece
			_world.room_runtime.terrain_container.add_child(baseline_piece)
			baseline_piece.configure(placement)
			baseline_piece.set_process(false)
		piece.set_process(false)
		piece._visual_time = 0.0
	_reset_player_effects()
	await physics_frame
	await process_frame


func _reset_player_effects() -> void:
	_player.status_effects.clear_all()
	_player.health = _player.max_health
	_player.focus = 0.55
	_player.invulnerability = 0.0
	_player.velocity = Vector2.ZERO
	_world.combat_runtime._terrain_hurt_remaining = 0.0


func _position_player(position: Vector2, seconds: float) -> void:
	_player.global_position = position
	_player.velocity = Vector2.ZERO
	_player.reset_physics_interpolation()
	# Allow the actual Area2D enter/exit signals to observe the new body pose.
	await physics_frame
	await physics_frame
	for tick in maxi(1, int(seconds * 60.0)):
		_advance(1.0 / 60.0)
	await process_frame


func _advance(delta: float) -> void:
	_player.status_effects.tick(delta)
	_player.invulnerability = maxf(0.0, _player.invulnerability - delta)
	_player._process(delta)
	_world.combat_runtime._update_temporary_effects(delta)
	_world.combat_runtime._update_terrain_effects(delta)
	for piece in _world.room_runtime.get_terrain_pieces():
		piece._process(delta)
	var hint := _world.room_runtime.get_node_or_null("TerrainHint")
	if hint != null and not _baseline:
		hint.call("_process", delta)


func _capture_motion(zone: int, approach: Vector2) -> void:
	_reset_player_effects()
	for frame in 12:
		var progress := float(frame) / 11.0
		var destination := CENTERS[zone] + Vector2(SIZES[zone].x * 0.5 + 54.0, 0)
		await _position_player(approach.lerp(destination, progress), 0.12)
		_update_hud("经过  ·  " + ZONE_NAMES[zone])
		await _save("%s/motion_%s/frame_%02d" % [REGIONS[_region_index], ZONE_IDS[zone], frame], zone)


func _capture_direction_checks() -> void:
	var current: FoldlightTerrainPiece
	for piece in _world.room_runtime.get_terrain_pieces():
		if piece.placement_id == &"current":
			current = piece
	if current == null:
		_errors += 1
		return
	var variants: Array[Dictionary] = [
		{"id": &"current", "kind": KINDS[3], "position": CENTERS[3], "size": Vector2(130, 340), "direction": Vector2.UP, "rotation": 0.0, "visual_style": &"sun_court"},
		{"id": &"current", "kind": KINDS[3], "position": CENTERS[3], "size": Vector2(440, 130), "direction": Vector2.RIGHT, "rotation": PI * 0.22, "visual_style": &"sun_court"},
	]
	for variant in variants.size():
		current.configure(variants[variant])
		_reset_player_effects()
		await _position_player(CENTERS[3] + Vector2(-36, -18), 0.6)
		_update_hud("潮流方向  ·  " + ("纵向上推" if variant == 0 else "旋转斜推"))
		await _save("direction/" + ("vertical" if variant == 0 else "rotated"), 3)


func _capture_actual_room() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as FoldlightGame
	root.add_child(game)
	await process_frame
	await process_frame
	var session := game.rogue_session
	session.persist_profile = false
	session.start_new_run()
	game.player.set_debug_invincible(true)
	_world = session.world
	_player = game.player
	_hud = session.presentation
	var combat := _world.combat_runtime
	for tick in 60:
		while session._mechanic_intro_active:
			session._on_mechanic_card_dismissed(session.presentation._mechanic_intro_content_id)
		await create_timer(0.12).timeout
		var hostile_count := combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile).size()
		if hostile_count >= 5 and not combat.enemies.is_empty():
			break
	await _save("live_generated_room")
	_records[-1]["enemy_count"] = combat.enemies.size()
	_records[-1]["hostile_projectiles"] = combat.projectiles.filter(func(projectile: FoldlightRogueProjectile) -> bool: return projectile.hostile).size()
	_records[-1]["debug_invincible"] = true
	if int(_records[-1]["hostile_projectiles"]) == 0:
		_errors += 1
		push_error("Live room capture did not contain hostile projectiles")
	game.queue_free()
	await process_frame
	_world = null
	_player = null
	_hud = null


func _update_hud(status: String) -> void:
	_hud.update_hud(_player, {"room_count": _region_index * 8 + 2, "glimmer": 18}, {"category": &"combat"}, TITLES[_region_index], status)


func _output_dir() -> String:
	return ProjectSettings.globalize_path(OUTPUT).path_join("baseline" if _baseline else "after")


func _save(filename: String, zone: int = -1) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := _output_dir().path_join(filename + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var captured := root.get_texture().get_image()
	var error := captured.save_png(path)
	if error != OK:
		_errors += 1
		push_error("Capture failed: " + path)
	var record := {"file": filename + ".png", "player_position": _player.global_position, "health": _player.health, "focus": _player.focus, "focus_regen_multiplier": _player.status_effects.get_focus_regen_multiplier(), "move_multiplier": _player.status_effects.get_move_multiplier(), "velocity": _player.velocity}
	var hint := _world.room_runtime.get_node_or_null("TerrainHint")
	if hint != null and hint.has_method("get_hint_snapshot"):
		record["hint"] = hint.call("get_hint_snapshot")
	if zone >= 0:
		for piece in _world.room_runtime.get_terrain_pieces():
			if piece.placement_id == ZONE_IDS[zone]:
				record["inside"] = piece.contains_world_point(_player.global_position)
				record["visual"] = piece.get_visual_signature()
				if piece.has_method("get_readability"):
					record["readability"] = piece.call("get_readability")
	_records.append(record)
	if not _baseline and filename == "paper_reef/overview":
		captured.save_jpg(ProjectSettings.globalize_path("res://../screenshots/terrain_readability.jpg"), 0.93)
	if not filename.contains("/motion_"):
		print("CAPTURED " + path)
