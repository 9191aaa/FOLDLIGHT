extends SceneTree

const DEMO_SCENE: PackedScene = preload("res://scenes/demos/pixel_playable_demo.tscn")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1254, 705)
	var game := DEMO_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	game.set("tutorial_time", 0.0)
	game.set("player_invulnerability", 99.0)
	await create_timer(1.35).timeout
	var output_dir := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var room_one_image := root.get_texture().get_image().get_region(Rect2i(0, 0, 1254, 705))
	var room_one_error := room_one_image.save_png(output_dir.path_join("pixel_playable_room_one.png"))

	game.call("start_boss_room")
	await process_frame
	await physics_frame
	game.call("debug_set_boss_health_ratio", 0.2)
	game.set("tutorial_time", 0.0)
	game.set("player_invulnerability", 99.0)
	await create_timer(1.15).timeout
	var boss_image := root.get_texture().get_image().get_region(Rect2i(0, 0, 1254, 705))
	var boss_error := boss_image.save_png(output_dir.path_join("pixel_playable_boss.png"))
	print("CAPTURED PIXEL PLAYABLE DEMO (%s, %s)" % [error_string(room_one_error), error_string(boss_error)])
	game.queue_free()
	await process_frame
	quit(0 if room_one_error == OK and boss_error == OK else 1)
