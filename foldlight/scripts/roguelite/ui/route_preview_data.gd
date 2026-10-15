extends RefCounted
## Read-only chart vocabulary. Never drafts rewards or composes encounters.

const TITLES := {&"entry": "入潮口", &"combat": "交锋房", &"elite": "高压房", &"cache": "藏光室", &"event": "异潮室", &"forge": "折纸坊", &"shop": "漂灯市", &"rest": "静水泊", &"boss": "终潮庭"}


static func describe(node: Dictionary, context: Dictionary, reachable: bool, region_index: int) -> Dictionary:
	var category := StringName(node.get("category", &"combat"))
	var title := String(TITLES.get(category, "无名折点"))
	var descriptions := {
		&"entry": "沿纸灯驶入海域。澄清第一片敌潮，让航路继续展开。",
		&"combat": "礁脊之间，敌潮交错。利用折翼与返光，打开前方航路。",
		&"elite": "强敌聚集，四波敌潮接连展开。为这段高压航程留足灯芯。",
		&"cache": "遗落的纸匣沉在浅滩。敌潮较缓，澄清后选择一道强化。",
		&"event": "不同的潮声在此交汇。这里仍有战斗，澄清后选择一道强化。",
		&"forge": "折纸坊的锋面尚待重铸。澄清敌潮后，选择一把自动武器。",
		&"shop": "漂灯汇成一座海上市集。澄清敌潮后，选择一件主动道具。",
		&"rest": "增援较慢的静水航段，仍需战斗。这里不会自动回复灯芯。",
		&"boss": "终潮守候在航路尽头。击败首领，完成这片海域的航程。",
	}
	var reward := "一道局内强化"
	var reward_kind: StringName = &"upgrade"
	if category == &"forge":
		reward = "选择自动武器"
		reward_kind = &"weapon"
	elif category == &"shop":
		reward = "选择主动道具"
		reward_kind = &"active"
	elif category == &"boss":
		reward = "完成本次迷航" if region_index + 1 >= int(context.get("region_count", 3)) else "启航下一海域"
		reward_kind = &"passage"
	if reachable and category != &"boss" and context.has("room_count") and int(context["room_count"]) + 1 == 2 and str(context.get("active_item_id", "")).is_empty():
		reward = "强化 ＋ 首次主动道具"
		reward_kind = &"first_active"
	var description := String(descriptions.get(category, descriptions[&"combat"]))
	if reward_kind == &"first_active":
		description = "下一房是本次航程的第二次澄清。战斗结束后，先选强化，再带走首次主动道具。"
	var boss := FoldlightRogueContentCatalog.boss_by_id(StringName(node.get("boss_id", &""))) if category == &"boss" else null
	if boss != null:
		title = "%s · %s" % [title, boss.title]
		description = boss.description
	var pressure := "常规敌潮"
	if category == &"elite": pressure = "高压敌潮"
	elif category in [&"rest", &"cache", &"shop", &"forge"]: pressure = "较缓敌潮"
	elif category == &"boss": pressure = "首领战"
	var waves := 4 if category == &"elite" or region_index > 0 else 3
	return {
		"title": title, "category_title": String(TITLES.get(category, "无名折点")),
		"description": description, "reward": reward, "reward_kind": reward_kind,
		"pressure": pressure, "waves": 0 if category == &"boss" else waves,
		"risk": maxi(1, int(node.get("risk", 1))), "category": category,
	}
