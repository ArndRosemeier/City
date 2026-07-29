## NavMotor, NavAgent, the goal layer and the six-rung failure ladder.
##
## One hand-painted tile carries every case: a flat deck with a sealed eight-voxel block on it,
## which is a reachable goal, an unreachable goal (its roof), a body to entomb (inside it) and
## an obstacle to blame — stated geometry instead of whatever a district happens to generate.
##
## The synthetic agent is a bare Node3D. That is the point: nothing in this stack is a
## consumer, so undead, peds and cars can all be ported onto it later.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_nav_agent.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
## Deep enough that headroom is never the reason a span is missing.
const FIELD_Y_MAX := 47

## The one test tile, parked far from every real district and from test_nav_service's tiles.
const TILE := Vector2i(70, 70)
const ORIGIN := Vector3i(30000, 0, 30000)
const SX := 112
const SZ := 84
## A sealed brick block on the deck: 8 voxels tall, so its roof is 4 m up and a pedestrian
## (max_drop 1.5 m, no climbing) can neither get up nor down.
const BLOCK_MIN := Vector3i(64, 1, 36)
const BLOCK_MAX := Vector3i(80, 9, 48)

## Second tile, registered only to bump nav_version. Nowhere near the first.
const DIRTY_TILE := Vector2i(90, 90)
const DIRTY_ORIGIN := Vector3i(40000, 0, 40000)
const DIRTY_SIZE := 32

## An undead that can also break, for the dig-out branch of TRAPPED.
const PROFILE_DIGGER := 110

## Fixed simulation step: the agents are ticked by hand, so the test does not depend on the
## headless frame rate.
const SIM_DT := 0.05
## Frames one case may spend before it counts as hung.
const MAX_FRAMES := 600
## Slop allowed when a link traversal is asked to hold a line.
const LINK_TOLERANCE_M := 0.01

var _failed := false
var _nav: NavService
var _paths_seen: int = 0
var _states: Array[int] = []
var _blocked_at: Array[Vector3] = []
var _trapped_at: Array[Vector3] = []
var _escapes: Array[int] = []
var _dug_at: Array[Vector3] = []


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return
	var digger := NavProfile.undead().duplicate_as(PROFILE_DIGGER, "digger")
	digger.can_break = true
	_nav.register_profile(digger)
	if not _nav.register_district(TILE, _bake_tile()):
		_fail("FAIL NavService refused the test tile")
		_quit()
		return

	_test_tiers()
	if _failed:
		_quit()
		return
	_test_link_routines()
	if _failed:
		_quit()
		return
	await _test_go_to_point()
	if _failed:
		_quit()
		return
	await _test_near_tier()
	if _failed:
		_quit()
		return
	await _test_partial_budget()
	if _failed:
		_quit()
		return
	await _test_partial_then_unreachable()
	if _failed:
		_quit()
		return
	await _test_failure_is_observable()
	if _failed:
		_quit()
		return
	await _test_no_progress_and_blocked()
	if _failed:
		_quit()
		return
	await _test_trapped_teleport()
	if _failed:
		_quit()
		return
	await _test_trapped_dig_out()
	if _failed:
		_quit()
		return
	await _test_trapped_lost()
	if _failed:
		_quit()
		return
	await _test_lazy_repath()
	if _failed:
		_quit()
		return
	await _test_tier_switch_continuity()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# LOD thresholds
# ---------------------------------------------------------------------------

## The bands, and that hysteresis needs real movement in either direction to switch.
func _test_tiers() -> void:
	var lod := NavLod.for_collision_view(48, VOXEL_SIZE)
	if not is_equal_approx(lod.near_radius_m, 20.0):
		_fail("FAIL a 48 voxel collision viewer gives a %.1f m near band" % lod.near_radius_m)
		return
	if lod.tier_for(5.0, NavLod.Tier.MID) != NavLod.Tier.NEAR:
		_fail("FAIL 5 m is not near")
		return
	if lod.tier_for(21.0, NavLod.Tier.NEAR) != NavLod.Tier.NEAR:
		_fail("FAIL hysteresis did not hold 21 m in the near band")
		return
	if lod.tier_for(21.0, NavLod.Tier.MID) != NavLod.Tier.MID:
		_fail("FAIL 21 m re-entered the near band without crossing 20 m")
		return
	if lod.tier_for(27.0, NavLod.Tier.NEAR) != NavLod.Tier.MID:
		_fail("FAIL 27 m stayed near")
		return
	if lod.tier_for(84.0, NavLod.Tier.MID) != NavLod.Tier.MID:
		_fail("FAIL hysteresis did not hold 84 m in the mid band")
		return
	if lod.tier_for(84.0, NavLod.Tier.FAR) != NavLod.Tier.FAR:
		_fail("FAIL 84 m re-entered the mid band without crossing 80 m")
		return
	if lod.tier_for(200.0, NavLod.Tier.MID) != NavLod.Tier.FAR:
		_fail("FAIL 200 m stayed mid")
		return
	if lod.detects_no_progress(NavLod.Tier.FAR):
		_fail("FAIL a far agent, whose motion is a lerp, can report NO_PROGRESS")
		return
	if not is_equal_approx(lod.far_corridor_sec, 30.0):
		_fail("FAIL far corridors refresh every %.1f s" % lod.far_corridor_sec)
		return
	print(
		"tiers: near<=%.0f m mid<=%.0f m hysteresis %.0f m far corridor %.0f s budget %d"
		% [
			lod.near_radius_m,
			lod.mid_radius_m,
			lod.hysteresis_m,
			lod.far_corridor_sec,
			lod.path_budget(NavLod.Tier.FAR),
		]
	)


# ---------------------------------------------------------------------------
# One traversal routine per link kind
# ---------------------------------------------------------------------------

## A hand-built corridor with all four link kinds in it, so each routine is pinned without
## depending on what the bake decided to emit on a given facade.
func _test_link_routines() -> void:
	var body := Node3D.new()
	body.name = "LinkWalker"
	add_child(body)
	body.global_position = Vector3.ZERO

	var motor := NavMotor.new()
	motor.setup(body, _nav.profile(NavProfile.Id.UNDEAD))
	motor.set_tier(NavLod.Tier.MID)
	var climb_top := Vector3(4.0, 4.0, 0.0)
	var path := _corridor(
		[
			Vector3(0.0, 0.0, 0.0),
			Vector3(4.0, 0.0, 0.0),
			climb_top,
			Vector3(8.0, 4.0, 0.0),
			Vector3(8.0, 0.0, 0.0),
			Vector3(11.0, 0.0, 0.0),
		],
		[
			NavPathResult.LINK_WALK,
			NavPathResult.LINK_WALK,
			NavPathResult.LINK_CLIMB,
			NavPathResult.LINK_WALK,
			NavPathResult.LINK_DROP,
			NavPathResult.LINK_JUMP,
		]
	)
	motor.set_path(path)
	if not motor.has_path():
		_fail("FAIL the motor refused a hand-built corridor")
		return
	if not is_equal_approx(motor.total_m(), 4.0 + 4.0 + 4.0 + 4.0 + 3.0):
		_fail("FAIL corridor arc length is %.2f m" % motor.total_m())
		return

	var seen: Dictionary[int, int] = {}
	var climb_drift := 0.0
	var jump_apex := -1.0
	var drop_start := -1.0
	var drop_end := -1.0
	var elapsed := 0.0
	var arrived := false
	for _frame in range(MAX_FRAMES):
		var was := body.global_position
		var step := motor.advance(SIM_DT)
		elapsed += SIM_DT
		seen[step.link] = int(seen.get(step.link, 0)) + 1
		match step.link:
			NavPathResult.LINK_CLIMB:
				## Only while ascending: once the top is within reach the routine mounts the
				## landing span, which is horizontal by design.
				if body.global_position.y < climb_top.y - NavMotor.LINK_EPSILON_M:
					var here := body.global_position
					climb_drift = maxf(
						climb_drift, Vector2(here.x - was.x, here.z - was.z).length()
					)
			NavPathResult.LINK_DROP:
				if drop_start < 0.0:
					drop_start = elapsed
				drop_end = elapsed
			NavPathResult.LINK_JUMP:
				jump_apex = maxf(jump_apex, body.global_position.y)
		if step.arrived:
			arrived = true
			break
	if not arrived:
		_fail("FAIL the corridor was not consumed in %d ticks" % MAX_FRAMES)
		return
	for kind: int in [
		NavPathResult.LINK_WALK,
		NavPathResult.LINK_CLIMB,
		NavPathResult.LINK_DROP,
		NavPathResult.LINK_JUMP,
	]:
		if not seen.has(kind):
			_fail("FAIL link kind %d was never traversed" % kind)
			return
	var end := body.global_position
	if end.distance_to(Vector3(11.0, 0.0, 0.0)) > 0.01:
		_fail("FAIL the body ended at %.2f,%.2f,%.2f" % [end.x, end.y, end.z])
		return
	## Climbing holds the take-off column: a facade traversal that drifts sideways ends up
	## inside the wall.
	if climb_drift > LINK_TOLERANCE_M:
		_fail("FAIL the climb drifted %.3f m off its column in one tick" % climb_drift)
		return
	## 4 m at climb_speed 1.15 m/s, and no faster.
	var climb_ticks := int(seen[NavPathResult.LINK_CLIMB])
	var climb_sec := float(climb_ticks) * SIM_DT
	if climb_sec < 4.0 / motor.climb_speed_mps:
		_fail("FAIL a 4 m climb took %.2f s, faster than climb_speed" % climb_sec)
		return
	## Falling accelerates, so 4 m of drop is far quicker than 4 m of climbing.
	var drop_sec := drop_end - drop_start + SIM_DT
	if drop_sec >= climb_sec:
		_fail("FAIL a 4 m drop took %.2f s and the climb %.2f s" % [drop_sec, climb_sec])
		return
	## The jump arcs over the straight line instead of sliding along it.
	if jump_apex < motor.jump_arc_m * 0.5 or jump_apex > motor.jump_arc_m * 1.1:
		_fail("FAIL the jump apex is %.2f m, arc is %.2f m" % [jump_apex, motor.jump_arc_m])
		return
	print(
		"links: walk=%d climb=%d (%.2f s, drift %.3f m) drop=%d (%.2f s) jump=%d (apex %.2f m)"
		% [
			int(seen[NavPathResult.LINK_WALK]),
			climb_ticks,
			climb_sec,
			climb_drift,
			int(seen[NavPathResult.LINK_DROP]),
			drop_sec,
			int(seen[NavPathResult.LINK_JUMP]),
			jump_apex,
		]
	)
	body.queue_free()


# ---------------------------------------------------------------------------
# Rung 1: a goal is reached
# ---------------------------------------------------------------------------

func _test_go_to_point() -> void:
	var start := _w(Vector3i(12, 1, 20))
	var goal_at := _w(Vector3i(72, 1, 20))
	var body := _make_body("Walker", start)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue)

	var frames := await _run(agent, body, func() -> bool: return queue.reached() > 0, 40.0)
	if queue.reached() != 1:
		_fail(
			"FAIL GoToPoint was not reached in %d ticks (state %s, %.1f m short)"
			% [frames, agent.state_name(), body.global_position.distance_to(goal_at)]
		)
		return
	if agent.state() != NavLadder.State.PATH_OK:
		_fail("FAIL a reached goal left the ladder at %s" % agent.state_name())
		return
	if body.global_position.distance_to(goal_at) > 1.5:
		_fail(
			"FAIL the body stopped %.2f m from the goal"
			% body.global_position.distance_to(goal_at)
		)
		return
	if agent.goal() != null:
		_fail("FAIL the agent kept a goal after reaching it")
		return
	## A finished goal makes the agent ask for the next one, which is what keeps an actor busy.
	await _tick(agent, body, 2, 40.0)
	if queue.asked() < 2:
		_fail("FAIL the provider was asked %d times, expected a second goal" % queue.asked())
		return
	print(
		"GoToPoint: %.1f m in %d ticks (%.1f s), provider asked %d times, tier %s"
		% [
			start.distance_to(goal_at),
			frames,
			float(frames) * SIM_DT,
			queue.asked(),
			NavLod.tier_name(agent.tier()),
		]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Near tier: the same corridor, driven through VoxelBodyMotion
# ---------------------------------------------------------------------------

## Headless has no VoxelTerrain, so VoxelBoxMover has no voxels to collide with and
## VoxelBodyMotion integrates the velocity directly. What this pins is the near-tier wiring:
## the collider path runs, reports NEAR, and walks the same corridor. Gravity is off because
## without terrain there is no floor to land on.
func _test_near_tier() -> void:
	var start := _w(Vector3i(12, 1, 60))
	var goal_at := _w(Vector3i(40, 1, 60))
	var character := _make_character("NearWalker", start)
	var motor := _collider_motor(character)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(character, NavProfile.Id.PEDESTRIAN, motor, queue)

	var frames := await _run(agent, character, func() -> bool: return queue.reached() > 0, 5.0)
	if queue.reached() != 1:
		_fail(
			"FAIL the near-tier agent did not arrive in %d ticks (state %s)"
			% [frames, agent.state_name()]
		)
		return
	if agent.tier() != NavLod.Tier.NEAR:
		_fail("FAIL a body 5 m from the observer is %s" % NavLod.tier_name(agent.tier()))
		return
	if not motor.can_use_collider():
		_fail("FAIL the motor lost its collider")
		return
	print(
		"near tier: %.1f m through VoxelBoxMover in %d ticks"
		% [start.distance_to(goal_at), frames]
	)
	agent.dispose()
	character.queue_free()


# ---------------------------------------------------------------------------
# Rung 2: a partial corridor is walked, then re-evaluated
# ---------------------------------------------------------------------------

## A budget too small to reach the goal returns the best reachable span. The agent must walk
## that and ask again from there, arriving in several bites rather than giving up.
func _test_partial_budget() -> void:
	## Past the block, so the search has to work for its route instead of walking a straight
	## line across empty deck.
	var start := _w(Vector3i(8, 1, 42))
	var goal_at := _w(Vector3i(100, 1, 42))
	var body := _make_body("Partial", start)
	var lod := NavLod.new()
	lod.mid_budget = 200
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue, lod)
	_states.clear()
	_paths_seen = 0
	agent.ladder_changed.connect(_on_ladder)
	agent.path_assigned.connect(_on_path)

	var frames := await _run(agent, body, func() -> bool: return queue.reached() > 0, 40.0)
	if queue.reached() != 1:
		_fail(
			"FAIL a budget-limited walk did not finish in %d ticks (state %s, %.1f m left)"
			% [frames, agent.state_name(), body.global_position.distance_to(goal_at)]
		)
		return
	if not _states.has(int(NavLadder.State.PATH_PARTIAL)):
		_fail(
			"FAIL a %d expansion budget never produced PATH_PARTIAL: %s"
			% [lod.mid_budget, str(_states)]
		)
		return
	if _paths_seen < 2:
		_fail("FAIL the agent finished on %d paths, so nothing was re-evaluated" % _paths_seen)
		return
	print(
		"PATH_PARTIAL: %.1f m walked over %d corridors in %d ticks"
		% [start.distance_to(goal_at), _paths_seen, frames]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Rung 5: the goal itself is impossible
# ---------------------------------------------------------------------------

## The block's roof is 4 m up with no climb link for a pedestrian, so the corridor stops
## beside it forever. After `partial_retry_limit` re-evaluations the goal is abandoned and the
## provider hands out a reachable one instead.
func _test_partial_then_unreachable() -> void:
	var start := _w(Vector3i(20, 1, 42))
	var roof := _w(Vector3i(72, 10, 42))
	var second := _w(Vector3i(20, 1, 12))
	var body := _make_body("Unreachable", start)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(roof, 1.5))
	queue.add(NavGoal.go_to_point(second, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue)
	_states.clear()
	agent.ladder_changed.connect(_on_ladder)

	var frames := await _run(agent, body, func() -> bool: return queue.reached() > 0, 60.0)
	if queue.failed() != 1:
		_fail("FAIL %d goals failed, expected exactly the roof" % queue.failed())
		return
	if queue.last_failure() != NavLadder.State.GOAL_UNREACHABLE:
		_fail(
			"FAIL the roof goal failed as %s"
			% NavLadder.state_name(queue.last_failure())
		)
		return
	if not _states.has(int(NavLadder.State.PATH_PARTIAL)):
		_fail("FAIL the unreachable roof never produced PATH_PARTIAL: %s" % str(_states))
		return
	if NavAgent.trapped_events() != 0:
		_fail("FAIL an unreachable goal was reported as entombment")
		return
	if queue.reached() != 1:
		_fail(
			"FAIL the replacement goal was not reached in %d ticks (state %s)"
			% [frames, agent.state_name()]
		)
		return
	print(
		"GOAL_UNREACHABLE: roof abandoned after %d ladder states %s, replacement reached in %d ticks"
		% [_states.size(), str(_states), frames]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# A failure a consumer can poll for
# ---------------------------------------------------------------------------

## A wander anchor with no span under it fails at adoption, before the ladder has climbed
## anywhere — and the replacement goal puts the rung back to PATH_OK on the next tick. So a
## HUD that samples `state()` sees a healthy agent either way, and the failure record is the
## only thing that can tell it otherwise.
func _test_failure_is_observable() -> void:
	var start := _w(Vector3i(30, 1, 6))
	var second := _w(Vector3i(46, 1, 6))
	## Off the field entirely, so no probe in the wander ring lands on a span.
	var nowhere := _w(Vector3i(SX + 200, 1, 6))
	var body := _make_body("Failing", start)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.wander(nowhere, 4.0))
	queue.add(NavGoal.go_to_point(second, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue)
	_states.clear()
	agent.ladder_changed.connect(_on_ladder)
	NavAgent.reset_events()

	if agent.has_failed():
		_fail("FAIL a fresh agent already reports a failure")
		return
	if agent.last_failure() != NavLadder.State.PATH_OK or agent.failure_count() != 0:
		_fail(
			"FAIL a fresh agent reports %s after %d failures"
			% [agent.last_failure_name(), agent.failure_count()]
		)
		return
	if not is_inf(agent.failure_age_sec()):
		_fail("FAIL a never-failed agent is %.2f s past its failure" % agent.failure_age_sec())
		return

	print("--- one 'no pedestrian span within' warning below is the assertion ---")
	var frames := await _run(agent, body, func() -> bool: return queue.failed() > 0, 40.0)
	if queue.failed() != 1:
		_fail("FAIL %d goals failed in %d ticks, expected the wander anchor" % [
			queue.failed(), frames
		])
		return
	if not agent.has_failed():
		_fail("FAIL the agent does not admit to the failure the provider was just told about")
		return
	if agent.last_failure() != NavLadder.State.GOAL_UNREACHABLE:
		_fail("FAIL the failure reads %s" % agent.last_failure_name())
		return
	if agent.failure_count() != 1 or NavAgent.goal_failure_events() != 1:
		_fail(
			"FAIL counted %d failures on the agent and %d world-wide"
			% [agent.failure_count(), NavAgent.goal_failure_events()]
		)
		return
	## The signal fired too, because the existing consumers listen rather than poll.
	if not _states.has(int(NavLadder.State.GOAL_UNREACHABLE)):
		_fail("FAIL ladder_changed never carried GOAL_UNREACHABLE: %s" % str(_states))
		return
	var age := agent.failure_age_sec()
	if age < 0.0 or age > float(frames) * SIM_DT:
		_fail("FAIL the failure is %.2f s old after %.2f s of ticks" % [age, float(frames) * SIM_DT])
		return
	print(
		"goal failure: state=%s last_failure=%s age=%.2f s after %d ticks"
		% [agent.state_name(), agent.last_failure_name(), age, frames]
	)

	## And the part that used to be unobservable: the record survives the recovery.
	frames += await _run(agent, body, func() -> bool: return queue.reached() > 0, 40.0)
	if queue.reached() != 1:
		_fail("FAIL the replacement goal was not reached in %d ticks" % frames)
		return
	if agent.state() != NavLadder.State.PATH_OK:
		_fail("FAIL the recovered agent sits at %s" % agent.state_name())
		return
	if agent.last_failure() != NavLadder.State.GOAL_UNREACHABLE or agent.failure_count() != 1:
		_fail(
			"FAIL the recovery erased the failure record: %s x%d"
			% [agent.last_failure_name(), agent.failure_count()]
		)
		return
	if agent.failure_age_sec() <= age:
		_fail("FAIL the failure age went backwards, %.2f s after %.2f s" % [
			agent.failure_age_sec(), age
		])
		return
	print(
		"after recovery: state=%s but last_failure=%s %.2f s ago, count %d"
		% [
			agent.state_name(),
			agent.last_failure_name(),
			agent.failure_age_sec(),
			agent.failure_count(),
		]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Rungs 3 and 4: no progress, then a blamed column
# ---------------------------------------------------------------------------

## A motor that swallows its own motion is what a body wedged against fresh rubble looks like:
## the corridor is fine, the displacement is not.
class PinnedMotor:
	extends NavMotor
	## Set once the agent is walking, so the corridor is adopted normally first.
	var pinned: bool = false

	func advance(delta: float) -> NavMotor.Step:
		if not pinned:
			return super.advance(delta)
		var held := body().global_position
		var step := super.advance(delta)
		body().global_position = held
		step.moved = Vector3.ZERO
		step.advanced_m = 0.0
		return step


func _test_no_progress_and_blocked() -> void:
	var start := _w(Vector3i(20, 1, 70))
	var goal_at := _w(Vector3i(100, 1, 70))
	var body := _make_body("Pinned", start)
	var motor := PinnedMotor.new()
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, motor, queue)
	_states.clear()
	_blocked_at.clear()
	_trapped_at.clear()
	_escapes.clear()
	_paths_seen = 0
	var goals: Array[Vector3] = []
	agent.ladder_changed.connect(_on_ladder)
	agent.column_blocked.connect(_on_blocked)
	agent.trapped.connect(_on_trapped)
	agent.path_assigned.connect(func(result: NavPathResult) -> void:
		_paths_seen += 1
		goals.append(result.to_world)
	)
	NavAgent.reset_events()

	var blocks_before := NavAgent.blocked_columns()
	var frames := await _run(
		agent, body, func() -> bool: return _blocked_at.size() > 0, 40.0, true
	)
	if _blocked_at.is_empty():
		_fail(
			"FAIL a pinned body never reached BLOCKED in %d ticks (state %s, states %s)"
			% [frames, agent.state_name(), str(_states)]
		)
		return
	if not _states.has(int(NavLadder.State.NO_PROGRESS)):
		_fail("FAIL BLOCKED was reached without NO_PROGRESS first: %s" % str(_states))
		return
	if _states.find(int(NavLadder.State.NO_PROGRESS)) > _states.find(int(NavLadder.State.BLOCKED)):
		_fail("FAIL the ladder reached BLOCKED before NO_PROGRESS: %s" % str(_states))
		return
	if NavAgent.blocked_columns() <= blocks_before:
		_fail("FAIL the blocked-column counter did not move")
		return

	## The local repaths aimed one sector ahead on the corridor, not at the goal.
	var local := 0
	for target: Vector3 in goals:
		if target.distance_to(goal_at) > 2.0:
			local += 1
			var ahead := start.distance_to(target)
			if ahead > 20.0:
				_fail("FAIL a local repath aimed %.1f m ahead, a sector is 14 m" % ahead)
				return
	if local < 1:
		_fail("FAIL every repath aimed at the goal; none stayed inside the sector")
		return

	## The block is real: a path that used to end on that column no longer does.
	var offender: Vector3 = _blocked_at[0]
	var probe := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, start, offender)
	if probe.status != NavPathResult.Status.PARTIAL:
		_fail(
			"FAIL a path to the blocked column %.1f,%.1f is %s, so the overlay did nothing"
			% [offender.x, offender.z, probe.status_name()]
		)
		return
	print(
		"NO_PROGRESS -> BLOCKED: %d local repaths, column %.1f,%.1f blocked (%s), states %s"
		% [local, offender.x, offender.z, probe.status_name(), str(_states)]
	)

	## Blocking its way out twice without moving an inch is entombment, and it is reported.
	frames += await _run(agent, body, func() -> bool: return _trapped_at.size() > 0, 40.0, true)
	if _trapped_at.is_empty():
		_fail(
			"FAIL a body that blocked its own corridor twice was never reported: %s"
			% str(_states)
		)
		return
	if NavAgent.trapped_events() != 1:
		_fail("FAIL %d trapped events counted, expected 1" % NavAgent.trapped_events())
		return
	print(
		"pinned body escalated to TRAPPED after %d ticks, escape %s"
		% [frames, NavLadder.escape_name(_escapes[0] as NavLadder.Escape)]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Rung 6: entombed
# ---------------------------------------------------------------------------

## Inside the sealed block there is no span the body can stand on, and the corridor the search
## snaps together is PARTIAL. That combination is entombment, and the escape is a move to the
## nearest span — counted, warned about and emitted, never quiet.
func _test_trapped_teleport() -> void:
	var buried := _w(Vector3i(70, 3, 42))
	var goal_at := _w(Vector3i(20, 1, 20))
	var body := _make_body("Entombed", buried)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	queue.looping = true
	var agent := _make_agent(body, NavProfile.Id.UNDEAD, NavMotor.new(), queue)
	_trapped_at.clear()
	_escapes.clear()
	NavAgent.reset_events()
	agent.trapped.connect(_on_trapped)

	var frames := await _run(agent, body, func() -> bool: return _trapped_at.size() > 0, 40.0)
	if _trapped_at.is_empty():
		_fail(
			"FAIL a body inside solid brick was never reported trapped in %d ticks (state %s)"
			% [frames, agent.state_name()]
		)
		return
	if _escapes[0] != int(NavLadder.Escape.TELEPORTED):
		_fail(
			"FAIL an undead escaped by %s, expected TELEPORTED"
			% NavLadder.escape_name(_escapes[0] as NavLadder.Escape)
		)
		return
	if NavAgent.trapped_events() != 1 or NavAgent.teleport_events() != 1:
		_fail(
			"FAIL counted %d trapped and %d teleports"
			% [NavAgent.trapped_events(), NavAgent.teleport_events()]
		)
		return
	if agent.trapped_count() != 1:
		_fail("FAIL the agent counted %d entombments" % agent.trapped_count())
		return
	var moved := buried.distance_to(body.global_position)
	if moved < 1.0:
		_fail("FAIL the trapped body moved %.2f m, so it is still entombed" % moved)
		return
	var footing := _nav.nearest_surface(NavProfile.Id.UNDEAD, body.global_position, 2.0)
	if not footing.found or body.global_position.distance_to(footing.position) > 1.0:
		_fail("FAIL the escape did not land on a span")
		return
	print(
		"TRAPPED: entombed body moved %.2f m to a span in %d ticks (%d counted)"
		% [moved, frames, NavAgent.trapped_events()]
	)
	agent.dispose()
	body.queue_free()


## A can_break profile is not moved: it is told to dig, and the voxels are the consumer's
## business. Off the field there is no span at all, so nothing could move it anyway.
func _test_trapped_dig_out() -> void:
	var nowhere := _w(Vector3i(SX + 80, 1, 42))
	var goal_at := _w(Vector3i(20, 1, 20))
	var body := _make_body("Digger", nowhere)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	queue.looping = true
	var agent := _make_agent(body, PROFILE_DIGGER, NavMotor.new(), queue)
	_trapped_at.clear()
	_escapes.clear()
	_dug_at.clear()
	NavAgent.reset_events()
	agent.trapped.connect(_on_trapped)
	agent.dig_out_requested.connect(_on_dig_out)

	var frames := await _run(agent, body, func() -> bool: return _trapped_at.size() > 0, 40.0)
	if _trapped_at.is_empty():
		_fail("FAIL a body with nowhere to stand was never reported trapped in %d ticks" % frames)
		return
	if _escapes[0] != int(NavLadder.Escape.DUG_OUT):
		_fail(
			"FAIL a can_break profile escaped by %s"
			% NavLadder.escape_name(_escapes[0] as NavLadder.Escape)
		)
		return
	if _dug_at.size() != 1:
		_fail("FAIL %d dig-out requests, expected 1" % _dug_at.size())
		return
	if NavAgent.dig_out_events() != 1 or NavAgent.teleport_events() != 0:
		_fail(
			"FAIL counted %d dig-outs and %d teleports"
			% [NavAgent.dig_out_events(), NavAgent.teleport_events()]
		)
		return
	if body.global_position.distance_to(nowhere) > 0.01:
		_fail("FAIL a digger was moved instead of digging")
		return
	print("TRAPPED: can_break profile asked to dig at %.0f,%.0f" % [_dug_at[0].x, _dug_at[0].z])
	agent.dispose()
	body.queue_free()


## The loudest rung: nowhere to stand and no way to dig. One error per event, and the body
## stays where it is rather than being teleported somewhere invented.
func _test_trapped_lost() -> void:
	var nowhere := _w(Vector3i(SX + 120, 1, 42))
	var body := _make_body("Lost", nowhere)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(_w(Vector3i(20, 1, 20)), 1.5))
	queue.looping = true
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue)
	_trapped_at.clear()
	_escapes.clear()
	NavAgent.reset_events()
	agent.trapped.connect(_on_trapped)

	print("--- one 'entombed ... with no pedestrian span' error below is the assertion ---")
	var frames := await _run(agent, body, func() -> bool: return _trapped_at.size() > 0, 40.0)
	if _trapped_at.is_empty():
		_fail("FAIL a body with no span anywhere was never reported in %d ticks" % frames)
		return
	if _escapes[0] != int(NavLadder.Escape.LOST):
		_fail(
			"FAIL escape was %s, expected LOST"
			% NavLadder.escape_name(_escapes[0] as NavLadder.Escape)
		)
		return
	if NavAgent.lost_events() != 1:
		_fail("FAIL %d lost events counted" % NavAgent.lost_events())
		return
	if body.global_position.distance_to(nowhere) > 0.01:
		_fail("FAIL a body with no valid span was moved anyway")
		return
	print("TRAPPED: no span within reach reported as LOST and left in place")
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Lazy invalidation
# ---------------------------------------------------------------------------

## A nav_version bump does not repath the world in one frame: the corridor goes stale and the
## agent rebuilds it after its tier's grace period. With a dirty-sector probe that says the
## change is somewhere else, it never rebuilds at all.
func _test_lazy_repath() -> void:
	var start := _w(Vector3i(8, 1, 30))
	var goal_at := _w(Vector3i(104, 1, 30))
	var body := _make_body("Lazy", start)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, NavMotor.new(), queue)
	_paths_seen = 0
	agent.path_assigned.connect(_on_path)

	await _run(agent, body, func() -> bool: return agent.has_corridor(), 40.0)
	if not agent.has_corridor():
		_fail("FAIL the agent never got a corridor to invalidate")
		return
	var grace := NavLod.new().stale_grace_sec(NavLod.Tier.MID)
	var before := _paths_seen
	if not _nav.register_district(DIRTY_TILE, _bake_dirty()):
		_fail("FAIL could not register the tile that bumps nav_version")
		return
	var early := int(grace / SIM_DT) - 4
	await _tick(agent, body, early, 40.0)
	if _paths_seen != before:
		_fail(
			"FAIL the agent repathed %.2f s into a %.2f s grace period"
			% [float(early) * SIM_DT, grace]
		)
		return
	await _tick(agent, body, 10, 40.0)
	if _paths_seen <= before:
		_fail("FAIL a stale corridor was never rebuilt after %.2f s" % grace)
		return
	print("lazy repath: rebuilt after the %.2f s grace period, not on the version bump" % grace)

	## With a probe that says the dirty sectors are elsewhere, the bump is ignored.
	agent.dirty_probe = func(_points: PackedVector3Array, _since: int) -> bool: return false
	before = _paths_seen
	if not _nav.unregister_district(DIRTY_TILE):
		_fail("FAIL could not unregister the version-bumping tile")
		return
	await _tick(agent, body, int(grace / SIM_DT) + 20, 40.0)
	if _paths_seen != before:
		_fail("FAIL the agent repathed for a change its own corridor never crosses")
		return
	print("lazy repath: a dirty-sector probe that says 'not my corridor' suppresses it")
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Tier switching
# ---------------------------------------------------------------------------

## Walking out of the near band and back must not teleport the body: the far tier tracks arc
## length and the others track a point index, so the two have to be re-synced on the switch.
func _test_tier_switch_continuity() -> void:
	var start := _w(Vector3i(8, 1, 50))
	var goal_at := _w(Vector3i(104, 1, 50))
	var body := _make_character("Tiers", start)
	var queue := NavGoalQueue.new()
	queue.add(NavGoal.go_to_point(goal_at, 1.5))
	var agent := _make_agent(body, NavProfile.Id.PEDESTRIAN, _collider_motor(body), queue)

	var offsets: Array[float] = [5.0, 40.0, 200.0, 40.0, 5.0]
	var seen: Array[int] = []
	var worst_jump := 0.0
	for offset: float in offsets:
		for _frame in range(40):
			var was := body.global_position
			await get_tree().process_frame
			agent.tick(SIM_DT, body.global_position + Vector3(0.0, 0.0, offset))
			if not seen.has(int(agent.tier())):
				seen.append(int(agent.tier()))
			worst_jump = maxf(worst_jump, was.distance_to(body.global_position))
	if seen.size() != 3:
		_fail("FAIL only tiers %s were used across 5 m to 200 m" % str(seen))
		return
	## A stride is speed * SIM_DT; anything much larger is a re-sync bug, not motion.
	if worst_jump > 0.5:
		_fail("FAIL a tier switch moved the body %.2f m in one tick" % worst_jump)
		return
	var walked := start.distance_to(body.global_position)
	if walked < 5.0:
		_fail("FAIL the body only covered %.1f m across 200 ticks of tier churn" % walked)
		return
	print(
		"tier switching: %.1f m walked across %d tiers, worst single tick %.3f m"
		% [walked, seen.size(), worst_jump]
	)
	agent.dispose()
	body.queue_free()


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

func _on_ladder(state: NavLadder.State) -> void:
	_states.append(int(state))


func _on_path(_result: NavPathResult) -> void:
	_paths_seen += 1


func _on_blocked(world_pos: Vector3) -> void:
	_blocked_at.append(world_pos)


func _on_trapped(world_pos: Vector3, escape: NavLadder.Escape) -> void:
	_trapped_at.append(world_pos)
	_escapes.append(int(escape))


func _on_dig_out(world_pos: Vector3) -> void:
	_dug_at.append(world_pos)


func _make_body(name: String, at: Vector3) -> Node3D:
	var body := Node3D.new()
	body.name = name
	add_child(body)
	body.global_position = at
	return body


## A body the near tier can actually use: VoxelBoxMover needs a capsule to sweep.
func _make_character(name: String, at: Vector3) -> CharacterBody3D:
	var character := CharacterBody3D.new()
	character.name = name
	add_child(character)
	character.global_position = at
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	capsule.shape = shape
	capsule.position = Vector3(0.0, 0.9, 0.0)
	character.add_child(capsule)
	return character


## Gravity is off because a headless test has no VoxelTerrain, so there is no floor to land on
## and VoxelBodyMotion integrates the velocity as given.
func _collider_motor(character: CharacterBody3D) -> NavMotor:
	var motion := VoxelBodyMotion.new()
	motion.setup(null, 0.55)
	var motor := NavMotor.new()
	motor.gravity = 0.0
	motor.attach_collider(character, character.get_child(0) as CollisionShape3D, motion)
	return motor


func _make_agent(
	body: Node3D,
	profile_id: int,
	motor: NavMotor,
	provider: NavGoalProvider,
	lod: NavLod = null
) -> NavAgent:
	var agent := NavAgent.new()
	agent.setup(body, profile_id, motor, provider, lod)
	return agent


## Tick until `done` or the time limit. The observer is held `offset` metres from the body, so
## a case picks its tier by how close it says the camera is.
func _run(
	agent: NavAgent,
	body: Node3D,
	done: Callable,
	offset: float,
	pin_after_start: bool = false
) -> int:
	var frames := 0
	while frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
		agent.tick(SIM_DT, body.global_position + Vector3(0.0, 0.0, offset))
		if pin_after_start and agent.has_corridor():
			var pinned := agent.motor() as PinnedMotor
			if pinned != null:
				pinned.pinned = true
		if bool(done.call()):
			break
	return frames


func _tick(agent: NavAgent, body: Node3D, frames: int, offset: float) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
		agent.tick(SIM_DT, body.global_position + Vector3(0.0, 0.0, offset))


## A corridor NavService did not produce, so a traversal routine can be tested without hunting
## for a facade that happens to bake the link.
func _corridor(points: Array[Vector3], links: Array[int]) -> NavPathResult:
	var result := NavPathResult.new()
	result.status = NavPathResult.Status.OK
	result.profile_id = NavProfile.Id.UNDEAD
	var pts := PackedVector3Array()
	for p: Vector3 in points:
		pts.append(p)
	var kinds := PackedByteArray()
	for kind: int in links:
		kinds.append(kind)
	result.points = pts
	result.link_kinds = kinds
	result.from_world = points[0]
	result.to_world = points[points.size() - 1]
	return result


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Flat concrete deck with one sealed brick block on it.
func _bake_tile() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	volume.fill_box(BLOCK_MIN, BLOCK_MAX, VoxelMaterial.BRICK)
	return _bake_volume(volume, ORIGIN, SX, SZ)


func _bake_dirty() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(DIRTY_SIZE, 1, DIRTY_SIZE), VoxelMaterial.CONCRETE)
	return _bake_volume(volume, DIRTY_ORIGIN, DIRTY_SIZE, DIRTY_SIZE)


func _bake_volume(
	volume: NativeOfflineVoxelVolume, origin: Vector3i, size_x: int, size_z: int
) -> NativeNavBake:
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		origin,
		size_x,
		size_z,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected %dx%d at %s" % [size_x, size_z, str(origin)])
		return null
	return bake


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
