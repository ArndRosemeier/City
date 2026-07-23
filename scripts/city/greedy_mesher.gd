## Greedy meshing + merged AABB collision boxes for a chunk.
class_name GreedyMesher
extends RefCounted

const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Returns { "mesh": ArrayMesh, "boxes": Array[{pos, size, material}] }
func build(chunk: VoxelChunk, world: VoxelWorld) -> Dictionary:
	var mesh := ArrayMesh.new()
	var boxes: Array = _build_collision_boxes(chunk, world)
	var vs := world.voxel_size
	var base := chunk.coord * VoxelChunk.SIZE

	# One opaque surface (vertex colors) + optional glass surface — same look, far less overhead.
	var opaque_v := PackedVector3Array()
	var opaque_n := PackedVector3Array()
	var opaque_c := PackedColorArray()
	var glass_v := PackedVector3Array()
	var glass_n := PackedVector3Array()

	for y in range(VoxelChunk.SIZE):
		for z in range(VoxelChunk.SIZE):
			for x in range(VoxelChunk.SIZE):
				var mat := chunk.get_voxel_fast(x, y, z)
				if mat == VoxelMaterial.AIR:
					continue
				var local := Vector3i(x, y, z)
				var world_v := base + local
				for d in _DIRS:
					if _neighbor_solid(chunk, world, world_v, local, d):
						continue
					if mat == VoxelMaterial.GLASS:
						_add_face(local, d, vs, glass_v, glass_n)
					else:
						_add_face_colored(local, d, vs, VoxelMaterial.color(mat), opaque_v, opaque_n, opaque_c)

	if not opaque_v.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = opaque_v
		arrays[Mesh.ARRAY_NORMAL] = opaque_n
		arrays[Mesh.ARRAY_COLOR] = opaque_c
		var surf := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surf, world.get_opaque_vertex_material())

	if not glass_v.is_empty():
		var garrays: Array = []
		garrays.resize(Mesh.ARRAY_MAX)
		garrays[Mesh.ARRAY_VERTEX] = glass_v
		garrays[Mesh.ARRAY_NORMAL] = glass_n
		var gsurf := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garrays)
		mesh.surface_set_material(gsurf, world.get_shared_material(VoxelMaterial.GLASS))

	return {"mesh": mesh, "boxes": boxes}


func _neighbor_solid(
	chunk: VoxelChunk,
	world: VoxelWorld,
	world_v: Vector3i,
	local: Vector3i,
	d: Vector3i
) -> bool:
	var nl := local + d
	if chunk.in_bounds(nl):
		return VoxelMaterial.is_solid(chunk.get_voxel_fast(nl.x, nl.y, nl.z))
	return VoxelMaterial.is_solid(world.get_voxel(world_v + d))


func _build_collision_boxes(chunk: VoxelChunk, world: VoxelWorld) -> Array:
	var vs := world.voxel_size
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(VoxelChunk.VOLUME)
	visited.fill(0)
	var boxes: Array = []

	for y in range(VoxelChunk.SIZE):
		for z in range(VoxelChunk.SIZE):
			for x in range(VoxelChunk.SIZE):
				var idx := x + z * VoxelChunk.SIZE + y * VoxelChunk.SIZE * VoxelChunk.SIZE
				if visited[idx]:
					continue
				var mat := chunk.get_voxel_fast(x, y, z)
				if not VoxelMaterial.is_solid(mat):
					continue
				var max_x := x
				while max_x + 1 < VoxelChunk.SIZE:
					var ni := (max_x + 1) + z * VoxelChunk.SIZE + y * VoxelChunk.SIZE * VoxelChunk.SIZE
					if visited[ni] or chunk.get_voxel_fast(max_x + 1, y, z) != mat:
						break
					max_x += 1
				var max_z := z
				var can_z := true
				while can_z and max_z + 1 < VoxelChunk.SIZE:
					for xx in range(x, max_x + 1):
						var ni2 := xx + (max_z + 1) * VoxelChunk.SIZE + y * VoxelChunk.SIZE * VoxelChunk.SIZE
						if visited[ni2] or chunk.get_voxel_fast(xx, y, max_z + 1) != mat:
							can_z = false
							break
					if can_z:
						max_z += 1
				var max_y := y
				var can_y := true
				while can_y and max_y + 1 < VoxelChunk.SIZE:
					for zz in range(z, max_z + 1):
						for xx in range(x, max_x + 1):
							var ni3 := xx + zz * VoxelChunk.SIZE + (max_y + 1) * VoxelChunk.SIZE * VoxelChunk.SIZE
							if visited[ni3] or chunk.get_voxel_fast(xx, max_y + 1, zz) != mat:
								can_y = false
								break
						if not can_y:
							break
					if can_y:
						max_y += 1
				for yy in range(y, max_y + 1):
					for zz in range(z, max_z + 1):
						for xx in range(x, max_x + 1):
							visited[xx + zz * VoxelChunk.SIZE + yy * VoxelChunk.SIZE * VoxelChunk.SIZE] = 1
				var size_vox := Vector3(float(max_x - x + 1), float(max_y - y + 1), float(max_z - z + 1))
				var pos_local := (
					Vector3(float(x) + size_vox.x * 0.5, float(y) + size_vox.y * 0.5, float(z) + size_vox.z * 0.5)
					* vs
				)
				boxes.append({
					"pos": pos_local,
					"size": size_vox * vs,
					"material": mat,
				})
	return boxes


func _add_face(
	local: Vector3i,
	dir: Vector3i,
	vs: float,
	verts: PackedVector3Array,
	norms: PackedVector3Array
) -> void:
	var o := Vector3(local) * vs
	var n := Vector3(dir)
	var c0: Vector3
	var c1: Vector3
	var c2: Vector3
	var c3: Vector3
	if dir.x == 1:
		c0 = o + Vector3(vs, 0, 0); c1 = o + Vector3(vs, vs, 0); c2 = o + Vector3(vs, vs, vs); c3 = o + Vector3(vs, 0, vs)
	elif dir.x == -1:
		c0 = o + Vector3(0, 0, vs); c1 = o + Vector3(0, vs, vs); c2 = o + Vector3(0, vs, 0); c3 = o + Vector3(0, 0, 0)
	elif dir.y == 1:
		c0 = o + Vector3(0, vs, 0); c1 = o + Vector3(0, vs, vs); c2 = o + Vector3(vs, vs, vs); c3 = o + Vector3(vs, vs, 0)
	elif dir.y == -1:
		c0 = o + Vector3(0, 0, 0); c1 = o + Vector3(vs, 0, 0); c2 = o + Vector3(vs, 0, vs); c3 = o + Vector3(0, 0, vs)
	elif dir.z == 1:
		c0 = o + Vector3(0, 0, vs); c1 = o + Vector3(vs, 0, vs); c2 = o + Vector3(vs, vs, vs); c3 = o + Vector3(0, vs, vs)
	else:
		c0 = o + Vector3(vs, 0, 0); c1 = o + Vector3(0, 0, 0); c2 = o + Vector3(0, vs, 0); c3 = o + Vector3(vs, vs, 0)
	verts.append(c0); norms.append(n)
	verts.append(c1); norms.append(n)
	verts.append(c2); norms.append(n)
	verts.append(c0); norms.append(n)
	verts.append(c2); norms.append(n)
	verts.append(c3); norms.append(n)


func _add_face_colored(
	local: Vector3i,
	dir: Vector3i,
	vs: float,
	color: Color,
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	cols: PackedColorArray
) -> void:
	var before := verts.size()
	_add_face(local, dir, vs, verts, norms)
	for _i in range(verts.size() - before):
		cols.append(color)


## Build collision boxes from an arbitrary set of world voxels (for rigid clusters).
static func boxes_from_voxels(voxels: Array[Vector3i], materials: Dictionary, voxel_size: float) -> Array:
	if voxels.is_empty():
		return []
	var set_map: Dictionary = {}
	for v in voxels:
		set_map[v] = true
	var visited: Dictionary = {}
	var boxes: Array = []
	var sorted := voxels.duplicate()
	sorted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x
	)
	for start: Vector3i in sorted:
		if visited.has(start):
			continue
		var mat: int = int(materials.get(start, VoxelMaterial.CONCRETE))
		var max_x := start.x
		while set_map.has(Vector3i(max_x + 1, start.y, start.z)) and not visited.has(Vector3i(max_x + 1, start.y, start.z)):
			if int(materials.get(Vector3i(max_x + 1, start.y, start.z), -1)) != mat:
				break
			max_x += 1
		var max_z := start.z
		var grow_z := true
		while grow_z:
			var nz := max_z + 1
			for xx in range(start.x, max_x + 1):
				var p := Vector3i(xx, start.y, nz)
				if not set_map.has(p) or visited.has(p) or int(materials.get(p, -1)) != mat:
					grow_z = false
					break
			if grow_z:
				max_z = nz
		var max_y := start.y
		var grow_y := true
		while grow_y:
			var ny := max_y + 1
			for zz in range(start.z, max_z + 1):
				for xx in range(start.x, max_x + 1):
					var p2 := Vector3i(xx, ny, zz)
					if not set_map.has(p2) or visited.has(p2) or int(materials.get(p2, -1)) != mat:
						grow_y = false
						break
				if not grow_y:
					break
			if grow_y:
				max_y = ny
		for yy in range(start.y, max_y + 1):
			for zz in range(start.z, max_z + 1):
				for xx in range(start.x, max_x + 1):
					visited[Vector3i(xx, yy, zz)] = true
		var size_vox := Vector3(float(max_x - start.x + 1), float(max_y - start.y + 1), float(max_z - start.z + 1))
		var min_w := Vector3(start) * voxel_size
		var size_w := size_vox * voxel_size
		var center := min_w + size_w * 0.5
		boxes.append({"pos": center, "size": size_w, "material": mat})
	return boxes
