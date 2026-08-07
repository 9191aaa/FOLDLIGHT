class_name FoldlightRogueContentCatalog

const REGIONS: Array[FoldlightRogueRegionDefinition] = [
	preload("res://resources/roguelite/regions/paper_reef.tres"),
	preload("res://resources/roguelite/regions/inverted_ink_city.tres"),
	preload("res://resources/roguelite/regions/nameless_sun_court.tres"),
]

const WEAPONS: Array[FoldlightRogueWeaponDefinition] = [
	preload("res://resources/roguelite/weapons/crease_lantern.tres"),
	preload("res://resources/roguelite/weapons/needle_orbit.tres"),
	preload("res://resources/roguelite/weapons/returning_gull.tres"),
	preload("res://resources/roguelite/weapons/tide_bell.tres"),
	preload("res://resources/roguelite/weapons/prism_fan.tres"),
	preload("res://resources/roguelite/weapons/sun_thread.tres"),
]

const ACTIVE_ITEMS: Array[FoldlightRogueActiveItemDefinition] = [
	preload("res://resources/roguelite/active_items/paper_burst.tres"),
	preload("res://resources/roguelite/active_items/mirror_step.tres"),
	preload("res://resources/roguelite/active_items/ink_wash.tres"),
	preload("res://resources/roguelite/active_items/crease_anchor.tres"),
	preload("res://resources/roguelite/active_items/tide_clock.tres"),
	preload("res://resources/roguelite/active_items/sun_stamp.tres"),
]

const ENEMIES: Array[FoldlightRogueEnemyDefinition] = [
	# The shipped 2.0 roster is the ordinary combat foundation.
	preload("res://resources/roguelite/enemies/drifter.tres"),
	preload("res://resources/roguelite/enemies/fan.tres"),
	preload("res://resources/roguelite/enemies/weaver.tres"),
	preload("res://resources/roguelite/enemies/ram.tres"),
	preload("res://resources/roguelite/enemies/bloomer.tres"),
	preload("res://resources/roguelite/enemies/leech.tres"),
	preload("res://resources/roguelite/enemies/mirror.tres"),
	preload("res://resources/roguelite/enemies/rewinder.tres"),
	# Compatibility aliases remain loadable for old room saves and tests, but
	# authored encounters no longer substitute them for the original roster.
	preload("res://resources/roguelite/enemies/paper_drifter.tres"),
	preload("res://resources/roguelite/enemies/needle_skiff.tres"),
	preload("res://resources/roguelite/enemies/reef_ram.tres"),
	preload("res://resources/roguelite/enemies/paper_turret.tres"),
	preload("res://resources/roguelite/enemies/bell_binder.tres"),
	preload("res://resources/roguelite/enemies/ink_warden.tres"),
	preload("res://resources/roguelite/enemies/prism_bulwark.tres"),
	preload("res://resources/roguelite/enemies/brood_lantern.tres"),
	preload("res://resources/roguelite/enemies/shear_scribe.tres"),
]

const ENCOUNTERS: Array[FoldlightRogueEncounterDefinition] = [
	preload("res://resources/roguelite/encounters/reef_crossfire.tres"),
	preload("res://resources/roguelite/encounters/ink_city_order.tres"),
	preload("res://resources/roguelite/encounters/sun_court_verdict.tres"),
]

const UPGRADES: Array[FoldlightRogueUpgradeDefinition] = [
	preload("res://resources/roguelite/upgrades/steady_lantern.tres"),
	preload("res://resources/roguelite/upgrades/rapid_crease.tres"),
	preload("res://resources/roguelite/upgrades/twin_fold.tres"),
	preload("res://resources/roguelite/upgrades/needle_eye.tres"),
	preload("res://resources/roguelite/upgrades/returning_edge.tres"),
	preload("res://resources/roguelite/upgrades/prism_echo.tres"),
	preload("res://resources/roguelite/upgrades/hunter_mark.tres"),
	preload("res://resources/roguelite/upgrades/luminous_pierce.tres"),
	preload("res://resources/roguelite/upgrades/paper_storm.tres"),
	preload("res://resources/roguelite/upgrades/wide_return.tres"),
	preload("res://resources/roguelite/upgrades/quiet_hinge.tres"),
	preload("res://resources/roguelite/upgrades/sixfold_memory.tres"),
	preload("res://resources/roguelite/upgrades/clean_crease.tres"),
	preload("res://resources/roguelite/upgrades/mirror_tax.tres"),
	preload("res://resources/roguelite/upgrades/dense_fold.tres"),
	preload("res://resources/roguelite/upgrades/afterglow.tres"),
	preload("res://resources/roguelite/upgrades/crescent_field.tres"),
	preload("res://resources/roguelite/upgrades/perfect_release.tres"),
	preload("res://resources/roguelite/upgrades/swift_wing.tres"),
	preload("res://resources/roguelite/upgrades/double_step.tres"),
	preload("res://resources/roguelite/upgrades/long_glide.tres"),
	preload("res://resources/roguelite/upgrades/slipstream.tres"),
	preload("res://resources/roguelite/upgrades/razor_wake.tres"),
	preload("res://resources/roguelite/upgrades/foldstep.tres"),
	preload("res://resources/roguelite/upgrades/quick_recovery.tres"),
	preload("res://resources/roguelite/upgrades/phase_feather.tres"),
	preload("res://resources/roguelite/upgrades/kinetic_paper.tres"),
	preload("res://resources/roguelite/upgrades/tiny_silhouette.tres"),
	preload("res://resources/roguelite/upgrades/thick_paper.tres"),
	preload("res://resources/roguelite/upgrades/mend_on_clear.tres"),
	preload("res://resources/roguelite/upgrades/last_lantern.tres"),
	preload("res://resources/roguelite/upgrades/calm_current.tres"),
	preload("res://resources/roguelite/upgrades/glimmer_guard.tres"),
	preload("res://resources/roguelite/upgrades/large_burden.tres"),
	preload("res://resources/roguelite/upgrades/ink_immunity.tres"),
	preload("res://resources/roguelite/upgrades/steady_heart.tres"),
]

const BOSSES: Array[FoldlightRogueBossDefinition] = [
	preload("res://resources/roguelite/bosses/reef_crown_battery.tres"),
	preload("res://resources/roguelite/bosses/inverted_archivist.tres"),
	preload("res://resources/roguelite/bosses/origami_judge.tres"),
]


static func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	_validate_collection("region", REGIONS, errors)
	_validate_collection("weapon", WEAPONS, errors)
	_validate_collection("active item", ACTIVE_ITEMS, errors)
	_validate_collection("enemy", ENEMIES, errors)
	_validate_collection("encounter", ENCOUNTERS, errors)
	_validate_collection("upgrade", UPGRADES, errors)
	_validate_collection("boss", BOSSES, errors)
	var boss_ids := _id_set(BOSSES)
	var enemy_ids := _id_set(ENEMIES)
	var encounter_ids := _id_set(ENCOUNTERS)
	var upgrade_ids := _id_set(UPGRADES)
	for region in REGIONS:
		for boss_id in region.boss_ids:
			if not boss_ids.has(String(boss_id)):
				errors.append("region %s references unknown boss %s" % [region.content_id, boss_id])
		for encounter_id in region.encounter_ids:
			if not encounter_ids.has(String(encounter_id)):
				errors.append("region %s references unknown encounter %s" % [region.content_id, encounter_id])
	for encounter in ENCOUNTERS:
		for enemy_id in encounter.enemy_ids:
			if not enemy_ids.has(String(enemy_id)):
				errors.append("encounter %s references unknown enemy %s" % [encounter.content_id, enemy_id])
	for upgrade in UPGRADES:
		for prerequisite in upgrade.prerequisites:
			if not upgrade_ids.has(String(prerequisite)):
				errors.append("upgrade %s references unknown prerequisite %s" % [upgrade.content_id, prerequisite])
		for exclusion in upgrade.exclusions:
			if not upgrade_ids.has(String(exclusion)):
				errors.append("upgrade %s references unknown exclusion %s" % [upgrade.content_id, exclusion])
	return errors


static func weapon_by_id(content_id: StringName) -> FoldlightRogueWeaponDefinition:
	for definition in WEAPONS:
		if definition.content_id == content_id:
			return definition
	return null


static func active_item_by_id(content_id: StringName) -> FoldlightRogueActiveItemDefinition:
	for definition in ACTIVE_ITEMS:
		if definition.content_id == content_id:
			return definition
	return null


static func enemy_by_id(content_id: StringName) -> FoldlightRogueEnemyDefinition:
	for definition in ENEMIES:
		if definition.content_id == content_id:
			return definition
	return null


static func encounter_by_id(content_id: StringName) -> FoldlightRogueEncounterDefinition:
	for definition in ENCOUNTERS:
		if definition.content_id == content_id:
			return definition
	return null


static func upgrade_by_id(content_id: StringName) -> FoldlightRogueUpgradeDefinition:
	for definition in UPGRADES:
		if definition.content_id == content_id:
			return definition
	return null


static func boss_by_id(content_id: StringName) -> FoldlightRogueBossDefinition:
	for definition in BOSSES:
		if definition.content_id == content_id:
			return definition
	return null


static func _validate_collection(label: String, definitions: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for definition_variant: Variant in definitions:
		if not definition_variant is FoldlightRogueContentDefinition:
			errors.append("%s collection contains an invalid resource" % label)
			continue
		var definition := definition_variant as FoldlightRogueContentDefinition
		for error in definition.validation_errors():
			errors.append("%s: %s" % [label, error])
		var key := String(definition.content_id)
		if seen.has(key):
			errors.append("duplicate %s id %s" % [label, key])
		seen[key] = true


static func _id_set(definitions: Array) -> Dictionary:
	var result: Dictionary = {}
	for definition_variant: Variant in definitions:
		if definition_variant is FoldlightRogueContentDefinition:
			result[String((definition_variant as FoldlightRogueContentDefinition).content_id)] = true
	return result
