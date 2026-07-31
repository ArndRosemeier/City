## Headless: DOOR barriers block VoxelBoxMover when closed; open clears the plug.
## Aim-ray door pick lives in test_click_interact (needs autoloads for CastleDoorPlacer).
##
## Run: Godot --headless --path . -s res://tools/test_door_barrier.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const DoorBarrierScript := preload("res://scripts/city/door_barrier.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VOXEL_SIZE := 0.5
const ORIGIN := Vector3i(32, 4, 32)

var _failed := false
var _terrain: VoxelTerrain
var _tool: VoxelTool
var _brush: CityBrush


func _initialize() -> void:
	await _make_terrain()
	_brush = CityBrushScript.new(_tool, Vector3i.ZERO)
	_check_barrier_cells()
	await _check_mover_block_and_open()
	_check_toggle_no_orphan()
	if _failed:
		push_error("test_door_barrier: FAILED")
		quit(1)
	else:
		print("test_door_barrier: OK")
		quit(0)


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _make_doorway() -> CastleDoorway:
	var d := CastleDoorway.new()
	d.center = Vector2i(ORIGIN.x, ORIGIN.z)
	d.axis = Vector2i(0, 1)
	d.width = 3
	d.depth = 1
	d.floor_y = ORIGIN.y
	d.height = 4
	d.arch_courses = 0
	d.leaf = CastleDoorway.LEAF_DOOR
	d.link = CastleDoorway.LINK_LOOP
	return d


func _check_barrier_cells() -> void:
	var d := _make_doorway()
	var cells: Array[Vector3i] = DoorBarrierScript.barrier_cells(d)
	## width 3 × depth 1 × height 4 = 12
	if cells.size() != 12:
		_fail("FAIL barrier_cells size %d, expected 12" % cells.size())
		return
	print("  barrier_cells: %d" % cells.size())


func _check_mover_block_and_open() -> void:
	var d := _make_doorway()
	## Floor slab under the doorway so the capsule has footing context.
	_brush.begin_edit()
	for x in range(ORIGIN.x - 2, ORIGIN.x + 3):
		for z in range(ORIGIN.z - 2, ORIGIN.z + 6):
			_brush.set_vox(Vector3i(x, ORIGIN.y, z), VoxelMaterial.STONE)
	_brush.end_edit()
	## Wait a couple frames for mesher/collision tables.
	for _i in range(4):
		await process_frame

	var closed_n := DoorBarrierScript.apply_closed(_brush, d)
	if closed_n <= 0:
		_fail("FAIL apply_closed wrote nothing")
		return
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) != VoxelMaterial.DOOR:
			_fail("FAIL closed cell %s is %d not DOOR" % [vox, _brush.get_vox(vox)])
			return
	for _i in range(4):
		await process_frame

	var mover := VoxelBoxMover.new()
	mover.set_collision_mask(1)
	mover.set_step_climbing_enabled(false)
	## Capsule standing in front of the door, walking +Z into the plug.
	var start := Vector3(
		(float(ORIGIN.x) + 0.5) * VOXEL_SIZE,
		(float(ORIGIN.y) + 1.0) * VOXEL_SIZE,
		(float(ORIGIN.z) - 1.2) * VOXEL_SIZE
	)
	var aabb := AABB(Vector3(-0.25, 0.0, -0.25), Vector3(0.5, 1.6, 0.5))
	var want := Vector3(0.0, 0.0, 2.0)
	var allowed: Vector3 = mover.get_motion(start, want, aabb, _terrain)
	## Gap to the plug is ~0.35 m; anything near the full 2 m wish means we walked through.
	if allowed.z > 0.6:
		_fail("FAIL closed door allowed z=%.3f (expected blocked)" % allowed.z)
		return
	print("  closed blocks mover (allowed.z=%.3f)" % allowed.z)

	var opened := DoorBarrierScript.apply_open(_brush, d)
	if opened <= 0:
		_fail("FAIL apply_open cleared nothing")
		return
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) != VoxelMaterial.AIR:
			_fail("FAIL open left %s as %d" % [vox, _brush.get_vox(vox)])
			return
	for _i in range(4):
		await process_frame
	var allowed_open: Vector3 = mover.get_motion(start, want, aabb, _terrain)
	if allowed_open.z < 0.5:
		_fail("FAIL open door still blocked (allowed.z=%.3f)" % allowed_open.z)
		return
	print("  open allows mover (allowed.z=%.3f)" % allowed_open.z)


func _check_toggle_no_orphan() -> void:
	## Barrier open/close cycle (placer is a thin wrapper over DoorBarrier).
	var d := _make_doorway()
	d.center = Vector2i(ORIGIN.x + 20, ORIGIN.z + 20)
	if DoorBarrierScript.apply_closed(_brush, d) <= 0:
		_fail("FAIL seal wrote nothing")
		return
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) != VoxelMaterial.DOOR:
			_fail("FAIL seal missing DOOR at %s" % vox)
			return
	if DoorBarrierScript.apply_open(_brush, d) <= 0:
		_fail("FAIL open cleared nothing")
		return
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) == VoxelMaterial.DOOR:
			_fail("FAIL orphan DOOR after open at %s" % vox)
			return
	if DoorBarrierScript.apply_closed(_brush, d) <= 0:
		_fail("FAIL re-close wrote nothing")
		return
	var door_cells := 0
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) == VoxelMaterial.DOOR:
			door_cells += 1
	if door_cells <= 0:
		_fail("FAIL re-close wrote no DOOR")
		return
	DoorBarrierScript.apply_open(_brush, d)
	for vox in DoorBarrierScript.barrier_cells(d):
		if _brush.get_vox(vox) == VoxelMaterial.DOOR:
			_fail("FAIL final open left DOOR at %s" % vox)
			return
	print("  toggle cycle: no orphan DOOR")


func _make_terrain() -> void:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	root.add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	_terrain.bounds = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 220, 4000))
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 512
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	root.add_child(anchor)
	anchor.global_position = Vector3(ORIGIN) * VOXEL_SIZE

	var box := AABB(Vector3(ORIGIN) - Vector3(16, 8, 16), Vector3(64, 32, 64))
	for _i in range(600):
		await process_frame
		if _tool.is_area_editable(box):
			return
	_fail("FAIL area never became editable")
