extends SceneTree
## Diagnose skeleton hierarchy + deformation when posing thigh.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)

	var skel := _find_skel(root)
	var mesh := _find_mesh(root)
	print("skel=", skel, " mesh=", mesh)
	print("mesh.skeleton=", mesh.skeleton if mesh else "?")
	print("mesh path=", mesh.get_path() if mesh else "?")
	print("skel path=", skel.get_path() if skel else "?")

	# Print hip chain parents
	for name in ["pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r"]:
		var i := skel.find_bone(name)
		if i < 0:
			print("MISSING bone ", name)
			continue
		var p := skel.get_bone_parent(i)
		var pname := skel.get_bone_name(p) if p >= 0 else "(none)"
		var rest := skel.get_bone_rest(i)
		print(
			"bone ", name, " idx=", i, " parent=", pname,
			" rest.origin=", rest.origin,
			" rest.basis=", rest.basis.get_euler()
		)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")

	# World positions of bone tips before pose
	print("--- BEFORE pose ---")
	_print_bone_global(skel, thigh, "thigh_l")
	_print_bone_global(skel, calf, "calf_l")
	_print_bone_global(skel, foot, "foot_l")
	print("mesh aabb=", mesh.get_aabb())
	print("mesh global_aabb=", mesh.global_transform * mesh.get_aabb())

	# Bend thigh ~45 deg
	skel.set_bone_pose_rotation(thigh, Quaternion(Vector3.RIGHT, 0.8))
	await process_frame
	await process_frame

	print("--- AFTER thigh pitch 0.8 ---")
	_print_bone_global(skel, thigh, "thigh_l")
	_print_bone_global(skel, calf, "calf_l")
	_print_bone_global(skel, foot, "foot_l")
	print("mesh aabb=", mesh.get_aabb())
	print("mesh global_aabb=", mesh.global_transform * mesh.get_aabb())

	# Also try rotating around local bone Y / Z
	skel.reset_bone_pose(thigh)
	skel.set_bone_pose_rotation(thigh, Quaternion(Vector3.FORWARD, 0.8))
	await process_frame
	print("--- AFTER thigh FORWARD 0.8 ---")
	_print_bone_global(skel, calf, "calf_l")
	_print_bone_global(skel, foot, "foot_l")
	print("mesh aabb=", mesh.get_aabb())

	skel.reset_bone_pose(thigh)
	skel.set_bone_pose_rotation(thigh, Quaternion(Vector3.UP, 0.8))
	await process_frame
	print("--- AFTER thigh UP 0.8 ---")
	_print_bone_global(skel, calf, "calf_l")
	_print_bone_global(skel, foot, "foot_l")
	print("mesh aabb=", mesh.get_aabb())

	quit(0)


func _print_bone_global(skel: Skeleton3D, idx: int, label: String) -> void:
	var t := skel.get_bone_global_pose(idx)
	print("  ", label, " global.origin=", t.origin, " euler=", t.basis.get_euler())


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
