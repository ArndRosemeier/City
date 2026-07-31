## Landmark evergreen grove — pine silhouette vs the old park ellipsoid.
##
##   powershell -File tools\run_test.ps1 shot_landmark_trees -Rendered
extends Node

const OUT_DIR := "res://tools/"
const VOX := 0.5
const DECK_Y := 2


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	_build_environment(root)

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(VOX, VOX, VOX)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibrary.build()
	terrain.mesher = mesher
	const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
	terrain.generator = AirGeneratorScript.new()
	terrain.bounds = AABB(Vector3(-8, 0, -8), Vector3(96, 72, 80))
	terrain.max_view_distance = 180
	terrain.generate_collisions = false
	root.add_child(terrain)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 180
	viewer.requires_visuals = true
	root.add_child(viewer)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var guard := 0
	while not tool.is_area_editable(AABB(Vector3(0, 0, 0), Vector3(80, 56, 48))) and guard < 400:
		guard += 1
		await get_tree().process_frame

	_paint_deck(tool)
	var brush := CityBrush.new(tool)
	var stamper := TreeStamper.new()
	stamper.brush = brush
	stamper.rng = RandomNumberGenerator.new()
	stamper.rng.seed = 7
	brush.begin_edit()
	## Small grove like the reference — overlapping crowns, clear trunks.
	stamper.landmark_tree(28, DECK_Y, 22)
	stamper.landmark_tree(36, DECK_Y, 20)
	stamper.landmark_tree(32, DECK_Y, 28)
	brush.end_edit()

	await get_tree().create_timer(2.2).timeout
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	## Low eye-level: bare trunks + wide lower shelves, tip taper in frame.
	cam.global_position = Vector3(8.0, 4.5, 2.0)
	cam.look_at(Vector3(16.0, 9.0, 12.0))
	viewer.global_position = cam.global_position
	await get_tree().create_timer(1.2).timeout

	var out_path := OUT_DIR + "landmark_trees_ab.png"
	get_viewport().get_texture().get_image().save_png(out_path)
	print("LANDMARK_TREES wrote %s" % out_path)
	print("RESULT: OK")
	get_tree().quit(0)


func _paint_deck(tool: VoxelTool) -> void:
	for z in range(8, 40):
		for x in range(12, 56):
			tool.set_voxel(Vector3i(x, DECK_Y, z), VoxelMaterial.PARK)
			tool.set_voxel(Vector3i(x, DECK_Y - 1, z), VoxelMaterial.DIRT)


func _build_environment(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.74, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.74, 0.78)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 28, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root.add_child(sun)
