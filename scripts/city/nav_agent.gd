## One actor's navigation brain: a typed goal from a provider, a corridor from NavService, a
## NavMotor to walk it, and the six-rung failure ladder.
##
## The ladder is the whole point. An agent that cannot reach its goal escalates through named
## states, and every rung does something specific and observable:
##
## 1. PATH_OK          — follow the corridor.
## 2. PATH_PARTIAL     — the goal is unreachable for this profile; walk to the best reachable
##                       span, then re-evaluate. `partial_retry_limit` re-evaluations, then
##                       the goal is unreachable.
## 3. NO_PROGRESS      — measured corridor advance fell below `progress_ratio` of what the
##                       motor asked for; repath inside the current sector.
## 4. BLOCKED          — local repathing did not help; write the offending column into
##                       NavService's dynamic-block overlay so every other agent routes around
##                       it too, then repath.
## 5. GOAL_UNREACHABLE — nothing routes there; abandon the goal and ask the provider for
##                       another.
## 6. TRAPPED          — entombed. can_break profiles are asked to dig; everyone else moves to
##                       the nearest span on a *different* column. Counted through CityProfiler
##                       and emitted, so the last-resort escape is loud rather than hidden the
##                       way `_unstuck_horizontal()` in undead_unit.gd was.
##
## Separate from the ladder: NEAR bodies that thrash in place (high path length, tiny net
## displacement) hop to the nearest free span within `NEARBY_UNSTUCK_VOXELS`, never the column
## they are already on. Also counted and warned.
##
## Repathing is lazy: a nav_version bump marks the corridor stale, and the agent only repaths
## after its tier's grace period — and only when `dirty_probe` says the change actually landed
## on the corridor, so one blast does not make hundreds of agents repath in the same frame.
##
## A rung is a live reading, so the two terminal ones are recorded as well as emitted:
## `state()` is back at PATH_OK one tick after the replacement goal is adopted, and
## `last_failure()` is what a consumer that samples rather than listens has to read.
class_name NavAgent
extends RefCounted

const NavLadderScript := preload("res://scripts/city/nav_ladder.gd")
const NavLodScript := preload("res://scripts/city/nav_lod.gd")
const NavGoalScript := preload("res://scripts/city/nav_goal.gd")
const NavGoalRequestScript := preload("res://scripts/city/nav_goal_request.gd")
const NavPathResultScript := preload("res://scripts/city/nav_path_result.gd")

## Corridor metres of real advance that clear the escalation counters: the agent is plainly
## moving again, so whatever it worked around is behind it.
const LADDER_RESET_M := 2.5
## An escalation that ends here without the body having moved this far is entombment, not a
## bad goal.
const LADDER_MOVE_EPSILON_M := 0.5
## Tries at picking a standable point for a WANDER goal.
const WANDER_TRIES := 6
## Nearest fraction of the wander radius a pick may land at, so wandering means going
## somewhere.
const WANDER_MIN_FRACTION := 0.35
## Short horizontal unstuck: search at most this many voxels from the feet (Chebyshev).
const NEARBY_UNSTUCK_VOXELS := 2
## Seconds of thrashing averaged before a nearby hop is considered.
const WIGGLE_WINDOW_SEC := 0.45
## Horizontal path length inside the window that counts as thrashing.
const WIGGLE_PATH_M := 0.28
## Net XZ displacement below which that path length is a wiggle, not travel.
const WIGGLE_NET_M := 0.07

signal goal_changed(goal: NavGoal)
signal ladder_changed(state: NavLadder.State)
signal path_assigned(result: NavPathResult)
## A column was written into the dynamic-block overlay. For the debug overlay.
signal column_blocked(world_pos: Vector3)
## Entombed, and this is how it got out. Never silent.
signal trapped(world_pos: Vector3, escape: NavLadder.Escape)
## A can_break profile is entombed and wants the voxels around it gone. The consumer owns the
## digging, because voxel writes belong to CityBrush and not to the nav layer.
signal dig_out_requested(world_pos: Vector3)

## World-wide event counts, so the HUD and the tests can see the ladder working.
static var _trapped_events: int = 0
static var _dig_out_events: int = 0
static var _teleport_events: int = 0
static var _nearby_unstuck_events: int = 0
static var _lost_events: int = 0
static var _blocked_columns: int = 0
static var _goal_failure_events: int = 0
static var _stale_repaths: int = 0
static var _stale_skipped: int = 0
static var _next_agent_id: int = 1

## Seconds of motion the progress test averages over.
var progress_window_sec: float = 0.6
## Fraction of the requested corridor advance that still counts as progress.
var progress_ratio: float = 0.35
## Local repaths tried before the column is blamed and blocked.
var local_repath_limit: int = 2
## How far ahead a local repath aims — one sector, so the search stays inside it.
var local_repath_ahead_m: float = float(DistrictCoord.CELL_SIZE) * 0.5
## Blocked columns written for one goal before the goal itself is the problem.
var blocked_limit: int = 2
## How long a blocked column stays blocked for everyone.
var block_seconds: float = 6.0
## Corridor ends that did not satisfy the goal before it is called unreachable.
var partial_retry_limit: int = 2
## How far a tracked target may drift before the corridor is rebuilt.
var repath_slack_m: float = 2.5
## How far from a span a body may stand and still be considered on it. Past this it is inside
## something.
var footing_tolerance_m: float = 1.5
## Search radius for the nearest span a trapped body can be put on.
var escape_radius_m: float = 12.0
## Quiet time after a TRAPPED report before a new goal is requested.
var trapped_cooldown_sec: float = 1.0
## Quiet time after a nearby wiggle-hop before another is allowed.
var nearby_unstuck_cooldown_sec: float = 0.85
## Retry delay after the provider had nothing to offer.
var idle_retry_sec: float = 0.5
## `func(points: PackedVector3Array, since_version: int) -> bool`, answering whether the
## remaining corridor crosses a sector that changed. `setup` defaults it to NavService's own
## dirty-sector probe; a consumer that wants a different answer assigns one afterwards.
## Clearing it back to an empty Callable makes every nav_version bump stale this corridor,
## which is correct but repaths far more than it has to.
var dirty_probe: Callable = Callable()

var _nav: NavService = null
var _body: Node3D = null
var _profile_id: int = -1
var _profile: NavProfile = null
var _motor: NavMotor = null
var _provider: NavGoalProvider = null
var _lod: NavLod = null
var _goal: NavGoal = null
var _destination: Vector3 = Vector3.INF
var _state: NavLadder.State = NavLadder.State.PATH_OK
var _last_result: NavPathResult = null
var _request_id: int = 0
var _tier: NavLod.Tier = NavLod.Tier.MID
var _agent_id: int = 0
var _time: float = 0.0
var _last_path_time: float = -1.0e9
var _path_version: int = 0
## When the corridor was first seen to be stale, or -1 while it is current.
var _stale_since: float = -1.0
var _progress_expected: float = 0.0
var _progress_actual: float = 0.0
var _progress_elapsed: float = 0.0
var _progress_total: float = 0.0
var _local_repaths: int = 0
var _blocks_written: int = 0
var _partial_retries: int = 0
var _ladder_origin: Vector3 = Vector3.ZERO
var _trapped_count: int = 0
var _next_goal_at: float = -1.0
## The rung the last abandoned goal died on, and when. Sticky, because `_state` is the live
## rung and the next goal resets it to PATH_OK on the following tick: a consumer that samples
## `state()` on a timer would otherwise never see a failure at all.
var _failed_state: NavLadder.State = NavLadder.State.PATH_OK
var _failed_at: float = -1.0
var _failures: int = 0
var _rng := RandomNumberGenerator.new()
## Wiggle window: thrashing path length vs net displacement while the motor wants to move.
var _wiggle_origin: Vector3 = Vector3.ZERO
var _wiggle_path_m: float = 0.0
var _wiggle_elapsed: float = 0.0
var _wiggle_wanted_m: float = 0.0
var _nearby_unstuck_ready_at: float = -1.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## `motor` is injected rather than built here: a car integrates its own motion and a test
## needs a body that refuses to move.
func setup(
	body: Node3D,
	profile_id: int,
	motor: NavMotor,
	provider: NavGoalProvider,
	lod: NavLod = null
) -> void:
	if body == null:
		push_error("NavAgent.setup: no body")
		return
	if motor == null:
		push_error("NavAgent.setup: no motor for %s" % body.name)
		return
	if provider == null:
		push_error("NavAgent.setup: no goal provider for %s" % body.name)
		return
	_nav = NavService.instance()
	if not _nav.is_configured():
		push_error("NavAgent.setup: NavService is not configured yet")
		return
	_profile = _nav.profile(profile_id)
	if _profile == null:
		return
	_body = body
	_profile_id = profile_id
	_motor = motor
	_provider = provider
	_lod = lod if lod != null else NavLodScript.new()
	## One sector, in metres, so a local repath's search stays inside the sector it started in.
	local_repath_ahead_m = float(DistrictCoord.CELL_SIZE) * _nav.voxel_size()
	if dirty_probe.is_null():
		dirty_probe = _nav.corridor_probe()
	_agent_id = _next_agent_id
	_next_agent_id += 1
	_rng.seed = hash(String(body.name)) ^ _agent_id
	_motor.setup(body, _profile)
	_motor.set_tier(_tier)
	_ladder_origin = body.global_position


## Drop the agent: cancels anything queued so the service does not serve a dead body.
func dispose() -> void:
	_cancel_request()
	if _motor != null:
		_motor.clear_path()
	_goal = null
	_provider = null


func seed_rng(value: int) -> void:
	_rng.seed = value


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func agent_id() -> int:
	return _agent_id


func state() -> NavLadder.State:
	return _state


func state_name() -> String:
	return NavLadderScript.state_name(_state)


func goal() -> NavGoal:
	return _goal


func tier() -> NavLod.Tier:
	return _tier


func motor() -> NavMotor:
	return _motor


func profile_id() -> int:
	return _profile_id


func destination() -> Vector3:
	return _destination


func has_corridor() -> bool:
	return _motor != null and _motor.has_path()


func remaining_m() -> float:
	if _motor == null:
		return 0.0
	return _motor.remaining_m()


func last_result() -> NavPathResult:
	return _last_result


func is_waiting_for_path() -> bool:
	return _request_id != 0


## How often this body has been entombed.
func trapped_count() -> int:
	return _trapped_count


## Has this agent ever abandoned a goal? True from the first failure on, so pair it with
## `failure_age_sec` to ask whether one happened recently.
func has_failed() -> bool:
	return _failed_at >= 0.0


## The rung the last abandoned goal died on — GOAL_UNREACHABLE or TRAPPED — and PATH_OK until
## one has. This is what `state()` cannot answer: the ladder is back at PATH_OK one tick after
## the next goal is adopted, so a consumer that polls only ever sees the recovery.
func last_failure() -> NavLadder.State:
	return _failed_state


func last_failure_name() -> String:
	return NavLadderScript.state_name(_failed_state)


## Seconds since the last abandoned goal, on this agent's own clock. INF when none has been.
func failure_age_sec() -> float:
	if _failed_at < 0.0:
		return INF
	return _time - _failed_at


func failure_count() -> int:
	return _failures


static func trapped_events() -> int:
	return _trapped_events


static func dig_out_events() -> int:
	return _dig_out_events


static func teleport_events() -> int:
	return _teleport_events


## Bodies that hopped off a thrashing column to a neighbour span (not a TRAPPED escape).
static func nearby_unstuck_events() -> int:
	return _nearby_unstuck_events


## TRAPPED bodies that had no span to escape to. Counted and warned about; consumers decide
## what to do with the body (the crowd despawns pedestrians).
static func lost_events() -> int:
	return _lost_events


static func blocked_columns() -> int:
	return _blocked_columns


## Goals abandoned world-wide, on either terminal rung. A HUD sampling `state()` sees none of
## these, which is why the count exists.
static func goal_failure_events() -> int:
	return _goal_failure_events


## Corridors rebuilt because an edit landed on them.
static func stale_repaths() -> int:
	return _stale_repaths


## nav_version bumps the dirty probe proved a corridor never crossed, so no repath happened.
## Against `stale_repaths` this is what the lazy-repath hook is worth.
static func stale_repaths_skipped() -> int:
	return _stale_skipped


## Tests only.
static func reset_events() -> void:
	_trapped_events = 0
	_dig_out_events = 0
	_teleport_events = 0
	_nearby_unstuck_events = 0
	_lost_events = 0
	_blocked_columns = 0
	_goal_failure_events = 0
	_stale_repaths = 0
	_stale_skipped = 0


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

## One frame for this agent. `observer_world` is what the LOD tiers are measured from — the
## player camera for peds and undead.
func tick(delta: float, observer_world: Vector3) -> void:
	if _body == null or not is_instance_valid(_body):
		push_error("NavAgent %d: ticked without a body" % _agent_id)
		return
	if _nav == null or not _nav.is_configured():
		push_error("NavAgent %d: ticked with no configured NavService" % _agent_id)
		return
	_time += delta
	_update_tier(observer_world)
	if _goal == null:
		_acquire_goal()
		return
	if not _goal.is_alive():
		## The thing being followed or used was freed: the goal cannot survive that.
		_fail_goal(NavLadder.State.GOAL_UNREACHABLE)
		return
	_track_target()
	_refresh_corridor()
	if _motor.has_path():
		_drive(delta)
	elif _request_id == 0:
		_request_path(_destination)


func _update_tier(observer_world: Vector3) -> void:
	var distance := _body.global_position.distance_to(observer_world)
	var want := _lod.tier_for(distance, _tier)
	if want == _tier:
		return
	var was_far := _tier == NavLod.Tier.FAR
	_tier = want
	_motor.set_tier(want)
	## Coming in from the far tier, the interpolated corridor was bought with a coarse budget;
	## a body that is about to be watched gets a fine one.
	if was_far and _goal != null and _request_id == 0:
		_request_path(_destination)


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

## Replace the goal from outside — a director reacting to a blast, say. The ladder restarts.
func set_goal(goal: NavGoal) -> void:
	if goal == null:
		push_error("NavAgent %d: set_goal(null); use abandon_goal()" % _agent_id)
		return
	_adopt_goal(goal)


func abandon_goal() -> void:
	_goal = null
	_cancel_request()
	_motor.clear_path()


func _acquire_goal() -> void:
	if _time < _next_goal_at:
		return
	var goal := _provider.next_goal(_make_request(_state, null))
	if goal == null:
		## Nothing to do is legitimate; ask again shortly.
		_next_goal_at = _time + idle_retry_sec
		return
	_adopt_goal(goal)


func _adopt_goal(goal: NavGoal) -> void:
	_goal = goal
	_reset_ladder()
	_enter_state(NavLadder.State.PATH_OK)
	if not _resolve_destination():
		## The provider asked for somewhere this body cannot stand: that is its problem to fix.
		_fail_goal(NavLadder.State.GOAL_UNREACHABLE)
		return
	goal_changed.emit(goal)
	_request_path(_destination)


## Where this goal wants the body right now. False when a WANDER goal has nowhere to go.
func _resolve_destination() -> bool:
	var pos := _body.global_position
	if not _goal.needs_destination_pick():
		## No snapping: NavService resolves the goal onto a span itself and says NO_GOAL when
		## it cannot, which is the answer the ladder wants.
		_destination = _goal.raw_destination(pos)
		return true
	## Horizontal ring first, then every standable height in that column inside the wander
	## radius. That keeps the probe cheap (one column, no ring search) while still letting
	## crypt undead pick the chapel floor above them.
	for _try in range(WANDER_TRIES):
		var angle := _rng.randf() * TAU
		var reach := _goal.radius * lerpf(WANDER_MIN_FRACTION, 1.0, _rng.randf())
		var probe := _goal.point + Vector3(sin(angle) * reach, 0.0, cos(angle) * reach)
		var surfaces: PackedVector3Array = _nav.column_surfaces(
			_profile_id, probe, _goal.radius
		)
		if surfaces.is_empty():
			continue
		_destination = surfaces[_rng.randi_range(0, surfaces.size() - 1)]
		return true
	push_warning(
		"NavAgent %d: no %s span within %.1f m of the wander anchor %.1f,%.1f"
		% [_agent_id, _profile.display_name, _goal.radius, _goal.point.x, _goal.point.z]
	)
	return false


## Tracked goals move. Rebuild the corridor when the subject has drifted, no more often than
## the tier allows.
func _track_target() -> void:
	if not _goal.tracks_target():
		return
	if _request_id != 0:
		return
	var raw := _goal.raw_destination(_body.global_position)
	if raw.distance_to(_destination) <= repath_slack_m:
		return
	if _time - _last_path_time < _lod.repath_interval_sec(_tier):
		return
	_destination = raw
	_request_path(_destination)


## Lazy invalidation, plus the far tier's own corridor clock.
func _refresh_corridor() -> void:
	if _request_id != 0:
		return
	if _tier == NavLod.Tier.FAR:
		if _time - _last_path_time >= _lod.far_corridor_sec:
			_request_path(_destination)
		return
	if _last_result == null or _nav.version() == _path_version:
		_stale_since = -1.0
		return
	if not _corridor_is_dirty():
		## The field changed somewhere this corridor does not go.
		_path_version = _nav.version()
		_stale_since = -1.0
		_stale_skipped += 1
		CityProfiler.add_counter("nav_stale_skipped")
		return
	if _stale_since < 0.0:
		_stale_since = _time
		return
	if _time - _stale_since >= _lod.stale_grace_sec(_tier):
		_stale_repaths += 1
		CityProfiler.add_counter("nav_stale_repaths")
		_request_path(_destination)


func _corridor_is_dirty() -> bool:
	if dirty_probe.is_null():
		return true
	if not dirty_probe.is_valid():
		push_error("NavAgent %d: dirty_probe is dead" % _agent_id)
		return true
	return bool(dirty_probe.call(_motor.remaining_points(), _path_version))


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

func _request_path(to_world: Vector3) -> void:
	if to_world == Vector3.INF:
		push_error("NavAgent %d: asked for a path to nowhere" % _agent_id)
		return
	_cancel_request()
	_last_path_time = _time
	_stale_since = -1.0
	_request_id = _nav.request_path(
		_profile_id,
		_body.global_position,
		to_world,
		_on_path,
		_lod.path_budget(_tier)
	)
	if _request_id == 0:
		push_error("NavAgent %d: NavService refused the request" % _agent_id)


func _cancel_request() -> void:
	if _request_id == 0:
		return
	_nav.cancel_path(_request_id)
	_request_id = 0


func _on_path(result: NavPathResult) -> void:
	if result.request_id != _request_id:
		## Cancelled requests never call back, so this means one was served anyway.
		push_error(
			"NavAgent %d: served request %d while waiting for %d"
			% [_agent_id, result.request_id, _request_id]
		)
		return
	_request_id = 0
	_last_result = result
	_path_version = result.nav_version
	_stale_since = -1.0
	path_assigned.emit(result)
	if _goal == null:
		## The goal was abandoned while the query sat in the queue.
		return
	match result.status:
		NavPathResult.Status.NO_START:
			## Nowhere to start from: the body is not standing anywhere navigable.
			_escalate(NavLadder.State.TRAPPED)
		NavPathResult.Status.NO_GOAL, NavPathResult.Status.UNREACHABLE:
			_escalate(NavLadder.State.GOAL_UNREACHABLE)
		NavPathResult.Status.OK, NavPathResult.Status.BREACH:
			## BREACH is a real corridor for a can_break profile; the wall in the way is the
			## consumer's to remove, and until it does the progress test will say so.
			_adopt_corridor(result, NavLadder.State.PATH_OK)
		NavPathResult.Status.PARTIAL:
			_adopt_corridor(result, NavLadder.State.PATH_PARTIAL)
		_:
			push_error("NavAgent %d: unknown status %d" % [_agent_id, result.status])


func _adopt_corridor(result: NavPathResult, reached_state: NavLadder.State) -> void:
	## Entombment is about where the body is, not what the search returned: a snapped start can
	## hand a mob a perfectly good corridor that begins inside a collapsed building, and
	## span-following would walk it out of solid rock without anyone noticing. One bounded
	## nearest_surface per adopted corridor is the price of that never being quiet.
	if _motor.is_supported() and _footing_is_invalid():
		_escalate(NavLadder.State.TRAPPED)
		return
	if result.points.size() < 2:
		## Start and goal are the same span. Nothing to walk, so judge it as an arrival.
		_on_corridor_end()
		return
	_motor.set_path(result)
	_reset_progress()
	_enter_state(reached_state)


# ---------------------------------------------------------------------------
# Rung 1 and 2: follow, and re-evaluate a partial corridor
# ---------------------------------------------------------------------------

func _drive(delta: float) -> void:
	var step := _motor.advance(delta)
	var gained := maxf(step.advanced_m, 0.0)
	_progress_total += gained
	if _progress_total >= LADDER_RESET_M:
		## Demonstrably moving again: whatever was worked around is behind us.
		_reset_ladder()
	if _lod.detects_no_progress(_tier):
		_progress_expected += step.expected_m
		_progress_actual += gained
		_progress_elapsed += delta
		if _note_wiggle(step, delta):
			return
	if step.arrived:
		_on_corridor_end()
		return
	if _progress_elapsed >= progress_window_sec:
		_judge_progress()


func _on_corridor_end() -> void:
	_motor.clear_path()
	var pos := _body.global_position
	if _goal.is_satisfied(pos, _destination):
		if _goal.is_persistent():
			## FOLLOW holds its distance and waits for the subject to move again.
			return
		_complete_goal()
		return
	_partial_retries += 1
	if _partial_retries > partial_retry_limit:
		_escalate(NavLadder.State.GOAL_UNREACHABLE)
		return
	## Either the corridor was PARTIAL and this is the best reachable span, or the goal moved.
	## Either way the answer is the same: look again from here.
	if not _resolve_destination():
		_fail_goal(NavLadder.State.GOAL_UNREACHABLE)
		return
	_request_path(_destination)


# ---------------------------------------------------------------------------
# Rung 3 and 4: no progress, then blame a column
# ---------------------------------------------------------------------------

## Did the body cover a believable fraction of what the motor asked for?
func _judge_progress() -> void:
	var expected := _progress_expected
	var actual := _progress_actual
	_reset_progress()
	if expected <= 0.0:
		return
	if actual >= expected * progress_ratio:
		return
	_local_repaths += 1
	CityProfiler.add_counter("nav_no_progress")
	if _local_repaths > local_repath_limit:
		_block_and_repath()
		return
	_enter_state(NavLadder.State.NO_PROGRESS)
	## Inside the sector only: the corridor is probably right and one cell of it is wrong.
	var ahead := _motor.point_ahead(local_repath_ahead_m)
	if ahead == Vector3.INF:
		_request_path(_destination)
		return
	_request_path(ahead)


func _block_and_repath() -> void:
	_enter_state(NavLadder.State.BLOCKED)
	_local_repaths = 0
	var offender := _motor.next_point()
	if offender == Vector3.INF:
		offender = _body.global_position
	_nav.block_column(offender, block_seconds)
	_blocks_written += 1
	_blocked_columns += 1
	CityProfiler.add_counter("nav_blocked_columns")
	column_blocked.emit(offender)
	if _blocks_written > blocked_limit:
		## Blocking our way out twice over and still stuck: it is not the column.
		_escalate(NavLadder.State.GOAL_UNREACHABLE)
		return
	_motor.clear_path()
	_request_path(_destination)


# ---------------------------------------------------------------------------
# Rung 5 and 6: abandon the goal, or admit the body is entombed
# ---------------------------------------------------------------------------

## GOAL_UNREACHABLE turns into TRAPPED when the body is the problem rather than the goal.
func _escalate(state: NavLadder.State) -> void:
	if not NavLadderScript.is_terminal(state):
		push_error(
			"NavAgent %d: %s is not a rung a goal can be abandoned on"
			% [_agent_id, NavLadderScript.state_name(state)]
		)
		return
	if state == NavLadder.State.GOAL_UNREACHABLE:
		var entombed := _footing_is_invalid()
		var went_nowhere := (
			_blocks_written > 0
			and _body.global_position.distance_to(_ladder_origin) < LADDER_MOVE_EPSILON_M
		)
		if entombed or went_nowhere:
			_escalate(NavLadder.State.TRAPPED)
			return
	_enter_state(state)
	if state == NavLadder.State.TRAPPED:
		_report_trapped()
	else:
		CityProfiler.add_counter("nav_goal_unreachable")
	_fail_goal(state)


## Standing inside something, or on a span no profile of this size can occupy.
func _footing_is_invalid() -> bool:
	var pos := _body.global_position
	var hit := _nav.nearest_surface(_profile_id, pos, escape_radius_m)
	if not hit.found:
		return true
	return pos.distance_to(hit.position) > footing_tolerance_m


## Every entombment is counted and emitted. Nothing here is quiet.
func _report_trapped() -> void:
	_trapped_count += 1
	_trapped_events += 1
	CityProfiler.note_event("nav_trapped")
	CityProfiler.add_counter("nav_trapped")
	var pos := _body.global_position
	var escape := NavLadder.Escape.NONE
	if _profile.can_break:
		if dig_out_requested.get_connections().is_empty():
			push_error(
				(
					"NavAgent %d: %s can break out but nothing listens for"
					+ " dig_out_requested — moving it instead"
				)
				% [_agent_id, _profile.display_name]
			)
		else:
			dig_out_requested.emit(pos)
			_dig_out_events += 1
			escape = NavLadder.Escape.DUG_OUT
	if escape == NavLadder.Escape.NONE:
		escape = _escape_to_nearest_span(pos)
	push_warning(
		"NavAgent %d (%s) TRAPPED at %.1f,%.1f,%.1f goal=%s escape=%s (%d so far)"
		% [
			_agent_id,
			_profile.display_name,
			pos.x,
			pos.y,
			pos.z,
			_goal.describe() if _goal != null else "<none>",
			NavLadderScript.escape_name(escape),
			_trapped_events,
		]
	)
	trapped.emit(pos, escape)
	_next_goal_at = _time + trapped_cooldown_sec


func _escape_to_nearest_span(from: Vector3) -> NavLadder.Escape:
	## Prefer a neighbour column first — the span under the feet is what pinned the body.
	var spot := _find_free_span_excluding_column(from, NEARBY_UNSTUCK_VOXELS)
	if spot == Vector3.INF:
		spot = _find_escape_span(from, escape_radius_m)
	if spot == Vector3.INF:
		spot = _find_escape_span(from, escape_radius_m * 3.0)
	if spot == Vector3.INF:
		## Last resort: any span in range, even the current column (better than LOST).
		var hit := _nav.nearest_surface(_profile_id, from, escape_radius_m * 3.0)
		if hit.found:
			spot = hit.position
	if spot == Vector3.INF:
		_lost_events += 1
		## A warning, not an error: the crowd despawns LOST pedestrians, and shouting about a
		## single stuck ped as a script fault floods the overlay for something that is scenery.
		push_warning(
			"NavAgent %d: entombed at %.1f,%.1f,%.1f with no %s span within %.1f m"
			% [
				_agent_id,
				from.x,
				from.y,
				from.z,
				_profile.display_name,
				escape_radius_m * 3.0,
			]
		)
		return NavLadder.Escape.LOST
	_body.global_position = spot
	if _body is CharacterBody3D:
		(_body as CharacterBody3D).velocity = Vector3.ZERO
	_teleport_events += 1
	return NavLadder.Escape.TELEPORTED


## Wider than the 2-voxel hop: nearest span on another column, Y unrestricted (entombment).
func _find_escape_span(from: Vector3, radius_m: float) -> Vector3:
	var origin_col := _nav.column_of(from)
	var hit := _nav.nearest_surface(_profile_id, from, radius_m)
	if hit.found and _nav.column_of(hit.position) != origin_col:
		return hit.position
	var vs := _nav.voxel_size()
	if vs <= 0.0:
		return Vector3.INF
	var max_v := maxi(1, ceili(radius_m / vs))
	var best := Vector3.INF
	var best_d := INF
	for dist in range(1, max_v + 1):
		var steps := mini(16, 4 * dist)
		for i in range(steps):
			var ang := TAU * float(i) / float(steps)
			var probe := from + Vector3(sin(ang) * float(dist) * vs, 0.0, cos(ang) * float(dist) * vs)
			var h := _nav.nearest_surface(_profile_id, probe, vs * 0.8)
			if not h.found:
				continue
			if _nav.column_of(h.position) == origin_col:
				continue
			var d := from.distance_to(h.position)
			if d < best_d:
				best_d = d
				best = h.position
		if best != Vector3.INF:
			return best
	return best


## High path length + tiny net displacement while the motor still wants to walk: hop off the
## column. A motor that freezes the body (zero `moved`) does not trip this — that stays on the
## ladder so BLOCKED / TRAPPED keep their meaning.
func _note_wiggle(step: NavMotor.Step, delta: float) -> bool:
	var path_step := Vector2(step.moved.x, step.moved.z).length()
	if _wiggle_elapsed <= 0.0:
		_wiggle_origin = _body.global_position - step.moved
		_wiggle_path_m = 0.0
		_wiggle_wanted_m = 0.0
	_wiggle_path_m += path_step
	_wiggle_wanted_m += maxf(step.expected_m, 0.0)
	_wiggle_elapsed += delta
	if _wiggle_elapsed < WIGGLE_WINDOW_SEC:
		return false
	var net := Vector2(
		_body.global_position.x - _wiggle_origin.x,
		_body.global_position.z - _wiggle_origin.z
	).length()
	var thrashing := (
		_wiggle_wanted_m > 0.05
		and _wiggle_path_m >= WIGGLE_PATH_M
		and net <= WIGGLE_NET_M
	)
	_reset_wiggle()
	if not thrashing:
		return false
	return _try_nearby_unstuck()


func _try_nearby_unstuck() -> bool:
	if _time < _nearby_unstuck_ready_at:
		return false
	var from := _body.global_position
	var spot := _find_free_span_excluding_column(from, NEARBY_UNSTUCK_VOXELS)
	if spot == Vector3.INF:
		return false
	var before := from
	_body.global_position = spot
	if _body is CharacterBody3D:
		(_body as CharacterBody3D).velocity = Vector3.ZERO
	_nearby_unstuck_events += 1
	_teleport_events += 1
	CityProfiler.add_counter("nav_nearby_unstuck")
	_nearby_unstuck_ready_at = _time + nearby_unstuck_cooldown_sec
	push_warning(
		(
			"NavAgent %d (%s) nearby unstuck %.1f,%.1f,%.1f -> %.1f,%.1f,%.1f (≤%d voxels)"
			% [
				_agent_id,
				_profile.display_name,
				before.x,
				before.y,
				before.z,
				spot.x,
				spot.y,
				spot.z,
				NEARBY_UNSTUCK_VOXELS,
			]
		)
	)
	_reset_progress()
	_reset_wiggle()
	_local_repaths = 0
	_motor.clear_path()
	_request_path(_destination)
	_enter_state(NavLadder.State.NO_PROGRESS)
	return true


## Nearest profile-valid span within `max_voxels` Chebyshev of `from`, never the column the
## body is already standing on. Horizontal preference: reject climbs/drops past max_step.
func _find_free_span_excluding_column(from: Vector3, max_voxels: int) -> Vector3:
	if max_voxels < 1:
		return Vector3.INF
	var vs := _nav.voxel_size()
	if vs <= 0.0:
		return Vector3.INF
	var origin_col := _nav.column_of(from)
	var best := Vector3.INF
	var best_d := INF
	var max_dy := vs * maxf(_profile.max_step, 1.0)
	var max_flat := vs * float(max_voxels) + vs * 0.51
	for dz in range(-max_voxels, max_voxels + 1):
		for dx in range(-max_voxels, max_voxels + 1):
			if dx == 0 and dz == 0:
				continue
			if maxi(absi(dx), absi(dz)) > max_voxels:
				continue
			var probe := Vector3(from.x + float(dx) * vs, from.y, from.z + float(dz) * vs)
			var hit := _nav.nearest_surface(_profile_id, probe, vs * 0.65)
			if not hit.found:
				continue
			if _nav.column_of(hit.position) == origin_col:
				continue
			if absf(hit.position.y - from.y) > max_dy:
				continue
			var flat := Vector2(hit.position.x - from.x, hit.position.z - from.z).length()
			if flat > max_flat:
				continue
			if flat < best_d:
				best_d = flat
				best = hit.position
	return best


func _reset_wiggle() -> void:
	_wiggle_elapsed = 0.0
	_wiggle_path_m = 0.0
	_wiggle_wanted_m = 0.0
	_wiggle_origin = Vector3.ZERO


# ---------------------------------------------------------------------------
# Goal lifecycle
# ---------------------------------------------------------------------------

## Ending a goal never asks for the next one from here: the following tick does that, so one
## tick can only ever adopt one goal. A provider handing out goals that are already satisfied,
## or that fail on adoption, would otherwise recurse until the stack ran out.
func _complete_goal() -> void:
	var done := _goal
	_goal = null
	_cancel_request()
	_enter_state(NavLadder.State.PATH_OK)
	_provider.goal_reached(_make_request(NavLadder.State.PATH_OK, done), done)


## Every abandoned goal enters its rung and is recorded here, not only at the escalation that
## reached it: a freed Follow subject and a destination the profile cannot stand on both land
## straight on this, and used to leave the ladder reading PATH_OK.
func _fail_goal(state: NavLadder.State) -> void:
	if not NavLadderScript.is_terminal(state):
		push_error(
			"NavAgent %d: a goal cannot be abandoned on %s"
			% [_agent_id, NavLadderScript.state_name(state)]
		)
	_enter_state(state)
	_failed_state = state
	_failed_at = _time
	_failures += 1
	_goal_failure_events += 1
	CityProfiler.add_counter("nav_goal_failed")
	var lost := _goal
	_goal = null
	_cancel_request()
	_motor.clear_path()
	if lost != null:
		_provider.goal_failed(_make_request(state, lost), lost, state)


func _make_request(state: NavLadder.State, goal: NavGoal) -> NavGoalRequest:
	var req: NavGoalRequest = NavGoalRequestScript.new()
	req.body = _body
	req.agent_id = _agent_id
	req.position = _body.global_position
	req.profile_id = _profile_id
	req.last_state = state
	req.last_goal = goal
	req.trapped_count = _trapped_count
	return req


# ---------------------------------------------------------------------------
# Bookkeeping
# ---------------------------------------------------------------------------

func _enter_state(state: NavLadder.State) -> void:
	if _state == state:
		return
	_state = state
	ladder_changed.emit(state)


func _reset_progress() -> void:
	_progress_expected = 0.0
	_progress_actual = 0.0
	_progress_elapsed = 0.0


func _reset_ladder() -> void:
	_reset_progress()
	_reset_wiggle()
	_progress_total = 0.0
	_local_repaths = 0
	_blocks_written = 0
	_partial_retries = 0
	_ladder_origin = _body.global_position
