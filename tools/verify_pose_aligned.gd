extends SceneTree
## Raised-knee proof with correctly fitted bones.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1400, 900))
	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2, 2, 1)
	fill.light_energy = 0.5
	world.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.38, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.88)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.16, 0.18)
	ground.material_override = gmat
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 38
	cam.position = Vector3(2.6, 1.0, 0.35)
	world.add_child(cam)
	cam.look_at(Vector3(0.05, 0.95, 0.0), Vector3.UP)

	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var body: Node3D = packed.instantiate()
	body.rotation.y = PI * 0.5
	world.add_child(body)
	var skel := _find_skel(body)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	# Hip flex + knee bend (deltas multiply onto bind pose)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.LEFT, 0.85))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 1.1))
	skel.force_update_all_bone_transforms()

	print("thigh=", skel.get_bone_global_pose(thigh).origin)
	print("calf=", skel.get_bone_global_pose(calf).origin)
	print("foot=", skel.get_bone_global_pose(skel.find_bone("foot_l")).origin)

	# Red markers on joints
	for bname in ["thigh_l", "calf_l", "foot_l", "pelvis"]:
		var bi := skel.find_bone(bname)
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.03
		sph.height = 0.06
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.15, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		skel.add_child(m)
		m.position = skel.get_bone_global_pose(bi).origin

	for _i in range(8):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	img.save_png("res://tools/pose_FIXED_aligned.png")
	print("saved pose_FIXED_aligned.png")
	quit(0)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
