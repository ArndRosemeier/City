## Grounded flood-fill connectivity for structural collapse.
class_name VoxelConnectivity
extends RefCounted

const NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Full-world scan (small maps only).
static func find_unsupported_components(world: VoxelWorld, min_voxels: int = 2) -> Array:
	return _components_from_solids(world, world.get_all_solid_voxels(), min_voxels)


## Localized scan around a blast — required for large cities.
static func find_unsupported_near(
	world: VoxelWorld,
	center_world: Vector3,
	radius_m: float,
	min_voxels: int = 2
) -> Array:
	var vs := world.voxel_size
	var r := ceili(radius_m / vs) + 2
	var c := world.world_to_voxel(center_world)
	# Tall enough to cover a 30m building above the cut.
	var aabb_min := Vector3i(c.x - r, 0, c.z - r)
	var aabb_max := Vector3i(c.x + r + 1, c.y + ceili(32.0 / vs) + 4, c.z + r + 1)
	var solids := world.collect_solids_in_aabb(aabb_min, aabb_max)
	return _components_from_solids(world, solids, min_voxels)


static func _components_from_solids(world: VoxelWorld, solids: Array[Vector3i], min_voxels: int) -> Array:
	if solids.is_empty():
		return []

	var solid_set: Dictionary = {}
	for v in solids:
		solid_set[v] = true

	var grounded: Dictionary = {}
	var queue: Array[Vector3i] = []
	for v in solids:
		var mat := world.get_voxel(v)
		if v.y == 0 or mat == VoxelMaterial.BEDROCK:
			queue.append(v)
			grounded[v] = true

	var qi := 0
	while qi < queue.size():
		var cur: Vector3i = queue[qi]
		qi += 1
		for d in NEIGHBORS:
			var n: Vector3i = cur + d
			if grounded.has(n):
				continue
			if not solid_set.has(n):
				continue
			grounded[n] = true
			queue.append(n)

	var unsupported: Array[Vector3i] = []
	for v in solids:
		if grounded.has(v):
			continue
		if world.get_voxel(v) == VoxelMaterial.BEDROCK:
			continue
		# Ignore pavement that somehow floats — only detach building mats.
		var mat2 := world.get_voxel(v)
		if (
			mat2 == VoxelMaterial.ASPHALT
			or mat2 == VoxelMaterial.ROAD
			or mat2 == VoxelMaterial.SIDEWALK
			or mat2 == VoxelMaterial.PLAZA
			or mat2 == VoxelMaterial.PARK
			or mat2 == VoxelMaterial.GRAVEL
			or mat2 == VoxelMaterial.DIRT
			or mat2 == VoxelMaterial.TILES
			or mat2 == VoxelMaterial.CURB
			or mat2 == VoxelMaterial.ROAD_LINE
			or mat2 == VoxelMaterial.CROSSWALK
			or mat2 == VoxelMaterial.WATER
		):
			continue
		unsupported.append(v)

	if unsupported.is_empty():
		return []

	var visited: Dictionary = {}
	var components: Array = []
	for start in unsupported:
		if visited.has(start):
			continue
		var comp: Array[Vector3i] = []
		var q2: Array[Vector3i] = [start]
		visited[start] = true
		var qj := 0
		while qj < q2.size():
			var c: Vector3i = q2[qj]
			qj += 1
			comp.append(c)
			for d2 in NEIGHBORS:
				var n2: Vector3i = c + d2
				if visited.has(n2):
					continue
				if not solid_set.has(n2):
					continue
				if grounded.has(n2):
					continue
				visited[n2] = true
				q2.append(n2)
		if comp.size() >= min_voxels:
			components.append(comp)
	return components
