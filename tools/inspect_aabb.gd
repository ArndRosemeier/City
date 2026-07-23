extends SceneTree
## nipple AABB check


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	if packed == null:
		printerr("FAIL: could not load male_base.gltf")
		quit(1)
		return
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var mesh := _find_mesh(root)
	var skel := _find_skel(root)
	if mesh == null or skel == null:
		printerr("FAIL: missing MeshInstance3D or Skeleton3D")
		quit(1)
		return
	_report_joint_last_usage(mesh, skel)
	_play_idle(root, skel)
	await process_frame
	await process_frame
	skel.force_update_all_bone_transforms()
	await process_frame
	var local_aabb: AABB = mesh.get_aabb()
	var global_aabb: AABB = mesh.global_transform * local_aabb
	var skinned_aabb: AABB = _skinned_aabb(mesh, skel)
	print("local aabb pos=", local_aabb.position, " size=", local_aabb.size)
	print("global aabb pos=", global_aabb.position, " size=", global_aabb.size)
	print("skinned aabb pos=", skinned_aabb.position, " size=", skinned_aabb.size)
	print("skinned aabb length=", skinned_aabb.size.length())
	var aabb := global_aabb
	var center := aabb.position + aabb.size * 0.5
	print("aabb center=", center)
	print("size_ok=", aabb.size.x < 1.2 and aabb.size.y < 2.2 and aabb.size.z < 1.0)
	print("pos_y_ok=", aabb.position.y > 0.5, " center_y_ok=", center.y > 0.5)
	print("skinned size_ok=", skinned_aabb.size.x < 1.2 and skinned_aabb.size.y < 2.2 and skinned_aabb.size.z < 1.0)
	print("no_absurd=", not (aabb.size.y > 3.0 or aabb.size.length() > 4.0 or skinned_aabb.size.y > 3.0 or skinned_aabb.size.length() > 4.0))
	var pass_size := aabb.size.x < 1.2 and aabb.size.y < 2.2 and aabb.size.z < 1.0 and aabb.position.y > 0.5
	var absurd := aabb.size.y > 3.0 or aabb.size.length() > 4.0
	if pass_size and not absurd:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		print(" criteria failed; size=", aabb.size, " pos=", aabb.position)
		quit(1)


func _play_idle(body: Node, skel: Skeleton3D) -> void:
	var lib_path := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
	if not ResourceLoader.exists(lib_path):
		printerr("WARN: Quaternius lib missing; Idle skipped")
		return
	var lib_packed := load(lib_path)
	if not (lib_packed is PackedScene):
		printerr("WARN: Quaternius lib not PackedScene; Idle skipped")
		return
	var lib_root: Node = (lib_packed as PackedScene).instantiate()
	var src_player := _find_anim_player(lib_root)
	if src_player == null or not src_player.has_animation("Idle"):
		printerr("WARN: Idle animation missing")
		lib_root.free()
		return
	var player := AnimationPlayer.new()
	body.add_child(player)
	var library := AnimationLibrary.new()
	var copy: Animation = src_player.get_animation("Idle").duplicate(true) as Animation
	copy.loop_mode = Animation.LOOP_LINEAR
	for i in range(copy.get_track_count() - 1, -1, -1):
		var path := str(copy.track_get_path(i))
		if copy.track_get_type(i) == Animation.TYPE_POSITION_3D and path.ends_with(":Root"):
			copy.remove_track(i)
	library.add_animation("Idle", copy)
	player.add_animation_library("quat", library)
	lib_root.free()
	player.root_node = player.get_parent().get_path()
	player.play("quat/Idle")
	player.advance(0.0)
	skel.force_update_all_bone_transforms()


func _report_joint_last_usage(mesh: MeshInstance3D, skel: Skeleton3D) -> void:
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var vert_count := bones_a.size() / 4
	var last_idx := skel.get_bone_count() - 1
	var last_name := skel.get_bone_name(last_idx)
	var heavy := 0
	var any := 0
	for vi in range(vert_count):
		var base := vi * 4
		for k in range(4):
			if bones_a[base + k] == last_idx and weights_a[base + k] > 0.01:
				any += 1
				if weights_a[base + k] >= 0.25:
					heavy += 1
				break
	print("last joint idx=", last_idx, " name=", last_name, " verts_with_weight=", any, " verts_weight>=0.25=", heavy, " / ", vert_count)


func _skinned_aabb(mesh: MeshInstance3D, skel: Skeleton3D) -> AABB:
	var skin: Skin = mesh.skin
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for vi in range(verts.size()):
		var pnt := _skin_vertex(verts[vi], vi, bones_a, weights_a, skel, skin)
		mn = mn.min(pnt)
		mx = mx.max(pnt)
	return AABB(mn, mx - mn)


func _skin_vertex(v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array, skel: Skeleton3D, skin: Skin) -> Vector3:
	var base := vi * 4
	var out := Vector3.ZERO
	var wsum := 0.0
	for k in range(4):
		var bone_idx: int = bones_a[base + k]
		var wt: float = weights_a[base + k]
		if wt <= 0.0:
			continue
		var bname := skel.get_bone_name(bone_idx)
		var bind_i := -1
		for bi in range(skin.get_bind_count()):
			if skin.get_bind_name(bi) == bname:
				bind_i = bi
				break
		if bind_i < 0:
			continue
		out += (skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_i)) * v * wt
		wsum += wt
	if wsum <= 0.0:
		return v
	return out / wsum


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


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim_player(c)
		if f:
			return f
	return null
