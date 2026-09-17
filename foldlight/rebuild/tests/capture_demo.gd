extends SceneTree

var output: String = OS.get_environment("FOLDLIGHT_PREVIEW_DIR")

func _initialize() -> void:
	call_deferred("capture")

func save_frame(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(output.path_join(name))
	if error != OK:
		push_error("Preview image could not be saved")
		quit(1)

func capture() -> void:
	if output.is_empty():
		push_error("FOLDLIGHT_PREVIEW_DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var scene: PackedScene = load("res://rebuild/scenes/boss_lab.tscn")
	var lab := scene.instantiate() as FoldlightBossLab
	root.add_child(lab)
	await create_timer(0.5).timeout
	await save_frame("01_title.png")
	lab.start_voyage(&"normal")
	lab.player.set_debug_invincible(true)
	await create_timer(2.5).timeout
	lab.player.try_begin_fold()
	await create_timer(0.7).timeout
	await save_frame("02_voyage.png")
	lab.player.release_fold_action()
	lab.mode = FoldlightBossLab.Mode.REWARD
	paused = true
	lab.feedback.set_suspended(true)
	lab.ui.show_rewards(FoldlightDemoContent.REWARDS[0], 1)
	await save_frame("03_rewards.png")
	lab.start_boss(&"normal")
	lab.player.set_debug_invincible(true)
	await create_timer(2.6).timeout
	lab.player.try_begin_fold()
	await create_timer(1.1).timeout
	await save_frame("04_boss.png")
	lab.player.release_fold_action()
	await create_timer(0.08).timeout
	await save_frame("05_return.png")
	lab.show_title()
	lab.queue_free()
	await process_frame
	print("FOLDLIGHT_RENDER_PREVIEW_PASS")
	quit(0)
