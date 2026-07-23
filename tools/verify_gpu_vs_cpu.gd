extends SceneTree
## Side-by-side: GPU skinned mesh vs CPU-skinned duplicate. Proves where failure is.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 20, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.35, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40
	cam.position = Vector3(3.2, 1.05, 0.0)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)

	var packed: PackedScene = load("res://assets/humans/male_base.gltf")

	# Left: GPU skinning (original)
	var gpu_root: Node3D = packed.instantiate()
	gpu_root.position = Vector3(0, 0, -0.55)
	gpu_root.rotation.y = PI * 0.5
	world.add_child(gpu_root)
	var skel_gpu := _find_skel(gpu_root)
	_pose_leg(skel_gpu)

	# Right: CPU bake of same pose
	var cpu_root: Node3D = packed.instantiate()
	cpu_root.position = Vector3(0, 0, 0.55)
	cpu_root.rotation.y = PI * 0.5
	world.add_child(cpu_root)
	var skel_cpu := _find_skel(cpu_root)
	var mesh_cpu: MeshInstance3D = _find_mesh(cpu_root)
	_pose_leg(skel_cpu)
	_bake_cpu_skin(mesh_cpu, skel_cpu)
	# Detach from skeleton so only baked mesh shows
	mesh_cpu.skeleton = NodePath()
	mesh_cpu.skin = null

	# Labels via 3D text is heavy; print instead
	print("LEFT(z-) = GPU skinning, RIGHT(z+) = CPU baked skin")

	for _i in range(8):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	img.save_png("res://tools/pose_GPU_vs_CPU.png")
	print("saved pose_GPU_vs_CPU.png")
	quit(0)


func _pose_leg(skel: Skeleton3D) -> void:
	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.RIGHT, 0.75))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 1.0))
	skel.force_update_all_bone_transforms()


func _bake_cpu_skin(mesh: MeshInstance3D, skel: Skeleton3D) -> void:
	var skin: Skin = mesh.skin
	var src := mesh.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_a: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights_a: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var new_verts := PackedVector3Array()
		new_verts.resize(verts.size())
		for vi in range(verts.size()):
			new_verts[vi] = _skin_one(verts[vi], vi, bones_a, weights_a, skel, skin)
		arrays[Mesh.ARRAY_VERTEX] = new_verts
		# Remove skeleton arrays so it's a static mesh
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, src.surface_get_format(s) & ~(Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS))
		out.surface_set_material(s, src.surface_get_material(s))
	mesh.mesh = out


func _skin_one(
	v: Vector3, vi: int, bones_a: PackedInt32Array, weights_a: PackedFloat32Array,
	skel: Skeleton3D, skin: Skin
) -> Vector3:
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
