extends SceneTree

var _failures: Array[String] = []
var _uses: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	var slot := FoldlightActiveItemSlot.new()
	root.add_child(slot)
	slot.enabled = true
	slot.item_used.connect(func(item: FoldlightRogueActiveItemDefinition) -> void: _uses.append(item.content_id))
	var burst := FoldlightRogueContentCatalog.active_item_by_id(&"paper_burst")
	var mirror := FoldlightRogueContentCatalog.active_item_by_id(&"mirror_step")
	_check(slot.equip(burst) and slot.request_use(), "starter skill fires normally through the compatibility API")
	var burst_duration := burst.cooldown
	_check(slot.replace(mirror) == burst and slot.get_inventory_snapshot().size() == 2, "acquiring a new skill retains the previous one while equipping only the new skill")
	_check(slot.request_use() and _uses == [&"paper_burst", &"mirror_step"], "one request releases only the currently equipped skill")
	slot.tick(1.25)
	_check(slot.select(&"paper_burst") and is_equal_approx(slot.cooldown_remaining, burst_duration - 1.25) and not slot.request_use(), "switching away and back preserves a recovering skill's own cooldown")
	slot.equip(burst)
	_check(is_equal_approx(slot.cooldown_remaining, burst_duration - 1.25), "duplicate equip cannot refresh a used skill")
	_check(not slot.select(&"ink_wash") and slot.definition == burst, "selection cannot acquire an unowned catalog skill")
	var before_invalid := slot.get_save_snapshot()
	slot.tick(-2.0)
	slot.tick(NAN)
	slot.enabled = false
	slot.tick(3.0)
	_check(slot.get_save_snapshot() == before_invalid, "disabled and invalid ticks cannot advance independent cooldowns")
	slot.enabled = true
	slot.definition = mirror
	slot.cooldown_remaining = 2.75
	_check(slot.get_inventory_snapshot().size() == 2 and is_equal_approx(slot.cooldown_remaining, 2.75), "legacy direct properties remain writable without losing the collection")
	var independent := slot.get_save_snapshot()
	(independent["active_item_cooldowns"] as Dictionary)["mirror_step"] = 0.0
	_check(is_equal_approx(slot.cooldown_remaining, 2.75) and burst.cooldown == burst_duration, "snapshot mutation cannot alter live cooldowns or shared definitions")

	var state := FoldlightRogueRunState.new()
	state.begin_run(315315, {"regions": [{"start_id": "r1_start"}]})
	state.acquire_weapon(&"needle_orbit")
	state.acquire_weapon(&"needle_orbit")
	state.set_active_collection(slot.get_save_snapshot())
	var saved := state.make_checkpoint()
	var restored := FoldlightRogueRunState.new()
	_check(restored.restore_checkpoint(JSON.parse_string(JSON.stringify(saved))), "collection checkpoint survives the real JSON representation")
	var recovered_slot := FoldlightActiveItemSlot.new()
	recovered_slot.restore_collection(restored.get_active_collection())
	_check(int(saved.version) == 3 and recovered_slot.get_save_snapshot() == slot.get_save_snapshot(), "v3 restores equipped skill and every independent remaining cooldown")
	_check(restored.weapon_levels == state.weapon_levels, "active collection migration preserves ranked weapons")
	for version in [1, 2]:
		var legacy := saved.duplicate(true)
		legacy["version"] = version
		legacy["active_item_id"] = "ink_wash"
		_check(restored.restore_checkpoint(legacy) and restored.active_item_ids == [&"ink_wash"] and restored.active_item_id == &"ink_wash" and restored.active_item_cooldowns == {"ink_wash": 0.0}, "v%d migrates only its previously equipped skill" % version)
		_check(restored.get_weapon_level(&"needle_orbit") == (1 if version == 1 else 2), "v%d keeps its existing weapon migration contract" % version)
		legacy["active_item_id"] = {"malformed": []}
		_check(restored.restore_checkpoint(legacy) and restored.active_item_ids.is_empty(), "v%d malformed legacy skill data is ignored safely" % version)
	var malformed := saved.duplicate(true)
	malformed["active_item_ids"] = ["paper_burst", "paper_burst", "mirror_step", "unknown", {}, 12]
	malformed["active_item_id"] = []
	malformed["active_item_cooldowns"] = {"paper_burst": 999.0, "mirror_step": NAN, "unknown": 15}
	_check(restored.restore_checkpoint(malformed) and restored.active_item_ids == [&"paper_burst", &"mirror_step"] and restored.active_item_id == &"paper_burst", "malformed v3 IDs deduplicate and select a valid collected fallback")
	_check(is_equal_approx(float(restored.active_item_cooldowns.paper_burst), burst.cooldown) and float(restored.active_item_cooldowns.mirror_step) == 0.0, "invalid and oversized cooldowns sanitize without changing resources")
	_check(not restored.acquire_active_item(&"paper_burst") and not restored.select_active_item(&"unknown"), "state rejects duplicate acquisition and unknown equipment")
	state.begin_run(315316, {"regions": [{"start_id": "r1_start"}]})
	slot.unequip()
	_check(state.active_item_ids.is_empty() and state.active_item_cooldowns.is_empty() and slot.definition == null and slot.get_inventory_snapshot().is_empty(), "new run and explicit reset clear all prior skills and cooldowns")

	state.free()
	restored.free()
	recovered_slot.free()
	slot.queue_free()
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	await process_frame
	print("FOLDLIGHT_ACTIVE_COLLECTION_3_15: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures.append(label)
		push_error("[FAIL] %s" % label)
