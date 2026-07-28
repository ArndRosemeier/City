## Moves one body along a NavPathResult corridor, with one traversal routine per link kind.
##
## The corridor is funnel-smoothed span data, so following it is a matter of steering at the
## next point — except where the bake says the segment is a climb, a drop or a jump, which are
## scripted traversals rather than steering (a mob cannot raycast a facade that has no
## collider past the collision viewer, which is exactly why the links are baked).
##
## Three motion tiers, from NavLod:
## - NEAR: VoxelBoxMover against live voxel data, gravity, steering separation. Digs and
##   collapses are felt immediately because the mover reads voxels, not meshed colliders.
## - MID: span-following. The corridor already carries the floor height per point, so the
##   body is placed on it directly. No colliders, no gravity.
## - FAR: one lerp along the corridor by arc length. No per-point steering at all.
##
## Link traversals are kinematic in every tier, including NEAR: VoxelBoxMover would refuse to
## push a body into the facade it is supposed to be climbing. The collider takes over again on
## the landing span.
class_name NavMotor
extends RefCounted

const NavLodScript := preload("res://scripts/city/nav_lod.gd")
const NavPathResultScript := preload("res://scripts/city/nav_path_result.gd")

## Below this the corridor point counts as reached and the motor moves on.
const WAYPOINT_RADIUS_M := 0.5
const ARRIVE_RADIUS_M := 0.35
## A walk point sits on its span's floor, so a body far above or below it has not reached it —
## that is a drop or a climb, and those are links with their own routines.
const WAYPOINT_HEIGHT_SLACK_M := 1.5
## Vertical slop when a link traversal decides it has arrived.
const LINK_EPSILON_M := 0.05


## One tick of motion, as a value: the agent's whole progress measurement reads from this.
class Step:
	extends RefCounted
	## The tier that actually ran, which is not the requested one when NEAR was asked for
	## without a collider.
	var tier: NavLod.Tier = NavLod.Tier.MID
	## NavPathResult.LINK_* of the segment being traversed.
	var link: int = NavPathResult.LINK_WALK
	## Where the body actually went this tick.
	var moved: Vector3 = Vector3.ZERO
	## Corridor distance the routine asked for.
	var expected_m: float = 0.0
	## Corridor distance actually gained. Negative when the body was pushed back.
	var advanced_m: float = 0.0
	## The corridor has been consumed.
	var arrived: bool = false
	## Index of the point being moved towards, or the point count once arrived.
	var corridor_index: int = 0
	## NEAR only; false in the other tiers, which do not simulate gravity.
	var on_floor: bool = false


## Horizontal walking speed, metres per second.
var speed_mps: float = 3.2
## Vertical climb speed. city_walker's `climb_speed` at character_scale 1, so a mob scales a
## facade at the pace the player does.
var climb_speed_mps: float = 1.15
## Sideways pace while mounting a landing span at the top of a climb.
var mount_speed_mps: float = 1.2
var fall_speed_max_mps: float = 22.0
## Take-off speed of a jump link; the arc duration follows from the link length.
var jump_speed_mps: float = 5.0
## Apex height added over the straight line of a jump link.
var jump_arc_m: float = 0.8
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var waypoint_radius_m: float = WAYPOINT_RADIUS_M
var arrive_radius_m: float = ARRIVE_RADIUS_M
## Weight on the separation velocity the director accumulates. NEAR only.
var separation_weight: float = 1.0

var _body: Node3D = null
var _profile: NavProfile = null
var _tier: NavLod.Tier = NavLod.Tier.MID
var _path: NavPathResult = null
var _points: PackedVector3Array = PackedVector3Array()
var _links: PackedByteArray = PackedByteArray()
## Arc length from the corridor start to each point.
var _arc: PackedFloat32Array = PackedFloat32Array()
var _total_m: float = 0.0
## Point being moved towards. Equal to the point count once the corridor is consumed.
var _index: int = 0
## Distance travelled along the corridor, FAR tier only.
var _far_arc: float = 0.0
var _vel_y: float = 0.0
var _separation: Vector3 = Vector3.ZERO
## Which point the running link traversal belongs to, so entering one resets its state.
var _link_point: int = -1
var _link_from: Vector3 = Vector3.ZERO
var _link_t: float = 0.0
var _link_span_m: float = 0.0
var _char: CharacterBody3D = null
var _capsule: CollisionShape3D = null
var _motion: VoxelBodyMotion = null
var _collider_error_shown: bool = false


func setup(body: Node3D, profile: NavProfile) -> void:
	if body == null:
		push_error("NavMotor.setup: no body")
		return
	if profile == null:
		push_error("NavMotor.setup: no profile")
		return
	_body = body
	_profile = profile


## Give the near tier real collision. `motion` must already be `setup()` against the terrain.
func attach_collider(
	character: CharacterBody3D, capsule: CollisionShape3D, motion: VoxelBodyMotion
) -> void:
	if character == null or capsule == null or motion == null:
		push_error("NavMotor.attach_collider: character, capsule and motion are all required")
		return
	_char = character
	_capsule = capsule
	_motion = motion


func can_use_collider() -> bool:
	return _char != null and _capsule != null and _motion != null


## Is the body standing on something? Span-following places it on the corridor, so it is
## supported by construction; the near tier asks VoxelBoxMover, which is the only tier where a
## body can be in mid-air.
func is_supported() -> bool:
	if effective_tier() == NavLod.Tier.NEAR and can_use_collider():
		return _motion.is_on_floor()
	return true


func body() -> Node3D:
	return _body


func profile() -> NavProfile:
	return _profile


func tier() -> NavLod.Tier:
	return _tier


## The tier that will run. NEAR degrades to MID without a collider, loudly and once.
func effective_tier() -> NavLod.Tier:
	if _tier != NavLod.Tier.NEAR or can_use_collider():
		return _tier
	if not _collider_error_shown:
		_collider_error_shown = true
		push_error(
			"NavMotor: near tier asked for on %s with no collider attached — span-following"
			% _body_name()
		)
	return NavLod.Tier.MID


## Switching tier keeps the position on the corridor: the FAR tier tracks arc length and the
## others track a point index, so whichever one is about to run gets re-synced from the other.
func set_tier(new_tier: NavLod.Tier) -> void:
	if new_tier == _tier:
		return
	var was_far := _tier == NavLod.Tier.FAR
	var walked := _total_m - remaining_m()
	_tier = new_tier
	if not has_path():
		return
	if new_tier == NavLod.Tier.FAR:
		_far_arc = clampf(walked, 0.0, _total_m)
	elif was_far:
		_index = _index_for_arc(_far_arc)
		_link_point = -1
	_vel_y = 0.0


# ---------------------------------------------------------------------------
# Corridor
# ---------------------------------------------------------------------------

## Adopt a corridor. It must be usable — following a failed query is the agent's decision to
## make, not something the motor papers over.
func set_path(result: NavPathResult) -> void:
	if result == null:
		push_error("NavMotor.set_path: null result")
		return
	if not result.is_usable():
		push_error(
			"NavMotor.set_path: %s is not usable for %s"
			% [result.status_name(), _body_name()]
		)
		return
	if result.points.size() < 2:
		push_error(
			"NavMotor.set_path: %s corridor has %d points"
			% [result.status_name(), result.points.size()]
		)
		return
	if result.link_kinds.size() != result.points.size():
		push_error(
			"NavMotor.set_path: %d points but %d link kinds"
			% [result.points.size(), result.link_kinds.size()]
		)
		return
	_path = result
	_points = result.points
	_links = result.link_kinds
	_index = 1
	_far_arc = 0.0
	_vel_y = 0.0
	_link_point = -1
	_build_arc()
	_check_links()


func clear_path() -> void:
	_path = null
	_points = PackedVector3Array()
	_links = PackedByteArray()
	_arc = PackedFloat32Array()
	_total_m = 0.0
	_index = 0
	_far_arc = 0.0
	_link_point = -1


func has_path() -> bool:
	return _path != null and _index < _points.size()


func path() -> NavPathResult:
	return _path


## Corridor still to walk, in metres.
func remaining_m() -> float:
	if _path == null:
		return 0.0
	if effective_tier() == NavLod.Tier.FAR:
		return maxf(_total_m - _far_arc, 0.0)
	if _index >= _points.size():
		return 0.0
	return _body.global_position.distance_to(_points[_index]) + (_total_m - _arc[_index])


func total_m() -> float:
	return _total_m


func corridor_index() -> int:
	return _index


## Link kind of the segment being traversed, LINK_WALK when walking or interpolating.
func current_link() -> int:
	if effective_tier() == NavLod.Tier.FAR or _index <= 0 or _index >= _links.size():
		return NavPathResult.LINK_WALK
	return int(_links[_index])


## Where the corridor ends. Vector3.INF without one.
func destination() -> Vector3:
	if _path == null or _points.is_empty():
		return Vector3.INF
	return _points[_points.size() - 1]


## The point being moved towards. Vector3.INF once the corridor is consumed — this is the
## cell the agent blames when it cannot make progress.
func next_point() -> Vector3:
	if not has_path():
		return Vector3.INF
	return _points[_index]


## The corridor from here on, for a dirty-sector test or the debug overlay.
func remaining_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _path == null:
		return out
	out.append(_body.global_position)
	for i in range(_index, _points.size()):
		out.append(_points[i])
	return out


## A point `distance_m` further along the corridor, for repathing inside the current sector
## instead of all the way to the goal. Clamped to the corridor end.
func point_ahead(distance_m: float) -> Vector3:
	if _path == null or _points.is_empty():
		return Vector3.INF
	var walked := clampf(_total_m - remaining_m(), 0.0, _total_m)
	return _sample_arc(minf(walked + distance_m, _total_m))


## Extra velocity for this tick, from crowd separation. Consumed and cleared by `advance`.
func add_separation(velocity: Vector3) -> void:
	_separation += velocity


# ---------------------------------------------------------------------------
# Motion
# ---------------------------------------------------------------------------

## One tick along the corridor. The returned Step is how the agent measures progress, so it
## reports what happened rather than what was asked for.
func advance(delta: float) -> Step:
	var step := Step.new()
	step.tier = effective_tier()
	if _path == null:
		push_error("NavMotor.advance: no corridor on %s" % _body_name())
		return step
	if _body == null or not is_instance_valid(_body):
		push_error("NavMotor.advance: body is gone")
		return step
	if delta <= 0.0:
		push_error("NavMotor.advance: delta %.4f" % delta)
		return step
	step.corridor_index = _index
	if _index >= _points.size():
		step.arrived = true
		return step

	var before := remaining_m()
	var from := _body.global_position
	step.link = current_link()
	match step.tier:
		NavLod.Tier.FAR:
			step.expected_m = _interpolate(delta)
		NavLod.Tier.MID, NavLod.Tier.NEAR:
			step.expected_m = _follow(delta, step)
		_:
			push_error("NavMotor.advance: unknown tier %d" % step.tier)
	_separation = Vector3.ZERO
	## A tick that runs out of corridor asked for less than a full stride, and expecting the
	## stride would read as a stall every time a body arrives.
	step.expected_m = minf(step.expected_m, before)
	step.moved = _body.global_position - from
	step.advanced_m = before - remaining_m()
	step.corridor_index = _index
	step.arrived = not has_path()
	if step.tier == NavLod.Tier.NEAR and can_use_collider():
		step.on_floor = _motion.is_on_floor()
	return step


## The requested corridor distance for this tick, and the motion to achieve it.
func _follow(delta: float, step: Step) -> float:
	var target := _points[_index]
	match step.link:
		NavPathResult.LINK_WALK:
			return _traverse_walk(delta, target, step.tier)
		NavPathResult.LINK_CLIMB:
			return _traverse_climb(delta, target)
		NavPathResult.LINK_DROP:
			return _traverse_drop(delta, target)
		NavPathResult.LINK_JUMP:
			return _traverse_jump(delta, target)
		_:
			push_error(
				"NavMotor: corridor point %d has unknown link kind %d"
				% [_index, step.link]
			)
			return _traverse_walk(delta, target, step.tier)


## Plain walking. NEAR pushes the body through VoxelBoxMover with gravity, MID places it on
## the span the corridor named.
func _traverse_walk(delta: float, target: Vector3, tier_now: NavLod.Tier) -> float:
	var pos := _body.global_position
	if tier_now == NavLod.Tier.NEAR:
		var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var dir := Vector3.ZERO
		if flat.length_squared() > 0.000001:
			dir = flat.normalized()
		var wish := dir * speed_mps + _separation * separation_weight
		if _motion.is_on_floor():
			_vel_y = 0.0
		_vel_y = maxf(_vel_y - gravity * delta, -fall_speed_max_mps)
		_motion.move(_char, _capsule, Vector3(wish.x, _vel_y, wish.z), delta)
		if _motion.is_on_floor():
			_vel_y = 0.0
	else:
		var to := target - pos
		var stride := speed_mps * delta
		if to.length() <= stride:
			_body.global_position = target
		else:
			_body.global_position = pos + to.normalized() * stride
	_accept_waypoint(target)
	return speed_mps * delta


## LINK_CLIMB: rise the facade at climb speed with the footprint held on the take-off column,
## then step onto the landing span. Kinematic — the wall is in the way by definition.
func _traverse_climb(delta: float, target: Vector3) -> float:
	_enter_link(target)
	var pos := _body.global_position
	var dy := target.y - pos.y
	if absf(dy) > LINK_EPSILON_M:
		var rise := clampf(dy, -climb_speed_mps * delta, climb_speed_mps * delta)
		_body.global_position = Vector3(pos.x, pos.y + rise, pos.z)
		_vel_y = 0.0
		return climb_speed_mps * delta
	var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var mount := mount_speed_mps * delta
	if flat.length() <= mount:
		_body.global_position = target
		_advance_index()
	else:
		_body.global_position = pos + flat.normalized() * mount
	return mount_speed_mps * delta


## LINK_DROP: walk off the edge and fall to the landing span. Gravity drives Y in every tier,
## because a drop that is placed rather than fallen reads as teleporting.
func _traverse_drop(delta: float, target: Vector3) -> float:
	_enter_link(target)
	var pos := _body.global_position
	_vel_y = maxf(_vel_y - gravity * delta, -fall_speed_max_mps)
	var next_y := pos.y + _vel_y * delta
	var landed := false
	if next_y <= target.y:
		next_y = target.y
		landed = true
		_vel_y = 0.0
	var flat := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var stride := speed_mps * delta
	var next_xz := Vector3(target.x, 0.0, target.z)
	if flat.length() > stride:
		next_xz = pos + flat.normalized() * stride
	_body.global_position = Vector3(next_xz.x, next_y, next_xz.z)
	var flat_left := Vector2(target.x - next_xz.x, target.z - next_xz.z).length()
	if landed and flat_left <= waypoint_radius_m:
		_body.global_position = target
		_advance_index()
	return maxf(absf(_vel_y) * delta, speed_mps * delta)


## LINK_JUMP: a fixed arc over the gap. The link length sets the duration, so a long jump
## takes longer instead of moving faster.
func _traverse_jump(delta: float, target: Vector3) -> float:
	_enter_link(target)
	var duration := maxf(_link_span_m / maxf(jump_speed_mps, 0.01), 0.15)
	_link_t = minf(_link_t + delta / duration, 1.0)
	var along := _link_from.lerp(target, _link_t)
	var arc := jump_arc_m * 4.0 * _link_t * (1.0 - _link_t)
	_body.global_position = along + Vector3(0.0, arc, 0.0)
	if _link_t >= 1.0:
		_body.global_position = target
		_advance_index()
	return _link_span_m * delta / duration


## FAR: the whole corridor as one arc-length parameter. No steering, no link routines — a
## body nobody can see does not act out a climb.
func _interpolate(delta: float) -> float:
	var stride := speed_mps * delta
	_far_arc = minf(_far_arc + stride, _total_m)
	_body.global_position = _sample_arc(_far_arc)
	if _far_arc >= _total_m:
		_index = _points.size()
	else:
		_index = _index_for_arc(_far_arc)
	return stride


# ---------------------------------------------------------------------------
# Corridor bookkeeping
# ---------------------------------------------------------------------------

func _accept_waypoint(target: Vector3) -> void:
	var pos := _body.global_position
	var flat := Vector2(target.x - pos.x, target.z - pos.z).length()
	var radius := waypoint_radius_m
	if _index == _points.size() - 1:
		radius = arrive_radius_m
	if flat > radius:
		return
	if absf(pos.y - target.y) > WAYPOINT_HEIGHT_SLACK_M:
		return
	_advance_index()


func _advance_index() -> void:
	_index += 1
	_link_point = -1
	_vel_y = 0.0


## First tick of a link traversal: remember where it started, because a jump arc and a mount
## are relative to the take-off, not to wherever the body drifted.
func _enter_link(target: Vector3) -> void:
	if _link_point == _index:
		return
	_link_point = _index
	_link_from = _body.global_position
	_link_t = 0.0
	_link_span_m = maxf(_link_from.distance_to(target), 0.01)
	_vel_y = 0.0


func _build_arc() -> void:
	_arc = PackedFloat32Array()
	_arc.resize(_points.size())
	_arc[0] = 0.0
	var total := 0.0
	for i in range(1, _points.size()):
		total += _points[i].distance_to(_points[i - 1])
		_arc[i] = total
	_total_m = total


## A corridor that asks for a traversal the profile cannot perform means the bake and the
## profile filter disagree, which is worth an error rather than a mob stuck on a wall.
func _check_links() -> void:
	if _profile == null:
		return
	for i in range(_links.size()):
		var kind := int(_links[i])
		if kind == NavPathResult.LINK_CLIMB and not _profile.can_climb:
			push_error(
				"NavMotor: corridor for %s uses a climb link but the profile cannot climb"
				% _profile.display_name
			)
			return
		if kind == NavPathResult.LINK_JUMP and not _profile.can_jump:
			push_error(
				"NavMotor: corridor for %s uses a jump link but the profile cannot jump"
				% _profile.display_name
			)
			return


func _sample_arc(arc: float) -> Vector3:
	if _points.is_empty():
		return _body.global_position
	if arc <= 0.0:
		return _points[0]
	if arc >= _total_m:
		return _points[_points.size() - 1]
	var i := _index_for_arc(arc)
	var span := _arc[i] - _arc[i - 1]
	if span <= 0.0001:
		return _points[i]
	return _points[i - 1].lerp(_points[i], (arc - _arc[i - 1]) / span)


## The point the body is heading for at `arc`.
func _index_for_arc(arc: float) -> int:
	for i in range(1, _arc.size()):
		if _arc[i] > arc:
			return i
	return maxi(_points.size() - 1, 1)


func _body_name() -> String:
	if _body == null or not is_instance_valid(_body):
		return "<no body>"
	return String(_body.name)
