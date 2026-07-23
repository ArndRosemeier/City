## Pedestrian crowd: full skinned bodies when near, culled when far (no mid proxies).
class_name CrowdDirector
extends Node3D

const CrowdPedVisualScript := preload("res://scripts/city/crowd_ped_visual.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const TumbleSettleScript := preload("res://scripts/city/tumble_settle.gd")

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
## How far away pedestrians notice destruction and start sprinting away.
@export var flee_radius_m: float = 32.0
## Keep fleeing until at least this far from the player.
@export var flee_clear_distance_m: float = 200.0
@export var flee_speed_mul: float = 2.65
@export var flee_goal_min_m: float = 40.0
@export var flee_goal_max_m: float = 140.0
## Cap expensive flee repaths per physics frame (graph walks).
@export var flee_repaths_per_frame: int = 3
@export var flee_greedy_hops: int = 14

var _agents: Array[PedAgent] = []
var _near_agents: Array[PedAgent] = []
var _roadmap: PedRoadMap
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _time: float = 0.0
var _lod_accum: float = 0.0
var _ground_y: float = 1.0
var _skinned_count: int = 0
var _flee_repath_queue: Array[PedAgent] = []
var _threat_pos_cache: Vector3 = Vector3.ZERO
var _threat_pos_frame: int = -1


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
	_flee_repath_queue.clear()
	_skinned_count = 0
	for child in get_children():
		if child is RigidBody3D and String(child.name).begins_with("Corpse_"):
			child.queue_free()


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
	var live: Array = []
	for agent in _agents:
		if agent != null and not agent.dead:
			live.append(agent)
	return live


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


## Nearby living peds sprint away along the sidewalk graph.
func react_to_destruction(world_pos: Vector3, radius_m: float = -1.0) -> void:
	var radius := radius_m if radius_m > 0.0 else flee_radius_m
	var r2 := radius * radius
	var threat := _threat_position(world_pos)
	for agent in _agents:
		if agent == null or agent.dead:
			continue
		var dx := agent.position.x - world_pos.x
		var dz := agent.position.z - world_pos.z
		if dx * dx + dz * dz > r2:
			continue
		_start_flee(agent, threat)


func _start_flee(agent: PedAgent, danger: Vector3) -> void:
	agent.fleeing = true
	agent.flee_from = danger
	agent.next_decision_at = _time + 600.0
	## Keep the current route if any — only mark sprint. Repath is budgeted.
	if agent.state == PedAgent.State.WALK and agent.path_i < agent.waypoints.size():
		return
	_enqueue_flee_repath(agent)


func _threat_position(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	## Cache once per frame — hundreds of agents used to query the camera each.
	var frame := Engine.get_process_frames()
	if frame == _threat_pos_frame:
		return _threat_pos_cache
	_threat_pos_frame = frame
	if _camera != null and is_instance_valid(_camera):
		_threat_pos_cache = _camera.global_position
	else:
		_threat_pos_cache = fallback
	return _threat_pos_cache


func _enqueue_flee_repath(agent: PedAgent) -> void:
	if agent == null or agent.dead or agent.flee_repath_queued:
		return
	agent.flee_repath_queued = true
	_flee_repath_queue.append(agent)


func _drain_flee_repath_queue() -> void:
	var budget := maxi(flee_repaths_per_frame, 1)
	while budget > 0 and not _flee_repath_queue.is_empty():
		var agent: PedAgent = _flee_repath_queue.pop_front()
		if agent == null:
			continue
		agent.flee_repath_queued = false
		if agent.dead or not agent.fleeing:
			continue
		_assign_flee_path(agent)
		budget -= 1


func _assign_flee_path(agent: PedAgent) -> void:
	## Cheap greedy hop away from the player — no multi-sample BFS storm.
	if _roadmap == null or _roadmap.is_empty():
		return
	var from_node := _roadmap.nearest_node(agent.position)
	if from_node < 0:
		return
	agent.flee_from = _threat_position(agent.flee_from)
	var danger := agent.flee_from
	var path := PackedVector3Array()
	var node := from_node
	var prev := -1
	var hops := maxi(flee_greedy_hops, 4)
	for _i in hops:
		var nbrs: PackedInt32Array = _roadmap.neighbors[node]
		if nbrs.is_empty():
			break
		var best := -1
		var best_d2 := -1.0
		for n in nbrs:
			if n == prev:
				continue
			var p: Vector3 = _roadmap.positions[n]
			var d2 := Vector2(p.x - danger.x, p.z - danger.z).length_squared()
			if d2 > best_d2:
				best_d2 = d2
				best = n
		if best < 0:
			best = nbrs[_rng.randi_range(0, nbrs.size() - 1)]
		prev = node
		node = best
		path.append(_roadmap.positions[node])
	if path.is_empty():
		return
	agent.set_path(path)
	agent.next_decision_at = _time + 600.0


## Closest living ped along segment [from, to]. Empty if none.
## Keys: distance (float), point (Vector3), agent (PedAgent), index (int).
func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	var best_dist := INF
	var best: Dictionary = {}
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.05:
		return best
	var dir := seg / seg_len
	## Fat capsule: third-person aim is imprecise; thin AABBs miss constantly.
	const HIT_RADIUS := 0.85
	const HIT_HALF_H := 1.05
	for i in range(_agents.size()):
		var agent: PedAgent = _agents[i]
		if agent == null or agent.dead:
			continue
		var center := agent.position + Vector3(0.0, HIT_HALF_H * 0.85, 0.0)
		var hit := _segment_hits_capsule(from, dir, seg_len, center, HIT_RADIUS, HIT_HALF_H)
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


func kill_agent(agent: PedAgent, hit_point: Vector3, impulse_dir: Vector3) -> bool:
	if agent == null or agent.dead:
		return false
	agent.dead = true
	agent.clear_path()
	agent.next_decision_at = _time + 1.0e9
	var idx := _agents.find(agent)
	if idx < 0:
		return false
	agent.lod = PedAgent.Lod.NEAR
	_ensure_visual(idx, agent)
	var vis := agent.visual as CrowdPedVisual
	if vis == null or not is_instance_valid(vis):
		push_error("CrowdDirector: kill_agent missing visual")
		return false
	vis.visible = true
	vis.process_mode = Node.PROCESS_MODE_INHERIT
	vis.global_position = agent.position
	vis.rotation.y = agent.yaw
	vis.play_death()
	agent.visual = null

	var dir := impulse_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()

	var body_h := 1.7 * agent.body_scale
	var body_r := 0.28 * agent.body_scale
	var com := Vector3(0.0, body_h * 0.5, 0.0)

	var body := RigidBody3D.new()
	body.name = "Corpse_%d" % idx
	body.collision_layer = 2
	body.collision_mask = 1
	body.continuous_cd = true
	body.contact_monitor = false
	body.linear_damp = 0.4
	body.angular_damp = 0.5
	body.mass = 72.0 * agent.body_scale
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = com

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_r
	capsule.height = maxf(body_h - body_r * 2.0, body_r * 2.0)
	shape.shape = capsule
	shape.position = com
	body.add_child(shape)

	var keep_xf: Transform3D = vis.global_transform
	var parent_node: Node = vis.get_parent()
	if parent_node != null:
		parent_node.remove_child(vis)
	add_child(body)
	body.global_transform = keep_xf
	body.add_child(vis)
	vis.transform = Transform3D.IDENTITY

	## Same dramatic tumble as cars, scaled for a human body.
	var impulse := dir * 18.0 + Vector3.UP * 12.0
	var hit_offset := hit_point - body.global_position
	body.apply_impulse(impulse, hit_offset)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	body.apply_torque_impulse(side * 14.0 + dir * 6.0)
	## Upright death pose keeps the root near the ground.
	body.set_meta("tumble_clearance", 0.08)
	if get_tree() != null:
		get_tree().create_timer(4.5).timeout.connect(_freeze_corpse.bind(body))
	return true


func _freeze_corpse(body: RigidBody3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var clearance := float(body.get_meta("tumble_clearance", 0.08))
	TumbleSettleScript.freeze_lying_down(body, TumbleSettleScript.Kind.PEDESTRIAN, clearance)


## Vertical capsule vs segment. Radius is horizontal; half_height is along Y from center.
static func _segment_hits_capsule(
	from: Vector3,
	dir: Vector3,
	seg_len: float,
	center: Vector3,
	radius: float,
	half_height: float
) -> Dictionary:
	var to_c := center - from
	var t := to_c.dot(dir)
	t = clampf(t, 0.0, seg_len)
	var closest := from + dir * t
	var delta := closest - center
	var dy := absf(delta.y)
	var xz := Vector2(delta.x, delta.z).length()
	if dy > half_height + radius * 0.35:
		return {}
	var y_slack := 0.0
	if dy > half_height:
		y_slack = dy - half_height
	var radial := sqrt(xz * xz + y_slack * y_slack)
	if radial > radius:
		return {}
	return {"point": closest, "distance": t}


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
	_drain_flee_repath_queue()
	_simulate_agents(delta)
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		_refresh_lod(false)
	_update_frustum_visibility()
	_sync_near_visuals()


func _simulate_agents(delta: float) -> void:
	## Threat position once for the whole tick (not per fleeing agent).
	var threat := _threat_position()
	var clear_r2 := flee_clear_distance_m * flee_clear_distance_m
	for agent in _agents:
		if agent.dead:
			continue
		if agent.fleeing:
			agent.flee_from = threat
			var fdx := agent.position.x - threat.x
			var fdz := agent.position.z - threat.z
			if fdx * fdx + fdz * fdz >= clear_r2:
				agent.fleeing = false
				agent.flee_repath_queued = false
				agent.next_decision_at = _time + _rng.randf_range(rewalk_min_sec, rewalk_max_sec)
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
		var step := agent.move_speed(flee_speed_mul) * delta
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
	## Skip expensive nearest-node scans while sprinting away.
	if not agent.is_fleeing():
		_leave_carriageway_if_needed(agent)
	if agent.is_fleeing():
		_enqueue_flee_repath(agent)
		return
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
	if agent.is_fleeing():
		agent.next_decision_at = _time + 600.0
		_enqueue_flee_repath(agent)
		return
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
		if agent.dead:
			## Visual already reparented onto a RigidBody corpse.
			agent.lod = PedAgent.Lod.CULLED
			continue
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
		if agent.dead:
			continue
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
