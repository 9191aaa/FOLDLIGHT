extends SceneTree

## Controlled GPU comparison using the production actors, damage entry points,
## simulation ticks and runtime contact FX. This is visual QA, not a balance run.
const OUTPUT := "res://captures/combat_feedback"
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const BOSS_SCENE: PackedScene = preload("res://scenes/roguelite/bosses/rogue_boss_actor.tscn")
const CONTENT: Array[StringName] = [&"drifter", &"fan", &"reef_crown_battery", &"inverted_archivist", &"origami_judge"]
const NAMES: Array[String] = ["潮漂兵", "潮翼", "礁冠炮台", "倒悬书记", "折纸裁判"]
const TIMES: Array[int] = [0, 3, 9, 18]

var _actors: Array[Node2D] = []
var _anchors: Array[Vector2] = []
var _runtimes: Array[FoldlightRogueCombatRuntime] = []
var _time_label: Label
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	_build_board()
	for row in 2:
		var runtime := FoldlightRogueCombatRuntime.new()
		root.add_child(runtime)
		runtime.set_process(false)
		runtime.set_physics_process(false)
		_runtimes.append(runtime)
		for column in CONTENT.size():
			var anchor := Vector2(240.0 + float(column) * 360.0, 350.0 + float(row) * 430.0)
			var actor: Node2D
			if column < 2:
				actor = FoldlightRogueEnemyFactory.create(FoldlightRogueContentCatalog.enemy_by_id(CONTENT[column]), StringName("capture_%d_%d" % [row, column]))
				root.add_child(actor)
				(actor as FoldlightRogueEnemyActor)._age = 3.0
			else:
				var boss := BOSS_SCENE.instantiate() as FoldlightRogueBossActor
				root.add_child(boss)
				boss.configure(FoldlightRogueContentCatalog.boss_by_id(CONTENT[column]), Rect2(anchor - Vector2(1440, 810), Vector2(2880, 1620)), 48001)
				boss.arena_controller.hide()
				actor = boss
			actor.global_position = anchor
			actor.set_process(false)
			actor.set_physics_process(false)
			_actors.append(actor)
			_anchors.append(anchor)
	await process_frame
	for index in _actors.size():
		var actor: Node2D = _actors[index]
		var row: int = index / CONTENT.size()
		var heavy: bool = row == 1
		var contact_radius: float = 108.0 if index % CONTENT.size() == 2 else (66.0 if actor is FoldlightRogueBossActor else (actor as FoldlightRogueEnemyActor).get_contact_radius())
		var direction := Vector2(1.0, -0.18).normalized()
		var amount: float = 22.4 if heavy and actor is FoldlightRogueBossActor else 0.5
		if actor is FoldlightRogueBossActor:
			(actor as FoldlightRogueBossActor).take_damage(amount, &"return" if heavy else &"weapon", direction)
		else:
			(actor as FoldlightRogueEnemyActor).take_projectile_damage(amount, direction * 650.0, &"return_light" if heavy else &"crease_petal")
		_runtimes[row]._register_enemy_hit_feedback(StringName("impact_%d" % index), actor.global_position - direction * contact_radius * 0.80, direction, amount, &"return" if heavy else &"weapon")
	for frame in 19:
		if TIMES.has(frame):
			_time_label.text = "命中后 %.2f 秒  ·  实际敌人绘制 + 接触特效" % (float(frame) / 60.0)
			await _save("impact_%03d" % frame)
		if frame < 18:
			_advance(1.0 / 60.0)
	for actor in _actors:
		actor.queue_free()
	for runtime in _runtimes:
		runtime.queue_free()
	await process_frame
	print("COMBAT_FEEDBACK_CAPTURE: %s" % ("PASS" if _errors == 0 else "FAIL"))
	quit(0 if _errors == 0 else 1)


func _advance(delta: float) -> void:
	for index in _actors.size():
		var actor: Node2D = _actors[index]
		actor.call("advance_simulation", delta, _anchors[index] - Vector2(300, 0))
		# Hold the review grid in place; every pose and effect still comes from
		# production drawing, without scaling actors or moving their hitboxes.
		actor.global_position = _anchors[index]
	for runtime in _runtimes:
		runtime._update_enemy_hit_vfx(delta)


func _build_board() -> void:
	var background := ColorRect.new()
	background.color = Palette.INK
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	_label("折光  /  命中反馈", Vector2(72, 42), 32, Palette.PAPER)
	_time_label = _label("", Vector2(72, 96), 21, Palette.MUTED)
	_label("普通射击", Vector2(72, 170), 25, Palette.PAPER)
	_label("短促局部破纸  ·  连发共用一次反馈", Vector2(270, 176), 19, Palette.MUTED)
	_label("返光重击", Vector2(72, 600), 25, Palette.FOLD)
	_label("普通敌人受创  ·  三首领真实触发返光破防", Vector2(270, 606), 19, Palette.MUTED)
	for column in CONTENT.size():
		for row in 2:
			_label(NAMES[column], Vector2(120 + column * 360, 504 + row * 430), 21, Palette.MUTED)
	_label("受击位移仅作用于绘制；伤害、物理范围、攻击随机序列保持一致。", Vector2(72, 1020), 18, Palette.MUTED)


func _label(value: String, origin: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = origin
	label.add_theme_font_override("font", Palette.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	root.add_child(label)
	return label


func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var destination: String = ProjectSettings.globalize_path(OUTPUT).path_join(filename + ".png")
	var error: Error = root.get_texture().get_image().save_png(destination)
	if error != OK:
		_errors += 1
		push_error("Combat feedback capture failed: %s" % error_string(error))
	else:
		print("CAPTURED " + destination)
