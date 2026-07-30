## Pins the CityBrush write funnel: live writes land in the terrain and every one of
## them is published through `voxels_changed(aabb_vox)` in world voxel space.
##
## Run: Godot --headless --path . res://tools/test_voxel_write_funnel.tscn
extends Node

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

const VOXEL_SIZE := 0.5
## Well inside the editable bubble the viewer below pins.
const ORIGIN := Vector3i(64, 16, 64)

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _events: Array[AABB] = []
var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _make_terrain()
	if _failed:
		_quit()
		return

	var brush: CityBrush = CityBrushScript.new(_tool) as CityBrush
	brush.voxels_changed.connect(_on_voxels_changed)

	_check_single_write(brush)
	_check_batch_coalesces(brush)
	_check_fill_box(brush)
	_check_origin_offset()
	_check_offline_is_silent()

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	_quit()


func _on_voxels_changed(aabb_vox: AABB) -> void:
	_events.append(aabb_vox)


func _take_events() -> Array[AABB]:
	var out := _events.duplicate() as Array[AABB]
	_events.clear()
	return out


## One unbatched write publishes exactly the one cell it touched, and the cell really
## changed in the terrain — this is what pins CityBrush.set_vox to VoxelTool semantics.
func _check_single_write(brush: CityBrush) -> void:
	var vox := ORIGIN
	brush.set_vox(vox, VoxelMaterial.CONCRETE)
	var events := _take_events()
	if events.size() != 1:
		_fail("FAIL single write emitted %d signals, expected 1" % events.size())
		return
	var want := AABB(Vector3(vox), Vector3.ONE)
	if events[0] != want:
		_fail("FAIL single write aabb %s, expected %s" % [events[0], want])
		return
	var read := int(_tool.get_voxel(vox))
	if read != VoxelMaterial.CONCRETE:
		_fail("FAIL set_vox did not write: read %d, expected %d" % [read, VoxelMaterial.CONCRETE])
		return
	print("OK single write %s" % events[0])


## A whole logical edit (a blast, a stamped prop) is one signal covering the union.
func _check_batch_coalesces(brush: CityBrush) -> void:
	brush.begin_edit()
	brush.set_vox(ORIGIN, VoxelMaterial.AIR)
	brush.set_vox(ORIGIN + Vector3i(3, 2, 1), VoxelMaterial.BRICK)
	if not _events.is_empty():
		_fail("FAIL batch emitted %d signals before end_edit" % _events.size())
		return
	brush.end_edit()
	var events := _take_events()
	if events.size() != 1:
		_fail("FAIL batch emitted %d signals, expected 1" % events.size())
		return
	var want := AABB(Vector3(ORIGIN), Vector3(4.0, 3.0, 2.0))
	if events[0] != want:
		_fail("FAIL batch aabb %s, expected %s" % [events[0], want])
		return
	## Batched set_vox flushes via copy/paste per 16³ block — must actually land.
	if int(_tool.get_voxel(ORIGIN)) != VoxelMaterial.AIR:
		_fail("FAIL batch did not clear ORIGIN")
		return
	if int(_tool.get_voxel(ORIGIN + Vector3i(3, 2, 1))) != VoxelMaterial.BRICK:
		_fail("FAIL batch did not write brick via block paste")
		return
	print("OK batched edit %s" % events[0])


## fill_box takes inclusive min / exclusive max, and the signal keeps that convention.
func _check_fill_box(brush: CityBrush) -> void:
	var bmin := ORIGIN + Vector3i(8, 0, 8)
	var bmax := bmin + Vector3i(4, 2, 3)
	brush.fill_box(bmin, bmax, VoxelMaterial.STONE)
	var events := _take_events()
	if events.size() != 1:
		_fail("FAIL fill_box emitted %d signals, expected 1" % events.size())
		return
	var want := AABB(Vector3(bmin), Vector3(bmax - bmin))
	if events[0] != want:
		_fail("FAIL fill_box aabb %s, expected %s" % [events[0], want])
		return
	if int(_tool.get_voxel(bmax - Vector3i.ONE)) != VoxelMaterial.STONE:
		_fail("FAIL fill_box did not fill its last cell %s" % (bmax - Vector3i.ONE))
		return
	if int(_tool.get_voxel(bmax)) == VoxelMaterial.STONE:
		_fail("FAIL fill_box wrote the exclusive max cell %s" % bmax)
		return
	print("OK fill_box %s" % events[0])


## District brushes paint in local coords; the published region must be world voxels.
func _check_origin_offset() -> void:
	var offset := ORIGIN + Vector3i(0, 4, 0)
	var local := Vector3i(2, 1, 3)
	var brush: CityBrush = CityBrushScript.new(_tool, offset) as CityBrush
	var seen: Array[AABB] = []
	brush.voxels_changed.connect(func(aabb: AABB) -> void: seen.append(aabb))
	brush.set_vox(local, VoxelMaterial.GLASS)
	if seen.size() != 1:
		_fail("FAIL offset brush emitted %d signals, expected 1" % seen.size())
		return
	var want := AABB(Vector3(offset + local), Vector3.ONE)
	if seen[0] != want:
		_fail("FAIL offset brush aabb %s, expected %s" % [seen[0], want])
		return
	if int(_tool.get_voxel(offset + local)) != VoxelMaterial.GLASS:
		_fail("FAIL offset brush wrote the wrong cell (nothing at %s)" % (offset + local))
		return
	print("OK origin offset %s" % seen[0])


## Bake brushes paint millions of cells and their nav data comes from the bake, so
## they must never publish.
func _check_offline_is_silent() -> void:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var seen := 0
	brush.voxels_changed.connect(func(_aabb: AABB) -> void: seen += 1)
	brush.fill_box(Vector3i.ZERO, Vector3i(4, 4, 4), VoxelMaterial.STONE)
	brush.set_vox(Vector3i(1, 1, 1), VoxelMaterial.BRICK)
	if seen != 0:
		_fail("FAIL offline brush emitted %d signals, expected 0" % seen)
		return
	if int(brush.get_vox(Vector3i(1, 1, 1))) != VoxelMaterial.BRICK:
		_fail("FAIL offline brush did not write")
		return
	print("OK offline brush silent")


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

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 512
	anchor.requires_visuals = false
	anchor.requires_collisions = false
	add_child(anchor)
	anchor.global_position = Vector3(ORIGIN) * VOXEL_SIZE

	## Two regions get written: the ORIGIN cluster and the offset-brush probe.
	var box := AABB(Vector3(ORIGIN) - Vector3(8, 8, 8), Vector3(32, 32, 32))
	for _i in range(600):
		await get_tree().process_frame
		if _tool.is_area_editable(box):
			return
	_fail("FAIL area %s never became editable" % box)


func _quit() -> void:
	get_tree().quit(1 if _failed else 0)
