## What one undead wants next: people for a mage, a facade for a minion, a building for a
## giant, and a wander when the city offers none of those.
##
## One provider per body, because the answer comes out of that body's role, its state and
## what the city can see around it. NavAgent asks whenever a goal ends; `retarget` exists
## because prey walks away, and a corridor built for where a pedestrian used to be is stale
## long before it has been walked.
class_name UndeadGoalProvider
extends NavGoalProvider

## Goal tags, so `goal_reached` knows which behaviour just finished.
const TAG_HUNT := &"hunt"
const TAG_NIBBLE := &"nibble"
const TAG_DEMOLISH := &"demolish"
const TAG_PAD := &"pad"
const TAG_WANDER := &"wander"

## How far prey may drift before the corridor is rebuilt for where it is now.
const RETARGET_SLACK_M := 3.0
## Wander pick radius. About the mage pursue range, so a bored body covers ground instead
## of shuffling on the spot the way the old random-heading wander did.
const WANDER_RADIUS_M := 24.0
## Prey cache lifetime. The city query walks every loaded crowd, so it is not free.
const PREY_CACHE_SEC := 0.28
## Corridors end where they are aimed, so every goal here is aimed at a spot the body can
## actually stand on and this is only the slop that counts as being there.
const ARRIVE_TOLERANCE_M := 1.5
## How far from a wall voxel to look for a span the body can work from. A giant needs 11
## cells of clearance, so its standing spot is metres out from the facade it is peeling.
const FACADE_SNAP_M := 8.0

var _unit: UndeadUnit = null
var _city: CityRoot = null
var _prey: Vector3 = Vector3.INF
var _prey_at_msec: int = -1000000
## The wall voxel behind the current facade goal — the goal itself points at the span the
## body stands on, not at the solid it is there to chew.
var _facade: Vector3 = Vector3.INF
## Set when the ladder gave up on a goal: look somewhere else before looking there again.
var _wander_next: bool = false


func setup(unit: UndeadUnit, city: CityRoot) -> void:
	if unit == null:
		push_error("UndeadGoalProvider.setup: no unit")
		return
	if city == null:
		push_error("UndeadGoalProvider.setup: no city for %s" % unit.name)
		return
	_unit = unit
	_city = city


# ---------------------------------------------------------------------------
# NavGoalProvider
# ---------------------------------------------------------------------------

func next_goal(_request: NavGoalRequest) -> NavGoal:
	if not _has_unit() or not _unit.is_alive():
		return null
	if _wander_next:
		_wander_next = false
		return _wander()
	match _unit.state:
		UndeadUnit.State.SEEK_PED:
			return _hunt_or_chew()
		UndeadUnit.State.SEEK_PAD:
			return _pad()
		UndeadUnit.State.STOMP:
			return _demolish()
		UndeadUnit.State.IDLE, UndeadUnit.State.CAST, UndeadUnit.State.GROWING:
			return null
		UndeadUnit.State.NIBBLE, UndeadUnit.State.SCRAPE, UndeadUnit.State.DEAD:
			## Standing still on purpose: chewing a wall, peeling one, or dead.
			return null
		_:
			push_error(
				"UndeadGoalProvider: %s is in unknown state %d" % [_unit.name, _unit.state]
			)
			return null


func goal_reached(_request: NavGoalRequest, goal: NavGoal) -> void:
	if not _has_unit():
		return
	match goal.tag:
		TAG_HUNT:
			_unit.on_prey_in_range()
		TAG_NIBBLE:
			_unit.on_facade_in_reach(_facade, UndeadUnit.State.NIBBLE)
		TAG_DEMOLISH:
			_unit.on_facade_in_reach(_facade, UndeadUnit.State.SCRAPE)
		TAG_PAD:
			_unit.on_pad_in_reach()
		TAG_WANDER:
			pass
		_:
			push_error(
				"UndeadGoalProvider: %s reached an untagged goal %s"
				% [_unit.name, goal.describe()]
			)


## The ladder gave up. NavAgent has already counted and warned, so nothing is smoothed over
## here — but sending the body straight back at the same unreachable thing would only repeat
## it, so the next goal takes it somewhere else first.
func goal_failed(_request: NavGoalRequest, goal: NavGoal, state: NavLadder.State) -> void:
	if not _has_unit():
		return
	_prey = Vector3.INF
	_prey_at_msec = -1000000
	_facade = Vector3.INF
	_unit.on_goal_failed(goal, state)
	_wander_next = goal.tag != TAG_WANDER


# ---------------------------------------------------------------------------
# Retargeting
# ---------------------------------------------------------------------------

## Prey moves while the mage walks. Called by the unit on the crowd-query cadence rather
## than every frame, since only the hunt goal has a subject that can run away.
func retarget(agent: NavAgent) -> void:
	if not _has_unit():
		return
	var goal := agent.goal()
	if goal == null or goal.tag != TAG_HUNT:
		return
	var prey := _nearest_prey()
	if prey == Vector3.INF:
		## The soft leash: they broke the pursue range, so stop chasing.
		agent.set_goal(_wander())
		return
	if prey.distance_to(goal.point) <= RETARGET_SLACK_M:
		return
	agent.set_goal(_hunt(prey))


# ---------------------------------------------------------------------------
# The goals themselves
# ---------------------------------------------------------------------------

## SEEK_PED covers both non-giant roles: a mage hunts people, a minion hunts wall.
func _hunt_or_chew() -> NavGoal:
	if _unit.role == UndeadUnit.Role.MINION:
		return _facade_goal(UndeadUnit.MINION_BUILDING_SEEK_M, TAG_NIBBLE)
	## A mage nobody can see hunting does not pay for the crowd query.
	if _unit.nav_tier() == NavLod.Tier.FAR:
		return _wander()
	var prey := _nearest_prey()
	if prey == Vector3.INF:
		return _wander()
	return _hunt(prey)


## Aimed at the spot the mage wants to fire from, not at the prey: a corridor ends where it
## is aimed, and a goal's radius only decides whether arriving counted.
func _hunt(prey: Vector3) -> NavGoal:
	var from := _unit.global_position
	var away := from - prey
	away.y = 0.0
	var distance := away.length()
	var stand_off := _cast_stand_off_m()
	if distance <= stand_off:
		## Already in range: the goal is done where the body stands.
		return _tagged(NavGoal.go_to_point(from, ARRIVE_TOLERANCE_M), TAG_HUNT)
	return _tagged(
		NavGoal.go_to_point(prey + away / distance * stand_off, ARRIVE_TOLERANCE_M), TAG_HUNT
	)


## Stop in orb range when the mage can fire; keep closing while it cannot, which is what the
## old straight-line pursue did between casts.
func _cast_stand_off_m() -> float:
	if _unit.can_cast():
		return UndeadUnit.ORB_RANGE_M * UndeadUnit.ORB_STANDOFF_FRACTION
	return UndeadUnit.MAGE_CLOSE_IN_M


func _demolish() -> NavGoal:
	return _facade_goal(UndeadUnit.GIANT_BUILDING_SEEK_M, TAG_DEMOLISH)


## Building fabric is solid, so it is never a destination: the goal is the nearest span this
## profile can stand on beside it, and the wall voxel is remembered for the working state.
func _facade_goal(seek_m: float, tag: StringName) -> NavGoal:
	var fabric := _city.find_nearest_building_nibble(_unit.global_position, seek_m)
	if fabric == Vector3.INF:
		return _wander()
	var stand := NavService.instance().nearest_surface(
		_unit.nav_profile_id(), _approach_point(fabric), FACADE_SNAP_M
	)
	if not stand.found:
		## Nothing this body can stand on beside that wall — a giant in an alley, usually.
		return _wander()
	_facade = fabric
	return _tagged(NavGoal.go_to_point(stand.position, ARRIVE_TOLERANCE_M), tag)


## A step back out of the wall along the line the body is coming from. Snapping straight to the
## fabric voxel finds the span in *its* column, which for a facade is the roof twenty metres up;
## the body wants the street it is standing on.
func _approach_point(fabric: Vector3) -> Vector3:
	var out := _unit.global_position - fabric
	out.y = 0.0
	if out.length_squared() < 0.0001:
		return fabric
	return fabric + out.normalized() * _unit.facade_standoff_m()


func _pad() -> NavGoal:
	var pad := _unit.target_pad()
	if pad == null:
		## The pad streamed out with its district; hunting is the default again.
		_unit.abandon_pad()
		return _hunt_or_chew()
	return _tagged(NavGoal.use_target(pad, _unit.pad_reach(pad)), TAG_PAD)


func _wander() -> NavGoal:
	return _tagged(NavGoal.wander(_unit.global_position, WANDER_RADIUS_M), TAG_WANDER)


func _tagged(goal: NavGoal, tag: StringName) -> NavGoal:
	goal.tag = tag
	return goal


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Nearest pedestrian, or the player, within the mage pursue range. Vector3.INF for nobody.
func _nearest_prey() -> Vector3:
	var now := Time.get_ticks_msec()
	if now - _prey_at_msec < int(PREY_CACHE_SEC * 1000.0):
		return _prey
	_prey_at_msec = now
	_prey = _city.find_nearest_ped_position(
		_unit.global_position, UndeadUnit.MAGE_PURSUE_RANGE_M
	)
	return _prey


func _has_unit() -> bool:
	return _unit != null and is_instance_valid(_unit)
