## What one undead wants next: living prey by combat-table weights, a facade when buildings
## are weighted, a grow pad when the director asks, and a wander when the city offers none.
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
## After a miss, do not re-run the city-wide fabric probe from nearly the same place. The
## probe is budgeted now, but a TRAPPED / unreachable loop would still burn a column budget
## every acquire without this.
const FACADE_MISS_CACHE_SEC := 1.25
const FACADE_MISS_REUSE_M := 10.0
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
## Whoever last hurt this body — overrides table prey weights / LOS acquire until cleared.
var _forced_attacker: Node = null
## The wall voxel behind the current facade goal — the goal itself points at the span the
## body stands on, not at the solid it is there to chew.
var _facade: Vector3 = Vector3.INF
## Set when the ladder gave up on a goal: look somewhere else before looking there again.
var _wander_next: bool = false
var _facade_miss_at_msec: int = -1000000
var _facade_miss_from: Vector3 = Vector3.INF


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


## Promote `attacker` (player body or UndeadUnit) above all table prey rules.
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
		## Engage-in-place (null hunt): refresh living aim so strikes track the player
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
func _handle_lost_prey() -> NavGoal:
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

## SEEK_PED: pick the highest-weighted option among living prey and buildings.
func _hunt_or_chew() -> NavGoal:
	CityProfiler.begin("undead_hunt_pick")
	var combat: RefCounted = _unit.combat()
	## Legacy minion path when no combat kit (should not happen after setup).
	if combat == null:
		var legacy_goal: NavGoal
		if _unit.role == UndeadUnit.Role.MINION:
			legacy_goal = _facade_goal(UndeadUnit.MINION_BUILDING_SEEK_M, TAG_NIBBLE)
		else:
			var legacy := _nearest_living_prey()
			if legacy != Vector3.INF:
				_unit.set_combat_prey(legacy)
				legacy_goal = _hunt(legacy)
			else:
				var legacy_memory := _handle_lost_prey()
				legacy_goal = legacy_memory if legacy_memory != null else _wander()
		CityProfiler.end("undead_hunt_pick")
		return legacy_goal

	## Living-memory investigate outranks building nibble until pursuit clears.
	if _pursuit == Pursuit.INVESTIGATE and _lkp != Vector3.INF:
		var reacquired := _nearest_living_prey()
		if reacquired != Vector3.INF:
			_unit.set_combat_prey(reacquired)
			var hot_goal := _hunt(reacquired)
			CityProfiler.end("undead_hunt_pick")
			return hot_goal
		var memory := _handle_lost_prey()
		if memory != null:
			_unit.set_combat_prey(Vector3.INF)
			CityProfiler.end("undead_hunt_pick")
			return memory

	var best_kind := ""
	var best_score := -1.0
	var best_living := Vector3.INF
	var from := _unit.global_position
	var range_m := UndeadUnit.MINION_BUILDING_SEEK_M
	var aggro: float = float(combat.call("aggro_range_m"))
	if aggro > 0.0:
		range_m = maxf(range_m, aggro)
	var d_living := INF

	if bool(combat.call("has_living_prey")) and _unit.nav_tier() != NavLod.Tier.FAR:
		var living := _nearest_living_prey()
		if living != Vector3.INF:
			d_living = Vector2(living.x - from.x, living.z - from.z).length()
			## Use the same weight that won the living pick: prefer player weight when the
			## aim is the player, else ped / monsters — approximated by max living weight.
			var w_living := maxf(
				float(combat.call("prey_weight", "player")),
				maxf(
					float(combat.call("prey_weight", "ped")),
					float(combat.call("prey_weight", "monsters"))
				)
			)
			var score_living := w_living / maxf(d_living, 0.5)
			if score_living > best_score:
				best_score = score_living
				best_kind = "living"
				best_living = living
		elif _pursuit == Pursuit.HOT and _lkp != Vector3.INF:
			## Acquire path saw Hot then lost LOS before a corridor existed.
			var lost := _handle_lost_prey()
			if lost != null:
				_unit.set_combat_prey(Vector3.INF)
				CityProfiler.end("undead_hunt_pick")
				return lost

	## Building fabric flood is the expensive path. Skip it when living prey is close enough
	## to commit to — otherwise one summoned minion re-scans tens of metres of voxels every
	## time a trivial hunt goal completes.
	var skip_building := false
	if best_kind == "living" and d_living <= maxf(_hunt_stand_off_m() * 4.0, 16.0):
		skip_building = true

	if not skip_building and bool(combat.call("has_building_prey")):
		var fabric := _city.find_nearest_building_nibble(from, range_m)
		if fabric != Vector3.INF:
			var d_build := Vector2(fabric.x - from.x, fabric.z - from.z).length()
			var w_build := float(combat.call("prey_weight", "building"))
			var score_build := w_build / maxf(d_build, 0.5)
			if score_build > best_score:
				best_score = score_build
				best_kind = "building"

	var picked: NavGoal
	if best_kind == "living":
		_unit.set_combat_prey(best_living)
		picked = _hunt(best_living)
	else:
		_unit.set_combat_prey(Vector3.INF)
		if best_kind == "building":
			picked = _facade_goal(range_m, TAG_NIBBLE)
		elif _unit.role == UndeadUnit.Role.MINION:
			## FODDER / convert-minion slot: when nothing living is in range, chew fabric even if
			## the averaged prey weights left building at zero (pure chase brutes spawned as MINION).
			picked = _facade_goal(range_m, TAG_NIBBLE)
		else:
			picked = _wander()
	CityProfiler.end("undead_hunt_pick")
	return picked


## Aimed at the spot the body wants to fight from, not at the prey: a corridor ends where it
## is aimed, and a goal's radius only decides whether arriving counted.
func _hunt(prey: Vector3) -> NavGoal:
	var from := _unit.global_position
	var away := from - prey
	away.y = 0.0
	var distance := away.length()
	var stand_off := _hunt_stand_off_m()
	if distance <= stand_off:
		## Already in range: hold and let MonsterCombat strike. A trivial go_to(self) goal
		## completes every physics frame, re-acquires, and re-paths — that alone tanks FPS.
		_unit.set_combat_prey(prey)
		return null
	return _tagged(
		NavGoal.go_to_point(prey + away / distance * stand_off, ARRIVE_TOLERANCE_M), TAG_HUNT
	)


func _hunt_stand_off_m() -> float:
	var combat: RefCounted = _unit.combat()
	if combat != null:
		return float(combat.call("hunt_standoff_m"))
	## Legacy mage orb standoff.
	if _unit.can_cast():
		return UndeadUnit.ORB_RANGE_M * UndeadUnit.ORB_STANDOFF_FRACTION
	return UndeadUnit.MAGE_CLOSE_IN_M


func _demolish() -> NavGoal:
	## Giants still peel buildings; if they also hunt the player, prefer living prey in range.
	var combat: RefCounted = _unit.combat()
	if combat != null and bool(combat.call("has_living_prey")) and _unit.nav_tier() != NavLod.Tier.FAR:
		var prey := _nearest_living_prey()
		if prey != Vector3.INF:
			_unit.set_combat_prey(prey)
			return _hunt(prey)
		var memory := _handle_lost_prey()
		if memory != null:
			_unit.set_combat_prey(Vector3.INF)
			return memory
	var seek := UndeadUnit.GIANT_BUILDING_SEEK_M
	if combat != null:
		var aggro: float = float(combat.call("aggro_range_m"))
		if aggro > 0.0:
			seek = maxf(seek, aggro)
	return _facade_goal(seek, TAG_DEMOLISH)


## Building fabric is solid, so it is never a destination: the goal is the nearest span this
## profile can stand on beside it, and the wall voxel is remembered for the working state.
func _facade_goal(seek_m: float, tag: StringName) -> NavGoal:
	var from := _unit.global_position
	if _facade_miss_is_fresh(from):
		return _wander()
	var fabric := _city.find_nearest_building_nibble(from, seek_m)
	if fabric == Vector3.INF:
		_remember_facade_miss(from)
		return _wander()
	var stand := NavService.instance().nearest_surface(
		_unit.nav_profile_id(), _approach_point(fabric), FACADE_SNAP_M
	)
	if not stand.found:
		## Nothing this body can stand on beside that wall — a giant in an alley, usually.
		_remember_facade_miss(from)
		return _wander()
	_facade = fabric
	_facade_miss_at_msec = -1000000
	return _tagged(NavGoal.go_to_point(stand.position, ARRIVE_TOLERANCE_M), tag)


func _facade_miss_is_fresh(from: Vector3) -> bool:
	if _facade_miss_at_msec < 0:
		return false
	if Time.get_ticks_msec() - _facade_miss_at_msec >= int(FACADE_MISS_CACHE_SEC * 1000.0):
		return false
	return from.distance_to(_facade_miss_from) <= FACADE_MISS_REUSE_M


func _remember_facade_miss(from: Vector3) -> void:
	_facade_miss_at_msec = Time.get_ticks_msec()
	_facade_miss_from = from


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

## Living prey inside aggro range with clear voxel LOS. Among visible targets: highest
## combat-table weight, then closest. A forced attacker (revenge) overrides all of that —
## no weight filter, no LOS gate for acquire (shots still check LOS in MonsterCombat).
## Vector3.INF for nobody.
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
	var range_m := UndeadUnit.MAGE_PURSUE_RANGE_M
	if combat != null:
		var aggro: float = float(combat.call("aggro_range_m"))
		if aggro > 0.0:
			range_m = aggro
	var from := _unit.global_position
	var eye := _unit.muzzle_world() if _unit.has_method("muzzle_world") else from + Vector3(0.0, 1.4, 0.0)
	## { "pos": Vector3, "weight": float, "dist": float }
	var candidates: Array[Dictionary] = []

	var w_player := 1.0
	if combat != null:
		w_player = float(combat.call("prey_weight", "player"))
	if w_player > 0.0 and _city.is_player_alive():
		var ppos := _city.get_player_target_position()
		var d := Vector2(ppos.x - from.x, ppos.z - from.z).length()
		if d <= range_m:
			candidates.append({"pos": ppos, "weight": w_player, "dist": d})

	var w_ped := 0.8
	if combat != null:
		w_ped = float(combat.call("prey_weight", "ped"))
	if w_ped > 0.0 and _city.has_method("collect_ped_positions"):
		var peds: PackedVector3Array = _city.call(
			"collect_ped_positions", from, range_m
		) as PackedVector3Array
		for i in range(peds.size()):
			var ped: Vector3 = peds[i]
			var d_ped := Vector2(ped.x - from.x, ped.z - from.z).length()
			if d_ped <= range_m:
				candidates.append({
					"pos": ped + Vector3(0.0, 1.0, 0.0),
					"weight": w_ped,
					"dist": d_ped,
				})

	var w_monsters := 0.0
	if combat != null:
		w_monsters = float(combat.call("prey_weight", "monsters"))
	if w_monsters > 0.0 and _city.has_method("collect_hostile_monster_positions"):
		var others: PackedVector3Array = _city.call(
			"collect_hostile_monster_positions", from, range_m, _unit
		) as PackedVector3Array
		for j in range(others.size()):
			var other: Vector3 = others[j]
			var d_m := Vector2(other.x - from.x, other.z - from.z).length()
			if d_m <= range_m:
				candidates.append({"pos": other, "weight": w_monsters, "dist": d_m})

	var best := Vector3.INF
	var best_weight := -1.0
	var best_dist := INF
	for c in candidates:
		var pos: Vector3 = c["pos"] as Vector3
		if not _city.has_voxel_line_of_sight(eye, pos):
			continue
		var w: float = float(c["weight"])
		var d: float = float(c["dist"])
		if w > best_weight or (is_equal_approx(w, best_weight) and d < best_dist):
			best_weight = w
			best_dist = d
			best = pos
	_prey = best
	if best != Vector3.INF:
		_mark_hot_pursuit(best)
	return _prey


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


func _clear_pursuit() -> void:
	_pursuit = Pursuit.NONE
	_lkp = Vector3.INF
	_investigate_age_sec = 0.0
	_forced_attacker = null


## Forced attacker aim if still valid and inside leash; otherwise drops the sticky target.
func _forced_prey_aim() -> Vector3:
	if _forced_attacker == null or not is_instance_valid(_forced_attacker):
		_forced_attacker = null
		return Vector3.INF
	var aim := _aim_of_attacker(_forced_attacker)
	if aim == Vector3.INF:
		_forced_attacker = null
		return Vector3.INF
	var from := _unit.global_position
	var flat := Vector2(aim.x - from.x, aim.z - from.z).length()
	if flat > _investigate_leash_m():
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
	var from := _unit.global_position
	var flat := Vector2(from.x - _lkp.x, from.z - _lkp.z).length()
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
