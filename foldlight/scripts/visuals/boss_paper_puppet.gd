extends RefCounted
## Art-only articulated paper models. Call from CanvasItem._draw().
## Templates contain one ordered vertex-colored surface per paper part; the
## bounded six-model cache retains every Mesh RID used by canvas commands.
## No nodes, simulation clocks, random calls or per-frame mesh rebuilds.
## Pose: phase 0..2, time, motion_scale 0..1, intro 0..1 (1 = unfolded),
## charge/recoil/stagger/flash 0..1, transition 0..1 + transition_active,
## death 0..1, direction Vector2. Caller owns the outer hit-reaction transform.

const Palette = preload("res://scripts/ui/foldlight_theme.gd")
const Batch = preload("res://scripts/visuals/paper_draw_batch.gd")
const IDS: Array[StringName] = [&"reef_crown_battery", &"inverted_archivist", &"origami_judge", &"tide_loom_mother", &"torn_page_executioner", &"eclipse_twin_bells"]
const SHADOW := Color("061119")
const REEF := Color("a49772")
const PAGE := Color("c4ccc0")
const FOIL := Color("bda379")
static var _models: Dictionary = {}


static func draw_puppet(canvas: CanvasItem, boss_id: StringName, pose: Dictionary) -> void:
	var model := _get_model(boss_id)
	var parts: Array = model["parts"]
	var death := clampf(float(pose.get("death", 0.0)), 0.0, 1.0)
	if death >= 1.0:
		return
	var flash := clampf(float(pose.get("flash", 0.0)), 0.0, 1.0)
	var stagger := clampf(float(pose.get("stagger", 0.0)), 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.20, 1.0, death)
	for index in parts.size():
		var part: Dictionary = parts[index]
		var tint := Color(1.0 + flash * 0.52, 1.0 + flash * 0.52, 1.0 + flash * 0.52, fade)
		if StringName(part["role"]) == &"core":
			tint = tint.lerp(Color(0.55, 1.22, 1.80, fade), stagger)
		var mesh := part["mesh"] as ArrayMesh
		canvas.draw_mesh(mesh, null, _part_transform(boss_id, part, pose), tint)


static func get_visual_bounds(boss_id: StringName) -> Rect2:
	# Fully opened living silhouette, excluding the short death dispersal.
	match boss_id:
		&"reef_crown_battery": return Rect2(-153, -146, 306, 267)
		&"inverted_archivist": return Rect2(-133, -119, 266, 277)
		&"tide_loom_mother": return Rect2(-190, -130, 380, 272)
		&"torn_page_executioner": return Rect2(-146, -181, 292, 359)
		&"eclipse_twin_bells": return Rect2(-189, -151, 378, 297)
		_: return Rect2(-196, -146, 392, 282)


static func get_visual_contract(boss_id: StringName) -> Dictionary:
	var model := _get_model(boss_id)
	return {"part_count": (model["parts"] as Array).size(), "surfaces_per_part": 1,
		"cached_models": _models.size(), "core_radius": 49.0 if boss_id == &"reef_crown_battery" else 42.0,
		"bounds": get_visual_bounds(boss_id), "procedural": true}


static func get_part_transforms(boss_id: StringName, pose: Dictionary) -> Array[Transform2D]:
	var result: Array[Transform2D] = []
	var model := _get_model(boss_id)
	for part: Dictionary in model["parts"]:
		result.append(_part_transform(boss_id, part, pose))
	return result


static func _get_model(boss_id: StringName) -> Dictionary:
	var resolved := boss_id if IDS.has(boss_id) else &"origami_judge"
	if not _models.has(resolved):
		var parts: Array[Dictionary] = []
		match resolved:
			&"reef_crown_battery": _build_reef(parts)
			&"inverted_archivist": _build_archivist(parts)
			&"tide_loom_mother": _build_loom(parts)
			&"torn_page_executioner": _build_executioner(parts)
			&"eclipse_twin_bells": _build_bells(parts)
			_: _build_judge(parts)
		_models[resolved] = {"parts": parts}
	return _models[resolved]


static func _add(parts: Array[Dictionary], mesh: ArrayMesh, origin: Vector2, angle: float, role: StringName, side: float = 0.0, order: int = 0) -> void:
	parts.append({"mesh": mesh, "origin": origin, "angle": angle, "role": role, "side": side, "order": order})


static func _part_transform(boss_id: StringName, part: Dictionary, pose: Dictionary) -> Transform2D:
	var motion := clampf(float(pose.get("motion_scale", 1.0)), 0.0, 1.0)
	var time := float(pose.get("time", 0.0)) * motion
	var intro := lerpf(1.0, clampf(float(pose.get("intro", 1.0)), 0.0, 1.0), motion)
	var charge := clampf(float(pose.get("charge", 0.0)), 0.0, 1.0) * motion
	var charging := motion if bool(pose.get("charging", false)) else 0.0
	var commanding := motion if bool(pose.get("command_frenzy", false)) else 0.0
	var recoil := clampf(float(pose.get("recoil", 0.0)), 0.0, 1.0) * motion
	var stagger := clampf(float(pose.get("stagger", 0.0)), 0.0, 1.0) * motion
	var phase := clampi(int(pose.get("phase", 0)), 0, 2)
	var death := clampf(float(pose.get("death", 0.0)), 0.0, 1.0)
	var change := sin(clampf(float(pose.get("transition", 1.0)), 0.0, 1.0) * PI) * motion if bool(pose.get("transition_active", false)) else 0.0
	var side := float(part["side"])
	var order := int(part["order"])
	var role := StringName(part["role"])
	var origin := Vector2(part["origin"])
	var angle := float(part["angle"])
	var scale := Vector2.ONE * lerpf(0.18, 1.0, smoothstep(0.0, 1.0, intro))
	var breathing := sin(time * 1.7 + float(order) * 0.83) * motion
	if role == &"petal":
		angle += side * ((1.0 - intro) * -0.52 + charge * 0.14 + stagger * 0.22 + change * 0.12)
		angle += breathing * 0.012
		origin += Vector2.from_angle(angle - PI * 0.5) * (charge * 5.0 - recoil * (12.0 + float(order % 3) * 2.0) + float(phase) * 2.0)
	elif role == &"folio":
		angle += side * ((1.0 - intro) * 0.55 - charge * 0.17 + stagger * 0.23 + change * 0.14)
		angle += breathing * (0.035 + float(order) * 0.008)
		origin += Vector2(side * (charge * 4.0 + stagger * 9.0), breathing * 2.0 - recoil * (9.0 - float(order)))
		scale.y *= 1.0 - charge * 0.10 + stagger * 0.06
	elif role == &"wing":
		angle += side * ((1.0 - intro) * 0.72 - charge * 0.22 - float(phase) * 0.035 + stagger * 0.28 + change * 0.18)
		angle += breathing * 0.018
		origin += Vector2(side * (float(phase) * 2.0 + stagger * 8.0 - recoil * 8.0), recoil * 5.0)
	elif role == &"sun":
		angle += sin(time * 0.3) * 0.045 + change * 0.18
		scale *= 1.0 + charge * 0.05 + stagger * 0.05
	elif role == &"tail":
		angle += side * (stagger * 0.2 + charge * 0.06) + breathing * 0.024
		origin.y += breathing * 2.0 + recoil * 5.0
	elif role == &"shuttle":
		origin.x += side * (sin(time * (2.0 + commanding * 4.0) + float(order)) * (5.0 + commanding * 8.0) * motion - charge * 18.0 + stagger * 14.0 + commanding * 15.0)
		origin.y += recoil * (12.0 + float(order) * 2.0)
		angle += side * ((1.0 - intro) * 0.65 + charge * 0.20 - stagger * 0.25)
	elif role == &"blade":
		angle += -charge * 0.38 + recoil * 0.52 + stagger * 0.32 + (1.0 - intro) * 0.8 + charging * 0.75
		origin.y += -charge * 22.0 + recoil * 35.0 + stagger * 15.0
		scale.y *= 1.0 + charging * 0.15
	elif role == &"bell":
		angle += side * (sin(time * 1.6 + side) * 0.065 * motion + charge * 0.24 - recoil * 0.30 + stagger * 0.19)
		origin.y += -charge * 9.0 + recoil * 12.0 + stagger * 8.0
		scale.x *= 1.0 - charge * 0.08
	elif role == &"eclipse":
		angle += time * 0.10 + charge * 0.15 + change * 0.22
		scale *= 1.0 + stagger * 0.10 - charge * 0.04
	elif role == &"core":
		# The damageable light never drifts away from the actor's physical origin.
		scale *= 1.0 + charge * 0.035 - recoil * 0.06 + stagger * 0.05
	else:
		origin.y += breathing * 1.1 + recoil * 3.0
	if death > 0.0:
		var ray := origin.normalized()
		if ray.is_zero_approx():
			ray = Vector2.from_angle(float(order) * 2.399 + 0.7)
		origin += ray * death * motion * (28.0 if role == &"core" else 72.0 + float(order % 4) * 13.0)
		origin.y += death * death * motion * 36.0
		angle += death * motion * (side if not is_zero_approx(side) else sin(float(order) + 1.0)) * 0.85
		scale *= 1.0 - death * motion * 0.25
	return Transform2D(angle, scale, 0.0, origin)


static func _build_reef(parts: Array[Dictionary]) -> void:
	# Seven tall, independently hinged cannon petals form a coral crown.
	for index in 7:
		var offset := float(index - 3)
		var side := signf(offset)
		var b := Batch.new()
		var outline := PackedVector2Array([Vector2(-14,28),Vector2(-24,-17),Vector2(-15,-64),Vector2(0,-96),Vector2(19,-62),Vector2(26,-15),Vector2(15,28)])
		_folded(b, outline, Vector2(0,-18), REEF.darkened(absf(offset) * 0.035), Palette.GOLD, 2)
		b.draw_colored_polygon(PackedVector2Array([Vector2(-9,-59),Vector2(0,-78),Vector2(10,-59),Vector2(7,-43),Vector2(-7,-43)]), SHADOW)
		b.draw_colored_polygon(PackedVector2Array([Vector2(-5,-58),Vector2(0,-67),Vector2(5,-58),Vector2(0,-49)]), Palette.GOLD)
		b.draw_line(Vector2(-7,-35),Vector2(7,-35),Color(Palette.PAPER,0.65),1.1)
		_add(parts,b.build_mesh(),Vector2(offset*7.0,-18+absf(offset)*5),offset*0.31,&"petal",side,index)
	for side in [-1.0,1.0]:
		var b := Batch.new()
		_folded(b,_mirror(PackedVector2Array([Vector2(0,0),Vector2(58,16),Vector2(67,56),Vector2(25,73),Vector2(8,44)]),side),Vector2(side*27,29),Color("617e77"),Palette.FOLD,1)
		_add(parts,b.build_mesh(),Vector2(side*31,28),0.0,&"tail",side,1)
	var hull := Batch.new()
	_folded(hull,PackedVector2Array([Vector2(0,-65),Vector2(67,-36),Vector2(83,13),Vector2(59,65),Vector2(0,81),Vector2(-59,65),Vector2(-83,13),Vector2(-67,-36)]),Vector2(0,9),Color("69756c"),Palette.GOLD,2)
	for side in [-1.0,1.0]:
		_folded(hull,_mirror(PackedVector2Array([Vector2(12,-32),Vector2(51,-27),Vector2(62,13),Vector2(38,41),Vector2(19,28)]),side),Vector2(side*37,3),Color("b2b59a"),Palette.PAPER,1)
		hull.draw_line(Vector2(side*28,53),Vector2(side*48,46),Color(Palette.GOLD,0.75),2.0)
	_add(parts,hull.build_mesh(),Vector2.ZERO,0.0,&"body")
	var mask := Batch.new()
	_folded(mask,PackedVector2Array([Vector2(0,-48),Vector2(31,-22),Vector2(39,12),Vector2(23,44),Vector2(0,54),Vector2(-23,44),Vector2(-39,12),Vector2(-31,-22)]),Vector2(0,4),Color("c7c3a3"),Palette.PAPER,1)
	mask.draw_colored_polygon(PackedVector2Array([Vector2(0,-23),Vector2(23,-6),Vector2(20,24),Vector2(0,38),Vector2(-20,24),Vector2(-23,-6)]),SHADOW)
	mask.draw_polyline(PackedVector2Array([Vector2(-19,-6),Vector2(0,-18),Vector2(19,-6)]),Palette.GOLD,2.2,true)
	_add(parts,mask.build_mesh(),Vector2.ZERO,0.0,&"body")
	_add(parts,_lantern(Vector2(16,23),Palette.GOLD),Vector2(0,8),0.0,&"core")


static func _build_archivist(parts: Array[Dictionary]) -> void:
	for side in [-1.0,1.0]:
		for index in range(2,-1,-1):
			var b := Batch.new()
			var length := 71.0 + float(index % 2)*22.0
			# A dark book cover, staggered paper edges and a folded hanging leaf.
			b.draw_line(Vector2.ZERO,Vector2(0,19),Color(Palette.GOLD,0.65),1.3,true)
			var page := PackedVector2Array([Vector2(-12,16),Vector2(16,20),Vector2(21,length),Vector2(2,length+19),Vector2(-14,length-2)])
			_folded(b,page,Vector2(0,48),PAGE.darkened(float(index)*0.055),Palette.FOLD,2)
			b.draw_colored_polygon(PackedVector2Array([Vector2(2,length+19),Vector2(4,length-2),Vector2(21,length)]),Palette.PAPER)
			for line in 4:
				var y := 32.0+float(line)*8.0
				b.draw_line(Vector2(-7,y),Vector2(8-float(line%2)*3,y+1),Color(Palette.INK,0.38),1.0)
			b.draw_line(Vector2(-9,21),Vector2(-10,length-5),Color(Palette.GOLD,0.75),1.0)
			_add(parts,b.build_mesh(),Vector2(side*(35+index*25),-47+index*10),side*(0.10+index*0.10),&"folio",side,index)
	for side in [-1.0,1.0]:
		var b := Batch.new()
		_folded(b,_mirror(PackedVector2Array([Vector2(0,0),Vector2(34,-21),Vector2(84,-8),Vector2(68,15),Vector2(25,19)]),side),Vector2(side*34,2),Color("658b87"),Palette.PAPER,2)
		b.draw_polyline(_mirror(PackedVector2Array([Vector2(12,4),Vector2(35,-12),Vector2(72,-4)]),side),Color(Palette.GOLD,0.7),1.1)
		_add(parts,b.build_mesh(),Vector2(side*4,-53),side*-0.10,&"wing",side,1)
	var robe := Batch.new()
	_folded(robe,PackedVector2Array([Vector2(-34,-38),Vector2(34,-38),Vector2(42,16),Vector2(21,70),Vector2(0,109),Vector2(-21,70),Vector2(-42,16)]),Vector2(0,26),Color("618b85"),Palette.FOLD,2)
	for index in 4:
		var y := 51.0+float(index)*11.0
		robe.draw_line(Vector2(-10+index*1.5,y),Vector2(10-index*1.5,y),Color(Palette.GOLD,0.7),1.1)
	_add(parts,robe.build_mesh(),Vector2.ZERO,0.0,&"tail",0.0,3)
	var head := Batch.new()
	_folded(head,PackedVector2Array([Vector2(-45,-53),Vector2(0,-69),Vector2(45,-53),Vector2(52,-18),Vector2(26,14),Vector2(0,28),Vector2(-26,14),Vector2(-52,-18)]),Vector2(0,-16),PAGE,Palette.PAPER,2)
	head.draw_colored_polygon(PackedVector2Array([Vector2(-31,-27),Vector2(0,-37),Vector2(31,-27),Vector2(21,-7),Vector2(0,2),Vector2(-21,-7)]),SHADOW)
	head.draw_line(Vector2(-21,-19),Vector2(-6,-14),Palette.GOLD,2.0)
	head.draw_line(Vector2(6,-14),Vector2(21,-19),Palette.GOLD,2.0)
	_add(parts,head.build_mesh(),Vector2.ZERO,0.0,&"body")
	var book := Batch.new()
	for side in [-1.0,1.0]:
		_folded(book,_mirror(PackedVector2Array([Vector2(0,-7),Vector2(28,-20),Vector2(32,15),Vector2(7,27),Vector2(0,15)]),side),Vector2(side*12,5),Palette.PAPER,Palette.GOLD,1)
	book.draw_line(Vector2(0,-8),Vector2(0,26),SHADOW,2.0)
	_add(parts,book.build_mesh(),Vector2(0,11),0.0,&"body")
	_add(parts,_lantern(Vector2(8,15),Palette.GOLD),Vector2(0,-16),0.0,&"core")


static func _build_judge(parts: Array[Dictionary]) -> void:
	var sun := Batch.new()
	for ray in 12:
		var angle := float(ray)*TAU/12.0
		var points := PackedVector2Array([Vector2(0,-51),Vector2(8,-57),Vector2(5,-74 if ray%3==0 else -65),Vector2(-5,-74 if ray%3==0 else -65),Vector2(-8,-57)])
		var rotated := PackedVector2Array()
		for point in points:
			rotated.append(point.rotated(angle))
		_folded(sun,rotated,Vector2(0,-58).rotated(angle),FOIL.darkened(0.12),Palette.GOLD,0)
	_add(parts,sun.build_mesh(),Vector2(0,-15),0.0,&"sun")
	for side in [-1.0,1.0]:
		for index in range(2,-1,-1):
			var b := Batch.new()
			var length := 131.0-float(index)*18.0
			var wing := _mirror(PackedVector2Array([Vector2(0,0),Vector2(41,-27),Vector2(length,-54+index*7),Vector2(length-24,-13+index*10),Vector2(49,29),Vector2(14,23)]),side)
			var fill := Color("c4c8ad").darkened(float(index)*0.11)
			_folded(b,wing,Vector2(side*49,-1),fill,Palette.GOLD,2)
			b.draw_polyline(_mirror(PackedVector2Array([Vector2(19,8),Vector2(48,-13),Vector2(length-14,-42+index*7)]),side),Color(Palette.GOLD,0.85),1.3,true)
			for mark in 3:
				var mark_center := Vector2(side*(59+mark*13),-9+float(index)*4.0)
				b.draw_line(mark_center,mark_center+Vector2(side*3,7),Color(Palette.INK,0.32),1.1)
			_add(parts,b.build_mesh(),Vector2(side*(28-index*3),-12+index*23),side*float(index)*0.16,&"wing",side,index)
	for side in [-1.0,1.0]:
		var b := Batch.new()
		_folded(b,_mirror(PackedVector2Array([Vector2(0,0),Vector2(34,6),Vector2(43,57),Vector2(23,93),Vector2(4,69)]),side),Vector2(side*19,32),Color("9ca592"),Palette.GOLD,1)
		_add(parts,b.build_mesh(),Vector2(side*5,21),side*-0.03,&"tail",side,2)
	var face := Batch.new()
	_folded(face,PackedVector2Array([Vector2(0,-58),Vector2(34,-43),Vector2(48,-12),Vector2(36,30),Vector2(0,60),Vector2(-36,30),Vector2(-48,-12),Vector2(-34,-43)]),Vector2(0,-1),FOIL,Palette.PAPER,2)
	face.draw_colored_polygon(PackedVector2Array([Vector2(0,-38),Vector2(28,-24),Vector2(29,4),Vector2(16,25),Vector2(0,40),Vector2(-16,25),Vector2(-29,4),Vector2(-28,-24)]),SHADOW)
	for side in [-1.0,1.0]:
		_folded(face,_mirror(PackedVector2Array([Vector2(2,-32),Vector2(25,-22),Vector2(21,5),Vector2(8,24)]),side),Vector2(side*12,-10),Palette.PAPER,Palette.GOLD,0)
		face.draw_line(Vector2(side*9,-9),Vector2(side*23,-14),Palette.INK,3.0)
		face.draw_line(Vector2(side*11,-9),Vector2(side*19,-12),Palette.GOLD,1.0)
	face.draw_polyline(PackedVector2Array([Vector2(-12,31),Vector2(0,44),Vector2(12,31)]),Palette.GOLD,1.5,true)
	_add(parts,face.build_mesh(),Vector2.ZERO,0.0,&"body")
	_add(parts,_lantern(Vector2(7,21),Palette.GOLD),Vector2(0,1),0.0,&"core")


static func _build_loom(parts: Array[Dictionary]) -> void:
	# A broad weaving frame, eight hanging shuttles, and a low moth-like mask.
	var frame := Batch.new()
	for side in [-1.0, 1.0]:
		_folded(frame, _mirror(PackedVector2Array([Vector2(20,-65),Vector2(110,-101),Vector2(164,-48),Vector2(147,4),Vector2(105,-55),Vector2(30,-35)]), side), Vector2(side*100,-65), Color("638b7c"), Palette.FOLD, 2)
		frame.draw_line(Vector2(side*48,-52), Vector2(side*161,38), Color(Palette.GOLD,0.70), 2.0)
	_add(parts, frame.build_mesh(), Vector2.ZERO, 0.0, &"body")
	for side in [-1.0, 1.0]:
		for index in 4:
			var shuttle := Batch.new()
			var length := 65.0 + float(index % 2)*22.0
			shuttle.draw_line(Vector2(0,-47),Vector2(0,-15),Color(Palette.FOLD,0.66),1.8)
			_folded(shuttle,PackedVector2Array([Vector2(0,-21),Vector2(15,9),Vector2(9,length-13),Vector2(0,length),Vector2(-9,length-13),Vector2(-15,9)]),Vector2(0,22),Color("abc7ae"),Palette.PAPER,2)
			shuttle.draw_colored_polygon(PackedVector2Array([Vector2(0,7),Vector2(6,22),Vector2(0,40),Vector2(-6,22)]),SHADOW)
			shuttle.draw_line(Vector2(0,15),Vector2(0,33),Palette.FOLD,2.0)
			_add(parts,shuttle.build_mesh(),Vector2(side*(48+index*31),-16+index*5),side*(0.04+float(index)*0.055),&"shuttle",side,index)
	var body := Batch.new()
	_folded(body,PackedVector2Array([Vector2(0,-75),Vector2(42,-44),Vector2(62,12),Vector2(35,71),Vector2(0,109),Vector2(-35,71),Vector2(-62,12),Vector2(-42,-44)]),Vector2(0,4),Color("748f79"),Palette.GOLD,2)
	for side in [-1.0, 1.0]:
		_folded(body,_mirror(PackedVector2Array([Vector2(5,-35),Vector2(47,-18),Vector2(34,19),Vector2(9,33)]),side),Vector2(side*23,-1),Color("d0d6b6"),Palette.PAPER,1)
		body.draw_line(Vector2(side*15,-7),Vector2(side*35,-15),SHADOW,4.0)
		body.draw_line(Vector2(side*17,-8),Vector2(side*31,-13),Palette.FOLD,1.5)
	for index in 4:
		var y := 46.0+float(index)*11.0
		body.draw_line(Vector2(-22+index*4,y),Vector2(22-index*4,y),Color(Palette.GOLD,0.8),1.5)
	_add(parts,body.build_mesh(),Vector2.ZERO,0.0,&"body")
	_add(parts,_lantern(Vector2(11,27),Palette.FOLD),Vector2(0,9),0.0,&"core")


static func _build_executioner(parts: Array[Dictionary]) -> void:
	# Asymmetric torn cloak and a raised guillotine sheet distinguish the dash.
	for side in [-1.0, 1.0]:
		for index in 2:
			var cloak := Batch.new()
			var length := 100.0+float(index)*25.0
			_folded(cloak,_mirror(PackedVector2Array([Vector2(0,-23),Vector2(44,4),Vector2(58,length-25),Vector2(39,length-40),Vector2(31,length),Vector2(14,length-24),Vector2(0,58)]),side),Vector2(side*24,39),Color("77738f").darkened(index*0.12),Palette.PAPER,2)
			cloak.draw_line(Vector2(side*15,18),Vector2(side*31,length-41),Color(Palette.GOLD,0.65),1.5)
			_add(parts,cloak.build_mesh(),Vector2(side*(24+index*25),-28+index*9),side*-0.15,&"folio",side,index)
	var beam := Batch.new()
	_folded(beam,PackedVector2Array([Vector2(-113,-94),Vector2(92,-111),Vector2(116,-83),Vector2(-106,-62)]),Vector2(0,-87),Color("777480"),Palette.GOLD,2)
	_add(parts,beam.build_mesh(),Vector2.ZERO,0.0,&"body")
	var blade := Batch.new()
	_folded(blade,PackedVector2Array([Vector2(-16,-139),Vector2(28,-152),Vector2(49,-91),Vector2(40,64),Vector2(-22,105),Vector2(-16,40)]),Vector2(10,-33),Color("cbd0c4"),Palette.PAPER,2)
	blade.draw_colored_polygon(PackedVector2Array([Vector2(27,-123),Vector2(37,-89),Vector2(30,58),Vector2(15,69)]),Color("48445a"))
	blade.draw_line(Vector2(-11,72),Vector2(33,44),Palette.GOLD,3.0)
	_add(parts,blade.build_mesh(),Vector2(80,-4),-0.09,&"blade",1.0,1)
	var hood := Batch.new()
	_folded(hood,PackedVector2Array([Vector2(0,-85),Vector2(44,-35),Vector2(36,38),Vector2(0,67),Vector2(-43,35),Vector2(-48,-26)]),Vector2(0,-2),Color("858393"),Palette.PAPER,2)
	hood.draw_colored_polygon(PackedVector2Array([Vector2(0,-50),Vector2(29,-21),Vector2(21,22),Vector2(0,37),Vector2(-26,16),Vector2(-29,-20)]),SHADOW)
	hood.draw_polyline(PackedVector2Array([Vector2(-21,-17),Vector2(0,-7),Vector2(19,-20)]),Palette.GOLD,3.0,true)
	_add(parts,hood.build_mesh(),Vector2.ZERO,0.0,&"body")
	_add(parts,_lantern(Vector2(8,19),Palette.GOLD),Vector2(0,14),0.0,&"core")


static func _build_bells(parts: Array[Dictionary]) -> void:
	var eclipse := Batch.new()
	for ray in 10:
		var angle := float(ray)*TAU/10.0
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		_folded(eclipse,PackedVector2Array([direction*82.0-side*9.0,direction*112.0,direction*97.0+side*14.0,direction*74.0+side*10.0]),direction*89.0,FOIL,Palette.GOLD,0)
	_add(parts,eclipse.build_mesh(),Vector2(0,-20),0.0,&"eclipse")
	var yoke := Batch.new()
	_folded(yoke,PackedVector2Array([Vector2(-151,-64),Vector2(-90,-98),Vector2(0,-72),Vector2(90,-98),Vector2(151,-64),Vector2(104,-50),Vector2(0,-48),Vector2(-104,-50)]),Vector2(0,-59),Color("a28d64"),Palette.PAPER,2)
	_add(parts,yoke.build_mesh(),Vector2.ZERO,0.0,&"body")
	for side in [-1.0,1.0]:
		var bell := Batch.new()
		bell.draw_line(Vector2(0,-53),Vector2(0,-30),Palette.GOLD,3.0)
		_folded(bell,PackedVector2Array([Vector2(-23,-30),Vector2(23,-30),Vector2(31,17),Vector2(52,47),Vector2(43,65),Vector2(-43,65),Vector2(-52,47),Vector2(-31,17)]),Vector2(0,18),Color("c2a97a") if side<0.0 else Color("a9b2a3"),Palette.PAPER,2)
		bell.draw_colored_polygon(PackedVector2Array([Vector2(-34,45),Vector2(34,45),Vector2(26,59),Vector2(-26,59)]),SHADOW)
		bell.draw_line(Vector2(-32,36),Vector2(32,36),Palette.GOLD,2.0)
		for index in 3:
			var x := float(index-1)*15.0
			bell.draw_line(Vector2(x,-11),Vector2(x,13),Color(Palette.INK,0.48),2.0)
		_add(parts,bell.build_mesh(),Vector2(side*106,10),0.0,&"bell",side,0 if side<0.0 else 1)
		_add(parts,_lantern(Vector2(9,21),Palette.GOLD),Vector2(side*106,82),0.0,&"tail",side,1)
	var core := Batch.new()
	_folded(core,PackedVector2Array([Vector2(0,-54),Vector2(37,-31),Vector2(47,15),Vector2(25,45),Vector2(0,70),Vector2(-25,45),Vector2(-47,15),Vector2(-37,-31)]),Vector2(0,3),Color("aea382"),Palette.GOLD,2)
	core.draw_colored_polygon(PackedVector2Array([Vector2(0,-34),Vector2(26,-14),Vector2(25,19),Vector2(0,43),Vector2(-25,19),Vector2(-26,-14)]),SHADOW)
	core.draw_line(Vector2(-17,-10),Vector2(17,-10),Palette.GOLD,2.0)
	_add(parts,core.build_mesh(),Vector2.ZERO,0.0,&"body")
	_add(parts,_lantern(Vector2(12,24),Palette.GOLD),Vector2(0,13),0.0,&"core")


static func _lantern(half_size: Vector2, light: Color) -> ArrayMesh:
	var b := Batch.new()
	var outline := PackedVector2Array([Vector2(0,-half_size.y),Vector2(half_size.x,-half_size.y*0.28),Vector2(half_size.x*0.7,half_size.y*0.5),Vector2(0,half_size.y),Vector2(-half_size.x*0.7,half_size.y*0.5),Vector2(-half_size.x,-half_size.y*0.28)])
	b.draw_colored_polygon(outline,light.darkened(0.18))
	b.draw_colored_polygon(PackedVector2Array([outline[0],outline[1],outline[3]]),light)
	b.draw_colored_polygon(PackedVector2Array([outline[0],outline[3],outline[5]]),Palette.PAPER)
	b.draw_line(Vector2(0,-half_size.y*0.65),Vector2(0,half_size.y*0.65),Color.WHITE,1.4,true)
	return b.build_mesh()


static func _folded(batch: RefCounted, points: PackedVector2Array, ridge: Vector2, color: Color, trim: Color, detail: int) -> void:
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(1.5,3.5))
	batch.draw_colored_polygon(shadow,Color(SHADOW,0.88))
	# A fan of folded facets, all sharing an authored interior ridge.
	for index in points.size():
		var next := (index+1)%points.size()
		var shade := color.lightened(0.10) if index%3==0 else color.darkened(0.12 if index%3==1 else 0.28)
		batch.draw_colored_polygon(PackedVector2Array([points[index],points[next],ridge]),shade)
	var edge := points.duplicate()
	edge.append(points[0])
	batch.draw_polyline(edge,Color(trim,0.66),1.15,true)
	if detail > 0:
		batch.draw_line(points[0],ridge,Color(Palette.PAPER,0.58),1.0,true)
		batch.draw_line(points[int(points.size()/2)],ridge,Color(Palette.INK,0.62),1.0,true)
	if detail > 1:
		batch.draw_line(points[1].lerp(ridge,0.13),ridge.lerp(points[0],0.12),Color(trim,0.56),0.8,true)


static func _mirror(points: PackedVector2Array, side: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(Vector2(point.x*side,point.y))
	return result
