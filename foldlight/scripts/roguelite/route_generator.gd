class_name FoldlightRogueRouteGenerator
extends Node

const ROUTE_VERSION: int = 1
const ORDINARY_CATEGORIES: Array[StringName] = [&"combat", &"combat", &"cache", &"event", &"forge", &"shop", &"rest"]


func generate_route(seed: int, regions: Array[FoldlightRogueRegionDefinition]) -> Dictionary:
	var generated_regions: Array[Dictionary] = []
	for region_index in regions.size():
		var definition: FoldlightRogueRegionDefinition = regions[region_index]
		generated_regions.append(_generate_region(seed, region_index, definition))
	return {
		"version": ROUTE_VERSION,
		"seed": seed,
		"regions": generated_regions,
	}


func _generate_region(run_seed: int, region_index: int, definition: FoldlightRogueRegionDefinition) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash("%d:%s:%d" % [run_seed, definition.content_id, region_index])) + 1
	var region_number := region_index + 1
	var depth_count := maxi(5, definition.depth_count)
	var nodes: Array[Dictionary] = []
	var previous_ids: Array[String] = []
	var start_id := "r%d_d0_a" % region_number
	nodes.append(_make_node(start_id, 0, &"entry", region_number, []))
	previous_ids.append(start_id)

	for depth in range(1, depth_count - 1):
		var branch_count := 2 if depth == 1 or (depth == 3 and depth_count >= 7) else 1
		var current_ids: Array[String] = []
		for branch in branch_count:
			var suffix := char(97 + branch)
			var node_id := "r%d_d%d_%s" % [region_number, depth, suffix]
			var category := _pick_category(rng, depth, depth_count, branch)
			nodes.append(_make_node(node_id, depth, category, region_number, []))
			current_ids.append(node_id)
		_connect_exits(nodes, previous_ids, current_ids)
		previous_ids = current_ids

	var boss_id := "r%d_d%d_boss" % [region_number, depth_count - 1]
	var boss_content_id := String(definition.boss_ids[rng.randi_range(0, definition.boss_ids.size() - 1)]) if not definition.boss_ids.is_empty() else ""
	var boss_node := _make_node(boss_id, depth_count - 1, &"boss", region_number, [])
	boss_node["boss_id"] = boss_content_id
	nodes.append(boss_node)
	_connect_exits(nodes, previous_ids, [boss_id])

	return {
		"id": String(definition.content_id),
		"title": definition.title,
		"index": region_index,
		"start_id": start_id,
		"boss_node_id": boss_id,
		"base_threat_budget": definition.base_threat_budget,
		"route_mark": rng.randi(),
		"nodes": nodes,
	}


func _pick_category(rng: RandomNumberGenerator, depth: int, depth_count: int, branch: int) -> StringName:
	if depth == depth_count - 2:
		return &"elite" if branch == 0 else &"rest"
	var index := rng.randi_range(0, ORDINARY_CATEGORIES.size() - 1)
	var category: StringName = ORDINARY_CATEGORIES[index]
	if branch > 0 and category == &"combat":
		category = [&"cache", &"event", &"forge", &"shop"][rng.randi_range(0, 3)]
	return category


func _make_node(node_id: String, depth: int, category: StringName, region_number: int, exits: Array[String]) -> Dictionary:
	return {
		"id": node_id,
		"depth": depth,
		"category": String(category),
		"risk": region_number + int(depth / 2),
		"exits": exits.duplicate(),
	}


func _connect_exits(nodes: Array[Dictionary], sources: Array[String], destinations: Array[String]) -> void:
	for source_id in sources:
		for index in nodes.size():
			if String(nodes[index].get("id", "")) != source_id:
				continue
			nodes[index]["exits"] = destinations.duplicate()
			break

