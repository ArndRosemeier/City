## One loaded city tile: voxels stamped + local nav/crowd/traffic/props/impostors.
class_name DistrictInstance
extends Node3D

const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const OfflineVolumeCommitterScript := preload("res://scripts/city/offline_volume_committer.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")
const ScalePadPlacerScript := preload("res://scripts/city/scale_pad_placer.gd")
const BuildingImpostorLodScript := preload("res://scripts/city/building_impostor_lod.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CarRoadMapScript := preload("res://scripts/city/car_roadmap.gd")

signal ready_to_play(instance: DistrictInstance)
signal failed(instance: DistrictInstance, reason: String)
signal ground_ready(instance: DistrictInstance)
signal stamp_progress(cells: int)

var coord: Vector2i = Vector2i.ZERO
var origin_vox: Vector3i = Vector3i.ZERO
var is_ready: bool = false
var is_busy: bool = false
var is_ground_ready: bool = false
## True when this instance only re-pinned an already-stamped stream tile.
var from_stream_cache: bool = false
## "full" = voxel buildings; "far" = ground + impostors only.
var bake_quality: String = "full"

var generator: DistrictGenerator
var crowd: CrowdDirector
var vehicles: VehicleDirector
var street_props: StreetPropPlacer
var scale_pads: Node
var building_lod: BuildingImpostorLod
var _anchor: VoxelViewer
var _proxy_floor: StaticBody3D
var _nav_layers: StreetNavLayers

var _voxel_size: float = 0.5
var _world_seed: int = 42
var _crowd_count: int = 180
var _vehicle_count: int = 10
var _player_view_m: float = 220.0
var _ground_thickness: int = 1
var _dseed: int = 0
var _terrain_ref: VoxelTerrain
var _tool_ref: VoxelTool
var _camera_ref: Camera3D
## Worker bake result held between ground commit and detail commit.
var _bake_blocks: Dictionary = {}
var _bake_block_keys: Array[Vector3i] = []
var _bake_key_index: int = 0
var _bake_impostors: Array = []


func configure(
	p_coord: Vector2i,
	p_voxel_size: float,
	p_world_seed: int,
	p_crowd: int,
	p_vehicles: int,
	p_player_view_m: float
) -> void:
	coord = p_coord
	origin_vox = DistrictCoord.origin_vox(coord)
	_voxel_size = p_voxel_size
	_world_seed = p_world_seed
	_crowd_count = p_crowd
	_vehicle_count = p_vehicles
	_player_view_m = p_player_view_m
	name = "District_%d_%d" % [coord.x, coord.y]


func ensure_prefetch() -> void:
	## Floor first: visible + walkable deck as soon as the tile enters the bubble.
	_ensure_proxy_floor()


func bind_camera(camera: Camera3D) -> void:
	_camera_ref = camera
	if crowd != null and is_instance_valid(crowd):
		crowd._camera = camera
		crowd._refresh_lod(true)
	if vehicles != null and is_instance_valid(vehicles):
		vehicles._camera = camera
		vehicles._refresh_lod(true)
	if building_lod != null and is_instance_valid(building_lod):
		building_lod._camera = camera
	if street_props != null and is_instance_valid(street_props):
		street_props._camera = camera


func world_aabb_center() -> Vector3:
	return DistrictCoord.center_world(coord, _voxel_size)


func distance_to_point(world: Vector3) -> float:
	## Horizontal distance to nearest point on this district's footprint.
	var o := DistrictCoord.origin_world(coord, _voxel_size)
	var sx := float(DistrictCoord.SIZE_X_VOX) * _voxel_size
	var sz := float(DistrictCoord.SIZE_Z_VOX) * _voxel_size
	var nx := clampf(world.x, o.x, o.x + sx)
	var nz := clampf(world.z, o.z, o.z + sz)
	return Vector2(nx - world.x, nz - world.z).length()


func needs_ground() -> bool:
	return not is_ready and not is_ground_ready and not from_stream_cache


func needs_detail() -> bool:
	return is_ground_ready and not is_ready and not from_stream_cache


func needs_upgrade() -> bool:
	## Far impostor tile that has entered the voxel-detail radius.
	return is_ready and bake_quality == "far" and not is_busy and not from_stream_cache


func begin_ground(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D, quality: String = "full") -> void:
	if is_busy or is_ready or is_ground_ready:
		return
	is_busy = true
	bake_quality = quality
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	_stamp_ground_async()


func begin_detail(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	if is_busy or is_ready or not is_ground_ready:
		return
	is_busy = true
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	_stamp_detail_async()


func begin_upgrade(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	## Promote a far impostor tile to full voxel buildings.
	if not needs_upgrade():
		return
	is_busy = true
	is_ready = false
	is_ground_ready = false
	bake_quality = "full"
	_bake_blocks.clear()
	_bake_block_keys.clear()
	_bake_key_index = 0
	_bake_impostors.clear()
	if building_lod != null and is_instance_valid(building_lod):
		building_lod.clear()
		building_lod.queue_free()
	building_lod = null
	if crowd != null and is_instance_valid(crowd):
		crowd.clear_crowd()
		crowd.queue_free()
	crowd = null
	if vehicles != null and is_instance_valid(vehicles):
		vehicles.clear_vehicles()
		vehicles.queue_free()
	vehicles = null
	if street_props != null and is_instance_valid(street_props):
		street_props.clear_props()
		street_props.queue_free()
	street_props = null
	_nav_layers = null
	generator = null
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	_stamp_ground_async()


func begin_generate(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	## Boot path: ground then detail back-to-back via streamer chaining.
	begin_ground(terrain, tool, camera)


func destroy_and_clear(_tool: VoxelTool) -> void:
	is_ready = false
	is_busy = false
	is_ground_ready = false
	if crowd != null and is_instance_valid(crowd):
		crowd.clear_crowd()
		crowd.queue_free()
	crowd = null
	if vehicles != null and is_instance_valid(vehicles):
		vehicles.clear_vehicles()
		vehicles.queue_free()
	vehicles = null
	if street_props != null and is_instance_valid(street_props):
		street_props.clear_props()
		street_props.queue_free()
	street_props = null
	if building_lod != null and is_instance_valid(building_lod):
		building_lod.clear()
		building_lod.queue_free()
	building_lod = null
	_clear_proxy_floor()
	if _anchor != null and is_instance_valid(_anchor):
		_anchor.queue_free()
	_anchor = null
	_nav_layers = null
	generator = null
	## Dropping the data-only anchor unloads this tile's voxels from RAM.
	queue_free()


func _stamp_ground_async() -> void:
	## Bake the whole district off-thread, then commit ground-layer blocks on main.
	_ensure_anchor()
	_pin_data_only()
	_ensure_proxy_floor()
	var tool := _tool_ref
	var box := DistrictCoord.aabb_vox(coord, 208)
	var guard := 0
	while not tool.is_area_editable(box) and guard < 600:
		guard += 1
		await get_tree().process_frame
	if not tool.is_area_editable(box):
		is_busy = false
		failed.emit(self, "area not editable")
		return

	var payload := await _bake_on_worker()
	if not is_instance_valid(self):
		return
	if payload.is_empty() or not bool(payload.get("ok", false)):
		is_busy = false
		failed.emit(self, str(payload.get("error", "bake failed")))
		return

	_dseed = int(payload.get("seed", 0))
	_ground_thickness = int(payload.get("ground_thickness", 1))
	_bake_impostors = payload.get("impostors", [])
	_bake_blocks = payload.get("blocks", {})
	generator = payload.get("generator") as DistrictGenerator
	if generator == null:
		is_busy = false
		failed.emit(self, "bake missing generator")
		return

	## Ground layer first, nearest-to-player within that layer.
	_bake_block_keys = OfflineVolumeCommitterScript.sorted_block_keys_near_player(
		_bake_blocks, origin_vox, _focus_world(_camera_ref), _voxel_size, 0, -1
	)
	_bake_key_index = 0
	var ground_ok := await _commit_blocks_until()
	if not is_instance_valid(self):
		return
	if not ground_ok:
		is_busy = false
		failed.emit(self, "ground commit failed")
		return

	stamp_progress.emit(int(payload.get("cells_total", 0)) / 2)
	_pin_data_only()
	is_ground_ready = true
	is_busy = false
	print("DistrictInstance ground ready %s quality=%s" % [str(coord), bake_quality])
	ground_ready.emit(self)


func _stamp_detail_async() -> void:
	var tool := _tool_ref
	var camera := _camera_ref
	if generator == null:
		is_busy = false
		failed.emit(self, "detail without generator")
		return

	_ensure_anchor()
	_pin_data_only()
	_ensure_proxy_floor()

	## Upper blocks nearest-to-player (re-focus in case the camera moved during ground).
	_bake_block_keys = OfflineVolumeCommitterScript.sorted_block_keys_near_player(
		_bake_blocks, origin_vox, _focus_world(camera), _voxel_size, -1, 1
	)
	_bake_key_index = 0
	var detail_ok := await _commit_blocks_until()
	if not is_instance_valid(self):
		return
	if not detail_ok:
		is_busy = false
		failed.emit(self, "detail commit failed")
		return
	_bake_blocks.clear()
	_bake_block_keys.clear()

	## Far tiles: impostors only — skip nav/crowd/traffic until upgraded.
	if bake_quality == "far":
		generator.end_generate()
		building_lod = BuildingImpostorLodScript.new()
		building_lod.name = "BuildingImpostors"
		add_child(building_lod)
		var far_impostors: Array = _bake_impostors
		if far_impostors.is_empty():
			far_impostors = generator.building_impostors
		## Show shells even near the camera — no voxel buildings on far tiles.
		building_lod.setup(camera, far_impostors, 0.0)
		var day_night_far := get_tree().get_first_node_in_group(&"day_night")
		if day_night_far != null and day_night_far.has_method("get_night_factor"):
			building_lod.set_night_factor(float(day_night_far.call("get_night_factor")))
		_pin_data_only()
		is_ready = true
		is_busy = false
		ready_to_play.emit(self)
		print("DistrictInstance far-ready %s seed=%d" % [str(coord), _dseed])
		return

	generator.end_generate()
	await get_tree().process_frame
	_nav_layers = generator.build_street_nav(tool)
	if _nav_layers == null or not _nav_layers.is_ready():
		is_busy = false
		failed.emit(self, "nav failed")
		return

	await get_tree().process_frame
	var ped_map: PedRoadMap = PedRoadMapScript.new()
	ped_map.bind_graph(_nav_layers.ped, _nav_layers)
	var car_map: CarRoadMap = CarRoadMapScript.new()
	car_map.bind_graph(_nav_layers.road, _nav_layers)

	crowd = CrowdDirectorScript.new()
	crowd.name = "Crowd"
	crowd.pedestrian_count = _crowd_count
	add_child(crowd)
	crowd.setup(ped_map, camera, _dseed)
	await get_tree().process_frame

	vehicles = VehicleDirectorScript.new()
	vehicles.name = "Traffic"
	vehicles.vehicle_count = _vehicle_count
	add_child(vehicles)
	vehicles.setup(car_map, camera, _dseed)
	vehicles.bind_crowd(crowd)
	await get_tree().process_frame

	street_props = StreetPropPlacerScript.new()
	street_props.name = "StreetProps"
	add_child(street_props)
	street_props.place_from_planner(
		generator.get_planner(),
		generator.cell_size,
		_voxel_size,
		generator.ground_thickness,
		camera,
		origin_vox
	)
	var day_night := get_tree().get_first_node_in_group(&"day_night")
	if day_night != null and day_night.has_method("get_night_factor"):
		street_props.set_night_factor(float(day_night.call("get_night_factor")))
	await get_tree().process_frame

	scale_pads = ScalePadPlacerScript.new()
	scale_pads.name = "ScalePads"
	add_child(scale_pads)
	scale_pads.place_from_planner(
		generator.get_planner(),
		generator.cell_size,
		_voxel_size,
		generator.ground_thickness,
		origin_vox,
		_dseed
	)
	await get_tree().process_frame

	building_lod = BuildingImpostorLodScript.new()
	building_lod.name = "BuildingImpostors"
	add_child(building_lod)
	var impostors: Array = _bake_impostors
	if impostors.is_empty():
		impostors = generator.building_impostors
	building_lod.setup(camera, impostors, maxf(_player_view_m, 1.0))
	if day_night != null and day_night.has_method("get_night_factor"):
		building_lod.set_night_factor(float(day_night.call("get_night_factor")))

	## Player VoxelViewer remeshes the near field; district anchor stays data-only
	## so whole-tile remesh storms don't tank FPS while other districts generate.
	_pin_data_only()
	is_ready = true
	is_busy = false
	ready_to_play.emit(self)
	print("DistrictInstance ready %s seed=%d" % [str(coord), _dseed])


func _bake_on_worker() -> Dictionary:
	var params := {
		"coord": coord,
		"world_seed": _world_seed,
		"origin_vox": origin_vox,
		"size_x": DistrictCoord.SIZE_X_VOX,
		"size_z": DistrictCoord.SIZE_Z_VOX,
		"cell_size": DistrictCoord.CELL_SIZE,
		"floor_height_vox": 6,
		"max_building_height_vox": 200,
		"voxel_size": _voxel_size,
		"quality": bake_quality,
	}
	var mutex := Mutex.new()
	var state := {"done": false, "payload": {}}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var result: Dictionary = DistrictBakeJobScript.bake(params)
			mutex.lock()
			state["payload"] = result
			state["done"] = true
			mutex.unlock()
	)
	while true:
		mutex.lock()
		var done: bool = bool(state["done"])
		mutex.unlock()
		if done:
			break
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	mutex.lock()
	var payload: Dictionary = state["payload"]
	mutex.unlock()
	return payload


func _commit_blocks_until() -> bool:
	## Time-budgeted commits. Keys must already be nearest-first for this phase.
	const BUDGET_MSEC := 3
	var terrain := _terrain_ref
	while true:
		if not is_instance_valid(self):
			OfflineVolumeCommitterScript.release_commit(coord)
			return false
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		if _bake_key_index >= _bake_block_keys.size():
			break

		var t0 := Time.get_ticks_msec()
		var committed := 0
		while _bake_key_index < _bake_block_keys.size():
			var bp: Vector3i = _bake_block_keys[_bake_key_index]
			var data: PackedByteArray = _bake_blocks.get(bp, PackedByteArray())
			var ok := OfflineVolumeCommitterScript.commit_block(terrain, origin_vox, bp, data)
			var attempts := 0
			while not ok and attempts < 90:
				await get_tree().process_frame
				## Keep holding the commit lock while retrying this block.
				ok = OfflineVolumeCommitterScript.commit_block(terrain, origin_vox, bp, data)
				attempts += 1
			if not ok:
				push_error("DistrictInstance commit failed at %s local block %s" % [str(coord), str(bp)])
				OfflineVolumeCommitterScript.release_commit(coord)
				return false
			_bake_key_index += 1
			committed += 1
			if Time.get_ticks_msec() - t0 >= BUDGET_MSEC:
				break
		if committed > 0:
			stamp_progress.emit(committed)
		await get_tree().process_frame

	OfflineVolumeCommitterScript.release_commit(coord)
	return true


func reactivate_from_stream(_terrain: VoxelTerrain, _camera: Camera3D) -> void:
	## Legacy no-op — voxel data is not kept in a permanent stream anymore.
	## Callers should regenerate via begin_ground.
	from_stream_cache = false
	ensure_prefetch()


func _focus_world(camera: Camera3D) -> Vector3:
	if camera != null and is_instance_valid(camera):
		return camera.global_position
	return world_aabb_center()


func _cells_nearest_first(cells_x: int, cells_z: int, focus: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var scored: Array = []
	var ox := float(origin_vox.x) * _voxel_size
	var oz := float(origin_vox.z) * _voxel_size
	var cs := float(DistrictCoord.CELL_SIZE) * _voxel_size
	for cz in range(cells_z):
		for cx in range(cells_x):
			var cxw := ox + (float(cx) + 0.5) * cs
			var czw := oz + (float(cz) + 0.5) * cs
			var d2 := (cxw - focus.x) * (cxw - focus.x) + (czw - focus.z) * (czw - focus.z)
			scored.append({"c": Vector2i(cx, cz), "d": d2})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for item: Dictionary in scored:
		out.append(item["c"] as Vector2i)
	return out


func _wait_ground_meshed(terrain: VoxelTerrain, focus: Vector3) -> void:
	## Short approach-only wait (spawn path). Never wait on the full district AABB.
	var local := Vector3(
		focus.x / _voxel_size,
		float(_ground_thickness),
		focus.z / _voxel_size
	)
	var min_x := float(origin_vox.x) + 4.0
	var max_x := float(origin_vox.x + DistrictCoord.SIZE_X_VOX) - 4.0
	var min_z := float(origin_vox.z) + 4.0
	var max_z := float(origin_vox.z + DistrictCoord.SIZE_Z_VOX) - 4.0
	local.x = clampf(local.x, min_x, max_x)
	local.z = clampf(local.z, min_z, max_z)
	var approach := AABB(local - Vector3(32, 0, 32), Vector3(64, 8, 64))
	var guard := 0
	while not terrain.is_area_meshed(approach) and guard < 180:
		guard += 1
		await get_tree().process_frame


func _ensure_anchor() -> void:
	## Pins voxel *data* for this tile while it is in the bubble — without requesting
	## mesh or collision (those are the expensive part). Player VoxelViewer handles
	## near visuals/collisions; proxy floor covers walkable gaps; impostors draw far massing.
	if _anchor != null and is_instance_valid(_anchor):
		return
	_anchor = VoxelViewer.new()
	_anchor.name = "DistrictAnchor"
	## Cover tile from center (half-diagonal ≈ 482 vox).
	_anchor.view_distance = 512
	_anchor.requires_visuals = false
	_anchor.requires_collisions = false
	add_child(_anchor)
	_anchor.global_position = world_aabb_center() + Vector3(0.0, 40.0, 0.0)


func _ensure_generate_viewer() -> void:
	## Temporary collisions near the tile while stamping so ground can mesh for spawn/nav.
	## Swapped back to data-only after detail finishes.
	_ensure_anchor()
	if _anchor == null:
		return
	_anchor.requires_visuals = true
	_anchor.requires_collisions = true


func _pin_data_only() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	_anchor.requires_visuals = false
	_anchor.requires_collisions = false


func _ensure_proxy_floor() -> void:
	## Invisible collision only — never a fake visible deck (that fights the real voxels).
	if _proxy_floor != null and is_instance_valid(_proxy_floor):
		return
	var sx := float(DistrictCoord.SIZE_X_VOX) * _voxel_size
	var sz := float(DistrictCoord.SIZE_Z_VOX) * _voxel_size
	var top_y := float(_ground_thickness + 1) * _voxel_size
	var thickness := 0.6
	_proxy_floor = StaticBody3D.new()
	_proxy_floor.name = "ProxyFloor"
	_proxy_floor.collision_layer = 1
	_proxy_floor.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(sx, thickness, sz)
	shape.shape = box
	_proxy_floor.add_child(shape)
	add_child(_proxy_floor)
	var o := DistrictCoord.origin_world(coord, _voxel_size)
	_proxy_floor.global_position = Vector3(
		o.x + sx * 0.5,
		top_y - thickness * 0.5,
		o.z + sz * 0.5
	)


func _clear_proxy_floor() -> void:
	if _proxy_floor != null and is_instance_valid(_proxy_floor):
		_proxy_floor.queue_free()
	_proxy_floor = null
