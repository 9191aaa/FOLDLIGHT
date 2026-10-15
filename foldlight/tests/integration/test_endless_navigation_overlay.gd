extends SceneTree
const NAV = preload("res://scripts/endless/navigation_overlay.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var nav := NAV.new()
	layer.add_child(nav)
	await _settle()
	var data := {
		"map_id": &"offset_test", "map_title": "纸礁环湾", "layout_revision": 1, "combat_time": 22.0,
		"bounds": Rect2(-1200, 400, 6144, 4096), "player_position": Vector2(1872, 2448),
		"camera_rect": Rect2(1000, 1800, 1920, 1080),
		"obstacles": [Rect2(-700, 900, 300, 300), PackedVector2Array([Vector2(300, 700), Vector2(400, 700), Vector2(400, 900)])],
		"safe_corridors": [Rect2(1800, 400, 200, 4096)], "refuges": [Vector2(1900, 2000)],
		"zones": [
			{"id": &"one", "title": "西礁", "rect": Rect2(-1200, 400, 1900, 2000), "state": &"closed"},
			{"id": &"two", "title": "东礁", "rect": Rect2(3000, 400, 1900, 2000), "state": &"warning"},
			{"id": &"three", "title": "南礁", "rect": Rect2(-1200, 2600, 6144, 1800), "state": &"open"}],
		"objective": {"id": &"mission1", "kind": &"capture_point", "status": &"active", "title": "守住潮汐信标",
			"instruction": "进入金色信标范围持续驻守；离开后进度不再增加。", "progress": 4.5, "required": 10.0,
			"progress_text": "驻守 4.5 / 10 秒", "time_remaining": 42.1, "target_active": true, "target_position": Vector2(4600, 2448)},
		"danger": {"state": &"safe"},
	}
	var untouched := data.duplicate(true)
	nav.update_snapshot(data)
	await _settle()
	var state: Dictionary = nav.get_navigation_snapshot()
	check(data == untouched, "rendering never mutates the authoritative source snapshot")
	check(state.wall_count == 2 and state.zone_counts == {"open": 1, "warning": 1, "closed": 1}, "map includes actual rect/polygon obstacles and three distinct zone states")
	check((state.player_map_position as Vector2).is_equal_approx((state.chart_rect as Rect2).get_center()), "non-zero world origin and actual aspect ratio map the world center correctly")
	check(nav._map.project(data.bounds.position).is_equal_approx(nav._map.chart.position) and nav._map.project(data.bounds.end).is_equal_approx(nav._map.chart.end), "the entire true world bounds fit the minimap")
	var corridor_clear := true
	var safe_point: Vector2 = nav._map.project(Vector2(1900, 3000))
	for part: Rect2 in nav._map.zone_patches(nav._map.project_rect(Rect2(-1200, 2600, 6144, 1800))):
		if part.has_point(safe_point): corridor_clear = false
	check(corridor_clear, "always-open corridors remain clear in the rendered zone footprint")
	check(nav._danger.visible and state.indicator_mode == &"objective", "global closure warnings are visible without falsely directing a safe player to evacuate")
	check(state.progress_text == "驻守 4.5 / 10 秒" and state.time_text == "43 秒", "task progress and remaining time preserve the director's units")
	check(state.indicator_mode == &"objective" and state.indicator_direction.is_equal_approx(Vector2.RIGHT), "an actual offscreen objective points in its world direction")
	var cache := int(state.geometry_rebuilds)
	data.combat_time = 23.0
	data.player_position += Vector2(70, 0)
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().geometry_rebuilds == cache, "moving player and warnings reuse static obstacle geometry")
	data.layout_revision = 2
	data.obstacles.append(Rect2(3200, 3000, 400, 300))
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().geometry_rebuilds == cache + 1 and nav.get_navigation_snapshot().wall_count == 3, "a changed map revision rebuilds actual terrain once")
	data.objective.target_active = false
	data.objective.kind = &"clear_enemies"
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().indicator_mode == &"", "location-free tasks never invent a direction target")
	data.objective.target_active = true
	data.objective.target_position = Vector2(1800, 2200)
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().indicator_mode == &"", "an onscreen objective does not produce an unnecessary offscreen arrow")
	data.danger = {"state": &"closed", "message": "西礁已封闭，区域会扣血。请沿青色方向回到开放通路。", "safe_position": Vector2(1872, 4000), "seconds_remaining": 10.0}
	nav.update_snapshot(data)
	state = nav.get_navigation_snapshot()
	check(state.indicator_mode == &"safe" and state.indicator_direction.y > 0.9 and state.danger_text.contains("扣血"), "closed-zone escape takes priority over mission guidance and states its real consequence")
	data.objective.status = &"failed"
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().task_title.begins_with("未达成") and nav.get_navigation_snapshot().time_text == "未达成", "failed tasks visibly stop showing an active countdown")
	data.objective.status = &"completed"
	nav.update_snapshot(data)
	check(nav.get_navigation_snapshot().task_title.begins_with("完成"), "successful tasks have a distinct completion state")
	check(_inside(nav._map.get_global_rect()) and not nav._map.get_global_rect().intersects(nav._task.get_global_rect()), "desktop map and task card fit without overlapping")
	nav.set_touch_layout(true, 184)
	await _settle()
	state = nav.get_navigation_snapshot()
	var mobile_map: Rect2 = state.map_rect
	check(mobile_map.size.x >= 120 and mobile_map.size.y >= 120, "the mobile map is a full touch target at actual phone scale")
	check(_thumbs_clear(mobile_map) and _thumbs_clear(state.task_rect), "compact navigation leaves both mobile thumb regions free")
	check(not nav._task.get_global_rect().intersects(Rect2(1756, 184, 120, 120)), "mobile task details cannot cover the pause button")
	var event := InputEventScreenTouch.new()
	event.index = 4
	event.position = mobile_map.get_center()
	event.pressed = true
	root.push_input(event, true)
	await _settle()
	state = nav.get_navigation_snapshot()
	check(state.expanded and not paused, "a real raw touch opens the larger map without pausing the game or race")
	check(_thumbs_clear(state.map_rect) and _inside(state.map_rect) and not (state.map_rect as Rect2).intersects(state.task_rect), "expanded mobile map stays between controls and below the task card")
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = (state.map_rect as Rect2).get_center()
	root.push_input(mouse, true)
	check(nav.get_navigation_snapshot().expanded, "the touch's emulated mouse does not immediately close the map")
	event.pressed = false
	root.push_input(event, true)
	nav.set_hud_visible(false)
	check(not nav.visible and not nav.get_navigation_snapshot().expanded, "reward and pause transitions hide and collapse navigation immediately")
	nav.update_snapshot(data)
	check(not nav.visible, "late HUD data cannot expose navigation over a modal")
	nav.set_hud_visible(true)
	check(nav.visible and not nav.get_navigation_snapshot().expanded, "returning to combat restores only the compact map")
	event.position = nav._map.get_global_rect().get_center()
	event.pressed = true
	event.canceled = true
	root.push_input(event, true)
	check(not nav.get_navigation_snapshot().expanded, "a canceled finger cannot open the map")
	nav.set_touch_layout(false)
	await _settle()
	check(nav.get_navigation_snapshot().map_rect == Rect2(1510, 150, 366, 245), "desktop geometry is restored exactly after the mobile layout")
	nav.update_snapshot({"bounds": Rect2()})
	check(not nav.visible, "missing world geometry hides the map instead of dividing by zero")
	layer.queue_free()
	await process_frame
	await _shared_presentation_layout(data)
	print("ENDLESS_NAVIGATION_OVERLAY: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _shared_presentation_layout(data: Dictionary) -> void:
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(ui)
	root.add_child(player)
	player.set_physics_process(false)
	player.set_play_enabled(false)
	var attached := NAV.new()
	ui.attach_navigation_overlay(attached)
	ui.show_hud()
	var context := {"objective_title": "守住潮汐信标", "objective_detail": "驻守 4.5 / 10 秒", "objective_progress": 0.45, "endless_navigation": true}
	ui.update_hud(player, {}, {}, "纸礁环湾", "第 2 波", {}, context)
	attached.update_snapshot(data)
	await _settle()
	check(not ui._hud_objective.visible and not ui._hud_objective_detail.visible and not ui._hud_objective_bar.visible, "the endless adapter removes the old duplicate task block from shared desktop HUD")
	check(ui._hud_objective.text == context.objective_title and is_equal_approx(ui._hud_objective_bar.value, 45.0), "hidden legacy task data remains available to existing adapters")
	check(ui.get_endless_navigation_snapshot().map_title == "纸礁环湾", "the public presentation inspector exposes the mounted real navigation snapshot")
	var touch := root.get_node("TouchControls")
	var previous_insets: Vector4 = touch._safe_insets
	touch._safe_insets = Vector4(0, 160, 0, 0)
	touch._set_touch_mode(true)
	touch.layout_changed.emit()
	ui.update_hud(player, {}, {}, "纸礁环湾", "第 2 波", {}, context)
	await _settle()
	var state := ui.get_endless_navigation_snapshot()
	check(state.mobile and not ui._mobile_hud.objective.visible, "the same navigation owns mobile task guidance without a second task label")
	check((state.map_rect as Rect2).position.y >= 184 and not (state.task_rect as Rect2).intersects(ui._mobile_hud.pause_button.get_global_rect()), "shared phone layout forwards the host safe area and leaves its actual pause button clear")
	touch._safe_insets = Vector4(0, 190, 0, 0)
	touch.layout_changed.emit()
	await _settle()
	var moved := ui.get_endless_navigation_snapshot()
	check(is_equal_approx((moved.map_rect as Rect2).position.y - (state.map_rect as Rect2).position.y, 30.0), "changing the actual host safe inset reflows the attached navigation once")
	var owned: WeakRef = weakref(attached)
	ui.queue_free()
	player.queue_free()
	await _settle()
	check(owned.get_ref() == null, "the shared presentation releases its mounted navigation on scene teardown")
	touch._safe_insets = previous_insets
	touch._set_touch_mode(false)

func _inside(rect: Rect2) -> bool:
	return Rect2(0, 0, 1920, 1080).encloses(rect)

func _thumbs_clear(rect: Rect2) -> bool:
	return not rect.intersects(Rect2(0, 570, 580, 510)) and not rect.intersects(Rect2(1320, 510, 600, 570))

func _settle() -> void:
	for frame in 3: await process_frame

func check(ok: bool, message: String) -> void:
	if ok: print("PASS " + message)
	else:
		failures += 1
		push_error("FAIL " + message)
