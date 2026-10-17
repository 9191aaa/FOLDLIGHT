extends SceneTree

const Cloud = preload("res://scripts/roguelite/enemies/miasma_cloud.gd")
const OUTPUT := "res://build/test-runtime/readability-318/quiet-projectiles.png"


class FixtureCanvas:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 900), Color("13252f"))
		var font := FoldlightTheme.body_font()
		draw_string(font, Vector2(48, 62), "弹幕辨识与瘴气边界", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("cfdbd6"))
		draw_string(font, Vector2(48, 96), "受控视觉样本：暖色敌弹、灰青友弹、淡金返光 · 保留轨迹与碰撞", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("91aaa9"))
		draw_line(Vector2(48, 124), Vector2(1392, 124), Color("385155"), 1.0)
		draw_line(Vector2(48, 570), Vector2(1392, 570), Color("385155"), 1.0)
		draw_string(font, Vector2(48, 612), "瘴纸游魂：虚线预告、实线生效，优先击杀源头消散", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("b9c4a4"))
		for index in 6:
			var rect := Rect2(64 + index * 235, 260 + (index % 2) * 85, 82, 36)
			draw_rect(rect, Color("203840"))
			draw_rect(rect, Color("496061"), false, 1.0)
		draw_string(font, Vector2(405, 872), "预告 · 尚不伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("b9c4a4"))
		draw_string(font, Vector2(870, 872), "生效 · 绕开边界", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("b9c4a4"))


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	var stage := FixtureCanvas.new()
	stage.z_index = -10
	root.add_child(stage)
	for row in 7:
		for column in 24:
			var bullet := FoldlightRogueProjectile.new()
			stage.add_child(bullet)
			var origin := Vector2(75 + column * 56, 174 + row * 52)
			bullet.configure({"origin": origin, "velocity": Vector2.from_angle(float(column) * 0.08 + row * 0.42) * 220.0,
				"hostile": true, "reflectable": column % 7 != 0, "kind": row % 3, "style": &"hostile_petal", "color": Color.MAGENTA})
			bullet.set_visual_preferences(false, false)
	var friendly_styles: Array[StringName] = [&"crease_petal", &"needle_orbit", &"returning_gull", &"prism_fan", &"sun_thread", &"tide_bell"]
	for column in 42:
		var bullet := FoldlightRogueProjectile.new()
		stage.add_child(bullet)
		bullet.configure({"origin": Vector2(80 + column * 31, 275 + sin(column * 0.35) * 85.0), "velocity": Vector2(650, -120),
			"hostile": false, "style": friendly_styles[column % friendly_styles.size()], "color": Color.MAGENTA})
	for column in 12:
		var bullet := FoldlightRogueProjectile.new()
		stage.add_child(bullet)
		bullet.configure({"origin": Vector2(45 + column * 103, 464), "velocity": Vector2(680, -130), "hostile": false, "style": &"return_light", "lifetime": 8.0})
		bullet.set_visual_preferences(false, false)
		for frame in 18:
			bullet.advance_simulation(1.0 / 120.0)
	var carrier := FoldlightRogueEnemyFactory.create(FoldlightRogueContentCatalog.enemy_by_id(&"miasma_wraith"), &"preview_miasma")
	stage.add_child(carrier)
	carrier.position = Vector2(190, 728)
	var warning := Cloud.new()
	stage.add_child(warning)
	warning.configure({"position": Vector2(490, 728), "source_id": &"preview_miasma"})
	for frame in 4:
		warning.advance_simulation(0.1)
	var active_cloud := Cloud.new()
	stage.add_child(active_cloud)
	active_cloud.configure({"position": Vector2(955, 728), "source_id": &"preview_miasma"})
	for frame in 12:
		active_cloud.advance_simulation(0.1)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var error := root.get_texture().get_image().save_png(OUTPUT)
	print("FOLDLIGHT_READABILITY_VISUAL_3_18: " + ("PASS" if error == OK else "FAIL"))
	stage.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	quit(0 if error == OK else 1)
