## Walkable roadmap for pedestrians: asphalt / plaza / sidewalk / park paths / markings.
## Agents follow node paths — no building collision queries needed.
class_name PedRoadMap
extends RefCounted

var positions: PackedVector3Array = PackedVector3Array()
## neighbors[i] = PackedInt32Array of adjacent node indices.
var neighbors: Array = []
var node_count: int = 0
var ground_y: float = 1.0
var stride_vox: int = 2
var voxel_size: float = 0.5

var _cell_to_node: Dictionary = {}  # Vector2i(x_vox, z_vox) -> node index


func is_empty() -> bool:
	return node_count <= 0


func build_from_district(
	tool: VoxelTool,
	size_xz: int,
	ground_thickness: int,
	vs: float,
	stride: int = 2
) -> void:
	positions = PackedVector3Array()
	neighbors.clear()
	_cell_to_node.clear()
	node_count = 0
	voxel_size = vs
	stride_vox = maxi(stride, 1)
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var y := ground_thickness
	var step := stride_vox

	for z in range(1, size_xz - 1, step):
		for x in range(1, size_xz - 1, step):
			if not _is_walkable_cell(tool, x, y, z):
				continue
			var idx := positions.size()
			_cell_to_node[Vector2i(x, z)] = idx
			positions.append(Vector3((float(x) + 0.5) * vs, float(y + 1) * vs, (float(z) + 0.5) * vs))
			neighbors.append(PackedInt32Array())

	node_count = positions.size()
	if node_count == 0:
		return
	ground_y = positions[0].y

	# 4-connected links on the stride grid.
	var offsets: Array[Vector2i] = [
		Vector2i(step, 0),
		Vector2i(-step, 0),
		Vector2i(0, step),
		Vector2i(0, -step),
	]
	for cell: Variant in _cell_to_node.keys():
		var c: Vector2i = cell
		var a: int = int(_cell_to_node[c])
		for off in offsets:
			var nkey := c + off
			if not _cell_to_node.has(nkey):
				continue
			var b: int = int(_cell_to_node[nkey])
			if a < b:
				var na: PackedInt32Array = neighbors[a]
				na.append(b)
				neighbors[a] = na
				var nb: PackedInt32Array = neighbors[b]
				nb.append(a)
				neighbors[b] = nb


func _is_walkable_cell(tool: VoxelTool, x: int, y: int, z: int) -> bool:
	var mat := tool.get_voxel(Vector3i(x, y, z))
	if not VoxelMaterial.is_walkable_surface(mat):
		return false
	if tool.get_voxel(Vector3i(x, y + 1, z)) != VoxelMaterial.AIR:
		return false
	if tool.get_voxel(Vector3i(x, y + 2, z)) != VoxelMaterial.AIR:
		return false
	return true


func nearest_node(world: Vector3) -> int:
	if node_count == 0:
		return -1
	# Snap to stride grid first for O(1), then fall back to search.
	var gx := int(floor(world.x / voxel_size))
	var gz := int(floor(world.z / voxel_size))
	gx = (gx / stride_vox) * stride_vox
	gz = (gz / stride_vox) * stride_vox
	for radius in range(0, 8):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius and radius > 0:
					continue
				var key := Vector2i(gx + dx * stride_vox, gz + dz * stride_vox)
				if _cell_to_node.has(key):
					return int(_cell_to_node[key])
	# Brute fallback (rare).
	var best := 0
	var best_d := INF
	for i in range(node_count):
		var d := positions[i].distance_squared_to(world)
		if d < best_d:
			best_d = d
			best = i
	return best


func random_node(rng: RandomNumberGenerator) -> int:
	if node_count == 0:
		return -1
	return rng.randi_range(0, node_count - 1)


func random_goal_node(from_node: int, min_m: float, max_m: float, rng: RandomNumberGenerator) -> int:
	if node_count == 0 or from_node < 0:
		return -1
	var from_pos := positions[from_node]
	for _attempt in range(24):
		var cand := rng.randi_range(0, node_count - 1)
		if cand == from_node:
			continue
		var d := from_pos.distance_to(positions[cand])
		if d >= min_m and d <= max_m:
			return cand
	return random_node(rng)


## BFS shortest path on the roadmap. Returns node indices including start and goal.
func find_path(from_node: int, to_node: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if from_node < 0 or to_node < 0 or from_node >= node_count or to_node >= node_count:
		return out
	if from_node == to_node:
		out.append(from_node)
		return out

	var came_from: PackedInt32Array = PackedInt32Array()
	came_from.resize(node_count)
	came_from.fill(-1)
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(node_count)
	visited.fill(0)

	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(from_node)
	visited[from_node] = 1
	var head := 0
	var found := false
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == to_node:
			found = true
			break
		var nbrs: PackedInt32Array = neighbors[cur]
		for n in nbrs:
			if visited[n] != 0:
				continue
			visited[n] = 1
			came_from[n] = cur
			queue.append(n)

	if not found:
		return out

	var stack: Array[int] = []
	var walk := to_node
	while walk != from_node:
		stack.append(walk)
		walk = came_from[walk]
		if walk < 0:
			return PackedInt32Array()
	stack.append(from_node)
	stack.reverse()
	for id in stack:
		out.append(id)
	return out


func path_to_world(path_nodes: PackedInt32Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(path_nodes.size())
	for i in range(path_nodes.size()):
		pts[i] = positions[path_nodes[i]]
	return pts
