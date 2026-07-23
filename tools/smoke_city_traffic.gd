## Headless smoke: planner StreetNavLayers + car displacement over time.
extends SceneTree

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")

const VOXEL_SIZE := 0.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gen := DistrictGenerator.new()
	gen.size_x = 336
	gen.size_z = 224
	gen.cell_size = 28
	gen.floor_height_vox = 6
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
	var layers := gen.build_street_nav(tool)
	if layers == null or not layers.is_ready():
		push_error("SMOKE_FAIL street nav not ready")
		quit(2)
		return

	var ped := PedRoadMap.new()
	ped.bind_graph(layers.ped, layers)
	var car := CarRoadMap.new()
	car.bind_graph(layers.road, layers)
	VehicleCatalogScript.ensure_loaded()

	print(
		"SMOKE ped_nodes=%d ped_edges=%d car_nodes=%d car_edges=%d crossings=%d road_comp=%.2f ped_comp=%.2f catalog=%d"
		% [
			ped.node_count,
			ped.edge_count,
			car.node_count,
			car.edge_count,
			layers.crossings.size(),
			car.largest_component_ratio(),
			ped.largest_component_ratio(),
			VehicleCatalogScript.count(),
		]
	)
	if car.node_count < 10 or car.edge_count < 10:
		push_error("SMOKE_FAIL car graph too small")
		quit(3)
		return
	if ped.node_count < 10 or ped.edge_count < 10:
		push_error("SMOKE_FAIL ped graph too small")
		quit(4)
		return
	if layers.crossings.is_empty():
		push_error("SMOKE_FAIL no crossings")
		quit(5)
		return
	if car.largest_component_ratio() < 0.55:
		push_error("SMOKE_FAIL road graph fragmented")
		quit(6)
		return
	if VehicleCatalogScript.count() < 1:
		push_error("SMOKE_FAIL empty vehicle catalog")
		quit(7)
		return

	# Path exists within largest component.
	var a := car.random_node(RandomNumberGenerator.new())
	var b := car.random_goal_node(a, 5.0, 80.0, RandomNumberGenerator.new())
	if b < 0:
		push_error("SMOKE_FAIL no car goal")
		quit(8)
		return
	var path := car.find_path(a, b)
	if path.size() < 2:
		push_error("SMOKE_FAIL car path empty a=%d b=%d" % [a, b])
		quit(9)
		return

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = viewer.global_position

	var crowd := CrowdDirectorScript.new()
	crowd.pedestrian_count = 8
	crowd.near_distance = 0.1
	crowd.mid_distance = 0.2
	root.add_child(crowd)
	crowd.setup(ped, cam, 42)

	var traffic := VehicleDirectorScript.new()
	traffic.vehicle_count = 16
	# Cull visuals in headless — DummyMesh RIDs crash on MultiMesh / skinned sync.
	traffic.near_distance = 0.05
	traffic.mid_distance = 0.1
	root.add_child(traffic)
	traffic.setup(car, cam, 42)
	traffic.bind_crowd(crowd)

	if traffic.vehicle_live_count() < 1:
		push_error("SMOKE_FAIL no vehicles spawned")
		quit(10)
		return

	var p0 := traffic.sample_agent_position(0)
	# Explicit sim — also covers headless where physics timing can be odd.
	for _i in range(120):
		traffic._simulate(1.0 / 60.0)
	var p1 := traffic.sample_agent_position(0)
	var moved := Vector2(p1.x - p0.x, p1.z - p0.z).length()
	print("SMOKE moved=%.3f p0=%s p1=%s" % [moved, str(p0), str(p1)])
	if moved < 0.5:
		push_error("SMOKE_FAIL car did not move (delta=%.3f)" % moved)
		quit(11)
		return

	print("SMOKE_OK")
	quit(0)
