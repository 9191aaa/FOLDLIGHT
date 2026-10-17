extends SceneTree
const Visual = preload("res://scripts/endless/endless_objective_visual.gd")
const Navigation = preload("res://scripts/endless/navigation_overlay.gd")
const Map = preload("res://scripts/endless/endless_handcrafted_map.gd")
const Definition = preload("res://resources/endless/maps/solar_archipelago.tres")
var _failures := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.get_node("ProfileManager").persistence_enabled = false
	var map := Map.new()
	map.build_physics_walls = false
	root.add_child(map)
	map.configure(Definition)
	var camera := Camera2D.new()
	camera.position = Definition.player_spawn
	root.add_child(camera)
	var boat := Definition.player_spawn + Vector2(-180,-60)
	var task := {"id":&"escort_test","kind":&"escort","title":"护送归航纸舟","status":&"active","target_active":true,"target_position":boat,"escort_position":boat,"escort_destination":boat+Vector2(560,140),"escort_next_position":boat+Vector2(260,0),"escort_direction":Vector2.RIGHT,"escort_route":PackedVector2Array([boat,boat+Vector2(260,0),boat+Vector2(560,140)]),"escort_progress":0.35,"progress":350.0,"required":1000.0,"progress_ratio":0.35,"escort_radius":280.0,"escort_state":&"waiting_player","escort_moving":false,"occupied":false,"time_remaining":80.0,"instruction":"陪伴纸舟驶向终点；离得太远会停航。"}
	map.set_active_objective(task)
	var visual: Node = map._objective_canvas
	_check(visual.get_visual_snapshot().escort_position == boat and visual.get_visual_snapshot().escort_radius == 280, "boat and escort boundary use exact authoritative position/radius")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var nav := Navigation.new()
	layer.add_child(nav)
	var snapshot := {"bounds":Definition.bounds,"map_title":Definition.title,"map_id":Definition.map_id,"objective":task,"player_position":Definition.player_spawn,"camera_rect":Rect2(Definition.player_spawn-Vector2(960,540),Vector2(1920,1080)),"danger":{"state":&"safe"},"bombardment":{"state":&"warning","warning_remaining":2.6,"zones":[{"position":boat+Vector2(400,-160),"radius":180.0}]}}
	nav.set_touch_layout(true,184)
	nav.update_snapshot(snapshot)
	await _settle()
	_check(nav.get_navigation_snapshot().instruction_text.contains("靠近金色纸舟") and nav.get_navigation_snapshot().task_title.contains("35%"), "waiting escort names the boat, proximity action and real percentage")
	_check(nav.get_navigation_snapshot().bombardment == snapshot.bombardment and nav.get_navigation_snapshot().danger_text.contains("2.6秒"), "minimap and warning use exact locked bombardment snapshot")
	_check(nav._task_instruction.get_minimum_size().y <= nav._task_instruction.size.y, "escort instruction stays inside two-line mobile task budget")
	await _save("escort-waiting-and-bombardment")
	task.escort_state = &"moving"
	task.escort_moving = true
	task.occupied = true
	task.escort_position += Vector2(30,0)
	task.target_position = task.escort_position
	map.set_active_objective(task)
	nav.update_snapshot(snapshot)
	map.advance_presentation(0.05)
	_check(visual.get_visual_snapshot().escort_position == task.target_position and nav.get_navigation_snapshot().instruction_text.contains("伴随纸舟前进"), "moving ship follows real snapshot and changes guidance without creating a target actor")
	var before: float = visual.get_visual_snapshot().animation_time
	await _settle()
	_check(visual.get_visual_snapshot().animation_time == before, "no process/timer can advance boat motion while combat owner is paused")
	map.set_motion_reduced(true)
	map.advance_presentation(0.3)
	_check(visual.get_visual_snapshot().animation_time == before, "reduced motion disables boat bobbing while keeping position updates")
	task.escort_state = &"contested"
	snapshot.danger = {"state":&"closed","safe_position":boat+Vector2(400,300)}
	map.set_active_objective(task)
	nav.update_snapshot(snapshot)
	_check(nav.get_navigation_snapshot().instruction_text.contains("减速") and nav.get_navigation_snapshot().danger_text.contains("正在扣血") and nav.get_navigation_snapshot().danger_text.contains("轰炸"), "contested escort, poison damage and incoming bombs retain distinct simultaneous guidance")
	await _save("escort-contested-and-hazards")
	for pair in [[&"capture_storm",44],[&"clear_swarm",42],[&"relay_route",5]]:
		task.kind = pair[0]
		task.required = pair[1]
		task.progress = 0
		task.progress_ratio = 0.0
		nav.update_snapshot(snapshot)
		_check(nav.get_navigation_snapshot().instruction_text.contains(str(pair[1])), "scaled task guidance reflects required amount: "+str(pair[0]))
	task.kind = &"capture_storm"
	task.required = 44
	task.progress = 22
	task.progress_ratio = 0.5
	map.set_active_objective(task)
	_check(visual.get_visual_snapshot().lit_petals == 6, "twelve bounded windmill petals show half of44, not false completion at12")
	task.kind = &"relay_route"
	task.route_points = PackedVector2Array([boat,boat+Vector2(100,0),boat+Vector2(200,0),boat+Vector2(300,0),boat+Vector2(400,0)])
	map.set_active_objective(task)
	_check(visual.get_visual_snapshot().facility_count == 5, "late relay presents all five stations")
	task.kind = &"escort"
	task.completed = true
	task.target_active = false
	map.set_active_objective(task)
	_check(visual.get_visual_snapshot().visible, "escort delivery keeps the bounded completion fold")
	map.advance_presentation(0.51)
	_check(not visual.get_visual_snapshot().visible, "completed boat vanishes after owner advances the half-second finish")
	map.configure(Definition)
	_check(not visual.get_visual_snapshot().visible, "restart clears escort and lingering completion art")
	layer.queue_free()
	map.queue_free()
	camera.queue_free()
	await process_frame
	root.get_node("AudioDirector").shutdown()
	print("ENDLESS_ESCORT_VISUAL_3_17: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL",_failures])
	quit(0 if _failures == 0 else 1)

func _settle() -> void:
	for frame in 4: await process_frame

func _save(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://build/test-runtime/endless-boss-ui-317")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(label+".png"))

func _check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		_failures += 1
		push_error("FAIL "+label)
