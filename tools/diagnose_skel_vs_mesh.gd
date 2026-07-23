extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)

	print("mesh aabb=", mesh.get_aabb())
	print("skel transform=", skel.transform)
	print("armature=", skel.get_parent().transform if skel.get_parent() else null)
	print("root=", root.transform)

	# Print chain of global bone origins from root to foot
	print("\n=== bone global origins (rest) ===")
	for name in ["Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck", "head", "thigh_l", "calf_l", "foot_l", "ball_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		var i := skel.find_bone(name)
		if i < 0:
			print(name, " missing")
			continue
		var g := skel.get_bone_global_pose(i)
		var rest := skel.get_bone_rest(i)
		print("%s  global_o=%s  rest_o=%s  parent=%s" % [
			name, g.origin, rest.origin,
			skel.get_bone_name(skel.get_bone_parent(i)) if skel.get_bone_parent(i) >= 0 else "-"
		])

	# Where are mesh verts relative to thigh bone?
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var thigh := skel.find_bone("thigh_l")
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var n := 0
	for vi in range(verts.size()):
		var base := vi * 4
		if bones_a[base] == thigh and weights_a[base] > 0.7:
			mn = mn.min(verts[vi])
			mx = mx.max(verts[vi])
			n += 1
	print("\nthigh-dominated verts aabb ", mn, " .. ", mx, " n=", n)
	print("thigh bone at ", skel.get_bone_global_pose(thigh).origin)

	# Head verts
	var head := skel.find_bone("head")
	mn = Vector3(1e9, 1e9, 1e9)
	mx = Vector3(-1e9, -1e9, -1e9)
	n = 0
	for vi in range(verts.size()):
		var base := vi * 4
		if bones_a[base] == head and weights_a[base] > 0.7:
			mn = mn.min(verts[vi])
			mx = mx.max(verts[vi])
			n += 1
	print("head-dominated verts aabb ", mn, " .. ", mx, " n=", n)
	print("head bone at ", skel.get_bone_global_pose(head).origin)

	quit(0)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f := _find_mesh(c)
		if f:
			return f
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
