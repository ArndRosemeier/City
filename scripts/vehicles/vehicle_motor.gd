## NavMotor for something with a wheelbase.
##
## A car follows the same span corridor as everything else, but it cannot pivot on the spot and
## it cannot be pushed around by VoxelBoxMover: there is no capsule, and a two-tonne saloon
## sliding sideways down a kerb is not the motion anybody wants. So the near tier is declined
## outright and every tier steers kinematically, turning at `turn_rate` and easing off the
## throttle in proportion to how far off the nose is from where the corridor goes.
##
## Yielding lives here rather than in the driver because a car waiting at a crossing has to stop
## without losing its corridor, its place on it, or its progress measurement: `stopped` declines
## the tick outright, so NavAgent's progress test has nothing to fail.
##
## The corridor is span data, and a span corridor between two lane points is only ever *near*
## the carriageway: it is smoothed, it prices pavement rather than forbidding it, and at the far
## tier it is a chord. So the car is glued to the lane line between the gate its leg started at
## and the gate it is driving to — the corridor still decides the route, the lane decides where
## on the road the car sits. Height comes off the corridor segment under the glued position
## rather than a lerp that trails behind it, which is what stops a car floating over a ramp.
class_name VehicleMotor
extends NavMotor

## Slowest a car takes a corner, as a fraction of its cruise speed.
const CORNER_SPEED_FLOOR := 0.35
## Below this alignment the car is essentially turning round and crawls at the floor speed.
const CORNER_SPEED_KNEE := 0.2

## How fast the car is drawn back onto the lane line, in metres of lateral pull per second. A
## car that repathed off-lane slides back into it rather than snapping across the road.
const GLUE_PULL_MPS := 6.0
## Past this the corridor is not drifting, it is detouring — round a blast hole, a wreck or a
## closure — and pulling the car back onto the lane line would fight the path it was given.
const GLUE_MAX_M := 6.0
## Inside this of the corridor point being driven to, the corridor wins. The lane line holds the
## car between waypoints, but the waypoint itself has to stay reachable: a car held off its own
## goal never registers progress, and the failure ladder would close a road that is perfectly
## good.
const GLUE_RELEASE_M := 3.0

## Radians per second of yaw change.
var turn_rate: float = 3.5
## Held at a crossing an occupied pedestrian paint is on. The corridor is kept.
var stopped: bool = false

## The district's lanes, for the glue. Without them this is the plain corridor follower.
var _lanes: CarLaneGraph = null


## Adopt the lanes the car's legs are named in. VehicleDirector owns the graph; the motor only
## reads the line between the two gates the goal provider put on the agent.
func bind_lanes(lanes: CarLaneGraph) -> void:
	if lanes == null:
		push_error("VehicleMotor.bind_lanes: no lane graph, so nothing to hold the car on")
		return
	_lanes = lanes


## A car has no capsule, so the near tier is not a degradation to report — it is a tier this
## body was never going to run. Span-following at every distance.
func effective_tier() -> NavLod.Tier:
	if _tier == NavLod.Tier.NEAR:
		return NavLod.Tier.MID
	return _tier


## Where the nose points, from the body's own yaw. The visual convention is nose along local
## -Z, which is what `atan2(-x, -z)` below produces.
func heading() -> Vector3:
	if _body == null or not is_instance_valid(_body):
		return Vector3.FORWARD
	var yaw := _body.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Held at a crossing: nothing moves and nothing is owed, in every tier. Refusing the tick
## outright rather than zeroing the stride inside the walk is what covers the far tier, which
## interpolates along the corridor without going through a traversal routine at all — a car
## nobody can see must still not drive through the pedestrian who is holding it.
##
## The corridor and the place on it survive, so the car resumes from where it stopped, and the
## agent's progress measurement has a zero expectation to compare against rather than a stall.
##
## The glue runs first on a tick that moves, before the tick is measured: correcting afterwards
## would book the pull onto the lane as corridor progress the car never made, and would move the
## body after the traversal already decided whether it had reached its waypoint. A held car is
## not corrected at all — standing still means standing still, and it is glued the moment it
## drives again.
func advance(delta: float) -> Step:
	if not stopped:
		_glue_to_lane(delta)
		return super.advance(delta)
	var step := Step.new()
	step.tier = effective_tier()
	step.link = current_link()
	step.corridor_index = corridor_index()
	return step


## Steer at the next corridor point instead of walking to it. The body still travels along the
## line to the target — a car that tracked its own nose would drift off the corridor whenever
## it could not turn fast enough — but the throttle is tied to the nose, so a sharp corner is
## taken slowly and the yaw has time to catch up.
func _traverse_walk(delta: float, target: Vector3, _tier_now: NavLod.Tier) -> float:
	var pos := _body.global_position
	var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if flat.length_squared() < 0.000001:
		_accept_waypoint(target)
		return 0.0
	var to_go := flat.length()
	var dir := flat / to_go
	var desired_yaw := atan2(-dir.x, -dir.z)
	_body.rotation.y = lerp_angle(
		_body.rotation.y, desired_yaw, clampf(turn_rate * delta, 0.0, 1.0)
	)
	var alignment := clampf(heading().dot(dir), 0.0, 1.0)
	var throttle := lerpf(
		CORNER_SPEED_FLOOR, 1.0, smoothstep(CORNER_SPEED_KNEE, 1.0, alignment)
	)
	var stride := minf(speed_mps * throttle * delta, to_go)
	## Height comes from the corridor, which carries the span floor per point, so a car
	## climbing a ramp rises with it instead of holding the height it set off at.
	var travelled := stride / to_go
	_body.global_position = Vector3(
		pos.x + dir.x * stride,
		lerpf(pos.y, target.y, travelled),
		pos.z + dir.z * stride
	)
	_accept_waypoint(target)
	return stride


# ---------------------------------------------------------------------------
# Lane glue
# ---------------------------------------------------------------------------

## Hold the car on the lane line its leg runs along, and on the corridor's own floor.
##
## Only a leg of a planned drive has a lane line: `lane_from` and `lane_node` are the two gates
## `CarLaneGraph.route_to_legs` handed out, so the straight between them is a real carriageway.
## A fleeing car has no such pair and is left to the corridor.
func _glue_to_lane(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	if not has_path():
		return
	## A drop is gravity's business and the height it wants is not the one under the wheels.
	if current_link() != NavPathResult.LINK_WALK:
		return
	var pos := _body.global_position
	var glued := _lane_line_position(pos, delta)
	_body.global_position = Vector3(glued.x, _corridor_floor_y(glued), glued.z)


## `pos` pulled towards the lane line, or `pos` itself when there is no line to pull towards.
func _lane_line_position(pos: Vector3, delta: float) -> Vector3:
	if _lanes == null:
		return pos
	var car := _body as VehicleAgent
	if car == null:
		return pos
	if car.lane_from < 0 or car.lane_node < 0 or car.lane_from == car.lane_node:
		return pos
	var target := _points[_index]
	if Vector2(target.x - pos.x, target.z - pos.z).length() <= GLUE_RELEASE_M:
		return pos
	var on_lane := _lanes.project_onto_segment(pos, car.lane_from, car.lane_node)
	var off := Vector2(on_lane.x - pos.x, on_lane.z - pos.z)
	var off_m := off.length()
	if off_m < 0.001 or off_m > GLUE_MAX_M:
		return pos
	var pull := off * (minf(GLUE_PULL_MPS * delta, off_m) / off_m)
	return Vector3(pos.x + pull.x, pos.y, pos.z + pull.y)


## The corridor's floor directly under `at`, taken off the segment being driven rather than
## interpolated towards the far end of it: a long leg up a ramp used to leave the car trailing
## the height it was heading for by most of the leg.
func _corridor_floor_y(at: Vector3) -> float:
	var to_point := _points[_index]
	var from_point := _points[_index - 1]
	var run_x := to_point.x - from_point.x
	var run_z := to_point.z - from_point.z
	var run2 := run_x * run_x + run_z * run_z
	if run2 < 0.000001:
		return to_point.y
	var along := (at.x - from_point.x) * run_x + (at.z - from_point.z) * run_z
	return lerpf(from_point.y, to_point.y, clampf(along / run2, 0.0, 1.0))
