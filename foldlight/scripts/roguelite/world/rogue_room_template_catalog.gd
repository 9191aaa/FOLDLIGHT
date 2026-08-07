class_name FoldlightRogueRoomTemplateCatalog
extends RefCounted

## Authored room library. A run randomly selects one complete composition; it
## never rotates or jitters individual props at runtime, so cover remains fair
## and visual silhouettes do not overlap by accident.

const REGION_IDS: Array[StringName] = [&"paper_reef", &"inverted_ink_city", &"nameless_sun_court"]
const TEMPLATE_NAMES: Array[String] = [
	"双堤回湾", "折潮十字", "侧帆水道", "双岛回廊",
	"月牙浅滩", "斜桥渡口", "四礁港", "风车汐眼",
	"三层潮阶", "折光瞳庭", "逆流双渠", "群礁航线",
]


static func template_count() -> int:
	return REGION_IDS.size() * TEMPLATE_NAMES.size()


static func templates_for_region(region_id: StringName) -> Array[Dictionary]:
	var safe_region := region_id if REGION_IDS.has(region_id) else &"paper_reef"
	var result: Array[Dictionary] = []
	for layout_index in TEMPLATE_NAMES.size():
		result.append(_make_template(safe_region, layout_index))
	return result


static func select_template(region_id: StringName, seed: int, room_id: StringName, category: StringName, depth: int) -> Dictionary:
	var templates := templates_for_region(region_id)
	if templates.is_empty():
		return {}
	var selection_seed := seed ^ hash(String(room_id)) ^ hash(String(category)) ^ depth * 104729
	var rng := RandomNumberGenerator.new()
	rng.seed = selection_seed
	return templates[rng.randi_range(0, templates.size() - 1)].duplicate(true)


static func _make_template(region_id: StringName, layout_index: int) -> Dictionary:
	var region_prefix := {
		&"paper_reef": "reef",
		&"inverted_ink_city": "city",
		&"nameless_sun_court": "court",
	}.get(region_id, "reef") as String
	var terrain := _layout(layout_index, region_id)
	for index in terrain.size():
		terrain[index]["id"] = "%s_%02d_%s" % [region_prefix, layout_index + 1, str(terrain[index].get("id", "terrain"))]
	return {
		"id": StringName("%s_room_%02d" % [region_prefix, layout_index + 1]),
		"display_name": TEMPLATE_NAMES[layout_index],
		"region_id": region_id,
		"terrain": terrain,
		"spawn_slots": _spawn_slots(layout_index),
	}


static func _layout(index: int, region_id: StringName) -> Array[Dictionary]:
	var favorable := FoldlightRogueTerrainDefinition.TerrainKind.SUN_PATCH
	var harmful := FoldlightRogueTerrainDefinition.TerrainKind.INK_POOL
	var hazard := FoldlightRogueTerrainDefinition.TerrainKind.THORN_PAPER
	var flow := FoldlightRogueTerrainDefinition.TerrainKind.CURRENT_LANE
	var flow_strength := 0.78
	if region_id == &"inverted_ink_city":
		flow_strength = 0.90
	elif region_id == &"nameless_sun_court":
		flow_strength = 1.02
	match index:
		0:
			return [
				_t("wall_w", 0, Vector2(780, 650), Vector2(500, 76), -0.12),
				_t("wall_e", 0, Vector2(2100, 650), Vector2(500, 76), 0.12),
				_t("pillar_n", 1, Vector2(1440, 350), Vector2(150, 150)),
				_t("flow_s", flow, Vector2(1440, 1320), Vector2(760, 140), 0.0, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(520, 1220), Vector2(330, 150)),
				_t("hazard", hazard, Vector2(2380, 1130), Vector2(320, 130), -0.12),
			]
		1:
			return [
				_t("wall_h", 0, Vector2(1440, 690), Vector2(560, 72)),
				_t("wall_v", 0, Vector2(1440, 900), Vector2(380, 72), PI * 0.5),
				_t("pillar_w", 1, Vector2(620, 440), Vector2(140, 140)),
				_t("pillar_e", 1, Vector2(2260, 440), Vector2(140, 140)),
				_t("flow_w", flow, Vector2(560, 910), Vector2(500, 130), 0.0, flow_strength, Vector2.UP),
				_t("blessing", favorable, Vector2(2300, 1240), Vector2(340, 150)),
				_t("pool", harmful, Vector2(450, 1280), Vector2(310, 140)),
			]
		2:
			return [
				_t("wall_nw", 0, Vector2(870, 450), Vector2(480, 72), 0.22),
				_t("wall_se", 0, Vector2(2010, 1050), Vector2(480, 72), 0.22),
				_t("pillar_sw", 1, Vector2(630, 1040), Vector2(145, 145)),
				_t("pillar_ne", 1, Vector2(2260, 460), Vector2(145, 145)),
				_t("flow_mid", flow, Vector2(1440, 790), Vector2(720, 145), -0.10, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(2180, 1310), Vector2(340, 145)),
				_t("hazard", hazard, Vector2(430, 360), Vector2(300, 120), 0.16),
			]
		3:
			return [
				_t("island_w", 1, Vector2(940, 760), Vector2(210, 210)),
				_t("island_e", 1, Vector2(1940, 760), Vector2(210, 210)),
				_t("wall_n", 0, Vector2(1440, 330), Vector2(440, 70)),
				_t("wall_s", 0, Vector2(1440, 900), Vector2(440, 70)),
				_t("flow_w", flow, Vector2(510, 760), Vector2(430, 125), 0.0, flow_strength, Vector2.DOWN),
				_t("flow_e", flow, Vector2(2370, 760), Vector2(430, 125), 0.0, flow_strength, Vector2.UP),
				_t("blessing", favorable, Vector2(520, 1240), Vector2(310, 140)),
				_t("pool", harmful, Vector2(2360, 340), Vector2(310, 140)),
			]
		4:
			return [
				_t("arc_w", 0, Vector2(850, 600), Vector2(440, 70), -0.38),
				_t("arc_n", 0, Vector2(1440, 390), Vector2(420, 70)),
				_t("arc_e", 0, Vector2(2030, 600), Vector2(440, 70), 0.38),
				_t("pillar_center", 1, Vector2(1440, 780), Vector2(150, 150)),
				_t("flow_s", flow, Vector2(1440, 1320), Vector2(820, 130), 0.0, flow_strength, Vector2.LEFT),
				_t("blessing", favorable, Vector2(520, 1050), Vector2(320, 145)),
				_t("hazard", hazard, Vector2(2360, 1060), Vector2(320, 125), 0.12),
			]
		5:
			return [
				_t("bridge_a", 0, Vector2(900, 500), Vector2(540, 72), -0.32),
				_t("bridge_b", 0, Vector2(1940, 1030), Vector2(540, 72), -0.32),
				_t("pillar_n", 1, Vector2(2140, 360), Vector2(145, 145)),
				_t("pillar_s", 1, Vector2(740, 1210), Vector2(145, 145)),
				_t("flow_mid", flow, Vector2(1430, 780), Vector2(660, 135), 0.16, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(2320, 1290), Vector2(320, 145)),
				_t("pool", harmful, Vector2(470, 820), Vector2(320, 145)),
			]
		6:
			return [
				_t("reef_nw", 1, Vector2(780, 430), Vector2(170, 170)),
				_t("reef_ne", 1, Vector2(2100, 430), Vector2(170, 170)),
				_t("reef_sw", 1, Vector2(780, 1080), Vector2(170, 170)),
				_t("reef_se", 1, Vector2(2100, 1080), Vector2(170, 170)),
				_t("wall_mid", 0, Vector2(1440, 750), Vector2(500, 70)),
				_t("flow_n", flow, Vector2(1440, 250), Vector2(620, 120), 0.0, flow_strength, Vector2.LEFT),
				_t("blessing", favorable, Vector2(470, 1280), Vector2(310, 140)),
				_t("hazard", hazard, Vector2(2410, 1280), Vector2(310, 125)),
			]
		7:
			return [
				_t("blade_n", 0, Vector2(1440, 430), Vector2(520, 70), 0.0),
				_t("blade_e", 0, Vector2(1940, 790), Vector2(460, 70), PI * 0.5),
				_t("blade_w", 0, Vector2(940, 790), Vector2(460, 70), PI * 0.5),
				_t("pillar", 1, Vector2(1440, 790), Vector2(155, 155)),
				_t("flow_s", flow, Vector2(1440, 1320), Vector2(680, 125), 0.0, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(460, 1160), Vector2(320, 145)),
				_t("pool", harmful, Vector2(2420, 420), Vector2(320, 145)),
			]
		8:
			return [
				_t("tier_n", 0, Vector2(1440, 360), Vector2(720, 70)),
				_t("tier_mid_w", 0, Vector2(850, 760), Vector2(430, 70)),
				_t("tier_mid_e", 0, Vector2(2030, 760), Vector2(430, 70)),
				_t("pillar_sw", 1, Vector2(700, 1190), Vector2(145, 145)),
				_t("pillar_se", 1, Vector2(2180, 1190), Vector2(145, 145)),
				_t("flow_s", flow, Vector2(1440, 1340), Vector2(650, 120), 0.0, flow_strength, Vector2.LEFT),
				_t("blessing", favorable, Vector2(420, 540), Vector2(300, 140)),
				_t("hazard", hazard, Vector2(2460, 540), Vector2(300, 125)),
			]
		9:
			return [
				_t("lid_n", 0, Vector2(1440, 390), Vector2(620, 70)),
				_t("lid_s", 0, Vector2(1440, 900), Vector2(620, 70)),
				_t("iris_w", 1, Vector2(880, 720), Vector2(165, 165)),
				_t("iris_e", 1, Vector2(2000, 720), Vector2(165, 165)),
				_t("flow", flow, Vector2(1440, 720), Vector2(650, 135), 0.0, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(2320, 1260), Vector2(330, 145)),
				_t("pool", harmful, Vector2(520, 1260), Vector2(330, 145)),
			]
		10:
			return [
				_t("wall_w", 0, Vector2(760, 760), Vector2(540, 70), PI * 0.5),
				_t("wall_e", 0, Vector2(2120, 760), Vector2(540, 70), PI * 0.5),
				_t("pillar_n", 1, Vector2(1440, 360), Vector2(145, 145)),
				_t("flow_w", flow, Vector2(1120, 780), Vector2(500, 125), PI * 0.5, flow_strength, Vector2.DOWN),
				_t("flow_e", flow, Vector2(1760, 780), Vector2(500, 125), PI * 0.5, flow_strength, Vector2.UP),
				_t("blessing", favorable, Vector2(480, 1260), Vector2(320, 145)),
				_t("hazard", hazard, Vector2(2400, 1260), Vector2(320, 125)),
			]
		_:
			return [
				_t("isle_a", 1, Vector2(620, 500), Vector2(145, 145)),
				_t("isle_b", 1, Vector2(1140, 390), Vector2(135, 135)),
				_t("isle_c", 1, Vector2(1740, 430), Vector2(135, 135)),
				_t("isle_d", 1, Vector2(2300, 600), Vector2(145, 145)),
				_t("wall_sw", 0, Vector2(820, 1050), Vector2(420, 70), 0.18),
				_t("wall_se", 0, Vector2(2060, 1050), Vector2(420, 70), -0.18),
				_t("flow", flow, Vector2(1440, 760), Vector2(650, 130), 0.0, flow_strength, Vector2.RIGHT),
				_t("blessing", favorable, Vector2(450, 1290), Vector2(300, 140)),
				_t("pool", harmful, Vector2(2430, 1290), Vector2(300, 140)),
			]


static func _t(id: String, kind: int, position: Vector2, size: Vector2, rotation: float = 0.0, strength: float = 1.0, direction: Vector2 = Vector2.RIGHT) -> Dictionary:
	return {"id": id, "kind": kind, "position": position, "size": size, "rotation": rotation, "strength": strength, "direction": direction}


static func _spawn_slots(layout_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ground_points: Array[Vector2] = [
		Vector2(300, 300), Vector2(580, 300), Vector2(920, 280), Vector2(1260, 260), Vector2(1620, 260), Vector2(1960, 280), Vector2(2300, 300), Vector2(2580, 300),
		Vector2(300, 650), Vector2(2580, 650), Vector2(300, 990), Vector2(2580, 990),
		Vector2(360, 1330), Vector2(700, 1370), Vector2(1040, 1360), Vector2(1840, 1360), Vector2(2180, 1370), Vector2(2520, 1330),
	]
	var ranged_points: Array[Vector2] = [
		Vector2(1030, 520), Vector2(1440, 540), Vector2(1850, 520),
		Vector2(980, 790), Vector2(1440, 780), Vector2(1900, 790),
		Vector2(1050, 1050), Vector2(1830, 1050),
	]
	var turret_points: Array[Vector2] = [
		Vector2(650, 500), Vector2(2230, 500), Vector2(650, 1020), Vector2(2230, 1020),
		Vector2(1440, 300), Vector2(1440, 920),
	]
	for point_index in ground_points.size():
		result.append({"id": StringName("l%02d_g%02d" % [layout_index + 1, point_index + 1]), "kind": &"ground", "position": ground_points[point_index]})
	for point_index in ranged_points.size():
		result.append({"id": StringName("l%02d_r%02d" % [layout_index + 1, point_index + 1]), "kind": &"ranged", "position": ranged_points[point_index]})
	for point_index in turret_points.size():
		result.append({"id": StringName("l%02d_t%02d" % [layout_index + 1, point_index + 1]), "kind": &"turret", "position": turret_points[point_index]})
	return result
