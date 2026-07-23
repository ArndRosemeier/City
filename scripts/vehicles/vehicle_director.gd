## Spawns and simulates cars on planner road graph with crossing yield.
## Full catalog visuals when near; culled when far (no mid box proxies).
class_name VehicleDirector
extends Node3D

const VehicleAgentScript := preload("res://scripts/vehicles/vehicle_agent.gd")
const VehicleVisualScript := preload("res://scripts/vehicles/vehicle_visual.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")

@export var vehicle_count: int = 48
## Full vehicle render distance. Beyond this: not drawn.
@export var render_distance: float = 120.0
@export var lod_hysteresis_m: float = 18.0
@export var trip_min_m: float = 20.0
@export var trip_max_m: float = 180.0
@export var lod_interval_sec: float = 0.5
@export var cruise_speed_min: float = 7.0
@export var cruise_speed_max: float = 12.0
@export var turn_rate: float = 3.5
@export var waypoint_reach_m: float = 0.85
@export var stuck_error_sec: float = 8.0
@export var crossing_occupancy_interval_sec: float = 0.12

var _agents: Array[VehicleAgent] = []
var _near_agents: Array[VehicleAgent] = []
var _roadmap: CarRoadMap
var _layers: StreetNavLayers
var _crowd: CrowdDirector
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _time: float = 0.0
var _lod_accum: float = 0.0
var _occupancy_accum: float = 0.0
var _ground_y: float = 1.0
var _near_count: int = 0


func setup(roadmap: CarRoadMap, camera: Camera3D, seed_value: int = -1) -> void:
	clear_vehicles()
	if seed_value >= 0:
		_rng.seed = seed_value + 917
	else:
		_rng.randomize()
	_camera = camera
	_roadmap = roadmap
	_layers = roadmap.layers() if roadmap != null else null
	VehicleCatalogScript.reload()
	if not VehicleCatalogScript.is_ready():
		push_error("VehicleDirector: VehicleCatalog not ready — traffic disabled")
		return
	if _roadmap == null or _roadmap.is_empty():
		push_error("VehicleDirector: empty car roadmap — traffic disabled")
		return
	if _roadmap.edge_count < 1:
		push_error("VehicleDirector: car roadmap has no edges — traffic disabled")
		return
	_ground_y = _roadmap.ground_y
	_spawn_agents()
	_refresh_lod(true)
	print(
		"VehicleDirector: agents=%d roadmap_nodes=%d edges=%d catalog=%d visible=%d render=%.0fm"
		% [
			_agents.size(),
			_roadmap.node_count,
			_roadmap.edge_count,
			VehicleCatalogScript.count(),
			_near_count,
			render_distance,
		]
	)


func bind_crowd(crowd: CrowdDirector) -> void:
	_crowd = crowd


func clear_vehicles() -> void:
	for agent in _agents:
		_release_visual(agent)
	_agents.clear()
	_near_agents.clear()
	_near_count = 0


func vehicle_live_count() -> int:
	return _agents.size()


func sample_agent_position(index: int = 0) -> Vector3:
	if index < 0 or index >= _agents.size():
		return Vector3.ZERO
	return _agents[index].position


func count_lod_tiers() -> Vector3i:
	## x=visible, y=0 (no mid), z=culled
	var near_n := 0
	var culled_n := 0
	for agent in _agents:
		if agent.lod == VehicleAgent.Lod.NEAR:
			near_n += 1
		else:
			culled_n += 1
	return Vector3i(near_n, 0, culled_n)


func _spawn_agents() -> void:
	var n := vehicle_count
	if _roadmap == null or _roadmap.is_empty():
		return
	if not VehicleCatalogScript.is_ready():
		push_error("VehicleDirector._spawn_agents: catalog not ready")
		return
	_agents.resize(n)
	for i in range(n):
		var agent: VehicleAgent = VehicleAgentScript.new()
		var spawn_node := _roadmap.random_node(_rng)
		agent.position = _roadmap.positions[spawn_node]
		agent.yaw = _rng.randf_range(0.0, TAU)
		agent.cruise_speed = _rng.randf_range(cruise_speed_min, cruise_speed_max)
		agent.speed = agent.cruise_speed
		var entry := VehicleCatalogScript.pick(_rng)
		if entry.is_empty():
			push_error("VehicleDirector: catalog.pick failed at agent %d" % i)
			_agents.resize(i)
			return
		agent.catalog_id = str(entry.get("id", ""))
		if agent.catalog_id == "":
			push_error("VehicleDirector: catalog entry missing id")
			_agents.resize(i)
			return
		var kind := str(entry.get("kind", "car"))
		if kind == "van":
			agent.passenger_count = 1 + _rng.randi() % 3
		else:
			agent.passenger_count = 1 + (_rng.randi() % 2)
		agent.clear_path()
		agent.stuck_sec = 0.0
		agent.lod = VehicleAgent.Lod.CULLED
		agent.visual = null
		_assign_trip(agent)
		_agents[i] = agent


func _physics_process(delta: float) -> void:
	if _agents.is_empty():
		return
	_time += delta
	_occupancy_accum += delta
	if _occupancy_accum >= crossing_occupancy_interval_sec:
		_occupancy_accum = 0.0
		_refresh_crossing_occupancy()
	_simulate(delta)
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		_refresh_lod(false)
	_update_frustum_visibility()
	_sync_near_visuals()


func _refresh_crossing_occupancy() -> void:
	if _layers == null or _crowd == null:
		return
	_layers.refresh_crossing_occupancy_agents(_crowd.agents_for_occupancy())


func _assign_trip(agent: VehicleAgent) -> void:
	if _roadmap == null or _roadmap.is_empty():
		agent.clear_path()
		return
	var from_node := _roadmap.nearest_node(agent.position)
	if from_node < 0:
		agent.clear_path()
		return
	var to_node := _roadmap.random_goal_node(from_node, trip_min_m, trip_max_m, _rng)
	var nodes := PackedInt32Array()
	if to_node >= 0 and to_node != from_node:
		nodes = _roadmap.find_path(from_node, to_node)
	if nodes.size() < 2:
		var nbrs: PackedInt32Array = _roadmap.neighbors[from_node]
		if nbrs.is_empty():
			agent.clear_path()
			return
		nodes = PackedInt32Array([from_node, nbrs[_rng.randi_range(0, nbrs.size() - 1)]])
	agent.set_path(_roadmap.path_to_world(nodes))
	agent.stuck_sec = 0.0


func _simulate(delta: float) -> void:
	var reach_r2 := waypoint_reach_m * waypoint_reach_m
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		if not agent.moving or agent.path_i >= agent.waypoints.size():
			_assign_trip(agent)
			if not agent.moving:
				agent.stuck_sec += delta
				if agent.stuck_sec >= stuck_error_sec:
					push_error(
						"VehicleDirector: agent stuck with no path for %.1fs at %s"
						% [agent.stuck_sec, str(agent.position)]
					)
					agent.stuck_sec = 0.0
				continue
		var target: Vector3 = agent.waypoints[agent.path_i]
		var to := target - agent.position
		to.y = 0.0
		var dist_sq := to.length_squared()
		if dist_sq <= reach_r2:
			agent.path_i += 1
			agent.stuck_sec = 0.0
			if agent.path_i >= agent.waypoints.size():
				agent.clear_path()
				_assign_trip(agent)
			continue

		# Crossing yield: stop when approaching occupied crosswalks.
		var yield_now := false
		if _layers != null:
			yield_now = _layers.yielding_for_car(agent.position, target)
		agent.speed = 0.0 if yield_now else agent.cruise_speed
		if yield_now:
			continue

		var dist := sqrt(dist_sq)
		var dir := to / dist
		var desired_yaw := atan2(-dir.x, -dir.z)
		agent.yaw = lerp_angle(agent.yaw, desired_yaw, clampf(turn_rate * delta, 0.0, 1.0))
		var step := minf(agent.speed * delta, dist)
		if step <= 0.0001:
			agent.stuck_sec += delta
			continue
		var next_pos := agent.position + dir * step
		next_pos.y = _ground_y
		if dist - step <= waypoint_reach_m:
			next_pos = Vector3(target.x, _ground_y, target.z)
			agent.path_i += 1
		agent.position = next_pos
		agent.stuck_sec = 0.0
		_agents[i] = agent


func _refresh_lod(force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam_pos := _camera.global_position
	var enter_r := render_distance
	var exit_r := render_distance + lod_hysteresis_m
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		var dx := agent.position.x - cam_pos.x
		var dz := agent.position.z - cam_pos.z
		var dist := sqrt(dx * dx + dz * dz)
		var next_lod := agent.lod
		if agent.lod == VehicleAgent.Lod.NEAR:
			if dist > exit_r:
				next_lod = VehicleAgent.Lod.CULLED
		else:
			if dist <= enter_r:
				next_lod = VehicleAgent.Lod.NEAR
		if force:
			next_lod = VehicleAgent.Lod.NEAR if dist <= enter_r else VehicleAgent.Lod.CULLED
		if force or next_lod != agent.lod:
			agent.lod = next_lod
			if agent.lod == VehicleAgent.Lod.NEAR:
				_ensure_visual(i, agent)
			else:
				_release_visual(agent)


func _update_frustum_visibility() -> void:
	_near_agents.clear()
	_near_count = 0
	if _camera == null or not is_instance_valid(_camera):
		return
	for agent in _agents:
		var vis := agent.visual as VehicleVisual
		if vis == null or not is_instance_valid(vis):
			continue
		var in_view := _camera.is_position_in_frustum(agent.position + Vector3(0.0, 1.0, 0.0))
		vis.visible = in_view
		vis.process_mode = Node.PROCESS_MODE_INHERIT if in_view else Node.PROCESS_MODE_DISABLED
		if in_view:
			_near_count += 1
			_near_agents.append(agent)


func _ensure_visual(agent_index: int, agent: VehicleAgent) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if agent.visual != null and is_instance_valid(agent.visual):
		return
	var entry := VehicleCatalogScript.entry_by_id(agent.catalog_id)
	if entry.is_empty():
		push_error("VehicleDirector: no catalog entry for '%s'" % agent.catalog_id)
		return
	var visual: VehicleVisual = VehicleVisualScript.new()
	visual.name = "NearVehicle_%d" % agent_index
	add_child(visual)
	visual.setup(entry, agent.passenger_count, agent_index * 97 + 3)
	if not visual.ready_visual:
		push_error("VehicleDirector: visual setup failed for agent %d (%s)" % [agent_index, agent.catalog_id])
		visual.queue_free()
		return
	visual.sync_pose(agent.position, agent.yaw)
	agent.visual = visual


func _release_visual(agent: VehicleAgent) -> void:
	if agent.visual == null:
		return
	if is_instance_valid(agent.visual):
		agent.visual.queue_free()
	agent.visual = null


func _sync_near_visuals() -> void:
	for agent in _near_agents:
		if agent.visual == null or not is_instance_valid(agent.visual):
			continue
		if not agent.visual.visible:
			continue
		(agent.visual as VehicleVisual).sync_pose(agent.position, agent.yaw)
