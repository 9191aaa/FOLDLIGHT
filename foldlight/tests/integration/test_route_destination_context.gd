extends SceneTree

const Preview = preload("res://scripts/roguelite/ui/route_preview_data.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first_context := {"room_count": 1, "active_item_id": "", "region_count": 3}
	for category: StringName in [&"forge", &"shop", &"rest", &"combat", &"elite"]:
		var node := {"id": "next", "category": category, "depth": 1, "risk": 2}
		var next := Preview.describe(node, first_context, true, 0)
		_check(next["reward_kind"] == &"first_active", "%s next room uses the actual second-clear active tutorial reward" % category)
		var future := Preview.describe(node, first_context, false, 0)
		_check(future["reward_kind"] != &"first_active", "%s future preview cannot promise a current-run conditional bonus" % category)
	var equipped := {"room_count": 1, "active_item_id": "paper_burst", "region_count": 3}
	_check(Preview.describe({"category": "forge"}, equipped, true, 0)["reward_kind"] == &"weapon", "forge offers a weapon when the first-active exception does not apply")
	_check(Preview.describe({"category": "shop"}, equipped, true, 0)["reward_kind"] == &"active", "shop offers an active item without implying currency trading")
	var rest := Preview.describe({"category": "rest"}, equipped, true, 0)
	_check(int(rest["waves"]) == 3 and str(rest["description"]).contains("不会自动回复灯芯"), "rest preview discloses actual combat and no automatic healing")
	var elite := Preview.describe({"category": "elite"}, equipped, true, 0)
	_check(int(elite["waves"]) == 4 and elite["reward_kind"] == &"upgrade" and not str(elite["reward"]).contains("稀有"), "elite communicates four waves without inventing rare rewards")
	var boss := Preview.describe({"category": "boss", "boss_id": "reef_crown_battery"}, first_context, true, 0)
	_check(boss["reward_kind"] == &"passage" and str(boss["title"]).contains("礁冠炮城"), "boss keeps its authored identity and passage reward despite second-clear context")
	_check(Preview.describe({"category": "boss"}, equipped, true, 2)["reward"] == "完成本次迷航", "final boss preview describes the real run completion")
	var generator := FoldlightRogueRouteGenerator.new()
	var route := generator.generate_route(52015, FoldlightRogueContentCatalog.REGIONS)
	var state := FoldlightRogueRunState.new()
	state.begin_run(52015, route)
	state.mark_room_cleared(state.current_node_id)
	state.health = 3
	state.max_health = 6
	state.glimmer = 27
	var controller := FoldlightRogueRunController.new()
	controller.run_state = state
	var session := FoldlightRogueSessionController.new()
	session.run_controller = controller
	session.profile_manager = root.get_node("ProfileManager")
	session.current_region_snapshot = (route["regions"] as Array)[0].duplicate(true)
	session._pending_reward_kinds = {"steady_lantern": &"upgrade"}
	session._pending_reward_sequence = [&"active"]
	var checkpoint := state.make_checkpoint()
	var region_before := session.current_region_snapshot.duplicate(true)
	seed(88401)
	var expected_random := randi()
	seed(88401)
	var a := session._route_view_snapshot()
	var b := session._route_view_snapshot()
	var actual_random := randi()
	_check(a == b and actual_random == expected_random, "repeated route previews are deterministic and consume no global random values")
	_check(state.make_checkpoint() == checkpoint and session.current_region_snapshot == region_before, "route context cannot modify route or checkpoint data")
	_check(session._pending_reward_kinds == {"steady_lantern": &"upgrade"} and session._pending_reward_sequence == [&"active"], "route preview leaves pending reward state intact")
	_check(a["context"]["health"] == 3 and a["context"]["max_health"] == 6 and a["context"]["glimmer"] == 27, "field note receives real health and glimmer values")
	a["context"]["health"] = 99
	a["cleared_node_ids"].clear()
	_check(state.health == 3 and state.cleared_node_ids.size() == 1, "presentation context and visited path are independent copies")
	var restored := FoldlightRogueRunState.new()
	_check(restored.restore_checkpoint(checkpoint), "existing checkpoint restores without a route schema change")
	controller.run_state = restored
	_check(session._route_view_snapshot() == b, "restored route reconstructs identical field-note context")
	session.free()
	controller.free()
	restored.free()
	state.free()
	generator.free()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	print("Route destination context: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
