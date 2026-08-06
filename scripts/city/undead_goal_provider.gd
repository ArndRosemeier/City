## What one undead wants next: a living body of another faction, the place it was last seen,
## or a wander when the city offers neither.
##
## There is no prey table and there are no buildings to chew. Hostility is faction against
## faction — the player and every pedestrian are `human` — and among everyone hostile the
## closest one this body can actually see wins. Once picked, that target is *kept*: a hunter
## commits until its quarry dies or leaves the leash, so a chase cannot be stolen by whoever
## happens to wander closer mid-pursuit.
##
## One provider per body, because the answer comes out of that body's role, its state and
## what the city can see around it. NavAgent asks whenever a goal ends; `retarget` exists
## because prey walks away, and a corridor built for where a pedestrian used to be is stale
## long before it has been walked.
class_name UndeadGoalProvider
extends NavGoalProvider

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")

## Goal tags, so `goal_reached` knows which behaviour just finished.
const TAG_HUNT := &"hunt"
const TAG_WANDER := &"wander"
## Walk a standing objective (Siege Lodestone) when nothing living is acquirable.
const TAG_PUSH := &"push"

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
## Hunt corridors are short on purpose (melee stand-off is ~1 m). The wander/investigate
## tolerance above is wider than a melee swing, so using it here made bodies "arrive" outside
## strike range, drop the corridor, re-path, and jiggle in the prey's face forever.
const HUNT_ARRIVE_TOLERANCE_M := 0.35
## How far inside a push objective's vulnerability radius its stand ring sits. Aiming *at* the
## radius would let arrive slop park bodies a hair outside it, where they neither hold nor hurt.
const PUSH_RING_INSET_M := 0.75
## How far a committed pedestrian may be from where it was last seen and still be recognised
## as the same one. Peds walk under 2 m/s and the query runs every PREY_CACHE_SEC, so half a
## metre is the honest drift — the rest is slack for a crowd that respawned around it.
const STICKY_PED_MATCH_M := 3.0
## After LOS breaks, keep walking to the last seen point this long before giving up.
const INVESTIGATE_TIMEOUT_SEC := 5.0
## Do not treat "already standing on LKP" as give-up until this elapses — otherwise a
## stand-off fight drops aggro the frame the prey steps behind a corner.
const INVESTIGATE_MIN_SEC := 0.85

## Hot = visible prey. Investigate = walking to last known position after LOS/range loss.
enum Pursuit { NONE = 0, HOT = 1, INVESTIGATE = 2 }

var _unit: UndeadUnit = null
var _city: CityRoot = null
var _prey: Vector3 = Vector3.INF
var _prey_at_msec: int = -1000000
## Last aim-point where living prey was seen with LOS (Hot / Investigate memory).
var _lkp: Vector3 = Vector3.INF
var _pursuit: Pursuit = Pursuit.NONE
## Simulated seconds in Investigate (advanced from UndeadUnit.tick — not wall clock).
var _investigate_age_sec: float = 0.0
## Aggro queue of actors that hurt this body. Index 0 is the current target: later hitters enqueue
## behind it and do not steal the chase. The head drops only when it becomes unreachable (dead,
## freed, outside the leash, or the navigator gives up on the corridor to it).
var _aggro_queue: Array[Node] = []
## The body this hunter committed to. The player and other monsters are nodes; pedestrians
## are crowd positions with no node to hold, so their commitment is the last aim point and
## is re-matched against the fresh crowd every query. Exactly one of the two is ever set.
var _target_node: Node = null
var _target_ped: Vector3 = Vector3.INF
## Set when the ladder gave up on a goal: look somewhere else before looking there again.
var _wander_next: bool = false
## Objective this body walks when nothing living is acquirable, resolved by `_refresh_objective`.
## A registered beacon wins over the unit's own push aim.
var _objective_aim: Vector3 = Vector3.INF
var _objective_hold_m: float = 1.5
## Beacon this body walked to last, for `BeaconRegistry.nearest_for` hysteresis. 0 means none.
var _beacon_id: int = 0


func setup(unit: UndeadUnit, city: CityRoot) -> void:
	if unit == null:
		push_error("UndeadGoalProvider.setup: no unit")
		return
	if city == null:
		push_error("UndeadGoalProvider.setup: no city for %s" % unit.name)
		return
	_unit = unit
	_city = city
	_clear_pursuit()


## Test / debug: NONE / HOT / INVESTIGATE.
func pursuit() -> Pursuit:
	return _pursuit


func last_known_prey() -> Vector3:
	return _lkp


## True while a damage-driven attacker is still on the aggro queue.
func has_forced_attacker() -> bool:
	_prune_aggro_heads()
	return not _aggro_queue.is_empty()


## True while this body is holding one chosen target rather than re-picking every query.
func has_committed_target() -> bool:
	return _target_node != null or _target_ped != Vector3.INF


## Enqueue `attacker` (player body or UndeadUnit) for retaliation.
##
## The first hitter becomes the chase; anyone who lands a blow while that chase is live joins the
## queue behind them. Swapping to every new hitter made melee bodies ping-pong between attackers and
## never close the gap — so the top of the queue only changes when that target becomes unreachable.
func promote_attacker(attacker: Node) -> void:
	if not _has_unit() or attacker == null or not is_instance_valid(attacker):
		return
	if attacker == _unit:
		return
	if not _aggro_queue.has(attacker):
		_aggro_queue.append(attacker)
	_prey_at_msec = -1000000
	## Always aim at the *head*, even when this call only appended a second hitter. Setting prey to
	## the newcomer here was half of the ping-pong: combat swung at B while the feet still walked to A.
	var aim := _forced_prey_aim()
	if aim != Vector3.INF:
		_mark_hot_pursuit(aim)
		_prey = aim
		_unit.set_combat_prey(aim)


## Advance investigate age with the unit's simulation delta (headless tests use fixed dt).
func tick_pursuit(delta: float) -> void:
	if _pursuit == Pursuit.INVESTIGATE and delta > 0.0:
		_investigate_age_sec += delta


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
		UndeadUnit.State.SEEK_PED, UndeadUnit.State.STOMP:
			## Giants hunt the same way everything else does — there is no facade path left.
			return _hunt_goal()
		UndeadUnit.State.IDLE, UndeadUnit.State.CAST, UndeadUnit.State.GROWING:
			return null
		UndeadUnit.State.DEAD:
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
			if _pursuit == Pursuit.INVESTIGATE:
				## Arrived at last-known point: reacquire or give up (no blind fire).
				var found := _nearest_living_prey()
				if found != Vector3.INF:
					_unit.set_combat_prey(found)
					_unit.on_prey_in_range()
				elif _investigate_age_sec >= INVESTIGATE_MIN_SEC:
					_clear_pursuit()
					_unit.set_combat_prey(Vector3.INF)
				## Else still investigating — next_goal re-issues the LKP walk.
			else:
				_unit.on_prey_in_range()
		TAG_WANDER, TAG_PUSH:
			## Arrival just frees the agent to ask again — push re-issues if still short,
			## or holds so the Siege controller can apply Lodestone contact damage.
			pass
		_:
			push_error(
				"UndeadGoalProvider: %s reached an untagged goal %s"
				% [_unit.name, goal.describe()]
			)


## The ladder gave up. NavAgent has already counted and warned, so nothing is smoothed over
## here — but sending the body straight back at the same unreachable thing would only repeat
## it. If that thing was the aggro head *and* this body cannot fight it without a corridor,
## drop it and serve the next hitter; otherwise look somewhere else first.
##
## A failed hunt is not automatically an unreachable head. Stand-off points next to a siege tower
## often sit inside its stamp, so the navigator reports GOAL_UNREACHABLE the moment a melee body
## is close enough to swing — and treating that as "drop the tower" is exactly the walk-away-
## after-one-hit bug. In strike reach the fight continues without a path; only a head that is
## dead, unleashed, or still too far to engage is actually unreachable.
func goal_failed(_request: NavGoalRequest, goal: NavGoal, state: NavLadder.State) -> void:
	if not _has_unit():
		return
	_prey = Vector3.INF
	_prey_at_msec = -1000000
	if goal.tag == TAG_HUNT and not _aggro_queue.is_empty():
		_drop_aggro_head_if_unreachable()
	var next_forced := _forced_prey_aim()
	if next_forced != Vector3.INF:
		_mark_hot_pursuit(next_forced)
		_prey = next_forced
		_unit.set_combat_prey(next_forced)
		_unit.on_goal_failed(goal, state)
		## Stay in retaliation — do not wander off a live queue because one corridor failed.
		_wander_next = false
		return
	_clear_pursuit()
	_unit.set_combat_prey(Vector3.INF)
	_unit.on_goal_failed(goal, state)
	## "Look somewhere else first" is advice for something that can walk. An immobile body has
	## nowhere else to look, and a wander it cannot serve would fail again next frame.
	_wander_next = goal.tag != TAG_WANDER and not _is_immobile()


# ---------------------------------------------------------------------------
# Retargeting
# ---------------------------------------------------------------------------

## Prey moves while the hunter walks. Called by the unit on the crowd-query cadence rather
## than every frame, since only the hunt goal has a subject that can run away.
func retarget(agent: NavAgent) -> void:
	if not _has_unit():
		return
	var goal := agent.goal()
	if goal == null:
		## Engage-in-place (null hunt): refresh living aim so strikes track the target
		## without adopting a trivial go_to(self) corridor every physics frame.
		if (
			_unit.state == UndeadUnit.State.SEEK_PED
			or _unit.state == UndeadUnit.State.STOMP
		):
			_retarget_engage_in_place(agent)
		return
	if goal.tag == TAG_PUSH:
		## Answering fire outranks the errand. A body on a corridor to a stone is not asked for a
		## new goal until it arrives, so without this a tower could shoot it the whole way in and
		## the promotion `promote_attacker` recorded would never become a goal — towers fired, the
		## horde walked past, and nothing fought back.
		if _turn_on_attacker(agent):
			return
		_retarget_objective(agent)
		return
	if goal.tag != TAG_HUNT:
		return
	var prey := _nearest_living_prey()
	if prey != Vector3.INF:
		_unit.set_combat_prey(prey)
		if prey.distance_to(goal.point) <= RETARGET_SLACK_M and _pursuit == Pursuit.HOT:
			return
		var next := _hunt(prey)
		if next == null:
			## Prey walked into stand-off — drop the corridor and hold.
			agent.abandon_goal()
			return
		agent.set_goal(next)
		return
	## No visible prey — pursue last known point before giving up.
	var memory := _handle_lost_prey()
	if memory == null:
		var idle := _idle_goal()
		if idle == null:
			agent.abandon_goal()
			return
		agent.set_goal(idle)
		return
	_unit.set_combat_prey(Vector3.INF)
	if memory.point.distance_to(goal.point) <= RETARGET_SLACK_M:
		return
	agent.set_goal(memory)


## A stone can fall while a body is still walking to it. The registry drops the entry, so the next
## pick is whatever is still standing — but without re-issuing here the body would first walk all the
## way to the crater it was already aimed at, which is up to half a minute of a wave doing nothing.
func _retarget_objective(agent: NavAgent) -> void:
	var was := _beacon_id
	_refresh_objective()
	if _objective_aim == Vector3.INF:
		## The run ended, or whatever it was walking to is no longer anybody's objective.
		agent.abandon_goal()
		return
	if _beacon_id == was:
		return
	var next := _push_goal()
	if next == null:
		## Already inside the new objective's radius: hold, and let the controller land contact.
		agent.abandon_goal()
		return
	agent.set_goal(next)


func _retarget_engage_in_place(agent: NavAgent) -> void:
	var hold_prey := _nearest_living_prey()
	if hold_prey != Vector3.INF:
		_unit.set_combat_prey(hold_prey)
		var resume := _hunt(hold_prey)
		if resume != null:
			## Prey left stand-off — resume the corridor immediately.
			agent.set_goal(resume)
		return
	var memory := _handle_lost_prey()
	if memory == null:
		_unit.set_combat_prey(Vector3.INF)
		return
	_unit.set_combat_prey(Vector3.INF)
	agent.set_goal(memory)


## Hot→Investigate on first loss; keep LKP goal while investigating; null when cleared.
## Immobile towers skip Investigate entirely — see `_committed_aim`.
func _handle_lost_prey() -> NavGoal:
	if _is_immobile():
		_clear_pursuit()
		_unit.set_combat_prey(Vector3.INF)
		return null
	if _pursuit == Pursuit.HOT and _lkp != Vector3.INF:
		_begin_investigate()
	if _pursuit != Pursuit.INVESTIGATE or _lkp == Vector3.INF:
		_clear_pursuit()
		_unit.set_combat_prey(Vector3.INF)
		return null
	if _should_give_up_investigate():
		_clear_pursuit()
		_unit.set_combat_prey(Vector3.INF)
		return null
	return _investigate_goal()


# ---------------------------------------------------------------------------
# The goals themselves
# ---------------------------------------------------------------------------

## Chase the committed target, walk to where it was last seen, or wander.
func _hunt_goal() -> NavGoal:
	CityProfiler.begin("undead_hunt_pick")
	var goal: NavGoal = null
	_refresh_objective()
	if _unit.nav_tier() == NavLod.Tier.FAR and not _is_immobile():
		## Nobody is close enough to see this body fight; the crowd query is not worth it.
		##
		## Towers are the exception. The saving this buys is a corridor an immobile body was
		## never going to walk, and a defence that stops shooting 80 m from the player is a
		## defence that does not work: the player holds one side of a quarter while the horde
		## eats the other. A tower's prey query is its whole cost, and it is the cheap half of
		## a walker — no path, no motion, no separation.
		##
		## A beacon-bound body is the other exception, and it is cheaper still: it already knows
		## where it is going, so it skips the crowd query outright. Wandering here is what would
		## leave three siege flanks untouched all run — the horde grinding stones the player is
		## nowhere near *is* the mode, and far bodies still walk their corridor (as a lerp).
		##
		## Being shot is not handled here. It does not need to be: whatever this picks is retargeted
		## on the crowd cadence, and `retarget` answers fire from any tier.
		goal = _push_goal() if _beacon_id != 0 else _wander()
	else:
		var prey := _nearest_living_prey()
		if prey != Vector3.INF:
			_unit.set_combat_prey(prey)
			goal = _hunt(prey)
		else:
			_unit.set_combat_prey(Vector3.INF)
			var memory := _handle_lost_prey()
			if memory != null:
				goal = memory
			else:
				## Siege attackers (and anything else with a standing objective) walk it before
				## they shuffle. Without this the horde would never reach a stone — defenders are
				## unacquirable, so there is never a hunt target on the way in.
				if _objective_aim != Vector3.INF:
					## Null from `_push_goal` here means "inside the vulnerability radius, hold".
					## Wandering on that null is what kept the horde circling the Lodestone.
					goal = _push_goal()
				else:
					goal = _idle_goal()
	CityProfiler.end("undead_hunt_pick")
	return goal


## Aimed at the spot the body wants to fight from, not at the prey: a corridor ends where it
## is aimed, and a goal's radius only decides whether arriving counted.
func _hunt(prey: Vector3) -> NavGoal:
	var from := _unit.global_position
	var away := from - prey
	away.y = 0.0
	var distance := away.length()
	var engage := _hunt_engage_m()
	## Prey volume (creature capsule or tower stamp). Distance is centre-to-centre; engage is the
	## swing length past the surface, or stand-off aims land inside solid stamps and fail forever.
	var prey_r := _prey_hit_radius_m(prey)
	if distance <= engage + prey_r or _is_immobile():
		## Close enough to swing: hold and let MonsterCombat strike. A trivial go_to(self)
		## goal completes every physics frame, re-acquires, and re-paths — that alone tanks FPS.
		## Engage is the *strike* reach, not the stand-off the corridor aims at: a body that
		## lands a touch short of stand-off must still fight, not open another approach.
		##
		## Immobile bodies hold at any distance. A tower handed a corridor it cannot walk ends in
		## `goal_failed`, which drops the target it had just acquired — so prey between the
		## stand-off and the aggro range would have it re-acquiring instead of shooting.
		_unit.set_combat_prey(prey)
		return null
	var stand_off := minf(_hunt_stand_off_m(), engage) + prey_r
	return _tagged(
		NavGoal.go_to_point(
			prey + away / distance * stand_off, HUNT_ARRIVE_TOLERANCE_M
		),
		TAG_HUNT
	)


func _hunt_stand_off_m() -> float:
	var combat: RefCounted = _unit.combat()
	if combat != null:
		return float(combat.call("hunt_standoff_m"))
	## Legacy mage orb standoff.
	if _unit.can_cast():
		return UndeadUnit.ORB_RANGE_M * UndeadUnit.ORB_STANDOFF_FRACTION
	return UndeadUnit.MAGE_CLOSE_IN_M


## Distance at which a hunt holds and tries to strike. Matches MonsterCombat's melee reach
## when the kit has one; otherwise the stand-off (ranged kits hold where they shoot from).
func _hunt_engage_m() -> float:
	var combat: RefCounted = _unit.combat()
	if combat != null and combat.has_method("hunt_engage_m"):
		return float(combat.call("hunt_engage_m"))
	return _hunt_stand_off_m()


## Flat body / structure radius of whatever `prey` is aiming at. Zero when the aim is a ped
## point or the player (their capsule is already baked into table reach / player checks).
func _prey_hit_radius_m(prey: Vector3) -> float:
	if prey == Vector3.INF:
		return 0.0
	## Hunt retarget can run after a tower died this frame; `as UndeadUnit` on a freed RefCounted
	## errors before any null check. Prune first, then cast only a still-live node.
	_prune_aggro_heads()
	if not _aggro_queue.is_empty():
		var head_node: Node = _aggro_queue[0]
		if head_node != null and is_instance_valid(head_node):
			var head := head_node as UndeadUnit
			if head != null and head.is_alive():
				var aim := _aim_of_attacker(head)
				if aim != Vector3.INF and _flat(aim, prey) <= 0.75:
					return float(head.hit_radius())
	if _target_node != null and is_instance_valid(_target_node):
		var sticky := _target_node as UndeadUnit
		if sticky != null and sticky.is_alive():
			var sticky_aim := _aim_of_attacker(sticky)
			if sticky_aim != Vector3.INF and _flat(sticky_aim, prey) <= 0.75:
				return float(sticky.hit_radius())
	if _city != null and _city.has_method("find_nearest_hostile_monster"):
		var near: UndeadUnit = _city.call(
			"find_nearest_hostile_monster", prey, 0.75, _unit
		) as UndeadUnit
		if near != null and is_instance_valid(near):
			return float(near.hit_radius())
	return 0.0


func _wander() -> NavGoal:
	return _tagged(NavGoal.wander(_unit.global_position, WANDER_RADIUS_M), TAG_WANDER)


## What a body does with nobody to fight. Immobile bodies get null, which NavAgent reads as
## engage-in-place — the state whose `retarget` keeps re-asking who is in range. A wander goal
## instead would fail (nothing can walk it), and a failed goal drops the target this body holds,
## so a tower would spend a fight losing prey it had already found.
func _idle_goal() -> NavGoal:
	if _is_immobile():
		return null
	return _wander()


## Pick the objective this body walks when it has nothing to hunt: the nearest beacon it is allowed
## to perceive, or its own push aim when the registry has nothing for its faction.
##
## Beacons win because they are the live answer. A siege stone can die mid-approach, and a per-unit
## aim stamped at spawn would send bodies to keep chewing a crater; the registry drops the entry
## instead, and the next query hands them whatever is still standing.
func _refresh_objective() -> void:
	var beacon := _nearest_beacon()
	if beacon != null:
		_beacon_id = beacon.id
		_objective_aim = beacon.pos
		_objective_hold_m = beacon.hold_radius_m
		return
	_beacon_id = 0
	_objective_aim = _unit.push_aim()
	_objective_hold_m = _unit.push_hold_m()


func _nearest_beacon() -> BeaconRegistry.Entry:
	if _city == null or not is_instance_valid(_city):
		return null
	var registry := _city.beacon_registry()
	if registry == null or registry.is_empty():
		return null
	return registry.nearest_for(_unit.faction(), _unit.global_position, _beacon_id)


## Walk the standing objective (a siege stone). Null once the body is inside its vulnerability
## radius, meaning **hold here** — callers must not read that as "nothing to do" and wander
## off, because holding still is what lets the controller land contact damage.
##
## The aim is the *centre* of a solid objective. Pathing into that point forever PATH_PARTIALs
## around the shell (melee "dance"). Walk to a standable ring instead, set a little inside the
## vulnerability radius so any re-path only ever moves the body further in.
func _push_goal() -> NavGoal:
	var aim := _objective_aim
	if aim == Vector3.INF:
		return null
	var vuln_r := _objective_hold_m
	var from := _unit.global_position
	var away := Vector2(from.x - aim.x, from.z - aim.z)
	var dist := away.length()
	if dist <= vuln_r:
		return null
	var ring_r := maxf(vuln_r - PUSH_RING_INSET_M, 0.5)
	var ring := aim
	if dist > 0.01:
		var dir := away / dist
		ring = Vector3(aim.x + dir.x * ring_r, aim.y, aim.z + dir.y * ring_r)
	return _tagged(NavGoal.go_to_point(ring, ARRIVE_TOLERANCE_M), TAG_PUSH)


## The objective this body is close enough to be hurting, or INF when it is not on one.
##
## Being inside the radius is precisely the state `_push_goal` answers with "no goal": the body has
## arrived and the controller is draining the stone for as long as it stays. None of that reads on
## screen — a stone has no hitbox, so there is no target and no swing — and the body is asked for this
## so it can at least face what it is destroying and strike at it.
func objective_strike_aim() -> Vector3:
	var aim := _objective_aim
	if aim == Vector3.INF:
		return Vector3.INF
	var from := _unit.global_position
	if Vector2(from.x - aim.x, from.z - aim.z).length() > _objective_hold_m:
		return Vector3.INF
	return aim


func _tagged(goal: NavGoal, tag: StringName) -> NavGoal:
	goal.tag = tag
	return goal


# ---------------------------------------------------------------------------
# Who this body is fighting
# ---------------------------------------------------------------------------

## Aim point of whoever this body is fighting, or Vector3.INF for nobody visible.
##
## Order of authority: the head of the aggro queue, then the target it already committed to,
## then a fresh pick. A committed target that is in range but out of sight yields INF on
## purpose — the caller turns that into Investigate, which is how a hunter loses somebody,
## rather than into an excuse to swap onto a nearer body.
func _nearest_living_prey() -> Vector3:
	var now := Time.get_ticks_msec()
	if now - _prey_at_msec < int(PREY_CACHE_SEC * 1000.0):
		return _prey
	_prey_at_msec = now

	var forced := _forced_prey_aim()
	if forced != Vector3.INF:
		_mark_hot_pursuit(forced)
		_prey = forced
		return _prey

	var combat: RefCounted = _unit.combat()
	if combat == null or not bool(combat.call("hunts_living")):
		_prey = Vector3.INF
		return _prey

	var sticky := _committed_aim()
	if sticky != Vector3.INF:
		_mark_hot_pursuit(sticky)
		_prey = sticky
		return _prey
	if has_committed_target():
		## Still ours, just not in sight this instant.
		_prey = Vector3.INF
		return _prey

	_prey = _acquire_prey()
	if _prey != Vector3.INF:
		_mark_hot_pursuit(_prey)
	return _prey


## Aim at the committed target, Vector3.INF when it cannot be seen right now. Drops the
## commitment — freeing the caller to pick again — when the target is dead, gone, or has put
## the leash between itself and this body.
##
## Immobile bodies (siege towers, `speed_mult` 0): lost LOS means release, not Investigate.
## A tower cannot walk to a last-known point, so holding the commitment would trap the barrel
## on a target it can no longer hit.
func _committed_aim() -> Vector3:
	if not has_committed_target():
		return Vector3.INF
	var aim := _target_aim()
	if aim == Vector3.INF or not _inside_leash(aim):
		_clear_target()
		return Vector3.INF
	if not _city.has_voxel_line_of_sight(_eye(), aim):
		if _is_immobile():
			_clear_target()
		return Vector3.INF
	return aim


func _is_immobile() -> bool:
	if _unit != null and _unit.has_method("is_siege_tower") and bool(_unit.call("is_siege_tower")):
		return true
	var combat: RefCounted = _unit.combat() if _has_unit() else null
	if combat == null:
		return false
	return float(combat.call("speed_mult")) <= 0.0


func _target_aim() -> Vector3:
	if _target_node != null:
		if not is_instance_valid(_target_node):
			return Vector3.INF
		return _aim_of_attacker(_target_node)
	return _rematch_ped()


## Find the committed pedestrian again in the fresh crowd. There is no node to compare, so
## the nearest ped to where this one was last seen is taken to be it.
func _rematch_ped() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for aim: Vector3 in _ped_aims(_target_ped, STICKY_PED_MATCH_M):
		var d := _target_ped.distance_to(aim)
		if d < best_d:
			best_d = d
			best = aim
	if best == Vector3.INF:
		return Vector3.INF
	_target_ped = best
	return best


## Fresh pick: closest hostile body with a clear voxel corridor to it. No weights — the only
## questions are faction and distance.
func _acquire_prey() -> Vector3:
	var from := _unit.global_position
	var range_m := float(_unit.combat().call("aggro_range_m"))
	## { "aim": Vector3, "node": Node, "dist": float }
	var candidates: Array[Dictionary] = []

	if _city.is_player_alive() and _can_acquire(_city.player_faction()):
		var ppos := _city.get_player_target_position()
		var d_player := _flat(from, ppos)
		if d_player <= range_m:
			candidates.append(
				{"aim": ppos, "node": _city.get_player_node(), "dist": d_player}
			)

	if _can_acquire(_city.ped_faction()):
		for aim: Vector3 in _ped_aims(from, range_m):
			var d_ped := _flat(from, aim)
			if d_ped <= range_m:
				candidates.append({"aim": aim, "node": null, "dist": d_ped})

	for other: UndeadUnit in _city.collect_acquirable_monsters(from, range_m, _unit):
		var mob_aim := other.global_position + Vector3(0.0, 1.0, 0.0)
		candidates.append(
			{"aim": mob_aim, "node": other, "dist": _flat(from, mob_aim)}
		)

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["dist"]) < float(b["dist"])
	)
	var eye := _eye()
	for c: Dictionary in candidates:
		var aim: Vector3 = c["aim"] as Vector3
		if not _city.has_voxel_line_of_sight(eye, aim):
			continue
		_commit_to(c["node"] as Node, aim)
		return aim
	return Vector3.INF


func _commit_to(node: Node, aim: Vector3) -> void:
	_target_node = node
	_target_ped = Vector3.INF if node != null else aim


func _clear_target() -> void:
	_target_node = null
	_target_ped = Vector3.INF


func _hostile_to(other_faction: int) -> bool:
	return MonsterFactionScript.is_hostile(_unit.faction(), other_faction)


## Fresh prey only — forced retaliation bypasses this via `_forced_prey_aim`.
func _can_acquire(other_faction: int) -> bool:
	return MonsterFactionScript.can_acquire(_unit.faction(), other_faction)


## Pedestrian aim points (chest height) inside `radius_m` of `centre`.
func _ped_aims(centre: Vector3, radius_m: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if centre == Vector3.INF:
		return out
	var peds := _city.collect_ped_positions(centre, radius_m)
	for i in range(peds.size()):
		out.append(peds[i] + Vector3(0.0, 1.0, 0.0))
	return out


func _eye() -> Vector3:
	return _unit.muzzle_world()


func _inside_leash(aim: Vector3) -> bool:
	return _flat(_unit.global_position, aim) <= _investigate_leash_m()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Pursuit memory (last known position)
# ---------------------------------------------------------------------------

func _mark_hot_pursuit(aim: Vector3) -> void:
	_lkp = aim
	_pursuit = Pursuit.HOT
	_investigate_age_sec = 0.0


func _begin_investigate() -> void:
	if _lkp == Vector3.INF:
		_pursuit = Pursuit.NONE
		return
	_pursuit = Pursuit.INVESTIGATE
	_investigate_age_sec = 0.0
	## Force a fresh LOS scan on the next query — do not keep a stale Hot cache hit.
	_prey = Vector3.INF
	_prey_at_msec = -1000000


## Giving up on the search is giving up on the target: the next acquire starts from scratch.
func _clear_pursuit() -> void:
	_pursuit = Pursuit.NONE
	_lkp = Vector3.INF
	_investigate_age_sec = 0.0
	_aggro_queue.clear()
	_clear_target()


## Drop the current errand and go for whoever is shooting. True when it took over, so callers can
## skip their own goal choice.
##
## Deliberately free of any crowd query — one position read and a leash check. That is what makes it
## affordable on every push retarget, and it is also the whole policy: a body interrupts an errand for
## something that hit it, never for something it merely walked past.
func _turn_on_attacker(agent: NavAgent) -> bool:
	var hit := _forced_prey_aim()
	if hit == Vector3.INF:
		return false
	_mark_hot_pursuit(hit)
	_prey = hit
	_prey_at_msec = Time.get_ticks_msec()
	_unit.set_combat_prey(hit)
	var next := _hunt(hit)
	if next == null:
		## Already inside strike reach: hold here and let MonsterCombat swing. A corridor to a
		## point this body is already standing on completes every frame and re-paths forever.
		agent.abandon_goal()
	else:
		agent.set_goal(next)
	return true


## Aim of the aggro head if it is still reachable; otherwise drops dead heads until one is, or
## the queue is empty. "Unreachable" here is dead / freed / outside the leash — navigator failure
## drops the head in `goal_failed` instead, because that is the only place that knows the corridor
## itself gave up.
func _forced_prey_aim() -> Vector3:
	_prune_aggro_heads()
	if _aggro_queue.is_empty():
		return Vector3.INF
	return _aim_of_attacker(_aggro_queue[0])


## Drop heads that can no longer be fought. Does not reorder the rest of the queue.
func _prune_aggro_heads() -> void:
	while not _aggro_queue.is_empty():
		var attacker: Node = _aggro_queue[0]
		if attacker == null or not is_instance_valid(attacker):
			_aggro_queue.remove_at(0)
			continue
		var aim := _aim_of_attacker(attacker)
		if aim == Vector3.INF or not _inside_leash(aim):
			_aggro_queue.remove_at(0)
			continue
		return


## After a hunt corridor dies: drop the head only when this body cannot fight it from where it
## stands. In engage range the head stays — the navigator failing is not the same as the target
## being gone.
func _drop_aggro_head_if_unreachable() -> void:
	if _aggro_queue.is_empty():
		return
	var head: Node = _aggro_queue[0]
	if head == null or not is_instance_valid(head):
		_aggro_queue.remove_at(0)
		return
	var aim := _aim_of_attacker(head)
	if aim == Vector3.INF or not _inside_leash(aim):
		_aggro_queue.remove_at(0)
		return
	var head_r := 0.0
	var head_unit := head as UndeadUnit
	if head_unit != null and head_unit.has_method("hit_radius"):
		head_r = float(head_unit.call("hit_radius"))
	if _flat(_unit.global_position, aim) > _hunt_engage_m() + head_r:
		## Still needs a corridor to fight, and that corridor is what just failed.
		_aggro_queue.remove_at(0)


func _aim_of_attacker(attacker: Node) -> Vector3:
	if attacker == null or not is_instance_valid(attacker):
		return Vector3.INF
	var unit := attacker as UndeadUnit
	if unit != null:
		if not unit.is_alive():
			return Vector3.INF
		return unit.global_position + Vector3(0.0, 1.0, 0.0)
	## Player body from CityRoot, or any Node3D stand-in (headless stubs).
	if _city != null and _city.has_method("get_player_node"):
		var player: Node = _city.call("get_player_node") as Node
		if player != null and is_instance_valid(player) and attacker == player and _city.is_player_alive():
			return _city.get_player_target_position()
	var as3 := attacker as Node3D
	if as3 != null:
		return as3.global_position + Vector3(0.0, 1.0, 0.0)
	return Vector3.INF


## Walk to the remembered aim point itself (not a combat stand-off).
func _investigate_goal() -> NavGoal:
	return _tagged(NavGoal.go_to_point(_lkp, ARRIVE_TOLERANCE_M), TAG_HUNT)


func _should_give_up_investigate() -> bool:
	if _lkp == Vector3.INF:
		return true
	var flat := _flat(_unit.global_position, _lkp)
	if _investigate_age_sec >= INVESTIGATE_TIMEOUT_SEC:
		return true
	if flat > _investigate_leash_m():
		return true
	## Arrived at LKP after a short search window and still nothing visible.
	if flat <= ARRIVE_TOLERANCE_M and _investigate_age_sec >= INVESTIGATE_MIN_SEC:
		return true
	return false


func _investigate_leash_m() -> float:
	var combat: RefCounted = _unit.combat()
	if combat != null:
		var leash: float = float(combat.call("leash_m"))
		if leash > 0.0:
			return leash
		var aggro: float = float(combat.call("aggro_range_m"))
		if aggro > 0.0:
			return aggro * 1.25
	return UndeadUnit.MAGE_PURSUE_RANGE_M * 1.25


func _has_unit() -> bool:
	return _unit != null and is_instance_valid(_unit)
