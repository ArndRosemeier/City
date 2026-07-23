extends SceneTree
## Find which local axis bends the leg naturally; verify skin updates.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)

	print("skin=", mesh.skin)
	print("skeleton prop=", mesh.skeleton)
	if mesh.skin:
		print("skin binds=", mesh.skin.get_bind_count())

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")

	var rest_foot := skel.get_bone_global_pose(foot).origin
	print("rest foot=", rest_foot)

	for axis_name in ["X", "Y", "Z", "-X", "-Z"]:
		skel.reset_bone_poses()
		var axis := Vector3.RIGHT
		match axis_name:
			"X":
				axis = Vector3.RIGHT
			"Y":
				axis = Vector3.UP
			"Z":
				axis = Vector3.FORWARD
			"-X":
				axis = Vector3.LEFT
			"-Z":
				axis = Vector3.BACK
		skel.set_bone_pose_rotation(thigh, Quaternion(axis, 0.6))
		# force update
		skel.force_update_all_bone_transforms()
		await process_frame
		var foot_pos := skel.get_bone_global_pose(foot).origin
		var calf_pos := skel.get_bone_global_pose(calf).origin
		var delta := foot_pos - rest_foot
		print(
			"axis ", axis_name,
			" foot=", foot_pos,
			" dfoot=", delta,
			" calf=", calf_pos
		)

	# Sample a few mesh vertices via RenderingServer? Use get_aabb of custom
	# Check if MeshInstance has skeleton animation active
	print("mesh visible=", mesh.visible)
	print("cast_shadow=", mesh.cast_shadow)

	# Compare bind pose vertex y vs after - use ArrayMesh surface
	var arr_mesh := mesh.mesh as ArrayMesh
	if arr_mesh:
		var arrays := arr_mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		print("vert_count=", verts.size(), " bones_array=", bones_a.size(), " weights_array=", weights_a.size())
		# Find verts heavily weighted to thigh_l
		var thigh_idx := thigh
		var count_thigh := 0
		var sample := 0
		for vi in range(mini(verts.size(), 5000)):
			var base := vi * 4
			if base + 3 >= bones_a.size():
				break
			for k in range(4):
				if bones_a[base + k] == thigh_idx and weights_a[base + k] > 0.5:
					count_thigh += 1
					if sample < 3:
						print("  thigh-weighted vert ", vi, " pos=", verts[vi], " w=", weights_a[base + k])
						sample += 1
		print("verts strongly on thigh_l (first 5k): ", count_thigh)

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
