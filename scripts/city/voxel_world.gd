## Sparse chunked voxel world in world-voxel coordinates.
class_name VoxelWorld
extends Node3D

signal chunks_remeshed

@export var voxel_size: float = 0.5

var _chunks: Dictionary = {}  # Vector3i -> VoxelChunk
var _chunk_nodes: Dictionary = {}  # Vector3i -> Node3D (mesh + static body)
var _mesher: GreedyMesher
var _materials: Array[StandardMaterial3D] = []
var _opaque_vert_mat: StandardMaterial3D
## When true, set_voxel skips neighbor dirty fan-out (use during city gen).
var bulk_edit: bool = false


func _ready() -> void:
	_mesher = GreedyMesher.new()
	_build_materials()


func _build_materials() -> void:
	_materials.clear()
	for id in range(VoxelMaterial.COUNT):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = VoxelMaterial.color(id)
		mat.roughness = 0.85
		if id == VoxelMaterial.GLASS:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.15
			mat.metallic = 0.2
		_materials.append(mat)


func clear() -> void:
	for key in _chunk_nodes.keys():
		var node: Node = _chunk_nodes[key]
		if is_instance_valid(node):
			node.free()
	_chunk_nodes.clear()
	_chunks.clear()


func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / voxel_size),
		floori(world_pos.y / voxel_size),
		floori(world_pos.z / voxel_size)
	)


func voxel_to_world_center(voxel: Vector3i) -> Vector3:
	return (Vector3(voxel) + Vector3(0.5, 0.5, 0.5)) * voxel_size


func voxel_to_chunk(voxel: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(voxel.x) / float(VoxelChunk.SIZE)),
		floori(float(voxel.y) / float(VoxelChunk.SIZE)),
		floori(float(voxel.z) / float(VoxelChunk.SIZE))
	)


func voxel_to_local(voxel: Vector3i) -> Vector3i:
	var c := voxel_to_chunk(voxel)
	return Vector3i(
		voxel.x - c.x * VoxelChunk.SIZE,
		voxel.y - c.y * VoxelChunk.SIZE,
		voxel.z - c.z * VoxelChunk.SIZE
	)


func get_voxel(voxel: Vector3i) -> int:
	var ccoord := voxel_to_chunk(voxel)
	if not _chunks.has(ccoord):
		return VoxelMaterial.AIR
	var chunk: VoxelChunk = _chunks[ccoord]
	return chunk.get_voxel(voxel_to_local(voxel))


func set_voxel(voxel: Vector3i, material_id: int) -> void:
	var ccoord := voxel_to_chunk(voxel)
	var chunk: VoxelChunk = _ensure_chunk(ccoord)
	chunk.set_voxel(voxel_to_local(voxel), material_id)
	if not bulk_edit:
		_mark_border_neighbors_dirty(voxel, ccoord)


func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	## Inclusive min, exclusive max — writes whole chunk slabs without per-voxel calls.
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	var c0 := voxel_to_chunk(min_v)
	var c1 := voxel_to_chunk(Vector3i(max_v.x - 1, max_v.y - 1, max_v.z - 1))
	for cy in range(c0.y, c1.y + 1):
		for cz in range(c0.z, c1.z + 1):
			for cx in range(c0.x, c1.x + 1):
				var ccoord := Vector3i(cx, cy, cz)
				var chunk := _ensure_chunk(ccoord)
				var base := ccoord * VoxelChunk.SIZE
				var local_min := Vector3i(
					maxi(min_v.x - base.x, 0),
					maxi(min_v.y - base.y, 0),
					maxi(min_v.z - base.z, 0)
				)
				var local_max := Vector3i(
					mini(max_v.x - base.x, VoxelChunk.SIZE),
					mini(max_v.y - base.y, VoxelChunk.SIZE),
					mini(max_v.z - base.z, VoxelChunk.SIZE)
				)
				chunk.fill_local_box(local_min, local_max, material_id)


func carve_sphere(center_world: Vector3, radius_m: float) -> Array[Vector3i]:
	## Returns list of voxel coords that were solid and became air.
	var removed: Array[Vector3i] = []
	var r_vox := ceili(radius_m / voxel_size) + 1
	var c := world_to_voxel(center_world)
	var r2 := radius_m * radius_m
	for y in range(c.y - r_vox, c.y + r_vox + 1):
		for z in range(c.z - r_vox, c.z + r_vox + 1):
			for x in range(c.x - r_vox, c.x + r_vox + 1):
				var v := Vector3i(x, y, z)
				var center := voxel_to_world_center(v)
				if center.distance_squared_to(center_world) > r2:
					continue
				if not _try_carve(v):
					continue
				removed.append(v)
	return removed


func carve_horizontal_disk(center_world: Vector3, radius_m: float, half_height_m: float = -1.0) -> Array[Vector3i]:
	## Flat cut used to sever hollow walls so upper structure can detach.
	var removed: Array[Vector3i] = []
	if half_height_m < 0.0:
		half_height_m = voxel_size * 1.1
	var r_vox := ceili(radius_m / voxel_size) + 1
	var h_vox := maxi(1, ceili(half_height_m / voxel_size))
	var c := world_to_voxel(center_world)
	var r2 := radius_m * radius_m
	for y in range(c.y - h_vox, c.y + h_vox + 1):
		for z in range(c.z - r_vox, c.z + r_vox + 1):
			for x in range(c.x - r_vox, c.x + r_vox + 1):
				var v := Vector3i(x, y, z)
				var center := voxel_to_world_center(v)
				var dx := center.x - center_world.x
				var dz := center.z - center_world.z
				if dx * dx + dz * dz > r2:
					continue
				if not _try_carve(v):
					continue
				removed.append(v)
	return removed


func _try_carve(v: Vector3i) -> bool:
	if not VoxelMaterial.is_solid(get_voxel(v)):
		return false
	if get_voxel(v) == VoxelMaterial.BEDROCK:
		return false
	set_voxel(v, VoxelMaterial.AIR)
	return true


func _ensure_chunk(ccoord: Vector3i) -> VoxelChunk:
	if _chunks.has(ccoord):
		return _chunks[ccoord]
	var chunk := VoxelChunk.new(ccoord)
	_chunks[ccoord] = chunk
	return chunk


func _mark_border_neighbors_dirty(voxel: Vector3i, ccoord: Vector3i) -> void:
	var local := voxel_to_local(voxel)
	if local.x == 0:
		_dirty_chunk(ccoord + Vector3i(-1, 0, 0))
	if local.x == VoxelChunk.SIZE - 1:
		_dirty_chunk(ccoord + Vector3i(1, 0, 0))
	if local.y == 0:
		_dirty_chunk(ccoord + Vector3i(0, -1, 0))
	if local.y == VoxelChunk.SIZE - 1:
		_dirty_chunk(ccoord + Vector3i(0, 1, 0))
	if local.z == 0:
		_dirty_chunk(ccoord + Vector3i(0, 0, -1))
	if local.z == VoxelChunk.SIZE - 1:
		_dirty_chunk(ccoord + Vector3i(0, 0, 1))


func _dirty_chunk(ccoord: Vector3i) -> void:
	if _chunks.has(ccoord):
		(_chunks[ccoord] as VoxelChunk).dirty = true


func get_all_solid_voxels() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for key in _chunks.keys():
		var chunk: VoxelChunk = _chunks[key]
		var base := chunk.coord * VoxelChunk.SIZE
		for y in range(VoxelChunk.SIZE):
			for z in range(VoxelChunk.SIZE):
				for x in range(VoxelChunk.SIZE):
					var local := Vector3i(x, y, z)
					if VoxelMaterial.is_solid(chunk.get_voxel(local)):
						out.append(base + local)
	return out


func collect_solids_in_aabb(aabb_min: Vector3i, aabb_max: Vector3i) -> Array[Vector3i]:
	## Inclusive min, exclusive max.
	var out: Array[Vector3i] = []
	var cmin := voxel_to_chunk(aabb_min)
	var cmax := voxel_to_chunk(aabb_max - Vector3i(1, 1, 1))
	for cy in range(cmin.y, cmax.y + 1):
		for cz in range(cmin.z, cmax.z + 1):
			for cx in range(cmin.x, cmax.x + 1):
				var ccoord := Vector3i(cx, cy, cz)
				if not _chunks.has(ccoord):
					continue
				var chunk: VoxelChunk = _chunks[ccoord]
				var base := ccoord * VoxelChunk.SIZE
				for y in range(VoxelChunk.SIZE):
					var wy := base.y + y
					if wy < aabb_min.y or wy >= aabb_max.y:
						continue
					for z in range(VoxelChunk.SIZE):
						var wz := base.z + z
						if wz < aabb_min.z or wz >= aabb_max.z:
							continue
						for x in range(VoxelChunk.SIZE):
							var wx := base.x + x
							if wx < aabb_min.x or wx >= aabb_max.x:
								continue
							if VoxelMaterial.is_solid(chunk.get_voxel(Vector3i(x, y, z))):
								out.append(Vector3i(wx, wy, wz))
	return out


func remesh_dirty() -> void:
	for key in _chunks.keys():
		var chunk: VoxelChunk = _chunks[key]
		if not chunk.dirty:
			continue
		_remesh_chunk(chunk)
		chunk.dirty = false
	chunks_remeshed.emit()


## Remesh a limited number of dirty chunks; returns remaining dirty count.
func remesh_dirty_budget(max_chunks: int) -> int:
	var done := 0
	for key in _chunks.keys():
		var chunk: VoxelChunk = _chunks[key]
		if not chunk.dirty:
			continue
		if done >= max_chunks:
			break
		_remesh_chunk(chunk)
		chunk.dirty = false
		done += 1
	var remaining := 0
	for key2 in _chunks.keys():
		if (_chunks[key2] as VoxelChunk).dirty:
			remaining += 1
	if remaining == 0:
		chunks_remeshed.emit()
	return remaining


func mark_all_dirty() -> void:
	for key in _chunks.keys():
		(_chunks[key] as VoxelChunk).dirty = true


func count_dirty_chunks() -> int:
	var n := 0
	for key in _chunks.keys():
		if (_chunks[key] as VoxelChunk).dirty:
			n += 1
	return n


func remesh_all() -> void:
	for key in _chunks.keys():
		(_chunks[key] as VoxelChunk).dirty = true
	remesh_dirty()


func _remesh_chunk(chunk: VoxelChunk) -> void:
	var ccoord := chunk.coord
	if _chunk_nodes.has(ccoord):
		var old: Node = _chunk_nodes[ccoord]
		if is_instance_valid(old):
			old.free()
		_chunk_nodes.erase(ccoord)

	if chunk.is_empty():
		return

	var result: Dictionary = _mesher.build(chunk, self)
	var mesh: ArrayMesh = result["mesh"]
	var boxes: Array = result["boxes"]  # Array of {pos: Vector3, size: Vector3, material: int}

	var root := Node3D.new()
	root.name = "Chunk_%d_%d_%d" % [ccoord.x, ccoord.y, ccoord.z]
	root.position = Vector3(ccoord) * float(VoxelChunk.SIZE) * voxel_size
	add_child(root)
	_chunk_nodes[ccoord] = root

	if mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		root.add_child(mi)

	if boxes.size() > 0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		for box in boxes:
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = box["size"]
			shape.shape = box_shape
			shape.position = box["pos"]
			body.add_child(shape)


func get_shared_material(mat_id: int) -> StandardMaterial3D:
	if mat_id < 0 or mat_id >= _materials.size():
		return _materials[VoxelMaterial.CONCRETE]
	return _materials[mat_id]


func get_opaque_vertex_material() -> StandardMaterial3D:
	if _opaque_vert_mat == null:
		_opaque_vert_mat = StandardMaterial3D.new()
		_opaque_vert_mat.vertex_color_use_as_albedo = true
		_opaque_vert_mat.roughness = 0.85
	return _opaque_vert_mat


func sample_neighbor(world_voxel: Vector3i) -> int:
	return get_voxel(world_voxel)
