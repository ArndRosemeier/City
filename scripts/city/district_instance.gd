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
## Planner-derived lane and pavement annotations. Not a navigation graph: it says which side
## of a carriageway is which lane and where the crossings are, and the span field in
## NavService does the routing.
var _topology: StreetTopology
## True once this tile's span field is registered with the world-level NavService.
var _nav_registered: bool = false

var _voxel_size: float = 0.5
var _world_seed: int = 42
var _crowd_count: int = 180
var _vehicle_count: int = 10
var _player_view_m: float = 220.0
var _ground_thickness: int = 6
var _dseed: int = 0
var _terrain_ref: VoxelTerrain
var _tool_ref: VoxelTool
var _camera_ref: Camera3D
## Worker bake result held between ground commit and detail commit.
var _bake_blocks: Dictionary = {}
var _bake_block_keys: Array[Vector3i] = []
var _bake_key_index: int = 0
var _bake_impostors: Array = []
## Hill gem ore in world voxel coords (empty outside Hill districts).
var hill_gem_positions: PackedVector3Array = PackedVector3Array()
var hill_gem_mats: PackedInt32Array = PackedInt32Array()


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
	## Catch the player while the tile has no voxels yet; dropped again once ground commits.
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
	CityProfiler.begin("stream_upgrade_reset")
	## The far field describes a district without buildings; drop it before the full bake
	## replaces it, so nothing paths through a tower that is about to exist.
	_unregister_nav()
	is_busy = true
	is_ready = false
	is_ground_ready = false
	bake_quality = "full"
	_bake_blocks.clear()
	_bake_block_keys.clear()
	_bake_key_index = 0
	_bake_impostors.clear()
	hill_gem_positions = PackedVector3Array()
	hill_gem_mats = PackedInt32Array()
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
	_topology = null
	generator = null
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	CityProfiler.end("stream_upgrade_reset")
	_stamp_ground_async()


func begin_generate(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	## Boot path: ground then detail back-to-back via streamer chaining.
	begin_ground(terrain, tool, camera)


func destroy_and_clear(_tool: VoxelTool) -> void:
	CityProfiler.begin("stream_unload")
	_unregister_nav()
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
		CityProfiler.note_event("voxel_anchor_removed")
		_anchor.queue_free()
	_anchor = null
	_topology = null
	generator = null
	## Dropping the data-only anchor unloads this tile's voxels from RAM.
	queue_free()
	CityProfiler.end("stream_unload")


func _stamp_ground_async() -> void:
	## Bake the whole district off-thread, then commit ground-layer blocks on main.
	_ensure_anchor()
	_pin_data_only()
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

	CityProfiler.set_counter("stream_phase", 1)  ## 1=ground bake
	var payload := await _bake_on_worker()
	if not is_instance_valid(self):
		return
	if payload.is_empty() or not bool(payload.get("ok", false)):
		is_busy = false
		failed.emit(self, str(payload.get("error", "bake failed")))
		return

	var t_ingest := Time.get_ticks_usec()
	_dseed = int(payload.get("seed", 0))
	_ground_thickness = int(payload.get("ground_thickness", 6))
	_bake_impostors = payload.get("impostors", [])
	_bake_blocks = payload.get("blocks", {})
	hill_gem_positions = payload.get("hill_gem_positions", PackedVector3Array()) as PackedVector3Array
	hill_gem_mats = payload.get("hill_gem_mats", PackedInt32Array()) as PackedInt32Array
	generator = payload.get("generator") as DistrictGenerator
	CityProfiler.scope_us("stream_ingest", Time.get_ticks_usec() - t_ingest)
	if generator == null:
		is_busy = false
		failed.emit(self, "bake missing generator")
		return
	## The span field was baked from the finished volume, so it describes the tile the
	## commits below are still writing. Registering now lets agents path into a district
	## while it streams in, and must happen on the main thread.
	_register_nav(payload.get("nav_bake") as RefCounted, payload.get("nav_stats", {}))

	## Ground layer first, nearest-to-player within that layer.
	var t_sort := Time.get_ticks_usec()
	_bake_block_keys = OfflineVolumeCommitterScript.sorted_block_keys_near_player(
		_bake_blocks, origin_vox, _focus_world(_camera_ref), _voxel_size, 0, -1
	)
	CityProfiler.scope_us("stream_sort", Time.get_ticks_usec() - t_sort)
	_bake_key_index = 0
	CityProfiler.set_counter("stream_phase", 2)  ## 2=ground commit
	CityProfiler.set_counter("stream_blocks_left", _bake_block_keys.size())
	var ground_ok := await _commit_blocks_until("stream_commit_ground")
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
	CityProfiler.set_counter("stream_phase", 0)
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

	## Upper blocks nearest-to-player (re-focus in case the camera moved during ground).
	var t_sort := Time.get_ticks_usec()
	_bake_block_keys = OfflineVolumeCommitterScript.sorted_block_keys_near_player(
		_bake_blocks, origin_vox, _focus_world(camera), _voxel_size, -1, 1
	)
	CityProfiler.scope_us("stream_sort", Time.get_ticks_usec() - t_sort)
	_bake_key_index = 0
	CityProfiler.set_counter("stream_phase", 3)  ## 3=detail commit
	CityProfiler.set_counter("stream_blocks_left", _bake_block_keys.size())
	var detail_ok := await _commit_blocks_until("stream_commit_detail")
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
		CityProfiler.begin("stream_far_setup")
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
		## Ground voxels are committed — the streaming failsafe would only be phantom
		## collision under caves and craters from here on.
		_clear_proxy_floor()
		CityProfiler.end("stream_far_setup")
		is_ready = true
		is_busy = false
		CityProfiler.set_counter("stream_phase", 0)
		ready_to_play.emit(self)
		print("DistrictInstance far-ready %s seed=%d" % [str(coord), _dseed])
		return

	CityProfiler.set_counter("stream_phase", 4)  ## 4=detail populate
	var t_end := Time.get_ticks_usec()
	generator.end_generate()
	CityProfiler.scope_us("stream_end_generate", Time.get_ticks_usec() - t_end)
	await get_tree().process_frame

	CityProfiler.begin("stream_nav")
	_topology = generator.build_street_topology()
	CityProfiler.end("stream_nav")
	if _topology == null or not _topology.is_ready():
		is_busy = false
		failed.emit(self, "street topology failed")
		return

	await get_tree().process_frame

	CityProfiler.begin("stream_crowd")
	crowd = CrowdDirectorScript.new()
	crowd.name = "Crowd"
	crowd.pedestrian_count = _crowd_count
	add_child(crowd)
	crowd.setup(_topology.sidewalks, camera, _dseed)
	CityProfiler.end("stream_crowd")
	await get_tree().process_frame

	CityProfiler.begin("stream_vehicles")
	vehicles = VehicleDirectorScript.new()
	vehicles.name = "Traffic"
	vehicles.vehicle_count = _vehicle_count
	add_child(vehicles)
	vehicles.setup(_topology, camera, _dseed)
	vehicles.bind_crowd(crowd)
	CityProfiler.end("stream_vehicles")
	await get_tree().process_frame

	CityProfiler.begin("stream_props")
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
	CityProfiler.end("stream_props")
	await get_tree().process_frame

	CityProfiler.begin("stream_pads")
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
	CityProfiler.end("stream_pads")
	await get_tree().process_frame

	CityProfiler.begin("stream_impostors")
	building_lod = BuildingImpostorLodScript.new()
	building_lod.name = "BuildingImpostors"
	add_child(building_lod)
	var impostors: Array = _bake_impostors
	if impostors.is_empty():
		impostors = generator.building_impostors
	building_lod.setup(camera, impostors, maxf(_player_view_m, 1.0))
	if day_night != null and day_night.has_method("get_night_factor"):
		building_lod.set_night_factor(float(day_night.call("get_night_factor")))
	CityProfiler.end("stream_impostors")

	## Player VoxelViewer remeshes the near field; district anchor stays data-only
	## so whole-tile remesh storms don't tank FPS while other districts generate.
	_pin_data_only()
	_clear_proxy_floor()
	is_ready = true
	is_busy = false
	CityProfiler.set_counter("stream_phase", 0)
	ready_to_play.emit(self)
	print("DistrictInstance ready %s seed=%d" % [str(coord), _dseed])


func _bake_on_worker() -> Dictionary:
	## Passability tables are built once on the main thread; the worker only reads them.
	var nav := NavService.instance()
	nav.ensure_configured(_voxel_size)
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
		"bake_nav": true,
		"nav_solidity": nav.solidity_tables(),
		"nav_link_params": nav.link_params(),
	}
	var mutex := Mutex.new()
	var state := {"done": false, "payload": {}}
	CityProfiler.add_counter("bake_tasks", 1)
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
	var t_wait := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task_id)
	CityProfiler.scope_us("stream_bake_wait", Time.get_ticks_usec() - t_wait)
	CityProfiler.add_counter("bake_tasks", -1)
	mutex.lock()
	var payload: Dictionary = state["payload"]
	mutex.unlock()
	return payload


func _register_nav(nav_bake: RefCounted, nav_stats: Dictionary) -> void:
	## Hands this tile's span field to the world registry. The bake handle is spent by the
	## insert — NavService moves the field rather than copying it.
	if nav_bake == null:
		push_error("DistrictInstance %s: bake returned no nav field" % str(coord))
		return
	CityProfiler.begin("stream_nav_register")
	_nav_registered = NavService.instance().register_district(coord, nav_bake)
	CityProfiler.end("stream_nav_register")
	if not _nav_registered:
		return
	print(
		"DistrictInstance nav %s quality=%s spans=%d portals=%d links=%d bytes=%d"
		% [
			str(coord),
			bake_quality,
			int(nav_stats.get("spans", 0)),
			int(nav_stats.get("portals", 0)),
			int(nav_stats.get("links", 0)),
			int(nav_stats.get("bytes", 0)),
		]
	)


func _unregister_nav() -> void:
	if not _nav_registered:
		return
	_nav_registered = false
	## Never rebuild the service on the way out — at shutdown it may already be gone.
	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		return
	if not nav.unregister_district(coord):
		push_error("DistrictInstance %s: NavService had no field to drop" % str(coord))


func _notification(what: int) -> void:
	## CityStreamer's failure path frees an instance without destroy_and_clear, and a span
	## field left in the registry would keep routing agents through a district that is not
	## there any more.
	if what == NOTIFICATION_PREDELETE:
		_unregister_nav()


func _commit_blocks_until(scope_name: String = "voxel_commit") -> bool:
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
		var t0_us := Time.get_ticks_usec()
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
		CityProfiler.scope_us(scope_name, Time.get_ticks_usec() - t0_us)
		CityProfiler.set_counter(
			"stream_blocks_left", maxi(_bake_block_keys.size() - _bake_key_index, 0)
		)
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
	CityProfiler.note_event("voxel_anchor_added")
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
	## Player failsafe layer, not terrain (1). On terrain this district-wide slab read as
	## real geometry to the camera spring arm, walker raycasts and resting debris — and
	## caves / blast craters sit below it, so the player ends up under phantom rock.
	_proxy_floor.collision_layer = CityWalker.SAFETY_DECK_LAYER
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
