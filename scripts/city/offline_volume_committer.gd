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
	## Legacy Y-major order (kept for tests / callers that don't pass a focus).
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


static func sorted_block_keys_near_player(
	blocks: Dictionary,
	origin_vox: Vector3i,
	focus_world: Vector3,
	voxel_size: float,
	max_local_by: int = -1,
	min_local_by: int = -1
) -> Array[Vector3i]:
	## Nearest-first by horizontal distance to the player/camera.
	## Optional Y filters: ground phase uses max_local_by=0; detail uses min_local_by=1.
	var scored: Array = []
	var half := float(BLOCK) * 0.5
	var vs := maxf(voxel_size, 0.001)
	for k: Variant in blocks.keys():
		var bp: Vector3i = k as Vector3i
		if max_local_by >= 0 and bp.y > max_local_by:
			continue
		if min_local_by >= 0 and bp.y < min_local_by:
			continue
		var wbp := world_block_pos(origin_vox, bp)
		var cx := (float(wbp.x) * float(BLOCK) + half) * vs
		var cz := (float(wbp.z) * float(BLOCK) + half) * vs
		var dx := cx - focus_world.x
		var dz := cz - focus_world.z
		scored.append({"bp": bp, "d2": dx * dx + dz * dz})
	scored.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"])
	)
	var keys: Array[Vector3i] = []
	keys.resize(scored.size())
	for i in range(scored.size()):
		keys[i] = scored[i]["bp"] as Vector3i
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
