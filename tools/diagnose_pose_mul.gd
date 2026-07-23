extends SceneTree
## Confirm posing must multiply onto initial pose rotation (not replace it).


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")

	skel.reset_bone_poses()
	var initial_rot := skel.get_bone_pose_rotation(thigh)
	var rest_foot := skel.get_bone_global_pose(foot).origin
	var rest_calf := skel.get_bone_global_pose(calf).origin
	print("initial pose rot=", initial_rot)
	print("rest foot=", rest_foot, " calf=", rest_calf)

	# WRONG: replace
	skel.set_bone_pose_rotation(thigh, Quaternion(Vector3.RIGHT, 0.5))
	skel.force_update_all_bone_transforms()
	print("REPLACE foot=", skel.get_bone_global_pose(foot).origin)

	# RIGHT: multiply onto initial
	skel.reset_bone_poses()
	skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.RIGHT, 0.5))
	skel.force_update_all_bone_transforms()
	var foot_x := skel.get_bone_global_pose(foot).origin
	print("MUL X+0.5 foot=", foot_x, " d=", foot_x - rest_foot)

	skel.reset_bone_poses()
	skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.FORWARD, 0.5))
	skel.force_update_all_bone_transforms()
	var foot_z := skel.get_bone_global_pose(foot).origin
	print("MUL Z+0.5 foot=", foot_z, " d=", foot_z - rest_foot)

	skel.reset_bone_poses()
	skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.BACK, 0.5))
	skel.force_update_all_bone_transforms()
	var foot_zb := skel.get_bone_global_pose(foot).origin
	print("MUL -Z+0.5 foot=", foot_zb, " d=", foot_zb - rest_foot)

	skel.reset_bone_poses()
	skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.LEFT, 0.5))
	skel.force_update_all_bone_transforms()
	var foot_nx := skel.get_bone_global_pose(foot).origin
	print("MUL -X+0.5 foot=", foot_nx, " d=", foot_nx - rest_foot)

	# Also try smaller anatomical hip flex (raise knee forward)
	for ang in [0.3, 0.6, 0.9]:
		skel.reset_bone_poses()
		skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.RIGHT, ang))
		skel.force_update_all_bone_transforms()
		var f := skel.get_bone_global_pose(foot).origin
		var c := skel.get_bone_global_pose(calf).origin
		print("flex X ", ang, " foot.y=", f.y, " foot.z=", f.z, " calf.y=", c.y, " calf.z=", c.z)

	for ang in [0.3, 0.6, 0.9]:
		skel.reset_bone_poses()
		skel.set_bone_pose_rotation(thigh, initial_rot * Quaternion(Vector3.FORWARD, ang))
		skel.force_update_all_bone_transforms()
		var f := skel.get_bone_global_pose(foot).origin
		print("flex Z ", ang, " foot=", f, " d=", f - rest_foot)

	quit(0)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
