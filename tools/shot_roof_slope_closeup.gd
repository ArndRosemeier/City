## Full clay gable close-up (slopes + solid fill) after winding fix.
extends Node


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.72, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.65, 0.7)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(0.5, 0.5, 0.5)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibrary.build()
	terrain.mesher = mesher
	const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
	terrain.generator = AirGeneratorScript.new()
	terrain.bounds = AABB(Vector3(-8, 0, -8), Vector3(24, 16, 24))
	terrain.max_view_distance = 64
	terrain.generate_collisions = false
	root.add_child(terrain)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 64
	viewer.requires_visuals = true
	root.add_child(viewer)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var guard := 0
	while not tool.is_area_editable(AABB(Vector3(0, 0, 0), Vector3(16, 12, 16))) and guard < 300:
		guard += 1
		await get_tree().process_frame

	for y in range(1, 5):
		for z in range(2, 10):
			for x in range(2, 10):
				if x == 2 or x == 9 or z == 2 or z == 9:
					tool.set_voxel(Vector3i(x, y, z), VoxelMaterial.BRICK)
	for s in range(4):
		var y := 5 + s
		var x0 := 2 + s
		var x1 := 10 - s
		for z_fill in range(2, 10):
			for x in range(x0, x1):
				tool.set_voxel(Vector3i(x, y, z_fill), VoxelMaterial.ROOF_CLAY)
			if x1 - x0 >= 2:
				for z_eave in range(2, 10):
					tool.set_voxel(Vector3i(x0, y, z_eave), VoxelMaterial.ROOF_CLAY_SLOPE_POS_X)
					tool.set_voxel(Vector3i(x1 - 1, y, z_eave), VoxelMaterial.ROOF_CLAY_SLOPE_NEG_X)

	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	## Same high-angle view as the original bug report.
	cam.global_position = Vector3(2.2, 6.8, 4.0)
	cam.look_at(Vector3(3.2, 3.6, 3.0))
	viewer.global_position = cam.global_position
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("res://tools/roof_slope_closeup.png")
	print("RESULT: OK")
	get_tree().quit(0)
