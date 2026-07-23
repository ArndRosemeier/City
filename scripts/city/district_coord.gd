## World district grid helpers (one tile = one procedural city block).
class_name DistrictCoord
extends RefCounted

## Planner cells per district (matches legacy 784×560 @ cell_size 28).
const CELLS_X := 28
const CELLS_Z := 20
const CELL_SIZE := 28
const SIZE_X_VOX := CELLS_X * CELL_SIZE  # 784
const SIZE_Z_VOX := CELLS_Z * CELL_SIZE  # 560


static func size_vox() -> Vector3i:
	return Vector3i(SIZE_X_VOX, 0, SIZE_Z_VOX)


static func origin_vox(coord: Vector2i) -> Vector3i:
	return Vector3i(coord.x * SIZE_X_VOX, 0, coord.y * SIZE_Z_VOX)


static func origin_world(coord: Vector2i, voxel_size: float) -> Vector3:
	var o := origin_vox(coord)
	return Vector3(float(o.x) * voxel_size, 0.0, float(o.z) * voxel_size)


static func center_world(coord: Vector2i, voxel_size: float) -> Vector3:
	var o := origin_world(coord, voxel_size)
	return o + Vector3(
		float(SIZE_X_VOX) * 0.5 * voxel_size,
		0.0,
		float(SIZE_Z_VOX) * 0.5 * voxel_size
	)


static func from_world(pos: Vector3, voxel_size: float) -> Vector2i:
	var vx := int(floor(pos.x / voxel_size))
	var vz := int(floor(pos.z / voxel_size))
	return Vector2i(
		int(floor(float(vx) / float(SIZE_X_VOX))),
		int(floor(float(vz) / float(SIZE_Z_VOX)))
	)


static func district_seed(world_seed: int, coord: Vector2i) -> int:
	## Stable per-tile seed from world seed + district grid coordinates.
	## Independent of load order / approach direction.
	return _mix3(world_seed, coord.x, coord.y)


static func cell_seed(district_seed_value: int, cx: int, cz: int) -> int:
	## Stable per-planner-cell seed (buildings, street detail).
	## `district_seed_value` must already be district_seed(world, coord).
	return _mix3(district_seed_value, cx, cz)


static func feature_seed(district_seed_value: int, feature_id: int) -> int:
	## Stable seed for multi-cell features (plazas, parks).
	return _mix3(district_seed_value, feature_id, 0xF17E)


static func _mix3(a: int, b: int, c: int) -> int:
	## Small deterministic 3-int mix → positive 31-bit seed.
	var h := int(a)
	h = (h ^ int(b) * 0x45d9f3b) & 0x7fffffff
	h = (h * 16777619 + 2246822519) & 0x7fffffff
	h = (h ^ int(c) * 0x27d4eb2d) & 0x7fffffff
	h = (h * 2246822519 + 3266489917) & 0x7fffffff
	h = (h ^ (h >> 15)) & 0x7fffffff
	return maxi(h, 1)


static func aabb_vox(coord: Vector2i, height_vox: int) -> AABB:
	var o := origin_vox(coord)
	return AABB(
		Vector3(float(o.x), 0.0, float(o.z)),
		Vector3(float(SIZE_X_VOX), float(height_vox), float(SIZE_Z_VOX))
	)
