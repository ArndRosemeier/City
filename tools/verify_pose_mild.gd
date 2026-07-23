extends SceneTree
## Milder hip flex only — clearer proof of clean deformation.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1400, 900))
	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.light_energy = 1.4
	world.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.28, 0.34, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.9)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 36
	cam.position = Vector3(2.4, 0.85, 0.5)
	world.add_child(cam)
	cam.look_at(Vector3(0.1, 0.85, 0.0), Vector3.UP)

	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var body: Node3D = packed.instantiate()
	body.rotation.y = PI * 0.5
	world.add_child(body)
	var skel := _find_skel(body)

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.LEFT, 0.55))
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.RIGHT, 0.7))
	skel.force_update_all_bone_transforms()
	print("foot=", skel.get_bone_global_pose(skel.find_bone("foot_l")).origin)

	for _i in range(8):
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png("res://tools/pose_mild_leg.png")
	print("saved pose_mild_leg.png")
	quit(0)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
