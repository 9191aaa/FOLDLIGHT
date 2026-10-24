extends SceneTree

## GPU-only visual inspection of the real player scene. Run without --headless.
## The left moth is game size; the right is magnified to inspect the true centre.
const OUTPUT := "res://build/player-feedback"
const PLAYER := preload("res://scenes/player.tscn")
const THEME := preload("res://scripts/ui/foldlight_theme.gd")
var _stage: Node2D

class ReferenceBackdrop extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 840), Color("091923"))
		for x in range(60, 1440, 40):
			draw_line(Vector2(x, 130), Vector2(x, 720), Color("112d38"), 1.0)
		for y in range(140, 741, 40):
			draw_line(Vector2(60, y), Vector2(1380, y), Color("112d38"), 1.0)
		for center in [Vector2(380, 430), Vector2(1040, 430)]:
			draw_line(center + Vector2(-100, 0), center + Vector2(100, 0), Color(0.46, 0.84, 0.78, 0.18), 1.0)
			draw_line(center + Vector2(0, -130), center + Vector2(0, 130), Color(0.46, 0.84, 0.78, 0.18), 1.0)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 840)
	root.content_scale_size = Vector2i(1440, 840)
	_stage = Node2D.new()
	root.add_child(_stage)
	_stage.add_child(ReferenceBackdrop.new())
	var title := _label("", Vector2(60, 40), 31)
	_label("实际游戏尺寸", Vector2(285, 650), 24)
	_label("3× 细节检查", Vector2(950, 650), 24)
	_label("来袭方向：左侧    ·    十字线交点为真实碰撞中心，白点始终留在交点", Vector2(60, 760), 22)
	var players: Array[FoldlightPlayer] = []
	for index in 2:
		var player := PLAYER.instantiate() as FoldlightPlayer
		_stage.add_child(player)
		player.set_process(false)
		player.set_physics_process(false)
		players.append(player)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var states: Array[Dictionary] = [
		{"file": "impact", "title": "受击瞬间 · 0 ms", "elapsed": 0.0, "motion": 1.0},
		{"file": "120ms", "title": "短促反冲恢复 · 120 ms", "elapsed": 0.12, "motion": 1.0},
		{"file": "300ms", "title": "机体已稳定，伤色淡出 · 300 ms", "elapsed": 0.30, "motion": 1.0},
		{"file": "reduced_motion", "title": "关闭动态 · 仍保留伤色、来袭侧与保护状态", "elapsed": 0.0, "motion": 0.0},
	]
	for state in states:
		title.text = str(state.title)
		for index in players.size():
			var player := players[index]
			player.reset_player()
			player.configure_roguelite_combat(true)
			player.scale = Vector2.ONE * (3.0 if index == 1 else 1.0)
			player.global_position = Vector2(380 if index == 0 else 1040, 430)
			player.set_feedback_motion_scale(float(state.motion))
			player.set_play_enabled(true)
			player.take_hit(Vector2.RIGHT)
			# Advance real timer/visual methods to the inspection instant, then
			# hold that pose while the GPU draws it. No replacement moth artwork.
			player._physics_process(float(state.elapsed))
			player._process(float(state.elapsed))
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [OUTPUT, state.file]
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Player feedback capture failed: " + path)
			quit(1)
			return
		print("PLAYER_FEEDBACK_CAPTURE: " + ProjectSettings.globalize_path(path))
	_stage.queue_free()
	await process_frame
	var audio := root.get_node_or_null("AudioDirector") as FoldlightAudioDirector
	if audio != null:
		audio.shutdown()
	await process_frame
	quit(0)


func _label(value: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font", THEME.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", THEME.PAPER)
	_stage.add_child(label)
	return label
