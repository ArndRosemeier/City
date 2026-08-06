## Undead on the navigation stack: the goal provider, the corridors it produces, and the
## failure ladder that replaced the old local unstick code.
##
## The city is stubbed rather than booted — what is under test is undead_unit.gd and
## undead_goal_provider.gd talking to a real NavService over a hand-painted tile, not
## CityRoot's world generation. The tile states its geometry: an open deck a giant fits on,
## and one sealed sixteen-metre tower that is both an unreachable roof and somewhere to be
## entombed. Nothing hunts the tower — buildings are not targets — so every case here gives
## its body a pedestrian to want and watches how it gets there.
##
## Two `NavAgent ... TRAPPED ... escape=TELEPORTED / DUG_OUT` warnings on stderr are expected and
## are the last two cases asserting themselves: being loud about an entombment is the behaviour
## under test, so silencing them here would delete the signal the port was written to produce.
## Every other line on stderr is a defect.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_undead_nav.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
## Deep enough that headroom is never why a span is missing, giants included.
const FIELD_Y_MAX := 47

## Parked far from every real district and from the other nav tests' tiles.
const TILE := Vector2i(120, 120)
const ORIGIN := Vector3i(50000, 0, 50000)
const SX := 160
const SZ := 120
## Sealed brick tower. Sixteen metres of sheer facade: one climb link cannot reach the roof
## and a blank wall has no landing span to chain them from.
const TOWER_MIN := Vector3i(120, 1, 50)
const TOWER_MAX := Vector3i(140, 33, 70)

## A siege outer stone, painted here exactly as `SiegeComposer._paint_obelisk` paints it: a 9-voxel
## square plinth flush with the deck, a 7-voxel step one course up, and a 3-voxel needle above that.
## Copied rather than shared because what is under test is whether a *walker* can reach the middle of
## this shape — the answer is a property of the geometry, so the geometry has to be the real one.
const OBELISK_CENTRE := Vector3i(60, 1, 114)
const OBELISK_FOOTPRINT := 4
const OBELISK_SHAFT_HALF := 1
const OBELISK_COURSES := 22

## Hold radius the siege beacons are registered with, and the one the controller actually produces:
## `SiegeController._stone_vulnerable_radius_m` floors the authored 5 m against an obelisk's own
## footprint, and 5 m wins. One number for "stop walking" and "you are hurting it", so a body that
## stops outside it is a body that never damages a stone.
const STONE_HOLD_M := 5.0

## Fixed simulation step, so nothing here depends on the headless frame rate.
const SIM_DT := 0.05
const MAX_FRAMES := 700
## Keeps every case in the mid LOD tier: far enough out of the 20 m near band that no body
## needs a collider, close enough that none of them drops to interpolation.
const OBSERVER_OFFSET_M := 45.0

## Model choice and body build come from a unit's seed, so both are pinned here: what is
## under test is the ladder, not whichever creature the catalogue happened to roll.
const BODY_SEED := 20260728
const DEFAULT_BODY: Dictionary[int, String] = {
	int(UndeadUnit.Role.MAGE): "kaykit/Skeleton_Mage",
	int(UndeadUnit.Role.MINION): "kaykit/Skeleton_Minion",
	## A melee elite: it closes to contact range, so the corridor a buried giant asks for ends
	## out on the deck rather than inside the brick it is entombed in.
	int(UndeadUnit.Role.GIANT): "big/Orc",
}
## A Quaternius Big body, three metres tall, which is the whole reason the mid-size profile
## exists.
const MONSTER_BODY := "big/Orc"

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain
## Ladder states seen while a case ran, in order.
var _states: Array[int] = []


# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

## CityRoot with the handful of world queries undead ask it, answered from the test instead
## of from a generated city. Never entered into the tree, so `_ready` never boots a world.
class TestCity:
	extends CityRoot
	var player_at: Vector3 = Vector3.ZERO
	## The crowd this city has: up to two pedestrians, either slot Vector3.INF for absent.
	## Two, because sticky pursuit is only a claim you can test with somebody else around.
	var prey_at: Vector3 = Vector3.INF
	var prey_b: Vector3 = Vector3.INF
	var brush: CityBrush = null
	## When false, voxel LOS fails (corner-juke / pursuit investigate tests).
	var los_ok: bool = true

	func is_player_alive() -> bool:
		## Units refuse to tick while the player is dead; keep them alive for the sim.
		return true

	func get_player_position() -> Vector3:
		## LOD observer — kept near the body so nav tiers stay NEAR.
		return player_at

	func get_player_target_position() -> Vector3:
		## Not a combatant. Headless undead tests hunt the crowd instead.
		return Vector3.INF

	func find_nearest_ped_position(from: Vector3, max_dist: float) -> Vector3:
		var best := Vector3.INF
		var best_d := INF
		for ped: Vector3 in collect_ped_positions(from, max_dist):
			var d := from.distance_to(ped)
			if d < best_d:
				best_d = d
				best = ped
		return best

	func find_nearest_ped_only(from: Vector3, max_dist: float) -> Vector3:
		return find_nearest_ped_position(from, max_dist)

	func collect_ped_positions(from: Vector3, max_dist: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		for ped: Vector3 in [prey_at, prey_b]:
			if ped != Vector3.INF and from.distance_to(ped) <= max_dist:
				out.append(ped)
		return out

	func has_voxel_line_of_sight(_from_world: Vector3, _to_world: Vector3) -> bool:
		return los_ok

	func voxel_brush() -> CityBrush:
		return brush

	func try_orb_hit_player(_world_pos: Vector3, _radius: float) -> bool:
		return false

	func try_convert_ped_near(_world_pos: Vector3, _radius: float) -> Variant:
		return null


## Invasion director on a harness-owned MonsterRoster (terrain injected, no CityRoot boot).
class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		var monsters := MonsterRoster.new()
		monsters.name = "MonsterRoster"
		add_child(monsters)
		monsters.setup(city, terrain, lod)
		_roster = monsters


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
	if not _nav.register_district(TILE, _bake_tile()):
		_fail("FAIL NavService refused the test tile")
		_quit()
		return

	## A coordinate frame, not a world: nothing streams off it, it is here because world
	## metres become voxels through the terrain transform, exactly as CityRoot scales it.
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	_city = TestCity.new()
	_city.brush = _offline_brush()
	_director = TestDirector.new()
	_director.name = "UndeadInvasion"
	add_child(_director)
	_director.bind(_city, _terrain, NavLod.for_collision_view(48, VOXEL_SIZE))

	_test_no_hacks_left()
	if _failed:
		_quit()
		return
	await _test_minion_walks_to_its_prey()
	if _failed:
		_quit()
		return
	await _test_mage_closes_to_orb_range()
	if _failed:
		_quit()
		return
	await _test_pursuit_investigates_after_los_break()
	if _failed:
		_quit()
		return
	await _test_sticky_target_survives_a_closer_one()
	if _failed:
		_quit()
		return
	await _test_mid_size_monster_walks_its_own_profile()
	if _failed:
		_quit()
		return
	await _test_unreachable_goal_escalates_instead_of_teleporting()
	if _failed:
		_quit()
		return
	await _test_entombed_undead_is_reported()
	if _failed:
		_quit()
		return
	await _test_giant_digs_out_through_the_brush()
	if _failed:
		_quit()
		return
	await _test_siege_attacker_walks_to_a_beacon()
	if _failed:
		_quit()
		return
	await _test_stone_bound_body_settles_inside_the_damage_radius()
	if _failed:
		_quit()
		return
	await _test_shot_attacker_turns_on_the_tower()
	if _failed:
		_quit()
		return
	await _test_far_attacker_turns_on_the_tower()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# The hacks the port exists to remove
# ---------------------------------------------------------------------------

## The plan names these: `_unstuck_horizontal()` teleported a jammed body to a free footprint
## and `_update_stuck()` decided when, both silently. The ladder's TRAPPED rung replaces them
## and reports every occurrence, so none of this may come back.
func _test_no_hacks_left() -> void:
	var banned: Array[String] = [
		"_unstuck_horizontal",
		"_update_stuck",
		"_can_stand_at",
		"_ensure_free_spawn_footing",
		"_slide_off_walls",
		"_do_stomp",
		"_wander_accum",
		"move_and_slide",
	]
	for path: String in [
		"res://scripts/city/undead_unit.gd",
		"res://scripts/city/undead_invasion_director.gd",
		"res://scripts/city/undead_goal_provider.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_fail("FAIL cannot read %s" % path)
			return
		var text := file.get_as_text()
		file.close()
		for hack: String in banned:
			if text.contains(hack):
				_fail("FAIL %s still references %s" % [path, hack])
				return
	print("hacks: none of %s survive in the undead scripts" % str(banned))


# ---------------------------------------------------------------------------
# Walking a corridor to what the provider asked for
# ---------------------------------------------------------------------------

## A minion crosses the deck to the only thing it hunts: a body of another faction. It closes
## to contact rather than to some stand-off, because melee is the whole kit it has.
func _test_minion_walks_to_its_prey() -> void:
	var start := _w(Vector3i(30, 1, 90))
	_city.prey_at = _w(Vector3i(110, 1, 90))
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	NavAgent.reset_events()

	var frames := await _run(
		unit,
		func() -> bool: return unit.global_position.distance_to(_city.prey_at) <= 3.0
	)
	var reach := unit.global_position.distance_to(_city.prey_at)
	if reach > 3.0:
		_fail(
			"FAIL the minion is %.1f m from its prey after %d ticks (state %d, ladder %s)"
			% [reach, frames, unit.state, NavLadder.state_name(unit.nav_state())]
		)
		return
	var walked := start.distance_to(unit.global_position)
	if walked < 10.0:
		_fail("FAIL the minion only covered %.1f m before claiming to be on its prey" % walked)
		return
	if NavAgent.trapped_events() != 0:
		_fail("FAIL crossing an open deck reported %d entombments" % NavAgent.trapped_events())
		return
	if unit.state != UndeadUnit.State.SEEK_PED:
		_fail("FAIL a minion standing on its prey is in state %d" % unit.state)
		return
	if unit.combat_prey() == Vector3.INF:
		_fail("FAIL the minion arrived with nothing to swing at")
		return
	print("minion: %.1f m to a human in %d ticks, still on it" % [walked, frames])
	_despawn(unit)
	_city.prey_at = Vector3.INF


## The mage stops at orb range and fires, rather than walking into the pedestrian.
func _test_mage_closes_to_orb_range() -> void:
	var start := _w(Vector3i(40, 1, 30))
	_city.prey_at = _w(Vector3i(110, 1, 30))
	var unit := _spawn(UndeadUnit.Role.MAGE, start)
	if unit == null:
		return
	NavAgent.reset_events()

	var frames := await _run(unit, func() -> bool: return not unit.can_cast())
	if unit.can_cast():
		_fail(
			"FAIL the mage never cast in %d ticks, %.1f m from its prey (ladder %s)"
			% [
				frames,
				unit.global_position.distance_to(_city.prey_at),
				NavLadder.state_name(unit.nav_state()),
			]
		)
		return
	var range_m := unit.global_position.distance_to(_city.prey_at)
	if range_m > UndeadUnit.ORB_RANGE_M:
		_fail("FAIL the mage fired from %.1f m, past its %.1f m orb" % [range_m, UndeadUnit.ORB_RANGE_M])
		return
	if range_m < UndeadUnit.ORB_RANGE_M * 0.5:
		_fail("FAIL the mage closed to %.1f m instead of holding orb range" % range_m)
		return
	if NavAgent.trapped_events() != 0:
		_fail("FAIL hunting reported %d entombments" % NavAgent.trapped_events())
		return
	print("mage: closed to %.1f m and cast after %d ticks" % [range_m, frames])
	_despawn(unit)
	_city.prey_at = Vector3.INF


## After LOS breaks, the body keeps a hunt corridor to the last seen prey point with
## combat_prey cleared (no blind fire), then drops memory when the investigate window ends.
func _test_pursuit_investigates_after_los_break() -> void:
	var start := _w(Vector3i(40, 1, 40))
	var prey := _w(Vector3i(100, 1, 40))
	_city.prey_at = prey
	_city.los_ok = true
	var unit := _spawn(UndeadUnit.Role.MAGE, start)
	if unit == null:
		return
	var provider := unit.goal_provider()
	if provider == null:
		_fail("FAIL mage has no goal provider")
		return

	var frames := await _run(
		unit,
		func() -> bool: return provider.pursuit() == UndeadGoalProvider.Pursuit.HOT
	)
	if provider.pursuit() != UndeadGoalProvider.Pursuit.HOT:
		_fail("FAIL pursuit never went Hot in %d ticks (prey %.1f m away)" % [
			frames,
			start.distance_to(prey),
		])
		return
	var lkp := provider.last_known_prey()
	if lkp == Vector3.INF:
		_fail("FAIL Hot pursuit stored no last-known prey")
		return
	if unit.combat_prey() == Vector3.INF:
		_fail("FAIL Hot pursuit cleared combat_prey")
		return

	## Prey ducks behind geometry — still in range, but no voxel LOS.
	_city.los_ok = false
	frames = await _run(
		unit,
		func() -> bool: return provider.pursuit() == UndeadGoalProvider.Pursuit.INVESTIGATE
	)
	if provider.pursuit() != UndeadGoalProvider.Pursuit.INVESTIGATE:
		_fail("FAIL LOS break did not enter Investigate in %d ticks (phase %d)" % [
			frames,
			provider.pursuit(),
		])
		return
	if unit.combat_prey() != Vector3.INF:
		_fail("FAIL Investigate left combat_prey set for blind fire")
		return
	var goal := unit.nav_agent().goal()
	if goal == null or goal.tag != UndeadGoalProvider.TAG_HUNT:
		_fail("FAIL Investigate has no hunt goal toward LKP")
		return
	var goal_flat := Vector2(goal.point.x - lkp.x, goal.point.z - lkp.z).length()
	if goal_flat > 2.5:
		_fail(
			"FAIL Investigate goal is %.1f m from LKP (expected the remembered point)"
			% goal_flat
		)
		return

	## Wait out the investigate timeout with LOS still blocked.
	frames = await _run(
		unit,
		func() -> bool: return provider.pursuit() == UndeadGoalProvider.Pursuit.NONE
	)
	if provider.pursuit() != UndeadGoalProvider.Pursuit.NONE:
		_fail("FAIL Investigate never cleared after timeout (%d ticks, phase %d)" % [
			frames,
			provider.pursuit(),
		])
		return
	if provider.last_known_prey() != Vector3.INF:
		_fail("FAIL cleared pursuit kept an LKP")
		return
	if unit.combat_prey() != Vector3.INF:
		_fail("FAIL cleared pursuit kept combat_prey")
		return
	print("pursuit: Hot → Investigate (no blind prey) → cleared after timeout")
	_despawn(unit)
	_city.prey_at = Vector3.INF
	_city.los_ok = true


## Committing to a target means keeping it. A second human walking past at arm's length is
## exactly the case the old closest-wins pick got wrong: the hunter would swap every query and
## never finish either chase. It only lets go once the one it picked is gone.
##
## The mage is the body for this because it holds orb range instead of walking, so what moves
## between the phases is the crowd and nothing else. The committed pedestrian is nudged a
## metre — inside the re-match radius, so it is still the same person — and the last-known
## point moving with it is what proves a fresh query ran rather than a cache being read.
func _test_sticky_target_survives_a_closer_one() -> void:
	var start := _w(Vector3i(30, 1, 95))
	var first := _w(Vector3i(70, 1, 95))
	var first_moved := _w(Vector3i(72, 1, 95))
	var closer := _w(Vector3i(34, 1, 95))
	_city.prey_at = first
	_city.prey_b = Vector3.INF
	_city.los_ok = true
	var unit := _spawn(UndeadUnit.Role.MAGE, start)
	if unit == null:
		return
	var provider := unit.goal_provider()

	var frames := await _run(
		unit,
		func() -> bool: return provider.pursuit() == UndeadGoalProvider.Pursuit.HOT
	)
	if provider.pursuit() != UndeadGoalProvider.Pursuit.HOT:
		_fail("FAIL pursuit never went Hot on the first human in %d ticks" % frames)
		return
	var locked := provider.last_known_prey()
	if locked.distance_to(first) > 1.5:
		_fail("FAIL Hot pursuit locked onto %s, not the only human there" % str(locked))
		return

	## Somebody much nearer turns up, and the one being chased takes a step.
	_city.prey_b = closer
	_city.prey_at = first_moved
	frames = await _run(
		unit,
		func() -> bool: return provider.last_known_prey().distance_to(locked) > 0.2
	)
	var held := provider.last_known_prey()
	if held.distance_to(locked) <= 0.2:
		_fail(
			"FAIL no fresh prey query landed in %d ticks, so stickiness was never exercised"
			% frames
		)
		return
	if held.distance_to(first_moved) > 1.5:
		_fail(
			"FAIL the mage re-picked %s; %.1f m from the human it committed to and %.1f m"
			% [str(held), held.distance_to(first_moved), held.distance_to(closer)]
			+ " from the one that walked up"
		)
		return
	if not provider.has_committed_target():
		_fail("FAIL a Hot mage is holding no committed target")
		return

	## Its quarry leaves. Only now may the nearer one become the hunt.
	_city.prey_at = Vector3.INF
	frames = await _run(
		unit,
		func() -> bool: return provider.last_known_prey().distance_to(closer) <= 1.5
	)
	var switched := provider.last_known_prey()
	if switched.distance_to(closer) > 1.5:
		_fail(
			"FAIL the mage never took the remaining human in %d ticks (last known %s)"
			% [frames, str(switched)]
		)
		return
	print("sticky: held the first human past a 2 m alternative, took it only once it left")
	_despawn(unit)
	_city.prey_at = Vector3.INF
	_city.prey_b = Vector3.INF


## A three-metre Quaternius body is neither a minion nor a giant. It registers on the
## mid-size profile, which is two cells of clearance and seven of headroom, and it has to
## cross the same open deck the minion does without ever asking the giant profile for the
## eleven cells it does not need.
func _test_mid_size_monster_walks_its_own_profile() -> void:
	var start := _w(Vector3i(90, 1, 95))
	_city.prey_at = _w(Vector3i(30, 1, 95))
	var unit := _spawn(UndeadUnit.Role.MINION, start, MONSTER_BODY)
	if unit == null:
		return
	if unit.nav_profile_id() != NavProfile.Id.MONSTER:
		_fail(
			"FAIL a %s navigates on profile %d, not the mid-size one"
			% [MONSTER_BODY, unit.nav_profile_id()]
		)
		return
	var profile := _nav.profile(NavProfile.Id.MONSTER)
	if profile == null or profile.radius_cells != 2 or profile.height_cells != 7:
		_fail("FAIL the mid-size profile is not 2 cells wide by 7 of headroom")
		return
	## The capsule has to have followed the body up, or a 3 m monster collides as a minion.
	var minion_radius := UndeadUnit.HIT_RADIUS_BASE_M
	if unit.hit_radius() <= minion_radius * 1.1:
		_fail(
			"FAIL a %.2f m body still hits at %.2f m, the reference skeleton's radius"
			% [unit.creature_entry().measured_height, unit.hit_radius()]
		)
		return
	NavAgent.reset_events()

	var frames := await _run(
		unit,
		func() -> bool: return unit.global_position.distance_to(_city.prey_at) <= 4.0
	)
	var reach := unit.global_position.distance_to(_city.prey_at)
	if reach > 4.0:
		_fail(
			"FAIL the monster is %.1f m from its prey after %d ticks (state %d, ladder %s)"
			% [reach, frames, unit.state, NavLadder.state_name(unit.nav_state())]
		)
		return
	if NavAgent.trapped_events() != 0:
		_fail("FAIL the monster reported %d entombments crossing an open deck" % NavAgent.trapped_events())
		return
	print(
		"monster: %s, %.2f m tall, hit radius %.2f (minion base %.2f), ran its prey down in %d ticks"
		% [
			MONSTER_BODY,
			unit.creature_entry().measured_height,
			unit.hit_radius(),
			minion_radius,
			frames,
		]
	)
	_despawn(unit)
	_city.prey_at = Vector3.INF


# ---------------------------------------------------------------------------
# The ladder, where the old code teleported
# ---------------------------------------------------------------------------

## The tower roof is sixteen metres of sheer wall up, and there is somebody standing on it. An
## undead climbs, but not that, and no landing span exists to chain links from — so the goal
## is genuinely impossible. The old code would have jammed against the facade and relocated
## itself; the ladder calls the goal unreachable and leaves the body where it is.
func _test_unreachable_goal_escalates_instead_of_teleporting() -> void:
	var start := _w(Vector3i(100, 1, 90))
	_city.prey_at = _w(Vector3i(130, TOWER_MAX.y, 60))
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	NavAgent.reset_events()
	_states.clear()

	var frames := await _run(
		unit,
		func() -> bool: return _states.has(int(NavLadder.State.GOAL_UNREACHABLE))
	)
	if not _states.has(int(NavLadder.State.GOAL_UNREACHABLE)):
		_fail(
			"FAIL a roof no undead can reach never escalated in %d ticks: %s"
			% [frames, str(_states)]
		)
		return
	if NavAgent.trapped_events() != 0 or NavAgent.teleport_events() != 0:
		_fail(
			"FAIL an unreachable goal produced %d entombments and %d teleports"
			% [NavAgent.trapped_events(), NavAgent.teleport_events()]
		)
		return
	var end := unit.global_position
	if absf(end.y - start.y) > 2.0:
		_fail("FAIL the body ended %.1f m above where it started, so something moved it" % (end.y - start.y))
		return
	var footing := _nav.nearest_surface(NavProfile.Id.UNDEAD, end, 2.0)
	if not footing.found:
		_fail("FAIL the body gave up standing off the span field entirely")
		return
	print("unreachable roof: ladder ran %s, nothing teleported" % str(_states))
	_despawn(unit)
	_city.prey_at = Vector3.INF


## Entombment is the one case that does move a body, and the whole point of the port is that
## it is loud: counted on NavAgent, counted on CityProfiler, and warned about.
func _test_entombed_undead_is_reported() -> void:
	var buried := _w(Vector3i(130, 10, 60))
	## Somebody out on the deck to want, so a corridor is asked for from inside the brick.
	_city.prey_at = _w(Vector3i(100, 1, 60))
	var unit := _spawn(UndeadUnit.Role.MINION, buried)
	if unit == null:
		return
	NavAgent.reset_events()
	_states.clear()

	print("--- the TRAPPED warning below is the assertion ---")
	var frames := await _run(unit, func() -> bool: return NavAgent.trapped_events() > 0)
	if NavAgent.trapped_events() != 1:
		_fail(
			"FAIL a body inside solid brick produced %d trapped events in %d ticks (ladder %s)"
			% [NavAgent.trapped_events(), frames, str(_states)]
		)
		return
	if NavAgent.teleport_events() != 1:
		_fail("FAIL %d escapes counted for one entombment" % NavAgent.teleport_events())
		return
	if not _states.has(int(NavLadder.State.TRAPPED)):
		_fail("FAIL TRAPPED was counted without the ladder reporting it: %s" % str(_states))
		return
	var moved := buried.distance_to(unit.global_position)
	if moved < 1.0:
		_fail("FAIL the entombed body moved %.2f m, so it is still in the wall" % moved)
		return
	var footing := _nav.nearest_surface(NavProfile.Id.UNDEAD, unit.global_position, 2.0)
	if not footing.found:
		_fail("FAIL the escape did not land on a span")
		return
	print("entombed minion: reported, counted and moved %.1f m onto a span" % moved)
	_despawn(unit)
	_city.prey_at = Vector3.INF


# ---------------------------------------------------------------------------
# Giants
# ---------------------------------------------------------------------------

## A giant is entombed off the span field. `can_break` means it is asked to dig rather than
## moved, and the dig has to be a real edit: through CityBrush, the single write funnel, in
## a pocket wide enough for the eleven cells of clearance the giant profile demands.
func _test_giant_digs_out_through_the_brush() -> void:
	## Off the end of the baked tile, but still inside the giant's aggro range, so the goal
	## resolves and the path query fails on the start rather than never being asked.
	var nowhere := _w(Vector3i(SX + 40, 1, 60))
	var centre := Vector3i(ORIGIN.x + SX + 40, ORIGIN.y + 1, ORIGIN.z + 60)
	## Solid to dig out of, wider than the pocket so the pocket's edges can be checked.
	_city.brush.fill_box(
		centre + Vector3i(-16, -1, -16), centre + Vector3i(17, 12, 17), VoxelMaterial.BRICK
	)
	## Somebody real to want, out on the deck, so the query fails on the start rather than
	## the goal — and far enough out that the stand-off point is clear of the brick too.
	_city.prey_at = _w(Vector3i(110, 1, 60))
	var unit := _spawn(UndeadUnit.Role.GIANT, nowhere)
	if unit == null:
		return
	if unit.nav_profile_id() != NavProfile.Id.GIANT:
		_fail("FAIL a giant navigates on profile %d" % unit.nav_profile_id())
		return
	NavAgent.reset_events()
	_states.clear()

	print("--- the TRAPPED warning below is the assertion ---")
	var frames := await _run(unit, func() -> bool: return NavAgent.dig_out_events() > 0)
	if NavAgent.dig_out_events() != 1:
		_fail(
			"FAIL a giant with nowhere to stand asked to dig %d times in %d ticks (ladder %s)"
			% [NavAgent.dig_out_events(), frames, str(_states)]
		)
		return
	if NavAgent.teleport_events() != 0:
		_fail("FAIL a can_break body was moved instead of digging")
		return
	if nowhere.distance_to(unit.global_position) > 0.01:
		_fail("FAIL the giant was relocated as well as dug out")
		return

	var profile := _nav.profile(NavProfile.Id.GIANT)
	var r := profile.radius_cells + UndeadUnit.DIG_OUT_MARGIN_CELLS
	if _city.brush.get_vox(centre + Vector3i(0, 4, 0)) != VoxelMaterial.AIR:
		_fail("FAIL the dig-out left the giant's own cell solid")
		return
	if _city.brush.get_vox(centre + Vector3i(r, 0, 0)) != VoxelMaterial.AIR:
		_fail("FAIL the pocket is narrower than the %d cells the giant profile needs" % r)
		return
	if _city.brush.get_vox(centre + Vector3i(r + 2, 4, 0)) != VoxelMaterial.BRICK:
		_fail("FAIL the dig-out carved past its own footprint")
		return
	if _city.brush.get_vox(centre + Vector3i(0, -1, 0)) != VoxelMaterial.BRICK:
		_fail("FAIL the dig-out removed the floor the giant has to stand on")
		return
	print(
		"giant: entombed off the field, dug a %d cell pocket through CityBrush in %d ticks"
		% [r * 2 + 1, frames]
	)
	_despawn(unit)
	_city.prey_at = Vector3.INF


## A siege attacker walks to a stone under conditions where nothing else in the provider would give
## it anywhere to go: no prey in the city, no line of sight to anything, and the observer parked far
## enough away that navigation is running the body at its far tier — where every other walker gets a
## wander instead of a goal. That combination is the entire point of a beacon, and the siege depends
## on it: the outer stones are ~100 m from the quarter, so a horde that only advanced near the player
## would leave three flanks untouched for the whole run.
func _test_siege_attacker_walks_to_a_beacon() -> void:
	var start := _w(Vector3i(30, 1, 108))
	## Open deck, deliberately not the sealed tower. A beacon in the middle of that block sends
	## bodies to a stand ring inside solid brick, so the ladder gives up and they wander — which is
	## a fine test of the ladder and a useless one for "did it reach its objective".
	var stone := _w(Vector3i(120, 1, 108))
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	unit.set_faction(int(MonsterFaction.Id.SIEGE_ATTACKER))
	## Blind and alone: only a beacon can produce a goal from here.
	_city.los_ok = false
	_city.prey_at = Vector3.INF
	_city.prey_b = Vector3.INF
	var registry := _city.beacon_registry()
	var beacon := registry.register(
		stone, STONE_HOLD_M, int(MonsterFaction.Id.SIEGE_ATTACKER)
	)
	NavAgent.reset_events()

	var frames := await _run_far(
		unit, func() -> bool: return _flat(unit.global_position, stone) <= STONE_HOLD_M
	)
	if unit.nav_tier() != NavLod.Tier.FAR:
		_fail(
			"FAIL the body ran at tier %s, so this never tested the far path"
			% NavLod.tier_name(unit.nav_tier())
		)
		return
	var reach := _flat(unit.global_position, stone)
	if reach > STONE_HOLD_M:
		_fail(
			"FAIL a siege attacker sits %.1f m out after %d ticks, outside the %.1f m it has to be"
			% [reach, frames, STONE_HOLD_M]
			+ " within to hurt the stone (ladder %s)" % NavLadder.state_name(unit.nav_state())
		)
		return
	## Ambient wildlife must not see siege stones, or a Siege tile's stones would be chewed down by
	## whatever wandered past before the player ever staked a run.
	if registry.nearest_for(int(MonsterFaction.Id.UNDEAD), start) != null:
		_fail("FAIL an ordinary undead was handed a siege beacon")
		return
	print(
		"beacon: a blind siege attacker crossed %.1f m to a stone at far tier in %d ticks"
		% [start.distance_to(stone), frames]
	)
	registry.unregister(beacon)
	_city.los_ok = true
	_despawn(unit)


## Arriving at a stone has to mean *inside* its damage radius, and staying there.
##
## The radius answers two questions with one number — "stop walking" and "you are hurting it" — so the
## provider walks bodies to a ring set inside it. But the goal's arrival slop was wider than that
## inset, so a body could satisfy the goal while still outside the radius: it stopped short, hurt
## nothing, was handed a fresh ring, drifted a little sideways, arrived again, and orbited the stone
## for the rest of the run. From the player's chair that is a mob that refuses to attack.
##
## The stone is the real one, plinth and needle both, because the reported symptom was bodies milling
## around an obelisk rather than closing on it — and whether a walker can reach the ring around this
## shape is a property of the shape.
func _test_stone_bound_body_settles_inside_the_damage_radius() -> void:
	var start := _w(OBELISK_CENTRE - Vector3i(30, 0, 0))
	var stone := _w(OBELISK_CENTRE)
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	unit.set_faction(int(MonsterFaction.Id.SIEGE_ATTACKER))
	_city.los_ok = false
	_city.prey_at = Vector3.INF
	_city.prey_b = Vector3.INF
	var registry := _city.beacon_registry()
	var beacon := registry.register(
		stone, STONE_HOLD_M, int(MonsterFaction.Id.SIEGE_ATTACKER)
	)

	var frames := await _run(
		unit, func() -> bool: return _flat(unit.global_position, stone) <= STONE_HOLD_M
	)
	var reach := _flat(unit.global_position, stone)
	if reach > STONE_HOLD_M:
		_fail(
			"FAIL the body stalled %.1f m out after %d ticks, outside the %.1f m damage radius"
			% [reach, frames, STONE_HOLD_M]
			+ " — it would circle the stone hurting nothing (ladder %s)"
			% NavLadder.state_name(unit.nav_state())
		)
		return
	## And it holds. Contact damage is applied per tick to bodies inside the radius, so a body that
	## dips in and wanders back out again is barely better than one that never arrived.
	var settled := unit.global_position
	await _tick(unit, 120)
	var after := _flat(unit.global_position, stone)
	if after > STONE_HOLD_M:
		_fail("FAIL the body drifted back out to %.1f m after arriving at %.1f m" % [after, reach])
		return
	var drift := _flat(unit.global_position, settled)
	if drift > 4.0:
		_fail("FAIL the body slid %.1f m around the stone instead of holding station" % drift)
		return
	print(
		"stone: settled %.1f m inside the %.1f m damage radius in %d ticks, held within %.1f m"
		% [reach, STONE_HOLD_M, frames, drift]
	)

	## And it fights what it arrived at. The stone's hit points are drained by proximity, so the swing
	## is the only thing a player can see — and with nothing living in range, a body facing the stone
	## can only have been turned there by striking at it.
	if unit.combat_prey() != Vector3.INF:
		_fail("FAIL something living got in the way, so this proves nothing about stones")
		return
	var want := atan2(stone.x - unit.global_position.x, stone.z - unit.global_position.z)
	## Turned away by hand first: walking in left it roughly facing the stone already, so without
	## this the check would pass on a body that does nothing at all.
	unit.rotation.y = wrapf(want + PI, -PI, PI)
	await _tick(unit, 160)
	var off := absf(wrapf(unit.rotation.y - want, -PI, PI))
	if off > deg_to_rad(30.0):
		_fail(
			"FAIL a body inside the damage radius never turned on the stone (%.0f° off) — it is"
			% rad_to_deg(off)
			+ " destroying it in total silence"
		)
		return
	print("stone: it turned back onto the stone and swung, %.0f° off centre" % rad_to_deg(off))
	registry.unregister(beacon)
	_city.los_ok = true
	_despawn(unit)


## Aggro in this mode is earned by shooting, and this is the half that was missing.
##
## A body walking to a stone is not asked for a new goal until it arrives, so a tower could shoot it
## the whole way in while `promote_attacker` recorded an attacker nothing ever read: towers fired,
## the horde filed past, and the player watched a fight that only went one way. Only forced
## retaliation may interrupt an errand — a body that acquired freely would stall on the first tower
## it passed, which is exactly what the unacquirable-defender rule exists to prevent.
func _test_shot_attacker_turns_on_the_tower() -> void:
	var start := _w(Vector3i(60, 1, 100))
	var stone := _w(Vector3i(150, 1, 100))
	## Behind the body and off the line, so closing on it means giving up ground it already walked.
	## A tower anywhere along the corridor would be reached by ignoring it and carrying on.
	var pad := _w(Vector3i(34, 1, 74))
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	unit.set_faction(int(MonsterFaction.Id.SIEGE_ATTACKER))
	var tower := _spawn(UndeadUnit.Role.MINION, pad)
	if tower == null:
		return
	tower.set_faction(int(MonsterFaction.Id.SIEGE_DEFENDER))
	## Nothing acquirable anywhere: whatever this body does next, it does because it was hit.
	_city.los_ok = false
	_city.prey_at = Vector3.INF
	_city.prey_b = Vector3.INF
	var registry := _city.beacon_registry()
	var beacon := registry.register(stone, 5.0, int(MonsterFaction.Id.SIEGE_ATTACKER))

	## Let it commit to the walk first — the bug lived in the retarget of an errand already
	## underway, not in the first goal pick.
	await _tick(unit, 20)
	var hit_at := unit.global_position
	var gained := start.distance_to(stone) - hit_at.distance_to(stone)
	if gained <= 1.0:
		_fail("FAIL the attacker never set off for its stone (%.1f m gained)" % gained)
		return

	## One tower hit, exactly as `MonsterCombat._hurt_monster` lands it.
	var lethal := unit.apply_damage_scaled(
		DamageSource.for_monster_attack_mob("blaster"), 0.05, "siege_tower", tower
	)
	if lethal:
		_fail("FAIL the test hit killed the attacker, so there was nothing left to retaliate")
		return
	var frames := await _run(unit, func() -> bool: return _aims_at(unit, pad))
	if not _aims_at(unit, pad):
		_fail(
			"FAIL a shot attacker never took the tower as its goal in %d ticks (goal %s)"
			% [frames, _goal_tag(unit)]
		)
		return
	## And it acts on the goal rather than merely holding it: the tower is back the way it came, so
	## closing on it means giving up ground it had already walked toward the stone.
	var was := hit_at.distance_to(pad)
	await _tick(unit, 80)
	var now := unit.global_position.distance_to(pad)
	if now >= was - 2.0:
		_fail("FAIL it aimed at the tower but closed nothing (%.1f m → %.1f m)" % [was, now])
		return
	print(
		"aggro: one tower hit turned a stone-bound attacker around in %d ticks (%.1f m → %.1f m)"
		% [frames, was, now]
	)
	registry.unregister(beacon)
	_city.los_ok = true
	_despawn(unit)
	_despawn(tower)


## Answering fire is not a privilege of bodies the player is standing next to.
##
## The far tier skips the crowd query to save it, and a wandering body has no errand whose retarget
## would notice the hit either — so this pins the guarantee rather than the route: a far body that is
## shot ends up coming for the shooter, here within a few seconds of sim. Towers fire at whatever
## enters range whether or not anybody is watching that flank, and a flank that cannot fight back is
## one the player holds with two towers and no attention.
func _test_far_attacker_turns_on_the_tower() -> void:
	var start := _w(Vector3i(60, 1, 30))
	var pad := _w(Vector3i(34, 1, 8))
	var unit := _spawn(UndeadUnit.Role.MINION, start)
	if unit == null:
		return
	unit.set_faction(int(MonsterFaction.Id.SIEGE_ATTACKER))
	var tower := _spawn(UndeadUnit.Role.MINION, pad)
	if tower == null:
		return
	tower.set_faction(int(MonsterFaction.Id.SIEGE_DEFENDER))
	## No beacon and nothing acquirable: left alone this body would only ever wander.
	_city.los_ok = false
	_city.prey_at = Vector3.INF
	_city.prey_b = Vector3.INF
	if not _city.beacon_registry().is_empty():
		_fail("FAIL a beacon leaked from an earlier case into the wander test")
		return

	var lethal := unit.apply_damage_scaled(
		DamageSource.for_monster_attack_mob("blaster"), 0.05, "siege_tower", tower
	)
	if lethal:
		_fail("FAIL the test hit killed the far attacker")
		return
	var frames := await _run_far(unit, func() -> bool: return _aims_at(unit, pad))
	if unit.nav_tier() != NavLod.Tier.FAR:
		_fail(
			"FAIL the body ran at tier %s, so this never tested the far path"
			% NavLod.tier_name(unit.nav_tier())
		)
		return
	if not _aims_at(unit, pad):
		_fail(
			"FAIL a shot far-tier attacker never took the tower as its goal in %d ticks (goal %s)"
			% [frames, _goal_tag(unit)]
		)
		return
	var was := start.distance_to(pad)
	var closed := await _run_far(
		unit, func() -> bool: return unit.global_position.distance_to(pad) <= was - 3.0
	)
	var now := unit.global_position.distance_to(pad)
	if now > was - 3.0:
		_fail(
			"FAIL the far body aimed at the tower but closed nothing in %d ticks (%.1f m → %.1f m)"
			% [closed, was, now]
		)
		return
	print(
		"aggro: a far-tier wanderer answered fire in %d ticks and closed %.1f m → %.1f m"
		% [frames, was, now]
	)
	_city.los_ok = true
	_despawn(unit)
	_despawn(tower)


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

## Bodies are pinned by name and by seed. Model choice is now content, and a nav test that
## rolled a different creature every run would be testing a different capsule every run.
func _spawn(spawn_role: UndeadUnit.Role, at: Vector3, body_id: String = "") -> UndeadUnit:
	_city.player_at = at + Vector3(0.0, 0.0, OBSERVER_OFFSET_M)
	var wanted := body_id
	if wanted.is_empty():
		wanted = DEFAULT_BODY[int(spawn_role)]
	var unit := _director._spawn_unit(spawn_role, at, BODY_SEED, wanted)
	if unit == null:
		_fail("FAIL the director refused to spawn a %d at %.1f,%.1f" % [spawn_role, at.x, at.z])
		return null
	## The test steps every body itself, on a fixed delta.
	unit.set_physics_process(false)
	## Rungs are watched, not sampled: a goal that fails and is replaced inside one tick would
	## never show up in `nav_state()`.
	unit.nav_agent().ladder_changed.connect(_note_rung)
	return unit


## Dropping a body straight out of the tree trips the roster's registered-on-exit alarm, so
## the roster loses it first — the same order a death goes in.
func _despawn(unit: UndeadUnit) -> void:
	_director.despawn_unit(unit)


func _note_rung(state: NavLadder.State) -> void:
	if _states.is_empty() or _states[_states.size() - 1] != int(state):
		_states.append(int(state))


## Tick until `done` or the frame cap. One real frame per tick, because NavService serves its
## query queue off SceneTree.process_frame.
func _run(unit: UndeadUnit, done: Callable) -> int:
	var frames := 0
	while frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
		_city.player_at = unit.global_position + Vector3(0.0, 0.0, OBSERVER_OFFSET_M)
		unit.tick(SIM_DT)
		if bool(done.call()):
			break
	return frames


## Like `_run`, but the observer stays parked well outside the mid band, so the body is navigated at
## the far tier — one coarse corridor, interpolated motion — for the whole case.
func _run_far(unit: UndeadUnit, done: Callable) -> int:
	_city.player_at = unit.global_position + Vector3(0.0, 0.0, NavLod.MID_RADIUS_M * 3.0)
	var frames := 0
	while frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
		unit.tick(SIM_DT)
		if bool(done.call()):
			break
	return frames


func _tick(unit: UndeadUnit, frames: int) -> void:
	for _frame in range(frames):
		await get_tree().process_frame
		_city.player_at = unit.global_position + Vector3(0.0, 0.0, OBSERVER_OFFSET_M)
		unit.tick(SIM_DT)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## An outer stone as the composer builds one. Two square plinth steps and a slender needle: a shape
## that hardly obstructs a walker, which is the whole point of standing one here.
func _stamp_obelisk(volume: NativeOfflineVoxelVolume) -> void:
	var c := OBELISK_CENTRE
	for step in range(2):
		var r := OBELISK_FOOTPRINT - step
		volume.fill_box(
			Vector3i(c.x - r, c.y + step, c.z - r),
			Vector3i(c.x + r, c.y + step, c.z + r),
			VoxelMaterial.STONE
		)
	var h := OBELISK_SHAFT_HALF
	volume.fill_box(
		Vector3i(c.x - h, c.y + 2, c.z - h),
		Vector3i(c.x + h, c.y + 1 + OBELISK_COURSES, c.z + h),
		VoxelMaterial.GLASS_LIT
	)


## Flat concrete deck, wide enough for a giant's eleven cells of clearance, with one sealed
## brick tower and one siege obelisk on it.
func _bake_tile() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	volume.fill_box(TOWER_MIN, TOWER_MAX, VoxelMaterial.BRICK)
	_stamp_obelisk(volume)
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	## Keep the deck's own lanes clear of it: the plinth reaches z 110..118, so every other case on
	## this tile runs at z <= 108.
	assert(OBELISK_CENTRE.z - OBELISK_FOOTPRINT > 108, "obelisk sits in another case's lane")
	var ok: bool = bake.bake_from_volume(
		volume,
		ORIGIN,
		SX,
		SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test tile")
		return null
	return bake


## A CityBrush over an offline volume: the dig-out has to go through the funnel, and this is
## the funnel with a volume behind it instead of a live terrain.
func _offline_brush() -> CityBrush:
	var brush := CityBrush.new()
	brush.use_offline_volume()
	return brush


## Ground distance. Every siege radius — hold, damage, withdrawal — is measured flat, because a body
## at the foot of an 11 m obelisk is at its base, not 11 m from it.
func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Tag of the goal the body is currently walking, or "-" when it is holding in place.
func _goal_tag(unit: UndeadUnit) -> String:
	var agent := unit.nav_agent()
	if agent == null:
		return "no-agent"
	var goal := agent.goal()
	if goal == null:
		return "-"
	return String(goal.tag)


## The claim these cases make: the body is going for `target`, not merely near it. Either it is
## walking a hunt corridor aimed there, or it is holding within strike reach of it.
func _aims_at(unit: UndeadUnit, target: Vector3) -> bool:
	var agent := unit.nav_agent()
	if agent == null:
		return false
	var goal := agent.goal()
	if goal == null:
		return unit.combat_prey().distance_to(target) <= 3.0
	if goal.tag != UndeadGoalProvider.TAG_HUNT:
		return false
	return goal.point.distance_to(target) <= 6.0


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _quit() -> void:
	if _director != null and is_instance_valid(_director):
		_director.clear_all()
	NavService.reset()
	if _city != null:
		## Never entered the tree, so nothing else will free it.
		_city.free()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
