extends SceneTree
## Compare inverse-bind * bone_global at rest (should ~ Identity) and after pose.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)
	var skin: Skin = mesh.skin

	print("bind_count=", skin.get_bind_count(), " bone_count=", skel.get_bone_count())

	# Map bind index -> skeleton bone index
	var bad_rest := 0
	var checked := 0
	for bi in range(skin.get_bind_count()):
		var bname := skin.get_bind_name(bi)
		var bone_idx := skin.get_bind_bone(bi)
		if bone_idx < 0:
			bone_idx = skel.find_bone(bname)
		if bone_idx < 0:
			print("UNMATCHED bind ", bi, " name=", bname, " bone_prop=", skin.get_bind_bone(bi))
			continue
		var bind: Transform3D = skin.get_bind_pose(bi)
		var global: Transform3D = skel.get_bone_global_pose(bone_idx)
		# At rest, global * bind should be ~ identity (skinning: bone*bind*v)
		var composed := global * bind
		var origin_err := composed.origin.length()
		var qdiff: Quaternion = composed.basis.get_rotation_quaternion()
		var basis_err: float = absf(qdiff.w - 1.0) + absf(qdiff.x) + absf(qdiff.y) + absf(qdiff.z)
		checked += 1
		if origin_err > 0.05 or basis_err > 0.15:
			bad_rest += 1
			if bad_rest <= 12:
				print(
					"BAD rest bind ", bname,
					" origin_err=", origin_err,
					" basis_err=", basis_err,
					" composed_o=", composed.origin
				)
		elif bname in ["thigh_l", "calf_l", "pelvis", "spine_01", "upperarm_l"]:
			print("OK rest ", bname, " origin_err=", origin_err, " basis_err=", basis_err)

	print("checked=", checked, " bad_rest=", bad_rest)

	# Manual skin a thigh vertex at rest and after pose
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]

	var thigh := skel.find_bone("thigh_l")
	var sample_vi := -1
	for vi in range(verts.size()):
		var base := vi * 4
		if bones_a[base] == thigh and weights_a[base] > 0.8:
			sample_vi = vi
			break
	print("sample vert=", sample_vi, " pos=", verts[sample_vi] if sample_vi >= 0 else Vector3.ZERO)

	if sample_vi >= 0:
		var rest_skinned := _skin_vertex(verts[sample_vi], sample_vi, bones_a, weights_a, skel, skin)
		print("rest skinned=", rest_skinned, " bind_pos=", verts[sample_vi], " delta=", rest_skinned - verts[sample_vi])

		var bind_thigh := skel.get_bone_pose_rotation(thigh)
		skel.set_bone_pose_rotation(thigh, bind_thigh * Quaternion(Vector3.RIGHT, 0.7))
		skel.force_update_all_bone_transforms()
		var posed_skinned := _skin_vertex(verts[sample_vi], sample_vi, bones_a, weights_a, skel, skin)
		print("posed skinned=", posed_skinned, " move=", posed_skinned - rest_skinned)

		# What if bone indices in mesh are skin bind indices not skeleton indices?
		var alt := _skin_vertex_as_bind_indices(verts[sample_vi], sample_vi, bones_a, weights_a, skel, skin)
		print("alt (bones as bind idx) posed=", alt)

	# Print first few mesh bone indices vs names
	print("\nFirst vert bone indices:")
	for vi: int in [0, 41, 100, 500]:
		var base: int = vi * 4
		print(" v", vi, " bones=", [bones_a[base], bones_a[base+1], bones_a[base+2], bones_a[base+3]],
			" w=", [weights_a[base], weights_a[base+1], weights_a[base+2], weights_a[base+3]])
		for k in range(4):
			var bi2: int = bones_a[base + k]
			if bi2 >= 0 and bi2 < skel.get_bone_count():
				print("   skel[", bi2, "]=", skel.get_bone_name(bi2))
			if bi2 >= 0 and bi2 < skin.get_bind_count():
				print("   bind[", bi2, "]=", skin.get_bind_name(bi2))

	quit(0)


func _skin_vertex(
	v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array,
	skel: Skeleton3D, skin: Skin
) -> Vector3:
	var base := vi * 4
	var out := Vector3.ZERO
	var wsum := 0.0
	for k in range(4):
		var bone_idx: int = bones_a[base + k]
		var w: float = weights_a[base + k]
		if w <= 0.0 or bone_idx < 0:
			continue
		# Find bind for this skeleton bone
		var bind_i := _find_bind_for_bone(skin, skel, bone_idx)
		if bind_i < 0:
			continue
		var xform: Transform3D = skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_i)
		out += xform * v * w
		wsum += w
	if wsum > 0.0:
		out /= wsum
	return out


func _skin_vertex_as_bind_indices(
	v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array,
	skel: Skeleton3D, skin: Skin
) -> Vector3:
	var base := vi * 4
	var out := Vector3.ZERO
	var wsum := 0.0
	for k in range(4):
		var bind_i: int = bones_a[base + k]
		var w: float = weights_a[base + k]
		if w <= 0.0 or bind_i < 0 or bind_i >= skin.get_bind_count():
			continue
		var bname := skin.get_bind_name(bind_i)
		var bone_idx := skel.find_bone(bname)
		if bone_idx < 0:
			continue
		var xform: Transform3D = skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_i)
		out += xform * v * w
		wsum += w
	if wsum > 0.0:
		out /= wsum
	return out


func _find_bind_for_bone(skin: Skin, skel: Skeleton3D, bone_idx: int) -> int:
	var bname := skel.get_bone_name(bone_idx)
	for bi in range(skin.get_bind_count()):
		if skin.get_bind_name(bi) == bname:
			return bi
		if skin.get_bind_bone(bi) == bone_idx:
			return bi
	return -1


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
