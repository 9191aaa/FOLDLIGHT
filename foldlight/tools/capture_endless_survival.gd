extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene
	var slice := packed.instantiate() as FoldlightEndlessSliceRuntime if packed != null else null
	if slice == null:
		push_error("Unable to instantiate endless survival slice")
		quit(1)
		return
	root.add_child(slice)
	await process_frame
	await process_frame
	# Build a representative live frame: several real waves, an active capture
	# objective and enough bullets to make the fold/cover relationship readable.
	slice.controller.force_next_wave()
	slice.controller.force_next_wave()
	slice.folding = true
	slice.fold_charge = 0.72
	for frame in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("rogue_endless.png")
	var gameplay_error := root.get_texture().get_image().save_png(output_path)
	print("CAPTURED %s (%s)" % [output_path, error_string(gameplay_error)])

	# Capture the real 3.9 reward modal as part of release visual QA so lane
	# labels, complete descriptions and controller focus cannot regress unseen.
	slice.controller._on_objective_completed({"completion_count": 1, "title": "航标校准"})
	await process_frame
	await RenderingServer.frame_post_draw
	var reward_path := output_dir.path_join("rogue_endless_reward.png")
	var reward_error := root.get_texture().get_image().save_png(reward_path)
	print("CAPTURED %s (%s)" % [reward_path, error_string(reward_error)])
	slice.queue_free()
	await process_frame
	quit(0 if gameplay_error == OK and reward_error == OK else 1)
