extends SceneTree

const Puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const OUTPUT := "res://captures/boss_puppets"
const TITLES: Array[String] = ["礁冠炮台", "倒悬档案官", "折纸审判者"]
var previews: Array[Node2D] = []
var caption: Label
var errors: int = 0

class Preview extends Node2D:
	var boss_id: StringName
	var pose: Dictionary = {}
	func _draw() -> void:
		Puppet.draw_puppet(self,boss_id,pose)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	(root.get_node("ProfileManager") as FoldlightProfileManager).persistence_enabled = false
	(root.get_node("AudioDirector") as FoldlightAudioDirector).shutdown()
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignored := FileAccess.open(OUTPUT.path_join(".gdignore"),FileAccess.WRITE)
	ignored.close()
	var background := ColorRect.new()
	background.color = Palette.INK
	background.size = Vector2(1920,1080)
	root.add_child(background)
	_label("折光  /  三首领纸雕形体",Vector2(66,38),34,Palette.PAPER)
	caption = _label("",Vector2(66,92),21,Palette.MUTED)
	for column in 3:
		var x := 320.0+float(column)*610.0
		_label(TITLES[column],Vector2(x-150,665),27,Palette.PAPER)
		var large := Preview.new()
		large.boss_id = Puppet.IDS[column]
		large.position = Vector2(x,390)
		large.scale = Vector2.ONE*1.8
		root.add_child(large)
		previews.append(large)
		var native := Preview.new()
		native.boss_id = Puppet.IDS[column]
		native.position = Vector2(x,870)
		root.add_child(native)
		previews.append(native)
	_label("上排 1.8 倍细节  ·  下排实际局部尺寸  ·  同一生产绘制 helper，非海报贴图",Vector2(66,1021),18,Palette.MUTED)
	var shots: Array[Dictionary] = [
		{"name":"01_idle","label":"待机 · 纸层自然错落，光核固定在实体原点","pose":{"time":1.2,"intro":1.0}},
		{"name":"02_charge","label":"攻击蓄势 · 炮瓣张开，书页收束，巨翼向上折起","pose":{"time":1.2,"charge":1.0,"phase":1}},
		{"name":"03_stagger","label":"返光破防 · 外壳展开，灯芯转为折光青","pose":{"time":1.2,"stagger":1.0,"phase":2}},
		{"name":"04_death","label":"击破 · 原有纸片分离、旋落，保持首领形体身份","pose":{"time":1.2,"death":0.48,"phase":2}},
		{"name":"05_intro","label":"入场展开 · 原点灯芯先显，分节纸片逐次舒展","pose":{"time":0.4,"intro":0.48}},
		{"name":"06_recoil","label":"发射后坐 · 炮瓣回缩、书页抖落、巨翼收紧","pose":{"time":1.2,"recoil":1.0,"phase":1}},
		{"name":"07_phase","label":"转场变形 · 折翼外翻，姿态落定后回到可读轮廓","pose":{"time":1.2,"phase":2,"transition_active":true,"transition":0.5}},
	]
	for shot in shots:
		caption.text = String(shot["label"])
		for preview in previews:
			preview.pose = shot["pose"]
			preview.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(OUTPUT).path_join(String(shot["name"])+".png")
		if root.get_texture().get_image().save_png(path) != OK:
			errors += 1
		print("CAPTURED " + path)
		print("PUPPET_DRAW_CALLS %s %.0f" % [shot["name"],Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	for preview in previews:
		preview.queue_free()
	await process_frame
	print("FOLDLIGHT_BOSS_PUPPET_CAPTURE: " + ("PASS" if errors == 0 else "FAIL"))
	quit(0 if errors == 0 else 1)

func _label(value: String, origin: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = origin
	label.add_theme_font_override("font",Palette.body_font())
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	root.add_child(label)
	return label
