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

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")

	var g0_foot := skel.get_bone_global_pose(foot)
	var g0_thigh := skel.get_bone_global_pose(thigh)
	var g0_calf := skel.get_bone_global_pose(calf)
	var v := verts[3672]  # foot_l weighted toe
	print("v=", v)
	print("g0 foot o=", g0_foot.origin)
	print("rigid rest check=", g0_foot * skin.get_bind_pose(_bind(skin, "foot_l")) * v)

	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	# Try small angle only
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.RIGHT, 0.3))
	skel.force_update_all_bone_transforms()
	var g1_foot := skel.get_bone_global_pose(foot)
	var g1_thigh := skel.get_bone_global_pose(thigh)
	print("\n--- after thigh X+0.3 only ---")
	print("thigh o ", g0_thigh.origin, " -> ", g1_thigh.origin)
	print("foot o  ", g0_foot.origin, " -> ", g1_foot.origin, " d=", g1_foot.origin - g0_foot.origin)
	var skinned := g1_foot * skin.get_bind_pose(_bind(skin, "foot_l")) * v
	print("toe skinned=", skinned, " d=", skinned - v)
	print("expected if followed bone origin delta=", v + (g1_foot.origin - g0_foot.origin))

	# Motion delta transform
	var delta_xform := g1_foot * g0_foot.affine_inverse()
	print("delta_xform * v=", delta_xform * v)
	print("delta_xform origin=", delta_xform.origin)
	print("delta_xform basis euler=", delta_xform.basis.get_euler())

	# What hinge looks like for a few axes with SMALL angle - measure toe movement
	print("\n=== toe delta for axes at 0.35 rad thigh only ===")
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
		skel.reset_bone_poses()
		# re-cache bind after reset - pose returns to initial
		bt = skel.get_bone_pose_rotation(thigh)
		skel.set_bone_pose_rotation(thigh, bt * Quaternion(axis, 0.35))
		skel.force_update_all_bone_transforms()
		var gf := skel.get_bone_global_pose(foot)
		var toe := gf * skin.get_bind_pose(_bind(skin, "foot_l")) * v
		print("axis=", axis, " toe=", toe, " d=", toe - v, " foot_o=", gf.origin)

	quit(0)


func _bind(skin: Skin, name: String) -> int:
	for i in range(skin.get_bind_count()):
		if skin.get_bind_name(i) == name:
			return i
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
