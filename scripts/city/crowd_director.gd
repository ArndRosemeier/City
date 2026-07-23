## Pedestrian crowd: full skinned bodies when near, culled when far (no mid proxies).
class_name CrowdDirector
extends Node3D

const CrowdPedVisualScript := preload("res://scripts/city/crowd_ped_visual.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")

@export var pedestrian_count: int = 1000
## Full body render distance. Beyond this: not drawn.
@export var render_distance: float = 70.0
@export var render_distance_min: float = 10.0
@export var render_distance_max: float = 250.0
@export var render_distance_step: float = 5.0
## Rare pause window when a ped chooses to stay (exception, not the rule).
@export var stay_min_sec: float = 1.2
@export var stay_max_sec: float = 4.0
## Brief pause between consecutive walks.
@export var rewalk_min_sec: float = 0.05
@export var rewalk_max_sec: float = 0.7
@export var walk_goal_min_m: float = 12.0
@export var walk_goal_max_m: float = 55.0
@export var lod_interval_sec: float = 0.35
## Probability that a decision picks WALK (idle is the exception).
@export var walk_decision_chance: float = 0.92
@export var lod_hysteresis_m: float = 12.0

var _agents: Array[PedAgent] = []
var _near_agents: Array[PedAgent] = []
var _roadmap: PedRoadMap
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
	_spawn_agents()
	_refresh_lod(true)
	print(
		"CrowdDirector: agents=%d roadmap_nodes=%d skinned=%d render=%.0fm"
		% [_agents.size(), _roadmap.node_count, _skinned_count, render_distance]
	)


func clear_crowd() -> void:
	for agent in _agents:
		_release_visual(agent)
	_agents.clear()
	_near_agents.clear()
	_skinned_count = 0


func agent_count() -> int:
	return _agents.size()


func adjust_near_distance(direction: float) -> void:
	## F9/F10: shrink/grow full-body render radius.
	if is_zero_approx(direction):
		return
	var next := render_distance + (render_distance_step if direction > 0.0 else -render_distance_step)
	next = clampf(snappedf(next, render_distance_step), render_distance_min, render_distance_max)
	if is_equal_approx(next, render_distance):
		return
	render_distance = next
	_refresh_lod(true)
	print("CrowdDirector render=%.0fm skinned=%d" % [render_distance, _skinned_count])


func get_lod_distances() -> Vector2:
	## x = render distance, y unused (kept for HUD compatibility).
	return Vector2(render_distance, render_distance)


func get_skinned_count() -> int:
	return _skinned_count


func collect_positions() -> Array:
	var out: Array = []
	out.resize(_agents.size())
	for i in range(_agents.size()):
		out[i] = _agents[i].position
	return out


func agents_for_occupancy() -> Array:
	return _agents


func count_lod_tiers() -> Vector3i:
	## x=visible, y=0 (no mid), z=culled
	var near_n := 0
	var culled_n := 0
	for agent in _agents:
		if agent.lod == PedAgent.Lod.NEAR:
			near_n += 1
		else:
			culled_n += 1
	return Vector3i(near_n, 0, culled_n)


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
		agent.walk_tendency = clampf(_rng.randfn(walk_decision_chance, 0.04), 0.82, 0.99)
		agent.walk_speed = _rng.randf_range(1.15, 1.85)
		agent.body_scale = _rng.randf_range(0.92, 1.08)
		agent.outfit = PedOutfitScript.random(_rng, agent.female)
		agent.next_decision_at = _time + _rng.randf_range(0.0, 0.8)
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
	_update_frustum_visibility()
	_sync_near_visuals()


func _simulate_agents(delta: float) -> void:
	for agent in _agents:
		if _time >= agent.next_decision_at:
			_decide(agent)
		if agent.state != PedAgent.State.WALK:
			continue
		if agent.path_i >= agent.waypoints.size():
			_finish_walk(agent)
			continue
		var target: Vector3 = agent.waypoints[agent.path_i]
		var to := target - agent.position
		to.y = 0.0
		var dist_sq := to.length_squared()
		if dist_sq < 0.16:
			agent.path_i += 1
			if agent.path_i >= agent.waypoints.size():
				_finish_walk(agent)
			continue
		var step := agent.walk_speed * delta
		if dist_sq <= step * step:
			agent.position = Vector3(target.x, _ground_y, target.z)
			agent.path_i += 1
			if agent.path_i >= agent.waypoints.size():
				_finish_walk(agent)
		else:
			var dir := to / sqrt(dist_sq)
			agent.yaw = atan2(-dir.x, -dir.z)
			agent.position += dir * step
			agent.position.y = _ground_y


func _finish_walk(agent: PedAgent) -> void:
	agent.clear_path()
	_leave_carriageway_if_needed(agent)
	agent.next_decision_at = _time + _rng.randf_range(rewalk_min_sec, rewalk_max_sec)


func _leave_carriageway_if_needed(agent: PedAgent) -> void:
	if _roadmap == null or _roadmap.is_empty():
		return
	var node := _roadmap.nearest_node(agent.position)
	if node < 0 or not _roadmap.is_crossing_node(node):
		return
	var curb := _roadmap.nearest_sidewalk_node(agent.position)
	if curb < 0:
		return
	agent.position = _roadmap.positions[curb]
	agent.position.y = _ground_y


func _decide(agent: PedAgent) -> void:
	if _roadmap == null or _roadmap.is_empty():
		agent.clear_path()
		agent.next_decision_at = _time + stay_max_sec
		return
	_leave_carriageway_if_needed(agent)
	var will_walk := _rng.randf() <= agent.walk_tendency
	if not will_walk:
		agent.clear_path()
		_leave_carriageway_if_needed(agent)
		agent.next_decision_at = _time + _rng.randf_range(stay_min_sec, stay_max_sec)
		return
	var from_node := _roadmap.nearest_sidewalk_node(agent.position)
	if from_node < 0:
		from_node = _roadmap.nearest_node(agent.position)
	if from_node < 0:
		agent.clear_path()
		agent.next_decision_at = _time + stay_max_sec
		return
	var to_node := _roadmap.random_goal_node(
		from_node, walk_goal_min_m, walk_goal_max_m, _rng
	)
	if to_node < 0 or to_node == from_node:
		var nbrs: PackedInt32Array = _roadmap.neighbors[from_node]
		if nbrs.is_empty():
			agent.clear_path()
			agent.next_decision_at = _time + stay_max_sec
			return
		to_node = nbrs[_rng.randi_range(0, nbrs.size() - 1)]
		for _pick in range(mini(nbrs.size(), 4)):
			var cand: int = nbrs[_rng.randi_range(0, nbrs.size() - 1)]
			if not _roadmap.is_crossing_node(cand):
				to_node = cand
				break
	var nodes := _roadmap.find_path(from_node, to_node)
	if nodes.size() < 2:
		var nbrs2: PackedInt32Array = _roadmap.neighbors[from_node]
		if nbrs2.is_empty():
			agent.clear_path()
			agent.next_decision_at = _time + stay_max_sec
			return
		nodes = PackedInt32Array([from_node, nbrs2[_rng.randi_range(0, nbrs2.size() - 1)]])
	agent.set_path(_roadmap.path_to_world(nodes))
	agent.next_decision_at = _time + 600.0


func _refresh_lod(force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam_pos := _camera.global_position
	var enter_r2 := render_distance * render_distance
	var exit_r := render_distance + lod_hysteresis_m
	var exit_r2 := exit_r * exit_r
	for i in range(_agents.size()):
		var agent: PedAgent = _agents[i]
		var dx := agent.position.x - cam_pos.x
		var dz := agent.position.z - cam_pos.z
		var d2 := dx * dx + dz * dz
		var want_near := agent.lod == PedAgent.Lod.NEAR
		if want_near:
			want_near = d2 <= exit_r2
		else:
			want_near = d2 <= enter_r2
		if force:
			want_near = d2 <= enter_r2
		if want_near:
			agent.lod = PedAgent.Lod.NEAR
			_ensure_visual(i, agent)
		else:
			agent.lod = PedAgent.Lod.CULLED
			_release_visual(agent)


func _update_frustum_visibility() -> void:
	_near_agents.clear()
	_skinned_count = 0
	if _camera == null or not is_instance_valid(_camera):
		return
	for agent in _agents:
		var vis := agent.visual as CrowdPedVisual
		if vis == null or not is_instance_valid(vis):
			continue
		var in_view := _camera.is_position_in_frustum(agent.position + Vector3(0.0, 1.1, 0.0))
		vis.visible = in_view
		vis.process_mode = Node.PROCESS_MODE_INHERIT if in_view else Node.PROCESS_MODE_DISABLED
		if in_view:
			_skinned_count += 1
			_near_agents.append(agent)


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
	for agent in _near_agents:
		if agent.visual == null or not is_instance_valid(agent.visual):
			continue
		if not agent.visual.visible:
			continue
		(agent.visual as CrowdPedVisual).sync_from_agent(agent)
