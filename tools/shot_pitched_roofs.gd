## LOD check for pitched-roof houses: the same camera on voxels and on impostor shells.
##
## Townhouse rows are the one archetype whose silhouette is a gable rather than a slab,
## so a box shell reads as a flat-topped block from across the district. Walks to the
## densest patch of TOWN_LOT cells and saves the voxel/shell pair for comparison.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
extends Node

const WORLD_SEED := 42
const VOXEL_PNG := "res://tools/roofs_voxels.png"
const IMPOSTOR_PNG := "res://tools/roofs_impostors.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	## Wall-clock, not frame count: headed runs hit hundreds of FPS while the district
	## bakes on worker threads, so a frame budget expires long before the city exists.
	var deadline := Time.get_ticks_msec() + 90_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 90 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	await _settle(6.0)
	_set_voxel_view(city, 200, 200.0 * CityRoot.VOXEL_SIZE)
	await _settle(8.0)

	var district := _spawn_district(city)
	if district == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	var planner := district.generator.get_planner()
	var cell := _densest_town_cell(planner)
	print("densest town cell %s" % cell)
	var center := _cell_world(district, Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5))
	await _goto(walker, center)

	## Low and level: a gable only differs from a box in profile, so a steep aerial
	## angle would hide exactly what is being checked.
	var cam_off := Vector3(0.0, 26.0, 78.0)
	var cam_rot := Vector3(-0.12, 0.0, 0.0)
	await _shoot(walker.global_position, cam_off, cam_rot, VOXEL_PNG)
	## detail 0 forces shells on at any range; the short viewer hides the voxels.
	_set_voxel_view(city, 70, 0.0)
	await _settle(6.0)
	await _shoot(walker.global_position, cam_off, cam_rot, IMPOSTOR_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _set_voxel_view(city: CityRoot, view_vox: int, detail_m: float) -> void:
	var viewer: VoxelViewer = city._player_viewer
	if viewer == null:
		push_error("no VoxelViewer on city root")
		return
	viewer.view_distance = view_vox
	for lod: BuildingImpostorLod in city.find_children("*", "BuildingImpostorLod", true, false):
		lod.voxel_detail_distance = detail_m


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.coord == want and di.generator != null:
			return di
	return null


## Cell with the most TOWN_LOT neighbours, so the frame is filled with roofs instead
## of one house against a plaza.
func _densest_town_cell(planner: DistrictPlanner) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := -1
	for z in range(1, planner.cells_z - 1):
		for x in range(1, planner.cells_x - 1):
			if int(planner.grid[z][x]) != LandUse.TOWN_LOT:
				continue
			var n := 0
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var tx := x + dx
					var tz := z + dz
					if tx < 0 or tz < 0 or tx >= planner.cells_x or tz >= planner.cells_z:
						continue
					if int(planner.grid[tz][tx]) == LandUse.TOWN_LOT:
						n += 1
			if n > best_n:
				best_n = n
				best = Vector2i(x, z)
	if best_n < 0:
		push_error("spawn district has no TOWN_LOT cell")
	return best


func _cell_world(di: DistrictInstance, cell: Vector2) -> Vector3:
	var cs := float(di.generator.cell_size)
	return Vector3(
		(float(di.origin_vox.x) + cell.x * cs) * CityRoot.VOXEL_SIZE,
		0.0,
		(float(di.origin_vox.z) + cell.y * cs) * CityRoot.VOXEL_SIZE
	)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _goto(walker: Node3D, target: Vector3) -> void:
	walker.global_position = Vector3(target.x, 30.0, target.z)
	await _settle(8.0)


func _shoot(anchor: Vector3, offset: Vector3, rot: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = anchor + offset
	cam.rotation = rot
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
