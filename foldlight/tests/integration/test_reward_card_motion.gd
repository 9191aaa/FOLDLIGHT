extends SceneTree

var _failures: Array[String] = []
var _chosen: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var packed := load("res://scenes/roguelite/ui/rogue_presentation.tscn") as PackedScene
	var ui := packed.instantiate() as FoldlightRoguePresentation if packed != null else null
	_check(ui != null, "animated reward presentation instantiates")
	if ui == null:
		_finish()
		return
	root.add_child(ui)
	await process_frame
	ui.reward_chosen.connect(func(id: StringName) -> void: _chosen.append(id))
	var choices: Array[Dictionary] = [
		{"content_id": &"tiny_silhouette", "title": "小纸身", "description": "缩小外观与命中体。", "rarity": 2, "next_level": 1, "maximum_level": 1},
		{"content_id": &"double_step", "title": "双页步", "description": "增加一次冲刺储能。", "rarity": 2, "next_level": 1, "maximum_level": 1},
		{"content_id": &"large_burden", "title": "巨页契", "description": "体型增大，提升武器伤害。", "rarity": 4, "next_level": 1, "maximum_level": 1},
	]
	ui.show_reward(choices, "纸礁浅海")
	# Drive the actual entrance Tweens on one shared clock. A cold headless
	# layout frame can exceed the whole animation and makes wall timers flaky.
	for card: FoldlightRewardCard in ui._reward_buttons:
		card._entrance_tween.pause()
	await process_frame
	var first: Button = ui._reward_buttons[0]
	var second: Button = ui._reward_buttons[1]
	var third: Button = ui._reward_buttons[2]
	_check(StringName(first.get_meta("upgrade_id")) == &"tiny_silhouette", "animated card preserves the upgrade ID metadata")
	_check(ui._reward_content[0]["title"].text == "小纸身", "legacy content references point to the rendered labels")
	_check(first.get_presentation_snapshot()["symbol"] != second.get_presentation_snapshot()["symbol"] and second.get_presentation_snapshot()["symbol"] != third.get_presentation_snapshot()["symbol"], "three upgrade identities receive distinct paper symbols")
	for card: FoldlightRewardCard in ui._reward_buttons:
		card._entrance_tween.custom_step(0.12)
	_check(float(first.get_presentation_snapshot()["reveal"]) > float(third.get_presentation_snapshot()["reveal"]), "reward cards enter in a staggered sequence")
	for card: FoldlightRewardCard in ui._reward_buttons:
		card._entrance_tween.custom_step(0.46)
	_check(is_equal_approx(float(third.get_presentation_snapshot()["reveal"]), 1.0), "all reward cards finish their entrance")
	await _wait_for_selection(ui)
	second.grab_focus()
	await create_timer(0.22).timeout
	_check(float(second.get_presentation_snapshot()["attention"]) > 0.99 and float(first.get_presentation_snapshot()["attention"]) < 0.01, "controller focus transfers the lifted highlight")
	var stable_bounds := second.get_global_rect()
	second.mouse_entered.emit()
	await create_timer(0.22).timeout
	_check(second.get_global_rect() == stable_bounds, "hover animation keeps the input target stable")

	first.pressed.emit()
	first.pressed.emit()
	second.pressed.emit()
	_check(_chosen.is_empty(), "selection waits for its visible confirmation")
	_check(first.disabled and second.disabled and third.disabled, "the first press locks every card immediately")
	await create_timer(0.28).timeout
	_check(_chosen == [&"tiny_silhouette"], "rapid repeated and cross-card presses apply exactly one reward")

	ui.show_reward(choices, "下一道折痕")
	await _wait_for_selection(ui)
	second.pressed.emit()
	ui.show_title({"prologue_complete": true})
	await create_timer(0.28).timeout
	_check(_chosen.size() == 1 and not second.is_processing(), "leaving the reward screen cancels pending confirmation and ambient animation")

	ui.show_reward(choices, "重新选择")
	await _wait_for_selection(ui)
	third.pressed.emit()
	ui.show_reward([choices[1]], "替换选择")
	await create_timer(0.28).timeout
	_check(_chosen.size() == 1, "replacing a draft cancels the previous pending reward")
	await _wait_for_selection(ui)
	_check(not second.visible and not third.visible and not first.disabled, "a new draft resets locking and hides unused cards")
	first.pressed.emit()
	await create_timer(0.28).timeout
	_check(_chosen == [&"tiny_silhouette", &"double_step"], "the following reward stage remains independently selectable")
	ui.show_reward(choices, "隐藏界面")
	await _wait_for_selection(ui)
	first.pressed.emit()
	ui.hide()
	await create_timer(0.28).timeout
	_check(_chosen.size() == 2 and not first.is_processing(), "hiding the whole presentation cancels pending selection")
	ui.show()
	var catalogue_fits := true
	var definitions: Array = []
	definitions.append_array(FoldlightRogueContentCatalog.UPGRADES)
	definitions.append_array(FoldlightRogueContentCatalog.WEAPONS)
	definitions.append_array(FoldlightRogueContentCatalog.ACTIVE_ITEMS)
	for definition in definitions:
		var kind := &"upgrade"
		if definition is FoldlightRogueWeaponDefinition:
			kind = &"weapon"
		elif definition is FoldlightRogueActiveItemDefinition:
			kind = &"active"
		ui.show_reward([{"content_id": definition.content_id, "title": definition.title, "description": definition.description, "choice_kind": kind, "offensive": true}], "真实内容排版")
		await process_frame
		var content: Dictionary = ui._reward_content[0]
		var title := content["title"] as Label
		var description := content["description"] as Label
		var rarity := content["rarity"] as Label
		var title_width := title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
		var rarity_width := rarity.get_theme_font("font").get_string_size(rarity.text, HORIZONTAL_ALIGNMENT_LEFT, -1, rarity.get_theme_font_size("font_size")).x
		catalogue_fits = catalogue_fits and title_width <= title.size.x and rarity_width <= rarity.size.x and description.position.y + description.size.y <= first.size.y - 78.0
	_check(catalogue_fits, "all actual upgrade, weapon and active-item text fits inside its card")
	ui.queue_free()
	await process_frame
	_finish()


func _wait_for_selection(ui: FoldlightRoguePresentation) -> void:
	for frame in 180:
		if not ui._reward_buttons[0].disabled:
			return
		await create_timer(0.02).timeout


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] " + description)
	else:
		_failures.append(description)
		push_error("[FAIL] " + description)


func _finish() -> void:
	print("FOLDLIGHT_REWARD_CARD_MOTION: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
