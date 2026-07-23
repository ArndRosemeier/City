## Sparse 16³ block volume for thread-safe district baking (no VoxelTool / scene access).
class_name OfflineVoxelVolume
extends RefCounted

const BLOCK := 16
const BLOCK_VOXELS := BLOCK * BLOCK * BLOCK

## Local district block coords → dense TYPE channel bytes (AIR=0).
var _blocks: Dictionary = {}  # Vector3i -> PackedByteArray


func clear() -> void:
	_blocks.clear()


func block_count() -> int:
	return _blocks.size()


func block_positions() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for k: Variant in _blocks.keys():
		out.append(k as Vector3i)
	return out


func export_blocks() -> Dictionary:
	## Shallow copy of block map for hand-off to the main thread.
	var out := {}
	for k: Variant in _blocks.keys():
		out[k] = (_blocks[k] as PackedByteArray).duplicate()
	return out


func export_blocks_u16() -> Dictionary:
	## Expand 8-bit materials → little-endian uint16 for VoxelTerrain TYPE channel.
	## Uniform blocks are stored as a 2-byte sentinel [value, 0] so main can buf.fill().
	## Runs on the bake worker so the main thread only memcpy's / fills.
	var out := {}
	for k: Variant in _blocks.keys():
		var src: PackedByteArray = _blocks[k]
		var n := mini(src.size(), BLOCK_VOXELS)
		var v0 := 0
		var uniform := n > 0
		if uniform:
			v0 = int(src[0])
			for i in range(1, n):
				if int(src[i]) != v0:
					uniform = false
					break
		if uniform:
			var tiny := PackedByteArray()
			tiny.resize(2)
			tiny[0] = v0
			tiny[1] = 0
			out[k] = tiny
			continue
		var dst := PackedByteArray()
		dst.resize(BLOCK_VOXELS * 2)
		dst.fill(0)
		for i2 in range(n):
			dst[i2 * 2] = src[i2]
		out[k] = dst
	return out


func set_vox(pos: Vector3i, material_id: int) -> void:
	if material_id < 0:
		material_id = 0
	if material_id > 255:
		material_id = 255
	var bp := _block_pos(pos)
	var data := _ensure_block(bp)
	var lp := pos - bp * BLOCK
	data[_index(lp)] = material_id


func get_vox(pos: Vector3i) -> int:
	var bp := _block_pos(pos)
	if not _blocks.has(bp):
		return 0
	var data: PackedByteArray = _blocks[bp]
	var lp := pos - bp * BLOCK
	return int(data[_index(lp)])


func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	## Inclusive min, exclusive max (local district voxel space).
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	if material_id < 0:
		material_id = 0
	if material_id > 255:
		material_id = 255
	## Walk by blocks for fewer dictionary lookups.
	var bx0 := int(floor(float(min_v.x) / float(BLOCK)))
	var by0 := int(floor(float(min_v.y) / float(BLOCK)))
	var bz0 := int(floor(float(min_v.z) / float(BLOCK)))
	var bx1 := int(floor(float(max_v.x - 1) / float(BLOCK)))
	var by1 := int(floor(float(max_v.y - 1) / float(BLOCK)))
	var bz1 := int(floor(float(max_v.z - 1) / float(BLOCK)))
	for bz in range(bz0, bz1 + 1):
		for by in range(by0, by1 + 1):
			for bx in range(bx0, bx1 + 1):
				var bp := Vector3i(bx, by, bz)
				var bmin := bp * BLOCK
				var bmax := bmin + Vector3i(BLOCK, BLOCK, BLOCK)
				var x0 := maxi(min_v.x, bmin.x)
				var y0 := maxi(min_v.y, bmin.y)
				var z0 := maxi(min_v.z, bmin.z)
				var x1 := mini(max_v.x, bmax.x)
				var y1 := mini(max_v.y, bmax.y)
				var z1 := mini(max_v.z, bmax.z)
				if x0 >= x1 or y0 >= y1 or z0 >= z1:
					continue
				## Whole block fill fast-path.
				if x0 == bmin.x and y0 == bmin.y and z0 == bmin.z and x1 == bmax.x and y1 == bmax.y and z1 == bmax.z:
					var full := _ensure_block(bp)
					full.fill(material_id)
					continue
				var data := _ensure_block(bp)
				for z in range(z0, z1):
					for y in range(y0, y1):
						for x in range(x0, x1):
							var lp := Vector3i(x, y, z) - bmin
							data[_index(lp)] = material_id


static func _block_pos(pos: Vector3i) -> Vector3i:
	return Vector3i(
		int(floor(float(pos.x) / float(BLOCK))),
		int(floor(float(pos.y) / float(BLOCK))),
		int(floor(float(pos.z) / float(BLOCK)))
	)


static func _index(lp: Vector3i) -> int:
	## Matches VoxelBuffer CHANNEL_TYPE raw layout: Y innermost, then X, then Z.
	return lp.y + lp.x * BLOCK + lp.z * BLOCK * BLOCK


func _ensure_block(bp: Vector3i) -> PackedByteArray:
	if _blocks.has(bp):
		return _blocks[bp]
	var data := PackedByteArray()
	data.resize(BLOCK_VOXELS)
	data.fill(0)
	_blocks[bp] = data
	return data
