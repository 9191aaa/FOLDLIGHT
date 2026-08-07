class_name FoldlightPixelPlayableBackdrop
extends Node2D

var background_texture: Texture2D
var source_region := Rect2()
var canvas_size := Vector2(1254.0, 705.0)


func configure(texture: Texture2D, requested_canvas: Vector2) -> void:
	background_texture = texture
	canvas_size = requested_canvas
	source_region = _center_crop_region(texture.get_size() if texture != null else Vector2.ZERO, canvas_size)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func get_source_region() -> Rect2:
	return source_region


func _center_crop_region(source_size: Vector2, target_size: Vector2) -> Rect2:
	if source_size.x < target_size.x or source_size.y < target_size.y:
		return Rect2(Vector2.ZERO, source_size)
	var origin := ((source_size - target_size) * 0.5).floor()
	return Rect2(origin, target_size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, canvas_size), Color("071d25"))
	if background_texture == null or not source_region.has_area():
		return
	# Source and destination are the same pixel dimensions. This is deliberate:
	# the playable demo never resamples its high-density pixel background.
	draw_texture_rect_region(background_texture, Rect2(Vector2.ZERO, canvas_size), source_region)
