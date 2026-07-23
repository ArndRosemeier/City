extends SceneTree
## Pose limbs correctly, render a frame, save PNG proof.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	light.light_energy = 1.35
	world.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.48, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40
	cam.position = Vector3(0.0, 1.1, 2.4)
	cam.look_at(Vector3(0, 1.0, 0))
	world.add_child(cam)

	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var body: Node = packed.instantiate()
	body.rotation.y = PI
	world.add_child(body)
	var skel := _find_skel(body)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bind_thigh := skel.get_bone_pose_rotation(thigh)
	var bind_calf := skel.get_bone_pose_rotation(calf)

	# Hip flex + knee bend (same math as fixed inspect POC)
	skel.set_bone_pose_rotation(thigh, bind_thigh * Quaternion(Vector3.RIGHT, 0.7))
	skel.set_bone_pose_rotation(calf, bind_calf * Quaternion(Vector3.RIGHT, 0.9))
	skel.force_update_all_bone_transforms()

	var foot := skel.get_bone_global_pose(skel.find_bone("foot_l")).origin
	print("posed foot_l global=", foot)
	if foot.y > 0.2:
		push_error("FAIL: foot flipped above waist (y=%s)" % foot.y)
		quit(1)
		return
	if foot.y < -1.2:
		push_error("FAIL: foot sank unrealistically (y=%s)" % foot.y)
		quit(1)
		return
	print("PASS: foot still near ground plane after hip+knee bend")

	# Let renderer draw a few frames then capture
	for _i in range(8):
		await process_frame

	var img: Image = get_root().get_viewport().get_texture().get_image()
	var out_path := "res://tools/pose_proof.png"
	var err := img.save_png(out_path)
	print("saved ", out_path, " err=", err, " size=", img.get_width(), "x", img.get_height())
	quit(0 if err == OK else 2)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
