## The pavement half of a district's street topology: kerb pads, the crossings between them,
## and who is standing on a crossing right now.
##
## This is an annotation layer, not a navigation graph. Nobody walks these edges — the span
## field routes, and `PedGoalProvider` reads this only to choose where an errand starts and
## ends and which crossings lie on the way, because A* legitimately jaywalks a wide
## carriageway on cost alone. Cars read the crossings to yield.
##
## Heights are nominal. A node position is the planner's idea of where a pad is, and the
## consumer snaps it onto a real span through `NavService.nearest_surface`; every distance
## question here is therefore answered in XZ, so a pad on a hill is still the nearest pad.
class_name SidewalkMap
extends RefCounted

## Kerb pad sides of a road cell.
const SIDE_N := 0
const SIDE_S := 1
const SIDE_E := 2
const SIDE_W := 3

## How wide a crossing counts as occupied, in metres. Tight, and on the carriageway mid only:
## a ped waiting on the kerb must not stop the traffic it is waiting for.
const CROSSING_RADIUS_M := 1.6
## Extra metres in front of an occupied crossing where a car has to have stopped.
const YIELD_APPROACH_M := 2.25
## Occupancy lookup grid, in metres.
const OCCUPANCY_CELL_M := 4.0

## One painted crossing: the kerb pads it joins, the carriageway node between them, and the
## disc that decides whether a car has to wait. Two pads on a straight street, four at a
## crossroads, which is one place in the middle of the junction and not one per axis.
class Crossing:
	extends RefCounted
	var id: int = -1
	var center: Vector3 = Vector3.ZERO
	var radius: float = CROSSING_RADIUS_M
	## The road cell the crossing is painted on.
	var road_cell: Vector2i = Vector2i.ZERO
	## Kerb pads a ped can step onto the crossing from.
	var kerbs: PackedInt32Array = PackedInt32Array()
	## The carriageway node itself: the only pavement node in the road, and standing on it is
	## what makes a car wait.
	var mid_node: int = -1

var positions: PackedVector3Array = PackedVector3Array()
var node_count: int = 0
var edge_count: int = 0
var crossings: Array[Crossing] = []

var _neighbors: Array[PackedInt32Array] = []
## node -> crossing id, or -1 for an ordinary kerb pad.
var _node_crossing: PackedInt32Array = PackedInt32Array()
var _component: PackedInt32Array = PackedInt32Array()
var _component_count: int = 0
var _largest_component: int = -1
var _largest_size: int = 0
## Kerb pads only, for spawning and for errand endpoints.
var _pavement_nodes: PackedInt32Array = PackedInt32Array()

var _cell_size: int = 28
var _voxel_size: float = 0.5
var _origin_vox: Vector3i = Vector3i.ZERO
var _nominal_y: float = 3.5

## Live occupancy: crossing id -> peds standing on it.
var _occupancy: Dictionary[int, int] = {}
var _occupied: PackedInt32Array = PackedInt32Array()
## Grid cell -> crossing ids whose disc touches it.
var _occupancy_grid: Dictionary[Vector2i, PackedInt32Array] = {}


func is_empty() -> bool:
	return node_count <= 0


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Walk the planner's road cells and lay out the pavement around them. No voxels are read:
## the span field owns heights, and `nominal_y` only has to be close enough that a consumer's
## `nearest_surface` finds the right column.
func build(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	origin_vox: Vector3i,
	nominal_y: float
) -> void:
	_cell_size = cell_size
	_voxel_size = voxel_size
	_origin_vox = origin_vox
	_nominal_y = nominal_y
	positions = PackedVector3Array()
	_neighbors = []
	node_count = 0
	edge_count = 0
	crossings.clear()
	_occupancy.clear()
	_occupied = PackedInt32Array()
	_occupancy_grid.clear()
	if planner == null:
		push_error("SidewalkMap.build: no planner")
		return

	## Vector3i(cx, cz, side) -> node.
	var pads: Dictionary[Vector3i, int] = {}
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not planner.has_road_cell(cx, cz):
				continue
			for side in _pad_sides(planner, cx, cz):
				_add_pad(pads, cx, cz, side)
	_link_runs(planner, pads)
	_link_corners(planner, pads)
	_add_crossings(planner, pads)
	finalize()


## Which kerb pads a road cell carries. An intersection gets all four corners; a straight run
## gets only the two pavements that flank it.
func _pad_sides(planner: DistrictPlanner, cx: int, cz: int) -> Array[int]:
	var horiz := planner.has_road_cell(cx - 1, cz) or planner.has_road_cell(cx + 1, cz)
	var vert := planner.has_road_cell(cx, cz - 1) or planner.has_road_cell(cx, cz + 1)
	if horiz and vert:
		return [SIDE_N, SIDE_S, SIDE_E, SIDE_W]
	if horiz:
		return [SIDE_N, SIDE_S]
	return [SIDE_E, SIDE_W]


func _add_pad(pads: Dictionary[Vector3i, int], cx: int, cz: int, side: int) -> int:
	var key := Vector3i(cx, cz, side)
	if pads.has(key):
		return pads[key]
	var node := add_pad(_pad_world(cx, cz, side))
	pads[key] = node
	return node


## Pavement runs along a street, so a ped can walk a block without crossing anything.
func _link_pads(pads: Dictionary[Vector3i, int], a: Vector3i, b: Vector3i) -> void:
	if not pads.has(a) or not pads.has(b):
		return
	link(pads[a], pads[b])


func _link_runs(planner: DistrictPlanner, pads: Dictionary[Vector3i, int]) -> void:
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not planner.has_road_cell(cx, cz):
				continue
			if planner.has_road_cell(cx + 1, cz):
				_link_pads(pads, Vector3i(cx, cz, SIDE_N), Vector3i(cx + 1, cz, SIDE_N))
				_link_pads(pads, Vector3i(cx, cz, SIDE_S), Vector3i(cx + 1, cz, SIDE_S))
			if planner.has_road_cell(cx, cz + 1):
				_link_pads(pads, Vector3i(cx, cz, SIDE_E), Vector3i(cx, cz + 1, SIDE_E))
				_link_pads(pads, Vector3i(cx, cz, SIDE_W), Vector3i(cx, cz + 1, SIDE_W))


## Round an intersection, so a ped can turn the corner without stepping into the road.
func _link_corners(planner: DistrictPlanner, pads: Dictionary[Vector3i, int]) -> void:
	var ring: Array[int] = [SIDE_N, SIDE_E, SIDE_S, SIDE_W]
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not planner.has_road_cell(cx, cz):
				continue
			if _pad_sides(planner, cx, cz).size() < 4:
				continue
			for i in range(ring.size()):
				_link_pads(
					pads,
					Vector3i(cx, cz, ring[i]),
					Vector3i(cx, cz, ring[(i + 1) % ring.size()])
				)


## A crossing at every intersection, plus sparse mid-block ones so a long straight is not a
## wall between the two pavements.
##
## An intersection gets exactly one, in the middle, joining all four kerbs. One per axis would
## put two crossings on the same point: a duplicate pavement node nobody walks, and one waiting
## pedestrian counted twice against the traffic.
func _add_crossings(planner: DistrictPlanner, pads: Dictionary[Vector3i, int]) -> void:
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not planner.has_road_cell(cx, cz):
				continue
			var sides := _pad_sides(planner, cx, cz)
			if sides.size() < 4 and not _has_midblock_crossing(cx, cz):
				continue
			_make_crossing(pads, cx, cz, sides)


func _make_crossing(
	pads: Dictionary[Vector3i, int], cx: int, cz: int, sides: Array[int]
) -> void:
	var kerbs := PackedInt32Array()
	for side in sides:
		var key := Vector3i(cx, cz, side)
		if pads.has(key):
			kerbs.append(pads[key])
	if kerbs.size() < 2:
		return
	add_crossing(kerbs, Vector2i(cx, cz))


## Sparse mid-block crossings, matching what the generator paints.
func _has_midblock_crossing(cx: int, cz: int) -> bool:
	return ((cx * 17 + cz * 31) % 7) == 0


## Close the pavement: index the crossings, work out what is connected to what. Must be called
## once every pad and crossing is in.
func finalize() -> void:
	node_count = positions.size()
	_node_crossing.resize(node_count)
	_node_crossing.fill(-1)
	for crossing in crossings:
		_node_crossing[crossing.mid_node] = crossing.id
	_pavement_nodes = PackedInt32Array()
	for node in range(node_count):
		if _node_crossing[node] < 0:
			_pavement_nodes.append(node)
	_compute_components()
	_rebuild_occupancy_grid()


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## Centre of the ~2 m pavement band on one side of a road cell.
func _pad_world(cx: int, cz: int, side: int) -> Vector3:
	var ox := float(_origin_vox.x + cx * _cell_size)
	var oz := float(_origin_vox.z + cz * _cell_size)
	var band := float(_sidewalk_vox())
	var x_vox := ox + float(_cell_size) * 0.5
	var z_vox := oz + float(_cell_size) * 0.5
	match side:
		SIDE_N:
			z_vox = oz + band * 0.5
		SIDE_S:
			z_vox = oz + float(_cell_size) - band * 0.5
		SIDE_E:
			x_vox = ox + float(_cell_size) - band * 0.5
		SIDE_W:
			x_vox = ox + band * 0.5
		_:
			push_error("SidewalkMap: unknown side %d" % side)
	return Vector3(x_vox * _voxel_size, _nominal_y, z_vox * _voxel_size)


## Pavement width in voxels, matching what the street painter lays down.
func _sidewalk_vox() -> int:
	return clampi(int(round(2.0 / _voxel_size)), 3, maxi(3, _cell_size / 6))


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------

## Add one kerb pad. Public so a test can lay a stated pavement instead of deriving one from a
## planner it would have to fabricate.
func add_pad(world: Vector3) -> int:
	var node := positions.size()
	positions.append(world)
	_neighbors.append(PackedInt32Array())
	return node


## Join two kerb pads with a stretch of pavement.
func link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	var na := _neighbors[a]
	if na.has(b):
		return
	na.append(b)
	_neighbors[a] = na
	var nb := _neighbors[b]
	nb.append(a)
	_neighbors[b] = nb
	edge_count += 1


## Paint a crossing joining kerb pads across a carriageway: two facing each other on a
## straight street, four at a crossroads. The carriageway node is created here, at their
## average, and it is the crossing as far as everything downstream is concerned.
func add_crossing(kerbs: PackedInt32Array, road_cell: Vector2i) -> int:
	if kerbs.size() < 2:
		push_error("SidewalkMap.add_crossing: %d kerb pads is not a crossing" % kerbs.size())
		return -1
	var center := Vector3.ZERO
	for kerb in kerbs:
		if kerb < 0 or kerb >= positions.size():
			push_error("SidewalkMap.add_crossing: %d is not a kerb pad" % kerb)
			return -1
		center += positions[kerb]
	var mid := add_pad(center / float(kerbs.size()))
	for kerb in kerbs:
		link(kerb, mid)
	var crossing := Crossing.new()
	crossing.id = crossings.size()
	crossing.center = positions[mid]
	crossing.radius = CROSSING_RADIUS_M
	crossing.road_cell = road_cell
	crossing.kerbs = kerbs
	crossing.mid_node = mid
	crossings.append(crossing)
	_occupancy[crossing.id] = 0
	return crossing.id


func _compute_components() -> void:
	_component.resize(node_count)
	_component.fill(-1)
	_component_count = 0
	_largest_component = -1
	_largest_size = 0
	for start in range(node_count):
		if _component[start] >= 0:
			continue
		var label := _component_count
		_component_count += 1
		_component[start] = label
		var stack: Array[int] = [start]
		var size := 0
		while not stack.is_empty():
			var node: int = stack.pop_back()
			size += 1
			for neighbor in _neighbors[node]:
				if _component[neighbor] >= 0:
					continue
				_component[neighbor] = label
				stack.append(neighbor)
		if size > _largest_size:
			_largest_size = size
			_largest_component = label


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func is_crossing_node(node: int) -> bool:
	if node < 0 or node >= _node_crossing.size():
		return false
	return _node_crossing[node] >= 0


func crossing_id_at(node: int) -> int:
	if node < 0 or node >= _node_crossing.size():
		return -1
	return _node_crossing[node]


func pavement_count() -> int:
	return _pavement_nodes.size()


func largest_component_ratio() -> float:
	if node_count <= 0:
		return 0.0
	return float(_largest_size) / float(node_count)


func component_count() -> int:
	return _component_count


## Nearest kerb pad, never a carriageway mid. XZ only: the planner's height is nominal.
func nearest_sidewalk_node(world: Vector3) -> int:
	var best := -1
	var best_d2 := INF
	for node in _pavement_nodes:
		var d2 := _flat_distance_squared(positions[node], world)
		if d2 >= best_d2:
			continue
		best_d2 = d2
		best = node
	return best


## A kerb pad in the largest connected part of the pavement, so a ped spawned on it has
## errands to run.
func random_node(rng: RandomNumberGenerator) -> int:
	if _pavement_nodes.is_empty():
		return -1
	if _largest_component < 0:
		return _pavement_nodes[rng.randi_range(0, _pavement_nodes.size() - 1)]
	for _attempt in range(64):
		var cand := _pavement_nodes[rng.randi_range(0, _pavement_nodes.size() - 1)]
		if _component[cand] == _largest_component:
			return cand
	for node in _pavement_nodes:
		if _component[node] == _largest_component:
			return node
	return _pavement_nodes[0]


## A kerb pad `min_m` to `max_m` away in a straight line, in the same connected pavement.
func random_goal_node(
	from_node: int, min_m: float, max_m: float, rng: RandomNumberGenerator
) -> int:
	if from_node < 0 or from_node >= node_count or _pavement_nodes.is_empty():
		return -1
	var comp := _component[from_node]
	var from_pos := positions[from_node]
	var min_d2 := min_m * min_m
	var max_d2 := max_m * max_m
	for _attempt in range(64):
		var cand := _pavement_nodes[rng.randi_range(0, _pavement_nodes.size() - 1)]
		if cand == from_node or _component[cand] != comp:
			continue
		var d2 := _flat_distance_squared(positions[cand], from_pos)
		if d2 >= min_d2 and d2 <= max_d2:
			return cand
	## Nothing in the band: any reachable pad still beats standing still.
	for _attempt in range(32):
		var cand := random_node(rng)
		if cand >= 0 and cand != from_node and _component[cand] == comp:
			return cand
	return -1


## Pavement route between two nodes, as node indices. Empty when they are not connected.
func find_path(from_node: int, to_node: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if from_node < 0 or to_node < 0 or from_node >= node_count or to_node >= node_count:
		return out
	if from_node == to_node:
		out.append(from_node)
		return out
	if _component[from_node] != _component[to_node]:
		return out
	var came_from := PackedInt32Array()
	came_from.resize(node_count)
	came_from.fill(-1)
	var queue := PackedInt32Array()
	queue.append(from_node)
	came_from[from_node] = from_node
	var head := 0
	while head < queue.size():
		var node: int = queue[head]
		head += 1
		if node == to_node:
			return _reconstruct(came_from, from_node, to_node)
		for neighbor in _neighbors[node]:
			if came_from[neighbor] >= 0:
				continue
			came_from[neighbor] = node
			queue.append(neighbor)
	push_error(
		"SidewalkMap: nodes %d and %d share a component but no route joins them"
		% [from_node, to_node]
	)
	return out


func _reconstruct(came_from: PackedInt32Array, from_node: int, to_node: int) -> PackedInt32Array:
	var reversed := PackedInt32Array()
	var walk := to_node
	while walk != from_node:
		reversed.append(walk)
		walk = came_from[walk]
	reversed.append(from_node)
	var out := PackedInt32Array()
	out.resize(reversed.size())
	for i in range(reversed.size()):
		out[i] = reversed[reversed.size() - 1 - i]
	return out


# ---------------------------------------------------------------------------
# Crossing occupancy
# ---------------------------------------------------------------------------

## Recount which crossings have someone on them. O(peds x crossings near each ped): a full
## crossing sweep per ped is what the grid exists to avoid.
func refresh_occupancy(agents: Array) -> void:
	_occupied = PackedInt32Array()
	for id: int in _occupancy.keys():
		_occupancy[id] = 0
	if agents.is_empty() or crossings.is_empty():
		return
	for agent: Variant in agents:
		var node := agent as Node3D
		if node == null:
			push_error("SidewalkMap.refresh_occupancy: %s is not a Node3D" % str(agent))
			continue
		var pos := node.global_position
		var key := _occupancy_key(pos.x, pos.z)
		if not _occupancy_grid.has(key):
			continue
		for id in _occupancy_grid[key]:
			var crossing := crossings[id]
			if _flat_distance_squared(pos, crossing.center) > crossing.radius * crossing.radius:
				continue
			_occupancy[id] = _occupancy[id] + 1
	for id: int in _occupancy.keys():
		if _occupancy[id] > 0:
			_occupied.append(id)


func is_crossing_occupied(crossing_id: int) -> bool:
	return int(_occupancy.get(crossing_id, 0)) > 0


func occupied_crossing_count() -> int:
	return _occupied.size()


## Should a car about to drive to `next_point` stop? True while an occupied crossing is both
## close to the car and ahead of it.
func yielding_for_car(car_pos: Vector3, next_point: Vector3) -> bool:
	for id in _occupied:
		var crossing := crossings[id]
		var stop_r := crossing.radius + YIELD_APPROACH_M
		if _flat_distance_squared(car_pos, crossing.center) > stop_r * stop_r:
			continue
		var reach := stop_r + 1.0
		if _flat_distance_squared(next_point, crossing.center) <= reach * reach:
			return true
	return false


func _rebuild_occupancy_grid() -> void:
	_occupancy_grid.clear()
	for crossing in crossings:
		var min_x := floori((crossing.center.x - crossing.radius) / OCCUPANCY_CELL_M)
		var max_x := floori((crossing.center.x + crossing.radius) / OCCUPANCY_CELL_M)
		var min_z := floori((crossing.center.z - crossing.radius) / OCCUPANCY_CELL_M)
		var max_z := floori((crossing.center.z + crossing.radius) / OCCUPANCY_CELL_M)
		for gx in range(min_x, max_x + 1):
			for gz in range(min_z, max_z + 1):
				var key := Vector2i(gx, gz)
				var bucket: PackedInt32Array = _occupancy_grid.get(key, PackedInt32Array())
				bucket.append(crossing.id)
				_occupancy_grid[key] = bucket


func _occupancy_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / OCCUPANCY_CELL_M), floori(z / OCCUPANCY_CELL_M))


static func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz
