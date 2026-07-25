## Shared undirected navigation graph for road / sidewalk layers.
class_name NavGraph
extends RefCounted

var positions: PackedVector3Array = PackedVector3Array()
var neighbors: Array = []
var node_count: int = 0
var ground_y: float = 1.0
var voxel_size: float = 0.5
## component_id[i] = connected-component label (>=0).
var component_id: PackedInt32Array = PackedInt32Array()
var component_count: int = 0
var largest_component: int = -1
var largest_component_size: int = 0
var edge_count: int = 0
## Optional: node -> crossing_id (>=0) when this node sits on/near a marked crossing.
var node_crossing_id: PackedInt32Array = PackedInt32Array()


func clear() -> void:
	positions = PackedVector3Array()
	neighbors.clear()
	node_count = 0
	component_id = PackedInt32Array()
	component_count = 0
	largest_component = -1
	largest_component_size = 0
	edge_count = 0
	node_crossing_id = PackedInt32Array()


func is_empty() -> bool:
	return node_count <= 0


func add_node(world: Vector3) -> int:
	var idx := positions.size()
	positions.append(world)
	neighbors.append(PackedInt32Array())
	node_count = positions.size()
	return idx


func link(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= node_count or b >= node_count or a == b:
		return
	var na: PackedInt32Array = neighbors[a]
	for n in na:
		if n == b:
			return
	na.append(b)
	neighbors[a] = na
	var nb: PackedInt32Array = neighbors[b]
	nb.append(a)
	neighbors[b] = nb
	edge_count += 1


func finalize(vs: float) -> void:
	voxel_size = vs
	node_count = positions.size()
	if node_count == 0:
		return
	ground_y = positions[0].y
	node_crossing_id.resize(node_count)
	node_crossing_id.fill(-1)
	_compute_components()


func set_crossing_id(node: int, crossing_id: int) -> void:
	if node < 0 or node >= node_count:
		return
	if node_crossing_id.size() != node_count:
		node_crossing_id.resize(node_count)
		node_crossing_id.fill(-1)
	node_crossing_id[node] = crossing_id


func crossing_id_at(node: int) -> int:
	if node < 0 or node >= node_crossing_id.size():
		return -1
	return int(node_crossing_id[node])


func _compute_components() -> void:
	component_id.resize(node_count)
	component_id.fill(-1)
	component_count = 0
	largest_component = -1
	largest_component_size = 0
	for i in range(node_count):
		if component_id[i] >= 0:
			continue
		var label := component_count
		component_count += 1
		var stack: Array[int] = [i]
		component_id[i] = label
		var size := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			size += 1
			var nbrs: PackedInt32Array = neighbors[cur]
			for n in nbrs:
				if component_id[n] >= 0:
					continue
				component_id[n] = label
				stack.append(n)
		if size > largest_component_size:
			largest_component_size = size
			largest_component = label


func nearest_node(world: Vector3) -> int:
	if node_count == 0:
		return -1
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


func random_node_in_component(comp: int, rng: RandomNumberGenerator) -> int:
	if node_count == 0 or comp < 0:
		return -1
	for _attempt in range(48):
		var cand := rng.randi_range(0, node_count - 1)
		if component_id[cand] == comp:
			return cand
	for i in range(node_count):
		if component_id[i] == comp:
			return i
	return -1


func is_crossing_node(node: int) -> bool:
	return crossing_id_at(node) >= 0


func random_sidewalk_node_in_component(comp: int, rng: RandomNumberGenerator) -> int:
	## Prefer non-crossing (curb/sidewalk) nodes so agents don't spawn/idle on carriageways.
	if node_count == 0 or comp < 0:
		return -1
	for _attempt in range(64):
		var cand := rng.randi_range(0, node_count - 1)
		if component_id[cand] != comp:
			continue
		if is_crossing_node(cand):
			continue
		return cand
	# Fallback: any node in component (may be a crossing mid).
	return random_node_in_component(comp, rng)


func random_goal_node(
	from_node: int,
	min_m: float,
	max_m: float,
	rng: RandomNumberGenerator,
	prefer_sidewalk: bool = false
) -> int:
	if node_count == 0 or from_node < 0 or from_node >= node_count:
		return -1
	var comp := int(component_id[from_node])
	var from_pos := positions[from_node]
	for _attempt in range(64):
		var cand := rng.randi_range(0, node_count - 1)
		if cand == from_node:
			continue
		if int(component_id[cand]) != comp:
			continue
		if prefer_sidewalk and is_crossing_node(cand):
			continue
		var d := from_pos.distance_to(positions[cand])
		if d >= min_m and d <= max_m:
			return cand
	# Fallback: any other node in the same component (sidewalk first if requested).
	for _attempt2 in range(48):
		var cand2 := (
			random_sidewalk_node_in_component(comp, rng)
			if prefer_sidewalk
			else random_node_in_component(comp, rng)
		)
		if cand2 >= 0 and cand2 != from_node and (not prefer_sidewalk or not is_crossing_node(cand2)):
			return cand2
	for _attempt3 in range(32):
		var cand3 := random_node_in_component(comp, rng)
		if cand3 >= 0 and cand3 != from_node:
			return cand3
	return -1


func nearest_sidewalk_node(world: Vector3) -> int:
	## Nearest non-crossing node; falls back to nearest_node if none exist.
	if node_count == 0:
		return -1
	var best := -1
	var best_d := INF
	for i in range(node_count):
		if is_crossing_node(i):
			continue
		var d := positions[i].distance_squared_to(world)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	return nearest_node(world)


func path_length_m(path_nodes: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(path_nodes.size() - 1):
		total += positions[path_nodes[i]].distance_to(positions[path_nodes[i + 1]])
	return total


## Pick a goal whose BFS path length (meters along edges) is in [min_m, max_m].
## Optional avoid_first_hop blocks immediate U-turns when the previous trip ended.
func random_goal_by_path_length(
	from_node: int,
	min_m: float,
	max_m: float,
	rng: RandomNumberGenerator,
	avoid_first_hop: int = -1
) -> int:
	if node_count == 0 or from_node < 0 or from_node >= node_count:
		return -1
	var min_d := maxf(min_m, 0.0)
	var max_d := maxf(max_m, min_d + 1.0)
	var dist_m: PackedFloat32Array = PackedFloat32Array()
	dist_m.resize(node_count)
	dist_m.fill(-1.0)
	var first_hop: PackedInt32Array = PackedInt32Array()
	first_hop.resize(node_count)
	first_hop.fill(-1)
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(from_node)
	dist_m[from_node] = 0.0
	var head := 0
	var preferred: Array[int] = []
	var any_ok: Array[int] = []
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cur_d: float = dist_m[cur]
		if cur_d > max_d:
			continue
		if cur != from_node and cur_d >= min_d and cur_d <= max_d:
			any_ok.append(cur)
			if first_hop[cur] != avoid_first_hop:
				preferred.append(cur)
		if cur_d >= max_d:
			continue
		var nbrs: PackedInt32Array = neighbors[cur]
		for n in nbrs:
			if dist_m[n] >= 0.0:
				continue
			var edge := positions[cur].distance_to(positions[n])
			var nd := cur_d + edge
			if nd > max_d + 0.01:
				continue
			dist_m[n] = nd
			if cur == from_node:
				first_hop[n] = n
			else:
				first_hop[n] = first_hop[cur]
			queue.append(n)
	var pool: Array[int] = preferred if not preferred.is_empty() else any_ok
	if pool.is_empty():
		## Soften: any node reached beyond min_d (ignore max) preferring non-U-turn.
		var soft_pref: Array[int] = []
		var soft_any: Array[int] = []
		for i in range(node_count):
			if i == from_node or dist_m[i] < min_d:
				continue
			soft_any.append(i)
			if first_hop[i] != avoid_first_hop:
				soft_pref.append(i)
		pool = soft_pref if not soft_pref.is_empty() else soft_any
	if pool.is_empty():
		return -1
	return pool[rng.randi_range(0, pool.size() - 1)]


func find_path(from_node: int, to_node: int) -> PackedInt32Array:
	CityProfiler.begin("nav_find_path")
	var out := _find_path_inner(from_node, to_node)
	CityProfiler.end("nav_find_path")
	return out


func _find_path_inner(from_node: int, to_node: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if from_node < 0 or to_node < 0 or from_node >= node_count or to_node >= node_count:
		return out
	if from_node == to_node:
		out.append(from_node)
		return out
	if component_id.size() == node_count and component_id[from_node] != component_id[to_node]:
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


func largest_component_ratio() -> float:
	if node_count <= 0:
		return 0.0
	return float(largest_component_size) / float(node_count)
