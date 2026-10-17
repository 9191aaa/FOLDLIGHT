extends RefCounted
## Coalesce simulation-driven canvas rebuilding until the next display frame.
## Godot flushes deferred queue_redraw callbacks after EACH physics step, so
## queue_redraw alone does not coalesce catch-up steps. Geometry and simulation
## remain unchanged; the idle frame renders their latest completed state.

static var _pending: Dictionary = {}


static func request(canvas: CanvasItem) -> void:
	if not is_instance_valid(canvas) or canvas.is_queued_for_deletion():
		return
	if not Engine.is_in_physics_frame() or not canvas.is_inside_tree():
		canvas.queue_redraw()
		return
	var object_id := canvas.get_instance_id()
	if not _pending.has(object_id):
		_pending[object_id] = weakref(canvas)
	var tree := canvas.get_tree()
	# This signal still fires when the scene is paused. A final hit/clear must
	# become visible even if the owner stops processing before the idle frame.
	if not tree.process_frame.is_connected(_flush):
		tree.process_frame.connect(_flush, CONNECT_ONE_SHOT)


static func _flush() -> void:
	var pending := _pending
	_pending = {}
	for reference: WeakRef in pending.values():
		var canvas := reference.get_ref() as CanvasItem
		if is_instance_valid(canvas) and canvas.is_inside_tree() and not canvas.is_queued_for_deletion():
			canvas.queue_redraw()
