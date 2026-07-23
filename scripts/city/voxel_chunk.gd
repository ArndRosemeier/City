## Fixed-size dense voxel chunk (16³).
class_name VoxelChunk
extends RefCounted

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

## World chunk coordinate (in chunk units).
var coord: Vector3i = Vector3i.ZERO
## Packed material ids, index = x + z*SIZE + y*SIZE*SIZE
var voxels: PackedByteArray = PackedByteArray()
var dirty: bool = true


func _init(chunk_coord: Vector3i = Vector3i.ZERO) -> void:
	coord = chunk_coord
	voxels.resize(VOLUME)
	voxels.fill(VoxelMaterial.AIR)


func index_of(local: Vector3i) -> int:
	return local.x + local.z * SIZE + local.y * SIZE * SIZE


func in_bounds(local: Vector3i) -> bool:
	return (
		local.x >= 0 and local.x < SIZE
		and local.y >= 0 and local.y < SIZE
		and local.z >= 0 and local.z < SIZE
	)


func get_voxel(local: Vector3i) -> int:
	if not in_bounds(local):
		return VoxelMaterial.AIR
	return int(voxels[index_of(local)])


func set_voxel(local: Vector3i, material_id: int) -> void:
	if not in_bounds(local):
		return
	var i := index_of(local)
	if voxels[i] == material_id:
		return
	voxels[i] = material_id
	dirty = true


## Inclusive local min, exclusive local max. Fast path for bulk fills.
func fill_local_box(min_l: Vector3i, max_l: Vector3i, material_id: int) -> void:
	var x0 := clampi(min_l.x, 0, SIZE)
	var y0 := clampi(min_l.y, 0, SIZE)
	var z0 := clampi(min_l.z, 0, SIZE)
	var x1 := clampi(max_l.x, 0, SIZE)
	var y1 := clampi(max_l.y, 0, SIZE)
	var z1 := clampi(max_l.z, 0, SIZE)
	if x0 >= x1 or y0 >= y1 or z0 >= z1:
		return
	for y in range(y0, y1):
		var y_off := y * SIZE * SIZE
		for z in range(z0, z1):
			var row := y_off + z * SIZE
			for x in range(x0, x1):
				voxels[row + x] = material_id
	dirty = true


func get_voxel_fast(x: int, y: int, z: int) -> int:
	return int(voxels[x + z * SIZE + y * SIZE * SIZE])


func fill(material_id: int) -> void:
	voxels.fill(material_id)
	dirty = true


func is_empty() -> bool:
	for i in range(VOLUME):
		if voxels[i] != VoxelMaterial.AIR:
			return false
	return true
