## Thin brush: live VoxelTool *or* OfflineVoxelVolume (thread-safe baking).
## Local district coords; live mode offsets by `origin` into world voxel space.
class_name CityBrush
extends RefCounted

const OfflineVoxelVolumeScript := preload("res://scripts/city/offline_voxel_volume.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

var tool: VoxelTool
var origin: Vector3i = Vector3i.ZERO
## OfflineVoxelVolume / NativeOfflineVoxelVolume when baking off-thread; null in live mode.
var volume


func _init(p_tool: VoxelTool = null, p_origin: Vector3i = Vector3i.ZERO) -> void:
	tool = p_tool
	origin = p_origin
	if tool != null:
		tool.channel = VoxelBuffer.CHANNEL_TYPE
		tool.mode = VoxelTool.MODE_SET


func use_offline_volume(p_volume = null) -> void:
	if p_volume != null:
		volume = p_volume
	else:
		volume = CityVoxelNativeScript.make_volume()
		if volume == null:
			volume = OfflineVoxelVolumeScript.new()
	## Offline paints in local space; origin applied at commit time.
	origin = Vector3i.ZERO


func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	## Inclusive min, exclusive max (local — callers use local).
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	if volume != null:
		volume.fill_box(min_v, max_v, material_id)
		return
	if tool == null:
		push_error("CityBrush.fill_box: no tool or volume")
		return
	tool.mode = VoxelTool.MODE_SET
	tool.value = material_id
	var a := min_v + origin
	var b := max_v + origin - Vector3i.ONE
	tool.do_box(a, b)


func set_vox(pos: Vector3i, material_id: int) -> void:
	if volume != null:
		volume.set_vox(pos, material_id)
		return
	if tool == null:
		push_error("CityBrush.set_vox: no tool or volume")
		return
	tool.set_voxel(pos + origin, material_id)


func get_vox(pos: Vector3i) -> int:
	if volume != null:
		return int(volume.get_vox(pos))
	if tool == null:
		return 0
	return tool.get_voxel(pos + origin)


func column(x: int, z: int, y0: int, y1: int, material_id: int) -> void:
	fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), material_id)
