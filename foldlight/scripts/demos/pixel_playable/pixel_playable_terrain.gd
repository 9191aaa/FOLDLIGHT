class_name FoldlightPixelPlayableTerrain
extends Node2D

## A deliberately small, reusable terrain vocabulary.  Each atlas cell is a
## complete authored module, so rooms can be recomposed without asking an image
## model to repaint the whole battlefield or introducing filtering blur.

const ATLAS_GRID := Vector2i(3, 2)
const CELL_SIZE := Vector2(512.0, 512.0)

var terrain_texture: Texture2D
var room_index: int = 1


func configure(texture: Texture2D, requested_room: int) -> void:
	terrain_texture = texture
	room_index = requested_room
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func get_module_vocabulary() -> Array[StringName]:
	return [
		&"shore_ruin",
		&"shallow_plaza",
		&"arch_ruin",
		&"healing_basin",
		&"corruption_field",
		&"reed_islets",
	]


func _draw() -> void:
	if terrain_texture == null:
		return
	if room_index == 2:
		# Exact 1:1 atlas draws: no interpolation and no per-room repainting.
		_draw_module(1, Vector2(371, 150))
		_draw_module(0, Vector2(-350, 176))
		_draw_module(2, Vector2(1090, 165))


func _draw_module(cell: int, destination_origin: Vector2) -> void:
	var column := cell % ATLAS_GRID.x
	var row := cell / ATLAS_GRID.x
	var source := Rect2(Vector2(column, row) * CELL_SIZE, CELL_SIZE)
	draw_texture_rect_region(
		terrain_texture,
		Rect2(destination_origin, CELL_SIZE),
		source,
		Color.WHITE,
		false
	)
