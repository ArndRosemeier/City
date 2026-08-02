## One loaded city tile: voxels stamped + local nav/crowd/traffic/props/impostors.
class_name DistrictInstance
extends Node3D

const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const OfflineVolumeCommitterScript := preload("res://scripts/city/offline_volume_committer.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")
const SignpostPlacerScript := preload("res://scripts/city/signpost_placer.gd")
const GemChestPlacerScript := preload("res://scripts/city/gem_chest_placer.gd")
const RecipePickupPlacerScript := preload("res://scripts/city/recipe_pickup_placer.gd")
const CastleDoorPlacerScript := preload("res://scripts/city/castle_door_placer.gd")
const MandelbrotArenaScript := preload("res://scripts/city/mandelbrot_arena.gd")
const ArenaControllerScript := preload("res://scripts/city/arena_controller.gd")
const ZooControllerScript := preload("res://scripts/city/zoo_controller.gd")
const CryptSpawnerScript := preload("res://scripts/city/crypt_spawner.gd")
const FactionPadSpawnerScript := preload("res://scripts/city/faction_pad_spawner.gd")
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
## Fingerposts naming the four neighbours. Empty of posts on special tiles.
var signposts: SignpostPlacer
## Gem chests placed as this tile's rooms get furnished. Created on the first chest.
var gem_chests: GemChestPlacer
## Recipe scrolls standing on this tile's landmarks. Null until the tile streams in full.
var recipe_pickups: RecipePickupPlacer
## Mesh doors hung in the castle's openings. Null on every tile that is not a Castle.
var castle_doors: CastleDoorPlacer
## Glowing plane + Mandelbrot panels. Null on every tile that is not Fractal.
var mandelbrot_arena: Node3D
## Summon boards + lifts + pit wipe. Null outside Arena districts.
var arena_controller: ArenaController
## Forever-war spawners + turf hazards + cloak gate. Null outside Monster Zoo districts.
var zoo_controller: ZooController
## Undead station under the chapel crypt. Null outside Graveyard districts.
var crypt_spawner: CryptSpawner
## Two opposing forever-war pads inside a Castle dungeon. Empty outside Castle districts.
var dungeon_summoners: Array[Node3D] = []
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
## Live CityBrush from CityRoot — Mandelbrot Create morph must write through this.
var _live_brush: CityBrush = null
## Worker bake result held between ground commit and detail commit.
var _bake_blocks: Dictionary = {}
var _bake_block_keys: Array[Vector3i] = []
var _bake_key_index: int = 0
var _bake_impostors: Array = []
## Local block positions already written to the live terrain. Cleared on unload.
## Far→full upgrade snapshots these, overwrites shared keys from the new bake, then wipes
## only orphans (far-only blocks the full sparse export never retouches).
var _committed_block_keys: Array[Vector3i] = []
## Far keys captured at upgrade start; used for post-stamp orphan AIR wipe.
var _upgrade_prev_committed: Array[Vector3i] = []
var _orphan_wipe_after_stamp: bool = false
## JIT subdivision + furniture targets (BuildingInterior), keyed by district cell.
## Empty on far / non-lot tiles.
var interior_buildings: Dictionary = {}
## Cell pitch of that index, in voxels — the decorator maps a foot position to a cell.
var interior_cell_size: int = 0
## City lot street doors (CastleDoorway, world voxel coords). Hung with castle doors.
var lot_doorways: Array = []
## Multi-storey elevators (ElevatorShaft, world voxel coords).
var elevator_shafts: Array = []
## Hill gem ore in world voxel coords (empty outside Hill districts).
var hill_gem_positions: PackedVector3Array = PackedVector3Array()
var hill_gem_mats: PackedInt32Array = PackedInt32Array()
## World stand inside the Unique cave-cage boss enclosure. INF when this tile has none.
var cave_cage_stand_world: Vector3 = Vector3.INF
const CAGE_DEMON_BODY_ID := "big/CageDemon"


func bind_live_brush(brush: CityBrush) -> void:
	_live_brush = brush


## The chest holder, made on demand — most tiles never have a room furnished in them.
func ensure_gem_chests() -> GemChestPlacer:
	if gem_chests != null and is_instance_valid(gem_chests):
		return gem_chests
	gem_chests = GemChestPlacerScript.new() as GemChestPlacer
	gem_chests.name = "GemChests"
	add_child(gem_chests)
	return gem_chests


func live_brush() -> CityBrush:
	return _live_brush


## False on Fractal / Arena / Zoo — spectacle tiles stay empty of pedestrians, cars and lamps.
## The zoo's only auto actors are the monsters its own stations keep pouring onto the field.
func allows_auto_actors() -> bool:
	if generator == null or generator.theme == null:
		return true
	var tid := generator.theme.id
	return (
		tid != DistrictTheme.FRACTAL
		and tid != DistrictTheme.ARENA
		and tid != DistrictTheme.ZOO
	)


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
	if signposts != null and is_instance_valid(signposts):
		signposts.set_camera(camera)
	if castle_doors != null and is_instance_valid(castle_doors):
		castle_doors.set_camera(camera)


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
	## Snapshot far keys, then clear the live list so the full stamp records what it wrote.
	## Do NOT paint those keys to AIR first — a failed/partial restamp used to leave
	## rectangular ground pits with no bedrock. Orphans are wiped after a successful stamp.
	_upgrade_prev_committed = _committed_block_keys.duplicate()
	_committed_block_keys.clear()
	_orphan_wipe_after_stamp = not _upgrade_prev_committed.is_empty()
	_bake_blocks.clear()
	_bake_block_keys.clear()
	_bake_key_index = 0
	_bake_impostors.clear()
	interior_buildings.clear()
	interior_cell_size = 0
	lot_doorways.clear()
	elevator_shafts.clear()
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
	if signposts != null and is_instance_valid(signposts):
		signposts.clear_posts()
		signposts.queue_free()
	signposts = null
	if gem_chests != null and is_instance_valid(gem_chests):
		gem_chests.clear_chests()
		gem_chests.queue_free()
	gem_chests = null
	if recipe_pickups != null and is_instance_valid(recipe_pickups):
		recipe_pickups.clear_pickups()
		recipe_pickups.queue_free()
	recipe_pickups = null
	_clear_castle_doors()
	if arena_controller != null and is_instance_valid(arena_controller):
		arena_controller.queue_free()
	arena_controller = null
	_clear_zoo_controller()
	_clear_crypt_spawner()
	_clear_dungeon_summoners()
	cave_cage_stand_world = Vector3.INF
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
	_committed_block_keys.clear()
	_upgrade_prev_committed.clear()
	_orphan_wipe_after_stamp = false
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
	if signposts != null and is_instance_valid(signposts):
		signposts.clear_posts()
		signposts.queue_free()
	signposts = null
	if gem_chests != null and is_instance_valid(gem_chests):
		gem_chests.clear_chests()
		gem_chests.queue_free()
	gem_chests = null
	if recipe_pickups != null and is_instance_valid(recipe_pickups):
		recipe_pickups.clear_pickups()
		recipe_pickups.queue_free()
	recipe_pickups = null
	_clear_castle_doors()
	if arena_controller != null and is_instance_valid(arena_controller):
		arena_controller.queue_free()
	arena_controller = null
	_clear_zoo_controller()
	_clear_crypt_spawner()
	_clear_dungeon_summoners()
	cave_cage_stand_world = Vector3.INF
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
	interior_buildings = payload.get("interior_buildings", {})
	interior_cell_size = int(payload.get("cell_size", 0))
	lot_doorways = payload.get("lot_doorways", [])
	elevator_shafts = payload.get("elevator_shafts", [])
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
	if _orphan_wipe_after_stamp:
		_orphan_wipe_after_stamp = false
		var wipe_ok := await _wipe_orphan_committed_blocks()
		if not is_instance_valid(self):
			return
		if not wipe_ok:
			is_busy = false
			failed.emit(self, "upgrade orphan wipe failed")
			return
	## Every block of this tile is written by now, so a reschedule can no longer be dropped
	## over a district neighbour that had not landed yet when the block was first committed.
	var retouch_ok := await _reschedule_meshed_commits()
	if not retouch_ok or not is_instance_valid(self):
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

	## Fractal is a quiet plaza: edge roads exist for world continuity, but no crowd,
	## traffic or lamps spawn on this tile.
	var day_night := get_tree().get_first_node_in_group(&"day_night")
	if allows_auto_actors():
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
		if day_night != null and day_night.has_method("get_night_factor"):
			street_props.set_night_factor(float(day_night.call("get_night_factor")))
		CityProfiler.end("stream_props")
		await get_tree().process_frame

		CityProfiler.begin("stream_signposts")
		signposts = SignpostPlacerScript.new()
		signposts.name = "Signposts"
		add_child(signposts)
		signposts.place_from_planner(
			generator.get_planner(),
			generator.cell_size,
			_voxel_size,
			generator.ground_thickness,
			origin_vox,
			_world_seed,
			coord,
			camera
		)
		CityProfiler.end("stream_signposts")
		await get_tree().process_frame

	## City lot façade doors only. Castle keep/dungeon openings stay open AIR — hung leaves
	## and DOOR barriers blocked dungeon forever-war circulation, so castle layouts are not hung.
	CityProfiler.begin("stream_castle_doors")
	_clear_castle_doors()
	if not lot_doorways.is_empty():
		castle_doors = CastleDoorPlacerScript.new()
		castle_doors.name = "CastleDoors"
		add_child(castle_doors)
		castle_doors.hang_lot_doorways(
			lot_doorways, _voxel_size, camera, live_brush()
		)
	CityProfiler.end("stream_castle_doors")
	await get_tree().process_frame

	## Recipe scrolls stand on landmarks, and two of those landmarks — the fractal deck and the
	## arena spires — live on tiles that spawn no auto actors at all. Placed outside that block.
	CityProfiler.begin("stream_recipes")
	_place_recipe_pickups(generator, origin_vox)
	CityProfiler.end("stream_recipes")
	await get_tree().process_frame

	CityProfiler.begin("stream_fractal_ui")
	_spawn_mandelbrot_arena(generator)
	CityProfiler.end("stream_fractal_ui")
	await get_tree().process_frame

	CityProfiler.begin("stream_arena_ui")
	_spawn_arena_controller(generator)
	CityProfiler.end("stream_arena_ui")
	await get_tree().process_frame

	CityProfiler.begin("stream_zoo_war")
	_spawn_zoo_controller(generator)
	CityProfiler.end("stream_zoo_war")
	await get_tree().process_frame

	CityProfiler.begin("stream_crypt_spawner")
	_spawn_crypt_spawner(generator, origin_vox)
	CityProfiler.end("stream_crypt_spawner")
	await get_tree().process_frame

	CityProfiler.begin("stream_dungeon_summoners")
	_spawn_dungeon_summoners(generator, origin_vox)
	CityProfiler.end("stream_dungeon_summoners")
	await get_tree().process_frame

	CityProfiler.begin("stream_cave_cage")
	_spawn_cave_cage_boss(generator, origin_vox)
	CityProfiler.end("stream_cave_cage")
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


## Stand this tile's recipe scrolls. Landmarks are offered to the placer in descending order of
## how much of a climb they were, because the per-district cap trims from the end.
func _place_recipe_pickups(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	if gen == null:
		return
	if recipe_pickups != null and is_instance_valid(recipe_pickups):
		recipe_pickups.clear_pickups()
		recipe_pickups.queue_free()
	recipe_pickups = RecipePickupPlacerScript.new() as RecipePickupPlacer
	recipe_pickups.name = "RecipePickups"
	add_child(recipe_pickups)
	_place_castle_tower_recipe(gen, origin_vox)
	_place_arena_tower_recipe(gen, origin_vox)
	_place_hill_summit_recipe(gen, origin_vox)
	_place_gazebo_recipe(gen, origin_vox)
	_place_zoo_gazebo_recipe(gen, origin_vox)
	## Fractal recipes come from lock-on Create → peak (MandelbrotArena), not stream-time.
	_place_lake_island_recipe(gen, origin_vox)
	_place_crypt_recipe(gen, origin_vox)
	_place_roof_recipes(gen, origin_vox)


## One tower per castle, chosen by the tile seed, so the climb is a different turret each world.
func _place_castle_tower_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var layout := gen.get_castle_layout()
	if layout == null or layout.towers.is_empty():
		return
	var index := absi(_dseed) % layout.towers.size()
	var tower: CastleTower = layout.towers[index]
	## Two voxels over the shaft top clears the merlon ring that sits at top_y + 1.
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_CASTLE_TOWER,
		coord,
		index,
		_landmark_world(tower.center, tower.top_y + 2, origin_vox),
		_dseed ^ 0x0CA57
	)


func _place_arena_tower_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var layout := gen.get_arena_layout()
	if layout == null or layout.corner_spires.is_empty():
		return
	var index := absi(_dseed) % layout.corner_spires.size()
	var spire: Vector3i = layout.corner_spires[index]
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_ARENA_TOWER,
		coord,
		index,
		_landmark_world(Vector2i(spire.x, spire.z), spire.y + 1, origin_vox),
		_dseed ^ 0x0A2E4
	)


func _place_hill_summit_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var summit := gen.get_hill_summit_top()
	if summit.x < 0:
		return
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_HILL_SUMMIT,
		coord,
		0,
		_landmark_world(
			Vector2i(summit.x, summit.z), gen.ground_thickness + summit.y + 1, origin_vox
		),
		_dseed ^ 0x51117
	)


func _place_gazebo_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var gazebo := gen.get_park_gazebo()
	if gazebo.x < 0:
		return
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_GAZEBO,
		coord,
		0,
		_landmark_world(Vector2i(gazebo.x, gazebo.z), gazebo.y, origin_vox),
		_dseed ^ 0x6A2E0
	)


## Monster Zoo: one district-level roll, then a single roof among summon stations and
## battlefield gazebos. Not 50% per gazebo — that would carpet the field in scrolls.
func _place_zoo_gazebo_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var layout := gen.get_zoo_layout()
	if layout == null or layout.gazebo_roof_vox.is_empty():
		return
	var site_seed := _dseed ^ 0x2006A
	if not RecipePickupPlacer.should_place(RecipePickupPlacer.SITE_ZOO_GAZEBO, site_seed):
		return
	var pick := RandomNumberGenerator.new()
	pick.seed = _dseed ^ 0x2006B
	var index := pick.randi() % layout.gazebo_roof_vox.size()
	var roof: Vector3i = layout.gazebo_roof_vox[index]
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_ZOO_GAZEBO,
		coord,
		index,
		_landmark_world(Vector2i(roof.x, roof.z), roof.y + 1, origin_vox),
		site_seed
	)


## The tallest island only. A lake can hold three, and a scroll on each would turn a rare find
## into a rowing route.
func _place_lake_island_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var crowns := gen.get_lake_island_crowns()
	if crowns.is_empty():
		return
	var best := 0
	for i in range(crowns.size()):
		if crowns[i].y > crowns[best].y:
			best = i
	var crown := crowns[best]
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_LAKE_ISLAND,
		coord,
		best,
		_landmark_world(
			Vector2i(crown.x, crown.z), gen.ground_thickness + crown.y + 1, origin_vox
		),
		_dseed ^ 0x15AD5
	)


## One chamber of the catacombs, chosen by the tile seed. Off the hub, so it is a room the
## player has to walk the halls to find.
func _place_crypt_recipe(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var rooms := gen.get_crypt_rooms()
	if rooms.is_empty():
		return
	var index := absi(_dseed) % rooms.size()
	var room := rooms[index]
	recipe_pickups.try_place(
		RecipePickupPlacer.SITE_CRYPT,
		coord,
		index,
		_landmark_world(Vector2i(room.x, room.z), room.y, origin_vox),
		_dseed ^ 0x0C297
	)


## The tallest handful of roofs each get their own long-odds roll.
func _place_roof_recipes(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var roofs := gen.get_tall_roofs()
	for i in range(mini(roofs.size(), DistrictGenerator.TALL_ROOF_CANDIDATES)):
		if recipe_pickups.at_capacity():
			return
		var roof := roofs[i]
		recipe_pickups.try_place(
			RecipePickupPlacer.SITE_ROOFTOP,
			coord,
			i,
			_landmark_world(Vector2i(roof.x, roof.z), roof.y, origin_vox),
			(_dseed ^ 0x0400F) + i * 7919
		)


## District-local voxel column + voxel Y to a world point in the middle of that column, lifted
## clear of the surface it stands on so the scroll reads as floating rather than half-sunk.
func _landmark_world(column: Vector2i, y: int, origin_vox: Vector3i) -> Vector3:
	return Vector3(
		(float(column.x) + float(origin_vox.x) + 0.5) * _voxel_size,
		(float(y) + float(origin_vox.y)) * _voxel_size + 0.5,
		(float(column.y) + float(origin_vox.z) + 0.5) * _voxel_size
	)


func _spawn_mandelbrot_arena(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var bounds: Dictionary = gen.get_fractal_world_bounds()
	if bounds.is_empty():
		return
	if mandelbrot_arena != null and is_instance_valid(mandelbrot_arena):
		mandelbrot_arena.queue_free()
	mandelbrot_arena = MandelbrotArenaScript.new() as Node3D
	mandelbrot_arena.name = "MandelbrotArena"
	add_child(mandelbrot_arena)
	mandelbrot_arena.call(
		"setup",
		bounds["min"] as Vector3,
		bounds["max"] as Vector3,
		float(bounds.get("ground_y_m", 0.0)),
		Callable(self, "live_brush"),
		_voxel_size,
		_dseed,
		coord
	)


func _spawn_arena_controller(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var layout: ArenaLayout = gen.get_arena_layout()
	if layout == null:
		return
	if arena_controller != null and is_instance_valid(arena_controller):
		arena_controller.queue_free()
	arena_controller = null
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: Arena needs CityRoot for summon/wipe")
		return
	arena_controller = ArenaControllerScript.new() as ArenaController
	add_child(arena_controller)
	arena_controller.setup(
		layout,
		origin_vox,
		_voxel_size,
		_dseed,
		Callable(self, "live_brush"),
		Callable(city, "spawn_monster_at"),
		Callable(city, "alive_undead_units"),
		Callable(city, "despawn_undead_unit")
	)


## Start this tile's forever war. Nothing here waits on the player: the stations begin
## delivering bodies as soon as the district is live, and stop when it streams out.
func _spawn_zoo_controller(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var layout: ZooLayout = gen.get_zoo_layout()
	if layout == null:
		return
	_clear_zoo_controller()
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: the Monster Zoo needs CityRoot to run its war")
		return
	zoo_controller = ZooControllerScript.new() as ZooController
	add_child(zoo_controller)
	zoo_controller.setup(
		layout,
		origin_vox,
		_voxel_size,
		_dseed,
		city,
		Callable(self, "live_brush"),
		Callable(city, "spawn_monster_at"),
		Callable(city, "alive_undead_units"),
		Callable(city, "despawn_undead_unit")
	)


## The war does not outlive its district: unloading takes the cloak and the bodies with it.
func _clear_zoo_controller() -> void:
	if zoo_controller != null and is_instance_valid(zoo_controller):
		zoo_controller.shutdown()
		zoo_controller.queue_free()
	zoo_controller = null


## Undead forever-war pad in the crypt hub under the chapel — no gazebo, just the station.
func _spawn_crypt_spawner(gen: DistrictGenerator, p_origin_vox: Vector3i) -> void:
	if gen == null:
		return
	var pad := gen.get_crypt_spawner()
	if pad.x < 0:
		return
	_clear_crypt_spawner()
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: crypt undead station needs CityRoot to spawn")
		return
	var world := _landmark_world(Vector2i(pad.x, pad.z), pad.y, p_origin_vox)
	crypt_spawner = CryptSpawnerScript.new() as CryptSpawner
	add_child(crypt_spawner)
	crypt_spawner.setup(
		world,
		_dseed,
		Callable(city, "spawn_monster_at"),
		Callable(city, "alive_undead_units"),
		Callable(city, "despawn_undead_unit")
	)


func _clear_castle_doors() -> void:
	if castle_doors != null and is_instance_valid(castle_doors):
		castle_doors.clear_doors()
		castle_doors.queue_free()
	castle_doors = null


func _clear_crypt_spawner() -> void:
	if crypt_spawner != null and is_instance_valid(crypt_spawner):
		crypt_spawner.shutdown()
		crypt_spawner.queue_free()
	crypt_spawner = null


## Two opposing forever-war pads inside the castle dungeon vaults.
func _spawn_dungeon_summoners(gen: DistrictGenerator, p_origin_vox: Vector3i) -> void:
	_clear_dungeon_summoners()
	if gen == null:
		return
	var layout: CastleLayout = gen.get_castle_layout()
	if layout == null:
		return
	if layout.dungeon_summoners.size() != layout.dungeon_summoner_factions.size():
		push_error(
			"DistrictInstance: dungeon summoner pads/factions mismatch (%d vs %d)"
			% [layout.dungeon_summoners.size(), layout.dungeon_summoner_factions.size()]
		)
		assert(false, "DistrictInstance: bad dungeon summoner plan")
		return
	if layout.dungeon_summoners.is_empty():
		return
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: castle dungeon summoners need CityRoot to spawn")
		return
	for i in range(layout.dungeon_summoners.size()):
		var pad: Vector3i = layout.dungeon_summoners[i]
		var faction := String(layout.dungeon_summoner_factions[i])
		var world := _landmark_world(Vector2i(pad.x, pad.z), pad.y, p_origin_vox)
		var spawner: Node3D = FactionPadSpawnerScript.new() as Node3D
		add_child(spawner)
		spawner.call(
			"setup",
			world,
			_dseed,
			Callable(city, "spawn_monster_at"),
			Callable(city, "alive_undead_units"),
			Callable(city, "despawn_undead_unit"),
			faction,
			"dungeon_summoner",
			StringName("dungeon_summoner_%d" % i),
			"DungeonSummoner_%s" % faction
		)
		dungeon_summoners.append(spawner)


func _clear_dungeon_summoners() -> void:
	for spawner: Node3D in dungeon_summoners:
		if spawner != null and is_instance_valid(spawner):
			spawner.call("shutdown")
			spawner.queue_free()
	dungeon_summoners.clear()


## One Unique CageDemon per Hill — stands inside the blastable red cage baked by HillComposer.
func _spawn_cave_cage_boss(gen: DistrictGenerator, p_origin_vox: Vector3i) -> void:
	cave_cage_stand_world = Vector3.INF
	if gen == null:
		return
	var stand := gen.get_hill_cave_cage_stand()
	if stand.x < 0:
		return
	cave_cage_stand_world = _landmark_world(Vector2i(stand.x, stand.z), stand.y, p_origin_vox)
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: cave cage boss needs CityRoot to spawn")
		assert(false, "DistrictInstance: no CityRoot for cage boss")
		return
	## No nav snap — the stand is inside the blastable cage; snapping would free the boss.
	var unit: UndeadUnit = city.spawn_monster_at(
		CAGE_DEMON_BODY_ID, cave_cage_stand_world, false
	)
	if unit == null:
		push_warning(
			"DistrictInstance: failed to spawn %s at %s" % [CAGE_DEMON_BODY_ID, str(cave_cage_stand_world)]
		)


func _find_city_root() -> CityRoot:
	var n: Node = get_parent()
	while n != null:
		if n is CityRoot:
			return n as CityRoot
		n = n.get_parent()
	return null


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
	var theme := DistrictTheme.for_district(_world_seed, coord)
	if bake_quality != "far" and theme.id == DistrictTheme.HILL:
		var city := _find_city_root()
		if city != null and city.has_method("hill_gem_paint_list"):
			params["hill_gem_mats_to_place"] = city.call("hill_gem_paint_list", coord)
		else:
			## Tools without a CityRoot still get the unvisited constant.
			params["hill_gem_mats_to_place"] = DistrictEconomy.flat_gem_list(
				DistrictEconomy.roll_budgets(
					DistrictTheme.HILL, DistrictCoord.district_seed(_world_seed, coord)
				)
			)
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


func _remember_committed_block(bp: Vector3i) -> void:
	## Dedup: ground and detail phases never share a local Y band, so append is enough.
	_committed_block_keys.append(bp)


## After a far→full overwrite, paint far-only blocks to AIR. Shared keys were already
## restamped; clearing them first is what used to open bedrock voids on commit failure.
func _wipe_orphan_committed_blocks() -> bool:
	var terrain := _terrain_ref
	var orphans: Array[Vector3i] = OfflineVolumeCommitterScript.orphan_block_keys(
		_upgrade_prev_committed, _bake_blocks
	)
	_upgrade_prev_committed.clear()
	if terrain == null or orphans.is_empty():
		return true
	## Do not CityProfiler.begin/end across awaits — streamer._process nests scopes each frame.
	var wipe_t0 := Time.get_ticks_usec()
	## Uniform AIR block sentinel (see OfflineVolumeCommitter.make_buffer_u16).
	var air_sentinel := PackedByteArray([0, 0])
	const BUDGET_MSEC := 4
	var i := 0
	while i < orphans.size():
		if not is_instance_valid(self):
			CityProfiler.scope_us("stream_upgrade_wipe", Time.get_ticks_usec() - wipe_t0)
			return false
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		var t0 := Time.get_ticks_msec()
		while i < orphans.size() and Time.get_ticks_msec() - t0 < BUDGET_MSEC:
			var bp: Vector3i = orphans[i]
			var ok := OfflineVolumeCommitterScript.commit_block(
				terrain, origin_vox, bp, air_sentinel
			)
			var attempts := 0
			while not ok and attempts < 90:
				await get_tree().process_frame
				ok = OfflineVolumeCommitterScript.commit_block(
					terrain, origin_vox, bp, air_sentinel
				)
				attempts += 1
			if not ok:
				push_error(
					"DistrictInstance orphan wipe failed at %s local block %s"
					% [str(coord), str(bp)]
				)
				OfflineVolumeCommitterScript.release_commit(coord)
				CityProfiler.scope_us("stream_upgrade_wipe", Time.get_ticks_usec() - wipe_t0)
				return false
			i += 1
		OfflineVolumeCommitterScript.release_commit(coord)
		await get_tree().process_frame
	CityProfiler.scope_us("stream_upgrade_wipe", Time.get_ticks_usec() - wipe_t0)
	print(
		"DistrictInstance wiped %d orphan far blocks after upgrade %s"
		% [orphans.size(), str(coord)]
	)
	return true


## Re-ask VoxelTerrain to mesh the committed blocks that already carry a mesh.
##
## A commit requests a remesh, but VoxelTerrain discards the request unless all 27 data
## blocks around the mesh block are loaded, and nothing re-issues it later. A tile stamped
## while the player already stands in it can therefore keep the mesh it had from before the
## stamp — correct voxels underfoot, because the walker moves with VoxelBoxMover against
## data rather than against geometry, over a surface that is missing or stale on screen
## until some unrelated edit nearby happens to reschedule it.
##
## `is_area_meshed` cannot find those blocks: it reports whether a mesh block exists, not
## whether it is current, so a stale mesh answers true. It is used here only to skip the
## rest of the tile, where the anchor is data-only, no mesh block exists, and the engine
## would drop the request anyway.
func _reschedule_meshed_commits() -> bool:
	var terrain := _terrain_ref
	var tool := _tool_ref
	var t0 := Time.get_ticks_usec()
	const BUDGET_MSEC := 3
	var touched := 0
	var unloaded := 0
	var i := 0
	while i < _committed_block_keys.size():
		if not is_instance_valid(self):
			OfflineVolumeCommitterScript.release_commit(coord)
			CityProfiler.scope_us("stream_mesh_retouch", Time.get_ticks_usec() - t0)
			return false
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		var t_slice := Time.get_ticks_msec()
		while (
			i < _committed_block_keys.size()
			and Time.get_ticks_msec() - t_slice < BUDGET_MSEC
		):
			var bp: Vector3i = _committed_block_keys[i]
			i += 1
			var area := OfflineVolumeCommitterScript.block_voxel_aabb(origin_vox, bp)
			if not terrain.is_area_meshed(area):
				continue
			if OfflineVolumeCommitterScript.retouch_block(terrain, tool, origin_vox, bp):
				touched += 1
			else:
				unloaded += 1
		OfflineVolumeCommitterScript.release_commit(coord)
		await get_tree().process_frame
	CityProfiler.scope_us("stream_mesh_retouch", Time.get_ticks_usec() - t0)
	if touched > 0 or unloaded > 0:
		print(
			"DistrictInstance re-meshed %d stamped blocks %s (%d unloaded meanwhile)"
			% [touched, str(coord), unloaded]
		)
	return true


func _commit_blocks_until(scope_name: String = "voxel_commit") -> bool:
	## Time-budgeted commits. Keys must already be nearest-first for this phase.
	## Remesh backpressure: do not outrun VoxelTools — feeding more blocks while
	## remaining_main_thread_blocks is high produces 600ms+ unaccounted gaps.
	const BUDGET_MSEC := 3
	const BUDGET_MSEC_SOFT := 1
	var terrain := _terrain_ref
	while true:
		if not is_instance_valid(self):
			OfflineVolumeCommitterScript.release_commit(coord)
			return false
		## Hard pressure: release the lock so another district is not stuck waiting,
		## then idle until the remesher drains.
		var pressure := CityProfiler.remesh_pressure()
		if pressure >= 2:
			OfflineVolumeCommitterScript.release_commit(coord)
			CityProfiler.set_counter("remesh_backpressure", 2)
			CityProfiler.set_counter(
				"stream_blocks_left", maxi(_bake_block_keys.size() - _bake_key_index, 0)
			)
			await get_tree().process_frame
			continue
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		if _bake_key_index >= _bake_block_keys.size():
			break

		var budget_ms := BUDGET_MSEC_SOFT if pressure >= 1 else BUDGET_MSEC
		CityProfiler.set_counter("remesh_backpressure", pressure)
		var t0 := Time.get_ticks_msec()
		var t0_us := Time.get_ticks_usec()
		var committed := 0
		while _bake_key_index < _bake_block_keys.size():
			var bp: Vector3i = _bake_block_keys[_bake_key_index]
			if not _bake_blocks.has(bp):
				push_error(
					"DistrictInstance commit missing bake payload at %s local block %s"
					% [str(coord), str(bp)]
				)
				OfflineVolumeCommitterScript.release_commit(coord)
				return false
			var data: PackedByteArray = _bake_blocks[bp] as PackedByteArray
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
			_remember_committed_block(bp)
			_bake_key_index += 1
			committed += 1
			if Time.get_ticks_msec() - t0 >= budget_ms:
				break
		CityProfiler.scope_us(scope_name, Time.get_ticks_usec() - t0_us)
		CityProfiler.set_counter(
			"stream_blocks_left", maxi(_bake_block_keys.size() - _bake_key_index, 0)
		)
		if committed > 0:
			stamp_progress.emit(committed)
		await get_tree().process_frame

	OfflineVolumeCommitterScript.release_commit(coord)
	CityProfiler.set_counter("remesh_backpressure", 0)
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
