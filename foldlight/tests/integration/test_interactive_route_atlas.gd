extends SceneTree

var _failures := 0
var _departures: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	root.add_child(ui)
	await process_frame
	ui.route_chosen.connect(func(node_id: StringName) -> void: _departures.append(node_id))
	var region := {
		"id": "paper_reef", "title": "纸礁浅海", "cleared_node_ids": ["start"],
		"nodes": [
			{"id": "start", "depth": 0, "category": "entry", "risk": 1, "exits": ["reef", "haven"]},
			{"id": "reef", "depth": 1, "category": "combat", "risk": 2, "exits": ["boss"]},
			{"id": "haven", "depth": 1, "category": "rest", "risk": 1, "exits": ["boss"]},
			{"id": "boss", "depth": 2, "category": "boss", "risk": 4, "exits": []},
		],
	}
	var exits: Array[String] = ["reef", "haven"]
	ui.show_route(region, &"start", exits)
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	var atlas: Control = ui._route_atlas
	_check(atlas.is_visible_in_tree() and atlas.size.y >= 460.0, "route atlas has a dedicated exploration viewport")
	_check(root.gui_get_focus_owner() == ui._route_buttons[0], "opening the atlas retains controller launch focus")
	_check(ui._route_preview_title.text.contains("交锋房"), "focused destination updates its preview")
	_check(not ui._route_buttons[2].visible, "unused launch actions stay hidden")

	# Real viewport mouse events exercise Control clipping and hit testing.
	var haven: Vector2 = atlas.get_node_screen_position(&"haven")
	_mouse_button(atlas.global_position + haven, MOUSE_BUTTON_LEFT, true)
	_mouse_button(atlas.global_position + haven, MOUSE_BUTTON_LEFT, false)
	await process_frame
	_check(_departures.is_empty(), "clicking an island previews without starting a room")
	_check(ui._route_preview_title.text.contains("静水泊"), "click hit testing selects the intended branch")
	_check(root.gui_get_focus_owner() == ui._route_buttons[1], "mouse island selection and controller action stay synchronized")

	ui._on_atlas_node_selected(&"boss")
	_check(ui._route_preview_body.text.contains("仅可查看"), "a future island explains that it is only a preview")
	_check(root.gui_get_focus_owner() == null, "future inspection removes unrelated launch focus")
	_press(ui, &"fold")
	_check(_departures.is_empty(), "confirming a future preview cannot launch another destination")
	_press(ui, &"move_right")
	_check(root.gui_get_focus_owner() in ui._route_buttons, "direction input returns from exploration to reachable choices")

	var before: Dictionary = atlas.get_view_state()
	_mouse_button(atlas.global_position + atlas.size * 0.5, MOUSE_BUTTON_WHEEL_UP, true)
	await create_timer(0.3).timeout
	var after: Dictionary = atlas.get_view_state()
	_check(float(after.get("zoom", 1.0)) > float(before.get("zoom", 1.0)), "wheel input zooms the map")
	var drag_start := atlas.global_position + Vector2(100, 100)
	_mouse_button(drag_start, MOUSE_BUTTON_LEFT, true)
	var motion := InputEventMouseMotion.new()
	motion.position = drag_start + Vector2(120, 45)
	motion.relative = Vector2(120, 45)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	_mouse_button(motion.position, MOUSE_BUTTON_LEFT, false)
	await process_frame
	var dragged: Dictionary = atlas.get_view_state()
	_check(not Vector2(dragged.get("pan", Vector2.ZERO)).is_equal_approx(Vector2(after.get("pan", Vector2.ZERO))), "drag input pans the chart")
	_check(_departures.is_empty(), "dragging cannot accidentally depart")
	atlas.recenter()
	await create_timer(0.5).timeout
	var current: Vector2 = atlas.get_node_screen_position(&"start")
	_check(Rect2(Vector2.ZERO, atlas.size).has_point(current), "recenter brings the current island back into view")

	ui._on_route_pressed(ui._route_buttons[0])
	ui._on_route_pressed(ui._route_buttons[0])
	_check(_departures == [&"reef"], "rapid repeated confirmation emits one departure")
	ui.show_route(region, &"start", exits)
	await process_frame
	ui._on_route_pressed(ui._route_buttons[1])
	_check(_departures == [&"reef", &"haven"], "reopening the route resets its confirmation guard")
	ui.show_hud()
	ui._on_route_pressed(ui._route_buttons[0])
	_check(_departures.size() == 2, "hidden route controls cannot emit departures")
	ui.queue_free()
	await process_frame
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("Interactive route atlas: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _mouse_button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)


func _press(ui: FoldlightRoguePresentation, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	ui._unhandled_input(event)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
