## The whole crowd's errand policy, as one NavGoalProvider for every pedestrian in a district.
##
## NavGoalRequest carries the body rather than the agent, so a single provider serves a
## thousand peds: whatever state a decision needs — the pause between two walks, the errand a
## ped is part way through, whether it is fleeing and from what — lives on the PedAgent that
## asked. CrowdDirector owns one of these and hands the same instance to every NavAgent.
##
## An errand is a short list of world points, and the ped walks one NavGoal per point. Almost
## always that list is one point, a pavement destination; the exceptions are the crossings on
## the way, which are the pavement intent the retired roadmap encoded as graph topology:
##
## - Destinations are pavement nodes, never carriageway mids, so a ped's errands begin and end
##   on the pavement and it never idles in the road. That replaces the curb teleport in the old
##   `_leave_carriageway_if_needed`, which shoved a ped onto the nearest curb after every walk.
## - Where an errand crosses a carriageway it goes through a crossing, as three points: the
##   near curb pad, the carriageway mid, the far curb pad. Those are exactly the three nodes
##   StreetNavLayers links a crossing out of, so a ped enters and leaves the road inside the
##   painted crossing — and it stands on the crossing mid, which is what makes cars yield to it
##   through `StreetNavLayers.refresh_crossing_occupancy_agents`.
##
## The legs are not a workaround for smoothing any more. `NavWorld::smooth` is cost-aware and
## does keep the crossing the search paid for — `tools/test_ped_nav.gd` asserts a corridor
## crosses on the paint where it used to record that it did not. What the legs are for now is
## the search's own arithmetic: eight metres of carriageway at 2.5x costs the same as walking
## about five metres of pavement each way to a crossing and 1.25x across it, so beyond that a
## detour is genuinely dearer and A* jaywalks on purpose. Dropping the legs and letting cost
## decide alone was measured on the street tile at 85% pavement and 6% of carriageway time off
## the paint, against 92% and 0% with them, so they stay.
##
## Every goal costs one NavService query, so this is also where the crowd's query volume is
## capped: a token bucket sets the ambient rate and a queue high-water mark parks the whole
## crowd whenever the service is behind, rather than letting hundreds of peds queue at once.
class_name PedGoalProvider
extends NavGoalProvider

const NavGoalScript := preload("res://scripts/city/nav_goal.gd")

## Destinations drawn before an errand gives up, in case the roadmap keeps offering
## carriageway mids.
const DEST_TRIES := 6
## Snap attempts for one waypoint before the errand is dropped.
const SNAP_TRIES := 2
## How long a ped waits after the crowd ran out of query budget.
const THROTTLE_PAUSE_SEC := 0.2
## How long a ped waits after a goal it could not reach, before starting another errand.
const FAILED_PAUSE_SEC := 0.4
## Tag on the goals that exist because a ped is running away.
const TAG_FLEE := &"flee"

## Walk errand range, straight from CrowdDirector's exports.
var walk_goal_min_m: float = 12.0
var walk_goal_max_m: float = 55.0
## Rare pause window when a ped chooses to stay (exception, not the rule).
var stay_min_sec: float = 1.2
var stay_max_sec: float = 4.0
## Brief pause between consecutive errands.
var rewalk_min_sec: float = 0.05
var rewalk_max_sec: float = 0.7
## How far a fleeing ped asks to get from its threat in one goal. The threat is not left
## behind in a single corridor, so a partial one is walked and the goal re-evaluated.
var flee_run_min_m: float = 40.0
var flee_run_max_m: float = 140.0
## Arrival distance for one leg of an errand. Tighter than a curb pad is wide, so a ped that
## arrived at a crossing is standing on it.
var arrive_radius_m: float = 1.25
## How far from a roadmap node a pedestrian span may be and still count as that node.
var snap_radius_m: float = 4.0
## Ambient path queries per second this crowd may cause, over the whole district.
var goal_queries_per_sec: float = 12.0
## No new goals while NavService already holds this many queries: undead, cars and the
## overlay share that queue, and a crowd must not be the reason they wait.
var queue_pause_size: int = 24

var _nav: NavService = null
var _profile_id: int = NavProfile.Id.PEDESTRIAN
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _tokens: float = 0.0
## The street layout, read for errand endpoints and crossings only. Never steered along.
var _roadmap: PedRoadMap = null
var _pavement_nodes: int = 0

var _errands: int = 0
var _issued: int = 0
var _reached: int = 0
var _failed: int = 0
var _throttled: int = 0
var _idled: int = 0
var _crossings_used: int = 0
var _snap_misses: int = 0


func setup(nav: NavService, profile_id: int, seed_value: int) -> void:
	if nav == null or not nav.is_configured():
		push_error("PedGoalProvider.setup: NavService is not configured")
		return
	_nav = nav
	_profile_id = profile_id
	_rng.seed = seed_value
	_tokens = goal_queries_per_sec


## Adopt the district's street layout. Returns the number of pavement nodes errands can start
## and end on; zero means this crowd has nowhere to walk and should not be spawned.
func bind_roadmap(roadmap: PedRoadMap) -> int:
	_roadmap = roadmap
	_pavement_nodes = 0
	if roadmap == null or roadmap.is_empty():
		push_error("PedGoalProvider.bind_roadmap: no roadmap, so the crowd has no pavement")
		return 0
	for node in range(roadmap.node_count):
		if not roadmap.is_crossing_node(node):
			_pavement_nodes += 1
	if _pavement_nodes == 0:
		push_error(
			"PedGoalProvider.bind_roadmap: %d roadmap nodes and every one is a carriageway mid"
			% roadmap.node_count
		)
	return _pavement_nodes


## Pavement nodes available as errand endpoints.
func pavement_count() -> int:
	return _pavement_nodes


## The provider's own clock, which every `paused_until` on a PedAgent is measured against.
func now() -> float:
	return _time


## One physics frame of provider clock, and one frame's worth of query budget.
func advance(delta: float) -> void:
	_time += delta
	_tokens = minf(_tokens + goal_queries_per_sec * delta, maxf(goal_queries_per_sec, 1.0))


## A spawn point on the pavement, on a span a pedestrian can stand on, in the largest
## connected part of the street layout so the ped has errands to run. Vector3.INF without a
## roadmap; the raw node when no span was found near it, so the spawned count stays what the
## director asked for and the failure ladder reports the rest.
func random_spawn() -> Vector3:
	if _roadmap == null or _roadmap.is_empty():
		return Vector3.INF
	var node := _roadmap.random_node(_rng)
	if node < 0:
		return Vector3.INF
	var at := _roadmap.positions[node]
	var hit := _nav.nearest_surface(_profile_id, at, snap_radius_m)
	if not hit.found:
		_snap_misses += 1
		return at
	return hit.position


## The points one errand is walked through: the crossings on the way, then the destination.
## Public because it is the whole of the pavement policy and worth testing on its own.
func plan_errand(from_world: Vector3) -> Array[Vector3]:
	var legs: Array[Vector3] = []
	if _roadmap == null or _roadmap.is_empty():
		return legs
	var from_node := _roadmap.nearest_sidewalk_node(from_world)
	if from_node < 0:
		return legs
	var to_node := -1
	for _try in range(DEST_TRIES):
		var cand := _roadmap.random_goal_node(
			from_node, walk_goal_min_m, walk_goal_max_m, _rng
		)
		if cand < 0 or cand == from_node:
			continue
		if _roadmap.is_crossing_node(cand):
			continue
		to_node = cand
		break
	if to_node < 0:
		return legs
	var nodes := _roadmap.find_path(from_node, to_node)
	if nodes.size() < 2:
		push_error(
			"PedGoalProvider: no route from node %d to %d, which the layout said were connected"
			% [from_node, to_node]
		)
		return legs
	for i in range(nodes.size()):
		if not _roadmap.is_crossing_node(nodes[i]):
			continue
		_crossings_used += 1
		if i > 0:
			_append_leg(legs, _roadmap.positions[nodes[i - 1]])
		_append_leg(legs, _roadmap.positions[nodes[i]])
		if i + 1 < nodes.size():
			_append_leg(legs, _roadmap.positions[nodes[i + 1]])
	_append_leg(legs, _roadmap.positions[to_node])
	_errands += 1
	return legs


# ---------------------------------------------------------------------------
# NavGoalProvider
# ---------------------------------------------------------------------------

func next_goal(request: NavGoalRequest) -> NavGoal:
	var ped := request.body as PedAgent
	if ped == null:
		push_error(
			"PedGoalProvider: agent %d asked with a %s body"
			% [request.agent_id, "null" if request.body == null else request.body.get_class()]
		)
		return null
	if ped.dead:
		return null
	if _time < ped.paused_until:
		return null
	if ped.fleeing:
		if not _spend_token():
			ped.paused_until = _time + THROTTLE_PAUSE_SEC
			return null
		return flee_goal(ped)
	if ped.legs.is_empty():
		if _rng.randf() > ped.walk_tendency:
			## Staying put is the exception, and the only decision that costs no query.
			ped.paused_until = _time + _rng.randf_range(stay_min_sec, stay_max_sec)
			_idled += 1
			return null
		ped.legs = plan_errand(ped.global_position)
		if ped.legs.is_empty():
			ped.paused_until = _time + _rng.randf_range(stay_min_sec, stay_max_sec)
			return null
	if not _spend_token():
		## The errand is kept: it costs nothing to hold and the next ask picks it up.
		ped.paused_until = _time + THROTTLE_PAUSE_SEC
		return null
	var to := _snap(ped.legs.pop_front())
	if to == Vector3.INF:
		ped.legs.clear()
		ped.paused_until = _time + _rng.randf_range(rewalk_min_sec, rewalk_max_sec)
		return null
	_issued += 1
	return NavGoalScript.go_to_point(to, arrive_radius_m)


## The goal a scared ped wants. Public because CrowdDirector pushes one in through
## `NavAgent.set_goal` the moment a threat appears, instead of waiting to be asked.
func flee_goal(ped: PedAgent) -> NavGoal:
	## Errands are off while running: the crossing a ped was heading for is beside the point.
	ped.legs.clear()
	var run := _rng.randf_range(flee_run_min_m, flee_run_max_m)
	var goal := NavGoalScript.flee_point(ped.flee_from, run)
	goal.tag = TAG_FLEE
	_issued += 1
	return goal


func goal_reached(request: NavGoalRequest, goal: NavGoal) -> void:
	_reached += 1
	var ped := request.body as PedAgent
	if ped == null:
		return
	if goal.tag == TAG_FLEE:
		## Far enough from the threat to stop running. The director agrees separately, on
		## `flee_clear_m`, because a flee goal can also be abandoned as unreachable.
		ped.fleeing = false
		ped.flee_goal_queued = false
	if not ped.legs.is_empty():
		## Mid-errand: a ped standing on a crossing does not pause there.
		ped.paused_until = 0.0
		return
	ped.paused_until = _time + _rng.randf_range(rewalk_min_sec, rewalk_max_sec)


func goal_failed(request: NavGoalRequest, _goal: NavGoal, _state: NavLadder.State) -> void:
	_failed += 1
	var ped := request.body as PedAgent
	if ped == null:
		return
	## Whatever the rest of that errand was, it started from a point the ped never reached.
	ped.legs.clear()
	ped.paused_until = _time + FAILED_PAUSE_SEC


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Errands planned. Each is one destination plus the crossings on the way to it.
func errands() -> int:
	return _errands


## Goals handed out: one per errand leg, plus one per flee.
func goals_issued() -> int:
	return _issued


func goals_reached() -> int:
	return _reached


func goals_failed() -> int:
	return _failed


## Crossings routed through. Zero over a long run on a district with crossings means peds are
## jaywalking, because the profile's surface costs alone do not keep them off the carriageway
## once the nearest crossing is further away than the detour is worth.
func crossings_used() -> int:
	return _crossings_used


## Asks refused because the crowd was over its query budget or the service queue was deep.
## Expected to be non-zero under load; a large share means the budget is too tight.
func throttled() -> int:
	return _throttled


## Asks that ended in a deliberate pause instead of an errand.
func idled() -> int:
	return _idled


## Roadmap nodes with no pedestrian span within `snap_radius_m`. Pavement the span field
## disagrees with, so worth seeing rather than swallowing.
func snap_misses() -> int:
	return _snap_misses


func describe_load() -> String:
	return (
		"pavement=%d errands=%d goals=%d reached=%d failed=%d crossings=%d throttled=%d"
		% [
			_pavement_nodes,
			_errands,
			_issued,
			_reached,
			_failed,
			_crossings_used,
			_throttled,
		]
		+ " idled=%d snap_misses=%d" % [_idled, _snap_misses]
	)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Crossing triples share their end nodes with the run either side of them, and the last
## crossing's far pad is often the destination itself.
func _append_leg(legs: Array[Vector3], at: Vector3) -> void:
	if not legs.is_empty() and legs[legs.size() - 1].is_equal_approx(at):
		return
	legs.append(at)


func _spend_token() -> bool:
	if _nav.queue_size() >= queue_pause_size:
		_throttled += 1
		return false
	if _tokens < 1.0:
		_throttled += 1
		return false
	_tokens -= 1.0
	return true


## A roadmap node is a position from the street layout; the span field decides the height it is
## actually standable at. Vector3.INF when there is no span there at all.
func _snap(at: Vector3) -> Vector3:
	for _try in range(SNAP_TRIES):
		var hit := _nav.nearest_surface(_profile_id, at, snap_radius_m)
		if hit.found:
			return hit.position
		_snap_misses += 1
	return Vector3.INF
