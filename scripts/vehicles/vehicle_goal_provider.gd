## Where the traffic is going, as one NavGoalProvider for every car in a district.
##
## A drive is a route through `CarLaneGraph` and the car walks one NavGoal per lane point, the
## same shape as a pedestrian errand. That split is what lets cars keep lane semantics while
## giving up their own pathfinder: the lane graph decides *which side of which street* the car
## is allowed to be on and which turns exist, and NavService decides how to get from one lane
## point to the next over whatever spans are actually there. Anti-U-turn is not a rule the
## driver applies any more — the lane graph has no edge to reverse along.
##
## Destruction reaches the lanes here. A lane point with no car-sized span under it is a road
## that is not there, so it is closed and the drive re-planned; nothing else in the stack would
## ever notice, because the span field is perfectly happy to route a car around a hole while
## the lane graph goes on insisting there is a carriageway over it.
class_name VehicleGoalProvider
extends NavGoalProvider

const NavGoalScript := preload("res://scripts/city/nav_goal.gd")

## Routes drawn before a car gives up and waits.
const TRIP_TRIES := 4
## How long a car waits after the traffic ran out of query budget.
const THROTTLE_PAUSE_SEC := 0.25
## How long a car waits after a leg it could not reach.
const FAILED_PAUSE_SEC := 0.5
## How long a car waits when the lane graph has no drive to offer from where it is.
const STRANDED_PAUSE_SEC := 1.5
## Tag on the goals that exist because a car is running away.
const TAG_FLEE := &"flee"

## Drive length band, straight from VehicleDirector's exports.
var trip_min_m: float = 70.0
var trip_max_m: float = 240.0
## How far a fleeing car asks to get from its threat in one goal.
var flee_run_min_m: float = 80.0
var flee_run_max_m: float = 260.0
## Arrival distance for one leg. Loose enough that a car does not have to stop dead on a lane
## point it is about to drive straight through.
var arrive_radius_m: float = 2.5
## How far from a lane point a car-sized span may be and still count as that lane point.
var snap_radius_m: float = 5.0
## Ambient path queries per second the whole district's traffic may cause.
var goal_queries_per_sec: float = 8.0
## No new goals while NavService already holds this many queries.
var queue_pause_size: int = 24

var _nav: NavService = null
var _profile_id: int = NavProfile.Id.CAR
var _lanes: CarLaneGraph = null
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _tokens: float = 0.0

var _trips: int = 0
var _issued: int = 0
var _reached: int = 0
var _failed: int = 0
var _throttled: int = 0
var _stranded: int = 0
var _lane_closures: int = 0


func setup(nav: NavService, profile_id: int, seed_value: int) -> void:
	if nav == null or not nav.is_configured():
		push_error("VehicleGoalProvider.setup: NavService is not configured")
		return
	_nav = nav
	_profile_id = profile_id
	_rng.seed = seed_value
	_tokens = goal_queries_per_sec


## Adopt the district's lanes. Returns the number of lane points drives can start from; zero
## means this district has no drivable street and should get no traffic.
func bind_lanes(lanes: CarLaneGraph) -> int:
	_lanes = lanes
	if lanes == null or lanes.is_empty():
		push_error("VehicleGoalProvider.bind_lanes: no lanes, so there is nowhere to drive")
		return 0
	return lanes.node_count


func lanes() -> CarLaneGraph:
	return _lanes


## The provider's own clock, which every `paused_until` on a VehicleAgent is measured against.
func now() -> float:
	return _time


func advance(delta: float) -> void:
	_time += delta
	_tokens = minf(_tokens + goal_queries_per_sec * delta, maxf(goal_queries_per_sec, 1.0))


## A spawn point on a lane, snapped onto a span a car can sit on. Vector3.INF when the lane
## graph has nothing open.
func random_spawn() -> Dictionary:
	var out := {"position": Vector3.INF, "heading": Vector3.FORWARD, "node": -1}
	if _lanes == null or _lanes.is_empty():
		return out
	var node := _lanes.random_node(_rng)
	if node < 0:
		return out
	var at := _lanes.positions[node]
	var hit := _nav.nearest_surface(_profile_id, at, snap_radius_m)
	out["position"] = hit.position if hit.found else at
	out["heading"] = _lanes.heading_of(node)
	out["node"] = node
	return out


# ---------------------------------------------------------------------------
# NavGoalProvider
# ---------------------------------------------------------------------------

func next_goal(request: NavGoalRequest) -> NavGoal:
	var car := request.body as VehicleAgent
	if car == null:
		push_error(
			"VehicleGoalProvider: agent %d asked with a %s body"
			% [request.agent_id, "null" if request.body == null else request.body.get_class()]
		)
		return null
	if car.wrecked:
		return null
	if _time < car.paused_until:
		return null
	if car.fleeing:
		if not _spend_token():
			car.paused_until = _time + THROTTLE_PAUSE_SEC
			return null
		return flee_goal(car)
	if car.legs.is_empty() and not _plan_drive(car):
		car.paused_until = _time + STRANDED_PAUSE_SEC
		return null
	if not _spend_token():
		## The drive is kept: it costs nothing to hold and the next ask picks it up.
		car.paused_until = _time + THROTTLE_PAUSE_SEC
		return null
	return _goal_for_next_leg(car)


## Plan a drive from wherever the car is, in the lane it is already pointing along. True when
## the car has legs to walk afterwards.
func _plan_drive(car: VehicleAgent) -> bool:
	if _lanes == null or _lanes.is_empty():
		return false
	var from_node := _lanes.nearest_node(car.global_position, car.heading())
	if from_node < 0:
		_stranded += 1
		return false
	for _attempt in range(TRIP_TRIES):
		var route := _lanes.plan_trip(from_node, trip_min_m, trip_max_m, _rng)
		if route.size() < 2:
			continue
		car.route = route
		car.legs = _lanes.route_to_legs(route)
		car.route_version = _lanes.version()
		if not car.legs.is_empty():
			_trips += 1
			return true
	_stranded += 1
	return false


## The next lane point as a goal, or nothing when the road under it has gone.
func _goal_for_next_leg(car: VehicleAgent) -> NavGoal:
	var node := car.legs[0]
	car.legs.remove_at(0)
	if not _lanes.is_open(node):
		car.clear_route()
		car.paused_until = _time + FAILED_PAUSE_SEC
		return null
	var hit := _nav.nearest_surface(_profile_id, _lanes.positions[node], snap_radius_m)
	if not hit.found:
		## The lane graph still believes in a carriageway the span field has no record of.
		_lanes.close_node(node)
		_lane_closures += 1
		car.clear_route()
		car.paused_until = _time + FAILED_PAUSE_SEC
		return null
	car.lane_node = node
	_issued += 1
	return NavGoalScript.go_to_point(hit.position, arrive_radius_m)


## The goal a frightened driver wants. Public because VehicleDirector pushes one in through
## `NavAgent.set_goal` the moment destruction happens, instead of waiting to be asked.
##
## Prefer a far open lane point so cars stay on carriageways (fractal plazas and other
## open reserves are not for traffic). Fall back to an open-field flee only when the
## lane graph has nothing usable.
func flee_goal(car: VehicleAgent) -> NavGoal:
	car.clear_route()
	var run := _rng.randf_range(flee_run_min_m, flee_run_max_m)
	var lane_goal := _flee_via_lanes(car, run)
	if lane_goal != null:
		return lane_goal
	var goal := NavGoalScript.flee_point(car.flee_from, run)
	goal.tag = TAG_FLEE
	_issued += 1
	return goal


func _flee_via_lanes(car: VehicleAgent, min_clear_m: float) -> NavGoal:
	if _lanes == null or _lanes.is_empty() or _nav == null:
		return null
	var best := -1
	var best_d := -1.0
	for _i in range(16):
		var node := _lanes.random_node(_rng)
		if node < 0 or not _lanes.is_open(node):
			continue
		var at: Vector3 = _lanes.positions[node]
		var d := at.distance_to(car.flee_from)
		if d < min_clear_m * 0.5:
			continue
		if d > best_d:
			best_d = d
			best = node
	if best < 0:
		return null
	var hit := _nav.nearest_surface(_profile_id, _lanes.positions[best], snap_radius_m)
	if not hit.found:
		return null
	car.lane_node = best
	var goal := NavGoalScript.go_to_point(hit.position, arrive_radius_m)
	goal.tag = TAG_FLEE
	_issued += 1
	return goal


func goal_reached(request: NavGoalRequest, goal: NavGoal) -> void:
	_reached += 1
	var car := request.body as VehicleAgent
	if car == null:
		return
	if goal.tag == TAG_FLEE:
		car.fleeing = false
		car.flee_goal_queued = false
		return
	## Mid-drive: a car that has reached a lane point does not stop on it.
	car.paused_until = 0.0


func goal_failed(request: NavGoalRequest, _goal: NavGoal, _state: NavLadder.State) -> void:
	_failed += 1
	var car := request.body as VehicleAgent
	if car == null:
		return
	## The rest of the drive started from a lane point the car never got to. If the lane point
	## itself is the problem it is closed, so the next drive routes around it rather than
	## planning the same impossible turn again.
	if car.lane_node >= 0 and _lanes != null:
		_lanes.close_node(car.lane_node)
		_lane_closures += 1
	car.clear_route()
	car.paused_until = _time + FAILED_PAUSE_SEC


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func trips() -> int:
	return _trips


func goals_issued() -> int:
	return _issued


func goals_reached() -> int:
	return _reached


func goals_failed() -> int:
	return _failed


func throttled() -> int:
	return _throttled


## Cars that had nowhere to drive from where they were standing.
func stranded() -> int:
	return _stranded


## Lane points taken out of service. Non-zero after a blast is the point; non-zero on a quiet
## district means the lane geometry and the span field disagree about where the road is.
func lane_closures() -> int:
	return _lane_closures


func describe_load() -> String:
	return (
		"lanes=%d open=%d trips=%d goals=%d reached=%d failed=%d throttled=%d"
		% [
			0 if _lanes == null else _lanes.node_count,
			0 if _lanes == null else _lanes.open_node_count(),
			_trips,
			_issued,
			_reached,
			_failed,
			_throttled,
		]
		+ " stranded=%d closures=%d" % [_stranded, _lane_closures]
	)


func _spend_token() -> bool:
	if _nav.queue_size() >= queue_pause_size:
		_throttled += 1
		return false
	if _tokens < 1.0:
		_throttled += 1
		return false
	_tokens -= 1.0
	return true
