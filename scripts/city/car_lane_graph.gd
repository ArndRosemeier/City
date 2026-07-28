## The carriageway half of a district's street topology: which side of the road is which lane,
## which way it runs, and which turns an intersection allows.
##
## The span field knows the asphalt is drivable; it cannot know that the northern half of it
## runs east and the southern half west, that a U-turn is not on, or that the kerb lane and the
## overtaking lane are different places. That is lane semantics, and it is planner data, so it
## stays here as an annotation over road-class spans rather than being baked into them.
##
## A lane node is an **entry gate**: the point where a car travelling in direction `d` crosses
## into a cell, offset to the right of `d` by half the carriageway. Modelling the gate rather
## than the cell centre is what makes turns come out right — leaving a cell sideways starts
## from where the car entered, so a right turn hugs the near corner and a left turn sweeps
## across the junction, instead of the car reversing to a shared centre point.
##
## Edges are directed and never include `-d`, so anti-U-turn is structural rather than a rule
## the driver has to remember. Only a cul-de-sac, which would otherwise be a sink that swallows
## cars, gets one.
##
## Nothing here is driven. `VehicleGoalProvider` turns a lane route into goals and NavService
## paths between them, so a car crossing a blasted junction reroutes like every other agent.
## Destruction reaches the lanes through `close_node`, which the provider calls when a lane
## point no longer has a car-sized span under it, and `invalidate_box`, which re-opens the
## lanes over a region that changed so a repaired road comes back into service.
class_name CarLaneGraph
extends RefCounted

## Travel directions in planner cell steps, indexed by lane direction id.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## How long a lane point stays out of service after a car found no road under it.
const CLOSED_SEC := 12.0
## Longest single leg handed to the pathfinder. A straight run merges into one leg, but not an
## unbounded one: the car should re-evaluate now and then, and one A* over half a district is
## dearer than two over a quarter each.
const MAX_LEG_M := 120.0

var positions: PackedVector3Array = PackedVector3Array()
var node_count: int = 0
var edge_count: int = 0

## Lane direction id per node, indexing DIRS.
var _direction: PackedByteArray = PackedByteArray()
## Planner cell per node.
var _cell: Array[Vector2i] = []
var _out: Array[PackedInt32Array] = []
## Clock reading a node re-opens at. Zero means open.
var _closed_until: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
## Bumped whenever the lanes change under a car — a closure or a region invalidation.
var _version: int = 1
var _closures: int = 0

var _cell_size: int = 28
var _voxel_size: float = 0.5
var _origin_vox: Vector3i = Vector3i.ZERO
var _nominal_y: float = 3.5


func is_empty() -> bool:
	return node_count <= 0


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Lay the lanes over the planner's road cells. No voxels are read: the span field owns
## heights, and `nominal_y` only has to be close enough for a consumer's `nearest_surface` to
## land in the right column.
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
	_direction = PackedByteArray()
	_cell = []
	_out = []
	node_count = 0
	edge_count = 0
	_clock = 0.0
	_version = 1
	_closures = 0
	if planner == null:
		push_error("CarLaneGraph.build: no planner")
		return

	## Vector3i(cx, cz, direction id) -> node.
	var lanes: Dictionary[Vector3i, int] = {}
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not planner.has_road_cell(cx, cz):
				continue
			for d in range(DIRS.size()):
				var back := Vector2i(cx, cz) - DIRS[d]
				if not planner.has_road_cell(back.x, back.y):
					## Nothing to arrive from, so no car ever enters this cell that way.
					continue
				lanes[Vector3i(cx, cz, d)] = _add_node(Vector2i(cx, cz), d)
	_link_lanes(planner, lanes)
	_closed_until.resize(node_count)
	_closed_until.fill(0.0)


func _link_lanes(planner: DistrictPlanner, lanes: Dictionary[Vector3i, int]) -> void:
	for key: Vector3i in lanes.keys():
		var node: int = lanes[key]
		var cell := Vector2i(key.x, key.y)
		var d := int(key.z)
		var back := _opposite(d)
		for e in range(DIRS.size()):
			if e == back:
				## The U-turn. Structurally absent, which is the whole point of the direction
				## being part of the node identity.
				continue
			var ahead := cell + DIRS[e]
			if not planner.has_road_cell(ahead.x, ahead.y):
				continue
			var next_key := Vector3i(ahead.x, ahead.y, e)
			if not lanes.has(next_key):
				push_error(
					"CarLaneGraph: %s is road and reachable along %s but has no lane node"
					% [str(ahead), str(DIRS[e])]
				)
				continue
			_link(node, lanes[next_key])
		if not _out[node].is_empty():
			continue
		## A cul-de-sac. Without the turn-around it is a sink, and a car that drives into one
		## never leaves it.
		var behind := cell + DIRS[back]
		var turn_key := Vector3i(behind.x, behind.y, back)
		if lanes.has(turn_key):
			_link(node, lanes[turn_key])


func _add_node(cell: Vector2i, direction: int) -> int:
	var node := positions.size()
	positions.append(_gate_world(cell, direction))
	_direction.append(direction)
	_cell.append(cell)
	_out.append(PackedInt32Array())
	node_count = positions.size()
	return node


func _link(from_node: int, to_node: int) -> void:
	var edges := _out[from_node]
	if edges.has(to_node):
		return
	edges.append(to_node)
	_out[from_node] = edges
	edge_count += 1


## Where a car travelling `direction` crosses into `cell`: the middle of the near face, moved
## to the right of travel by a quarter of the carriageway, which is the centre of that lane.
func _gate_world(cell: Vector2i, direction: int) -> Vector3:
	var d := DIRS[direction]
	var right := Vector2i(-d.y, d.x)
	var center_x := float(_origin_vox.x + cell.x * _cell_size) + float(_cell_size) * 0.5
	var center_z := float(_origin_vox.z + cell.y * _cell_size) + float(_cell_size) * 0.5
	var half_cell := float(_cell_size) * 0.5
	var offset := lane_offset_vox()
	return Vector3(
		(center_x - float(d.x) * half_cell + float(right.x) * offset) * _voxel_size,
		_nominal_y,
		(center_z - float(d.y) * half_cell + float(right.y) * offset) * _voxel_size
	)


## Distance from the road centreline to a lane centre, in voxels. The carriageway is the cell
## minus a pavement each side, and a lane is half of what is left.
func lane_offset_vox() -> float:
	var pavement := clampi(int(round(2.0 / _voxel_size)), 3, maxi(3, _cell_size / 6))
	return maxf((float(_cell_size) * 0.5 - float(pavement)) * 0.5, 1.0)


static func _opposite(direction: int) -> int:
	match direction:
		0:
			return 1
		1:
			return 0
		2:
			return 3
		3:
			return 2
		_:
			push_error("CarLaneGraph: unknown direction %d" % direction)
			return 0


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Travel direction of a lane node, as a unit vector in the XZ plane.
func heading_of(node: int) -> Vector3:
	if node < 0 or node >= node_count:
		push_error("CarLaneGraph.heading_of: %d of %d" % [node, node_count])
		return Vector3.ZERO
	var d := DIRS[int(_direction[node])]
	return Vector3(float(d.x), 0.0, float(d.y))


func direction_id(node: int) -> int:
	if node < 0 or node >= node_count:
		push_error("CarLaneGraph.direction_id: %d of %d" % [node, node_count])
		return 0
	return int(_direction[node])


func cell_of(node: int) -> Vector2i:
	if node < 0 or node >= node_count:
		push_error("CarLaneGraph.cell_of: %d of %d" % [node, node_count])
		return Vector2i.ZERO
	return _cell[node]


func exits_from(node: int) -> PackedInt32Array:
	if node < 0 or node >= node_count:
		push_error("CarLaneGraph.exits_from: %d of %d" % [node, node_count])
		return PackedInt32Array()
	return _out[node]


## Bumped by every closure and every invalidated region, so a car can tell that the lanes it
## planned across are not the lanes that are there now.
func version() -> int:
	return _version


## Lane points taken out of service because no car-sized span was under them.
func closures() -> int:
	return _closures


func open_node_count() -> int:
	var open := 0
	for node in range(node_count):
		if is_open(node):
			open += 1
	return open


func is_open(node: int) -> bool:
	if node < 0 or node >= node_count:
		return false
	return _closed_until[node] <= _clock


## One frame of the lane clock, which is what closures expire against.
func advance(delta: float) -> void:
	_clock += delta


## Take a lane point out of service: there is no road under it any more. It comes back by
## itself, because the street may be rebuilt and nothing else would ever re-test it.
func close_node(node: int, seconds: float = CLOSED_SEC) -> void:
	if node < 0 or node >= node_count:
		push_error("CarLaneGraph.close_node: %d of %d" % [node, node_count])
		return
	if seconds <= 0.0:
		push_error("CarLaneGraph.close_node: %.2f s is not a closure" % seconds)
		return
	if is_open(node):
		_closures += 1
	_closed_until[node] = _clock + seconds
	_version += 1


## The world changed over this region — a blast, a rebuild, a collapse. Lane points inside it
## go back into service so the next car re-tests them against the span field, and the version
## bump tells cars routed across it to plan again.
func invalidate_box(min_world: Vector3, max_world: Vector3) -> int:
	var touched := 0
	for node in range(node_count):
		var at := positions[node]
		if at.x < min_world.x or at.x > max_world.x:
			continue
		if at.z < min_world.z or at.z > max_world.z:
			continue
		touched += 1
		_closed_until[node] = 0.0
	if touched > 0:
		_version += 1
	return touched


## Nearest open lane point, preferring one a car already pointing along `heading` can take
## without turning round. XZ only: the planner's height is nominal.
func nearest_node(world: Vector3, heading: Vector3 = Vector3.ZERO) -> int:
	var best := -1
	var best_d2 := INF
	var best_aligned := -1
	var best_aligned_d2 := INF
	var want := Vector3(heading.x, 0.0, heading.z)
	var has_heading := want.length_squared() > 0.0001
	if has_heading:
		want = want.normalized()
	for node in range(node_count):
		if not is_open(node):
			continue
		var d2 := _flat_distance_squared(positions[node], world)
		if d2 < best_d2:
			best_d2 = d2
			best = node
		if has_heading and heading_of(node).dot(want) > 0.0 and d2 < best_aligned_d2:
			best_aligned_d2 = d2
			best_aligned = node
	return best_aligned if best_aligned >= 0 else best


func random_node(rng: RandomNumberGenerator) -> int:
	if node_count <= 0:
		return -1
	for _attempt in range(64):
		var cand := rng.randi_range(0, node_count - 1)
		if is_open(cand) and not _out[cand].is_empty():
			return cand
	for node in range(node_count):
		if is_open(node) and not _out[node].is_empty():
			return node
	return -1


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

## A drive of roughly `min_m` to `max_m`, as lane nodes. Directed, so the route never doubles
## back on itself, and closed lane points are not on it.
func plan_trip(
	from_node: int, min_m: float, max_m: float, rng: RandomNumberGenerator
) -> PackedInt32Array:
	if from_node < 0 or from_node >= node_count:
		push_error("CarLaneGraph.plan_trip: %d of %d" % [from_node, node_count])
		return PackedInt32Array()
	var max_d := maxf(max_m, maxf(min_m, 0.0) + 1.0)
	var came_from := PackedInt32Array()
	came_from.resize(node_count)
	came_from.fill(-1)
	var reached := PackedFloat32Array()
	reached.resize(node_count)
	reached.fill(-1.0)
	var queue := PackedInt32Array()
	queue.append(from_node)
	came_from[from_node] = from_node
	reached[from_node] = 0.0
	var head := 0
	var in_band: Array[int] = []
	var any: Array[int] = []
	while head < queue.size():
		var node: int = queue[head]
		head += 1
		var travelled := reached[node]
		if node != from_node:
			any.append(node)
			if travelled >= min_m:
				in_band.append(node)
		if travelled >= max_d:
			continue
		for next_node in _out[node]:
			if reached[next_node] >= 0.0 or not is_open(next_node):
				continue
			reached[next_node] = travelled + _leg_length(node, next_node)
			came_from[next_node] = node
			queue.append(next_node)
	var pool := in_band if not in_band.is_empty() else any
	if pool.is_empty():
		return PackedInt32Array()
	return _reconstruct(came_from, from_node, pool[rng.randi_range(0, pool.size() - 1)])


## Does any lane point on this route stand inside the region? Cars re-plan on that rather than
## on every edit anywhere in the district.
func route_crosses_box(
	route: PackedInt32Array, min_world: Vector3, max_world: Vector3
) -> bool:
	for node in route:
		var at := positions[node]
		if at.x < min_world.x or at.x > max_world.x:
			continue
		if at.z < min_world.z or at.z > max_world.z:
			continue
		return true
	return false


## The lane points a car is actually given as goals. Consecutive nodes running the same way lie
## on one straight lane, so the corridor between the ends of a run *is* that lane and the nodes
## in between buy nothing — they are merged out, up to `MAX_LEG_M`. Every direction change
## stays, because that is the turn, and a turn taken as one long leg would be cut across the
## junction by corridor smoothing.
##
## Node indices rather than points, so a car that finds no road under a leg can say which lane
## point to take out of service.
func route_to_legs(route: PackedInt32Array) -> PackedInt32Array:
	var legs := PackedInt32Array()
	if route.size() < 2:
		return legs
	var run_direction := int(_direction[route[1]])
	var run_m := _leg_length(route[0], route[1])
	for i in range(2, route.size()):
		var step := _leg_length(route[i - 1], route[i])
		if int(_direction[route[i]]) != run_direction:
			## Both ends of the turn: the approach in the old lane, then the gate the new one
			## starts at. One leg across a junction would be string-pulled into the corner and
			## the car would clip the oncoming side of it.
			legs.append(route[i - 1])
			legs.append(route[i])
			run_direction = int(_direction[route[i]])
			run_m = 0.0
		elif run_m + step > MAX_LEG_M:
			legs.append(route[i - 1])
			run_m = step
		else:
			run_m += step
	var last := route[route.size() - 1]
	if legs.is_empty() or legs[legs.size() - 1] != last:
		legs.append(last)
	return legs


func route_length_m(route: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += _leg_length(route[i - 1], route[i])
	return total


func _leg_length(from_node: int, to_node: int) -> float:
	return sqrt(_flat_distance_squared(positions[from_node], positions[to_node]))


func _reconstruct(came_from: PackedInt32Array, from_node: int, to_node: int) -> PackedInt32Array:
	var reversed := PackedInt32Array()
	var walk := to_node
	while walk != from_node:
		reversed.append(walk)
		walk = came_from[walk]
		if walk < 0:
			push_error("CarLaneGraph: route to %d has no way back to %d" % [to_node, from_node])
			return PackedInt32Array()
	reversed.append(from_node)
	var out := PackedInt32Array()
	out.resize(reversed.size())
	for i in range(reversed.size()):
		out[i] = reversed[reversed.size() - 1 - i]
	return out


static func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz
