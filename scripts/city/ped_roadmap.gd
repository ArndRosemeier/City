## Pedestrian navigation adapter over StreetNavLayers.ped (sidewalks + crossings).
##
## All that survives of the retired ped roadmap: the span field carries walkability, and what
## is left here is the planner's crossing topology, which `PedGoalProvider` walks an errand
## through because A* legitimately jaywalks a wide carriageway on cost.
class_name PedRoadMap
extends RefCounted

var positions: PackedVector3Array = PackedVector3Array()
var node_count: int = 0
var edge_count: int = 0

var _graph: NavGraph


func is_empty() -> bool:
	return node_count <= 0


func bind_graph(graph: NavGraph) -> void:
	_graph = graph
	if _graph == null:
		positions = PackedVector3Array()
		node_count = 0
		edge_count = 0
		return
	positions = _graph.positions
	node_count = _graph.node_count
	edge_count = _graph.edge_count


func nearest_sidewalk_node(world: Vector3) -> int:
	if _graph == null:
		return -1
	return _graph.nearest_sidewalk_node(world)


func is_crossing_node(node: int) -> bool:
	if _graph == null:
		return false
	return _graph.is_crossing_node(node)


func random_node(rng: RandomNumberGenerator) -> int:
	## Sidewalk/curb only — never spawn idle brains on carriageway mids.
	if _graph == null:
		return -1
	if _graph.largest_component >= 0:
		return _graph.random_sidewalk_node_in_component(_graph.largest_component, rng)
	return _graph.random_node(rng)


func random_goal_node(from_node: int, min_m: float, max_m: float, rng: RandomNumberGenerator) -> int:
	if _graph == null:
		return -1
	return _graph.random_goal_node(from_node, min_m, max_m, rng, true)


func find_path(from_node: int, to_node: int) -> PackedInt32Array:
	if _graph == null:
		return PackedInt32Array()
	return _graph.find_path(from_node, to_node)


func largest_component_ratio() -> float:
	if _graph == null:
		return 0.0
	return _graph.largest_component_ratio()
