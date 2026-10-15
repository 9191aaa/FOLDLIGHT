extends SceneTree

const Puppet = preload("res://scripts/visuals/boss_paper_puppet.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for boss_id in Puppet.IDS:
		var model: Dictionary = Puppet._get_model(boss_id)
		var parts: Array = model["parts"]
		_check(parts.size() <= 16, "%s uses at most sixteen articulated mesh submissions" % boss_id)
		var mesh_ids: Array[int] = []
		var total_vertices: int = 0
		var valid_meshes := true
		for part: Dictionary in parts:
			var mesh := part["mesh"] as ArrayMesh
			mesh_ids.append(mesh.get_instance_id())
			valid_meshes = valid_meshes and mesh.get_surface_count() == 1
			if mesh.get_surface_count() > 0:
				total_vertices += mesh.surface_get_array_len(0)
		_check(valid_meshes and total_vertices < 12000, "%s has valid one-surface paper pieces with bounded geometry" % boss_id)
		var rest := Puppet.get_part_transforms(boss_id, {"time": 1.0})
		var charged := Puppet.get_part_transforms(boss_id, {"time": 1.0, "charge": 1.0})
		var broken := Puppet.get_part_transforms(boss_id, {"time": 1.0, "stagger": 1.0})
		_check(rest != charged and charged != broken, "%s has distinct charging and opened break-window poses" % boss_id)
		var still := Puppet.get_part_transforms(boss_id, {"time": 1.0, "motion_scale": 0.0})
		var later := Puppet.get_part_transforms(boss_id, {"time": 99.0, "motion_scale": 0.0, "charge": 1.0, "recoil": 1.0, "intro": 0.0, "stagger": 1.0})
		_check(still == later, "%s honors zero-motion without unfolding, recoil or idle drift" % boss_id)
		_check(still == Puppet.get_part_transforms(boss_id, {"motion_scale": 0.0, "death": 0.7}), "%s keeps quiet death stationary while only its opacity fades" % boss_id)
		var finite := true
		for frame in 120:
			var progress := float(frame)/119.0
			var pose := {"time": progress*8.0, "intro": progress, "phase": frame%3, "charge": progress, "recoil": 1.0-progress, "stagger": progress, "death": progress, "transition_active": true, "transition": progress}
			for transform in Puppet.get_part_transforms(boss_id, pose):
				finite = finite and transform.is_finite()
		_check(finite, "%s maintains finite transforms across complete lifecycle progress" % boss_id)
		var unchanged := true
		for index in parts.size():
			unchanged = unchanged and mesh_ids[index] == (parts[index]["mesh"] as ArrayMesh).get_instance_id()
		_check(unchanged, "%s reuses the same mesh resources through animation" % boss_id)
		print("PUPPET %s parts=%d vertices=%d" % [boss_id,parts.size(),total_vertices])
	for index in 20:
		Puppet.get_visual_contract(StringName("unknown_%d" % index))
	_check(Puppet._models.size() == 3, "unknown preview ids cannot grow the three-model resource cache")
	seed(4281)
	var expected := randi()
	seed(4281)
	for boss_id in Puppet.IDS:
		Puppet.get_part_transforms(boss_id, {"phase": 2, "time": 4.5, "death": 0.7})
	_check(randi() == expected, "paper pose evaluation leaves gameplay random sequencing untouched")
	print("FOLDLIGHT_BOSS_PAPER_PUPPET: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] " + label)
	else:
		failures += 1
		push_error("[FAIL] " + label)
