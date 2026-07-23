## Headless smoke without CityWalker UI (dummy renderer friendly).
extends SceneTree

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")

const VOXEL_SIZE := 0.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gen := DistrictGenerator.new()
	gen.size_x = 160
	gen.size_z = 112
	gen.max_building_height_vox = 80
	gen.voxel_size = VOXEL_SIZE
	gen.city_seed = 42

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	terrain.generate_collisions = false
	terrain.max_view_distance = 256
	terrain.bounds = AABB(
		Vector3.ZERO,
		Vector3(float(gen.size_x), float(gen.max_building_height_vox + 8), float(gen.size_z))
	)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	terrain.mesher = mesher
	terrain.generator = AirGeneratorScript.new()
	root.add_child(terrain)

	var viewer := VoxelViewer.new()
	viewer.view_distance = 256
	viewer.requires_visuals = true
	viewer.requires_collisions = false
	root.add_child(viewer)
	viewer.global_position = Vector3(
		float(gen.size_x) * 0.5 * VOXEL_SIZE,
		10.0,
		float(gen.size_z) * 0.5 * VOXEL_SIZE
	)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var box := AABB(
		Vector3.ZERO,
		Vector3(float(gen.size_x), float(gen.max_building_height_vox + 8), float(gen.size_z))
	)
	var guard := 0
	while not tool.is_area_editable(box) and guard < 600:
		guard += 1
		await process_frame
	if not tool.is_area_editable(box):
		push_error("SMOKE_FAIL editable")
		quit(1)
		return

	gen.generate(tool, 42)
	var ped := gen.build_ped_roadmap(tool, 2)
	var car := gen.build_car_roadmap(tool, 2)
	var planner := gen.get_planner()
	VehicleCatalogScript.ensure_loaded()

	print(
		"SMOKE ped_nodes=%d car_nodes=%d lights=%d catalog=%d cells=%dx%d"
		% [
			ped.node_count,
			car.node_count,
			planner.avenue_light_cells.size(),
			VehicleCatalogScript.count(),
			planner.cells_x,
			planner.cells_z,
		]
	)
	if ped.node_count < 10:
		push_error("SMOKE_FAIL ped roadmap too small")
		quit(2)
		return
	if car.node_count < 10:
		push_error("SMOKE_FAIL car roadmap too small")
		quit(3)
		return
	if VehicleCatalogScript.count() < 1:
		push_error("SMOKE_FAIL empty vehicle catalog")
		quit(4)
		return
	# Sample: ped graph should not include asphalt-only cells (checked by mat filter).
	print("SMOKE_OK")
	quit(0)
