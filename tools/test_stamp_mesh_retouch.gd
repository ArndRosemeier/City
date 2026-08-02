## Post-stamp mesh retouch must reschedule meshing without touching a single voxel.
##
## VoxelTerrain drops a commit's remesh request unless all 27 data blocks around the mesh
## block are loaded, and never re-issues it — a tile stamped under the player's feet can keep
## a pre-stamp mesh while the data underneath is already correct. DistrictInstance closes that
## by writing committed blocks back unchanged. The danger is the write itself: copying an area
## that is not resident yields AIR, so a careless retouch would carve the hole it exists to
## close, and replaying the baked payload instead would roll back whatever the player shot
## away mid-stamp.
##
## Run: powershell -File tools\run_test.ps1 test_stamp_mesh_retouch
extends Node

const OfflineVolumeCommitterScript := preload("res://scripts/city/offline_volume_committer.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")

const VOXEL_SIZE := 0.5
const BLOCK := 16
## Local block (0,0,0) of a district whose origin is the world origin.
const ORIGIN_VOX := Vector3i(0, 0, 0)
const LOCAL_BP := Vector3i(0, 0, 0)
## Inside terrain bounds but far outside the viewer, so its data never loads. Out of bounds
## would not do: an area with nothing to edit in it reports editable.
const UNLOADED_BP := Vector3i(40, 0, 40)

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _make_terrain()
	if not _failed:
		_check_block_aabb()
		await _check_retouch_preserves_voxels()
		_check_retouch_refuses_unloaded()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_block_aabb() -> void:
	var area := OfflineVolumeCommitterScript.block_voxel_aabb(
		Vector3i(BLOCK * 3, 0, BLOCK * -2), Vector3i(1, 2, 0)
	)
	var want := AABB(Vector3(BLOCK * 4, BLOCK * 2, BLOCK * -2), Vector3(BLOCK, BLOCK, BLOCK))
	if area != want:
		_fail("FAIL block_voxel_aabb %s want %s" % [str(area), str(want)])
		return
	print("OK block_voxel_aabb maps a local block key to its voxel extent")


func _check_retouch_preserves_voxels() -> void:
	## Uniform STONE, then live edits on top — the retouch must keep both.
	var sentinel := PackedByteArray([VoxelMaterial.STONE & 0xFF, (VoxelMaterial.STONE >> 8) & 0xFF])
	## A commit is refused until the viewer has been paired, which takes a frame or two.
	var committed := false
	for _i in range(120):
		committed = OfflineVolumeCommitterScript.commit_block(
			_terrain, ORIGIN_VOX, LOCAL_BP, sentinel
		)
		if committed:
			break
		await get_tree().process_frame
	if not committed:
		_fail("FAIL commit_block never accepted the stone block")
		return
	var area := OfflineVolumeCommitterScript.block_voxel_aabb(ORIGIN_VOX, LOCAL_BP)
	if not await _await_editable(area):
		_fail("FAIL committed block %s never became editable" % str(area))
		return
	## The pass only retouches blocks that already carry a mesh, so the filter has to see
	## this one — otherwise it would skip exactly the blocks that can go stale.
	if not await _await_meshed(area):
		_fail("FAIL committed block under a visual viewer never reported as meshed")
		return
	print("OK is_area_meshed selects a committed block under a visual viewer")

	## Stand in for the player digging while the tile was still streaming.
	_tool.set_voxel(Vector3i(3, 2, 5), VoxelMaterial.BRICK)
	_tool.set_voxel(Vector3i(7, 9, 1), VoxelMaterial.AIR)

	var before := _snapshot_block()
	if not OfflineVolumeCommitterScript.retouch_block(_terrain, _tool, ORIGIN_VOX, LOCAL_BP):
		_fail("FAIL retouch_block refused a resident block")
		return
	var after := _snapshot_block()
	if before != after:
		var diff := 0
		var first := Vector3i(-1, -1, -1)
		for i in range(before.size()):
			if before[i] != after[i]:
				diff += 1
				if first.x < 0:
					first = Vector3i(i / (BLOCK * BLOCK), (i / BLOCK) % BLOCK, i % BLOCK)
		_fail("FAIL retouch changed %d of %d voxels (first %s)" % [diff, before.size(), first])
		return
	if int(_tool.get_voxel(Vector3i(3, 2, 5))) != VoxelMaterial.BRICK:
		_fail("FAIL retouch rolled back a live edit to the baked payload")
		return
	if int(_tool.get_voxel(Vector3i(7, 9, 1))) != VoxelMaterial.AIR:
		_fail("FAIL retouch refilled a voxel the player had dug out")
		return
	print("OK retouch rewrites the block without moving a voxel, live edits included")


func _check_retouch_refuses_unloaded() -> void:
	var area := OfflineVolumeCommitterScript.block_voxel_aabb(ORIGIN_VOX, UNLOADED_BP)
	if _tool.is_area_editable(area):
		_fail("FAIL block %s was expected to be out of viewer range" % str(area))
		return
	if OfflineVolumeCommitterScript.retouch_block(_terrain, _tool, ORIGIN_VOX, UNLOADED_BP):
		_fail("FAIL retouch_block accepted a block whose data is not resident")
		return
	print("OK retouch refuses a non-resident block instead of writing AIR into it")


func _snapshot_block() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(BLOCK * BLOCK * BLOCK)
	var i := 0
	for x in range(BLOCK):
		for y in range(BLOCK):
			for z in range(BLOCK):
				out[i] = int(_tool.get_voxel(Vector3i(x, y, z)))
				i += 1
	return out


func _await_editable(area: AABB) -> bool:
	for _i in range(600):
		await get_tree().process_frame
		if _tool.is_area_editable(area):
			return true
	return false


func _await_meshed(area: AABB) -> bool:
	for _i in range(600):
		await get_tree().process_frame
		if _terrain.is_area_meshed(area):
			return true
	return false


func _make_terrain() -> void:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	_terrain.bounds = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 220, 4000))
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = false
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	## Visuals on: mesh blocks must exist, or the retouch filter has nothing to select.
	var viewer := VoxelViewer.new()
	viewer.name = "MeshViewer"
	viewer.view_distance = 128
	viewer.requires_visuals = true
	viewer.requires_collisions = false
	add_child(viewer)
	viewer.global_position = Vector3(BLOCK, BLOCK, BLOCK) * 0.5 * VOXEL_SIZE
