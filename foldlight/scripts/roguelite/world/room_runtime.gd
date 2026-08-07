class_name FoldlightRoomRuntime
extends Node2D

signal room_ready(room_id: StringName, bounds: Rect2)
signal terrain_effect_entered(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D, strength: float, direction: Vector2)
signal terrain_effect_exited(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D)
signal door_entered(exit_id: StringName)
signal combat_lock_changed(locked: bool)
signal encounter_spawn_telegraph(entry: Dictionary, duration: float)
signal encounter_enemy_requested(entry: Dictionary)
signal encounter_cleared(performance: Dictionary)

const TERRAIN_SCENE: PackedScene = preload("res://scenes/roguelite/terrain_piece.tscn")
const DOOR_SCENE: PackedScene = preload("res://scenes/roguelite/rogue_door.tscn")
const WALL_MARGIN: float = 56.0

var room_id: StringName = &""
var room_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(2880, 1620))

@onready var backdrop: FoldlightRoomBackdrop = $Backdrop
@onready var terrain_container: Node2D = $Terrain
@onready var actor_container: Node2D = $Actors
@onready var enemy_container: Node2D = $Actors/Enemies
@onready var projectile_container: Node2D = $Projectiles
@onready var pickup_container: Node2D = $Pickups
@onready var door_container: Node2D = $Doors
@onready var encounter_runtime: FoldlightRoomEncounterRuntime = $EncounterRuntime


func _ready() -> void:
	encounter_runtime.combat_lock_changed.connect(_on_combat_lock_changed)
	encounter_runtime.spawn_telegraph_requested.connect(func(entry: Dictionary, duration: float) -> void: encounter_spawn_telegraph.emit(entry, duration))
	encounter_runtime.enemy_spawn_requested.connect(func(entry: Dictionary) -> void: encounter_enemy_requested.emit(entry))
	encounter_runtime.encounter_cleared.connect(_on_encounter_cleared)


func configure_room(new_room_id: StringName, world_size: Vector2, placements: Array[Dictionary], accent: Color, backdrop_style: StringName = &"") -> Array[String]:
	var errors := validate_layout(world_size, placements)
	if not errors.is_empty():
		return errors
	room_id = new_room_id
	room_bounds = Rect2(Vector2.ZERO, world_size)
	backdrop.configure(room_id, world_size, accent, backdrop_style)
	_clear_terrain()
	_clear_doors()
	encounter_runtime.reset()
	for placement in placements:
		var piece := TERRAIN_SCENE.instantiate() as FoldlightTerrainPiece
		terrain_container.add_child(piece)
		var styled_placement := placement.duplicate(true)
		if not styled_placement.has("visual_style"):
			styled_placement["visual_style"] = backdrop.style_id
		piece.configure(styled_placement)
		piece.terrain_effect_entered.connect(_forward_terrain_entered)
		piece.terrain_effect_exited.connect(_forward_terrain_exited)
	room_ready.emit(room_id, room_bounds)
	return []


func configure_exits(exits: Array[Dictionary]) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for snapshot in exits:
		var exit_id := StringName(snapshot.get("id", &""))
		var exit_position := Vector2(snapshot.get("position", Vector2.ZERO))
		if exit_id.is_empty() or seen.has(exit_id):
			errors.append("room exits need non-empty unique ids")
			continue
		seen[exit_id] = true
		if not room_bounds.grow(8.0).has_point(exit_position):
			errors.append("exit %s lies outside the room" % exit_id)
	if not errors.is_empty():
		return errors
	_clear_doors()
	for snapshot in exits:
		var door := DOOR_SCENE.instantiate() as FoldlightRogueDoor
		door_container.add_child(door)
		door.configure(snapshot)
		door.entered.connect(func(exit_id: StringName) -> void: door_entered.emit(exit_id))
	return []


func begin_encounter(plan: Dictionary) -> Array[String]:
	var errors := encounter_runtime.configure(plan)
	if not errors.is_empty():
		return errors
	if not encounter_runtime.begin():
		return ["encounter could not begin"]
	return []


func advance_encounter(delta: float) -> void:
	encounter_runtime.advance_simulation(delta)


func notify_enemy_defeated(count: int = 1) -> bool:
	return encounter_runtime.notify_enemy_defeated(count)


func set_doors_locked(locked: bool) -> void:
	for door in get_doors():
		door.set_locked(locked)


func get_doors() -> Array[FoldlightRogueDoor]:
	var result: Array[FoldlightRogueDoor] = []
	for child in door_container.get_children():
		if child is FoldlightRogueDoor:
			result.append(child as FoldlightRogueDoor)
	return result


func get_solid_terrain_bounds(extra_margin: float = 0.0) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for piece in get_terrain_pieces():
		if piece.kind in [FoldlightRogueTerrainDefinition.TerrainKind.PAPER_WALL, FoldlightRogueTerrainDefinition.TerrainKind.REFRACTION_PILLAR]:
			result.append(piece.get_world_bounds(extra_margin))
	return result


func validate_layout(world_size: Vector2, placements: Array[Dictionary]) -> Array[String]:
	var errors: Array[String] = []
	if world_size.x < 1920.0 or world_size.y < 1080.0:
		errors.append("room must be at least the 1920x1080 design viewport")
	var ids: Dictionary = {}
	var safe_bounds := Rect2(Vector2.ZERO, world_size).grow(-32.0)
	var authored_bounds: Array[Dictionary] = []
	for placement in placements:
		var placement_id := String(placement.get("id", ""))
		if placement_id.is_empty() or ids.has(placement_id):
			errors.append("terrain placement ids must be non-empty and unique")
		ids[placement_id] = true
		var piece_position := Vector2(placement.get("position", Vector2.ZERO))
		var piece_size := Vector2(placement.get("size", Vector2.ZERO)).abs()
		if piece_size.x <= 0.0 or piece_size.y <= 0.0:
			errors.append("terrain %s needs positive dimensions" % placement_id)
			continue
		var angle := float(placement.get("rotation", 0.0))
		var c := absf(cos(angle))
		var s := absf(sin(angle))
		var rotated_size := Vector2(piece_size.x * c + piece_size.y * s, piece_size.x * s + piece_size.y * c)
		var piece_bounds := Rect2(piece_position - rotated_size * 0.5, rotated_size)
		if not safe_bounds.encloses(piece_bounds):
			errors.append("terrain %s extends outside the safe room bounds" % placement_id)
		for previous in authored_bounds:
			var previous_bounds := previous.get("bounds", Rect2()) as Rect2
			if piece_bounds.grow(-12.0).intersects(previous_bounds.grow(-12.0)):
				errors.append("terrain %s overlaps authored terrain %s" % [placement_id, str(previous.get("id", "terrain"))])
		authored_bounds.append({"id": placement_id, "bounds": piece_bounds})
	return errors


func bind_player(player: FoldlightPlayer) -> void:
	player.play_bounds = room_bounds.grow(-WALL_MARGIN)


func get_terrain_pieces() -> Array[FoldlightTerrainPiece]:
	var result: Array[FoldlightTerrainPiece] = []
	for child in terrain_container.get_children():
		if child is FoldlightTerrainPiece:
			result.append(child as FoldlightTerrainPiece)
	return result


func _clear_terrain() -> void:
	for child in terrain_container.get_children():
		terrain_container.remove_child(child)
		child.queue_free()


func _clear_doors() -> void:
	for child in door_container.get_children():
		door_container.remove_child(child)
		child.queue_free()


func _forward_terrain_entered(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D, strength: float, direction: Vector2) -> void:
	terrain_effect_entered.emit(kind, body, strength, direction)


func _forward_terrain_exited(kind: FoldlightRogueTerrainDefinition.TerrainKind, body: Node2D) -> void:
	terrain_effect_exited.emit(kind, body)


func _on_combat_lock_changed(locked: bool) -> void:
	set_doors_locked(locked)
	combat_lock_changed.emit(locked)


func _on_encounter_cleared(performance: Dictionary) -> void:
	encounter_cleared.emit(performance.duplicate(true))
