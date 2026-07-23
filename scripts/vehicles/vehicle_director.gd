## Spawns and simulates cars on CarRoadMap with LOD visuals + passengers.
class_name VehicleDirector
extends Node3D

const VehicleAgentScript := preload("res://scripts/vehicles/vehicle_agent.gd")
const VehicleVisualScript := preload("res://scripts/vehicles/vehicle_visual.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")

@export var vehicle_count: int = 48
@export var near_distance: float = 55.0
@export var mid_distance: float = 120.0
## Extra meters before demoting LOD — stops thrashing at the boundary.
@export var lod_hysteresis_m: float = 18.0
@export var trip_min_m: float = 20.0
@export var trip_max_m: float = 180.0
@export var lod_interval_sec: float = 0.5
@export var cruise_speed_min: float = 7.0
@export var cruise_speed_max: float = 12.0
@export var turn_rate: float = 3.5
@export var waypoint_reach_m: float = 0.85

var _agents: Array[VehicleAgent] = []
var _roadmap: CarRoadMap
var _mid_mm: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _time: float = 0.0
var _lod_accum: float = 0.0
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
	VehicleCatalogScript.reload()
	if not VehicleCatalogScript.is_ready():
		push_error("VehicleDirector: VehicleCatalog not ready — traffic disabled")
		return
	if _roadmap == null or _roadmap.is_empty():
		push_error("VehicleDirector: empty car roadmap — traffic disabled")
		return
	_ground_y = _roadmap.ground_y
	_build_mid_multimesh()
	_spawn_agents()
	_refresh_lod(true)
	print(
		"VehicleDirector: agents=%d roadmap_nodes=%d catalog=%d near=%d"
		% [_agents.size(), _roadmap.node_count, VehicleCatalogScript.count(), _near_count]
	)


func clear_vehicles() -> void:
	for agent in _agents:
		_release_visual(agent)
	_agents.clear()
	_near_count = 0
	if _mid_mm != null and is_instance_valid(_mid_mm):
		_mid_mm.queue_free()
	_mid_mm = null


func vehicle_live_count() -> int:
	return _agents.size()


func count_lod_tiers() -> Vector3i:
	var near_n := 0
	var mid_n := 0
	var culled_n := 0
	for agent in _agents:
		match agent.lod:
			VehicleAgent.Lod.NEAR:
				near_n += 1
			VehicleAgent.Lod.MID:
				mid_n += 1
			_:
				culled_n += 1
	return Vector3i(near_n, mid_n, culled_n)


func _build_mid_multimesh() -> void:
	_mid_mm = MultiMeshInstance3D.new()
	_mid_mm.name = "MidVehicleProxies"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# Fixed count — resizing instance_count every LOD change flickers all proxies.
	mm.instance_count = maxi(vehicle_count, 1)
	var box := BoxMesh.new()
	box.size = Vector3(1.7, 0.55, 3.8)
	mm.mesh = box
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic = 0.2
	_mid_mm.material_override = mat
	_mid_mm.multimesh = mm
	add_child(_mid_mm)
	_hide_all_mid_proxies()


func _hide_all_mid_proxies() -> void:
	if _mid_mm == null:
		return
	var mm := _mid_mm.multimesh
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, hidden)


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
		agent.speed = _rng.randf_range(cruise_speed_min, cruise_speed_max)
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
		agent.lod = VehicleAgent.Lod.CULLED
		agent.visual = null
		_assign_trip(agent)
		_agents[i] = agent


func _physics_process(delta: float) -> void:
	if _agents.is_empty():
		return
	_time += delta
	_simulate(delta)
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		_refresh_lod(false)
	_sync_near_visuals()
	_sync_mid_proxies()


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
		nodes = PackedInt32Array()
		nodes.append(from_node)
		nodes.append(nbrs[_rng.randi_range(0, nbrs.size() - 1)])
	agent.set_path(_roadmap.path_to_world(nodes))


func _simulate(delta: float) -> void:
	var reach_r2 := waypoint_reach_m * waypoint_reach_m
	for agent in _agents:
		if not agent.moving or agent.path_i >= agent.waypoints.size():
			_assign_trip(agent)
			if not agent.moving:
				continue
		var target: Vector3 = agent.waypoints[agent.path_i]
		var to := target - agent.position
		to.y = 0.0
		var dist_sq := to.length_squared()
		if dist_sq <= reach_r2:
			agent.path_i += 1
			if agent.path_i >= agent.waypoints.size():
				agent.clear_path()
				_assign_trip(agent)
			continue
		var dist := sqrt(dist_sq)
		var dir := to / dist
		var desired_yaw := atan2(-dir.x, -dir.z)
		agent.yaw = lerp_angle(agent.yaw, desired_yaw, clampf(turn_rate * delta, 0.0, 1.0))
		# Translate straight at the waypoint — facing-only move orbits and never arrives.
		var step := mini(agent.speed * delta, dist)
		agent.position += dir * step
		agent.position.y = _ground_y
		if dist - step <= waypoint_reach_m:
			agent.position = Vector3(target.x, _ground_y, target.z)
			agent.path_i += 1


func _refresh_lod(force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam_pos := _camera.global_position
	var near_enter := near_distance
	var near_exit := near_distance + lod_hysteresis_m
	var mid_enter := mid_distance
	var mid_exit := mid_distance + lod_hysteresis_m
	_near_count = 0
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		var dx := agent.position.x - cam_pos.x
		var dz := agent.position.z - cam_pos.z
		var dist := sqrt(dx * dx + dz * dz)
		var next_lod := agent.lod
		match agent.lod:
			VehicleAgent.Lod.NEAR:
				if dist > near_exit:
					next_lod = VehicleAgent.Lod.MID if dist <= mid_exit else VehicleAgent.Lod.CULLED
			VehicleAgent.Lod.MID:
				if dist <= near_enter:
					next_lod = VehicleAgent.Lod.NEAR
				elif dist > mid_exit:
					next_lod = VehicleAgent.Lod.CULLED
			_:
				if dist <= near_enter:
					next_lod = VehicleAgent.Lod.NEAR
				elif dist <= mid_enter:
					next_lod = VehicleAgent.Lod.MID
		if force or next_lod != agent.lod:
			agent.lod = next_lod
			match agent.lod:
				VehicleAgent.Lod.NEAR:
					_ensure_visual(i, agent)
				_:
					_release_visual(agent)
		if agent.lod == VehicleAgent.Lod.NEAR:
			_near_count += 1


func _ensure_visual(agent_index: int, agent: VehicleAgent) -> void:
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
	for agent in _agents:
		if agent.visual == null or not is_instance_valid(agent.visual):
			continue
		(agent.visual as VehicleVisual).sync_pose(agent.position, agent.yaw)


func _sync_mid_proxies() -> void:
	if _mid_mm == null:
		return
	var mm := _mid_mm.multimesh
	if mm.instance_count < _agents.size():
		mm.instance_count = _agents.size()
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		if agent.lod != VehicleAgent.Lod.MID:
			mm.set_instance_transform(i, hidden)
			continue
		var basis := Basis.from_euler(Vector3(0.0, agent.yaw, 0.0))
		var origin := agent.position + Vector3(0.0, 0.35, 0.0)
		mm.set_instance_transform(i, Transform3D(basis, origin))
		var hue := float(absi(agent.catalog_id.hash()) % 100) / 100.0
		mm.set_instance_color(i, Color.from_hsv(hue, 0.55, 0.65))
