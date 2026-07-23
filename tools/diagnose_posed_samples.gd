extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)
	var skin: Skin = mesh.skin
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]

	print("mesh aabb=", mesh.get_aabb())
	print("bone thigh=", skel.get_bone_global_pose(skel.find_bone("thigh_l")).origin)
	print("bone calf=", skel.get_bone_global_pose(skel.find_bone("calf_l")).origin)
	print("bone foot=", skel.get_bone_global_pose(skel.find_bone("foot_l")).origin)

	# Sample verts by dominant bone
	for target in ["thigh_l", "calf_l", "foot_l", "ball_l"]:
		var bi := skel.find_bone(target)
		var found := 0
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for vi in range(verts.size()):
			var base := vi * 4
			if bones_a[base] != bi or weights_a[base] < 0.75:
				continue
			mn = mn.min(verts[vi])
			mx = mx.max(verts[vi])
			found += 1
		print(target, " dominated verts n=", found, " aabb ", mn, "..", mx)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.LEFT, 0.55))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 0.7))
	skel.force_update_all_bone_transforms()

	print("\nAfter pose bones:")
	print(" thigh=", skel.get_bone_global_pose(thigh).origin)
	print(" calf=", skel.get_bone_global_pose(calf).origin)
	print(" foot=", skel.get_bone_global_pose(skel.find_bone("foot_l")).origin)

	# Skin a few dominated verts and see if they stay near their bones
	for target in ["thigh_l", "calf_l", "foot_l"]:
		var bi := skel.find_bone(target)
		var bone_o := skel.get_bone_global_pose(bi).origin
		var shown := 0
		for vi in range(verts.size()):
			var base := vi * 4
			if bones_a[base] != bi or weights_a[base] < 0.85:
				continue
			var skinned := _skin(verts[vi], vi, bones_a, weights_a, skel, skin)
			var dist := skinned.distance_to(bone_o)
			print(" ", target, " v", vi, " bind=", verts[vi], " skin=", skinned, " dist_to_bone=", dist)
			shown += 1
			if shown >= 2:
				break

	# Check surface count / lod
	var am := mesh.mesh as ArrayMesh
	print("\nsurfaces=", am.get_surface_count(), " lods=", am.get_lods().size() if am.has_method("get_lods") else "?")
	print("skin binds=", skin.get_bind_count())

	quit(0)


func _skin(v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array, skel: Skeleton3D, skin: Skin) -> Vector3:
	var base := vi * 4
	var acc := Vector3.ZERO
	var wsum := 0.0
	for k in range(4):
		var bone_idx: int = bones_a[base + k]
		var w: float = weights_a[base + k]
		if w <= 0.0:
			continue
		var bname := skel.get_bone_name(bone_idx)
		var bind_i := -1
		for bi in range(skin.get_bind_count()):
			if skin.get_bind_name(bi) == bname:
				bind_i = bi
				break
		if bind_i < 0:
			continue
		acc += (skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_i)) * v * w
		wsum += w
	return acc / wsum if wsum > 0.0 else v


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
