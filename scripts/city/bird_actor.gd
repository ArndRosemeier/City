## One ambient bird. Every bird in the world is built from this same handful of primitives:
## only the overall scale and the two coat materials change, so a flock reads as a mix of
## sparrows, pigeons and crows without a second model anywhere.
##
## A dumb body — BirdDirector decides where it goes and when it bolts. Built facing -Z (the
## Godot forward axis) so steering is a plain yaw/pitch pair aimed down the flight path.
class_name BirdActor
extends Node3D

enum State {
	## Sitting on `perch`, wings folded.
	PERCHED,
	## Cruising toward `target` at `cruise_speed`.
	FLYING,
	## Bolting away from something that walked up. Same flight, faster and climbing.
	FLEEING,
}

## Body length at scale 1.0, in metres. Scaled per bird by the director.
const BODY_LEN_M := 0.34
## Wingbeats per second in level flight. Flee flight beats faster (see `tick`).
const FLAP_HZ := 6.5
const FLEE_FLAP_HZ := 9.5
## How far the wings swing either side of level, in radians.
const FLAP_SWING := 0.85
## Slight dihedral in flight: two planks held dead level read as a paper aeroplane.
const WING_DIHEDRAL := 0.12
## Wings are swept back a little on the wing and folded right along the flanks when sitting,
## which is the difference between a perched bird and a crucified one.
const FLIGHT_SWEEP := 0.2
const FOLDED_SWEEP := 1.45
const FOLDED_DROOP := 0.16
## Metres above the surface the seat point sits, so feet touch instead of sinking in.
const PERCH_LIFT_M := 0.07
## Wobble is a bounded offset laid over the flight path, in metres — never a change to
## `velocity`. Pushing it into the velocity compounds it frame on frame (the steering lerp
## only bleeds off a tenth of it), which silently turns a flutter into extra travel speed.
## Peak lift on the downstroke and peak sideways weave.
const BOB_AMP_M := 0.09
const SWAY_AMP_M := 0.14
## The weave runs slower than the wingbeat so it reads as banking, not vibrating.
const SWAY_RATE := 0.37
## Body roll that follows the weave, in radians.
const ROLL_SWAY := 0.09

var state: State = State.PERCHED
## World seat this bird is on (PERCHED) or heading home to (FLYING). INF = no perch.
var perch: Vector3 = Vector3.INF
## Where the body is steering right now. For a homeward flight this is `perch`.
var target: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var cruise_speed: float = 6.5
var flee_speed: float = 12.0
## Seconds left before the director gives this bird something new to do. Owned by the
## director; kept here so one bird's timers travel with it.
var decide_in: float = 0.0
## Size multiplier this bird was built at — the director spreads these across the flock.
var body_scale: float = 1.0

var _wing_l: Node3D
var _wing_r: Node3D
var _flap_phase: float = 0.0
var _idle_phase: float = 0.0
## Per-bird offset so a flock does not bob and bank in lockstep.
var _wobble_bias: float = 0.0
## Last frame's wobble offset, so it can be peeled back off before the next step.
var _wobble: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0


## Assemble the shared shape. `coat` colours body and head, `accent` the wings and tail,
## `beak_mat` the beak — three references shared across every bird of the same species.
func build(
	coat: StandardMaterial3D,
	accent: StandardMaterial3D,
	beak_mat: StandardMaterial3D,
	size: float
) -> void:
	if coat == null or accent == null or beak_mat == null:
		push_error("BirdActor.build: missing material")
		return
	body_scale = size
	scale = Vector3.ONE * size
	## Phase offsets are seed-independent on purpose: two birds of the same size must not
	## flap in unison just because they hatched from the same coat.
	_flap_phase = randf() * TAU
	_wobble_bias = randf() * TAU

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.085
	body_mesh.height = 0.17
	body_mesh.radial_segments = 10
	body_mesh.rings = 5
	body.mesh = body_mesh
	## One squashed sphere reads as a bird body: taller than wide, longer than tall.
	body.scale = Vector3(0.92, 0.88, 1.55)
	body.material_override = coat
	_no_shadow(body)
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.055
	head_mesh.height = 0.11
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.055, -0.115)
	head.material_override = coat
	_no_shadow(head)
	add_child(head)

	var beak := MeshInstance3D.new()
	var beak_mesh := CylinderMesh.new()
	beak_mesh.top_radius = 0.0
	beak_mesh.bottom_radius = 0.022
	beak_mesh.height = 0.075
	beak_mesh.radial_segments = 6
	beak.mesh = beak_mesh
	## Cylinders grow along +Y; tip the cone over so it points down the forward axis.
	beak.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	beak.position = Vector3(0.0, 0.045, -0.19)
	beak.material_override = beak_mat
	_no_shadow(beak)
	add_child(beak)

	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.075, 0.014, 0.16)
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, 0.02, 0.19)
	tail.rotation = Vector3(0.22, 0.0, 0.0)
	tail.material_override = accent
	_no_shadow(tail)
	add_child(tail)

	_wing_l = _build_wing(accent, 1.0)
	_wing_r = _build_wing(accent, -1.0)
	set_wings_folded()


## Wing pivots sit at the shoulder so a rotation about Z sweeps the whole wing, the way a
## wing hinged at the body does. `side` is +1 for the left wing, -1 for the right.
func _build_wing(accent: StandardMaterial3D, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.055 * side, 0.045, 0.0)
	add_child(pivot)
	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.2, 0.014, 0.135)
	wing.mesh = wing_mesh
	wing.position = Vector3(0.1 * side, 0.0, 0.01)
	wing.material_override = accent
	_no_shadow(wing)
	pivot.add_child(wing)
	return pivot


func _no_shadow(mesh: MeshInstance3D) -> void:
	## Birds are centimetres of geometry tens of metres up — their shadows cost more than
	## they are ever worth.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Drop onto a seat and stop flying. `seat` is the world point the feet stand on.
func sit_on(seat: Vector3) -> void:
	perch = seat
	target = seat
	state = State.PERCHED
	velocity = Vector3.ZERO
	global_position = seat + Vector3(0.0, PERCH_LIFT_M * body_scale, 0.0)
	_pitch = 0.0
	_roll = 0.0
	_wobble = Vector3.ZERO
	set_wings_folded()


## Head for a point under power. `home_seat` is the seat waiting at the far end, or INF for
## a flight that ends in mid-air (the director will hand out a perch when it arrives).
func fly_to(point: Vector3, home_seat: Vector3) -> void:
	target = point
	perch = home_seat
	state = State.FLYING
	## Launch with a little of the climb already in the body, so a take-off does not start
	## with the bird sliding sideways off its branch.
	velocity = Vector3(velocity.x, maxf(velocity.y, 1.5), velocity.z)
	_wobble = Vector3.ZERO


## Bolt. `away_point` is where the director wants this bird gone to.
func flee_to(away_point: Vector3) -> void:
	target = away_point
	perch = Vector3.INF
	state = State.FLEEING
	velocity = Vector3(velocity.x, maxf(velocity.y, 4.0), velocity.z)


func is_flying() -> bool:
	return state != State.PERCHED


## XZ+Y distance to whatever this bird is steering at. Meaningless while perched.
func distance_to_target() -> float:
	return global_position.distance_to(target)


func set_wings_folded() -> void:
	_pose_wings(FOLDED_SWEEP, -FOLDED_DROOP)


## `sweep` swings the wing back along the body, `lift` raises its tip. Mirrored between the
## two sides, so one call sets both.
func _pose_wings(sweep: float, lift: float) -> void:
	if _wing_l == null:
		return
	_wing_l.rotation = Vector3(0.0, -sweep, lift)
	_wing_r.rotation = Vector3(0.0, sweep, -lift)


func tick(delta: float) -> void:
	if state == State.PERCHED:
		_tick_perched(delta)
		return
	var speed := flee_speed if state == State.FLEEING else cruise_speed
	var hz := FLEE_FLAP_HZ if state == State.FLEEING else FLAP_HZ
	_flap_phase += delta * hz * TAU
	var flap := sin(_flap_phase)
	_pose_wings(FLIGHT_SWEEP, WING_DIHEDRAL + flap * FLAP_SWING)

	## Fly the clean path, then hang the wobble off it. Subtracting last frame's offset first
	## means an outside write to `global_position` (a spawn, a test, a tool) still lands where
	## the caller put it.
	var path_pos := global_position - _wobble
	var to_target := target - path_pos
	var dist := to_target.length()
	var want := Vector3.ZERO
	if dist > 0.01:
		want = to_target / dist * speed
	## Ease into the new heading instead of snapping: a bird that turns instantly reads
	## as a sprite being teleported around.
	velocity = velocity.lerp(want, clampf(delta * 2.6, 0.0, 1.0))
	path_pos += velocity * delta

	var sway := sin(_flap_phase * SWAY_RATE + _wobble_bias)
	_wobble = Vector3(0.0, flap * BOB_AMP_M, 0.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.01:
		_wobble += Vector3(-flat.z, 0.0, flat.x).normalized() * sway * SWAY_AMP_M
	global_position = path_pos + _wobble
	_face(velocity, delta, sway)


func _tick_perched(delta: float) -> void:
	## Small breathing bob and an occasional look around: enough that a sitting bird is not
	## mistaken for a prop.
	_idle_phase += delta * 1.7
	var seat := perch if perch.is_finite() else global_position
	global_position = Vector3(
		seat.x,
		seat.y + PERCH_LIFT_M * body_scale + sin(_idle_phase) * 0.008,
		seat.z
	)
	_yaw += sin(_idle_phase * 0.37) * delta * 0.5
	_pitch = lerpf(_pitch, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	_roll = lerpf(_roll, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	rotation = Vector3(_pitch, _yaw, _roll)


## Point the beak down the travel vector. Forward is -Z, so the yaw that maps -Z onto a
## heading (dx, dz) is atan2(-dx, -dz); pitch is the climb angle of the same vector.
## `sway` is the weave signal (−1..1) so the body banks into the lateral drift.
func _face(dir: Vector3, delta: float, sway: float = 0.0) -> void:
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.0004:
		return
	var want_yaw := atan2(-dir.x, -dir.z)
	var want_pitch := clampf(atan2(dir.y, flat.length()), -0.6, 0.6)
	## Bank into the weave: positive sway is left, so the bird rolls left with it.
	var want_roll := clampf(-sway * ROLL_SWAY, -ROLL_SWAY, ROLL_SWAY)
	var t := clampf(delta * 5.0, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, want_yaw, t)
	_pitch = lerpf(_pitch, want_pitch, t)
	_roll = lerpf(_roll, want_roll, t)
	rotation = Vector3(_pitch, _yaw, _roll)
