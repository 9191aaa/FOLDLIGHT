extends SceneTree
const Slot = preload("res://scripts/components/active_item_slot.gd")
var _failures := 0
var _captures := false
var _selected: Array[StringName] = []
var _rewards: Array[StringName] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_captures = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.get_node("ProfileManager").persistence_enabled = false
	var ui := load("res://scenes/roguelite/ui/rogue_presentation.tscn").instantiate() as FoldlightRoguePresentation
	var player := load("res://scenes/player.tscn").instantiate() as FoldlightPlayer
	root.add_child(ui)
	root.add_child(player)
	await _settle()
	player.set_physics_process(false)
	player.configure_roguelite_combat(true)
	for definition in FoldlightRogueContentCatalog.ACTIVE_ITEMS:
		player.active_item_slot.acquire(definition)
		player.active_item_slot.cooldown_remaining = definition.cooldown * 0.6
	for definition in FoldlightRogueContentCatalog.WEAPONS:
		player.weapon_mount.equip(definition, 3)
	player.active_item_slot.select(&"paper_burst")
	ui.active_relic_selected.connect(func(id: StringName) -> void:
		_selected.append(id)
		player.active_item_slot.select(id)
		ui.set_active_inventory(player.get_active_inventory_snapshot()))
	ui.reward_chosen.connect(func(id: StringName) -> void: _rewards.append(id))
	ui.update_hud(player, {"room_count": 5}, {"category": &"combat"}, "纸礁浅海")
	ui.show_pause()
	_check(ui.open_active_collection(), "pause exposes the same skill collection")
	ui._active_collection._buttons[1].pressed.emit()
	_check(_selected.is_empty(), "opening input cannot immediately equip a different skill")
	_arm(ui._collection_input_guard)
	await _settle()
	_check(root.gui_get_focus_owner() == ui._active_collection._buttons[0], "the ready book gives keyboard focus to its first collected skill")
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	ui._handle_menu_input(right)
	await _settle()
	_check(root.gui_get_focus_owner() == ui._active_collection._buttons[1], "keyboard navigation stays inside the skill collection")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	ui._handle_menu_input(accept)
	_check(_selected.size() == 1 and player.active_item_slot.definition.content_id == _selected[0], "collection selection reaches the real slot")
	await _settle()
	_check(root.gui_get_focus_owner() == ui._active_collection._buttons[1] and ui._active_collection._detail_title.text.begins_with(player.active_item_slot.definition.title), "deferred focus after equipping preserves the selected skill and its detail")
	_check(ui._active_collection.entries.size() == 6 and player.get_active_inventory_snapshot().size() == 6, "switching preserves every collected skill")
	var cooldowns: Dictionary = player.active_item_slot.get_save_snapshot().active_item_cooldowns
	ui._active_collection._buttons[0].pressed.emit()
	_check(player.active_item_slot.get_save_snapshot().active_item_cooldowns == cooldowns, "switching through the book cannot reset independent cooldowns")
	await _settle()
	await _save("desktop-collection")
	ui.close_active_collection()
	await _settle()
	await _save("desktop-pause")
	# Reward screenshots use a valid partial collection; the three candidates
	# have not been acquired. The full book fixture is restored separately.
	var full_collection: Dictionary = player.active_item_slot.get_save_snapshot()
	player.active_item_slot.restore_collection({"active_item_ids": ["ink_wash", "tide_clock", "sun_stamp"], "active_item_id": "ink_wash", "active_item_cooldowns": cooldowns})
	ui.set_active_inventory(player.get_active_inventory_snapshot())
	var choices: Array[Dictionary] = [Slot.make_choice(&"paper_burst"), Slot.make_choice(&"crease_anchor"), Slot.make_choice(&"mirror_step")]
	ui.show_reward(choices, "技能补给")
	_check(not ui.open_active_collection(), "collection entry cannot bypass the original reward reading guard")
	_arm(ui._reward_input_guard)
	var draft := _draft(ui)
	var elapsed: float = ui._reward_input_guard._elapsed
	_check(ui.open_active_collection() and ui.screen_kind == &"reward", "friends can change skills inside rewards without gaining a pause state")
	_arm(ui._collection_input_guard)
	ui._active_collection._buttons[2].pressed.emit()
	ui._on_reward_pressed(ui._reward_buttons[0])
	_check(_rewards.is_empty() and not ui._reward_selection_locked, "the opaque book blocks the underlying reward cards")
	Input.action_press("move_right")
	ui.close_active_collection()
	for frame in 4: ui._process(0.1)
	_check(ui._collection_return_blocked and ui._reward_buttons[0].disabled, "held navigation input cannot spill into reward selection")
	Input.action_release("move_right")
	ui._process(0.1)
	ui._process(0.1)
	_check(not ui._collection_return_blocked and ui._reward_input_guard._elapsed == elapsed and _draft(ui) == draft and _rewards.is_empty(), "return restores the same draft and original guard without claiming anything")
	await _save("desktop-reward")
	var touch := root.get_node("TouchControls")
	touch._safe_insets = Vector4(80, 160, 56, 24)
	touch._set_touch_mode(true)
	root.size = Vector2i(844, 390)
	ui.show_reward(choices, "技能补给")
	_arm(ui._reward_input_guard)
	await _settle()
	for card in ui._reward_buttons:
		_check(_inside(card.get_global_rect()) and card.description_label.get_minimum_size().y <= card.description_label.size.y + 1, "phone reward card retains the complete skill description inside the safe viewport")
		_check(card.level_label.text.contains("冷却") and card._action_label.text.contains("收藏"), "skill reward states its real cooldown and collection action")
	_check(_inside(ui._reward_collection_button.get_global_rect()), "phone collection entry remains a full separate touch target")
	await _save("mobile-reward")
	player.active_item_slot.restore_collection(full_collection)
	ui.set_active_inventory(player.get_active_inventory_snapshot())
	ui.open_active_collection()
	var held := InputEventScreenTouch.new()
	held.index = 3
	held.pressed = true
	held.position = Vector2(1600, 900)
	root.push_input(held, true)
	_arm(ui._collection_input_guard)
	_check(not ui._collection_input_guard.can_select(), "a held real touch keeps newly opened skill buttons disarmed")
	held.pressed = false
	root.push_input(held, true)
	_arm(ui._collection_input_guard)
	for index in ui._active_collection.entries.size():
		ui._active_collection._preview(index)
		await _settle()
		var book := ui._active_collection
		_check(book._detail_body.get_minimum_size().y <= book._detail_body.size.y + 1 and not book._detail_body.get_global_rect().intersects(book._return.get_global_rect()), "all authored descriptions fit the phone book above its return target")
		_check(_inside(book._buttons[index].get_global_rect()) and book._buttons[index].size.y >= 120, "all six phone skill targets fit with the actual top inset")
	ui._active_collection._preview(0)
	await _save("mobile-collection")
	root.get_node("PlatformBridge")._dispatch_native_back()
	await _settle()
	_check(not ui.is_active_collection_open() and ui.screen_kind == &"reward" and _draft(ui) == draft, "Android Back closes only the skill book and preserves the reward")
	ui._process(0.1)
	ui._process(0.1)
	ui.open_active_collection()
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	ui._handle_menu_input(cancel)
	_check(not ui.is_active_collection_open() and ui.screen_kind == &"reward" and _draft(ui) == draft, "cancel during the opening guard closes only the skill book and keeps the required reward screen")
	ui.show_pause()
	await _settle()
	await _save("mobile-pause")
	ui.set_active_inventory([])
	ui.open_active_collection()
	_check(ui._active_collection.focus_buttons.size() == 1 and ui._active_collection._detail_title.text.contains("尚未获得"), "empty collection offers a clear explanation and a safe return")
	ui.show_hud()
	_check(not ui.is_active_collection_open() and not ui._collection_input_guard._active, "changing screens retires the overlay and its input guard")
	ui.queue_free()
	player.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	await process_frame
	print("ACTIVE_COLLECTION_UI: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)

func _draft(ui: FoldlightRoguePresentation) -> Array[StringName]:
	var ids: Array[StringName] = []
	for card in ui._reward_buttons: ids.append(StringName(card.get_meta("upgrade_id")))
	return ids

func _arm(guard: Node) -> void:
	for step in 14: guard._process(0.1)

func _inside(rect: Rect2) -> bool:
	return Rect2(0, 0, 1921, 1081).encloses(rect)

func _settle() -> void:
	for frame in 4: await process_frame

func _save(name: String) -> void:
	if not _captures: return
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build/test-runtime/active-ui/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func _check(value: bool, message: String) -> void:
	if value: print("PASS ", message)
	else:
		_failures += 1
		push_error("FAIL " + message)
