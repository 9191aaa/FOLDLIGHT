extends SceneTree

## 3.0 room lifecycle contract: combat is a lockable, telegraphed, finite
## sequence. A clear is the only event that opens route exits.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/roguelite/room_runtime.tscn") as PackedScene
	var room := packed.instantiate() as FoldlightRoomRuntime if packed != null else null
	_check(room != null, "room runtime with encounter lifecycle loads")
	if room == null:
		_finish()
		return
	root.add_child(room)
	await process_frame
	var placements: Array[Dictionary] = [
		{"id": &"center_wall", "kind": FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, "position": Vector2(1440, 810), "size": Vector2(360, 100)},
	]
	_check(room.configure_room(&"flow_test", Vector2(2880, 1620), placements, Color(0.28, 0.84, 0.83)).is_empty(), "flow room accepts authored terrain")
	var exits: Array[Dictionary] = [
		{"id": &"west", "position": Vector2(10, 810), "normal": Vector2.LEFT, "width": 190.0},
		{"id": &"east", "position": Vector2(2870, 810), "normal": Vector2.RIGHT, "width": 190.0},
	]
	_check(room.configure_exits(exits).is_empty() and room.get_doors().size() == 2, "room authors two physical route exits")
	_check(room.get_solid_terrain_bounds().size() == 1, "room exposes solid bounds to safe-spawn composition")

	var lock_events: Array[bool] = []
	var telegraphs: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	var clears: Array[Dictionary] = []
	room.combat_lock_changed.connect(func(locked: bool) -> void: lock_events.append(locked))
	room.encounter_spawn_telegraph.connect(func(entry: Dictionary, _duration: float) -> void: telegraphs.append(entry))
	room.encounter_enemy_requested.connect(func(entry: Dictionary) -> void: spawns.append(entry))
	room.encounter_cleared.connect(func(performance: Dictionary) -> void: clears.append(performance))
	var plan := {
		"encounter_id": &"flow_contract",
		"errors": [],
		"entries": [
			{"enemy_id": &"paper_drifter", "wave": 0, "spawn_slot": &"g1", "spawn_position": Vector2(620, 320)},
			{"enemy_id": &"paper_turret", "wave": 0, "spawn_slot": &"t1", "spawn_position": Vector2(2640, 360)},
			{"enemy_id": &"paper_drifter", "wave": 1, "spawn_slot": &"g2", "spawn_position": Vector2(700, 1260)},
			{"enemy_id": &"reef_ram", "wave": 1, "spawn_slot": &"g3", "spawn_position": Vector2(2200, 1220)},
		],
	}
	_check(room.begin_encounter(plan).is_empty(), "valid encounter plan begins")
	_check(lock_events == [true] and room.get_doors().all(func(door: FoldlightRogueDoor) -> bool: return door.locked), "starting combat locks every route exit")
	_check(telegraphs.size() == 2 and spawns.is_empty(), "first wave telegraphs before any enemy becomes dangerous")
	room.advance_encounter(room.encounter_runtime.telegraph_duration + 0.01)
	_check(spawns.size() == 2 and room.encounter_runtime.active_enemy_count == 2, "first telegraph resolves to only the first wave")
	room.notify_enemy_defeated()
	_check(room.encounter_runtime.state == FoldlightRoomEncounterRuntime.State.TELEGRAPHING and clears.is_empty(), "one surviving enemy triggers an overlapping reinforcement warning")
	_check(telegraphs.size() == 4 and spawns.size() == 2, "second wave receives its warning while combat is still live")
	room.notify_enemy_defeated()
	_check(room.encounter_runtime.state == FoldlightRoomEncounterRuntime.State.TELEGRAPHING, "clearing survivors does not cancel an incoming reinforcement")
	room.advance_encounter(room.encounter_runtime.telegraph_duration + 0.01)
	_check(spawns.size() == 4 and room.encounter_runtime.active_enemy_count == 2, "second wave becomes active after warning")
	room.notify_enemy_defeated(2)
	_check(clears.size() == 1 and int(clears[0].get("defeated", 0)) == 4, "last defeat emits one complete performance snapshot")
	_check(lock_events == [true, false] and room.get_doors().all(func(door: FoldlightRogueDoor) -> bool: return not door.locked), "only encounter clear reopens route exits")
	_check(not room.begin_encounter({"entries": [], "errors": []}).is_empty(), "empty encounter plans cannot soft-lock a room")

	room.queue_free()
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
		print("FOLDLIGHT_ROOM_ENCOUNTER_FLOW_3_0: PASS")
		quit(0)
	else:
		print("FOLDLIGHT_ROOM_ENCOUNTER_FLOW_3_0: FAIL — %s" % ", ".join(_failures))
		quit(1)
