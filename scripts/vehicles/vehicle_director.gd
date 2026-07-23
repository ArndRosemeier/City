## Spawns and simulates cars on planner road graph with crossing yield.
## Full catalog visuals when near; culled when far (no mid box proxies).
class_name VehicleDirector
extends Node3D

const VehicleAgentScript := preload("res://scripts/vehicles/vehicle_agent.gd")
const VehicleVisualScript := preload("res://scripts/vehicles/vehicle_visual.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")
const TumbleSettleScript := preload("res://scripts/city/tumble_settle.gd")

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
	for child in get_children():
		if child is RigidBody3D and String(child.name).begins_with("Wreck_"):
			child.queue_free()


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


## Closest live vehicle along segment. Empty if none.
## Keys: distance, point, agent, index.
func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	var best_dist := INF
	var best: Dictionary = {}
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.05:
		return best
	var dir := seg / seg_len
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		if agent == null or agent.wrecked:
			continue
		var half := Vector3(1.15, 0.95, 2.4)
		var center := agent.position + Vector3(0.0, half.y, 0.0)
		if agent.visual != null and is_instance_valid(agent.visual):
			var vis := agent.visual as VehicleVisual
			if vis != null:
				half = vis.body_half_extents() * 1.15
				center = agent.position + vis.body_center_offset()
		var hit := _segment_hits_oriented_box(from, to, center, agent.yaw, half)
		if hit.is_empty():
			## Fat cylinder fallback so glancing aim still registers.
			hit = _segment_hits_cylinder(from, dir, seg_len, center, maxf(half.x, half.z) * 1.05, half.y)
		if hit.is_empty():
			continue
		var dist: float = float(hit["distance"])
		if dist >= best_dist:
			continue
		best_dist = dist
		best = {
			"distance": dist,
			"point": hit["point"],
			"agent": agent,
			"index": i,
		}
	return best


func wreck_agent(agent: VehicleAgent, hit_point: Vector3, impulse_dir: Vector3) -> bool:
	if agent == null or agent.wrecked:
		return false
	agent.wrecked = true
	agent.clear_path()
	agent.speed = 0.0
	var idx := _agents.find(agent)
	if idx < 0:
		return false
	agent.lod = VehicleAgent.Lod.NEAR
	_ensure_visual(idx, agent)
	var vis := agent.visual as VehicleVisual
	if vis == null or not is_instance_valid(vis):
		push_error("VehicleDirector: wreck_agent missing visual")
		return false
	vis.visible = true
	vis.process_mode = Node.PROCESS_MODE_INHERIT
	vis.sync_pose(agent.position, agent.yaw)
	agent.visual = null

	var dir := impulse_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()

	var body := RigidBody3D.new()
	body.name = "Wreck_%d" % idx
	body.collision_layer = 4
	body.collision_mask = 1
	body.continuous_cd = true
	body.contact_monitor = false
	body.linear_damp = 0.35
	body.angular_damp = 0.55
	body.mass = 1200.0
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = vis.body_center_offset()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = vis.body_half_extents() * 2.0
	shape.shape = box
	shape.position = vis.body_center_offset()
	body.add_child(shape)

	var keep_xf: Transform3D = vis.global_transform
	var parent_node: Node = vis.get_parent()
	if parent_node != null:
		parent_node.remove_child(vis)
	add_child(body)
	body.global_transform = keep_xf
	body.add_child(vis)
	vis.transform = Transform3D.IDENTITY

	## Dramatic tumble: lift + forward slam + strong roll torque.
	var impulse := dir * 42.0 + Vector3.UP * 28.0
	var hit_offset := hit_point - body.global_position
	body.apply_impulse(impulse, hit_offset)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	body.apply_torque_impulse(side * 55.0 + dir * 18.0)
	body.set_meta("tumble_clearance", maxf(vis.body_half_extents().x, vis.body_half_extents().y) * 1.05)
	if get_tree() != null:
		get_tree().create_timer(4.5).timeout.connect(_freeze_wreck.bind(body))
	return true


func _freeze_wreck(body: RigidBody3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var clearance := float(body.get_meta("tumble_clearance", 0.9))
	TumbleSettleScript.freeze_lying_down(body, TumbleSettleScript.Kind.VEHICLE, clearance)


static func _segment_hits_oriented_box(
	from: Vector3,
	to: Vector3,
	center: Vector3,
	yaw: float,
	half_extents: Vector3
) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, center)
	var inv := xf.affine_inverse()
	var local_from: Vector3 = inv * from
	var local_to: Vector3 = inv * to
	var aabb := AABB(-half_extents, half_extents * 2.0)
	var hit: Variant = aabb.intersects_segment(local_from, local_to)
	if hit == null or typeof(hit) != TYPE_VECTOR3:
		return {}
	var local_point: Vector3 = hit as Vector3
	var world_point: Vector3 = xf * local_point
	return {"point": world_point, "distance": from.distance_to(world_point)}


static func _segment_hits_cylinder(
	from: Vector3,
	dir: Vector3,
	seg_len: float,
	center: Vector3,
	radius: float,
	half_height: float
) -> Dictionary:
	var to_c := center - from
	var t := clampf(to_c.dot(dir), 0.0, seg_len)
	var closest := from + dir * t
	var delta := closest - center
	if absf(delta.y) > half_height + 0.35:
		return {}
	if Vector2(delta.x, delta.z).length() > radius:
		return {}
	return {"point": closest, "distance": t}


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
		if agent.wrecked:
			continue
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
		if agent.wrecked:
			## Visual already reparented onto a RigidBody wreck.
			agent.lod = VehicleAgent.Lod.CULLED
			continue
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
