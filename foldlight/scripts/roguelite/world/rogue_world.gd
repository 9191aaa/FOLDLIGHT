class_name FoldlightRogueWorld
extends Node2D

@onready var room_runtime: FoldlightRoomRuntime = $RoomRuntime
@onready var camera: FoldlightRogueCamera = $CameraRig
@onready var combat_runtime: FoldlightRogueCombatRuntime = $CombatRuntime


func _ready() -> void:
	deactivate()


func load_room(player: FoldlightPlayer, room_id: StringName, world_size: Vector2, placements: Array[Dictionary], accent: Color, run_seed: int = 330031, backdrop_style: StringName = &"") -> Array[String]:
	var errors := room_runtime.configure_room(room_id, world_size, placements, accent, backdrop_style)
	if not errors.is_empty():
		return errors
	room_runtime.bind_player(player)
	camera.configure(player, room_runtime.room_bounds)
	combat_runtime.bind(room_runtime, player, run_seed)
	return []


func activate() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	camera.set_active(true)
	combat_runtime.set_active(true)


func deactivate() -> void:
	if is_node_ready():
		combat_runtime.set_active(false)
	camera.set_active(false)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
