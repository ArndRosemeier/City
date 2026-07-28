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
class_name VehicleMotor
extends NavMotor

## Slowest a car takes a corner, as a fraction of its cruise speed.
const CORNER_SPEED_FLOOR := 0.35
## Below this alignment the car is essentially turning round and crawls at the floor speed.
const CORNER_SPEED_KNEE := 0.2

## Radians per second of yaw change.
var turn_rate: float = 3.5
## Held at a crossing an occupied pedestrian paint is on. The corridor is kept.
var stopped: bool = false


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
func advance(delta: float) -> Step:
	if not stopped:
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
