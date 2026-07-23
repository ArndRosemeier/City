## Simulates many pedestrians; every agent inside near_distance gets a full skinned body.
class_name CrowdDirector
extends Node3D

const CrowdPedVisualScript := preload("res://scripts/city/crowd_ped_visual.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")

@export var pedestrian_count: int = 1000
@export var near_distance: float = 28.0
@export var mid_distance: float = 75.0
@export var near_distance_min: float = 5.0
@export var near_distance_max: float = 250.0
@export var near_distance_step: float = 5.0
@export var decision_min_sec: float = 10.0
@export var decision_max_sec: float = 60.0
@export var walk_goal_min_m: float = 10.0
@export var walk_goal_max_m: float = 45.0
@export var lod_interval_sec: float = 0.35

var _agents: Array[PedAgent] = []
var _roadmap: PedRoadMap
var _mid_mm: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _time: float = 0.0
var _lod_accum: float = 0.0
var _ground_y: float = 1.0
var _skinned_count: int = 0


func setup(roadmap: PedRoadMap, camera: Camera3D, seed_value: int = -1) -> void:
	clear_crowd()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_camera = camera
	_roadmap = roadmap
	if _roadmap == null or _roadmap.is_empty():
		push_warning("CrowdDirector: empty roadmap; crowd empty")
		return
	_ground_y = _roadmap.ground_y
	_build_mid_multimesh()
	_spawn_agents()
	_refresh_lod(true)
	print(
		"CrowdDirector: agents=%d roadmap_nodes=%d skinned=%d"
		% [_agents.size(), _roadmap.node_count, _skinned_count]
	)


func clear_crowd() -> void:
	for agent in _agents:
		_release_visual(agent)
	_agents.clear()
	_skinned_count = 0
	if _mid_mm != null and is_instance_valid(_mid_mm):
		_mid_mm.queue_free()
	_mid_mm = null


func agent_count() -> int:
	return _agents.size()


func adjust_near_distance(direction: float) -> void:
	## direction > 0 grows near LOD radius, < 0 shrinks. Mid ring scales with it.
	if is_zero_approx(direction):
		return
	var next := near_distance + (near_distance_step if direction > 0.0 else -near_distance_step)
	next = clampf(snappedf(next, near_distance_step), near_distance_min, near_distance_max)
	if is_equal_approx(next, near_distance):
		return
	near_distance = next
	mid_distance = maxf(near_distance + 20.0, near_distance * 2.5)
	_refresh_lod(true)
	print(
		"CrowdDirector LOD near=%.0fm mid=%.0fm skinned=%d"
		% [near_distance, mid_distance, _skinned_count]
	)


func get_lod_distances() -> Vector2:
	return Vector2(near_distance, mid_distance)


func get_skinned_count() -> int:
	return _skinned_count


func count_lod_tiers() -> Vector3i:
	var near_n := 0
	var mid_n := 0
	var culled_n := 0
	for agent in _agents:
		match agent.lod:
			PedAgent.Lod.NEAR:
				near_n += 1
			PedAgent.Lod.MID:
				mid_n += 1
			_:
				culled_n += 1
	return Vector3i(near_n, mid_n, culled_n)


func _build_mid_multimesh() -> void:
	_mid_mm = MultiMeshInstance3D.new()
	_mid_mm.name = "MidPedProxies"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 1.7
	mm.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	_mid_mm.material_override = mat
	_mid_mm.multimesh = mm
	add_child(_mid_mm)


func _spawn_agents() -> void:
	var n := pedestrian_count
	if _roadmap == null or _roadmap.is_empty():
		return
	_agents.resize(n)
	for i in range(n):
		var agent := PedAgent.new()
		var spawn_node := _roadmap.random_node(_rng)
		agent.position = _roadmap.positions[spawn_node]
		agent.yaw = _rng.randf_range(0.0, TAU)
		agent.female = _rng.randf() < 0.5
		agent.walk_tendency = clampf(_rng.randfn(0.55, 0.22), 0.05, 0.95)
		agent.walk_speed = _rng.randf_range(1.1, 1.7)
		agent.body_scale = _rng.randf_range(0.92, 1.08)
		agent.outfit = PedOutfitScript.random(_rng, agent.female)
		agent.next_decision_at = _time + _rng.randf_range(0.5, decision_max_sec)
		agent.clear_path()
		agent.lod = PedAgent.Lod.CULLED
		agent.visual = null
		_decide(agent)
		_agents[i] = agent


func _physics_process(delta: float) -> void:
	if _agents.is_empty():
		return
	_time += delta
	_simulate_agents(delta)
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		_refresh_lod(false)
	_sync_near_visuals()
	_sync_mid_proxies()


func _simulate_agents(delta: float) -> void:
	for agent in _agents:
		if _time >= agent.next_decision_at:
			_decide(agent)
		if agent.state != PedAgent.State.WALK:
			continue
		if agent.path_i >= agent.waypoints.size():
			agent.clear_path()
			agent.next_decision_at = _time + _rng.randf_range(
				decision_min_sec * 0.35, decision_max_sec * 0.5
			)
			continue
		var target: Vector3 = agent.waypoints[agent.path_i]
		var to := target - agent.position
		to.y = 0.0
		var dist_sq := to.length_squared()
		if dist_sq < 0.16:
			agent.path_i += 1
			if agent.path_i >= agent.waypoints.size():
				agent.clear_path()
				agent.next_decision_at = _time + _rng.randf_range(
					decision_min_sec * 0.35, decision_max_sec * 0.5
				)
			continue
		var step := agent.walk_speed * delta
		if dist_sq <= step * step:
			agent.position = Vector3(target.x, _ground_y, target.z)
			agent.path_i += 1
		else:
			var dir := to / sqrt(dist_sq)
			agent.yaw = atan2(-dir.x, -dir.z)
			agent.position += dir * step
			agent.position.y = _ground_y


func _decide(agent: PedAgent) -> void:
	agent.next_decision_at = _time + _rng.randf_range(decision_min_sec, decision_max_sec)
	if _roadmap == null or _roadmap.is_empty():
		agent.clear_path()
		return
	if _rng.randf() > agent.walk_tendency:
		agent.clear_path()
		return
	var from_node := _roadmap.nearest_node(agent.position)
	var to_node := _roadmap.random_goal_node(
		from_node, walk_goal_min_m, walk_goal_max_m, _rng
	)
	if to_node < 0 or to_node == from_node:
		agent.clear_path()
		return
	var nodes := _roadmap.find_path(from_node, to_node)
	if nodes.size() < 2:
		agent.clear_path()
		return
	agent.set_path(_roadmap.path_to_world(nodes))


func _refresh_lod(_force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam_pos := _camera.global_position
	var near_r2 := near_distance * near_distance
	var mid_r2 := mid_distance * mid_distance
	_skinned_count = 0

	for i in range(_agents.size()):
		var agent: PedAgent = _agents[i]
		var dx := agent.position.x - cam_pos.x
		var dz := agent.position.z - cam_pos.z
		var d2 := dx * dx + dz * dz
		if d2 <= near_r2:
			agent.lod = PedAgent.Lod.NEAR
			_ensure_visual(i, agent)
			_skinned_count += 1
		elif d2 <= mid_r2:
			agent.lod = PedAgent.Lod.MID
			_release_visual(agent)
		else:
			agent.lod = PedAgent.Lod.CULLED
			_release_visual(agent)


func _ensure_visual(agent_index: int, agent: PedAgent) -> void:
	if agent.visual != null and is_instance_valid(agent.visual):
		return
	var visual: CrowdPedVisual = CrowdPedVisualScript.new()
	visual.name = "NearPed_%d" % agent_index
	add_child(visual)
	visual.bind_agent(agent_index, agent.female, agent.body_scale, agent.outfit)
	agent.visual = visual


func _release_visual(agent: PedAgent) -> void:
	if agent.visual == null:
		return
	if is_instance_valid(agent.visual):
		agent.visual.queue_free()
	agent.visual = null


func _sync_near_visuals() -> void:
	for agent in _agents:
		if agent.visual == null or not is_instance_valid(agent.visual):
			continue
		(agent.visual as CrowdPedVisual).sync_from_agent(agent)


func _sync_mid_proxies() -> void:
	if _mid_mm == null:
		return
	var mm := _mid_mm.multimesh
	var mid_indices: Array[int] = []
	for i in range(_agents.size()):
		if _agents[i].lod == PedAgent.Lod.MID:
			mid_indices.append(i)
	var count := mid_indices.size()
	if mm.instance_count != count:
		mm.instance_count = count
	for j in range(count):
		var agent: PedAgent = _agents[mid_indices[j]]
		var basis := Basis.from_euler(Vector3(0.0, agent.yaw, 0.0))
		basis = basis.scaled(Vector3(agent.body_scale, agent.body_scale, agent.body_scale))
		var origin := agent.position + Vector3(0.0, 0.85 * agent.body_scale, 0.0)
		mm.set_instance_transform(j, Transform3D(basis, origin))
		var proxy := Color(0.55, 0.45, 0.38)
		if agent.outfit != null:
			proxy = agent.outfit.mid_proxy_color()
		mm.set_instance_color(j, proxy)
