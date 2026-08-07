class_name FoldlightRogueRunController
extends Node

signal run_started(snapshot: Dictionary)
signal room_requested(room_node: Dictionary, region_snapshot: Dictionary)
signal room_cleared(room_node: Dictionary, performance: Dictionary)
signal checkpoint_ready(snapshot: Dictionary)
signal route_choice_requested(exits: Array[String])
signal run_finished(result: Dictionary)

enum Phase { INACTIVE, ENTERING_ROOM, COMBAT, REWARD, ROUTE_CHOICE, FINISHED }

var phase: Phase = Phase.INACTIVE

@onready var route_generator: FoldlightRogueRouteGenerator = $RouteGenerator
@onready var run_state: FoldlightRogueRunState = $RunState


func start_new_run(seed: int = 0) -> Dictionary:
	var resolved_seed := seed if seed != 0 else int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	var errors := FoldlightRogueContentCatalog.validation_errors()
	if not errors.is_empty():
		push_error("RogueRunController: invalid content — %s" % "; ".join(errors))
		return {}
	var route := route_generator.generate_route(resolved_seed, FoldlightRogueContentCatalog.REGIONS)
	run_state.begin_run(resolved_seed, route)
	phase = Phase.ENTERING_ROOM
	var snapshot := run_state.make_checkpoint()
	run_started.emit(snapshot)
	_request_current_room()
	return snapshot


func restore_run(checkpoint: Dictionary) -> bool:
	if not run_state.restore_checkpoint(checkpoint):
		return false
	var session_phase := StringName(checkpoint.get("session_phase", &"room"))
	match session_phase:
		&"reward": phase = Phase.REWARD
		&"route": phase = Phase.ROUTE_CHOICE
		_: phase = Phase.ENTERING_ROOM
	run_started.emit(run_state.make_checkpoint())
	if phase == Phase.ENTERING_ROOM:
		_request_current_room()
	return true


func begin_combat() -> void:
	if phase == Phase.ENTERING_ROOM:
		phase = Phase.COMBAT


func complete_room(performance: Dictionary = {}) -> void:
	if phase != Phase.COMBAT:
		return
	var room_node := get_current_room_node()
	if room_node.is_empty():
		return
	run_state.mark_room_cleared(run_state.current_node_id)
	room_cleared.emit(room_node.duplicate(true), performance.duplicate(true))
	var category := StringName(room_node.get("category", &""))
	if category == &"boss":
		_advance_after_boss()
		return
	phase = Phase.REWARD
	checkpoint_ready.emit(_checkpoint_for(&"reward"))


func fail_run(reason: StringName = &"lantern_extinguished") -> Dictionary:
	if phase in [Phase.INACTIVE, Phase.FINISHED]:
		return {}
	phase = Phase.FINISHED
	var result := {
		"won": false,
		"reason": reason,
		"seed": run_state.seed,
		"time": run_state.elapsed,
		"rooms": run_state.room_count,
		"region": run_state.current_region + 1,
		"pressure": 0,
		"glimmer": run_state.glimmer,
	}
	run_finished.emit(result.duplicate(true))
	return result


func open_route_choice() -> void:
	if phase != Phase.REWARD:
		return
	var room_node := get_current_room_node()
	var exits := _string_array(room_node.get("exits", []))
	phase = Phase.ROUTE_CHOICE
	checkpoint_ready.emit(_checkpoint_for(&"route"))
	route_choice_requested.emit(exits)


func choose_exit(destination_id: StringName) -> bool:
	if phase != Phase.ROUTE_CHOICE:
		return false
	var room_node := get_current_room_node()
	var exits := _string_array(room_node.get("exits", []))
	if not exits.has(String(destination_id)):
		return false
	run_state.current_node_id = destination_id
	phase = Phase.ENTERING_ROOM
	checkpoint_ready.emit(_checkpoint_for(&"room"))
	_request_current_room()
	return true


func get_current_room_node() -> Dictionary:
	var region := _current_region_snapshot()
	var nodes_variant: Variant = region.get("nodes", [])
	if nodes_variant is Array:
		for node_variant: Variant in nodes_variant:
			if node_variant is Dictionary and StringName((node_variant as Dictionary).get("id", &"")) == run_state.current_node_id:
				return (node_variant as Dictionary).duplicate(true)
	return {}


func _request_current_room() -> void:
	var region := _current_region_snapshot()
	var room_node := get_current_room_node()
	if region.is_empty() or room_node.is_empty():
		push_error("RogueRunController: route points to a missing room")
		return
	room_requested.emit(room_node, region)


func _advance_after_boss() -> void:
	if run_state.current_region >= FoldlightRogueContentCatalog.REGIONS.size() - 1:
		phase = Phase.FINISHED
		var result := {
			"won": true,
			"seed": run_state.seed,
			"time": run_state.elapsed,
			"rooms": run_state.room_count,
			"region": 3,
			"pressure": 0,
		}
		run_finished.emit(result)
		return
	run_state.current_region += 1
	var next_region := _current_region_snapshot()
	run_state.current_node_id = StringName(next_region.get("start_id", &""))
	phase = Phase.ENTERING_ROOM
	checkpoint_ready.emit(_checkpoint_for(&"room"))
	_request_current_room()


func _current_region_snapshot() -> Dictionary:
	var regions_variant: Variant = run_state.route.get("regions", [])
	if not regions_variant is Array:
		return {}
	var regions := regions_variant as Array
	if run_state.current_region < 0 or run_state.current_region >= regions.size():
		return {}
	var region_variant: Variant = regions[run_state.current_region]
	return (region_variant as Dictionary).duplicate(true) if region_variant is Dictionary else {}


func get_current_region_snapshot() -> Dictionary:
	return _current_region_snapshot()


func _checkpoint_for(session_phase: StringName) -> Dictionary:
	var snapshot := run_state.make_checkpoint()
	snapshot["session_phase"] = String(session_phase)
	return snapshot


func _string_array(source: Variant) -> Array[String]:
	var result: Array[String] = []
	if source is Array:
		for value: Variant in source:
			result.append(String(value))
	return result
