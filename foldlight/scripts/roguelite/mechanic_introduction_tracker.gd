class_name FoldlightMechanicIntroductionTracker
extends Node

signal card_requested(snapshot: Dictionary)

var _introduced_ids: Array[StringName] = []


func request_introduction(definition: FoldlightRogueEnemyDefinition) -> Dictionary:
	if definition == null or _introduced_ids.has(definition.content_id):
		return {}
	if definition.content_id != &"cinder_mine" and not definition.role in [FoldlightRogueEnemyDefinition.EnemyRole.TURRET, FoldlightRogueEnemyDefinition.EnemyRole.BUFFER, FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER, FoldlightRogueEnemyDefinition.EnemyRole.ELITE]:
		return {}
	_introduced_ids.append(definition.content_id)
	var snapshot := {
		"content_id": definition.content_id,
		"preview_kind": &"enemy",
		"preview_id": definition.content_id,
		"title": definition.title,
		"description": definition.description,
		"rule": definition.mechanic_rule,
		"counterplay": definition.counterplay,
		"rule_heading": "它怎么打",
		"counter_heading": "你怎么拆",
		"attack_style": _enemy_attack_style(definition),
		"role": definition.role,
		"role_title": _role_title(definition.role),
		"accent": definition.accent,
		"duration": 0.0,
	}
	card_requested.emit(snapshot.duplicate(true))
	return snapshot


func request_boss_introduction(definition: FoldlightRogueBossDefinition) -> Dictionary:
	if definition == null or _introduced_ids.has(definition.content_id):
		return {}
	_introduced_ids.append(definition.content_id)
	var briefing := _boss_briefing(definition.content_id)
	var snapshot := {
		"content_id": definition.content_id,
		"preview_kind": &"boss",
		"preview_id": definition.content_id,
		"title": definition.title,
		"description": definition.description,
		"rule": str(briefing.get("rule", "它会改变整个房间的走位规则。")),
		"counterplay": str(briefing.get("counterplay", "先看预警，再用冲刺穿过火力空档。")),
		"rule_heading": "这场战斗会发生什么",
		"counter_heading": "第一眼该看哪里",
		"attack_style": StringName(briefing.get("attack_style", &"boss_pattern")),
		"role": FoldlightRogueEnemyDefinition.EnemyRole.BOSS,
		"role_title": "区域首领",
		"accent": definition.accent,
		"duration": 0.0,
	}
	card_requested.emit(snapshot.duplicate(true))
	return snapshot


func restore_introduced(source: Variant) -> void:
	_introduced_ids.clear()
	if source is Array:
		for id_variant: Variant in source:
			var content_id := StringName(id_variant)
			if not content_id.is_empty() and not _introduced_ids.has(content_id):
				_introduced_ids.append(content_id)


func make_snapshot() -> Array[String]:
	var result: Array[String] = []
	for content_id in _introduced_ids:
		result.append(String(content_id))
	return result


func _role_title(role: FoldlightRogueEnemyDefinition.EnemyRole) -> String:
	return {
		FoldlightRogueEnemyDefinition.EnemyRole.TURRET: "阵地单位",
		FoldlightRogueEnemyDefinition.EnemyRole.BUFFER: "增幅单位",
		FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER: "控场单位",
		FoldlightRogueEnemyDefinition.EnemyRole.ELITE: "精英单位",
	}.get(role, "机制单位")


func _enemy_attack_style(definition: FoldlightRogueEnemyDefinition) -> StringName:
	match definition.content_id:
		&"miasma_wraith": return &"poison_trail"
		&"cinder_mine": return &"anchored_blast"
		&"shutter_seraph": return &"exposure_barrage"
		&"paper_turret": return &"aimed_volley"
		&"brood_lantern": return &"summon"
		&"bell_binder": return &"tether"
		&"ink_warden": return &"zone"
		&"prism_bulwark": return &"shield"
		&"shear_scribe": return &"cross_cut"
	match definition.role:
		FoldlightRogueEnemyDefinition.EnemyRole.TURRET: return &"aimed_volley"
		FoldlightRogueEnemyDefinition.EnemyRole.BUFFER: return &"support_aura"
		FoldlightRogueEnemyDefinition.EnemyRole.CONTROLLER: return &"control_zone"
		FoldlightRogueEnemyDefinition.EnemyRole.SHOOTER: return &"aimed_volley"
		FoldlightRogueEnemyDefinition.EnemyRole.CHARGER: return &"charge_line"
	return &"pursuit"


func _boss_briefing(content_id: StringName) -> Dictionary:
	match content_id:
		&"reef_crown_battery":
			return {
				"rule": "王冠电池会把潮波推向整间战场，但每一道波面都留有一段明显的安静缺口。它也会唤来小怪补充可收纳弹药。",
				"counterplay": "先找预警环上的青色缺口，再横向冲刺穿过去；收纳小怪弹幕，等王冠打开时集中返航。",
				"attack_style": &"tide_gap",
			}
		&"inverted_archivist":
			return {
				"rule": "倒悬档案官会用墨线切开房间，再让支援怪从分区中央夹击。墨色弹不可反射。",
				"counterplay": "不要贴边站：先绕开墨线，清掉中场支援怪，再把普通弹收纳回敬给首领。",
				"attack_style": &"partitions",
			}
		&"origami_judge":
			return {
				"rule": "无名折纸法官会不断移动审判框，框外区域持续危险，金黑裁决弹无法收纳。",
				"counterplay": "跟着安全框一起移动，留一次冲刺应对框体收缩；普通弹攒够后再打断它的宣判。",
				"attack_style": &"shrinking_frame",
			}
		&"tide_loom_mother":
			return {"rule": "织母强化范围内的敌人：跑得更快、开火更密、弹速更高。越到后期，号令越凶。", "counterplay": "看清连向织母的丝线，拉开敌群再优先击破她；光环外的小怪会失去强化。", "attack_style": &"command_swarm"}
		&"torn_page_executioner":
			return {"rule": "行刑者会连续追身冲撞，每一冲都会重新瞄准。后期连冲更多、转身更快。", "counterplay": "看到通道后横向闪开，别沿通道后退；每次都重新找侧面，留冲刺应对下一撞。", "attack_style": &"relentless_charge"}
		&"eclipse_twin_bells":
			return {"rule": "左右纸铃会先后敲出弹环，每个铃口的青色扇区都是缺口；下一轮先响的铃会交换。", "counterplay": "先看两侧各自的缺口，不要只跟着第一圈走；普通铃弹可收纳，返光能打断尚未响起的第二铃。", "attack_style": &"paired_gaps"}
	return {}
