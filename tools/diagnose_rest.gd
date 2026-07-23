extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)

	print("=== bone rest scales / determinants ===")
	for name in ["root", "pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "foot_l", "upperarm_l"]:
		var i := skel.find_bone(name)
		if i < 0:
			print(name, " MISSING")
			continue
		var rest := skel.get_bone_rest(i)
		var basis := rest.basis
		var det := basis.determinant()
		var scale := basis.get_scale()
		print(
			name,
			" det=", det,
			" scale=", scale,
			" origin=", rest.origin,
			" pose_scale=", skel.get_bone_pose_scale(i)
		)

	var thigh := skel.find_bone("thigh_l")
	print("\n=== pose compose check thigh_l ===")
	skel.reset_bone_poses()
	print("pose rot identity?", skel.get_bone_pose_rotation(thigh).is_equal_approx(Quaternion.IDENTITY))
	print("global rest-like=", skel.get_bone_global_pose(thigh))

	# Small rotation
	skel.set_bone_pose_rotation(thigh, Quaternion(Vector3(1, 0, 0), 0.1))
	skel.force_update_all_bone_transforms()
	print("after 0.1 X pose=", skel.get_bone_pose_rotation(thigh))
	print("after 0.1 X global=", skel.get_bone_global_pose(thigh))
	print("calf global=", skel.get_bone_global_pose(skel.find_bone("calf_l")))

	# What does get_bone_pose return (full transform)?
	print("full pose xform=", skel.get_bone_pose(thigh))

	# Try using rotate_object_local style via set_bone_pose
	skel.reset_bone_poses()
	var pose := skel.get_bone_pose(thigh)
	print("initial pose (should be I)=", pose)
	# Apply rotation in parent space manually: new_pose = rest.inverse() * desired... 

	# Check if rest has negative scale by looking at basis columns
	var r := skel.get_bone_rest(thigh)
	print("rest basis X=", r.basis.x, " Y=", r.basis.y, " Z=", r.basis.z)
	print("rest orthonormalized det=", r.basis.orthonormalized().determinant())

	# Skin bind for thigh
	var mesh: MeshInstance3D = _find_mesh(root)
	var skin: Skin = mesh.skin
	var bind_i := -1
	for bi in range(skin.get_bind_count()):
		if skin.get_bind_name(bi) == "thigh_l" or skin.get_bind_bone(bi) == thigh:
			bind_i = bi
			print("bind ", bi, " name=", skin.get_bind_name(bi), " bone=", skin.get_bind_bone(bi))
			print("  bind pose=", skin.get_bind_pose(bi))
			var bp: Transform3D = skin.get_bind_pose(bi)
			print("  bind det=", bp.basis.determinant(), " scale=", bp.basis.get_scale())

	# Manual expected: parent_global * rest * pose
	skel.reset_bone_poses()
	var parent_i := skel.get_bone_parent(thigh)
	var parent_g := skel.get_bone_global_pose(parent_i)
	var rest_t := skel.get_bone_rest(thigh)
	var expected_id := parent_g * rest_t
	var actual_id := skel.get_bone_global_pose(thigh)
	print("\nexpected global (I)=", expected_id.origin, " actual=", actual_id.origin)
	print("expected basis~actual?", expected_id.basis.is_equal_approx(actual_id.basis))

	var q := Quaternion(Vector3(1, 0, 0), 0.6)
	var pose_t := Transform3D(Basis(q), Vector3.ZERO)
	var expected_rot := parent_g * rest_t * pose_t
	skel.set_bone_pose_rotation(thigh, q)
	skel.force_update_all_bone_transforms()
	var actual_rot := skel.get_bone_global_pose(thigh)
	print("expected after rot origin=", expected_rot.origin, " actual=", actual_rot.origin)
	print("expected after rot basis=", expected_rot.basis.get_euler())
	print("actual after rot basis=", actual_rot.basis.get_euler())
	print("match?", expected_rot.is_equal_approx(actual_rot))

	# Child expected
	var calf := skel.find_bone("calf_l")
	var calf_rest := skel.get_bone_rest(calf)
	var expected_calf := actual_rot * calf_rest
	var actual_calf := skel.get_bone_global_pose(calf)
	print("calf expected=", expected_calf.origin, " actual=", actual_calf.origin)

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
