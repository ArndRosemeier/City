## Headless unit smoke for StreetNavLayers connectivity (no full city regen).
extends SceneTree

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gen := DistrictGenerator.new()
	gen.size_x = 336
	gen.size_z = 224
	gen.cell_size = 28
	gen.floor_height_vox = 6
	gen.max_building_height_vox = 40
	gen.voxel_size = 0.5
	gen.city_seed = 42

	var terrain := VoxelTerrain.new()
	terrain.scale = Vector3(0.5, 0.5, 0.5)
	terrain.generate_collisions = false
	terrain.max_view_distance = 400
	terrain.bounds = AABB(Vector3.ZERO, Vector3(336.0, 48.0, 224.0))
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
	viewer.global_position = Vector3(84.0, 10.0, 56.0)

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var box := AABB(Vector3.ZERO, Vector3(336.0, 48.0, 224.0))
	var guard := 0
	while not tool.is_area_editable(box) and guard < 600:
		guard += 1
		await process_frame
	if not tool.is_area_editable(box):
		push_error("FAIL editable")
		quit(1)
		return

	gen.generate(tool, 42)
	var layers := gen.build_street_nav(tool)
	if layers == null or not layers.is_ready():
		push_error("FAIL street nav")
		quit(2)
		return
	if layers.crossings.is_empty():
		push_error("FAIL no crossings")
		quit(3)
		return
	if layers.road.largest_component_ratio() < 0.55:
		push_error("FAIL road fragmented")
		quit(4)
		return
	if layers.ped.edge_count < 1:
		push_error("FAIL ped edges")
		quit(5)
		return

	# Yield registry: ped on mid counts; ped on far sidewalk does not.
	var c0: Dictionary = layers.crossings[0]
	var center: Vector3 = c0["center"]
	layers.refresh_crossing_occupancy([center])
	if not layers.is_crossing_occupied(int(c0["id"])):
		push_error("FAIL occupancy not detected")
		quit(6)
		return
	if not layers.yielding_for_car(center + Vector3(2.0, 0.0, 0.0), center):
		push_error("FAIL yield not triggered")
		quit(7)
		return
	var curb := center + Vector3(0.0, 0.0, 4.0)
	layers.refresh_crossing_occupancy([curb])
	if layers.is_crossing_occupied(int(c0["id"])):
		push_error("FAIL curb ped falsely occupies crossing")
		quit(8)
		return
	layers.refresh_crossing_occupancy([])
	if layers.is_crossing_occupied(int(c0["id"])):
		push_error("FAIL occupancy stuck")
		quit(9)
		return

	print("PASS street nav layers")
	quit(0)
