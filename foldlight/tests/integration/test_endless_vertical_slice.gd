extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/endless/endless_survival_slice.tscn") as PackedScene
	var slice := packed.instantiate() as FoldlightEndlessSliceRuntime if packed != null else null
	_check(slice != null, "standalone endless vertical slice scene loads")
	if slice == null:
		_finish()
		return
	root.add_child(slice)
	await process_frame
	await process_frame
	var snapshot := slice.get_slice_snapshot()
	var controller_snapshot := snapshot.get("controller", {}) as Dictionary
	_check(bool(controller_snapshot.get("active", false)), "standalone slice starts a live endless run")
	_check(Vector2(snapshot.get("player_position", Vector2.ZERO)).is_equal_approx(slice.controller.map_definition.player_spawn), "slice player starts at the authored harbor")
	_check(int(snapshot.get("enemy_count", 0)) > 0, "slice converts the first wave request into playable enemies")
	_check(slice.world.room_runtime.get_terrain_pieces().size() == slice.controller.map_definition.walls.size(), "slice converts fixed-map cover into shared 2.0 terrain")
	_check(slice.controller.map_runtime.get_node_or_null("AuthoredCoverCollision") == null, "slice disables the former parallel cover physics")
	_check(slice.camera.enabled, "slice owns an active camera for the large battlefield")
	_check(not slice.status_label.text.is_empty() and not slice.objective_label.text.is_empty(), "slice exposes live evolution and objective HUD text")
	_check(is_equal_approx(FoldlightEndlessSliceRuntime.DASH_COOLDOWN, 2.0), "slice preserves the formal two-second dash cooldown")
	slice.player.request_dash(Vector2.RIGHT)
	_check(slice.player.dash_component.dash_remaining > 0.0 and is_equal_approx(slice.player.dash_component.cooldown_remaining, 2.0), "slice dash is the actual 2.0 component with its two-second cooldown")

	# Exercise the playable capture/return loop without relying on brittle synthetic key events.
	slice.controller.report_projectiles_absorbed(24)
	var evolved := slice.controller.evolution.get_player_snapshot()
	_check(int(evolved.get("stage", 0)) == 1, "slice consumes the same absorption evolution API as the main integration")
	var route := slice.get_return_route_preview()
	_check(not route.is_empty(), "slice return shots always receive a cover-aware route")

	# Mission completion must pause action on a real three-choice evolution,
	# rather than silently auto-claiming the first option.
	slice.controller._on_objective_completed({"completion_count": 1, "title": "测试任务"})
	_check(slice._modal_kind == &"reward" and slice.modal_dim.visible, "mission completion opens a visible three-choice evolution")
	_check(slice._modal_options.size() == 3, "mission evolution presents exactly three authored rewards")
	slice._activate_modal_choice(0)
	_check(slice._modal_kind.is_empty() and slice.reward_toast.visible, "chosen mission evolution resumes play with explicit reward feedback")

	# Endless survival ends on death and offers restart/title; it must not
	# silently respawn forever like the former developer slice.
	for hit_index in slice.player.max_health:
		slice.player.invulnerability = 0.0
		slice.combat_runtime._try_hit_player(Vector2.RIGHT)
	_check(slice.run_ended and not slice.controller.active, "lethal damage ends the endless run instead of auto-respawning")
	_check(slice._modal_kind == &"game_over" and slice.modal_dim.visible, "defeat opens a complete result screen")
	_check(slice.modal_buttons[0].visible and slice.modal_buttons[1].visible, "result screen offers restart and title return")
	_check(slice.controller.visible and slice.controller.map_runtime.visible, "result screen preserves the authored battlefield behind its summary")

	slice.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDLIGHT_ENDLESS_VERTICAL_SLICE: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ENDLESS_VERTICAL_SLICE: FAIL - %s" % ", ".join(_failures))
		quit(1)
