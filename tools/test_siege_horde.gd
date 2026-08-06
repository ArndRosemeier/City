## Does a wave actually chew the stone it was sent at?
##
## Every other siege test answers a narrower question. `test_siege_faction` moves bodies by hand and
## asks the controller for arithmetic; `test_siege_district` reads the baked block map; `test_undead_nav`
## walks one body at one beacon on a flat deck. None of them puts a real horde on a real tile, which is
## the only place the mode either works or does not — and the player report this was written for was
## "the mobs circled the obelisk and attacked nothing".
##
## It is also the only harness with real terrain under a real tower pad, so the rule that a standing
## tower's voxels are immune to damage is checked here too (`_check_tower_voxels_are_warded`).
##
## So: boot the live city into a Siege tile, stake a run, aim a wave at one flank, and watch the flank.
## The claim is narrow and mechanical — an outer stone under a wave loses hit points — but everything
## the mode needs has to be true for it to hold: gates spawn on walkable ground, beacons are perceived,
## corridors reach the stand ring around a plinth, and bodies that arrive stay inside the damage radius.
##
## The player is parked well off the flank by default. Standing next to the stone makes *the player* the
## nearest hostile, and a horde correctly chasing the player is indistinguishable from a horde that
## cannot find the stone. `--watch-close` runs the other case on purpose — the player at the foot of the
## stone, which is where the report came from — and then asks the weaker question: does the horde engage
## *anything*, the stone or the player, rather than milling about between them.
##
## Run (-Command, not -File: the -File binder flattens a comma list into one argument):
##   powershell -Command "& '.\tools\run_test.ps1' -Scene test_siege_horde
##     -GodotArgs @('--spawn-theme=siege','--city-seed=42')"
##   ... add '--watch-close' for the player-at-the-stone case.
extends Node

const VOX := 0.5
## How far off the watched stone the player stands: outside every monster aggro range, inside
## `NavLod.MID_RADIUS_M` so the horde still walks real corridors rather than interpolated ones.
const WATCH_DIST_M := 45.0
## `--watch-close`: at the foot of the stone, inside every aggro range. The player is the prize here,
## and a body that reaches this far has reached its target.
const WATCH_CLOSE_M := 8.0
## Strike reach of a melee body, generously read. Closer than this to the player is a fight.
const MELEE_REACH_M := 3.0
## A body dropped at a base voxel is inside the ground, and CityRoot then reads the tile as
## underground. Only the streaming cares that the walker is here at all.
const ANCHOR_LIFT_M := 2.5
## How long the wave gets. The drip spawns over `wave_period_sec` and a body has ~60 m to walk from
## its mouth, so this is the walk plus a margin — not a number tuned until the test passed.
const WATCH_SEC := 100.0
const REPORT_EVERY_SEC := 10.0
## Index into `SiegeController.stones()`: 0 is the centre, so this is the first outer stone. Fixed
## rather than picked from the wave's own roll, because the player has to be standing there already.
const FLANK_STONE := 1

var _city: CityRoot = null
var _walker: Node3D = null
var _failed: bool = false
var _close: bool = false


func _ready() -> void:
	## Both lists: the harness passes tool flags through as user args, engine flags as its own.
	_close = (
		OS.get_cmdline_args().has("--watch-close")
		or OS.get_cmdline_user_args().has("--watch-close")
	)
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)
	_city = city

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			_fail("FAIL no walker after 120 s")
			_quit()
			return
		await get_tree().process_frame
	_walker = city.get_node_or_null("Walker") as Node3D
	_hide_overlays()

	var coord := city.spawn_district_coord
	var theme := DistrictTheme.for_district(city.city_seed, coord)
	if theme.id != DistrictTheme.SIEGE:
		_fail("FAIL spawn district is %s, expected Siege" % theme.display_name)
		_quit()
		return
	await _settle(10.0)

	## Walk out to the flank *before* anything is staked or held onto. Moving the walker re-streams the
	## tile, and a district reload replaces the generator and the controller — a probe that grabbed them
	## first spends the run reading a freed object.
	var stand_at := _flank_stand(city)
	if stand_at == Vector3.INF:
		_quit()
		return
	_walker.global_position = stand_at
	await _settle(12.0)

	var inst := _spawn_district(city)
	if inst == null:
		_fail("FAIL the spawn district never streamed in")
		_quit()
		return
	var layout: SiegeLayout = inst.generator.get_siege_layout()
	var ctrl := inst.siege_controller
	if layout == null or ctrl == null:
		_fail("FAIL the streamed Siege district has no layout or controller")
		_quit()
		return
	print(layout.describe())

	if not _stake(city, ctrl):
		_quit()
		return
	_check_tower_voxels_are_warded(city, ctrl)
	if _failed:
		_quit()
		return
	## The wave is aimed by hand at the flank the walker went to. Left to its own roll it would press a
	## random flank, which is right for play and useless for watching one — and the walker cannot be
	## moved to meet it afterwards without re-streaming the tile.
	_aim_wave_at_flank(ctrl)
	## Straight to the wave rather than waiting out the deploy window: what is under test is what a
	## wave does, and the clock that releases it is `test_siege_faction`'s business.
	ctrl._begin_wave()
	var stone: SiegeController.StoneState = ctrl.stones()[FLANK_STONE]
	print(
		"wave %d aimed at %s (%s), player standing %.0f m off it"
		% [
			ctrl.wave_number(),
			stone.label,
			ctrl.gate_bearing_label(ctrl._primary_gate),
			Vector2(
				_walker.global_position.x - stone.pos.x, _walker.global_position.z - stone.pos.z
			).length(),
		]
	)

	await _watch(ctrl, stone)
	_quit()


## A tower is a health pool with a bar over it, and its stamp is the only part of it the player's own
## weapons can reach at all. If a blast carves that stamp, the pool goes on standing and firing from
## inside a hole — so a living tower holds its cells (`VoxelWard`) and gives them back when it dies.
##
## Both halves are checked here rather than in `test_siege_towers` because this is the only harness with
## real terrain under a real pad: the fixture there has no live brush to stamp into.
func _check_tower_voxels_are_warded(city: CityRoot, ctrl: SiegeController) -> void:
	var pad := _pad_near(ctrl, ctrl.stones()[FLANK_STONE].pos)
	if pad < 0:
		_fail("FAIL the tile planned no tower pads")
		return
	if not ctrl.build_tower(pad, "splinter_post"):
		_fail("FAIL the pot would not buy a Splinter Post on pad %d" % pad)
		return
	var tower: UndeadUnit = ctrl._pad_tower[pad] as UndeadUnit
	var terrain := city.voxel_terrain()
	var brush := city.voxel_brush()
	var pad_world := ctrl._pad_world_pos(pad)
	var local := terrain.to_local(pad_world)
	## The stamp always paints its own axis, one cell above the pad plate.
	var cell := Vector3i(int(floor(local.x)), int(floor(local.y)) + 1, int(floor(local.z)))
	var mat := brush.get_vox(cell)
	var ward := city.voxel_ward()
	if mat == VoxelMaterial.AIR:
		_fail("FAIL the stamp left %v empty, so there is nothing to ward" % cell)
		return
	if not ward.holds(cell):
		_fail("FAIL a fresh tower does not hold %v, the cell it just painted" % cell)
		return
	if city._carve_verdict(mat, cell) != CityRoot.CarveVerdict.IMMUNE:
		_fail("FAIL the player's carve verdict on a warded cell is not immune")
		return
	## The real path, not just the verdict: a charged blast right on the pillar.
	city.apply_charged_blast(
		terrain.to_global(Vector3(cell) + Vector3(0.5, 0.5, 0.5)), 2.0
	)
	if brush.get_vox(cell) != mat:
		_fail(
			"FAIL a blast took material %d off a standing tower at %v"
			% [mat, cell]
		)
		return
	## Killed the way a wave kills it. The cells go back to being ordinary stone: the stump a dead
	## tower leaves has to be clearable like anything else.
	var swings := 0
	while tower.is_alive() and swings < 400:
		tower.apply_damage_scaled(DamageSource.Id.MONSTER_MELEE_MOB, 1.0, "probe", null)
		swings += 1
	if tower.is_alive():
		_fail("FAIL %d mob swings did not fell a Splinter Post" % swings)
		return
	if ward.holds(cell):
		_fail("FAIL a dead tower still holds %v" % cell)
		return
	if city._carve_verdict(mat, cell) == CityRoot.CarveVerdict.IMMUNE:
		_fail("FAIL the stump of a dead tower is still immune to the player")
		return
	print(
		"ward: a Splinter Post on pad %d shrugged off a charged blast, and gave its cells back"
		% pad
		+ " when %d mob swings felled it" % swings
	)


## Pad index closest to `aim` on the flat, or -1 when the tile planned none.
func _pad_near(ctrl: SiegeController, aim: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in range(ctrl.layout.pad_count()):
		var p := ctrl._pad_world_pos(i)
		var d := Vector2(p.x - aim.x, p.z - aim.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Where the player stands, read from the layout before the tile is re-streamed. Same stone the wave
## is aimed at, on the line back toward the objective — where a defender would be.
func _flank_stand(city: CityRoot) -> Vector3:
	var inst := _spawn_district(city)
	if inst == null or inst.generator == null:
		_fail("FAIL the spawn district never streamed in")
		return Vector3.INF
	var ctrl := inst.siege_controller
	if ctrl == null:
		_fail("FAIL the streamed Siege district stood up no controller")
		return Vector3.INF
	var stone: SiegeController.StoneState = ctrl.stones()[FLANK_STONE]
	var inward := ctrl.lodestone_world_pos() - stone.pos
	inward.y = 0.0
	var stand := WATCH_CLOSE_M if _close else WATCH_DIST_M
	return stone.pos + inward.normalized() * stand + Vector3(0.0, ANCHOR_LIFT_M, 0.0)


## Force the wave's mouth table onto the two gates flanking the watched stone. Gates are planned two to
## a stone in order, so those are gates 0 and 1.
func _aim_wave_at_flank(ctrl: SiegeController) -> void:
	var weights := PackedFloat32Array()
	weights.resize(ctrl.layout.hell_gate_count())
	weights.fill(0.0)
	var pair := (FLANK_STONE - 1) * 2
	weights[pair] = 1.0
	weights[pair + 1] = 1.0
	ctrl._next_gate_weights = weights
	ctrl._next_primary_gate = pair


## Steps the run and reports what the flank is doing every few seconds. The verdict is the stone's
## hit points; the rest of the row is there so a failure says *why* rather than only "no damage".
func _watch(ctrl: SiegeController, stone: SiegeController.StoneState) -> void:
	var hp_at_start := stone.hp
	var closest := INF
	var closest_to_player := INF
	var next_report := 0.0
	var elapsed := 0.0
	while elapsed < WATCH_SEC:
		await get_tree().process_frame
		if not is_instance_valid(ctrl):
			_fail("FAIL the district streamed out from under the probe, so it watched nothing")
			return
		elapsed += get_process_delta_time()
		closest = minf(closest, _closest_m(ctrl, stone.pos))
		closest_to_player = minf(closest_to_player, _closest_m(ctrl, _walker.global_position))
		if elapsed < next_report:
			continue
		next_report = elapsed + REPORT_EVERY_SEC
		print(
			"  t=%5.1f  %s %6.1f/%.0f hp   alive %2d   chewing %d   stone %5.1f m   player %5.1f m"
			% [
				elapsed,
				stone.label,
				stone.hp,
				stone.hp_max,
				ctrl.alive_count(),
				ctrl._chewers_within(stone.pos, stone.vuln_radius_m),
				_closest_m(ctrl, stone.pos),
				_closest_m(ctrl, _walker.global_position),
			]
			+ "   %s   prey %s" % [_goal_census(ctrl), _prey_census(ctrl)]
		)
		if not stone.alive:
			break

	var lost := hp_at_start - stone.hp
	print(
		"flank: %s lost %.0f hp; closest approach %.1f m to the stone (radius %.1f m),"
		% [stone.label, lost, closest, stone.vuln_radius_m]
		+ " %.1f m to the player" % closest_to_player
	)
	if lost > 0.0:
		return
	## Nothing touched the stone. With the player parked on the flank that is allowed — but only if the
	## horde went for the player instead. Neither is the reported bug: bodies between the two, engaging
	## nothing.
	if _close and closest_to_player <= MELEE_REACH_M:
		print("flank: the wave went for the player rather than the stone, which is a fight either way")
		return
	_fail(
		"FAIL %s took no damage in %.0f s under a wave aimed at it, and nothing reached the player"
		% [stone.label, WATCH_SEC]
		+ " either (stone %.1f m, player %.1f m). This is the horde engaging nothing."
		% [closest, closest_to_player]
	)


func _closest_m(ctrl: SiegeController, aim: Vector3) -> float:
	var best := INF
	for unit: UndeadUnit in ctrl._alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var d := Vector2(
			unit.global_position.x - aim.x, unit.global_position.z - aim.z
		).length()
		best = minf(best, d)
	return best


## How many living bodies have taken something as prey. A horde with a prey each is fighting; one with
## none is walking an errand, and the two look very different from the player's chair.
func _prey_census(ctrl: SiegeController) -> String:
	var hunting := 0
	var idle := 0
	for unit: UndeadUnit in ctrl._alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if unit.combat_prey() == Vector3.INF:
			idle += 1
		else:
			hunting += 1
	return "%d hunting / %d none" % [hunting, idle]


## What the living horde is doing, by goal tag. A wave that is all `wander` is lost; one that is all
## `push` is walking at something.
func _goal_census(ctrl: SiegeController) -> String:
	var tally: Dictionary = {}
	for unit: UndeadUnit in ctrl._alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var tag := _goal_tag(unit)
		tally[tag] = int(tally.get(tag, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for tag: Variant in tally.keys():
		parts.append("%s×%d" % [str(tag), int(tally[tag])])
	parts.sort()
	return " ".join(parts)


func _goal_tag(unit: UndeadUnit) -> String:
	var agent := unit.nav_agent()
	if agent == null:
		return "no-agent"
	var goal := agent.goal()
	if goal == null:
		return "hold"
	return String(goal.tag)


func _stake(city: CityRoot, ctrl: SiegeController) -> bool:
	var inv := city.get_inventory()
	if inv == null:
		_fail("FAIL no player inventory to stake from")
		return false
	var n := ctrl.min_stake_total()
	inv.add("gem_quartz", n)
	if not ctrl.start_run({"gem_quartz": n}):
		_fail("FAIL the run would not start on a %d gem stake" % n)
		return false
	return true


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


func _hide_overlays() -> void:
	for child: Node in _city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var errors := get_node_or_null("/root/ErrorOverlay")
	if errors is CanvasLayer:
		(errors as CanvasLayer).visible = false


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	print(message)


func _quit() -> void:
	print("RESULT: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)
