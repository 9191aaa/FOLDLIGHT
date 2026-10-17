extends RefCounted

static func heal_on_claim(metadata: Dictionary) -> String:
	var amount := maxi(0, int(metadata.get("heal_on_claim", 0)))
	if amount == 0: return ""
	var maximum := int(metadata.get("max_health", 0))
	if maximum > 0 and int(metadata.get("current_health", 0)) >= maximum:
		return "生命已满"
	return "领奖回复 %d 格生命" % amount
