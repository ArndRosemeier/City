## Cave-cage enclosure holds walkers inert until dissolve wakes the district.
##
## Run: powershell -File tools\run_test.ps1 test_cave_cage_inert
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const ProjectileLosScript := preload("res://scripts/city/projectile_los.gd")

const VOXEL_SIZE := 0.5
const TILE := Vector2i(130, 130)
const ORIGIN := Vector3i(60000, 0, 60000)
const SX := 48
const SZ := 48
const FIELD_Y_MAX := 24
const SIM_DT := 0.05
const BODY_SEED := 20260808

var _failed := false
var _nav: NavService
var _city: TestCity
var _roster: MonsterRoster
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot
	var brush: CityBrush = null
	var player_at: Vector3 = Vector3.ZERO

	func is_player_alive() -> bool:
		return true

	func get_player_position() -> Vector3:
		return player_at

	func get_player_target_position() -> Vector3:
		return Vector3.INF

	func find_nearest_ped_position(_from: Vector3, _max_dist: float) -> Vector3:
		return Vector3.INF

	func find_nearest_ped_only(_from: Vector3, _max_dist: float) -> Vector3:
		return Vector3.INF

	func collect_ped_positions(_from: Vector3, _max_dist: float) -> PackedVector3Array:
		return PackedVector3Array()

	func voxel_brush() -> CityBrush:
		return brush

	func voxel_terrain() -> VoxelTerrain:
		return null

	## Real solid probe against the offline brush (CityRoot's needs a live VoxelTool).
	func probe_solid_ray(from_world: Vector3, to_world: Vector3) -> Dictionary:
		if brush == null:
			return {}
		var local_from := from_world / VOXEL_SIZE
		var local_to := to_world / VOXEL_SIZE
		var get_voxel := func(v: Vector3i) -> int: return brush.get_vox(v)
		var local_hit: Dictionary = ProjectileLosScript.probe_solid_ray(
			local_from, local_to, get_voxel, 1.0
		)
		if local_hit.is_empty():
			return {}
		var local_dist := float(local_hit["distance"])
		var world_len := from_world.distance_to(to_world)
		var world_dist := ProjectileLosScript.local_distance_to_world(
			local_dist, local_from, local_to, world_len
		)
		return {
			"point": from_world + (to_world - from_world).normalized() * world_dist,
			"normal": local_hit["normal"],
			"distance": world_dist,
			"voxel_id": int(local_hit["voxel_id"]),
		}


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _run()
	_cleanup()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _run() -> void:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		return
	if not _nav.register_district(TILE, _bake_open_deck()):
		_fail("FAIL NavService refused the test tile")
		return

	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)

	_city = TestCity.new()
	_city.brush = CityBrush.new()
	_city.brush.use_offline_volume()

	_roster = MonsterRoster.new()
	_roster.name = "MonsterRoster"
	add_child(_roster)
	_roster.setup(_city, _terrain, NavLod.for_collision_view(48, VOXEL_SIZE))

	_test_cave_cage_holds_inert()
	if _failed:
		return
	_test_wake_then_reinert()
	if _failed:
		return
	_test_zoo_fence_does_not_inert()


func _test_cave_cage_holds_inert() -> void:
	var centre := ORIGIN + Vector3i(24, 0, 24)
	_stamp_ring(centre, VoxelMaterial.CAVE_CAGE_GLASS, VoxelMaterial.CAVE_CAGE_FRAME)
	var stand := _w(Vector3i(24, 1, 24))
	_city.player_at = stand + Vector3(0.0, 0.0, 40.0)
	var unit := _roster.spawn_role(UndeadUnit.Role.MINION, stand, BODY_SEED, "kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL could not spawn walker inside cave cage")
		return
	unit.set_physics_process(false)
	NavAgent.reset_events()
	for _i in 8:
		unit.tick(SIM_DT)
	if not unit.is_cage_inert():
		_fail("FAIL walker inside cave cage never went inert")
		return
	if NavAgent.dig_out_events() != 0 or NavAgent.nearby_unstuck_events() != 0:
		_fail("FAIL inert walker still ran dig-out / nearby-unstuck")
		return
	if unit.velocity.length() > 0.01:
		_fail("FAIL inert walker kept velocity")
		return
	print("cave cage: walker went inert and stayed still")
	_roster.despawn_unit(unit)
	## Clear ring for the next case.
	_clear_footprint(centre)


func _test_wake_then_reinert() -> void:
	var centre := ORIGIN + Vector3i(24, 0, 24)
	_stamp_ring(centre, VoxelMaterial.CAVE_CAGE_GLASS, VoxelMaterial.CAVE_CAGE_FRAME)
	var stand := _w(Vector3i(24, 1, 24))
	_city.player_at = stand + Vector3(0.0, 0.0, 40.0)
	var unit := _roster.spawn_role(UndeadUnit.Role.MINION, stand, BODY_SEED, "kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL wake case: spawn failed")
		return
	unit.set_physics_process(false)
	for _i in 4:
		unit.tick(SIM_DT)
	if not unit.is_cage_inert():
		_fail("FAIL wake case: never inert")
		return
	## One wall gone: still three cage sides → wake, then re-inert next tick.
	_open_east_wall(centre)
	var coord := DistrictCoord.from_world(stand, VOXEL_SIZE)
	_roster.wake_cage_inert_in_district(coord)
	if unit.is_cage_inert():
		_fail("FAIL wake_cage_inert_in_district left the unit inert")
		return
	unit.tick(SIM_DT)
	if not unit.is_cage_inert():
		_fail("FAIL three remaining cage walls should re-inert after wake")
		return
	## Strip the whole pen (dissolve's end state) — wake and stay free.
	_clear_footprint(centre)
	_roster.wake_cage_inert_in_district(coord)
	unit.tick(SIM_DT)
	if unit.is_cage_inert():
		_fail("FAIL walker stayed inert after the cage was fully cleared")
		return
	print("cave cage: wake + partial pen re-inerts; full clear stays free")
	_roster.despawn_unit(unit)


func _test_zoo_fence_does_not_inert() -> void:
	var centre := ORIGIN + Vector3i(24, 0, 24)
	_stamp_ring(centre, VoxelMaterial.ZOO_FENCE_GLASS, VoxelMaterial.ZOO_FENCE_FRAME)
	var stand := _w(Vector3i(24, 1, 24))
	_city.player_at = stand + Vector3(0.0, 0.0, 40.0)
	var unit := _roster.spawn_role(UndeadUnit.Role.MINION, stand, BODY_SEED, "kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL zoo case: spawn failed")
		return
	unit.set_physics_process(false)
	for _i in 8:
		unit.tick(SIM_DT)
	if unit.is_cage_inert():
		_fail("FAIL zoo fence wrongly made the walker cage-inert")
		return
	print("zoo fence: walker stays active")
	_roster.despawn_unit(unit)
	_clear_footprint(centre)


func _stamp_ring(centre: Vector3i, pane: int, frame: int) -> void:
	var half := 3
	_city.brush.begin_edit()
	for z in range(centre.z - half, centre.z + half + 1):
		for x in range(centre.x - half, centre.x + half + 1):
			_city.brush.set_vox(Vector3i(x, centre.y, z), VoxelMaterial.CAVE_FLOOR)
			var on_ring := (
				x == centre.x - half
				or x == centre.x + half
				or z == centre.z - half
				or z == centre.z + half
			)
			for y in range(centre.y + 1, centre.y + 8):
				var vox := Vector3i(x, y, z)
				if not on_ring:
					_city.brush.set_vox(vox, VoxelMaterial.AIR)
					continue
				var corner := (
					(x == centre.x - half or x == centre.x + half)
					and (z == centre.z - half or z == centre.z + half)
				)
				_city.brush.set_vox(vox, frame if corner else pane)
	_city.brush.end_edit()


func _open_east_wall(centre: Vector3i) -> void:
	var half := 3
	var x := centre.x + half
	_city.brush.begin_edit()
	for z in range(centre.z - half + 1, centre.z + half):
		for y in range(centre.y + 1, centre.y + 8):
			_city.brush.set_vox(Vector3i(x, y, z), VoxelMaterial.AIR)
	_city.brush.end_edit()


func _clear_footprint(centre: Vector3i) -> void:
	var half := 4
	_city.brush.begin_edit()
	for z in range(centre.z - half, centre.z + half + 1):
		for x in range(centre.x - half, centre.x + half + 1):
			for y in range(centre.y, centre.y + 10):
				_city.brush.set_vox(Vector3i(x, y, z), VoxelMaterial.AIR)
	_city.brush.end_edit()


func _bake_open_deck() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CAVE_FLOOR)
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		ORIGIN,
		SX,
		SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the open deck")
		return null
	return bake


func _w(local: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + local.x) + 0.5,
		float(ORIGIN.y + local.y),
		float(ORIGIN.z + local.z) + 0.5
	) * VOXEL_SIZE


func _cleanup() -> void:
	if _roster != null and is_instance_valid(_roster):
		for u in _roster.get_alive_units():
			u.queue_free()
	NavService.reset()
	if _city != null:
		_city.free()
