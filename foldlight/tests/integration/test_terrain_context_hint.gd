extends SceneTree

const KIND = FoldlightRogueTerrainDefinition.TerrainKind
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := (load("res://scenes/roguelite/rogue_world.tscn") as PackedScene).instantiate() as FoldlightRogueWorld
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FoldlightPlayer
	root.add_child(world)
	root.add_child(player)
	await process_frame
	player.configure_roguelite_combat(true)
	player.set_play_enabled(true)
	var placements: Array[Dictionary] = [
		{"id": &"rotated_ink", "kind": KIND.INK_POOL, "position": Vector2(520, 500), "size": Vector2(300, 180), "rotation": 0.45},
		{"id": &"sun", "kind": KIND.SUN_PATCH, "position": Vector2(1180, 500), "size": Vector2(300, 180)},
		{"id": &"current", "kind": KIND.CURRENT_LANE, "position": Vector2(520, 1100), "size": Vector2(320, 140), "rotation": -0.35},
		{"id": &"thorn", "kind": KIND.THORN_PAPER, "position": Vector2(1180, 1100), "size": Vector2(280, 140)},
	]
	_check(world.load_room(player, &"hint_room", Vector2(1920, 1620), placements, Color.WHITE).is_empty(), "terrain hint fixture uses valid separated real terrain")
	world.activate()
	var hint := world.room_runtime.get_node("TerrainHint") as Node2D
	for piece in world.room_runtime.get_terrain_pieces():
		player.global_position = piece.to_global(Vector2(piece.piece_size.x * 0.5 + 100.0, 0))
		await _frames(20)
		var nearby: Dictionary = hint.get_hint_snapshot()
		var semantic := piece.get_readability()
		_check(bool(nearby["visible"]) and nearby["placement_id"] == piece.placement_id and not bool(nearby["inside"]), "%s is explained before the player enters its real boundary" % piece.placement_id)
		_check(str(nearby["text"]).contains(str(semantic["label"])) and str(nearby["text"]).contains(str(semantic["detail"])), "%s uses the terrain's authoritative effect wording" % piece.placement_id)
		player.global_position = piece.global_position
		await _frames(10)
		var entered: Dictionary = hint.get_hint_snapshot()
		_check(bool(entered["inside"]) and entered["placement_id"] == piece.placement_id, "%s switches from approaching to inside without relying on an axis-aligned proxy" % piece.placement_id)
		_check(is_zero_approx(hint.global_rotation), "%s keeps its world label horizontal" % piece.placement_id)

	var ink := world.room_runtime.get_terrain_pieces()[0]
	player.global_position = ink.global_position
	await _frames(10)
	player.global_position = hint.global_position
	await _frames(10)
	_check(hint.global_position.distance_to(player.global_position) > 80.0, "label switches edges when its original anchor would cover the player")
	player.global_position = ink.to_global(Vector2(ink.piece_size.x * 0.5 + 155.0, 0))
	await _frames(24)
	_check(not bool(hint.get_hint_snapshot()["visible"]), "leaving the proximity range fades the label away")
	player.global_position = ink.global_position
	await _frames(2)
	var before_pause: Dictionary = hint.get_hint_snapshot()
	var terrain_time := ink._visual_time
	var terrain_presence := ink._presence
	player.suspend_for_overlay()
	world.combat_runtime.set_active(false)
	await _frames(20)
	var paused: Dictionary = hint.get_hint_snapshot()
	_check(not bool(paused["visible"]) and not bool(paused["active"]), "modal pause immediately hides the contextual label")
	_check(is_equal_approx(float(paused["alpha"]), float(before_pause["alpha"])) and is_equal_approx(float(paused["clock"]), float(before_pause["clock"])), "modal pause freezes fade progress and its clock")
	_check(is_equal_approx(ink._visual_time, terrain_time) and is_equal_approx(ink._presence, terrain_presence), "modal pause freezes moving ground textures and entry glow")
	player.resume_from_overlay()
	world.combat_runtime.set_active(true)
	await _frames(20)
	_check(bool(hint.get_hint_snapshot()["visible"]) and hint.get_hint_snapshot()["placement_id"] == ink.placement_id, "resuming combat restores the current terrain hint")
	_check(ink._visual_time > terrain_time and ink._presence >= terrain_presence, "resuming advances the ground animation and continues its entry response")

	var fold := InputEventAction.new()
	fold.action = &"fold"
	fold.pressed = true
	fold.strength = 1.0
	Input.parse_input_event(fold)
	await _frames(2)
	_check(player.folding, "a visible terrain label does not consume Fold input")
	var starting_position := player.global_position
	Input.action_press(&"move_right")
	await _frames(10)
	Input.action_release(&"move_right")
	_check(player.global_position.distance_to(starting_position) > 12.0, "a visible terrain label does not block movement or create collision")
	fold = InputEventAction.new()
	fold.action = &"fold"
	fold.pressed = false
	Input.parse_input_event(fold)
	player.velocity = Vector2.ZERO

	var priority_placements: Array[Dictionary] = [
		{"id": &"priority_ink", "kind": KIND.INK_POOL, "position": Vector2(800, 800), "size": Vector2(120, 100)},
		{"id": &"priority_thorn", "kind": KIND.THORN_PAPER, "position": Vector2(1000, 800), "size": Vector2(120, 100)},
	]
	world.load_room(player, &"hint_priority", Vector2(1920, 1620), priority_placements, Color.WHITE)
	world.activate()
	player.global_position = Vector2(700, 800)
	await _frames(20)
	_check(hint.get_hint_snapshot()["placement_id"] == &"priority_ink", "nearby debuff can become the stable current label")
	player.global_position = Vector2(900, 800)
	await _frames(20)
	_check(hint.get_hint_snapshot()["placement_id"] == &"priority_thorn", "nearby damage danger overrides a previous debuff despite hysteresis")
	player.global_position = Vector2(800, 800)
	await _frames(20)
	_check(hint.get_hint_snapshot()["placement_id"] == &"priority_ink" and bool(hint.get_hint_snapshot()["inside"]), "the occupied area takes precedence over a merely nearby hazard")

	var second_placements: Array[Dictionary] = [{"id": &"new_sun", "kind": KIND.SUN_PATCH, "position": Vector2(1450, 1150), "size": Vector2(260, 140)}]
	_check(world.load_room(player, &"hint_second", Vector2(1920, 1620), second_placements, Color.WHITE).is_empty(), "next room configures through the real world lifecycle")
	world.activate()
	var after_reload: Dictionary = hint.get_hint_snapshot()
	_check(StringName(after_reload["placement_id"]).is_empty() and is_zero_approx(float(after_reload["alpha"])), "room replacement clears the old label and fade immediately")
	await _frames(20)
	_check(not bool(hint.get_hint_snapshot()["visible"]), "a removed terrain piece cannot keep its hint alive")
	player.global_position = Vector2(1450, 1150)
	await _frames(20)
	_check(hint.get_hint_snapshot()["placement_id"] == &"new_sun" and bool(hint.get_hint_snapshot()["visible"]), "the next room reuses the label with its new terrain")
	world.queue_free()
	player.queue_free()
	await process_frame
	if _failures.is_empty():
		print("FOLDLIGHT_TERRAIN_CONTEXT_HINT: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_TERRAIN_CONTEXT_HINT: FAIL - %s" % ", ".join(_failures))
		quit(1)


func _frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
