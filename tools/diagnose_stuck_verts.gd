extends SceneTree
## After CPU skin pose: which left-leg verts failed to move?


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

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")
	var ball := skel.find_bone("ball_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.RIGHT, 0.75))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 1.0))
	skel.force_update_all_bone_transforms()

	print("bone foot=", skel.get_bone_global_pose(foot).origin)
	print("bone ball=", skel.get_bone_global_pose(ball).origin)
	print("bone calf=", skel.get_bone_global_pose(calf).origin)
	print("bone thigh=", skel.get_bone_global_pose(thigh).origin)

	var stuck := 0
	var moved := 0
	var stuck_examples: Array[String] = []
	var left_leg_bones := {thigh: true, calf: true, foot: true, ball: true}
	for vi in range(verts.size()):
		# Only consider verts that have majority weight on left leg chain
		var base := vi * 4
		var w_leg := 0.0
		var dominant := ""
		var dominant_w := 0.0
		for k in range(4):
			var bi: int = bones_a[base + k]
			var w: float = weights_a[base + k]
			if left_leg_bones.has(bi):
				w_leg += w
			if w > dominant_w:
				dominant_w = w
				dominant = skel.get_bone_name(bi)
		if w_leg < 0.5:
			continue
		var skinned := _skin(verts[vi], vi, bones_a, weights_a, skel, skin)
		var delta: float = skinned.distance_to(verts[vi])
		if delta < 0.02:
			stuck += 1
			if stuck_examples.size() < 10:
				stuck_examples.append("v%d bind=%s skin=%s dom=%s:%.2f w_leg=%.2f" % [vi, verts[vi], skinned, dominant, dominant_w, w_leg])
		else:
			moved += 1

	print("left-leg verts moved=", moved, " stuck=", stuck)
	for s in stuck_examples:
		print(" STUCK ", s)

	# AABB of skinned left-leg verts
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var count := 0
	for vi in range(verts.size()):
		var base := vi * 4
		var w_leg := 0.0
		for k in range(4):
			if left_leg_bones.has(bones_a[base + k]):
				w_leg += weights_a[base + k]
		if w_leg < 0.5:
			continue
		var skinned := _skin(verts[vi], vi, bones_a, weights_a, skel, skin)
		mn = mn.min(skinned)
		mx = mx.max(skinned)
		count += 1
	print("left-leg skinned AABB min=", mn, " max=", mx, " count=", count)

	# Also check: is get_bone_global_pose in skeleton space matching skin expectation?
	# Godot skinning uses skeleton space. Mesh is child of skeleton with identity transform?
	print("mesh transform=", mesh.transform)
	print("mesh global=", mesh.global_transform)

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
