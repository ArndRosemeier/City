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
## Whoever last hurt this body — overrides the committed target until it leaves the leash.
var _forced_attacker: Node = null
## The body this hunter committed to. The player and other monsters are nodes; pedestrians
## are crowd positions with no node to hold, so their commitment is the last aim point and
## is re-matched against the fresh crowd every query. Exactly one of the two is ever set.
var _target_node: Node = null
var _target_ped: Vector3 = Vector3.INF
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
	_clear_pursuit()


## Test / debug: NONE / HOT / INVESTIGATE.
func pursuit() -> Pursuit:
	return _pursuit


func last_known_prey() -> Vector3:
	return _lkp


## True while a damage-driven attacker is sticky pursuit prey.
func has_forced_attacker() -> bool:
	return _forced_attacker != null and is_instance_valid(_forced_attacker)


## True while this body is holding one chosen target rather than re-picking every query.
func has_committed_target() -> bool:
	return _target_node != null or _target_ped != Vector3.INF


## Promote `attacker` (player body or UndeadUnit) above the committed target.
func promote_attacker(attacker: Node) -> void:
	if not _has_unit() or attacker == null or not is_instance_valid(attacker):
		return
	if attacker == _unit:
		return
	_forced_attacker = attacker
	_prey_at_msec = -1000000
	var aim := _aim_of_attacker(attacker)
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
## it, so the next goal takes it somewhere else first.
func goal_failed(_request: NavGoalRequest, goal: NavGoal, state: NavLadder.State) -> void:
	if not _has_unit():
		return
	_prey = Vector3.INF
	_prey_at_msec = -1000000
	_clear_pursuit()
	_unit.set_combat_prey(Vector3.INF)
	_unit.on_goal_failed(goal, state)
	_wander_next = goal.tag != TAG_WANDER


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
		agent.set_goal(_wander())
		return
	_unit.set_combat_prey(Vector3.INF)
	if memory.point.distance_to(goal.point) <= RETARGET_SLACK_M:
		return
	agent.set_goal(memory)


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
	if _unit.nav_tier() == NavLod.Tier.FAR:
		## Nobody is close enough to see this body fight; the crowd query is not worth it.
		goal = _wander()
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
				## Siege attackers (and anything else with a standing push) walk the objective
				## before they shuffle. Without this the horde would never reach the Lodestone
				## — defenders are unacquirable, so there is never a hunt target on the way in.
				if _unit.push_aim() != Vector3.INF:
					## Null from `_push_goal` here means "inside the vulnerability radius, hold".
					## Wandering on that null is what kept the horde circling the Lodestone.
					goal = _push_goal()
				else:
					goal = _wander()
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
	if distance <= engage:
		## Close enough to swing: hold and let MonsterCombat strike. A trivial go_to(self)
		## goal completes every physics frame, re-acquires, and re-paths — that alone tanks FPS.
		## Engage is the *strike* reach, not the stand-off the corridor aims at: a body that
		## lands a touch short of stand-off must still fight, not open another approach.
		_unit.set_combat_prey(prey)
		return null
	var stand_off := minf(_hunt_stand_off_m(), engage)
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


func _wander() -> NavGoal:
	return _tagged(NavGoal.wander(_unit.global_position, WANDER_RADIUS_M), TAG_WANDER)


## Standing push (Lodestone). Null once the body is inside the objective's vulnerability
## radius, meaning **hold here** — callers must not read that as "nothing to do" and wander
## off, because holding still is what lets the controller land contact damage.
##
## The aim is the *centre* of a solid objective. Pathing into that point forever PATH_PARTIALs
## around the shell (melee "dance"). Walk to a standable ring instead, set a little inside the
## vulnerability radius so any re-path only ever moves the body further in.
func _push_goal() -> NavGoal:
	var aim := _unit.push_aim()
	if aim == Vector3.INF:
		return null
	var vuln_r := _unit.push_hold_m()
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


func _tagged(goal: NavGoal, tag: StringName) -> NavGoal:
	goal.tag = tag
	return goal


# ---------------------------------------------------------------------------
# Who this body is fighting
# ---------------------------------------------------------------------------

## Aim point of whoever this body is fighting, or Vector3.INF for nobody visible.
##
## Order of authority: the attacker that last hurt it, then the target it already committed
## to, then a fresh pick. A committed target that is in range but out of sight yields INF on
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
	_forced_attacker = null
	_clear_target()


## Forced attacker aim if still valid and inside leash; otherwise drops the sticky target.
func _forced_prey_aim() -> Vector3:
	if _forced_attacker == null or not is_instance_valid(_forced_attacker):
		_forced_attacker = null
		return Vector3.INF
	var aim := _aim_of_attacker(_forced_attacker)
	if aim == Vector3.INF:
		_forced_attacker = null
		return Vector3.INF
	if not _inside_leash(aim):
		_forced_attacker = null
		return Vector3.INF
	return aim


func _aim_of_attacker(attacker: Node) -> Vector3:
	var unit := attacker as UndeadUnit
	if unit != null:
		if not unit.is_alive():
			return Vector3.INF
		return unit.global_position + Vector3(0.0, 1.0, 0.0)
	## Player body from CityRoot, or any Node3D stand-in (headless stubs).
	if _city != null and _city.has_method("get_player_node"):
		var player: Node = _city.call("get_player_node") as Node
		if player != null and attacker == player and _city.is_player_alive():
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
