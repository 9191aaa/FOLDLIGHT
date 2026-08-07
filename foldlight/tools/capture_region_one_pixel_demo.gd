extends SceneTree

const DEMO_SCENE: PackedScene = preload("res://scenes/demos/region_one_pixel_demo.tscn")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DEMO_SCENE == null:
		push_error("Region-one pixel demo scene is missing")
		quit(1)
		return
	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	await create_timer(0.12).timeout
	var output_dir := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var standard_error := root.get_texture().get_image().save_png(output_dir.path_join("region_one_pixel_standard.png"))
	demo.call("set_room_state", &"boss_room")
	await process_frame
	await process_frame
	var boss_error := root.get_texture().get_image().save_png(output_dir.path_join("region_one_pixel_boss.png"))
	print("CAPTURED REGION ONE PIXEL DEMO (%s, %s)" % [error_string(standard_error), error_string(boss_error)])
	demo.queue_free()
	await process_frame
	quit(0 if standard_error == OK and boss_error == OK else 1)
