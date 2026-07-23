extends SceneTree
## Which bones own the lowest (foot) vertices? Hip stretch diagnosis.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var mesh: MeshInstance3D = _find_mesh(root)
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]

	# Find lowest verts
	var order: Array[int] = []
	for i in range(verts.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return verts[a].y < verts[b].y)

	print("=== 15 lowest vertices ===")
	for n in range(15):
		var vi: int = order[n]
		_print_vert(skel, verts, bones_a, weights_a, vi)

	# Count weight mass per bone for verts with y < 0.2 (lower legs/feet in bind)
	var mass: Dictionary = {}
	var count_low := 0
	for vi in range(verts.size()):
		if verts[vi].y > 0.15:
			continue
		count_low += 1
		var base := vi * 4
		for k in range(4):
			var bi: int = bones_a[base + k]
			var w: float = weights_a[base + k]
			if w <= 0.0:
				continue
			var nm := skel.get_bone_name(bi)
			mass[nm] = float(mass.get(nm, 0.0)) + w

	print("\nlow-vert count (y<0.15)=", count_low)
	var keys: Array = mass.keys()
	keys.sort_custom(func(a, b): return mass[a] > mass[b])
	print("weight mass by bone:")
	for i in range(mini(20, keys.size())):
		print("  ", keys[i], "=", mass[keys[i]])

	# After posing thigh+calf with multiply, manually skin lowest 5 verts
	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.RIGHT, 0.7))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 0.9))
	skel.force_update_all_bone_transforms()

	var skin: Skin = mesh.skin
	print("\n=== lowest verts after pose (manual skin) ===")
	for n in range(8):
		var vi: int = order[n]
		var skinned := _skin(verts[vi], vi, bones_a, weights_a, skel, skin)
		print(" v", vi, " bind=", verts[vi], " skinned=", skinned, " dy=", skinned.y - verts[vi].y)

	# Check left-foot-ish verts (x>0, y low)
	print("\n=== left foot region (x>0.05, y<0.1) sample ===")
	var shown := 0
	for vi in order:
		if verts[vi].x < 0.05 or verts[vi].y > 0.1:
			continue
		var skinned2 := _skin(verts[vi], vi, bones_a, weights_a, skel, skin)
		_print_vert(skel, verts, bones_a, weights_a, vi)
		print("   skinned=", skinned2)
		shown += 1
		if shown >= 8:
			break

	# How many verts heavily weighted to thigh_l also have significant Root/pelvis?
	var weird := 0
	for vi in range(verts.size()):
		var base := vi * 4
		var w_thigh := 0.0
		var w_root := 0.0
		var w_pelvis := 0.0
		for k in range(4):
			var bi: int = bones_a[base + k]
			var w: float = weights_a[base + k]
			var nm := skel.get_bone_name(bi)
			if nm == "thigh_l":
				w_thigh += w
			elif nm == "Root":
				w_root += w
			elif nm == "pelvis":
				w_pelvis += w
		if w_thigh > 0.3 and (w_root > 0.2 or w_pelvis > 0.3):
			weird += 1
	print("\nverts with thigh_l>0.3 AND (Root>0.2 or pelvis>0.3): ", weird)

	quit(0)


func _print_vert(skel: Skeleton3D, verts: PackedVector3Array, bones_a: PackedInt32Array, weights_a: PackedFloat32Array, vi: int) -> void:
	var base := vi * 4
	var parts: PackedStringArray = []
	for k in range(4):
		var w: float = weights_a[base + k]
		if w <= 0.001:
			continue
		parts.append("%s:%.2f" % [skel.get_bone_name(bones_a[base + k]), w])
	print(" v", vi, " ", verts[vi], " [", ", ".join(parts), "]")


func _skin(v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array, skel: Skeleton3D, skin: Skin) -> Vector3:
	var base := vi * 4
	var out := Vector3.ZERO
	var wsum := 0.0
	for k in range(4):
		var bone_idx: int = bones_a[base + k]
		var w: float = weights_a[base + k]
		if w <= 0.0:
			continue
		var bind_i := -1
		var bname := skel.get_bone_name(bone_idx)
		for bi in range(skin.get_bind_count()):
			if skin.get_bind_name(bi) == bname:
				bind_i = bi
				break
		if bind_i < 0:
			continue
		out += (skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_i)) * v * w
		wsum += w
	return out / wsum if wsum > 0.0 else v


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
