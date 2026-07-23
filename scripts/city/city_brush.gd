## Thin VoxelTool helper shared by planners / composers / grammars.
class_name CityBrush
extends RefCounted

var tool: VoxelTool


func _init(p_tool: VoxelTool = null) -> void:
	tool = p_tool
	if tool != null:
		tool.channel = VoxelBuffer.CHANNEL_TYPE
		tool.mode = VoxelTool.MODE_SET


func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	## Inclusive min, exclusive max.
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	tool.mode = VoxelTool.MODE_SET
	tool.value = material_id
	tool.do_box(min_v, max_v - Vector3i.ONE)


func set_vox(pos: Vector3i, material_id: int) -> void:
	tool.set_voxel(pos, material_id)


func get_vox(pos: Vector3i) -> int:
	return tool.get_voxel(pos)


func column(x: int, z: int, y0: int, y1: int, material_id: int) -> void:
	fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), material_id)
