## Shared voxel line-of-sight / projectile occlusion.
##
## Only solid voxels count — agents (player, peds, mobs) are ignored here so packs can
## shoot past each other. CityRoot owns the terrain tool; callers use the wrappers there.
##
## Callers may pass either world metres or terrain-local voxel units as endpoints — the
## march is unit-agnostic. When CityRoot marches in `VoxelTerrain.to_local` space it must
## convert the returned distance back to world metres via `local_distance_to_world`
## (terrain scale is VOXEL_SIZE; local length ≠ world length).
class_name ProjectileLos
extends RefCounted

## March step in the same units as the endpoints (~0.2 voxel when marching in local space).
const STEP_M := 0.2


## Map a hit distance from terrain-local units onto the world segment length.
## `local_dist` / `local_from` / `local_to` use VoxelTerrain.to_local space; `world_len` is
## metres. Clamped to the world segment.
static func local_distance_to_world(
	local_dist: float, local_from: Vector3, local_to: Vector3, world_len: float
) -> float:
	if world_len <= 0.0:
		return 0.0
	var local_len := local_from.distance_to(local_to)
	if local_len <= 0.0001:
		return 0.0
	return clampf(world_len * (local_dist / local_len), 0.0, world_len)


## First solid voxel along a ray. `get_voxel` is Callable(Vector3i) -> int.
## Returns {} or {point, normal, distance, voxel_id}. `distance` is in the same units as
## the endpoints (local voxels when CityRoot passes to_local points).
static func probe_solid_ray(
	from_world: Vector3,
	to_world: Vector3,
	get_voxel: Callable,
	voxel_size: float = 0.5
) -> Dictionary:
	if not get_voxel.is_valid():
		return {}
	var delta := to_world - from_world
	var dist := delta.length()
	if dist < 0.05:
		return {}
	var dir := delta / dist
	var steps := int(ceil(dist / STEP_M)) + 1
	var prev := Vector3i(2147483647, 2147483647, 2147483647)
	## Sample in a local frame that matches VoxelTerrain.to_local when callers pass local
	## endpoints; CityRoot converts before calling.
	for i in range(1, steps + 1):
		var p := from_world + dir * (float(i) * STEP_M)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if v == prev:
			continue
		prev = v
		var id := int(get_voxel.call(v))
		if not VoxelMaterial.is_solid(id):
			continue
		## Pull the hit slightly toward the entry face; `voxel_size` is in endpoint units
		## (pass ~1.0 when marching in voxel-local space, or VOXEL_SIZE in world metres).
		var hit_t := clampf(
			float(i) * STEP_M - voxel_size * 0.2, 0.0, dist
		)
		return {
			"point": from_world + dir * hit_t,
			"normal": -dir,
			"distance": hit_t,
			"voxel_id": id,
		}
	return {}


## True when no solid voxel lies strictly between the endpoints.
static func has_line_of_sight(
	from_world: Vector3,
	to_world: Vector3,
	get_voxel: Callable,
	voxel_size: float = 0.5
) -> bool:
	var hit := probe_solid_ray(from_world, to_world, get_voxel, voxel_size)
	if hit.is_empty():
		return true
	## Allow grazing the destination cell (standing inside a column).
	var dist := from_world.distance_to(to_world)
	return float(hit["distance"]) + voxel_size * 0.6 >= dist
