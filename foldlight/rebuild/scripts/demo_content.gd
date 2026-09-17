class_name FoldlightDemoContent
extends RefCounted

# One authored voyage, not another permanent combat engine.
const STAGE_NAMES: Array[String] = ["静水入航", "扇潮交锋", "冲角回廊", "礁冠炮城"]
const STAGE_HINTS: Array[String] = [
	"迎向紫色花瓣，按住空格收纳，再松手返光。",
	"扇面就是弹药。不要只逃跑，试着收下一整束。",
	"冲角亮出导线后横移；存着光也能按 Shift 返光冲刺。",
	"紫色收纳，黑金闪避。看清预警，再把光送回去。",
]
const WAVES: Array = [
	[["drifter", "drifter", "fan"], ["drifter", "fan", "drifter", "bloomer"]],
	[["fan", "drifter", "fan", "bloomer"], ["fan", "bloomer", "drifter", "fan", "drifter"]],
	[["ram", "fan", "drifter", "bloomer"], ["ram", "fan", "bloomer", "drifter", "fan"]],
]
const SLOTS: Array[Vector2] = [Vector2(510, 330), Vector2(1410, 330), Vector2(750, 470), Vector2(1190, 460), Vector2(960, 240)]
const REWARDS: Array = [
	[
		{"id": &"bright_return", "lane": "返光", "title": "亮刃", "body": "返光伤害 +20%\n收下的每一枚光，都更有分量。", "stats": {"return_damage_multiplier": 1.20}},
		{"id": &"wide_fold", "lane": "折域", "title": "展开", "body": "收纳容量 +2，折域半径 +8%\n一次收下更宽的弹幕。", "stats": {"capture_capacity": 2.0, "fold_radius_multiplier": 1.08}},
		{"id": &"paper_heart", "lane": "续航", "title": "纸心", "body": "最大生命 +1，立即回复 1 点\n留下一次犯错的余地。", "stats": {"max_health_add": 1.0}, "heal": 1},
	],
	[
		{"id": &"chain_light", "lane": "返光", "title": "连光", "body": "返光伤害 +10%，额外连锁 +1\n命中后改锁另一名可达敌人。", "stats": {"return_damage_multiplier": 1.10, "return_chain_add": 1.0}},
		{"id": &"slipstream", "lane": "机动", "title": "顺流", "body": "折域移动速度 +18%\n释放至少 3 光，冲刺冷却减少 0.4 秒。", "stats": {"fold_move_speed_add": 0.18, "dash_refund_on_release": 0.20}},
		{"id": &"afterglow", "lane": "续航", "title": "余辉", "body": "立即回复 2 点生命\n受击保护时间 +0.20 秒。", "stats": {"damage_grace_add": 0.20}, "heal": 2},
	],
]

static func reward_by_id(id: StringName) -> Dictionary:
	for row: Array in REWARDS:
		for item: Dictionary in row:
			if item["id"] == id:
				return item.duplicate(true)
	return {}

static func build_stats(ids: Array[StringName], base_health: int) -> Dictionary:
	var stats: Dictionary = {"max_health_add": float(base_health - 5)}
	for id: StringName in ids:
		var item: Dictionary = reward_by_id(id)
		var modifiers: Dictionary = item.get("stats", {})
		for key: String in modifiers:
			if key.ends_with("_multiplier"):
				stats[key] = float(stats.get(key, 1.0)) * float(modifiers[key])
			else:
				stats[key] = float(stats.get(key, 0.0)) + float(modifiers[key])
	return stats

static func wave_entries(stage: int, wave: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if stage < 0 or stage >= WAVES.size() or wave < 0 or wave >= 2:
		return result
	var roster: Array = WAVES[stage][wave]
	for index in roster.size():
		var point: Vector2 = SLOTS[index]
		if wave == 1:
			point.x = 1920.0 - point.x
		result.append({"enemy_id": StringName(roster[index]), "spawn_position": point, "health_multiplier": 1.0})
	return result
