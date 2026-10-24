class_name FoldlightEndlessMapLandmarks
extends Node2D

## One submerged, noninteractive landmark per map. Geometry is compiled once;
## camera visibility changes only the mesh flag, never its retained commands.
const DrawBatch = preload("res://scripts/visuals/paper_draw_batch.gd")
const Seascape = preload("res://scripts/visuals/paper_seascape.gd")
const MAX_CACHED_LANDMARKS: int = 3
const MAX_HIGHLIGHT_ALPHA: float = 0.22
static var _mesh_cache: Dictionary = {}

var _mesh_instance: MeshInstance2D
var _visibility_notifier: VisibleOnScreenNotifier2D
var _definition: FoldlightEndlessMapDefinition
var _local_bounds := Rect2()
var _geometry_builds: int = 0
var _visible_transitions: int = 0


func _ready() -> void:
	z_index = -1
	set_process(false)
	set_physics_process(false)


func configure(definition: FoldlightEndlessMapDefinition) -> void:
	_definition = definition
	z_index = -1
	if definition == null:
		if is_instance_valid(_mesh_instance):
			_mesh_instance.mesh = null
		visible = false
		_local_bounds = Rect2()
		return
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance2D.new()
		_mesh_instance.name = "RetainedSubmergedRelief"
		add_child(_mesh_instance)
		_visibility_notifier = VisibleOnScreenNotifier2D.new()
		_visibility_notifier.name = "LandmarkVisibility"
		_visibility_notifier.screen_entered.connect(_on_screen_entered)
		_visibility_notifier.screen_exited.connect(_on_screen_exited)
		add_child(_visibility_notifier)
	position = definition.landmark_center
	var key := "%s:%s:%s" % [definition.landmark_kind, definition.landmark_size, Seascape.canonical_style(definition.region_style)]
	var mesh := _mesh_cache.get(key) as ArrayMesh
	if mesh == null:
		var batch := DrawBatch.new()
		match definition.landmark_kind:
			&"archive_tower": _draw_archive_tower(batch, definition.landmark_size)
			&"broken_sun": _draw_broken_sun(batch, definition.landmark_size)
			_: _draw_reef_steps(batch, definition.landmark_size)
		mesh = batch.build_mesh()
		if _mesh_cache.size() >= MAX_CACHED_LANDMARKS:
			_mesh_cache.erase(_mesh_cache.keys()[0])
		_mesh_cache[key] = mesh
		_geometry_builds += 1
	_mesh_instance.mesh = mesh
	var aabb := mesh.get_aabb()
	_local_bounds = Rect2(Vector2(aabb.position.x, aabb.position.y), Vector2(aabb.size.x, aabb.size.y))
	_visibility_notifier.rect = _local_bounds.grow(4.0)
	# CanvasItem also culls its mesh AABB before the notifier's first frame.
	# The notifier itself remains visible when its sibling mesh is hidden.
	_mesh_instance.visible = true
	visible = true


func get_visual_contract() -> Dictionary:
	if _definition == null or not is_instance_valid(_mesh_instance) or _mesh_instance.mesh == null:
		return {}
	var mesh := _mesh_instance.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	return {
		"map_id": _definition.map_id,
		"region_style": Seascape.canonical_style(_definition.region_style),
		"motif": _definition.landmark_kind,
		"world_bounds": Rect2(position + _local_bounds.position, _local_bounds.size),
		"vertex_count": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"triangle_count": (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
		"geometry_hash": hash(arrays[Mesh.ARRAY_VERTEX]),
		"geometry_builds": _geometry_builds,
		"cached_mesh_count": _mesh_cache.size(),
		"mesh_id": mesh.get_instance_id(),
		"visible_transitions": _visible_transitions,
		"visible_mesh": _mesh_instance.visible,
		"cached_geometry": true,
		"has_collision": false,
		"frame_animation": false,
		"screen_culling": true,
		"maximum_highlight_alpha": MAX_HIGHLIGHT_ALPHA,
	}


func _on_screen_entered() -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.mesh != null:
		_mesh_instance.visible = true
		_visible_transitions += 1


func _on_screen_exited() -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false
		_visible_transitions += 1


static func _draw_reef_steps(batch, size: Vector2) -> void:
	var paper := Color("87aaa0")
	var shadow := Color("071923")
	# A tilted fan of sedimentary paper ledges, not upright wall rectangles.
	for layer in 8:
		var t := float(layer) / 7.0
		var center := Vector2(lerpf(-0.06, 0.12, t), lerpf(0.22, -0.23, t)) * size
		var width := lerpf(0.41, 0.22, t) * size.x
		var height := lerpf(0.16, 0.105, t) * size.y
		var ridge := PackedVector2Array([
			center + Vector2(-width, -height * 0.25),
			center + Vector2(-width * 0.51, -height * 0.74),
			center + Vector2(width * 0.28, -height),
			center + Vector2(width * 0.89, -height * 0.37),
			center + Vector2(width, height * 0.21),
			center + Vector2(width * 0.46, height * 0.64),
			center + Vector2(-width * 0.35, height * 0.78),
			center + Vector2(-width * 0.86, height * 0.39),
		])
		var sink := Vector2(-14.0, 18.0)
		batch.draw_colored_polygon(_offset(ridge, sink), Color(shadow, 0.26))
		batch.draw_colored_polygon(ridge, Color(paper, 0.065 + float(layer % 3) * 0.011))
		batch.draw_colored_polygon(PackedVector2Array([ridge[0], ridge[1], ridge[2], center + Vector2(12, 9), ridge[7]]), Color("c2bd9d", 0.055))
		batch.draw_polyline(PackedVector2Array([ridge[0], ridge[1], ridge[2], ridge[3]]), Color(paper, 0.19), 2.2, true)
		batch.draw_polyline(PackedVector2Array([ridge[4], ridge[5], ridge[6], ridge[7]]), Color(shadow, 0.32), 5.0, true)
		batch.draw_line(ridge[1], center + Vector2(width * 0.42, height * 0.30), Color(paper, 0.10), 1.4, true)
		batch.draw_line(center + Vector2(-width * 0.55, height * 0.25), center + Vector2(width * 0.34, height * 0.11), Color(paper, 0.07), 1.2, true)
	# Detached folded shelves and tide-eroded seams keep the silhouette uneven.
	for chip in 5:
		var origin := Vector2(-0.37 + float(chip) * 0.155, 0.34 + float(chip % 2) * 0.035) * size
		var flake := PackedVector2Array([origin + Vector2(-36, -10), origin + Vector2(26, -23), origin + Vector2(47, 4), origin + Vector2(-18, 20)])
		batch.draw_colored_polygon(flake, Color(paper, 0.07))
		batch.draw_line(flake[0], flake[1], Color(paper, 0.16), 1.5, true)


static func _draw_archive_tower(batch, size: Vector2) -> void:
	var paper := Color("93a3ba")
	var binding := Color("b6a88a")
	var ink := Color("091522")
	# Seven stepped folios recede toward a broken crown. Their oblique spines
	# create a recognizable archive tower without implying solid upright cover.
	for storey in 7:
		var t := float(storey) / 6.0
		var center := Vector2(lerpf(-0.06, 0.12, t), lerpf(0.29, -0.29, t)) * size
		var half_width := lerpf(0.35, 0.17, t) * size.x
		var depth := size.y * 0.076
		var sheet := PackedVector2Array([
			center + Vector2(-half_width, -depth * 0.32),
			center + Vector2(-half_width * 0.30, -depth),
			center + Vector2(half_width, -depth * 0.30),
			center + Vector2(half_width * 0.88, depth * 0.32),
			center + Vector2(-half_width * 0.38, depth * 0.84),
			center + Vector2(-half_width, depth * 0.28),
		])
		batch.draw_colored_polygon(_offset(sheet, Vector2(-15, 24)), Color(ink, 0.28))
		batch.draw_colored_polygon(sheet, Color(paper, 0.09))
		batch.draw_colored_polygon(PackedVector2Array([sheet[0], sheet[1], center + Vector2(-half_width * 0.33, depth * 0.55), sheet[5]]), Color(binding, 0.08))
		batch.draw_polyline(PackedVector2Array([sheet[0], sheet[1], sheet[2]]), Color(paper, MAX_HIGHLIGHT_ALPHA), 2.0, true)
		batch.draw_polyline(PackedVector2Array([sheet[2], sheet[3], sheet[4], sheet[5]]), Color(ink, 0.35), 6.0, true)
		batch.draw_line(sheet[1], sheet[4], Color(binding, 0.14), 1.5, true)
		for page in 3:
			var offset := Vector2(0, 5 + page * 5)
			batch.draw_line(sheet[4] + offset, sheet[3] + offset, Color(paper, 0.075), 1.1, true)
		for seal in 3:
			var at := center + Vector2(half_width * (float(seal) * 0.27 - 0.08), -depth * 0.22)
			batch.draw_line(at, at + Vector2(15, 7), Color(binding, 0.13), 3.0, true)
	var crown := Vector2(0.13, -0.37) * size
	batch.draw_colored_polygon(PackedVector2Array([crown + Vector2(-88, 4), crown + Vector2(-58, -52), crown + Vector2(-14, -19), crown + Vector2(32, -68), crown + Vector2(88, -2), crown + Vector2(6, 29)]), Color(paper, 0.11))
	batch.draw_line(crown + Vector2(-58, -52), crown + Vector2(-14, -19), Color(binding, 0.20), 2.1, true)
	# Loose leaves trail away from the fallen stack, rather than a full halo.
	for leaf in 5:
		var at := Vector2(-0.39 + float(leaf % 2) * 0.035, -0.28 + float(leaf) * 0.13) * size
		var page := PackedVector2Array([at + Vector2(-21, -15), at + Vector2(33, -30), at + Vector2(40, 5), at + Vector2(-9, 27)])
		batch.draw_colored_polygon(page, Color(paper, 0.055))
		batch.draw_line(page[0], page[1], Color(paper, 0.17), 1.4, true)


static func _draw_broken_sun(batch, size: Vector2) -> void:
	var gold := Color("b6a06f")
	var pale := Color("c7b690")
	var ink := Color("10212a")
	var radial_scale := Vector2(size.x * 0.44, size.y * 0.40)
	# The missing sectors are deliberate: no complete bright ring can be
	# mistaken for an objective radius or a hostile area warning.
	for segment in 12:
		if segment in [1, 5, 9]:
			continue
		var angle := float(segment) * TAU / 12.0 - 0.1
		var broken_offset := Vector2(0, 0.035 * size.y) if segment in [2, 8] else Vector2.ZERO
		var a := Vector2.from_angle(angle - 0.18) * radial_scale * 0.56 + broken_offset
		var b := Vector2.from_angle(angle - 0.21) * radial_scale + broken_offset
		var c := Vector2.from_angle(angle + 0.21) * radial_scale + broken_offset
		var d := Vector2.from_angle(angle + 0.18) * radial_scale * 0.56 + broken_offset
		var seam := Vector2.from_angle(angle) * radial_scale * 0.80 + broken_offset
		var facet := PackedVector2Array([a, b, c, d])
		batch.draw_colored_polygon(_offset(facet, Vector2(-11, 17)), Color(ink, 0.28))
		batch.draw_colored_polygon(facet, Color(gold, 0.105))
		batch.draw_colored_polygon(PackedVector2Array([a, b, seam, d]), Color(ink, 0.20))
		batch.draw_line(b, c, Color(pale, MAX_HIGHLIGHT_ALPHA), 2.4, true)
		batch.draw_line(a, seam, Color(pale, 0.13), 1.5, true)
		batch.draw_line(d, c, Color(ink, 0.24), 4.0, true)
		var ray_tip := Vector2.from_angle(angle) * radial_scale * 1.09 + broken_offset
		batch.draw_colored_polygon(PackedVector2Array([b.lerp(c, 0.37), ray_tip, b.lerp(c, 0.63)]), Color(gold, 0.075))
	var medallion := PackedVector2Array()
	for corner in 8:
		medallion.append(Vector2.from_angle(float(corner) * TAU / 8.0 + PI / 8.0) * radial_scale * 0.33)
	batch.draw_colored_polygon(_offset(medallion, Vector2(-8, 16)), Color(ink, 0.24))
	batch.draw_colored_polygon(medallion, Color(gold, 0.07))
	var crack := PackedVector2Array([medallion[6], Vector2(-size.x * 0.08, -size.y * 0.025), Vector2(size.x * 0.035, size.y * 0.02), medallion[2]])
	batch.draw_polyline(crack, Color(ink, 0.42), 8.0, true)
	batch.draw_polyline(_offset(crack, Vector2(3, -3)), Color(pale, 0.12), 1.2, true)
	for scar in 3:
		var origin := Vector2(-0.18 + float(scar) * 0.16, 0.43) * size
		batch.draw_line(origin, origin + Vector2(58, -11), Color(gold, 0.10), 2.0, true)


static func _offset(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	return shifted
