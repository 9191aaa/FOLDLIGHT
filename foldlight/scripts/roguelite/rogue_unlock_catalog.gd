class_name FoldlightRogueUnlockCatalog
extends RefCounted

## Roguelite meta progression is horizontal only. It expands future draft and
## equipment pools; it never adds permanent damage, health, Fold, or dash stats.

const STARTER_WEAPONS: Array[String] = ["crease_lantern", "needle_orbit", "returning_gull"]
const STARTER_ACTIVE_ITEMS: Array[String] = ["paper_burst", "mirror_step", "ink_wash"]
const STARTER_UPGRADES: Array[String] = [
	"steady_lantern", "rapid_crease", "twin_fold",
	"wide_return", "quiet_hinge", "dense_fold",
	"swift_wing", "long_glide", "slipstream",
	"thick_paper", "calm_current", "tiny_silhouette",
]

const RULES: Array[Dictionary] = [
	{"collection": "unlocked_weapons", "id": "tide_bell", "runs": 1},
	{"collection": "unlocked_active_items", "id": "crease_anchor", "runs": 1},
	{"collection": "unlocked_upgrades", "ids": ["needle_eye", "luminous_pierce", "sixfold_memory", "crescent_field", "razor_wake", "phase_feather", "mend_on_clear", "ink_immunity"], "runs": 1},
	{"collection": "unlocked_weapons", "id": "prism_fan", "best_region": 2},
	{"collection": "unlocked_active_items", "id": "tide_clock", "best_region": 2},
	{"collection": "unlocked_upgrades", "ids": ["returning_edge", "prism_echo", "clean_crease", "mirror_tax", "foldstep", "quick_recovery", "glimmer_guard", "steady_heart"], "best_region": 2},
	{"collection": "unlocked_weapons", "id": "sun_thread", "runs": 3},
	{"collection": "unlocked_active_items", "id": "sun_stamp", "runs": 3},
	{"collection": "unlocked_upgrades", "ids": ["hunter_mark", "afterglow", "double_step", "kinetic_paper"], "runs": 3},
	{"collection": "unlocked_upgrades", "ids": ["paper_storm", "perfect_release", "last_lantern", "large_burden"], "best_region": 3},
]


static func apply_eligible(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["unlocked_weapons"] = _normalized_with_required(result.get("unlocked_weapons", []), STARTER_WEAPONS)
	result["unlocked_active_items"] = _normalized_with_required(result.get("unlocked_active_items", []), STARTER_ACTIVE_ITEMS)
	result["unlocked_upgrades"] = _normalized_with_required(result.get("unlocked_upgrades", []), STARTER_UPGRADES)
	var recent: Array[Dictionary] = []
	for rule in RULES:
		if not _rule_met(rule, result):
			continue
		var collection := String(rule.get("collection", ""))
		var entries: Array[String] = _normalized_with_required(result.get(collection, []), [])
		var ids: Array[String] = []
		if rule.has("id"):
			ids.append(String(rule.get("id", "")))
		var ids_variant: Variant = rule.get("ids", [])
		if ids_variant is Array:
			for id_variant: Variant in ids_variant:
				ids.append(String(id_variant))
		for content_id in ids:
			if content_id.is_empty() or entries.has(content_id):
				continue
			entries.append(content_id)
			recent.append({"collection": collection, "content_id": content_id})
		result[collection] = entries
	result["recent_unlocks"] = recent
	return result


static func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for weapon_id in _all_rule_ids("unlocked_weapons", STARTER_WEAPONS):
		if FoldlightRogueContentCatalog.weapon_by_id(StringName(weapon_id)) == null:
			errors.append("unlock schedule references unknown weapon %s" % weapon_id)
	for item_id in _all_rule_ids("unlocked_active_items", STARTER_ACTIVE_ITEMS):
		if FoldlightRogueContentCatalog.active_item_by_id(StringName(item_id)) == null:
			errors.append("unlock schedule references unknown active item %s" % item_id)
	for upgrade_id in _all_rule_ids("unlocked_upgrades", STARTER_UPGRADES):
		if FoldlightRogueContentCatalog.upgrade_by_id(StringName(upgrade_id)) == null:
			errors.append("unlock schedule references unknown upgrade %s" % upgrade_id)
	return errors


static func _rule_met(rule: Dictionary, snapshot: Dictionary) -> bool:
	return (
		int(snapshot.get("runs", 0)) >= int(rule.get("runs", 0))
		and int(snapshot.get("best_region", 0)) >= int(rule.get("best_region", 0))
		and int(snapshot.get("victories", 0)) >= int(rule.get("victories", 0))
	)


static func _normalized_with_required(source: Variant, required: Array[String]) -> Array[String]:
	var result: Array[String] = []
	if source is Array:
		for value: Variant in source:
			var key := String(value)
			if not key.is_empty() and not result.has(key):
				result.append(key)
	for key in required:
		if not result.has(key):
			result.append(key)
	return result


static func _all_rule_ids(collection: String, starters: Array[String]) -> Array[String]:
	var result := starters.duplicate()
	for rule in RULES:
		if String(rule.get("collection", "")) != collection:
			continue
		if rule.has("id"):
			var one := String(rule.get("id", ""))
			if not result.has(one):
				result.append(one)
		var ids_variant: Variant = rule.get("ids", [])
		if ids_variant is Array:
			for id_variant: Variant in ids_variant:
				var content_id := String(id_variant)
				if not result.has(content_id):
					result.append(content_id)
	return result
