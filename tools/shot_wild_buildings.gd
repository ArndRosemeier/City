## Look inspection for the "wild" archetypes and the far-LOD skyline.
##
## Boots the live city, walks to the densest core cell of the spawn district and saves
## a street-level, an aerial and a long-range shot. The long-range one is the LOD check:
## impostor shells and real voxels have to agree on building heights.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
extends Node

const WORLD_SEED := 42
## The impostor LOD swaps voxel meshes out at ~44 m, so every "does the geometry look
## right" shot has to be taken from inside that radius. Only the last shot steps back,
## and that one is the LOD check: impostor heights against the voxels behind them.
const SHOT_DIR := "res://tools/"
const VOXEL_PNG := "res://tools/wild_voxels.png"
const IMPOSTOR_PNG := "res://tools/wild_impostors.png"


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
	## 200 vox = 100 m. Higher (280) meshes so much of the core at once that the
	## RenderingDevice runs out of elements and the process dies.
	_set_voxel_view(city, 200, 200.0 * CityRoot.VOXEL_SIZE)
	await _settle(8.0)

	var district := _spawn_district(city)
	if district == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	var planner := district.generator.get_planner()
	var best := _densest_core_cell(planner)
	print("densest core cell %s" % best)
	## Walk a short tour of core cells: 30 % of them are wild, so a handful of stops is
	## enough to see holes, arches, pods and twists.
	var stops: Array[Vector2i] = [
		best,
		best + Vector2i(3, 0),
		best + Vector2i(0, 3),
		best + Vector2i(3, 3),
	]
	for i in range(stops.size()):
		var cell := stops[i]
		if cell.x >= planner.cells_x or cell.y >= planner.cells_z:
			continue
		var center := _cell_world(district, Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5))
		await _goto(walker, center)
		await _shoot(
			walker.global_position,
			Vector3(0.0, 48.0, 85.0),
			Vector3(-0.22, 0.0, 0.0),
			"%swild_stop_%d.png" % [SHOT_DIR, i]
		)
	## Same camera twice: voxels only, then shells only. The two silhouettes have to
	## match, which is the check that round / pierced buildings keep their shape at LOD.
	var cam_off := Vector3(0.0, 48.0, 85.0)
	var cam_rot := Vector3(-0.22, 0.0, 0.0)
	await _shoot(walker.global_position, cam_off, cam_rot, VOXEL_PNG)
	## detail 0 forces shells on at any range; the short viewer hides the voxels.
	_set_voxel_view(city, 80, 0.0)
	await _settle(6.0)
	await _shoot(walker.global_position, cam_off, cam_rot, IMPOSTOR_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


## Gameplay meshes voxels out to ~44 m and shows impostor shells past that, which hides
## exactly the massing this tool inspects. `detail_m` = 0 restores the impostors so the
## final shot can compare shell heights against the voxels.
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


func _densest_core_cell(planner: DistrictPlanner) -> Vector2i:
	var best := Vector2i(0, 0)
	var best_v := -1.0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			if int(planner.grid[z][x]) != LandUse.CORE_LOT:
				continue
			var v := planner.intensity_at(x, z)
			if v > best_v:
				best_v = v
				best = Vector2i(x, z)
	if best_v < 0.0:
		push_error("spawn district has no CORE_LOT cell — run with --spawn-district=0,0")
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
	walker.global_position = Vector3(target.x, 40.0, target.z)
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
