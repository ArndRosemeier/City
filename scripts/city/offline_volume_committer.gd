## Commits OfflineVoxelVolume block maps into a live VoxelTerrain (main thread only).
class_name OfflineVolumeCommitter
extends RefCounted

const BLOCK := 16
const BLOCK_VOXELS := BLOCK * BLOCK * BLOCK

## Only one district may commit at a time — interleaved commits stall the remesher + FPS.
static var _commit_lock_coord: Vector2i = Vector2i(9999, 9999)


static func try_acquire_commit(coord: Vector2i) -> bool:
	if _commit_lock_coord.x == 9999 and _commit_lock_coord.y == 9999:
		_commit_lock_coord = coord
		return true
	return _commit_lock_coord == coord


static func release_commit(coord: Vector2i) -> void:
	if _commit_lock_coord == coord:
		_commit_lock_coord = Vector2i(9999, 9999)


static func sorted_block_keys(blocks: Dictionary) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	for k: Variant in blocks.keys():
		keys.append(k as Vector3i)
	keys.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			if a.z != b.z:
				return a.z < b.z
			return a.x < b.x
	)
	return keys


static func world_block_pos(origin_vox: Vector3i, local_bp: Vector3i) -> Vector3i:
	return Vector3i(
		int(floor(float(origin_vox.x) / float(BLOCK))) + local_bp.x,
		int(floor(float(origin_vox.y) / float(BLOCK))) + local_bp.y,
		int(floor(float(origin_vox.z) / float(BLOCK))) + local_bp.z
	)


static func make_buffer_u16(data: PackedByteArray) -> VoxelBuffer:
	## `data` is either a 2-byte uniform sentinel [value,0] or full 8192-byte u16 channel
	## (prepared off-thread).
	var buf := VoxelBuffer.new()
	buf.create(BLOCK, BLOCK, BLOCK)
	if data.size() == 2:
		buf.fill(int(data[0]), VoxelBuffer.CHANNEL_TYPE)
		return buf
	if data.size() < BLOCK_VOXELS * 2:
		buf.fill(0, VoxelBuffer.CHANNEL_TYPE)
		return buf
	buf.decompress_channel(VoxelBuffer.CHANNEL_TYPE)
	buf.set_channel_from_byte_array(VoxelBuffer.CHANNEL_TYPE, data)
	return buf


static func commit_block(terrain: VoxelTerrain, origin_vox: Vector3i, local_bp: Vector3i, data_u16: PackedByteArray) -> bool:
	if terrain == null:
		return false
	var buf := make_buffer_u16(data_u16)
	var wbp := world_block_pos(origin_vox, local_bp)
	return terrain.try_set_block_data(wbp, buf)
