## One loaded city tile: voxels stamped + local nav/crowd/traffic/props/impostors.
class_name DistrictInstance
extends Node3D

const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const OfflineVolumeCommitterScript := preload("res://scripts/city/offline_volume_committer.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")
const BirdDirectorScript := preload("res://scripts/city/bird_director.gd")
const SignpostPlacerScript := preload("res://scripts/city/signpost_placer.gd")
const GemChestPlacerScript := preload("res://scripts/city/gem_chest_placer.gd")
const RecipePickupPlacerScript := preload("res://scripts/city/recipe_pickup_placer.gd")
const CastleDoorPlacerScript := preload("res://scripts/city/castle_door_placer.gd")
const MandelbrotArenaScript := preload("res://scripts/city/mandelbrot_arena.gd")
const ArenaControllerScript := preload("res://scripts/city/arena_controller.gd")
const TeleportChamberScript := preload("res://scripts/city/teleport_chamber.gd")
const ZooControllerScript := preload("res://scripts/city/zoo_controller.gd")
const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const GamingArenaScript := preload("res://scripts/city/gaming_arena.gd")
const TetrisPedNpcScript := preload("res://scripts/city/tetris_ped_npc.gd")
const ChessArenaScript := preload("res://scripts/city/chess_arena.gd")
const CryptSpawnerScript := preload("res://scripts/city/crypt_spawner.gd")
const FactionPadSpawnerScript := preload("res://scripts/city/faction_pad_spawner.gd")
const SpawnTowerScript := preload("res://scripts/city/spawn_tower.gd")
const AlchemyLabSiteScript := preload("res://scripts/city/alchemy_lab_site.gd")
const WantedPosterScript := preload("res://scripts/city/wanted_poster.gd")
const WantedSuspectScript := preload("res://scripts/city/wanted_suspect.gd")
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
## Ambient birds. Unlike the crowd these are on every tile, spectacle ones included — birds
## fly over an arena as readily as over a park.
var birds: BirdDirector
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
## Console ring + launch pad + beacon. Exactly one on every normal tile, null on spectacle ones.
var teleport_chamber: TeleportChamber
## Forever-war spawners + turf hazards + cloak gate. Null outside Monster Zoo districts.
var zoo_controller: ZooController
## Pot / waves / Lodestone. Null outside Siege districts; idle until the player stakes.
var siege_controller: SiegeController
## Go tables + giant board + invite peds. Null outside Gaming districts.
var gaming_arena: GamingArena
## Permanent Tetris cabinets in the Gaming quarter's arcade, plus the NPCs that play two of
## them. They stamp their own voxel shells through the live brush, so they belong to the
## stream rather than the bake, and they are freed with the tile. Empty outside Gaming.
var gaming_cabinets: Array[Node3D] = []
var gaming_cabinet_peds: Array[Node3D] = []
## Monster chess on the same tile's east lawn: the puppets, the board collider and the
## control plate. Typed as Node3D so this file parses before ChessArena is in the class cache.
var chess_arena: Node3D
## Undead station under the chapel crypt. Null outside Graveyard districts.
var crypt_spawner: CryptSpawner
## Two opposing forever-war pads inside a Castle dungeon. Empty outside Castle districts.
var dungeon_summoners: Array[Node3D] = []
## Destructible spire standing over the crypt station. Null outside Graveyard districts. Typed as
## Node3D so this file parses before SpawnTower reaches the class cache.
var crypt_spawn_tower: Node3D
## Spires standing over the dungeon pads. Index-matched to `dungeon_summoners`.
var dungeon_spawn_towers: Array[Node3D] = []
## The apothecary this tile hides, with its street tells painted. Null on tiles without one
## (most of them) and on every non-vanilla theme.
var alchemy_lab: AlchemyLabSite
## Lot cell of that apothecary, read by the interior decorator when it subdivides a storey.
## Kept separate from `alchemy_lab` because the decorator asks for it before the exterior
## node is a child of anything.
var alchemy_lab_cell: Vector2i = AlchemyLabSite.NO_CELL
## Street posters naming this tile's wanted killer, on the avenue walls. Empty when no killer
## was rolled here, which is most tiles.
var wanted_posters: Array[WantedPoster] = []
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
## Bumped when this tile is torn down. In-flight bake/commit coroutines capture the value at
## start and bail when it changes — otherwise an unload mid-await keeps writing (and can
## hold the global commit lock) after `queue_free`.
var _stamp_epoch: int = 0
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
		and tid != DistrictTheme.GAMING
	)


## Pedestrians only. Siege keeps lamps/signposts/cars (streets are the lanes) but an empty
## sidewalk — otherwise the horde peels off to chase civilians instead of the Lodestone.
func allows_pedestrians() -> bool:
	if not allows_auto_actors():
		return false
	if generator == null or generator.theme == null:
		return true
	return generator.theme.id != DistrictTheme.SIEGE


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
	if birds != null and is_instance_valid(birds):
		birds._camera = camera
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
	_stamp_ground_async(_stamp_epoch)


func begin_detail(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	if is_busy or is_ready or not is_ground_ready:
		return
	is_busy = true
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	_stamp_detail_async(_stamp_epoch)


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
	if birds != null and is_instance_valid(birds):
		birds.clear_birds()
		birds.queue_free()
	birds = null
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
	_clear_teleport_chamber()
	_clear_zoo_controller()
	_clear_siege_controller()
	_clear_crypt_spawner()
	_clear_dungeon_summoners()
	_clear_alchemy_lab()
	_clear_wanted_posters()
	cave_cage_stand_world = Vector3.INF
	_topology = null
	generator = null
	_terrain_ref = terrain
	_tool_ref = tool
	_camera_ref = camera
	CityProfiler.end("stream_upgrade_reset")
	_stamp_ground_async(_stamp_epoch)


func begin_generate(terrain: VoxelTerrain, tool: VoxelTool, camera: Camera3D) -> void:
	## Boot path: ground then detail back-to-back via streamer chaining.
	begin_ground(terrain, tool, camera)


func destroy_and_clear(_tool: VoxelTool) -> void:
	## Far unload. Partial commits drop with the data anchor when the player is outside
	## unload radius; fail / mid-stamp abort with the player nearby uses `abort_and_clear`.
	CityProfiler.begin("stream_unload")
	_stamp_epoch += 1
	OfflineVolumeCommitterScript.release_commit(coord)
	_teardown_after_stamp_stop()
	## Dropping the data-only anchor unloads this tile's voxels from RAM.
	queue_free()
	CityProfiler.end("stream_unload")


## Fail-path teardown: wipe any partial 16³ commits, then free. The streamer awaits this so
## a nearby player VoxelViewer cannot keep a rectangular pit after `failed`.
func abort_and_clear(_tool: VoxelTool) -> void:
	CityProfiler.begin("stream_abort")
	_stamp_epoch += 1
	OfflineVolumeCommitterScript.release_commit(coord)
	is_busy = false
	if not _committed_block_keys.is_empty() and not is_ready:
		await _wipe_committed_blocks_to_air("abort_and_clear")
	_teardown_after_stamp_stop()
	queue_free()
	CityProfiler.end("stream_abort")


func _teardown_after_stamp_stop() -> void:
	_unregister_nav()
	is_ready = false
	is_busy = false
	is_ground_ready = false
	_committed_block_keys.clear()
	_upgrade_prev_committed.clear()
	_orphan_wipe_after_stamp = false
	_bake_blocks.clear()
	_bake_block_keys.clear()
	_bake_key_index = 0
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
	if birds != null and is_instance_valid(birds):
		birds.clear_birds()
		birds.queue_free()
	birds = null
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
	_clear_teleport_chamber()
	_clear_zoo_controller()
	_clear_siege_controller()
	_clear_crypt_spawner()
	_clear_dungeon_summoners()
	_clear_alchemy_lab()
	_clear_wanted_posters()
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


## Shared stamp failure: roll back any blocks already written, then notify the streamer.
func _fail_stamp(reason: String) -> void:
	is_busy = false
	if not _committed_block_keys.is_empty():
		await _wipe_committed_blocks_to_air(reason)
	failed.emit(self, reason)


## AIR-stamp every block this tile wrote this stamp, then clear the list. Used when a stamp
## aborts mid-commit so a nearby viewer cannot keep a half-written district as a hole.
func _wipe_committed_blocks_to_air(reason: String) -> void:
	var terrain := _terrain_ref
	var keys: Array[Vector3i] = _committed_block_keys.duplicate()
	_committed_block_keys.clear()
	if terrain == null or keys.is_empty():
		return
	var air_sentinel := PackedByteArray([0, 0])
	const BUDGET_MSEC := 4
	var i := 0
	var failed_n := 0
	while i < keys.size():
		if not is_instance_valid(self):
			return
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		var t0 := Time.get_ticks_msec()
		while i < keys.size() and Time.get_ticks_msec() - t0 < BUDGET_MSEC:
			var bp: Vector3i = keys[i]
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
				failed_n += 1
				push_error(
					"DistrictInstance rollback wipe failed at %s local block %s (%s)"
					% [str(coord), str(bp), reason]
				)
			i += 1
		OfflineVolumeCommitterScript.release_commit(coord)
		await get_tree().process_frame
	push_error(
		"DistrictInstance rolled back %d committed block(s) at %s (%s; %d still stuck)"
		% [keys.size(), str(coord), reason, failed_n]
	)


func _stamp_cancelled_after_commits(phase: String, epoch: int) -> void:
	push_error(
		"DistrictInstance %s stamp cancelled mid-%s epoch=%d commits=%d"
		% [str(coord), phase, epoch, _committed_block_keys.size()]
	)
	if not _committed_block_keys.is_empty():
		await _wipe_committed_blocks_to_air("stamp cancelled mid-%s" % phase)


func _stamp_ground_async(epoch: int) -> void:
	## Bake the whole district off-thread, then commit ground-layer blocks on main.
	_ensure_anchor()
	_pin_data_only()
	var tool := _tool_ref
	var box := DistrictCoord.aabb_vox(coord, 208)
	var guard := 0
	while not tool.is_area_editable(box) and guard < 600:
		guard += 1
		await get_tree().process_frame
		if not _stamp_still_current(epoch):
			push_error(
				"DistrictInstance %s stamp cancelled waiting for editable area epoch=%d"
				% [str(coord), epoch]
			)
			return
	if not _stamp_still_current(epoch):
		push_error(
			"DistrictInstance %s stamp cancelled before ground bake epoch=%d" % [str(coord), epoch]
		)
		return
	if not tool.is_area_editable(box):
		await _fail_stamp("area not editable")
		return

	CityProfiler.set_counter("stream_phase", 1)  ## 1=ground bake
	var payload := await _bake_on_worker()
	if not _stamp_still_current(epoch):
		push_error(
			"DistrictInstance %s stamp cancelled after ground bake epoch=%d" % [str(coord), epoch]
		)
		return
	if payload.is_empty() or not bool(payload.get("ok", false)):
		await _fail_stamp(str(payload.get("error", "bake failed")))
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
		await _fail_stamp("bake missing generator")
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
	var ground_err := await _commit_blocks_until("stream_commit_ground", epoch)
	if ground_err == "stamp cancelled":
		await _stamp_cancelled_after_commits("ground", epoch)
		return
	if not ground_err.is_empty():
		await _fail_stamp(ground_err)
		return

	stamp_progress.emit(int(payload.get("cells_total", 0)) / 2)
	_pin_data_only()
	is_ground_ready = true
	is_busy = false
	CityProfiler.set_counter("stream_phase", 0)
	print("DistrictInstance ground ready %s quality=%s" % [str(coord), bake_quality])
	ground_ready.emit(self)


func _stamp_detail_async(epoch: int) -> void:
	var tool := _tool_ref
	var camera := _camera_ref
	if generator == null:
		await _fail_stamp("detail without generator")
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
	var detail_err := await _commit_blocks_until("stream_commit_detail", epoch)
	if detail_err == "stamp cancelled":
		await _stamp_cancelled_after_commits("detail", epoch)
		return
	if not detail_err.is_empty():
		await _fail_stamp(detail_err)
		return
	if _orphan_wipe_after_stamp:
		_orphan_wipe_after_stamp = false
		var wipe_ok := await _wipe_orphan_committed_blocks()
		if not _stamp_still_current(epoch):
			await _stamp_cancelled_after_commits("orphan wipe", epoch)
			return
		if not wipe_ok:
			await _fail_stamp("upgrade orphan wipe failed")
			return
	## Every block of this tile is written by now, so a reschedule can no longer be dropped
	## over a district neighbour that had not landed yet when the block was first committed.
	var retouch_ok := await _reschedule_meshed_commits()
	if not retouch_ok or not _stamp_still_current(epoch):
		push_error(
			"DistrictInstance %s stamp aborted during mesh retouch epoch=%d retouch_ok=%s"
			% [str(coord), epoch, str(retouch_ok)]
		)
		if not _stamp_still_current(epoch) and not _committed_block_keys.is_empty():
			await _wipe_committed_blocks_to_air("stamp cancelled mid-retouch")
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
		await _fail_stamp("street topology failed")
		return

	await get_tree().process_frame

	## Fractal is a quiet plaza: edge roads exist for world continuity, but no crowd,
	## traffic or lamps spawn on this tile. Siege skips pedestrians only (see
	## `allows_pedestrians`) so the horde is not distracted by civilians.
	var day_night := get_tree().get_first_node_in_group(&"day_night")
	if allows_auto_actors():
		if allows_pedestrians():
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

	## Outside the auto-actor block on purpose: the arena, the zoo and the fractal plaza have
	## no crowd and no traffic, but there is no district a bird would not fly over.
	CityProfiler.begin("stream_birds")
	birds = BirdDirectorScript.new()
	birds.name = "Birds"
	add_child(birds)
	birds.bind_city(_find_city_root())
	birds.setup(
		live_brush(),
		generator.get_planner(),
		origin_vox,
		Vector2i(generator.size_x, generator.size_z),
		generator.ground_thickness,
		generator.cell_size,
		_voxel_size,
		camera,
		_dseed
	)
	CityProfiler.end("stream_birds")
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

	## Street tells before anything asks about the interior: the sick panes and the shingle
	## are what let a player decide to walk in, so they have to exist the moment the tile does.
	CityProfiler.begin("stream_alchemy_lab")
	_spawn_alchemy_lab()
	CityProfiler.end("stream_alchemy_lab")
	await get_tree().process_frame

	CityProfiler.begin("stream_wanted_poster")
	await _spawn_wanted_posters()
	CityProfiler.end("stream_wanted_poster")
	await get_tree().process_frame

	## Recipe scrolls stand on landmarks, and two of those landmarks — the fractal deck and the
	## arena spires — live on tiles that spawn no auto actors at all. Placed outside that block.
	CityProfiler.begin("stream_recipes")
	_place_recipe_pickups(generator, origin_vox)
	_watch_recipe_pickups()
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

	CityProfiler.begin("stream_teleport_chamber")
	_spawn_teleport_chamber(generator)
	CityProfiler.end("stream_teleport_chamber")
	await get_tree().process_frame

	CityProfiler.begin("stream_zoo_war")
	_spawn_zoo_controller(generator)
	CityProfiler.end("stream_zoo_war")
	await get_tree().process_frame

	CityProfiler.begin("stream_siege")
	_spawn_siege_controller(generator)
	CityProfiler.end("stream_siege")
	await get_tree().process_frame

	CityProfiler.begin("stream_gaming")
	_spawn_gaming_arena(generator)
	CityProfiler.end("stream_gaming")
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


## Roll this tile's apothecary and paint its street tells. At most one per district, and
## only on ordinary urban themes.
func _spawn_alchemy_lab() -> void:
	_clear_alchemy_lab()
	if generator == null or generator.theme == null:
		return
	var cell := AlchemyLabSiteScript.lab_cell_for(
		_dseed, generator.theme.id, interior_buildings
	)
	if cell == AlchemyLabSite.NO_CELL:
		return
	var building := interior_buildings.get(cell) as BuildingInterior
	if building == null:
		return
	var site := AlchemyLabSiteScript.new() as AlchemyLabSite
	site.name = "AlchemyLab"
	add_child(site)
	if not site.setup(live_brush(), cell, building, lot_doorways):
		site.queue_free()
		return
	alchemy_lab = site
	alchemy_lab_cell = cell
	if site.has_sign() and birds != null and is_instance_valid(birds):
		birds.add_attractor(site.sign_world(_voxel_size))
	print(
		"DistrictInstance alchemy lab %s cell=%s panes=%d"
		% [str(coord), str(cell), site.panes_painted]
	)


## Roll this tile's wanted killer and paste the bills that name them. The suspect is the same
## person on every tile of the world, so the face on the wall is the face in the street.
func _spawn_wanted_posters() -> void:
	_clear_wanted_posters()
	if generator == null or generator.theme == null:
		return
	if not allows_pedestrians():
		return
	var sites := WantedPosterScript.pick_sites(
		_dseed,
		generator.theme.id,
		interior_buildings,
		generator.get_planner(),
		live_brush(),
		_voxel_size
	)
	if sites.is_empty():
		return
	## Baked before the first sheet goes up so every bill on the tile shares one texture.
	await WantedSuspectScript.ensure_portrait(_world_seed, self)
	var portrait := WantedSuspectScript.portrait()
	for site: WantedPoster.Site in sites:
		var poster := WantedPosterScript.new() as WantedPoster
		poster.name = "WantedPoster%d" % wanted_posters.size()
		add_child(poster)
		if not poster.setup(live_brush(), site, _voxel_size, portrait):
			poster.queue_free()
			continue
		wanted_posters.append(poster)
		if birds != null and is_instance_valid(birds):
			birds.add_attractor(poster.poster_world(_voxel_size))
	if wanted_posters.is_empty():
		return
	## One killer per tile, hunting near the first bill.
	if crowd != null and is_instance_valid(crowd):
		crowd.mark_wanted(
			wanted_posters[0].wanted_world(_voxel_size),
			WantedSuspectScript.identity(_world_seed)
		)
	print(
		"DistrictInstance wanted bills %s posted=%d boarded=%d"
		% [str(coord), wanted_posters.size(), wanted_posters[0].panes_boarded]
	)


## Scrolls are worth a flock too — a knot of crows on a landmark is a reason to climb it.
func _watch_recipe_pickups() -> void:
	if birds == null or not is_instance_valid(birds):
		return
	if recipe_pickups == null or not is_instance_valid(recipe_pickups):
		return
	for pickup: RecipePickup in recipe_pickups.live_pickups():
		birds.add_attractor(pickup.global_position)


## A chest was just stood up in one of this tile's rooms (JIT, long after stream time).
func watch_gem_chest(world: Vector3) -> void:
	if birds == null or not is_instance_valid(birds):
		return
	birds.add_attractor(world)


func _clear_alchemy_lab() -> void:
	if alchemy_lab != null and is_instance_valid(alchemy_lab):
		alchemy_lab.queue_free()
	alchemy_lab = null
	alchemy_lab_cell = AlchemyLabSite.NO_CELL


func _clear_wanted_posters() -> void:
	for poster: WantedPoster in wanted_posters:
		if poster != null and is_instance_valid(poster):
			poster.queue_free()
	wanted_posters.clear()


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
	_place_hill_gate_tower_recipes(gen, origin_vox)
	_place_gazebo_recipe(gen, origin_vox)
	_place_zoo_gazebo_recipe(gen, origin_vox)
	_place_tetris_cabinet_recipes(gen, origin_vox)
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


## Each cave-gate spiral rolls on its own (gamedata `hill-gate-tower`); index separates the pair.
func _place_hill_gate_tower_recipes(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var towers := gen.get_hill_cave_gate_towers()
	for i in range(towers.size()):
		if recipe_pickups.at_capacity():
			return
		var spire: Vector3 = towers[i]
		var crown := Vector3i(int(round(spire.x)), int(round(spire.y)), int(round(spire.z)))
		recipe_pickups.try_place(
			RecipePickupPlacer.SITE_HILL_GATE_TOWER,
			coord,
			i,
			_landmark_world(Vector2i(crown.x, crown.z), crown.y + 1, origin_vox),
			(_dseed ^ 0x6A7E1) + i * 7919
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


## Gaming arcade: each Tetris bay rolls on its own. Anchors are bake-time, so the scroll can
## stand before the live cabinet stamps its shell. Height matches TetrisMachine.FRAME_H.
func _place_tetris_cabinet_recipes(gen: DistrictGenerator, origin_vox: Vector3i) -> void:
	var layout := gen.get_gaming_layout()
	if layout == null or layout.arcade_cabinets.is_empty():
		return
	for i in range(layout.arcade_cabinets.size()):
		if recipe_pickups.at_capacity():
			return
		var cell: Vector3i = layout.arcade_cabinets[i]
		## Same XZ as `_stand_world`; Y is the cabinet crown plus a half-metre float.
		var top := Vector3(
			(float(origin_vox.x + cell.x) + 0.5) * _voxel_size,
			float(origin_vox.y + cell.y + 1) * _voxel_size + TetrisMachine.FRAME_H + 0.5,
			(float(origin_vox.z + cell.z) + 0.5) * _voxel_size
		)
		recipe_pickups.try_place(
			RecipePickupPlacer.SITE_TETRIS_CABINET,
			coord,
			i,
			top,
			(_dseed ^ 0x7E7C15) + i * 7919
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


## Furnish the one teleport chamber this tile baked. Spectacle themes never plan a lot, so
## `get_teleport_chamber` reports nothing there and the chamber is simply absent.
func _spawn_teleport_chamber(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var site := gen.get_teleport_chamber()
	if site.x < 0:
		return
	_clear_teleport_chamber()
	var room := gen.get_teleport_chamber_room()
	if room.size.x <= 0.0 or room.size.z <= 0.0:
		push_error("DistrictInstance: teleport chamber at %s baked with no room" % site)
		return
	teleport_chamber = TeleportChamberScript.new() as TeleportChamber
	teleport_chamber.name = "TeleportChamber"
	add_child(teleport_chamber)
	## `site.y` is the voxel the body stands *in*, so the floor surface is its bottom face.
	var floor_center := Vector3(
		(float(origin_vox.x + site.x) + 0.5) * _voxel_size,
		float(origin_vox.y + site.y) * _voxel_size,
		(float(origin_vox.z + site.z) + 0.5) * _voxel_size
	)
	var room_half := minf(room.size.x, room.size.z) * 0.5 * _voxel_size
	teleport_chamber.build(_world_seed, coord, floor_center, room_half)


func _clear_teleport_chamber() -> void:
	if teleport_chamber != null and is_instance_valid(teleport_chamber):
		teleport_chamber.queue_free()
	teleport_chamber = null


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
func _spawn_gaming_arena(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var layout: GamingLayout = gen.get_gaming_layout()
	if layout == null:
		return
	if gaming_arena != null and is_instance_valid(gaming_arena):
		gaming_arena.queue_free()
	gaming_arena = GamingArenaScript.new() as GamingArena
	gaming_arena.name = "GamingArena"
	add_child(gaming_arena)
	gaming_arena.setup(layout, origin_vox, _voxel_size, _dseed, Callable(self, "live_brush"))
	_spawn_chess_arena(layout)
	## A cabinet needs the walker whose open panels gate its keys, and on the boot tile the
	## detail stamp finishes *before* CityRoot builds that walker. CityRoot calls us back
	## once the player exists; every tile streamed in later gets its row straight away.
	var city := _find_city_root()
	if city != null and city.has_player_walker():
		stand_up_gaming_arcade()


## Stand the chess armies up on the baked court. Unlike the arcade this needs nothing from
## the live brush and nobody from CityRoot: the court is already in the voxels, the pieces are
## puppets, and a saved game resumes off the world's match registry.
func _spawn_chess_arena(layout: GamingLayout) -> void:
	if chess_arena != null and is_instance_valid(chess_arena):
		chess_arena.queue_free()
	chess_arena = null
	## No court was published — GamingComposer already said why on a tile too small for one.
	if layout.chess_max.x <= layout.chess_min.x:
		return
	chess_arena = ChessArenaScript.new() as Node3D
	chess_arena.name = "ChessArena"
	add_child(chess_arena)
	chess_arena.call("setup", layout, origin_vox, _voxel_size, _dseed)


## Stand the arcade row up. The pavilion around it is baked (GamingArcade), but a cabinet
## stamps its own GAMEBOY shell through the live brush, so it can only exist once the tile
## is streamed in — which also means it re-stamps on every return to the district.
##
## Two random bays get an NPC and stay powered; the leftover bay starts OFF with ON/NEW so
## the player has a free machine that is not already claimed.
func stand_up_gaming_arcade() -> void:
	if generator == null:
		return
	var layout: GamingLayout = generator.get_gaming_layout()
	if layout == null or layout.arcade_cabinets.is_empty():
		return
	_clear_gaming_arcade()
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: the Tetris arcade needs CityRoot to stamp its cabinets")
		return
	for i in range(layout.arcade_cabinets.size()):
		var anchor: Vector3i = layout.arcade_cabinets[i]
		var machine := city.spawn_tetris_cabinet(
			self, _stand_world(anchor), layout.arcade_yaw, "TetrisCabinet_%d" % i
		)
		if machine == null:
			return
		gaming_cabinets.append(machine)
	var order: Array[int] = []
	for i in range(gaming_cabinets.size()):
		order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = _dseed ^ 0x7E7715
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	## Prefer two ped bays whenever the row is that long; a short row still leaves one free.
	var ped_count := mini(2, maxi(gaming_cabinets.size() - 1, 0))
	var ped_idxs: Array[int] = []
	for i in range(ped_count):
		ped_idxs.append(order[i])
	var free_idx := order[ped_count] if ped_count < order.size() else -1
	for i in range(gaming_cabinets.size()):
		var player_bay := i == free_idx
		gaming_cabinets[i].call("configure_arcade", player_bay)
	for ped_i in ped_idxs:
		var machine: Node3D = gaming_cabinets[ped_i]
		var ped: Node3D = TetrisPedNpcScript.new() as Node3D
		ped.name = "ArcadePed_%d" % ped_i
		add_child(ped)
		gaming_cabinet_peds.append(ped)
		## Stand a couple of metres in front of the bay so the ped walks to it, not from the
		## shared mid-row spawn that used to dump everyone on cabinet 0.
		var spawn: Vector3 = machine.call("get_stand_world_position")
		spawn += machine.global_transform.basis.z * -1.2
		spawn.y = machine.global_position.y
		ped.call("begin", spawn, machine, 0)


func _clear_gaming_arcade() -> void:
	for machine in gaming_cabinets:
		if machine != null and is_instance_valid(machine):
			machine.queue_free()
	gaming_cabinets.clear()
	for ped in gaming_cabinet_peds:
		if ped != null and is_instance_valid(ped):
			ped.queue_free()
	gaming_cabinet_peds.clear()


## World point on top of a district-local voxel cell, centred on its XZ footprint. This is
## the convention GamingLayout's arcade anchors use: the cell you stand on, not the air
## above it.
func _stand_world(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(origin_vox.x + cell.x) + 0.5) * _voxel_size,
		float(origin_vox.y + cell.y + 1) * _voxel_size,
		(float(origin_vox.z + cell.z) + 0.5) * _voxel_size
	)


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


## Stand the Siege controller up. Nothing spawns until the player stakes gems at the Lodestone.
func _spawn_siege_controller(gen: DistrictGenerator) -> void:
	if gen == null:
		return
	var layout: SiegeLayout = gen.get_siege_layout()
	if layout == null:
		return
	_clear_siege_controller()
	var city := _find_city_root()
	if city == null:
		push_error("DistrictInstance: the Siege Quarter needs CityRoot for waves and the pot")
		return
	siege_controller = SiegeControllerScript.new() as SiegeController
	add_child(siege_controller)
	siege_controller.setup(
		layout,
		origin_vox,
		_voxel_size,
		_dseed,
		city,
		Callable(city, "spawn_monster_at"),
		Callable(city, "alive_undead_units"),
		Callable(city, "despawn_undead_unit")
	)


## An active run restores the player's faction on shutdown; an idle controller just frees.
func _clear_siege_controller() -> void:
	if siege_controller != null and is_instance_valid(siege_controller):
		siege_controller.shutdown()
		siege_controller.queue_free()
	siege_controller = null


## Undead forever-war station in the crypt hub under the chapel, with the spawn spire that keeps
## it running. The station summons beside the spire so fresh bodies do not stand in its mass.
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
		SpawnTowerScript.summon_world(world, _voxel_size),
		_dseed,
		Callable(city, "spawn_monster_at"),
		Callable(city, "alive_undead_units"),
		Callable(city, "despawn_undead_unit")
	)
	crypt_spawn_tower = _raise_spawn_tower(
		city, world, MonsterFaction.Id.UNDEAD, crypt_spawner, "CryptSpire"
	)


func _clear_castle_doors() -> void:
	if castle_doors != null and is_instance_valid(castle_doors):
		castle_doors.clear_doors()
		castle_doors.queue_free()
	castle_doors = null


func _clear_crypt_spawner() -> void:
	_clear_spawn_tower(crypt_spawn_tower)
	crypt_spawn_tower = null
	if crypt_spawner != null and is_instance_valid(crypt_spawner):
		crypt_spawner.shutdown()
		crypt_spawner.queue_free()
	crypt_spawner = null


## Stand a spire over one summoning station and hand it the station to close when it falls.
## `faction_id` is a `MonsterFaction.Id` — the side both the tower and its bodies belong to.
## Null when the tile could not place it; the station still runs, it just cannot be switched off.
func _raise_spawn_tower(
	city: CityRoot, pad_world: Vector3, faction_id: int, station: Node3D, node_name: String
) -> Node3D:
	var tower: Node3D = SpawnTowerScript.new() as Node3D
	tower.name = node_name
	add_child(tower)
	if not bool(tower.call("raise", city, _voxel_size, pad_world, faction_id, station)):
		tower.queue_free()
		return null
	return tower


func _clear_spawn_tower(tower: Node3D) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	tower.call("clear")
	tower.queue_free()


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
			SpawnTowerScript.summon_world(world, _voxel_size),
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
		dungeon_spawn_towers.append(
			_raise_spawn_tower(
				city,
				world,
				MonsterFaction.from_name(faction),
				spawner,
				"DungeonSpire_%d" % i
			)
		)


func _clear_dungeon_summoners() -> void:
	for tower: Node3D in dungeon_spawn_towers:
		_clear_spawn_tower(tower)
	dungeon_spawn_towers.clear()
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
	if bake_quality != "far" and theme.id == DistrictTheme.GAMING:
		var city_g := _find_city_root()
		if city_g != null and city_g.has_method("gaming_gem_paint_list"):
			params["gaming_gem_mats_to_place"] = city_g.call("gaming_gem_paint_list", coord)
		else:
			params["gaming_gem_mats_to_place"] = DistrictEconomy.flat_gem_list(
				DistrictEconomy.roll_budgets(
					DistrictTheme.GAMING, DistrictCoord.district_seed(_world_seed, coord)
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
## In-footprint ground-band orphans (`bp.y <= 0`) are never wiped — that would carve
## rectangular pits. Edge-bleed blocks outside the district XZ footprint are wiped.
func _wipe_orphan_committed_blocks() -> bool:
	var terrain := _terrain_ref
	var orphans: Array[Vector3i] = OfflineVolumeCommitterScript.orphan_block_keys(
		_upgrade_prev_committed, _bake_blocks
	)
	_upgrade_prev_committed.clear()
	if terrain == null or orphans.is_empty():
		return true
	var size_x := DistrictCoord.SIZE_X_VOX
	var size_z := DistrictCoord.SIZE_Z_VOX
	if generator != null:
		size_x = generator.size_x
		size_z = generator.size_z
	var ground_orphans: Array[Vector3i] = OfflineVolumeCommitterScript.ground_orphan_keys(
		orphans, size_x, size_z
	)
	var upper_orphans: Array[Vector3i] = OfflineVolumeCommitterScript.upper_orphan_keys(
		orphans, size_x, size_z
	)
	if not ground_orphans.is_empty():
		## Leave far ground in place — AIR-wiping it is the rectangular bedrock void. The full
		## bake omitted these keys; keeping the far substrate is safer than a hole, and louder
		## than silence so the sparse-export gap can be chased.
		push_error(
			"DistrictInstance %s upgrade has %d ground orphan(s) — refusing AIR wipe (first %s)"
			% [str(coord), ground_orphans.size(), str(ground_orphans[0])]
		)
	## Do not CityProfiler.begin/end across awaits — streamer._process nests scopes each frame.
	var wipe_t0 := Time.get_ticks_usec()
	## Uniform AIR block sentinel (see OfflineVolumeCommitter.make_buffer_u16).
	var air_sentinel := PackedByteArray([0, 0])
	const BUDGET_MSEC := 4
	var i := 0
	while i < upper_orphans.size():
		if not is_instance_valid(self):
			CityProfiler.scope_us("stream_upgrade_wipe", Time.get_ticks_usec() - wipe_t0)
			return false
		if not OfflineVolumeCommitterScript.try_acquire_commit(coord):
			await get_tree().process_frame
			continue
		var t0 := Time.get_ticks_msec()
		while i < upper_orphans.size() and Time.get_ticks_msec() - t0 < BUDGET_MSEC:
			var bp: Vector3i = upper_orphans[i]
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
		% [upper_orphans.size(), str(coord)]
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


func _stamp_still_current(epoch: int) -> bool:
	return is_instance_valid(self) and _stamp_epoch == epoch


## Time-budgeted commits. Keys must already be nearest-first for this phase.
## Returns "" on success, `"stamp cancelled"` on epoch abort, or a hard-fail reason
## (`"commit failed"`, `"commit missing bake payload"`) for greppable logs.
func _commit_blocks_until(scope_name: String = "voxel_commit", epoch: int = -1) -> String:
	## Remesh backpressure: do not outrun VoxelTools — feeding more blocks while
	## remaining_main_thread_blocks is high produces 600ms+ unaccounted gaps.
	const BUDGET_MSEC := 3
	const BUDGET_MSEC_SOFT := 1
	var terrain := _terrain_ref
	if epoch < 0:
		epoch = _stamp_epoch
	while true:
		if not _stamp_still_current(epoch):
			OfflineVolumeCommitterScript.release_commit(coord)
			return "stamp cancelled"
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
		if not _stamp_still_current(epoch):
			OfflineVolumeCommitterScript.release_commit(coord)
			return "stamp cancelled"
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
				return "commit missing bake payload"
			var data: PackedByteArray = _bake_blocks[bp] as PackedByteArray
			var ok := OfflineVolumeCommitterScript.commit_block(terrain, origin_vox, bp, data)
			var attempts := 0
			while not ok and attempts < 90:
				await get_tree().process_frame
				if not _stamp_still_current(epoch):
					OfflineVolumeCommitterScript.release_commit(coord)
					return "stamp cancelled"
				## Keep holding the commit lock while retrying this block.
				ok = OfflineVolumeCommitterScript.commit_block(terrain, origin_vox, bp, data)
				attempts += 1
			if not ok:
				push_error(
					"DistrictInstance commit failed at %s local block %s" % [str(coord), str(bp)]
				)
				OfflineVolumeCommitterScript.release_commit(coord)
				return "commit failed"
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
	return ""


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
