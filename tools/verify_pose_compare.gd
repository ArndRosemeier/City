extends SceneTree
## Side-view screenshots: broken replace-pose vs fixed multiply-pose.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))

	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 2.0, 1.5)
	fill.light_energy = 0.6
	world.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.48)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.88)
	e.ambient_light_energy = 0.5
	env.environment = e
	world.add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.18, 0.2, 0.22)
	ground.material_override = gmat
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 35
	# Side view, slightly elevated
	cam.position = Vector3(2.8, 1.0, 0.15)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

	var packed: PackedScene = load("res://assets/humans/male_base.gltf")

	# --- Shot A: broken replace ---
	var body_a: Node3D = packed.instantiate()
	body_a.position = Vector3(0, 0, 0)
	body_a.rotation.y = PI * 0.5  # face +X toward camera-ish; camera is on +X
	world.add_child(body_a)
	var skel_a := _find_skel(body_a)
	var thigh_a := skel_a.find_bone("thigh_l")
	var calf_a := skel_a.find_bone("calf_l")
	skel_a.set_bone_pose_rotation(thigh_a, Quaternion(Vector3.RIGHT, 0.7))
	skel_a.set_bone_pose_rotation(calf_a, Quaternion(Vector3.RIGHT, 0.9))
	skel_a.force_update_all_bone_transforms()

	for _i in range(6):
		await process_frame
	var img_a: Image = get_root().get_viewport().get_texture().get_image()
	img_a.save_png("res://tools/pose_BROKEN_replace.png")
	print("saved BROKEN foot=", skel_a.get_bone_global_pose(skel_a.find_bone("foot_l")).origin)

	body_a.queue_free()
	await process_frame

	# --- Shot B: fixed multiply ---
	var body_b: Node3D = packed.instantiate()
	body_b.rotation.y = PI * 0.5
	world.add_child(body_b)
	var skel_b := _find_skel(body_b)
	var thigh_b := skel_b.find_bone("thigh_l")
	var calf_b := skel_b.find_bone("calf_l")
	var bt := skel_b.get_bone_pose_rotation(thigh_b)
	var bc := skel_b.get_bone_pose_rotation(calf_b)
	skel_b.set_bone_pose_rotation(thigh_b, bt * Quaternion(Vector3.RIGHT, 0.7))
	skel_b.set_bone_pose_rotation(calf_b, bc * Quaternion(Vector3.RIGHT, 0.9))
	skel_b.force_update_all_bone_transforms()

	for _i in range(6):
		await process_frame
	var img_b: Image = get_root().get_viewport().get_texture().get_image()
	img_b.save_png("res://tools/pose_FIXED_multiply.png")
	print("saved FIXED foot=", skel_b.get_bone_global_pose(skel_b.find_bone("foot_l")).origin)

	quit(0)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
