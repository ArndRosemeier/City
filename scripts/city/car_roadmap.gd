## Car navigation adapter over StreetNavLayers.road (planner topology).
class_name CarRoadMap
extends RefCounted

var positions: PackedVector3Array = PackedVector3Array()
var neighbors: Array = []
var node_count: int = 0
var ground_y: float = 1.0
var stride_vox: int = 1
var voxel_size: float = 0.5
var edge_count: int = 0

var _graph: NavGraph
var _layers: StreetNavLayers


func is_empty() -> bool:
	return node_count <= 0


func bind_graph(graph: NavGraph, layers: StreetNavLayers = null) -> void:
	_graph = graph
	_layers = layers
	if _graph == null:
		positions = PackedVector3Array()
		neighbors.clear()
		node_count = 0
		edge_count = 0
		return
	positions = _graph.positions
	neighbors = _graph.neighbors
	node_count = _graph.node_count
	ground_y = _graph.ground_y
	voxel_size = _graph.voxel_size
	edge_count = _graph.edge_count


## Deprecated voxel sampling — kept only so old call sites fail loudly.
func build_from_district(
	_tool: VoxelTool,
	_size_x: int,
	_size_z: int,
	_ground_thickness: int,
	_vs: float,
	_stride: int = 2
) -> void:
	push_error(
		"CarRoadMap.build_from_district is retired — use StreetNavLayers + bind_graph()"
	)
	positions = PackedVector3Array()
	neighbors.clear()
	node_count = 0


func nearest_node(world: Vector3) -> int:
	if _graph == null:
		return -1
	return _graph.nearest_node(world)


func random_node(rng: RandomNumberGenerator) -> int:
	if _graph == null:
		return -1
	if _graph.largest_component >= 0:
		return _graph.random_node_in_component(_graph.largest_component, rng)
	return _graph.random_node(rng)


func random_goal_node(from_node: int, min_m: float, max_m: float, rng: RandomNumberGenerator) -> int:
	if _graph == null:
		return -1
	return _graph.random_goal_node(from_node, min_m, max_m, rng)


func find_path(from_node: int, to_node: int) -> PackedInt32Array:
	if _graph == null:
		return PackedInt32Array()
	return _graph.find_path(from_node, to_node)


func path_to_world(path_nodes: PackedInt32Array) -> PackedVector3Array:
	if _graph == null:
		return PackedVector3Array()
	return _graph.path_to_world(path_nodes)


func largest_component_ratio() -> float:
	if _graph == null:
		return 0.0
	return _graph.largest_component_ratio()


func layers() -> StreetNavLayers:
	return _layers
