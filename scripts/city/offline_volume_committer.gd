## Commits NativeOfflineVoxelVolume block maps into a live VoxelTerrain (main thread only).
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


## Drop whatever district holds the lock. Unload used to kill a stamp mid-await and leave
## this stuck forever — the next boot's spawn then waited on a lock nobody would release.
static func force_release() -> void:
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
	## `data` is either a 2-byte uniform sentinel [lo, hi] or full 8192-byte u16 channel
	## (prepared off-thread). Unexpected sizes used to fill AIR — that stamped rectangular
	## bedrock voids into the live terrain whenever a payload was truncated.
	var buf := VoxelBuffer.new()
	buf.create(BLOCK, BLOCK, BLOCK)
	if data.size() == 2:
		## LE u16 sentinel [lo, hi].
		buf.fill(int(data[0]) | (int(data[1]) << 8), VoxelBuffer.CHANNEL_TYPE)
		return buf
	if data.size() != BLOCK_VOXELS * 2:
		push_error(
			"OfflineVolumeCommitter.make_buffer_u16: unexpected payload size %d (want 2 or %d)"
			% [data.size(), BLOCK_VOXELS * 2]
		)
		return null
	buf.decompress_channel(VoxelBuffer.CHANNEL_TYPE)
	buf.set_channel_from_byte_array(VoxelBuffer.CHANNEL_TYPE, data)
	return buf


## Blocks present in a prior stamp but absent from the new sparse bake — clear these after
## overwriting shared keys, never before. Pre-clearing shared ground to AIR is what left
## rectangular pits when restamp aborted.
static func orphan_block_keys(prev: Array[Vector3i], bake_blocks: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var seen: Dictionary = {}
	for bp in prev:
		if bake_blocks.has(bp):
			continue
		if seen.has(bp):
			continue
		seen[bp] = true
		out.append(bp)
	return out


## True when a local 16³ block overlaps the district XZ footprint `[0,size_x)×[0,size_z)`.
## Far decorate (tree canopies, stoops) can paint a few voxels past the south/west edge;
## those blocks are not district substrate and must not trip the ground-orphan guard.
static func block_intersects_footprint(bp: Vector3i, size_x: int, size_z: int) -> bool:
	var x0 := bp.x * BLOCK
	var z0 := bp.z * BLOCK
	return x0 < size_x and x0 + BLOCK > 0 and z0 < size_z and z0 + BLOCK > 0


## Drop sparse-export keys that lie entirely outside the district footprint so bleed is
## never committed (and never remembered for upgrade orphan math).
static func filter_blocks_to_footprint(
	blocks: Dictionary, size_x: int, size_z: int
) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key as Vector3i
		if block_intersects_footprint(bp, size_x, size_z):
			out[bp] = blocks[key]
	return out


## Orphan keys on the ground band (`bp.y <= 0`) that still intersect the footprint.
## These must never be AIR-wiped on far→full upgrade — a missing in-bounds ground key
## is a bake bug, and wiping it opens the rectangular bedrock voids the player falls through.
## Out-of-footprint ground orphans are edge paint bleed and belong in the wipe set.
static func ground_orphan_keys(
	orphans: Array[Vector3i], size_x: int = -1, size_z: int = -1
) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var check_footprint := size_x > 0 and size_z > 0
	for bp in orphans:
		if bp.y > 0:
			continue
		if check_footprint and not block_intersects_footprint(bp, size_x, size_z):
			continue
		out.append(bp)
	return out


## Orphan keys safe to AIR-wipe after a successful full restamp: above the ground band,
## or entirely outside the district footprint (far edge bleed).
static func upper_orphan_keys(
	orphans: Array[Vector3i], size_x: int = -1, size_z: int = -1
) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var check_footprint := size_x > 0 and size_z > 0
	for bp in orphans:
		if bp.y > 0:
			out.append(bp)
			continue
		if check_footprint and not block_intersects_footprint(bp, size_x, size_z):
			out.append(bp)
	return out


static func commit_block(terrain: VoxelTerrain, origin_vox: Vector3i, local_bp: Vector3i, data_u16: PackedByteArray) -> bool:
	if terrain == null:
		push_error("OfflineVolumeCommitter.commit_block: terrain is null at local %s" % str(local_bp))
		return false
	var wbp := world_block_pos(origin_vox, local_bp)
	## Live terrain bounds start at world Y=0 — skip below-ground bake leftovers.
	if wbp.y < 0:
		return true
	var buf := make_buffer_u16(data_u16)
	if buf == null:
		push_error(
			"OfflineVolumeCommitter.commit_block: buffer is null at local %s world block %s"
			% [str(local_bp), str(wbp)]
		)
		return false
	return terrain.try_set_block_data(wbp, buf)


## Voxel-space extent of one committed block, for VoxelTerrain.is_area_meshed queries.
static func block_voxel_aabb(origin_vox: Vector3i, local_bp: Vector3i) -> AABB:
	var wbp := world_block_pos(origin_vox, local_bp)
	return AABB(Vector3(wbp * BLOCK), Vector3(BLOCK, BLOCK, BLOCK))


## Writes a block's current voxels back unchanged so VoxelTerrain reschedules its mesh.
##
## `try_set_block_data` does request a remesh, but VoxelTerrain drops that request unless all
## 27 data blocks around the mesh block are loaded, and nothing re-issues it afterwards.
## Re-reading through the tool rather than replaying the baked payload keeps whatever the
## player shot away while the tile was still streaming.
##
## False means the block left every viewer's data box while we were working — it is being
## unloaded, so it has no mesh left to fix.
static func retouch_block(
	terrain: VoxelTerrain, tool: VoxelTool, origin_vox: Vector3i, local_bp: Vector3i
) -> bool:
	var wbp := world_block_pos(origin_vox, local_bp)
	if wbp.y < 0:
		return true
	## Copying an area that is not resident yields AIR, and writing that back would carve
	## the very hole this pass exists to close.
	var area := block_voxel_aabb(origin_vox, local_bp)
	if not tool.is_area_editable(area):
		return false
	var buf := VoxelBuffer.new()
	buf.create(BLOCK, BLOCK, BLOCK)
	tool.copy(wbp * BLOCK, buf, 1 << VoxelBuffer.CHANNEL_TYPE)
	return terrain.try_set_block_data(wbp, buf)
