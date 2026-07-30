## Diagnostic render: GLASS wall + floor with bright solids behind/under so
## translucency, fresnel, and mesh seams are obvious from pixels.
extends Node


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.68, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	environment.ambient_light_energy = 0.85
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(0.5, 0.5, 0.5)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibrary.build()
	terrain.mesher = mesher
	const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
	terrain.generator = AirGeneratorScript.new()
	terrain.bounds = AABB(Vector3(-8, 0, -8), Vector3(32, 20, 32))
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
	while not tool.is_area_editable(AABB(Vector3(0, 0, 0), Vector3(20, 12, 20))) and guard < 300:
		guard += 1
		await get_tree().process_frame

	## Opaque ground so the glass floor has something to show through.
	for z in range(1, 14):
		for x in range(1, 14):
			tool.set_voxel(Vector3i(x, 0, z), VoxelMaterial.BRICK)

	## Bright solids under the glass floor strip (checker so transmission is obvious).
	for z in range(3, 7):
		for x in range(3, 10):
			tool.set_voxel(
				Vector3i(x, 1, z),
				VoxelMaterial.ROOF_CLAY if (x + z) % 2 == 0 else VoxelMaterial.METAL_PLATE
			)

	## Glass floor over the bright pads.
	for z in range(3, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, 2, z), VoxelMaterial.GLASS)

	## Opaque back wall behind a glass curtain.
	for y in range(1, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, y, 11), VoxelMaterial.BRICK_DARK if x % 2 == 0 else VoxelMaterial.METAL)

	## Vertical glass sheet in front of the back wall.
	for y in range(1, 7):
		for x in range(3, 10):
			tool.set_voxel(Vector3i(x, y, 9), VoxelMaterial.GLASS)

	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	## High enough to read the glass floor as a sheet; offset for wall fresnel.
	cam.global_position = Vector3(0.9, 5.4, 0.6)
	cam.look_at(Vector3(3.4, 1.6, 5.0))
	viewer.global_position = cam.global_position
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("res://tools/glass_shot.png")
	print("RESULT: OK")
	get_tree().quit(0)
