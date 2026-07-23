extends SceneTree
## Find anatomical hinge axes; screenshot a clean raised-knee pose.


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
	var mesh: MeshInstance3D = _find_mesh(body)
	var skin: Skin = mesh.skin
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var toe_bind: Vector3 = verts[3672]

	var thigh := skel.find_bone("thigh_l")
	var calf := skel.find_bone("calf_l")
	var foot := skel.find_bone("foot_l")

	# Raise knee: -X on thigh; bend knee: need calf axis that brings foot toward thigh
	var bt := skel.get_bone_pose_rotation(thigh)
	var bc := skel.get_bone_pose_rotation(calf)

	print("=== calf axes after thigh raised ===")
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
		skel.reset_bone_poses()
		bt = skel.get_bone_pose_rotation(thigh)
		bc = skel.get_bone_pose_rotation(calf)
		skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.LEFT, 0.6))
		skel.set_bone_pose_rotation(calf, bc * Quaternion(axis, 0.8))
		skel.force_update_all_bone_transforms()
		var toe := skel.get_bone_global_pose(foot) * skin.get_bind_pose(_bind(skin, "foot_l")) * toe_bind
		print("calf axis=", axis, " toe=", toe, " foot_o=", skel.get_bone_global_pose(foot).origin)

	# Best guess pose for screenshot: hip flex -X, knee +X or -X from scan
	skel.reset_bone_poses()
	bt = skel.get_bone_pose_rotation(thigh)
	bc = skel.get_bone_pose_rotation(calf)
	skel.set_bone_pose_rotation(thigh, bt * Quaternion(Vector3.LEFT, 0.7))
	# From print, pick calf axis that raises foot most / shortens leg
	skel.set_bone_pose_rotation(calf, bc * Quaternion(Vector3.LEFT, 0.9))
	skel.force_update_all_bone_transforms()
	var toe2 := skel.get_bone_global_pose(foot) * skin.get_bind_pose(_bind(skin, "foot_l")) * toe_bind
	print("screenshot pose toe=", toe2, " foot=", skel.get_bone_global_pose(foot).origin)

	# Bone debug markers
	for bname in ["thigh_l", "calf_l", "foot_l", "ball_l"]:
		var bi := skel.find_bone(bname)
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.025
		sph.height = 0.05
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		# Marker in skeleton space; body has rotation so parent to skeleton
		skel.add_child(m)
		m.position = skel.get_bone_global_pose(bi).origin

	for _i in range(8):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	img.save_png("res://tools/pose_raised_knee.png")
	print("saved pose_raised_knee.png")
	quit(0)


func _bind(skin: Skin, name: String) -> int:
	for i in range(skin.get_bind_count()):
		if skin.get_bind_name(i) == name:
			return i
	return -1


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
