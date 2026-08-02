## City traffic on the voxel navigation stack: full catalog visuals when near, culled when far
## (no mid box proxies).
##
## Every car is a VehicleAgent body driven by a NavAgent, a VehicleMotor and the `car` profile,
## and the whole district's traffic shares one VehicleGoalProvider. What the director owns is
## everything around that: spawning, the visual LOD and its budgeted promotion queue, panic,
## wrecks, and yielding to pedestrians on a crossing.
##
## Cars are the last consumer to move off the planner graphs, and the only one that keeps a
## graph at all. `CarLaneGraph` is not a route it drives — it is the lane semantics the span
## field cannot carry: which side of the carriageway runs which way, and which turns a junction
## allows. Routing between two lane points is span A* like everything else, which is what buys
## the new behaviour: blow a hole in a road and the traffic reroutes around it, and the lane
## points over the hole go out of service until it is filled in.
class_name VehicleDirector
extends Node3D

const VehicleAgentScript := preload("res://scripts/vehicles/vehicle_agent.gd")
const VehicleMotorScript := preload("res://scripts/vehicles/vehicle_motor.gd")
const VehicleVisualScript := preload("res://scripts/vehicles/vehicle_visual.gd")
const VehicleCatalogScript := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleGoalProviderScript := preload("res://scripts/vehicles/vehicle_goal_provider.gd")
const TumbleSettleScript := preload("res://scripts/city/tumble_settle.gd")

@export var vehicle_count: int = 48
## Full vehicle render distance. Beyond this: not drawn.
@export var render_distance: float = 120.0
@export var lod_hysteresis_m: float = 18.0
@export var trip_min_m: float = 70.0
@export var trip_max_m: float = 240.0
@export var lod_interval_sec: float = 0.5
@export var cruise_speed_min: float = 7.0
@export var cruise_speed_max: float = 12.0
@export var turn_rate: float = 3.5
@export var crossing_occupancy_interval_sec: float = 0.12
## How far away cars notice destruction and floor it away.
@export var flee_radius_m: float = 40.0
## Keep fleeing until at least this far from the threat.
@export var flee_clear_distance_m: float = 200.0
@export var flee_speed_mul: float = 1.9
@export var flee_goal_min_m: float = 80.0
@export var flee_goal_max_m: float = 260.0
## Cap flee goals handed out per physics frame, so a blast cannot make every car queue a path
## in the same tick.
@export var flee_goals_per_frame: int = 2
## A new visual instantiates the car scene plus one outfit scene per passenger, so promotions
## are drained against a time budget, once per rendered frame (a long frame runs several
## physics ticks, which would otherwise multiply the budget).
@export var visual_create_budget_ms: float = 4.0
## Physics frames between ticks of a far-tier car. Past the mid band its motion is a lerp along
## a corridor nobody can see; the skipped time is owed and paid on the next tick, so the
## driving speed is unchanged.
@export var far_tick_stride: int = 4
## Ambient path queries per second the whole district's traffic may cause.
@export var goal_queries_per_sec: float = 8.0
## Hand out no new goals while NavService already holds this many queries.
@export var queue_pause_size: int = 24
## Car corridors fed to the F8 overlay at once.
@export var overlay_corridor_limit: int = 8

var _agents: Array[VehicleAgent] = []
var _drawn_agents: Array[VehicleAgent] = []
## Agent indices waiting for a visual, oldest first.
var _pending_visuals: Array[int] = []
## Process frame the queue was last drained in, so extra physics ticks don't multiply it.
var _visual_drain_frame: int = -1

var _nav: NavService = null
var _lod: NavLod = null
var _provider: VehicleGoalProvider = null
var _lanes: CarLaneGraph = null
var _sidewalks: SidewalkMap = null
var _crowd: CrowdDirector = null
var _overlay: NavDebugOverlay = null
var _overlay_ids: Array[StringName] = []

var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _lod_accum: float = 0.0
var _occupancy_accum: float = 0.0
var _drawn_count: int = 0
var _flee_queue: Array[VehicleAgent] = []
var _threat_pos_cache: Vector3 = Vector3.ZERO
var _threat_pos_frame: int = -1


func setup(topology: StreetTopology, camera: Camera3D, seed_value: int = -1) -> void:
	clear_vehicles()
	if seed_value >= 0:
		_rng.seed = seed_value + 917
	else:
		_rng.randomize()
	_camera = camera
	_nav = NavService.instance()
	if not _nav.is_configured():
		push_error("VehicleDirector: NavService is not configured, so traffic stays empty")
		return
	if not global_transform.is_equal_approx(Transform3D.IDENTITY):
		push_error(
			"VehicleDirector: %s is not at the world origin, and every consumer reads a car's"
			% get_path()
			+ " Node3D position as a world position"
		)
	if _nav.profile(NavProfile.Id.CAR) == null:
		return
	if topology == null or not topology.is_ready():
		push_error("VehicleDirector: no street topology — traffic disabled")
		return
	_lanes = topology.lanes
	_sidewalks = topology.sidewalks
	VehicleCatalogScript.reload()
	if not VehicleCatalogScript.is_ready():
		push_error("VehicleDirector: VehicleCatalog not ready — traffic disabled")
		return
	_lod = NavLod.new()
	_provider = VehicleGoalProviderScript.new()
	_configure_provider()
	_provider.setup(_nav, NavProfile.Id.CAR, _rng.randi())
	if _provider.bind_lanes(_lanes) <= 0:
		return
	_overlay = _find_overlay()
	_spawn_agents()
	_refresh_lod(true)
	print(
		"VehicleDirector: agents=%d %s catalog=%d render=%.0fm"
		% [
			_agents.size(),
			_provider.describe_load(),
			VehicleCatalogScript.count(),
			render_distance,
		]
	)


func bind_crowd(crowd: CrowdDirector) -> void:
	_crowd = crowd


func clear_vehicles() -> void:
	for agent in _agents:
		if agent == null:
			continue
		if agent.nav != null:
			agent.nav.dispose()
		_release_visual(agent)
		agent.queue_free()
	_agents.clear()
	_drawn_agents.clear()
	_flee_queue.clear()
	_pending_visuals.clear()
	_forget_overlay_corridors()
	_drawn_count = 0
	for child in get_children():
		if child is RigidBody3D and String(child.name).begins_with("Wreck_"):
			child.queue_free()


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func vehicle_live_count() -> int:
	return _agents.size()


func agent_at(index: int) -> VehicleAgent:
	if index < 0 or index >= _agents.size():
		push_error("VehicleDirector.agent_at: %d of %d" % [index, _agents.size()])
		return null
	return _agents[index]


func sample_agent_position(index: int = 0) -> Vector3:
	if index < 0 or index >= _agents.size():
		return Vector3.ZERO
	return _agents[index].global_position


## The one goal provider the whole district's traffic shares.
func goal_provider() -> VehicleGoalProvider:
	return _provider


func lane_graph() -> CarLaneGraph:
	return _lanes


func nav_lod() -> NavLod:
	return _lod


## x=near, y=mid, z=far — the navigation LOD tiers, matching CrowdDirector. For how many cars
## are actually on screen, ask `drawn_count`.
func count_lod_tiers() -> Vector3i:
	var out := Vector3i.ZERO
	for agent in _agents:
		if agent == null or agent.wrecked:
			continue
		match agent.nav.tier():
			NavLod.Tier.NEAR:
				out.x += 1
			NavLod.Tier.MID:
				out.y += 1
			_:
				out.z += 1
	return out


## Cars with a visual the camera can currently see.
func drawn_count() -> int:
	return _drawn_count


# ---------------------------------------------------------------------------
# Panic and destruction
# ---------------------------------------------------------------------------

## Nearby live cars accelerate away, and the lanes over the damage go back up for re-testing:
## the span field will have lost the carriageway under a crater, and the lane graph only finds
## that out by looking.
func react_to_destruction(world_pos: Vector3, radius_m: float = -1.0) -> void:
	var radius := radius_m if radius_m > 0.0 else flee_radius_m
	var threat := _threat_position(world_pos)
	_invalidate_lanes_near(world_pos, radius)
	var r2 := radius * radius
	for agent in _agents:
		if agent == null or agent.wrecked:
			continue
		var dx := agent.global_position.x - world_pos.x
		var dz := agent.global_position.z - world_pos.z
		if dx * dx + dz * dz > r2:
			continue
		_start_flee(agent, threat)


## Lane points over a changed region come back into service, and any car whose remaining drive
## crosses it plans again rather than driving into a road that may no longer be there.
func _invalidate_lanes_near(world_pos: Vector3, radius_m: float) -> void:
	if _lanes == null or _lanes.is_empty():
		return
	var extent := Vector3(radius_m, 0.0, radius_m)
	var min_world := world_pos - extent
	var max_world := world_pos + extent
	if _lanes.invalidate_box(min_world, max_world) <= 0:
		return
	for agent in _agents:
		if agent == null or agent.wrecked or agent.route.is_empty():
			continue
		if _lanes.route_crosses_box(agent.route, min_world, max_world):
			agent.clear_route()


func _start_flee(agent: VehicleAgent, danger: Vector3) -> void:
	agent.fleeing = true
	agent.flee_from = danger
	agent.flee_clear_m = flee_clear_distance_m
	agent.paused_until = 0.0
	if agent.flee_goal_queued:
		return
	agent.flee_goal_queued = true
	_flee_queue.append(agent)


func _drain_flee_queue() -> void:
	var budget := maxi(flee_goals_per_frame, 1)
	while budget > 0 and not _flee_queue.is_empty():
		var agent: VehicleAgent = _flee_queue.pop_front()
		if agent == null:
			continue
		agent.flee_goal_queued = false
		if agent.wrecked or not agent.fleeing:
			continue
		var goal := _provider.flee_goal(agent)
		budget -= 1
		if goal == null:
			## No open lane to run to. The car stays put rather than bolting across whatever
			## open ground the span field would happily route it over.
			continue
		agent.nav.set_goal(goal)


## Panic ends by distance, not by the goal: a flee goal can also be abandoned as unreachable,
## and a car that stopped running has to stop flooring it too.
func _update_flee(agent: VehicleAgent) -> void:
	if not agent.fleeing:
		return
	var clear_m := agent.flee_clear_m if agent.flee_clear_m > 0.0 else flee_clear_distance_m
	agent.flee_from = _threat_position(agent.flee_from)
	var dx := agent.global_position.x - agent.flee_from.x
	var dz := agent.global_position.z - agent.flee_from.z
	if dx * dx + dz * dz < clear_m * clear_m:
		return
	agent.fleeing = false
	agent.flee_goal_queued = false


func _threat_position(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	## Cache once per frame — every agent used to query the camera itself.
	var frame := Engine.get_process_frames()
	if frame == _threat_pos_frame:
		return _threat_pos_cache
	_threat_pos_frame = frame
	if _camera != null and is_instance_valid(_camera):
		_threat_pos_cache = _camera.global_position
	else:
		_threat_pos_cache = fallback
	return _threat_pos_cache


# ---------------------------------------------------------------------------
# Hit queries and wrecks
# ---------------------------------------------------------------------------

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
		var center := agent.global_position + Vector3(0.0, half.y, 0.0)
		if agent.visual != null and is_instance_valid(agent.visual):
			var vis := agent.visual as VehicleVisual
			if vis != null:
				half = vis.body_half_extents() * 1.15
				center = agent.global_position + vis.body_center_offset()
		var hit := _segment_hits_oriented_box(from, to, center, agent.yaw, half)
		if hit.is_empty():
			## Fat cylinder fallback so glancing aim still registers.
			hit = _segment_hits_cylinder(
				from, dir, seg_len, center, maxf(half.x, half.z) * 1.05, half.y
			)
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
	var idx := _agents.find(agent)
	if idx < 0:
		return false
	agent.wrecked = true
	agent.fleeing = false
	agent.flee_goal_queued = false
	agent.clear_route()
	if agent.nav != null:
		agent.nav.dispose()
	agent.lod = VehicleAgent.Lod.NEAR
	_ensure_visual(idx, agent)
	var vis := agent.visual as VehicleVisual
	if vis == null or not is_instance_valid(vis):
		push_error("VehicleDirector: wreck_agent missing visual")
		return false
	vis.visible = true
	vis.process_mode = Node.PROCESS_MODE_INHERIT
	vis.sync_pose(agent.global_position, agent.yaw)
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
	body.set_meta(
		"tumble_clearance", maxf(vis.body_half_extents().x, vis.body_half_extents().y) * 1.05
	)
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


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _configure_provider() -> void:
	_provider.trip_min_m = trip_min_m
	_provider.trip_max_m = trip_max_m
	_provider.flee_run_min_m = flee_goal_min_m
	_provider.flee_run_max_m = flee_goal_max_m
	_provider.goal_queries_per_sec = goal_queries_per_sec
	_provider.queue_pause_size = queue_pause_size


func _spawn_agents() -> void:
	var n := maxi(vehicle_count, 0)
	_agents.resize(n)
	for i in range(n):
		var entry := VehicleCatalogScript.pick(_rng)
		if entry.is_empty():
			push_error("VehicleDirector: catalog.pick failed at agent %d" % i)
			_agents.resize(i)
			return
		var catalog_id := str(entry.get("id", ""))
		if catalog_id == "":
			push_error("VehicleDirector: catalog entry missing id")
			_agents.resize(i)
			return
		var agent := VehicleAgentScript.new()
		agent.name = "Car_%d" % i
		add_child(agent)
		var spawn: Dictionary = _provider.random_spawn()
		agent.global_position = spawn["position"]
		var heading: Vector3 = spawn["heading"]
		agent.yaw = atan2(-heading.x, -heading.z)
		agent.catalog_id = catalog_id
		agent.cruise_speed = _rng.randf_range(cruise_speed_min, cruise_speed_max)
		agent.passenger_count = (
			1 + _rng.randi() % 3
			if str(entry.get("kind", "car")) == "van"
			else 1 + (_rng.randi() % 2)
		)
		agent.lod = VehicleAgent.Lod.CULLED
		agent.motor = VehicleMotorScript.new()
		agent.motor.speed_mps = agent.cruise_speed
		agent.motor.turn_rate = turn_rate
		## A car is wider than a person and does not have to stop dead on a lane point it is
		## about to drive straight through.
		agent.motor.waypoint_radius_m = 1.2
		agent.motor.arrive_radius_m = 1.5
		agent.motor.bind_lanes(_lanes)
		agent.nav = NavAgent.new()
		agent.nav.setup(agent, NavProfile.Id.CAR, agent.motor, _provider, _lod)
		agent.nav.seed_rng(_rng.randi())
		## Staggered, so a fresh district does not ask for every drive in one frame.
		agent.paused_until = _rng.randf_range(0.0, 1.2)
		_agents[i] = agent


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	simulate(delta)


## One step of the whole district's traffic. Public so a test or tool can drive it at a fixed
## step instead of at whatever rate the physics clock happens to run at.
func simulate(delta: float) -> void:
	if _agents.is_empty():
		return
	CityProfiler.set_counter("vehicle_agents", _agents.size())
	CityProfiler.begin("vehicles")
	_provider.advance(delta)
	_lanes.advance(delta)
	CityProfiler.begin("vehicle_repath")
	_drain_flee_queue()
	CityProfiler.end("vehicle_repath")
	_occupancy_accum += delta
	if _occupancy_accum >= crossing_occupancy_interval_sec:
		_occupancy_accum = 0.0
		CityProfiler.begin("vehicle_occupancy")
		_refresh_crossing_occupancy()
		CityProfiler.end("vehicle_occupancy")
	CityProfiler.begin("vehicle_sim")
	_simulate_agents(delta)
	CityProfiler.end("vehicle_sim")
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		CityProfiler.begin("vehicle_lod")
		_refresh_lod(false)
		CityProfiler.end("vehicle_lod")
	_drain_pending_visuals()
	CityProfiler.begin("vehicle_frustum")
	_update_frustum_visibility()
	CityProfiler.end("vehicle_frustum")
	CityProfiler.begin("vehicle_sync")
	_sync_drawn_visuals()
	CityProfiler.end("vehicle_sync")
	CityProfiler.end("vehicles")


func _refresh_crossing_occupancy() -> void:
	if _sidewalks == null or _crowd == null:
		return
	_sidewalks.refresh_occupancy(_crowd.agents_for_occupancy())


func _simulate_agents(delta: float) -> void:
	var observer := _observer_position()
	var frame := Engine.get_physics_frames()
	var stride := maxi(far_tick_stride, 1)
	for i in range(_agents.size()):
		var agent := _agents[i]
		if agent == null or agent.wrecked:
			continue
		_update_flee(agent)
		_sync_speed(agent)
		_update_yield(agent)
		agent.owed_delta += delta
		if agent.nav.tier() == NavLod.Tier.FAR and (frame + i) % stride != 0:
			continue
		var owed := agent.owed_delta
		agent.owed_delta = 0.0
		agent.nav.tick(owed, observer)


## What the LOD tiers are measured from. Without a camera the traffic keeps driving, at the
## coarsest tier, which is what a district streaming in before the player has one wants.
func _observer_position() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		return _camera.global_position
	return global_position


func _sync_speed(agent: VehicleAgent) -> void:
	var want := agent.drive_speed(flee_speed_mul)
	if not is_equal_approx(agent.motor.speed_mps, want):
		agent.motor.speed_mps = want


## Stop short of a crossing somebody is standing on. The corridor is kept, so the car resumes
## from where it stopped rather than re-planning every time a ped steps off the kerb.
func _update_yield(agent: VehicleAgent) -> void:
	if _sidewalks == null or _sidewalks.occupied_crossing_count() == 0:
		agent.motor.stopped = false
		return
	var ahead := agent.motor.next_point()
	if ahead == Vector3.INF:
		agent.motor.stopped = false
		return
	agent.motor.stopped = _sidewalks.yielding_for_car(agent.global_position, ahead)


# ---------------------------------------------------------------------------
# Visual LOD
# ---------------------------------------------------------------------------

func _refresh_lod(force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam_pos := _camera.global_position
	var enter_r2 := render_distance * render_distance
	var exit_r := render_distance + lod_hysteresis_m
	var exit_r2 := exit_r * exit_r
	for i in range(_agents.size()):
		var agent: VehicleAgent = _agents[i]
		if agent.wrecked:
			## Visual already reparented onto a RigidBody wreck.
			agent.lod = VehicleAgent.Lod.CULLED
			continue
		var dx := agent.global_position.x - cam_pos.x
		var dz := agent.global_position.z - cam_pos.z
		var d2 := dx * dx + dz * dz
		var want_near := d2 <= (exit_r2 if agent.lod == VehicleAgent.Lod.NEAR else enter_r2)
		if force:
			want_near = d2 <= enter_r2
		if want_near:
			agent.lod = VehicleAgent.Lod.NEAR
			_queue_visual(i, agent)
		else:
			agent.lod = VehicleAgent.Lod.CULLED
			_release_visual(agent)
	_refresh_overlay_corridors()


func _update_frustum_visibility() -> void:
	_drawn_agents.clear()
	_drawn_count = 0
	if _camera == null or not is_instance_valid(_camera):
		return
	for agent in _agents:
		if agent.wrecked:
			continue
		var vis := agent.visual as VehicleVisual
		if vis == null or not is_instance_valid(vis):
			continue
		var in_view := _camera.is_position_in_frustum(
			agent.global_position + Vector3(0.0, 1.0, 0.0)
		)
		vis.visible = in_view
		vis.process_mode = Node.PROCESS_MODE_INHERIT if in_view else Node.PROCESS_MODE_DISABLED
		if in_view:
			_drawn_count += 1
			_drawn_agents.append(agent)


func _queue_visual(agent_index: int, agent: VehicleAgent) -> void:
	if agent.visual_queued:
		return
	if agent.visual != null and is_instance_valid(agent.visual):
		return
	agent.visual_queued = true
	_pending_visuals.append(agent_index)


## Always makes at least one so the queue drains, then stops once over budget.
func _drain_pending_visuals() -> void:
	if _pending_visuals.is_empty():
		return
	var frame := Engine.get_process_frames()
	if frame == _visual_drain_frame:
		return
	_visual_drain_frame = frame
	var deadline := Time.get_ticks_usec() + int(visual_create_budget_ms * 1000.0)
	while not _pending_visuals.is_empty():
		var index: int = _pending_visuals.pop_front()
		if index < 0 or index >= _agents.size():
			continue
		var agent := _agents[index]
		agent.visual_queued = false
		if agent.wrecked or agent.lod != VehicleAgent.Lod.NEAR:
			continue
		_ensure_visual(index, agent)
		if Time.get_ticks_usec() >= deadline:
			return


func _ensure_visual(agent_index: int, agent: VehicleAgent) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if agent.visual != null and is_instance_valid(agent.visual):
		return
	var entry := VehicleCatalogScript.entry_by_id(agent.catalog_id)
	if entry.is_empty():
		push_error("VehicleDirector: no catalog entry for '%s'" % agent.catalog_id)
		return
	CityProfiler.begin("vehicle_visual_new")
	var visual: VehicleVisual = VehicleVisualScript.new()
	visual.name = "NearVehicle_%d" % agent_index
	add_child(visual)
	visual.setup(entry, agent.passenger_count, agent_index * 97 + 3)
	if not visual.ready_visual:
		push_error(
			"VehicleDirector: visual setup failed for agent %d (%s)"
			% [agent_index, agent.catalog_id]
		)
		visual.queue_free()
		CityProfiler.end("vehicle_visual_new")
		return
	visual.sync_pose(agent.global_position, agent.yaw)
	agent.visual = visual
	CityProfiler.end("vehicle_visual_new")


func _release_visual(agent: VehicleAgent) -> void:
	if agent.visual == null:
		return
	if is_instance_valid(agent.visual):
		agent.visual.queue_free()
	agent.visual = null


func _sync_drawn_visuals() -> void:
	for agent in _drawn_agents:
		if agent.visual == null or not is_instance_valid(agent.visual):
			continue
		if not agent.visual.visible:
			continue
		(agent.visual as VehicleVisual).sync_pose(agent.global_position, agent.yaw)


# ---------------------------------------------------------------------------
# Wiring found in the tree
# ---------------------------------------------------------------------------

func _find_overlay() -> NavDebugOverlay:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.get_first_node_in_group(&"city_root")
	if root == null:
		return null
	for child: Node in root.get_children():
		var overlay := child as NavDebugOverlay
		if overlay != null:
			return overlay
	return null


## Feed the F8 overlay a bounded set of live car corridors, on the LOD cadence rather than per
## repath: seeing where the traffic thinks the road is is the point of the overlay for cars.
func _refresh_overlay_corridors() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if not _overlay.is_enabled():
		_forget_overlay_corridors()
		return
	var shown: Array[StringName] = []
	for agent in _agents:
		if shown.size() >= overlay_corridor_limit:
			break
		if agent == null or agent.wrecked or agent.nav.tier() == NavLod.Tier.FAR:
			continue
		if not agent.nav.has_corridor():
			continue
		var result := agent.nav.last_result()
		if result == null or not result.is_usable():
			continue
		var id := StringName("car_%d" % agent.nav.agent_id())
		_overlay.set_corridor(id, result)
		shown.append(id)
	for id: StringName in _overlay_ids:
		if not shown.has(id):
			_overlay.clear_corridor(id)
	_overlay_ids = shown


func _forget_overlay_corridors() -> void:
	if _overlay_ids.is_empty():
		return
	if _overlay != null and is_instance_valid(_overlay):
		for id: StringName in _overlay_ids:
			_overlay.clear_corridor(id)
	_overlay_ids.clear()
