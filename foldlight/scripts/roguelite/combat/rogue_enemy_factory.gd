class_name FoldlightRogueEnemyFactory
extends RefCounted

const GENERIC_SCENE: PackedScene = preload("res://scenes/roguelite/combat/rogue_enemy_actor.tscn")
const TURRET_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/paper_turret.tscn")
const BINDER_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/bell_binder.tscn")
const WARDEN_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/ink_warden.tscn")
const PRISM_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/prism_bulwark.tscn")
const BROOD_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/brood_lantern.tscn")
const SHEAR_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/shear_scribe.tscn")
const SERAPH_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/shutter_seraph.tscn")
const CINDER_MINE_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/cinder_mine.tscn")
const MIASMA_WRAITH_SCENE: PackedScene = preload("res://scenes/roguelite/enemies/miasma_wraith.tscn")


static func create(definition: FoldlightRogueEnemyDefinition, actor_id: StringName) -> Node2D:
	if definition == null:
		return null
	var actor: Node2D
	match definition.content_id:
		&"miasma_wraith":
			actor = MIASMA_WRAITH_SCENE.instantiate() as CharacterBody2D
		&"cinder_mine":
			actor = CINDER_MINE_SCENE.instantiate() as CharacterBody2D
		&"shutter_seraph":
			actor = SERAPH_SCENE.instantiate() as CharacterBody2D
		&"prism_bulwark":
			actor = PRISM_SCENE.instantiate() as FoldlightPrismBulwark
		&"brood_lantern":
			actor = BROOD_SCENE.instantiate() as FoldlightBroodLantern
		&"shear_scribe":
			actor = SHEAR_SCENE.instantiate() as FoldlightShearScribe
		_:
			match definition.role:
				FoldlightRogueEnemyDefinition.EnemyRole.TURRET:
					actor = TURRET_SCENE.instantiate() as FoldlightPaperTurret
				FoldlightRogueEnemyDefinition.EnemyRole.BUFFER:
					actor = BINDER_SCENE.instantiate() as FoldlightBellBinder
				FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER:
					actor = WARDEN_SCENE.instantiate() as FoldlightInkWarden
				_:
					actor = GENERIC_SCENE.instantiate() as FoldlightRogueEnemyActor
	if actor != null and actor.has_method("configure"):
		actor.call("configure", definition, actor_id)
	return actor
