## Pedestrian crowd on the voxel navigation stack: full skinned bodies when near, culled when
## far (no mid proxies).
##
## Every ped is a PedAgent body driven by a NavAgent, a NavMotor and the `pedestrian` profile,
## and the whole crowd shares one PedGoalProvider — NavGoalRequest carries the body, so one
## provider serves a thousand peds instead of one per ped. What the director owns is everything
## around that: spawning, the three nav LOD tiers, the near-tier capsules and crowd separation,
## the skinned visuals, panic, and the query budget the crowd is allowed to spend.
##
## The pavement this is handed is no longer walked. It supplies the goal provider with errand
## endpoints and with the crossings to use on the way; routing, heights and reachability all
## come from the span field, so there is no one ground height per district any more and no
## teleport onto the kerb when a ped ends up somewhere the flat plane did not allow.
class_name CrowdDirector
extends Node3D

const CrowdPedVisualScript := preload("res://scripts/city/crowd_ped_visual.gd")
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
## How far one flee goal asks to get from the threat. A threat is rarely left behind in a
## single corridor, so a partial one is walked and the goal re-evaluated from there.
@export var flee_goal_min_m: float = 40.0
@export var flee_goal_max_m: float = 140.0
## Cap flee goals handed out per physics frame, so a blast cannot make the whole crowd queue
## a path in the same tick.
@export var flee_repaths_per_frame: int = 3
## Each new visual instantiates an outfit scene (~10 ms cold, well under 1 ms once cached),
## so promotions are drained against a time budget rather than a fixed count. Budgeting per
## rendered frame, not per physics tick: a long frame runs up to 8 ticks, and 14 promotions
## landing in one frame measured as a 360 ms freeze.
@export var visual_create_budget_ms: float = 4.0
## Physics frames between ticks of a far-tier ped. Past 80 m its motion is a lerp along a
## corridor nobody can see, so stepping it every frame buys nothing; the skipped time is owed
## and paid on the next tick, so the walking speed is unchanged.
@export var far_tick_stride: int = 7
## Soft µs budget for `_simulate_agents` per physics frame. Surplus agents keep owed_delta
## and a rotating cursor spreads ticks so late indices are not starved when the street is dense.
@export var sim_budget_ms: float = 5.0
## How far outside the near band a ped is given its capsule. The motor needs the collider
## before NavLod switches it to the near tier, not in the same frame.
@export var collider_margin_m: float = 8.0
## Near-tier separation: peds with colliders nudge each other apart instead of overlapping.
@export var separation_radius_m: float = 0.9
@export var separation_strength: float = 0.7
## Neighbours one ped separates from per frame, so a dense knot stays bounded.
@export var separation_neighbours_max: int = 6
## Ambient path queries per second the whole crowd may cause. NavService serves 8 per frame
## for every consumer together, so a district's peds take a modest share of it.
@export var goal_queries_per_sec: float = 12.0
## Hand out no new goals while NavService already holds this many queries: undead, cars and
## the debug overlay share that queue, and a crowd must not be why they wait.
@export var queue_pause_size: int = 24
## Ped corridors fed to the F8 overlay at once.
@export var overlay_corridor_limit: int = 12
## How long a parked ped waits before asking the provider for work again.
@export var goal_retry_sec: float = 0.25

var _agents: Array[PedAgent] = []
var _near_agents: Array[PedAgent] = []
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _lod_accum: float = 0.0
var _skinned_count: int = 0

var _nav: NavService = null
var _profile: NavProfile = null
var _lod: NavLod = null
var _provider: PedGoalProvider = null
var _terrain: VoxelTerrain = null
var _overlay: NavDebugOverlay = null
## Corridors currently drawn in the overlay, so they can be taken back out again.
var _overlay_ids: Array[StringName] = []
## Near-tier bodies bucketed for separation: cell -> indices into `_agents`.
var _near_grid: Dictionary[Vector2i, PackedInt32Array] = {}
var _colliders_built: int = 0

var _flee_queue: Array[PedAgent] = []
## Agent indices waiting for a visual, oldest first.
var _pending_visuals: Array[int] = []
## Process frame the queue was last drained in, so extra physics ticks don't multiply it.
var _visual_drain_frame: int = -1
var _threat_pos_cache: Vector3 = Vector3.ZERO
var _threat_pos_frame: int = -1
## Rotating start index for the soft sim budget — keeps late agents from starving.
var _sim_cursor: int = 0


func setup(pavement: SidewalkMap, camera: Camera3D, seed_value: int = -1) -> void:
	clear_crowd()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_camera = camera
	_nav = NavService.instance()
	if not _nav.is_configured():
		push_error("CrowdDirector: NavService is not configured, so the crowd stays empty")
		return
	if not global_transform.is_equal_approx(Transform3D.IDENTITY):
		push_error(
			"CrowdDirector: %s is not at the world origin, and every consumer reads a ped's"
			% get_path()
			+ " Node3D position as a world position"
		)
	_profile = _nav.profile(NavProfile.Id.PEDESTRIAN)
	if _profile == null:
		return
	_lod = NavLod.new()
	_provider = PedGoalProvider.new()
	_configure_provider()
	_provider.setup(_nav, NavProfile.Id.PEDESTRIAN, _rng.randi())
	if _provider.bind_pavement(pavement) <= 0:
		return
	_terrain = _find_terrain()
	if _terrain == null:
		## Real in a live city, expected in a tool or test scene that has no CityRoot at all:
		## VoxelBodyMotion integrates the wish velocity as given, so a near-tier ped walks
		## through digs and holes instead of over them.
		push_warning(
			"CrowdDirector: %s — near-tier peds move without voxel collision"
			% (
				"no CityRoot in the city_root group"
				if _city_root() == null
				else "the CityRoot has no VoxelTerrain yet"
			)
		)
	_overlay = _find_overlay()
	_spawn_agents()
	_refresh_lod(true)
	print(
		"CrowdDirector: agents=%d %s skinned=%d render=%.0fm near=%.0fm terrain=%s"
		% [
			_agents.size(),
			_provider.describe_load(),
			_skinned_count,
			render_distance,
			_lod.near_radius_m,
			_terrain != null,
		]
	)


func clear_crowd() -> void:
	for ped in _agents:
		if ped == null:
			continue
		if ped.nav != null:
			ped.nav.dispose()
		_release_visual(ped)
		ped.queue_free()
	_agents.clear()
	_near_agents.clear()
	_flee_queue.clear()
	_pending_visuals.clear()
	_near_grid.clear()
	_forget_overlay_corridors()
	_skinned_count = 0
	for child in get_children():
		if child is RigidBody3D and String(child.name).begins_with("Corpse_"):
			child.queue_free()


func agent_count() -> int:
	return _agents.size()


func agent_at(index: int) -> PedAgent:
	if index < 0 or index >= _agents.size():
		push_error("CrowdDirector.agent_at: %d of %d" % [index, _agents.size()])
		return null
	return _agents[index]


## The one goal provider the whole crowd shares.
func goal_provider() -> PedGoalProvider:
	return _provider


func nav_lod() -> NavLod:
	return _lod


## Near-tier capsules built so far. They are never taken back, because NavMotor has no way to
## drop a collider, so this only ever grows to the number of peds the player has walked past.
func collider_count() -> int:
	return _colliders_built


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
		out[i] = _agents[i].global_position
	return out


func agents_for_occupancy() -> Array:
	var live: Array = []
	for ped in _agents:
		if ped != null and not ped.dead:
			live.append(ped)
	return live


## x=near, y=mid, z=far — the navigation LOD tiers.
func count_lod_tiers() -> Vector3i:
	var out := Vector3i.ZERO
	for ped in _agents:
		if ped == null or ped.dead:
			continue
		match ped.nav.tier():
			NavLod.Tier.NEAR:
				out.x += 1
			NavLod.Tier.MID:
				out.y += 1
			_:
				out.z += 1
	return out


# ---------------------------------------------------------------------------
# Panic
# ---------------------------------------------------------------------------

## Nearby living peds sprint away from the threat.
func react_to_destruction(world_pos: Vector3, radius_m: float = -1.0) -> void:
	var radius := radius_m if radius_m > 0.0 else flee_radius_m
	var r2 := radius * radius
	## Destruction panic still treats the player as the lasting threat to clear from.
	var threat := _threat_position(world_pos)
	for ped in _agents:
		if ped == null or ped.dead:
			continue
		var dx := ped.global_position.x - world_pos.x
		var dz := ped.global_position.z - world_pos.z
		if dx * dx + dz * dz > r2:
			continue
		_start_flee(ped, threat, flee_clear_distance_m)


## Scare peds near undead mages. threats = Array of Vector3.
func scare_from_threats(threats: Array, trigger_m: float, clear_m: float) -> void:
	if threats.is_empty():
		return
	var trigger_r2 := trigger_m * trigger_m
	for ped in _agents:
		if ped == null or ped.dead:
			continue
		var best := Vector3.INF
		var best_d2 := trigger_r2
		for t in threats:
			var tp: Vector3 = t as Vector3
			var dx := ped.global_position.x - tp.x
			var dz := ped.global_position.z - tp.z
			var d2 := dx * dx + dz * dz
			if d2 > best_d2:
				continue
			best_d2 = d2
			best = tp
		if best == Vector3.INF:
			continue
		_start_flee(ped, best, clear_m)


## Sprinting starts this frame; the corridor away from the threat is queued, because a blast
## that made three hundred peds ask for a path in one tick is what the budget exists for.
func _start_flee(ped: PedAgent, danger: Vector3, clear_m: float) -> void:
	ped.fleeing = true
	ped.flee_from = danger
	ped.flee_clear_m = clear_m if clear_m > 0.0 else flee_clear_distance_m
	ped.paused_until = 0.0
	if ped.flee_goal_queued:
		return
	ped.flee_goal_queued = true
	_flee_queue.append(ped)


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


func _drain_flee_queue() -> void:
	var budget := maxi(flee_repaths_per_frame, 1)
	while budget > 0 and not _flee_queue.is_empty():
		var ped: PedAgent = _flee_queue.pop_front()
		if ped == null:
			continue
		ped.flee_goal_queued = false
		if ped.dead or not ped.fleeing:
			continue
		ped.nav.set_goal(_provider.flee_goal(ped))
		budget -= 1


# ---------------------------------------------------------------------------
# Hit queries
# ---------------------------------------------------------------------------

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
		var ped: PedAgent = _agents[i]
		if ped == null or ped.dead:
			continue
		var center := ped.global_position + Vector3(0.0, HIT_HALF_H * 0.85, 0.0)
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
			"agent": ped,
			"index": i,
		}
	return best


## Nearest living ped within max_dist (XZ). Empty if none.
func find_nearest_agent(world_pos: Vector3, max_dist: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d2 := max_dist * max_dist
	for i in range(_agents.size()):
		var ped: PedAgent = _agents[i]
		if ped == null or ped.dead:
			continue
		var d2 := Vector2(
			ped.global_position.x - world_pos.x, ped.global_position.z - world_pos.z
		).length_squared()
		if d2 > best_d2:
			continue
		best_d2 = d2
		best = {"agent": ped, "index": i, "position": ped.global_position}
	return best


## Remove a ped with no corpse (undead conversion). Returns former world position.
func convert_agent_silent(ped: PedAgent) -> Vector3:
	if ped == null or ped.dead:
		return Vector3.INF
	var pos := ped.global_position
	_retire(ped)
	if ped.visual != null and is_instance_valid(ped.visual):
		ped.visual.queue_free()
	ped.visual = null
	ped.lod = PedAgent.Lod.CULLED
	return pos


func kill_agent(ped: PedAgent, hit_point: Vector3, impulse_dir: Vector3) -> bool:
	if ped == null or ped.dead:
		return false
	var idx := _agents.find(ped)
	if idx < 0:
		return false
	_retire(ped)
	ped.lod = PedAgent.Lod.NEAR
	_ensure_visual(idx, ped)
	var vis := ped.visual as CrowdPedVisual
	if vis == null or not is_instance_valid(vis):
		push_error("CrowdDirector: kill_agent missing visual")
		return false
	vis.visible = true
	vis.process_mode = Node.PROCESS_MODE_INHERIT
	vis.global_position = ped.global_position
	vis.rotation.y = ped.yaw
	vis.play_death()
	ped.visual = null

	var dir := impulse_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()

	var body_h := 1.7 * ped.body_scale
	var body_r := 0.28 * ped.body_scale
	var com := Vector3(0.0, body_h * 0.5, 0.0)

	var body := RigidBody3D.new()
	body.name = "Corpse_%d" % idx
	body.collision_layer = 2
	body.collision_mask = 1
	body.continuous_cd = true
	body.contact_monitor = false
	body.linear_damp = 0.4
	body.angular_damp = 0.5
	body.mass = 72.0 * ped.body_scale
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


## Out of the simulation for good: the nav agent is disposed so NavService stops serving a
## body nobody drives any more.
func _retire(ped: PedAgent) -> void:
	ped.dead = true
	ped.fleeing = false
	ped.flee_goal_queued = false
	ped.state = PedAgent.State.STAY
	if ped.nav != null:
		ped.nav.dispose()


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


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _configure_provider() -> void:
	_provider.walk_goal_min_m = walk_goal_min_m
	_provider.walk_goal_max_m = walk_goal_max_m
	_provider.stay_min_sec = stay_min_sec
	_provider.stay_max_sec = stay_max_sec
	_provider.rewalk_min_sec = rewalk_min_sec
	_provider.rewalk_max_sec = rewalk_max_sec
	_provider.flee_run_min_m = flee_goal_min_m
	_provider.flee_run_max_m = flee_goal_max_m
	_provider.goal_queries_per_sec = goal_queries_per_sec
	_provider.queue_pause_size = queue_pause_size


func _spawn_agents() -> void:
	var n := maxi(pedestrian_count, 0)
	_agents.resize(n)
	for i in range(n):
		var ped := PedAgent.new()
		ped.name = "Ped_%d" % i
		## Peds have never had a physics presence: cars, corpses and the player must keep
		## passing through them. The capsule the near tier adds is for VoxelBoxMover only.
		ped.collision_layer = 0
		ped.collision_mask = 0
		add_child(ped)
		ped.global_position = _provider.random_spawn()
		ped.last_pos = ped.global_position
		ped.yaw = _rng.randf_range(0.0, TAU)
		ped.female = _rng.randf() < 0.5
		ped.walk_tendency = clampf(_rng.randfn(walk_decision_chance, 0.04), 0.82, 0.99)
		ped.walk_speed = _rng.randf_range(1.15, 1.85)
		ped.body_scale = _rng.randf_range(0.92, 1.08)
		ped.outfit = PedOutfitScript.random(_rng, ped.female, PedOutfit.Faction.CIVILIAN)
		ped.lod = PedAgent.Lod.CULLED
		ped.motor = NavMotor.new()
		ped.motor.speed_mps = ped.walk_speed
		ped.motor.separation_weight = 1.0
		ped.nav = NavAgent.new()
		ped.nav.idle_retry_sec = goal_retry_sec
		ped.nav.setup(ped, NavProfile.Id.PEDESTRIAN, ped.motor, _provider, _lod)
		ped.nav.seed_rng(_rng.randi())
		## Staggered, so a fresh district does not ask for a thousand paths in one frame.
		ped.paused_until = _rng.randf_range(0.0, 0.8)
		_agents[i] = ped


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	simulate(delta)


## One step of the whole crowd. Public so a test or tool can drive it at a fixed step instead
## of at whatever rate the physics clock happens to run at.
func simulate(delta: float) -> void:
	if _agents.is_empty():
		return
	CityProfiler.set_counter("crowd_agents", _agents.size())
	CityProfiler.begin("crowd")
	_provider.advance(delta)
	CityProfiler.begin("crowd_repath")
	_drain_flee_queue()
	CityProfiler.end("crowd_repath")
	CityProfiler.begin("crowd_sim")
	_simulate_agents(delta)
	CityProfiler.end("crowd_sim")
	_lod_accum += delta
	if _lod_accum >= lod_interval_sec:
		_lod_accum = 0.0
		CityProfiler.begin("crowd_lod")
		_refresh_lod(false)
		CityProfiler.end("crowd_lod")
	_drain_pending_visuals()
	CityProfiler.begin("crowd_frustum")
	_update_frustum_visibility()
	CityProfiler.end("crowd_frustum")
	CityProfiler.begin("crowd_sync")
	_sync_near_visuals()
	CityProfiler.end("crowd_sync")
	CityProfiler.end("crowd")


func _simulate_agents(delta: float) -> void:
	var observer := _observer_position()
	var frame := Engine.get_physics_frames()
	var stride := maxi(far_tick_stride, 1)
	_apply_separation()
	var n := _agents.size()
	if n == 0:
		return
	## Always accumulate owed time / flee / colliders for everyone; only the nav.tick
	## work is soft-budgeted so a dense street cannot blow past ~sim_budget_ms.
	for i in range(n):
		var ped := _agents[i]
		if ped == null or ped.dead:
			continue
		_update_flee(ped)
		_sync_speed(ped)
		_ensure_collider(ped, observer)
		ped.owed_delta += delta
	var budget_us := int(maxf(sim_budget_ms, 0.5) * 1000.0)
	var deadline := Time.get_ticks_usec() + budget_us
	var start := _sim_cursor % n
	var ticked := 0
	for k in range(n):
		var i := (start + k) % n
		var ped := _agents[i]
		if ped == null or ped.dead:
			continue
		if ped.nav.tier() == NavLod.Tier.FAR and (frame + i) % stride != 0:
			continue
		var owed := ped.owed_delta
		ped.owed_delta = 0.0
		ped.nav.tick(owed, observer)
		_after_tick(ped)
		ticked += 1
		if Time.get_ticks_usec() >= deadline and ticked > 0:
			_sim_cursor = (i + 1) % n
			return
	_sim_cursor = (start + 1) % n


## What the LOD tiers are measured from. Without a camera the crowd keeps walking, at the
## coarsest tier, which is what a district streaming in before the player has one wants.
func _observer_position() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		return _camera.global_position
	return global_position


func _after_tick(ped: PedAgent) -> void:
	var pos := ped.global_position
	var moved := Vector3(pos.x - ped.last_pos.x, 0.0, pos.z - ped.last_pos.z)
	if moved.length_squared() > 0.000001:
		var dir := moved.normalized()
		ped.yaw = atan2(-dir.x, -dir.z)
	ped.last_pos = pos
	ped.state = PedAgent.State.WALK if ped.nav.has_corridor() else PedAgent.State.STAY


## Panic ends by distance, not by the goal: a flee goal can also be abandoned as unreachable,
## and a ped that stopped running has to stop sprinting too.
func _update_flee(ped: PedAgent) -> void:
	if not ped.fleeing:
		return
	var clear_m := ped.flee_clear_m if ped.flee_clear_m > 0.0 else flee_clear_distance_m
	var dx := ped.global_position.x - ped.flee_from.x
	var dz := ped.global_position.z - ped.flee_from.z
	if dx * dx + dz * dz < clear_m * clear_m:
		return
	ped.fleeing = false
	ped.flee_goal_queued = false
	ped.paused_until = _provider.now() + _rng.randf_range(rewalk_min_sec, rewalk_max_sec)


func _sync_speed(ped: PedAgent) -> void:
	var want := ped.move_speed(flee_speed_mul)
	if not is_equal_approx(ped.motor.speed_mps, want):
		ped.motor.speed_mps = want


## The near tier moves a ped through VoxelBoxMover, which needs a capsule to sweep. It is
## built a little outside the band so it exists before NavLod asks for it, and never removed:
## NavMotor has no way to give a collider back.
func _ensure_collider(ped: PedAgent, observer: Vector3) -> void:
	if ped.has_collider():
		return
	var reach := _lod.near_radius_m + _lod.hysteresis_m + collider_margin_m
	var dx := ped.global_position.x - observer.x
	var dz := ped.global_position.z - observer.z
	if dx * dx + dz * dz > reach * reach:
		return
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28 * ped.body_scale
	shape.height = maxf(1.7 * ped.body_scale, shape.radius * 2.0)
	var capsule := CollisionShape3D.new()
	capsule.name = "Capsule"
	capsule.shape = shape
	capsule.position = Vector3(0.0, shape.height * 0.5, 0.0)
	ped.add_child(capsule)
	var motion := VoxelBodyMotion.new()
	motion.setup(_terrain, _profile.max_step * _nav.voxel_size())
	ped.capsule = capsule
	ped.motion = motion
	ped.motor.attach_collider(ped, capsule, motion)
	if _terrain == null:
		## Nothing to collide against: VoxelBodyMotion integrates the velocity as given, so
		## gravity would pull the body through a floor that is not there.
		ped.motor.gravity = 0.0
	_colliders_built += 1


## Near-tier peds push each other apart. Only they have colliders, so only they can resolve
## the push; bucketing by separation radius keeps a dense knot from going quadratic.
func _apply_separation() -> void:
	if separation_strength <= 0.0 or separation_radius_m <= 0.0:
		return
	_near_grid.clear()
	var cell := separation_radius_m
	for i in range(_agents.size()):
		var ped := _agents[i]
		if ped == null or ped.dead or ped.nav.tier() != NavLod.Tier.NEAR:
			continue
		var key := Vector2i(
			floori(ped.global_position.x / cell), floori(ped.global_position.z / cell)
		)
		var bucket: PackedInt32Array = _near_grid.get(key, PackedInt32Array())
		bucket.append(i)
		_near_grid[key] = bucket
	if _near_grid.is_empty():
		return
	var r2 := separation_radius_m * separation_radius_m
	for key: Vector2i in _near_grid.keys():
		for index: int in _near_grid[key]:
			var ped := _agents[index]
			var push := _separation_push(ped, key, r2)
			if push.length_squared() > 0.000001:
				ped.motor.add_separation(push * separation_strength)


func _separation_push(ped: PedAgent, key: Vector2i, r2: float) -> Vector3:
	var push := Vector3.ZERO
	var seen := 0
	var pos := ped.global_position
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var bucket: PackedInt32Array = _near_grid.get(
				key + Vector2i(ox, oz), PackedInt32Array()
			)
			for index: int in bucket:
				var other := _agents[index]
				if other == ped:
					continue
				var dx := pos.x - other.global_position.x
				var dz := pos.z - other.global_position.z
				var d2 := dx * dx + dz * dz
				if d2 > r2 or d2 < 0.000001:
					continue
				var d := sqrt(d2)
				push += Vector3(dx / d, 0.0, dz / d) * (1.0 - d / separation_radius_m)
				seen += 1
				if seen >= separation_neighbours_max:
					return push
	return push


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
		var ped: PedAgent = _agents[i]
		if ped.dead:
			## Visual already reparented onto a RigidBody corpse.
			ped.lod = PedAgent.Lod.CULLED
			continue
		var dx := ped.global_position.x - cam_pos.x
		var dz := ped.global_position.z - cam_pos.z
		var d2 := dx * dx + dz * dz
		var want_near := ped.lod == PedAgent.Lod.NEAR
		if want_near:
			want_near = d2 <= exit_r2
		else:
			want_near = d2 <= enter_r2
		if force:
			want_near = d2 <= enter_r2
		if want_near:
			ped.lod = PedAgent.Lod.NEAR
			_queue_visual(i, ped)
		else:
			ped.lod = PedAgent.Lod.CULLED
			_release_visual(ped)
	_refresh_overlay_corridors()


func _update_frustum_visibility() -> void:
	_near_agents.clear()
	_skinned_count = 0
	if _camera == null or not is_instance_valid(_camera):
		return
	for ped in _agents:
		if ped.dead:
			continue
		var vis := ped.visual as CrowdPedVisual
		if vis == null or not is_instance_valid(vis):
			continue
		var in_view := _camera.is_position_in_frustum(ped.global_position + Vector3(0.0, 1.1, 0.0))
		vis.visible = in_view
		vis.process_mode = Node.PROCESS_MODE_INHERIT if in_view else Node.PROCESS_MODE_DISABLED
		if in_view:
			_skinned_count += 1
			_near_agents.append(ped)


func _queue_visual(agent_index: int, ped: PedAgent) -> void:
	if ped.visual_queued:
		return
	if ped.visual != null and is_instance_valid(ped.visual):
		return
	ped.visual_queued = true
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
		var ped := _agents[index]
		ped.visual_queued = false
		if ped.dead or ped.lod != PedAgent.Lod.NEAR:
			continue
		_ensure_visual(index, ped)
		if Time.get_ticks_usec() >= deadline:
			return


func _ensure_visual(agent_index: int, ped: PedAgent) -> void:
	if ped.visual != null and is_instance_valid(ped.visual):
		return
	CityProfiler.begin("crowd_visual_new")
	var visual: CrowdPedVisual = CrowdPedVisualScript.new()
	visual.name = "NearPed_%d" % agent_index
	add_child(visual)
	visual.bind_agent(agent_index, ped.female, ped.body_scale, ped.outfit)
	ped.visual = visual
	CityProfiler.end("crowd_visual_new")


func _release_visual(ped: PedAgent) -> void:
	if ped.visual == null:
		return
	if is_instance_valid(ped.visual):
		ped.visual.queue_free()
	ped.visual = null


func _sync_near_visuals() -> void:
	for ped in _near_agents:
		if ped.visual == null or not is_instance_valid(ped.visual):
			continue
		if not ped.visual.visible:
			continue
		(ped.visual as CrowdPedVisual).sync_from_agent(ped)


# ---------------------------------------------------------------------------
# Wiring found in the tree
# ---------------------------------------------------------------------------

## The live terrain, found the way NavDirtyTracker finds the live brush: through the city_root
## group. A tool or test scene without a CityRoot gets none.
func _find_terrain() -> VoxelTerrain:
	var node := _city_root()
	if node == null:
		return null
	var root := node as CityRoot
	if root == null:
		push_error(
			"CrowdDirector: the city_root group holds %s, which is not a CityRoot" % node.name
		)
		return null
	return root.voxel_terrain()


func _find_overlay() -> NavDebugOverlay:
	var root := _city_root()
	if root == null:
		return null
	for child: Node in root.get_children():
		var overlay := child as NavDebugOverlay
		if overlay != null:
			return overlay
	return null


func _city_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"city_root")


## Feed the F8 overlay a bounded set of live ped corridors — enough to see how the crowd is
## routing, few enough that the corridor layer stays cheap. Refreshed on the LOD cadence
## rather than per repath, because a thousand path callbacks would each redraw it.
func _refresh_overlay_corridors() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if not _overlay.is_enabled():
		_forget_overlay_corridors()
		return
	var shown: Array[StringName] = []
	for ped in _agents:
		if shown.size() >= overlay_corridor_limit:
			break
		if ped == null or ped.dead or ped.nav.tier() != NavLod.Tier.NEAR:
			continue
		if not ped.nav.has_corridor():
			continue
		var result := ped.nav.last_result()
		if result == null or not result.is_usable():
			continue
		var id := StringName("ped_%d" % ped.nav.agent_id())
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
