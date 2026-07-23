extends SceneTree
## Does GPU/RenderingServer skeleton track pose changes?


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	await process_frame

	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)
	print("mesh path=", mesh.get_path())
	print("skel path=", skel.get_path())
	print("mesh.skeleton=", mesh.skeleton)
	print("mesh.skin=", mesh.skin)
	print("resolved skeleton node=", mesh.get_node_or_null(mesh.skeleton))

	var rid: RID = skel.get_skeleton_rid()
	print("skeleton rid valid=", rid.is_valid(), " rs bone count=", RenderingServer.skeleton_get_bone_count(rid))

	var thigh := skel.find_bone("thigh_l")
	var foot := skel.find_bone("foot_l")
	print("BEFORE godot thigh=", skel.get_bone_global_pose(thigh).origin)
	print("BEFORE rs thigh=", RenderingServer.skeleton_bone_get_transform(rid, thigh).origin)
	print("BEFORE rs foot=", RenderingServer.skeleton_bone_get_transform(rid, foot).origin)

	var bt := skel.get_bone_pose_rotation(thigh)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.RIGHT, 0.7))
	skel.force_update_all_bone_transforms()
	await process_frame
	await process_frame

	print("AFTER godot thigh=", skel.get_bone_global_pose(thigh).origin)
	print("AFTER godot foot=", skel.get_bone_global_pose(foot).origin)
	print("AFTER rs thigh=", RenderingServer.skeleton_bone_get_transform(rid, thigh).origin)
	print("AFTER rs foot=", RenderingServer.skeleton_bone_get_transform(rid, foot).origin)

	# Compare AABB via mesh get_aabb vs custom
	print("mesh aabb=", mesh.get_aabb())
	print("mesh global aabb=", mesh.global_transform * mesh.get_aabb())

	# Try explicit remap
	mesh.skeleton = mesh.get_path_to(skel)
	mesh.skin = mesh.skin
	skel.force_update_all_bone_transforms()
	await process_frame
	print("AFTER remap rs foot=", RenderingServer.skeleton_bone_get_transform(rid, foot).origin)

	# Check if show_rest_only
	print("show_rest_only=", skel.show_rest_only)
	print("animate_physical_bones=", skel.animate_physical_bones)
	print("modifier_callback_mode_process=", skel.modifier_callback_mode_process)

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
