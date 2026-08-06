## Bake a Castle-theme district and assert the fortress is walkable: a walled keep on a
## plinth, a courtyard a pedestrian can reach from the street, a keep whose every room on
## every storey a pedestrian can reach from the keep's own door, a way up to the crown, and a
## multi-level dungeon under it whose every chamber a pedestrian can reach from every route
## down — from the public street, in one walk.
##
## The headline assertions are those routes. Everything else here — the vertical budget, the
## gate opening, the one-voxel causeway steps and stair risers, the measured doorway widths
## and ceiling headrooms — exists because a route is the first thing any of them breaks, and
## a measurement says which one broke where a failed path only says "unreachable".
##
## The last check is different in kind: twenty seeds are planned and their dungeons tabulated,
## because "the dungeons feel distinct" is a requirement no single-seed assertion can express.
## The full voxel/nav walk itself also picks a fresh castle seed each run (override with
## CITY_CASTLE_SEED), and every distinctness seed gets the cheap dungeon-tree walk so a sealed
## vault cannot hide behind seed 42.
##
## Run: powershell -File tools\run_test.ps1 test_castle_district
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const CastleComposerScript := preload("res://scripts/city/castle_composer.gd")
const CastleDoorPlacerScript := preload("res://scripts/city/castle_door_placer.gd")
const DoorBarrierScript := preload("res://scripts/city/door_barrier.gd")

const VOXEL_SIZE := 0.5
const BLOCK := 16
## Rings searched for a Castle tile. CASTLE is a ring 2+ theme, so this is generous.
const MAX_RING := 8
## Deepest a probe scans for the top solid voxel of a column. Above every merlon.
const PROBE_Y_MAX := 90
## Pedestrian and undead both need one cell of clearance and four of height, so three clear
## voxels across and four up is the floor for anything an agent walks through.
const MIN_WALK_W := 3
const MIN_HEAD := 4
## Headroom probes stop here: an open-air column would otherwise scan to PROBE_Y_MAX.
const MAX_HEAD := 16
const NO_SURFACE := -1
## How far off a flight's last tread the next one is looked for. Wider than a pedestrian's
## 1.25 voxel step on purpose: a two-voxel riser must be reported as a two-voxel riser.
const STEP_REACH := 4
## Cell states of the expected-state grid `_check_dungeon_plan` builds out of the plan.
## EITHER is for the stepped doorway arches, whose shoulders are masonry by design.
const WANT_SOLID := 0
const WANT_AIR := 1
const WANT_EITHER := 2
## Expansions this test's queries are allowed. `NavService.DEFAULT_BUDGET` is sized for a
## frame's worth of agent queries and is nowhere near enough here, because what makes these
## routes expensive is not their length but their shape: the goal is often straight up through
## a slab, so the heuristic pulls the search into the whole open volume below it before it finds
## the one flight that gets there. Exhausting the budget yields the best node reached, which
## reads as an unreachable goal — the opposite of what is being measured. An agent actually
## crossing a fortress would path to the next stair head rather than to a cellar three floors
## down, so this ceiling says nothing about what the game affords per frame.
##
## The gardens push it up: railings, seats and urns each stand a fresh walkable span on the
## meadow and on the bailey flags, and a search aimed at a cellar drags all of them in before
## it finds its stair.
const ROUTE_BUDGET := 700000
## Seeds the distinctness measurement bakes, and how far it looks for that many castles. Well
## past the handful needed to prove the dungeons differ, because the interesting failure is the
## rare seed whose lane claims leave the plan no room, and that only shows up in numbers.
const DISTINCT_SEEDS := 20
const DISTINCT_SEED_MAX := 80
## Slack allowed when a measured mesh corner is compared against the opening it must lie in,
## in voxels. Floating point only — the leaf is built to hairline tolerances on purpose, so
## anything larger than this would hide a leaf genuinely poking out of its own hole.
const FIT_EPS := 0.001

var _failed := false
var _volume: NativeOfflineVoxelVolume = null
## Wet / dry: whether a ditch of that kind has already been dug through voxel by voxel.
var _moat_checked: Dictionary[bool, bool] = {}
var _garden_props := 0
## Picked once per run so the full voxel/nav walk is not forever seed 42. Printed first so a
## failure is reproducible: re-run with `CITY_CASTLE_SEED=<n>` to pin it.
var _world_seed: int = 0


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	_world_seed = _pick_world_seed()
	var coord := DistrictTheme.find_coord_for_theme(_world_seed, DistrictTheme.CASTLE, MAX_RING)
	if DistrictTheme.for_district(_world_seed, coord).id != DistrictTheme.CASTLE:
		_fail("FAIL no Castle theme in ring 0..%d for seed %d" % [MAX_RING, _world_seed])
		_quit()
		return
	print("baking Castle district seed=%d at %s" % [_world_seed, coord])

	var planner := _check_layout(coord)
	if _failed:
		_quit()
		return

	var nav := NavService.instance()
	nav.ensure_configured(VOXEL_SIZE)
	if not nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return

	var t0 := Time.get_ticks_msec()
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": _world_seed,
		"bake_nav": true,
		"nav_solidity": nav.solidity_tables(),
		"nav_link_params": nav.link_params(),
	})
	var bake_ms := Time.get_ticks_msec() - t0
	if not bool(res.get("ok", false)):
		_fail("FAIL bake: %s" % res.get("error", "?"))
		_quit()
		return
	if int(res["theme_id"]) != DistrictTheme.CASTLE:
		_fail("FAIL baked theme is %s not Castle" % res["theme_name"])
		_quit()
		return

	var gen: DistrictGenerator = res["generator"]
	var layout := gen.get_castle_layout()
	if layout == null:
		_fail("FAIL the bake produced no castle layout")
		_quit()
		return
	_volume = gen.get_offline_volume() as NativeOfflineVoxelVolume
	if _volume == null:
		_fail("FAIL the bake kept no voxel volume to probe")
		_quit()
		return
	print("bake %d ms, %s" % [bake_ms, layout.describe()])

	_check_masonry(res)
	_check_tower_masonry(layout)
	_check_approach(layout, int(res["ground_thickness"]))
	_check_vertical_budget(layout, int(res["ground_thickness"]))
	_check_gate(layout)
	_check_causeway(layout)
	_check_spawn_at_gate(gen, layout)
	_check_gardens("seed %d" % _world_seed, res, layout)
	_check_keep_shell(layout)
	_check_keep_tree("seed %d" % _world_seed, layout)
	_check_stair_treads(layout)
	_check_openings(layout)
	_check_rooms(layout)
	_check_dungeon_entries(layout)
	_check_dungeon_plan(layout)
	_check_dungeon_rooms(layout)
	_check_dungeon_openings(layout)
	_check_dungeon_stairs(layout)
	_check_dungeon_tall(layout)
	_check_dungeon_tree("seed %d" % _world_seed, layout)
	_check_dungeon_summoners(layout)
	_check_doors(layout)
	_check_castle_doors_not_hung(layout, res)
	if _failed:
		_quit()
		return

	_report_nav_stats(res)
	_check_path_to_courtyard(nav, coord, res, layout)
	_check_flights_walkable(nav, res, layout)
	_check_path_into_keep(nav, res, layout)
	_check_path_to_crown(nav, res, layout)
	_check_every_room_reachable(nav, res, layout)
	_check_dungeon_descents(nav, res, layout)
	_check_dungeon_reachable(nav, res, layout)
	_check_path_to_deepest(nav, res, layout)
	if _failed:
		_quit()
		return
	if not nav.unregister_district(coord):
		_fail("FAIL could not unregister the castle district")
		_quit()
		return

	_check_determinism(coord, planner, layout)
	if _failed:
		_quit()
		return
	_check_distinctness()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Planner
# ---------------------------------------------------------------------------

## Castle tiles are street connectors, not neighbourhoods: edge stubs, no interior grid and
## no housing anywhere.
func _check_layout(coord: Vector2i) -> DistrictPlanner:
	var dseed := DistrictCoord.district_seed(_world_seed, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.CASTLE)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	var lots := 0
	var castles := 0
	var roads := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.CASTLE:
				castles += 1
			elif LandUse.is_road(tag):
				roads += 1
	var mid_roads := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z in range(z0, z1):
		for x in range(x0, x1):
			if LandUse.is_road(planner.tag_at(x, z)):
				mid_roads += 1
	print(
		"layout lots=%d castle_cells=%d roads=%d mid_roads=%d castle_rect=%s"
		% [lots, castles, roads, mid_roads, planner.large_castle]
	)
	if planner.large_castle.size.x <= 0:
		_fail("FAIL planner produced no large_castle")
		return planner
	if lots > 0:
		_fail("FAIL Castle layout still has %d lots" % lots)
		return planner
	if castles < 100:
		_fail("FAIL Castle layout only has %d castle cells" % castles)
		return planner
	if roads < 8:
		_fail("FAIL Castle layout has too few road cells (%d) — edge connectors missing?" % roads)
		return planner
	if mid_roads > 0:
		_fail("FAIL Castle middle has %d road cells — expected edge stubs only" % mid_roads)
	return planner


# ---------------------------------------------------------------------------
# Voxels
# ---------------------------------------------------------------------------

## The castle's masonry, either fresh or weathered. Moss creeps over courtyard flags, wall
## feet and batter risers wherever the noise says so, so any column of this fortress may come
## back as the mossy id — an assertion that names only the fresh one fails on the seeds where
## the dressing happened to land on the column it sampled.
func _is_castle_stone(id: int) -> bool:
	return id == VoxelMaterial.CASTLE_BLOCK or id == VoxelMaterial.CASTLE_BLOCK_MOSSY


func _check_masonry(res: Dictionary) -> void:
	var counts := _count_above_deck(res["blocks"], int(res["ground_thickness"]))
	var ashlar := int(counts.get(VoxelMaterial.CASTLE_BLOCK, 0))
	var mossy := int(counts.get(VoxelMaterial.CASTLE_BLOCK_MOSSY, 0))
	print("voxels above the deck: ashlar=%d mossy=%d" % [ashlar, mossy])
	## A 120-voxel plinth 18 voxels tall is a quarter of a million on its own, so anything
	## in the thousands means the composer bailed out part way through.
	if ashlar < 100_000:
		_fail("FAIL only %d castle block voxels above the deck" % ashlar)
	if mossy <= 0:
		_fail("FAIL no weathered courses — the masonry has no age to it")


## A tower shaft is castle block and nothing else. The pale vertical banding on the right
## gate turret in the Phase 1 approach shot turned out to be sunlit ashlar against
## sky-lit ashlar, but a foreign material bleeding into a tower would look the same from a
## distance, so the shafts are now sampled rather than eyeballed.
func _check_tower_masonry(layout: CastleLayout) -> void:
	var foreign := 0
	var sampled := 0
	var worst := VoxelMaterial.AIR
	for t: CastleTower in layout.towers:
		for dz in range(-t.radius, t.radius + 1):
			for dx in range(-t.radius, t.radius + 1):
				if maxi(absi(dx), absi(dz)) != t.radius - 1:
					continue
				var col := t.center + Vector2i(dx, dz)
				for y in range(layout.courtyard_y + 2, t.top_y + 1):
					var m := _vox(col.x, y, col.y)
					if m == VoxelMaterial.AIR:
						continue
					sampled += 1
					if not _is_castle_stone(m):
						foreign += 1
						worst = m
	print("tower shafts: %d voxels sampled, %d not castle block" % [sampled, foreign])
	if sampled < 1000:
		_fail("FAIL only %d tower voxels sampled — the turrets are not there" % sampled)
		return
	if foreign > 0:
		_fail(
			(
				"FAIL %d tower voxels are material %d, not castle block — something is"
				+ " bleeding into tower generation"
			)
			% [foreign, worst]
		)


## The gravel track between the road stub and the foot of the causeway. The meadow is
## walkable either way, so this is about the castle reading as reached from a street rather
## than dropped into a field. It lives *on* the deck layer, which the above-deck histogram
## deliberately skips.
func _check_approach(layout: CastleLayout, ground_thickness: int) -> void:
	var foot: Vector2i = layout.causeway_line[0]
	if _vox(foot.x, ground_thickness, foot.y) != VoxelMaterial.GRAVEL:
		_fail("FAIL the foot of the causeway at %s is not paved" % foot)
		return
	var lo := Vector2i(
		mini(foot.x, layout.road_target.x), mini(foot.y, layout.road_target.y)
	)
	var hi := Vector2i(
		maxi(foot.x, layout.road_target.x), maxi(foot.y, layout.road_target.y)
	)
	var paved := 0
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if _vox(x, ground_thickness, z) == VoxelMaterial.GRAVEL:
				paved += 1
	var reach := (hi.x - lo.x) + (hi.y - lo.y)
	print(
		"approach: %d paved columns between the causeway foot %s and the road stub %s (%d apart)"
		% [paved, foot, layout.road_target, reach]
	)
	## One paved column per voxel of Manhattan reach is a floor, not a target: the track is
	## `causeway_hw * 2 + 1` wide, so a complete one is several times this.
	if paved < reach:
		_fail("FAIL only %d paved columns over a %d voxel approach" % [paved, reach])


## The vertical budget Phase 3 will carve the dungeon out of. The courtyard has to stand at
## exactly COURTYARD_Y with unbroken masonry all the way down to the deck, or the dungeon
## band is not where the constants say it is.
func _check_vertical_budget(layout: CastleLayout, ground_thickness: int) -> void:
	if layout.courtyard_y != CastleComposerScript.COURTYARD_Y:
		_fail(
			"FAIL courtyard datum is Y=%d, the budget says Y=%d"
			% [layout.courtyard_y, CastleComposerScript.COURTYARD_Y]
		)
		return
	if layout.courtyard_y - ground_thickness != CastleComposerScript.PLINTH_RISE:
		_fail(
			"FAIL plinth rises %d voxels over the deck, the budget says %d"
			% [layout.courtyard_y - ground_thickness, CastleComposerScript.PLINTH_RISE]
		)
		return
	if layout.dungeon_y1 + CastleComposerScript.COURTYARD_SLAB_H + 1 != layout.courtyard_y:
		_fail(
			"FAIL dungeon band ends at Y=%d, leaving no %d voxel slab under Y=%d"
			% [layout.dungeon_y1, CastleComposerScript.COURTYARD_SLAB_H, layout.courtyard_y]
		)
		return
	var at := layout.courtyard_center
	if not _is_castle_stone(_vox(at.x, layout.courtyard_y, at.y)):
		_fail(
			"FAIL the middle of the bailey is %d at Y=%d, not castle block"
			% [_vox(at.x, layout.courtyard_y, at.y), layout.courtyard_y]
		)
		return
	if _vox(at.x, layout.courtyard_y + 1, at.y) != VoxelMaterial.AIR:
		_fail("FAIL the bailey is roofed over at Y=%d" % (layout.courtyard_y + 1))
		return
	## Phase 3 inverted the old assertion here. The plinth is no longer solid all the way down —
	## the dungeon is inside it — so what has to hold is that the band stayed inside its own
	## budget: an unbroken slab over it and untouched bedrock under it.
	var holes := PackedInt32Array()
	for y in range(layout.dungeon_y1 + 1, layout.courtyard_y + 1):
		if _vox(at.x, y, at.y) == VoxelMaterial.AIR:
			holes.append(y)
	if not holes.is_empty():
		_fail(
			"FAIL %d of the %d slab voxels between the dungeon and the bailey at %s are air"
			% [holes.size(), layout.courtyard_y - layout.dungeon_y1, at]
			+ " (Y=%s of the band Y%d..%d)"
			% [holes, layout.dungeon_y1 + 1, layout.courtyard_y]
		)
		return
	for y2 in range(0, layout.dungeon_y0):
		if _vox(at.x, y2, at.y) == VoxelMaterial.AIR:
			_fail("FAIL the bedrock under the dungeon at Y=%d is air" % y2)
			return
	print(
		(
			"budget: courtyard Y=%d on a %d voxel plinth, dungeon band Y%d..%d carved,"
			+ " %d voxel slab between them"
		)
		% [
			layout.courtyard_y,
			layout.courtyard_y - ground_thickness,
			layout.dungeon_y0,
			layout.dungeon_y1,
			layout.courtyard_y - layout.dungeon_y1,
		]
	)


## The gate has to be a hole a person walks through, measured off the voxels rather than
## trusted from the plan.
func _check_gate(layout: CastleLayout) -> void:
	var side := Vector2i(-layout.gate_dir.y, layout.gate_dir.x)
	var threshold := layout.courtyard_y + 1
	var width := 1
	for dir: int in [-1, 1]:
		var t := 1
		while t < 32:
			var p := layout.gate_center + side * (t * dir)
			if _vox(p.x, threshold, p.y) != VoxelMaterial.AIR:
				break
			width += 1
			t += 1
	var height := 0
	while height < 32:
		var y := threshold + height
		if _vox(layout.gate_center.x, y, layout.gate_center.y) != VoxelMaterial.AIR:
			break
		height += 1
	print("gate: %d voxels wide, %d voxels of headroom at the threshold" % [width, height])
	if width < CastleComposerScript.GATE_W_MIN:
		_fail("FAIL the gate opening is %d voxels wide, the minimum is %d"
			% [width, CastleComposerScript.GATE_W_MIN])
		return
	if width != layout.gate_width:
		_fail("FAIL the gate measures %d voxels but the plan says %d" % [width, layout.gate_width])
		return
	if height < CastleComposerScript.GATE_H_MIN:
		_fail("FAIL the gate is %d voxels tall, the minimum is %d"
			% [height, CastleComposerScript.GATE_H_MIN])
		return
	## Both ends of the passage must be open, or the "gate" is a niche in the gatehouse.
	var inside := layout.gate_center - layout.gate_dir * (layout.wall_thick + 2)
	if _vox(inside.x, threshold, inside.y) != VoxelMaterial.AIR:
		_fail("FAIL the gate passage does not break through into the bailey")


## Every riser on the approach is one voxel. A two-voxel step bakes as a one-way drop link
## and a pedestrian who walks down it can never come back up.
func _check_causeway(layout: CastleLayout) -> void:
	if layout.causeway_line.size() != layout.causeway_run + 1:
		_fail(
			"FAIL causeway has %d stations for a run of %d"
			% [layout.causeway_line.size(), layout.causeway_run]
		)
		return
	if layout.causeway_hw * 2 + 1 < 5:
		_fail("FAIL causeway deck is only %d voxels wide" % (layout.causeway_hw * 2 + 1))
		return
	var worst := 0
	var worst_at := 0
	var prev := _surface_y(layout.causeway_line[0])
	var climb := 0
	for i in range(1, layout.causeway_line.size()):
		var here := _surface_y(layout.causeway_line[i])
		var step := absi(here - prev)
		if step > worst:
			worst = step
			worst_at = i
		climb += here - prev
		prev = here
	print(
		"causeway: %d stations, %d voxels of climb, worst step %d voxel at station %d"
		% [layout.causeway_line.size(), climb, worst, worst_at]
	)
	if worst > 1:
		_fail(
			"FAIL the causeway has a %d voxel riser at station %d — pedestrians cannot climb it"
			% [worst, worst_at]
		)
		return
	if climb != CastleComposerScript.PLINTH_RISE:
		_fail(
			"FAIL the causeway climbs %d voxels, the plinth is %d tall"
			% [climb, CastleComposerScript.PLINTH_RISE]
		)


## Spawn stands at the foot of the causeway stairs, facing up toward the gate.
func _check_spawn_at_gate(gen: DistrictGenerator, layout: CastleLayout) -> void:
	var spawn := gen.find_spawn_world(null)
	if not is_finite(spawn.x):
		_fail("FAIL castle gate spawn not found")
		return
	if not is_finite(float(gen.last_spawn_yaw)):
		_fail("FAIL castle spawn yaw missing (should face the gate)")
		return
	var lx := int(floor(spawn.x / VOXEL_SIZE)) - gen.origin_vox.x
	var lz := int(floor(spawn.z / VOXEL_SIZE)) - gen.origin_vox.z
	var to_gate := Vector2(
		float(layout.gate_center.x) - float(lx),
		float(layout.gate_center.y) - float(lz)
	)
	var reach := to_gate.length()
	var outward := Vector2(float(layout.gate_dir.x), float(layout.gate_dir.y))
	if to_gate.dot(outward) > -0.5:
		_fail(
			"FAIL castle spawn at (%d,%d) is not outside the gate (gate_dir=%s)"
			% [lx, lz, layout.gate_dir]
		)
		return
	## Foot of the ramp is about `causeway_run` out; allow a little road-side slack.
	var max_reach := float(layout.causeway_run + 16)
	if layout.causeway_line.is_empty():
		max_reach = 40.0
	if reach > max_reach:
		_fail(
			"FAIL castle spawn at (%d,%d) is %.0f voxels from the gate — past the approach"
			% [lx, lz, reach]
		)
		return
	if not layout.causeway_line.is_empty():
		var foot: Vector2i = layout.causeway_line[0]
		var from_foot := Vector2(float(lx - foot.x), float(lz - foot.y)).length()
		if from_foot > 12.0:
			_fail(
				"FAIL castle spawn at (%d,%d) is %.0f voxels from causeway foot %s"
				% [lx, lz, from_foot, foot]
			)
			return
	print(
		"spawn=(%.1f, %.1f, %.1f) yaw=%.2f at (%d,%d) %.0f voxels from gate"
		% [spawn.x, spawn.y, spawn.z, float(gen.last_spawn_yaw), lx, lz, reach]
	)


# ---------------------------------------------------------------------------
# Keep interior — Phase 2
# ---------------------------------------------------------------------------

## The keep stands on the bailey, is roofed, and leaves the dungeon band untouched.
func _check_keep_shell(layout: CastleLayout) -> void:
	if layout.keep_floors.is_empty():
		_fail("FAIL the keep has no storeys")
		return
	if layout.keep_storeys() < CastleComposerScript.KEEP_STOREYS_MIN:
		_fail("FAIL the keep only has %d storeys" % layout.keep_storeys())
		return
	if layout.keep_hall_storey + 2 > layout.keep_top_storey():
		_fail(
			"FAIL the great hall on storey %d has no storey above it to occupy"
			% layout.keep_hall_storey
		)
		return
	var kr := layout.keep_rect
	if not layout.courtyard_rect.encloses(kr):
		_fail("FAIL the keep %s is not inside the bailey %s" % [kr, layout.courtyard_rect])
		return
	## Corner of the shell: solid from the courtyard to the roof, nothing carved below it.
	var corner := kr.position + Vector2i.ONE
	var hollow := 0
	for y in range(layout.courtyard_y + 1, layout.keep_roof_y + 1):
		if _vox(corner.x, y, corner.y) == VoxelMaterial.AIR:
			hollow += 1
	if hollow > 0:
		_fail("FAIL %d voxels of the keep's corner pier are air" % hollow)
		return
	## The keep's storey-0 floor *is* the courtyard slab, and the cellar route cuts a well
	## through it. Anywhere else it has to carry, or the keep's ground floor is a pit.
	var cellar := layout.dungeon_entry_of(CastleDungeonEntry.KIND_KEEP_CELLAR)
	var well := {}
	if cellar != null:
		for c in _stair_columns(cellar.stair):
			well[c] = true
	var pierced := 0
	var stray := 0
	var where: Array[String] = []
	## The floor course and the one bedding it. The slab is three courses, but a descent's
	## shaft is carved one voxel taller than a chamber on purpose (DUNGEON_SHAFT_HEAD) so a
	## body climbing out does not jam on the lid, and a flight arriving on the top dungeon
	## level takes that bite out of the slab's bottom course wherever it lands — under the
	## keep as readily as anywhere else in the bailey. That buried void is sealed and is the
	## dungeon's business; what would make the ground floor a pit is the floor itself going.
	for y2 in range(layout.courtyard_y - 1, layout.courtyard_y + 1):
		for z in range(kr.position.y, kr.end.y):
			for x in range(kr.position.x, kr.end.x):
				if _vox(x, y2, z) != VoxelMaterial.AIR:
					continue
				if well.has(Vector2i(x, z)):
					pierced += 1
					continue
				stray += 1
				## A count alone says nothing about which lane or shaft cut the hole.
				if where.size() < 6:
					where.append("(%d,%d,%d)" % [x, y2, z])
	if stray > 0:
		_fail(
			"FAIL %d air voxels are in the keep's ground floor slab outside the cellar well,"
			% stray
			+ " keep %s cellar=%s at %s" % [kr, "yes" if cellar != null else "none", " ".join(where)]
		)
		return
	if cellar != null and pierced == 0:
		_fail("FAIL the cellar well never broke through the keep's ground floor")
		return
	## Roof and ceiling: the topmost storey must be roofed over, not open to the sky.
	var f := layout.keep_floor(layout.keep_top_storey())
	var probe := _room_probe(f, f.rooms[0])
	if probe.x < 0:
		_fail("FAIL the top storey has no walkable floor to stand on")
		return
	if _vox(probe.x, layout.keep_roof_y, probe.y) != VoxelMaterial.CASTLE_BLOCK:
		_fail("FAIL the keep roof at Y=%d is not masonry" % layout.keep_roof_y)
		return
	print(
		"keep: %d storeys, hall on %d (%d voxels of air), roof Y=%d (%d over the bailey)"
		% [
			layout.keep_storeys(),
			layout.keep_hall_storey,
			layout.keep_floor(layout.keep_hall_storey).air_h,
			layout.keep_roof_y,
			layout.keep_roof_y - layout.courtyard_y,
		]
	)


## World seed for this run. `CITY_CASTLE_SEED` pins a failure; otherwise a fresh castle seed
## is drawn each time so a sealed vault cannot hide behind seed 42 forever.
func _pick_world_seed() -> int:
	var pinned := OS.get_environment("CITY_CASTLE_SEED").strip_edges()
	if not pinned.is_empty():
		var n := int(pinned)
		if n <= 0:
			_fail("FAIL CITY_CASTLE_SEED=%s is not a positive world seed" % pinned)
			return 42
		return n
	var candidates: Array[int] = []
	for s in range(1, DISTINCT_SEED_MAX + 1):
		var c := DistrictTheme.find_coord_for_theme(s, DistrictTheme.CASTLE, MAX_RING)
		if DistrictTheme.for_district(s, c).id == DistrictTheme.CASTLE:
			candidates.append(s)
	if candidates.is_empty():
		_fail(
			"FAIL no world seed in 1..%d puts a Castle in ring 0..%d"
			% [DISTINCT_SEED_MAX, MAX_RING]
		)
		return 42
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return candidates[rng.randi() % candidates.size()]


## The keep's circulation, counted off the plan alone.
##
## Cheap, and it holds for a castle nothing has walked through yet, which is what makes it the
## check the seed sweep can afford. One flight per pair of floored storeys plus the crown ramp,
## and at least a spanning tree of doorways per storey — the two things a lane claim competing
## for the keep plate takes away, and neither of them shows up in a layout summary.
func _check_keep_tree(what: String, layout: CastleLayout) -> void:
	var want := layout.keep_storeys() - 1
	if layout.keep_stairs.size() != want:
		_fail(
			"FAIL %s: %d keep flights for %d storeys, %d expected — a storey is cut off"
			% [what, layout.keep_stairs.size(), layout.keep_storeys(), want]
		)
		return
	for f: CastleFloor in layout.keep_floors:
		if not f.has_slab:
			continue
		var doors := layout.keep_doorways_on(f.storey).size()
		if doors < f.rooms.size() - 1:
			_fail(
				"FAIL %s: storey %d has %d rooms and only %d doorways — one is sealed"
				% [what, f.storey, f.rooms.size(), doors]
			)
			return


## The dungeon's circulation, counted off the plan alone — the cheap twin of
## `_check_dungeon_reachable`. Every surviving chamber must be reachable from every route
## down by walking tree/loop doors and inter-level flights. Catches a sealed vault before the
## nav bake spends a minute proving the same thing.
func _check_dungeon_tree(what: String, layout: CastleLayout) -> void:
	if layout.dungeon_entries.is_empty():
		_fail("FAIL %s: the dungeon has no route down" % what)
		return
	if layout.dungeon_vaults.is_empty():
		_fail("FAIL %s: the dungeon has no chambers" % what)
		return
	## Vault identity is the object itself — indices into `dungeon_vaults` stay stable for the
	## adjacency walk below.
	var vaults := layout.dungeon_vaults
	var adj: Array[PackedInt32Array] = []
	adj.resize(vaults.size())
	for i in range(vaults.size()):
		adj[i] = PackedInt32Array()
	for d: CastleDoorway in layout.dungeon_doorways:
		var a := _vault_index_covering(vaults, d.storey, d.center - d.axis)
		var b := _vault_index_covering(vaults, d.storey, d.center + d.axis * d.depth)
		if a < 0 or b < 0 or a == b:
			_fail(
				"FAIL %s: doorway %s does not join two chambers (a=%d b=%d)"
				% [what, d.describe(), a, b]
			)
			return
		adj[a].append(b)
		adj[b].append(a)
	for st: CastleStair in layout.dungeon_stairs:
		if st.from_storey < 0 or st.to_storey < 0:
			continue
		var lo := _vault_index_covering(vaults, st.from_storey, st.center_column(0))
		var hi := _vault_index_covering(
			vaults, st.to_storey, st.center_column(st.run_len() - 1)
		)
		if lo < 0 or hi < 0:
			_fail(
				"FAIL %s: %s lands outside any chamber (foot=%d head=%d)"
				% [what, st.describe(), lo, hi]
			)
			return
		adj[lo].append(hi)
		adj[hi].append(lo)
	for e: CastleDungeonEntry in layout.dungeon_entries:
		var start := _vault_index_covering(
			vaults, layout.dungeon_top_level(), e.foot()
		)
		if start < 0:
			_fail(
				"FAIL %s: %s foot %s sits in no top-level chamber"
				% [what, e.describe(), e.foot()]
			)
			return
		var seen: Array[bool] = []
		seen.resize(vaults.size())
		seen.fill(false)
		var queue: Array[int] = [start]
		seen[start] = true
		var qi := 0
		while qi < queue.size():
			var cur: int = queue[qi]
			qi += 1
			for nxt: int in adj[cur]:
				if seen[nxt]:
					continue
				seen[nxt] = true
				queue.append(nxt)
		for vi in range(vaults.size()):
			if seen[vi]:
				continue
			_fail(
				"FAIL %s: %s cannot reach %s on the plan (doors+flights)"
				% [what, e.kind_name(), (vaults[vi] as CastleVault).describe()]
			)
			return
	print(
		"dungeon tree: %s — %d chambers reachable from every one of %d routes on the plan"
		% [what, vaults.size(), layout.dungeon_entries.size()]
	)


func _vault_index_covering(vaults: Array[CastleVault], level: int, col: Vector2i) -> int:
	for i in range(vaults.size()):
		var v: CastleVault = vaults[i]
		if v.level != level:
			continue
		if v.rect.has_point(col) or v.rect.grow(1).has_point(col):
			return i
	return -1


## Every riser on every flight, measured off the voxels. One voxel is the whole rule: at
## two the walk edge is gone and the nav bake replaces it with a one-way drop link.
func _check_stair_treads(layout: CastleLayout) -> void:
	if layout.crown_stair == null:
		_fail("FAIL no ramp from the bailey to the curtain crown was planned")
		return
	var worst := 0
	var worst_on := ""
	var min_head := 99
	var min_lane := 99
	for st: CastleStair in layout.keep_stairs:
		print("  %s foot=%s head=%s" % [
			st.describe(), st.center_column(0) - st.dir, st.center_column(st.run_len() - 1)
		])
		min_lane = mini(min_lane, st.lane_w)
		## The lane is walled down both flanks, so a foot with masonry in front of it is a
		## flight that can only ever be walked down. The crown ramp leaves sideways onto
		## the rampart instead of forwards, because ahead of its landing is open bailey.
		var top := st.run_len() - 1
		var exit := (
			st.column(top, 0) - st.across
			if st.to_storey < 0
			else st.center_column(top) + st.dir
		)
		if not _stands_on(st.center_column(0) - st.dir, st.y_from):
			_fail("FAIL %s: nothing to step off at the foot" % st.describe())
			return
		if not _stands_on(exit, st.top_y()):
			_fail("FAIL %s: nothing to step onto at %s, Y=%d" % [st.describe(), exit, st.top_y()])
			return
		var m := _measure_flight(st)
		min_head = mini(min_head, m.y)
		if m.x > worst:
			worst = m.x
			worst_on = "%s station %d" % [st.describe(), m.z]
		if _failed:
			return
		if st.lane_w < MIN_WALK_W:
			_fail("FAIL %s is only %d voxels wide" % [st.describe(), st.lane_w])
			return
		if st.to_storey >= 0:
			_check_stair_opening(st)
			if _failed:
				return
	print(
		"stairs: %d flights, worst riser %d voxel, narrowest lane %d, least tread headroom %d"
		% [layout.keep_stairs.size(), worst, min_lane, min_head]
	)
	if worst > 1:
		_fail("FAIL a %d voxel riser at %s — pedestrians cannot climb it" % [worst, worst_on])
		return
	if min_head < MIN_HEAD:
		_fail("FAIL a tread has only %d voxels of headroom, the profile needs %d"
			% [min_head, MIN_HEAD])


## Doorway width and headroom, measured through the masonry rather than trusted.
func _check_openings(layout: CastleLayout) -> void:
	var min_w := 99
	var min_h := 99
	var narrowest: CastleDoorway = null
	var all: Array[CastleDoorway] = [layout.keep_entrance]
	all.append_array(layout.keep_doorways)
	for d: CastleDoorway in all:
		var mid := d.center + d.axis * (d.depth / 2)
		var side := d.side()
		var y := d.floor_y + 1
		if _vox(mid.x, y, mid.y) != VoxelMaterial.AIR:
			_fail("FAIL %s was never cut — its threshold is still solid" % d.describe())
			return
		var w := 1
		for sign: int in [-1, 1]:
			var t := 1
			while t < 32:
				var p := mid + side * (t * sign)
				if _vox(p.x, y, p.y) != VoxelMaterial.AIR:
					break
				w += 1
				t += 1
		var h := _headroom(mid, d.floor_y)
		if w < min_w:
			min_w = w
			narrowest = d
		min_h = mini(min_h, h)
	print(
		"openings: %d doorways, narrowest %d voxels (%s), least headroom %d"
		% [all.size(), min_w, narrowest.describe(), min_h]
	)
	if min_w < MIN_WALK_W:
		_fail(
			"FAIL %s is only %d voxels wide — nav has no clearance through it"
			% [narrowest.describe(), min_w]
		)
		return
	if min_h < MIN_HEAD:
		_fail("FAIL a doorway has only %d voxels of headroom, the profile needs %d"
			% [min_h, MIN_HEAD])


## The same measurement for the dungeon's grilles, which is where it matters most: the keep has
## a handful of doorways and the warren below has a hundred, every one of them an edge some
## chamber's only route runs through. Measured through the full depth of the wall and on both
## thresholds, because the plan graph counts a doorway as an edge the moment it is recorded —
## a grille the carve left half-cut, or one opening onto a column nothing can stand in, is a
## chamber that is connected on paper and sealed in the world.
func _check_dungeon_openings(layout: CastleLayout) -> void:
	if layout.dungeon_doorways.is_empty():
		return
	var min_w := 99
	var min_h := 99
	var narrowest: CastleDoorway = null
	for d: CastleDoorway in layout.dungeon_doorways:
		var y := d.floor_y + 1
		var side := d.side()
		for step in range(d.depth):
			var mid := d.center + d.axis * step
			if _vox(mid.x, y, mid.y) != VoxelMaterial.AIR:
				_fail(
					"FAIL %s is still solid %d voxels into the wall at %s"
					% [d.describe(), step, mid]
				)
				return
			var w := 1
			for dir: int in [-1, 1]:
				var t := 1
				while t < 32:
					if _vox((mid + side * (t * dir)).x, y, (mid + side * (t * dir)).y) \
							!= VoxelMaterial.AIR:
						break
					w += 1
					t += 1
			if w < min_w:
				min_w = w
				narrowest = d
			min_h = mini(min_h, _headroom(mid, d.floor_y))
		## Both sides of it, the columns the plan graph reads as the chambers it joins.
		for at: Vector2i in [d.center - d.axis, d.center + d.axis * d.depth]:
			if not _stands_on(at, d.floor_y):
				_fail(
					"FAIL %s opens onto %s, where a body cannot stand on Y=%d"
					% [d.describe(), at, d.floor_y]
				)
				return
	print(
		"dungeon openings: %d grilles, narrowest %d voxels (%s), least headroom %d"
		% [layout.dungeon_doorways.size(), min_w, narrowest.describe(), min_h]
	)
	if min_w < MIN_WALK_W:
		_fail(
			"FAIL %s is only %d voxels wide — nav has no clearance through it"
			% [narrowest.describe(), min_w]
		)
		return
	if min_h < MIN_HEAD:
		_fail(
			"FAIL a dungeon grille has only %d voxels of headroom, the profile needs %d"
			% [min_h, MIN_HEAD]
		)


## Every planned room is a real room: a floor to stand on, a ceiling far enough above it,
## and enough of both to be worth walking into.
func _check_rooms(layout: CastleLayout) -> void:
	var min_head := 99
	var min_span := 999
	var rooms := 0
	var hall_head := 0
	for f: CastleFloor in layout.keep_floors:
		if not f.has_slab:
			continue
		for i in range(f.rooms.size()):
			var r: Rect2i = f.rooms[i]
			rooms += 1
			min_span = mini(min_span, mini(r.size.x, r.size.y))
			var probe := _room_probe(f, r)
			if probe.x < 0:
				_fail(
					"FAIL storey %d room %s has no column a body can stand in"
					% [f.storey, r]
				)
				return
			var head := _headroom(probe, f.floor_y)
			if i == f.hall_index:
				hall_head = head
			min_head = mini(min_head, head)
	print(
		"rooms: %d over %d storeys, narrowest %d voxels, least ceiling %d, great hall %d"
		% [rooms, layout.keep_storeys(), min_span, min_head, hall_head]
	)
	if min_span < CastleComposerScript.KEEP_ROOM_MIN:
		_fail("FAIL a room is only %d voxels across" % min_span)
		return
	if min_head < MIN_HEAD:
		_fail("FAIL a room has only %d voxels of ceiling, the profile needs %d"
			% [min_head, MIN_HEAD])
		return
	if hall_head <= CastleComposerScript.KEEP_LEVEL_H - CastleComposerScript.KEEP_SLAB_T:
		_fail(
			"FAIL the great hall is only %d voxels tall — it is not double height"
			% hall_head
		)


# ---------------------------------------------------------------------------
# Dungeon — Phase 3
# ---------------------------------------------------------------------------

## Every air voxel in the dungeon band has to be one the plan asked for, and every chamber the
## plan asked for has to be air.
##
## Phases 1 and 2 asserted the band was air-free. The band is the dungeon now, so the same
## check runs against the plan instead of against zero — and that is the stronger statement,
## because it catches the three failures no route test can: a chamber that was never cut, a
## carve that ran outside its footprint, and a breach through the substructure's outer wall.
func _check_dungeon_plan(layout: CastleLayout) -> void:
	if layout.dungeon_levels != CastleComposerScript.DUNGEON_LEVELS:
		_fail(
			"FAIL the dungeon has %d levels, the budget is cut for %d"
			% [layout.dungeon_levels, CastleComposerScript.DUNGEON_LEVELS]
		)
		return
	if (
		layout.dungeon_y0 != CastleComposerScript.DUNGEON_Y0
		or layout.dungeon_y1 != CastleComposerScript.DUNGEON_Y1
	):
		_fail(
			"FAIL the dungeon band is Y%d..%d, the budget reserves Y%d..%d"
			% [
				layout.dungeon_y0,
				layout.dungeon_y1,
				CastleComposerScript.DUNGEON_Y0,
				CastleComposerScript.DUNGEON_Y1,
			]
		)
		return
	if layout.dungeon_vaults.is_empty():
		_fail("FAIL the dungeon has no chambers at all")
		return
	if not layout.plateau_rect.encloses(layout.dungeon_rect):
		_fail(
			"FAIL the dungeon %s reaches outside the plinth top %s"
			% [layout.dungeon_rect, layout.plateau_rect]
		)
		return

	var r := layout.dungeon_rect
	var y0 := layout.dungeon_y0
	var y1 := layout.dungeon_y1
	var want := PackedByteArray()
	want.resize(r.size.x * r.size.y * (y1 - y0 + 1))
	for v: CastleVault in layout.dungeon_vaults:
		for y in range(v.floor_y + 1, v.top_y() + 1):
			for z in range(v.rect.position.y, v.rect.end.y):
				for x in range(v.rect.position.x, v.rect.end.x):
					_want_set(want, r, y0, y1, x, y, z, WANT_AIR)
	for d: CastleDoorway in layout.dungeon_doorways:
		for c: Vector2i in d.columns():
			for y2 in range(d.floor_y + 1, d.floor_y + d.height + 1):
				_want_set(want, r, y0, y1, c.x, y2, c.y, WANT_EITHER)
	var flights := _dungeon_flights(layout)
	for st: CastleStair in flights:
		for t in range(st.run_len()):
			var s := st.surface_at(t)
			var thin := t >= st.rise + 1
			for k in range(st.lane_w):
				var p := st.column(t, k)
				## Rising treads are a solid wedge; arrival columns are a single surface course
				## over open shaft so the well lip is not coplanar with the last riser.
				if thin:
					for y3 in range(st.y_from + 1, s):
						_want_set(want, r, y0, y1, p.x, y3, p.y, WANT_AIR)
					_want_set(want, r, y0, y1, p.x, s, p.y, WANT_SOLID)
				else:
					for y3b in range(st.y_from + 1, s + 1):
						_want_set(want, r, y0, y1, p.x, y3b, p.y, WANT_SOLID)
				for y4 in range(s + 1, s + CastleComposerScript.DUNGEON_SHAFT_HEAD + 1):
					_want_set(want, r, y0, y1, p.x, y4, p.y, WANT_AIR)
	if _failed:
		return

	var uncut := 0
	var uncut_at := Vector3i.ZERO
	var stray := 0
	var stray_at := Vector3i.ZERO
	var air := 0
	var props := 0
	for y in range(y0, y1 + 1):
		for z in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var code := int(want[_want_index(r, y0, x, y, z)])
				var id := _vox(x, y, z)
				var solid := id != VoxelMaterial.AIR
				if not solid:
					air += 1
				elif VoxelMaterial.is_prop_furniture(id):
					props += 1
				## Furniture is allowed in carved chambers; leftover masonry is not.
				if code == WANT_AIR and solid and not VoxelMaterial.is_prop_furniture(id):
					uncut += 1
					uncut_at = Vector3i(x, y, z)
				elif code == WANT_SOLID and not solid:
					stray += 1
					stray_at = Vector3i(x, y, z)
	print(
		(
			"dungeon: %d voxels of air (+%d props) in the band over %d columns, %d chambers,"
			+ " %d openings, %d flights"
		)
		% [
			air,
			props,
			r.size.x * r.size.y,
			layout.dungeon_vaults.size(),
			layout.dungeon_doorways.size(),
			flights.size(),
		]
	)
	if uncut > 0:
		_fail(
			"FAIL %d voxels the plan carves are still masonry, e.g. %s"
			% [uncut, uncut_at]
		)
		return
	if stray > 0:
		_fail(
			"FAIL %d voxels of the band are air the plan never asked for, e.g. %s"
			% [stray, stray_at]
		)


## Every chamber is a room a body can be in: a floor, a ceiling clear of the profile's head,
## and no room narrower than the cut is allowed to leave.
func _check_dungeon_rooms(layout: CastleLayout) -> void:
	var min_head := 99
	var min_span := 999
	var max_span := 0
	var per_level: Array[String] = []
	for l in range(layout.dungeon_levels):
		var on := layout.dungeon_vaults_on(l)
		per_level.append("%d" % on.size())
		if on.is_empty():
			_fail("FAIL dungeon level %d has no chambers" % l)
			return
		for v: CastleVault in on:
			if v.floor_y != layout.dungeon_floor_y(l):
				_fail(
					"FAIL %s is floored at Y=%d, level %d is at Y=%d"
					% [v.describe(), v.floor_y, l, layout.dungeon_floor_y(l)]
				)
				return
			min_span = mini(min_span, v.narrow_span())
			max_span = maxi(max_span, v.narrow_span())
			var probe := _vault_probe(v)
			if probe.x < 0:
				_fail("FAIL %s has no column a body can stand in" % v.describe())
				return
			min_head = mini(min_head, _headroom(probe, v.floor_y))
	print(
		(
			"vaults: %d over %d levels [%s], spans %d..%d voxels, least ceiling %d,"
			+ " wide=%d small=%d tall=%d"
		)
		% [
			layout.dungeon_vaults.size(),
			layout.dungeon_levels,
			"/".join(per_level),
			min_span,
			max_span,
			min_head,
			layout.dungeon_wide_count(),
			layout.dungeon_small_count(),
			layout.dungeon_tall_count(),
		]
	)
	if min_span < CastleComposerScript.DUNGEON_CELL_MIN:
		_fail(
			"FAIL a chamber is %d voxels across, the cut may not leave less than %d"
			% [min_span, CastleComposerScript.DUNGEON_CELL_MIN]
		)
		return
	if min_head < MIN_HEAD:
		_fail(
			"FAIL a chamber has %d voxels of ceiling, the profile needs %d"
			% [min_head, MIN_HEAD]
		)
		return
	## Both are asked for by name, and a dungeon of one grain throughout is the failure the
	## user would notice first.
	if layout.dungeon_wide_count() == 0:
		_fail("FAIL no chamber is %d voxels across — the dungeon has no halls"
			% CastleVault.WIDE_MIN)
		return
	if layout.dungeon_small_count() == 0:
		_fail("FAIL no chamber is %d voxels or less across — the dungeon has no cells"
			% CastleVault.SMALL_MAX)


## Every riser of every dungeon flight, entrances included, measured off the voxels. Same
## one-voxel rule as the keep's: at two the walk edge is gone and the bake leaves a one-way
## drop a pedestrian can fall down and never climb.
func _check_dungeon_stairs(layout: CastleLayout) -> void:
	var flights := _dungeon_flights(layout)
	if flights.is_empty():
		_fail("FAIL the dungeon has no flights at all")
		return
	if layout.dungeon_stairs.is_empty():
		_fail("FAIL no flight links one dungeon level to the next")
		return
	var worst := 0
	var worst_on := ""
	var min_head := 99
	var min_lane := 99
	for st: CastleStair in flights:
		print("  %s foot=%s head=%s" % [
			st.describe(), st.center_column(0) - st.dir, st.center_column(st.run_len() - 1)
		])
		min_lane = mini(min_lane, st.lane_w)
		if not _stands_on(st.center_column(0) - st.dir, st.y_from):
			_fail("FAIL %s: nothing to step off at the foot" % st.describe())
			return
		var head := st.center_column(st.run_len() - 1)
		if not _stands_on(head, st.top_y()):
			_fail(
				"FAIL %s: nothing to step onto at the head %s, Y=%d"
				% [st.describe(), head, st.top_y()]
			)
			return
		var m := _measure_flight(st)
		min_head = mini(min_head, m.y)
		if m.x > worst:
			worst = m.x
			worst_on = "%s station %d" % [st.describe(), m.z]
		if _failed:
			return
		_check_stair_opening(st)
		if _failed:
			return
	print(
		(
			"dungeon stairs: %d flights (%d between levels, %d entrances), worst riser %d voxel,"
			+ " narrowest lane %d, least tread headroom %d"
		)
		% [
			flights.size(),
			layout.dungeon_stairs.size(),
			layout.dungeon_entries.size(),
			worst,
			min_lane,
			min_head,
		]
	)
	if worst > 1:
		_fail("FAIL a %d voxel riser at %s — pedestrians cannot climb it" % [worst, worst_on])
		return
	if min_lane < MIN_WALK_W:
		_fail("FAIL a dungeon flight is only %d voxels wide" % min_lane)
		return
	if min_head < MIN_HEAD:
		_fail("FAIL a dungeon tread has only %d voxels of headroom, the profile needs %d"
			% [min_head, MIN_HEAD])


## A tall chamber is only tall if the slabs over it were never cast. The whole footprint is
## checked by `_check_dungeon_plan`; this measures the section a player reads as height, and
## says so per chamber, because "possible but not guaranteed" means a seed with none is a
## legitimate result and the report has to distinguish that from a broken one.
func _check_dungeon_tall(layout: CastleLayout) -> void:
	var tall := 0
	for v: CastleVault in layout.dungeon_vaults:
		if not v.is_tall():
			if v.air_h != layout.dungeon_level_h - layout.dungeon_slab_thick:
				_fail(
					"FAIL %s is one level but %d voxels of air, not %d"
					% [v.describe(), v.air_h, layout.dungeon_level_h - layout.dungeon_slab_thick]
				)
				return
			continue
		tall += 1
		var want_h := v.span_levels * layout.dungeon_level_h - layout.dungeon_slab_thick
		if v.air_h != want_h:
			_fail(
				"FAIL %s spans %d levels but has %d voxels of air, not %d"
				% [v.describe(), v.span_levels, v.air_h, want_h]
			)
			return
		if v.level + v.span_levels > layout.dungeon_levels:
			_fail("FAIL %s reaches past the top of the band" % v.describe())
			return
		var probe := _vault_probe(v)
		for y in range(v.floor_y + 1, v.top_y() + 1):
			var id := _vox(probe.x, y, probe.y)
			## Room props / footprint fillers are allowed; hanging slab stone is not.
			if id != VoxelMaterial.AIR and not VoxelMaterial.is_prop_furniture(id):
				_fail(
					"FAIL %s has masonry at Y=%d over %s — a slab fragment is hanging in it"
					% [v.describe(), y, probe]
				)
				return
		## The chamber is only vaulted if the slab it replaced is gone across the whole level
		## boundary, not merely over one column.
		for l in range(v.level + 1, v.level + v.span_levels):
			var slab := layout.dungeon_floor_y(l)
			var solid := 0
			for z in range(v.rect.position.y, v.rect.end.y):
				for x in range(v.rect.position.x, v.rect.end.x):
					if _vox(x, slab, z) != VoxelMaterial.AIR:
						solid += 1
			if solid > 0:
				_fail(
					"FAIL %s has %d voxels of level %d's floor left inside it"
					% [v.describe(), solid, l]
				)
				return
	print(
		"tall chambers: %d of %d, %s"
		% [
			tall,
			layout.dungeon_vaults.size(),
			(
				"none this seed — legitimate, the roll allows a dungeon of even height"
				if tall == 0
				else "spans %s levels" % _tall_spans(layout)
			),
		]
	)


## Two forever-war pads on distinct monster factions, spaced across the vault set.
func _check_dungeon_summoners(layout: CastleLayout) -> void:
	const WANT := 2
	const FORBIDDEN := ["human", "spectator", "unique"]
	if layout.dungeon_summoners.size() != WANT:
		_fail(
			"FAIL dungeon has %d summoner pads, expected %d"
			% [layout.dungeon_summoners.size(), WANT]
		)
		return
	if layout.dungeon_summoner_factions.size() != WANT:
		_fail(
			"FAIL dungeon has %d summoner factions, expected %d"
			% [layout.dungeon_summoner_factions.size(), WANT]
		)
		return
	var a: Vector3i = layout.dungeon_summoners[0]
	var b: Vector3i = layout.dungeon_summoners[1]
	var fa := String(layout.dungeon_summoner_factions[0])
	var fb := String(layout.dungeon_summoner_factions[1])
	if fa == fb:
		_fail("FAIL dungeon summoners share faction '%s'" % fa)
		return
	for f in [fa, fb]:
		if FORBIDDEN.has(f):
			_fail("FAIL dungeon summoner faction '%s' is not a combat side" % f)
			return
		var ok := false
		for i in range(MonsterFaction.MONSTER_COUNT):
			if MonsterFaction.faction_name(MonsterFaction.monster_faction_at(i)) == f:
				ok = true
				break
		if not ok:
			_fail("FAIL dungeon summoner faction '%s' is unknown" % f)
			return
	## Each pad must sit inside some vault's footprint on that vault's floor.
	for pad: Vector3i in layout.dungeon_summoners:
		var inside := false
		for v: CastleVault in layout.dungeon_vaults:
			if pad.y != v.floor_y:
				continue
			if (
				pad.x >= v.rect.position.x
				and pad.x < v.rect.end.x
				and pad.z >= v.rect.position.y
				and pad.z < v.rect.end.y
			):
				inside = true
				break
		if not inside:
			_fail("FAIL dungeon summoner %s is not inside any vault floor" % pad)
			return
	var dx := a.x - b.x
	var dz := a.z - b.z
	var dy := a.y - b.y
	var dist2 := dx * dx + dz * dz + dy * dy
	if dist2 < 36:
		_fail(
			"FAIL dungeon summoners are too close (%s vs %s, dist2=%d)"
			% [a, b, dist2]
		)
		return
	print("OK dungeon summoners: %s@%s vs %s@%s" % [fa, a, fb, b])


## At least one route down always exists. Which ones, and how many, is the first thing that
## makes two castles different, so the mix is reported rather than merely asserted non-empty.
func _check_dungeon_entries(layout: CastleLayout) -> void:
	if layout.dungeon_entries.is_empty():
		_fail("FAIL no way down into the dungeon was planned")
		return
	var seen: Array[int] = []
	for e: CastleDungeonEntry in layout.dungeon_entries:
		if seen.has(e.kind):
			_fail("FAIL two %s routes were planned" % e.kind_name())
			return
		seen.append(e.kind)
		if e.stair == null:
			_fail("FAIL the %s route has no flight" % e.kind_name())
			return
		if e.stair.top_y() != layout.courtyard_y:
			_fail(
				"FAIL the %s route arrives at Y=%d, the courtyard datum is Y=%d"
				% [e.kind_name(), e.stair.top_y(), layout.courtyard_y]
			)
			return
		if e.stair.y_from != layout.dungeon_floor_y(layout.dungeon_top_level()):
			_fail(
				"FAIL the %s route leaves Y=%d, the top dungeon level is at Y=%d"
				% [
					e.kind_name(),
					e.stair.y_from,
					layout.dungeon_floor_y(layout.dungeon_top_level()),
				]
			)
			return
		if e.kind == CastleDungeonEntry.KIND_TOWER_BASE:
			if e.tower_index < 0 or e.tower_index >= layout.towers.size():
				_fail("FAIL the tower-base route names tower %d" % e.tower_index)
				return
			var t: CastleTower = layout.towers[e.tower_index]
			if t.kind != CastleTower.KIND_CORNER:
				_fail("FAIL the tower-base route uses a %s tower" % t.kind)
				return
			if e.chamber_air_h < MIN_HEAD:
				_fail(
					"FAIL the tower base guardroom is %d voxels tall, the profile needs %d"
					% [e.chamber_air_h, MIN_HEAD]
				)
				return
			var pass_w := mini(e.chamber_rect.size.x, e.chamber_rect.size.y)
			if pass_w < CastleComposerScript.DUNGEON_STAIR_W:
				_fail(
					(
						"FAIL the tower-base passage is %d voxels across, the flight is %d"
						+ " — one column short zeroes nav clearance"
					)
					% [pass_w, CastleComposerScript.DUNGEON_STAIR_W]
				)
				return
		elif e.tower_index != -1:
			_fail("FAIL the %s route names a tower" % e.kind_name())
			return
	print(
		"entries: %d of %d routes — %s"
		% [
			layout.dungeon_entries.size(),
			CastleDungeonEntry.KIND_COUNT,
			layout.dungeon_entry_names(),
		]
	)


## Clear stairwell aperture against walker/nav needs: the well through the floor above must
## be at least `MIN_WALK_W` across, and the arrival lip must not rebuild a coplanar curb one
## voxel below the landing surface (that is the one-voxel-too-small opening the walker hits).
func _check_stair_opening(st: CastleStair) -> void:
	var top := st.top_y()
	var open_w := 0
	var open_run := 0
	for t in range(st.run_len()):
		var row := 0
		for k in range(st.lane_w):
			var p := st.column(t, k)
			if _vox(p.x, top, p.y) == VoxelMaterial.AIR:
				row += 1
		if row > 0:
			open_run += 1
			open_w = row if open_w == 0 else mini(open_w, row)
	if open_w < MIN_WALK_W:
		_fail(
			"FAIL %s well is only %d voxels wide through Y=%d — nav needs %d clear"
			% [st.describe(), open_w, top, MIN_WALK_W]
		)
		return
	if open_run < MIN_WALK_W:
		_fail(
			"FAIL %s well is only %d stations long through Y=%d — a body needs %d"
			% [st.describe(), open_run, top, MIN_WALK_W]
		)
		return
	## Arrival lip: surface at top_y, the course under it must be air across the lane.
	var land_t := st.rise + 1
	var lip_y := top - 1
	for k2 in range(st.lane_w):
		var land := st.column(land_t, k2)
		if _vox(land.x, top, land.y) == VoxelMaterial.AIR:
			_fail(
				"FAIL %s has no landing surface at t=%d %s Y=%d"
				% [st.describe(), land_t, land, top]
			)
			return
		if _vox(land.x, lip_y, land.y) != VoxelMaterial.AIR:
			_fail(
				(
					"FAIL %s landing lip at t=%d %s Y=%d is still solid — the well is one"
					+ " voxel too short and a walker jams on the last rising tread"
				)
				% [st.describe(), land_t, land, lip_y]
			)
			return


## Flights the dungeon owns: the entrance descents and the inter-level stairs.
func _dungeon_flights(layout: CastleLayout) -> Array[CastleStair]:
	var out: Array[CastleStair] = []
	for e: CastleDungeonEntry in layout.dungeon_entries:
		out.append(e.stair)
	out.append_array(layout.dungeon_stairs)
	return out


func _tall_spans(layout: CastleLayout) -> String:
	var parts: Array[String] = []
	for v: CastleVault in layout.dungeon_vaults:
		if v.is_tall():
			parts.append("%d@L%d" % [v.span_levels, v.level])
	return "+".join(parts)


## Lane columns of a flight, rail excluded — the columns it actually cuts.
func _stair_columns(st: CastleStair) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in range(st.run_len()):
		for k in range(st.lane_w):
			out.append(st.column(t, k))
	return out


func _want_index(r: Rect2i, y0: int, x: int, y: int, z: int) -> int:
	return ((y - y0) * r.size.y + (z - r.position.y)) * r.size.x + (x - r.position.x)


## Marks one voxel of the expected-state grid. A Y outside the band is not an error — an
## entrance shaft climbs out of it on purpose — but a column outside the substructure's
## footprint is a chamber planned in the open bailey, so it fails here.
func _want_set(
	want: PackedByteArray, r: Rect2i, y0: int, y1: int, x: int, y: int, z: int, code: int
) -> void:
	if y < y0 or y > y1:
		return
	if not r.has_point(Vector2i(x, z)):
		if not _failed:
			_fail(
				"FAIL the dungeon plan reaches %s, outside its own footprint %s"
				% [Vector2i(x, z), r]
			)
		return
	want[_want_index(r, y0, x, y, z)] = code


# ---------------------------------------------------------------------------
# Doors — Phase 4
# ---------------------------------------------------------------------------

## Every planned opening is a clear walkable cut (no hung leaves / DOOR plugs on castles).
##
## Doorway records still define circulation; sealed DOOR barriers are intentionally not hung
## so dungeon forever-war mobs can path through the keep and crypt.
func _check_doors(layout: CastleLayout) -> void:
	## The apron is the composer's, not the door's. Asserted rather than imported, because a
	## constant reaching from `CastleDoorway` into `CastleComposer` would close a cycle
	## between the two, and a silent drift here is the failure mode this phase is about.
	if CastleDoorway.SWING_REACH != CastleComposerScript.LANE_MARGIN:
		_fail(
			"FAIL a leaf may swing %d voxels out but lanes only keep %d clear"
			% [CastleDoorway.SWING_REACH, CastleComposerScript.LANE_MARGIN]
		)
		return
	_check_door_plan("seed %d" % _world_seed, layout)
	if _failed:
		return
	var all := layout.doorways()
	var profiles: Dictionary[String, int] = {}
	var shoulders := 0
	for d: CastleDoorway in all:
		shoulders += _check_opening_voxels(d)
		if _failed:
			return
		var key := "%s %dx%d through %d" % [d.leaf_name(), d.width, d.height, d.depth]
		profiles[key] = int(profiles.get(key, 0)) + 1
	var keys := profiles.keys()
	keys.sort()
	print("doors: %d openings, %d leaf profiles" % [all.size(), keys.size()])
	for k: String in keys:
		print("  %-30s x%d" % [k, profiles[k]])
	print(
		"  tiers: 2 gates, %d keep doors, %d dungeon grilles — %d tree edges, %d loops"
		% [
			layout.keep_doorways.size(),
			layout.dungeon_doorways.size(),
			layout.doorway_link_count(CastleDoorway.LINK_TREE),
			layout.doorway_link_count(CastleDoorway.LINK_LOOP),
		]
	)
	print("  %d arch shoulders are masonry, as the stepped profile intends" % shoulders)
	if layout.keep_doorways.is_empty():
		_check_keep_door_voxels()


## The keep's own doorways, measured off the voxels on a seed that has some.
##
## Seed 42's keep subdivides into one room a storey, so it plans no interior doorways at all
## and the middle of the three tiers would go unmeasured on the only seed this file cuts
## voxels for. Rather than hardcode a second seed, the first one whose keep does subdivide is
## found, baked and measured the same way the gate and the dungeon are above.
func _check_keep_door_voxels() -> void:
	var keep := _volume
	for s in range(1, DISTINCT_SEED_MAX + 1):
		var c := DistrictTheme.find_coord_for_theme(s, DistrictTheme.CASTLE, MAX_RING)
		if DistrictTheme.for_district(s, c).id != DistrictTheme.CASTLE:
			continue
		var res: Dictionary = DistrictBakeJobScript.bake({"coord": c, "world_seed": s})
		if not bool(res.get("ok", false)):
			_fail("FAIL bake of seed %d: %s" % [s, res.get("error", "?")])
			return
		var gen: DistrictGenerator = res["generator"]
		var l := gen.get_castle_layout()
		if l == null or l.keep_doorways.is_empty():
			continue
		_volume = gen.get_offline_volume() as NativeOfflineVoxelVolume
		if _volume == null:
			_fail("FAIL seed %d's bake kept no voxel volume to probe" % s)
			_volume = keep
			return
		var shoulders := 0
		var tallest := 0
		for d: CastleDoorway in l.keep_doorways:
			shoulders += _check_opening_voxels(d)
			tallest = maxi(tallest, d.height)
			if _failed:
				_volume = keep
				return
		print(
			"keep doors: seed %d cuts %d of them, up to %d courses tall, %d arch shoulders"
			% [s, l.keep_doorways.size(), tallest, shoulders]
		)
		_volume = keep
		return
	_fail(
		"FAIL no world seed in 1..%d subdivides a keep — the interior door tier is untested"
		% DISTINCT_SEED_MAX
	)


## Every invariant a door has that can be read off the plan alone. Split out from the voxel
## measurements because it is what the seed sweep can afford to run on all twenty of them,
## and a leaf that does not fit is exactly the failure a rare seed would produce.
func _check_door_plan(what: String, layout: CastleLayout) -> void:
	var all := layout.doorways()
	if all.is_empty():
		_fail("FAIL %s: the fortress plans no doors at all" % what)
		return
	var worst_swing := 0.0
	var worst_swing_on := ""
	for d: CastleDoorway in all:
		if d.leaf < CastleDoorway.LEAF_GATE or d.leaf > CastleDoorway.LEAF_GRATE:
			_fail("FAIL %s: %s has no leaf kind" % [what, d.describe()])
			return
		if d.is_load_bearing() != (d.link == CastleDoorway.LINK_TREE):
			_fail(
				"FAIL %s: %s disagrees with itself about being load-bearing"
				% [what, d.describe()]
			)
			return
		if d.width < MIN_WALK_W or d.width % 2 == 0:
			_fail(
				"FAIL %s: %s is %d columns across — nav needs an odd %d or more"
				% [what, d.describe(), d.width, MIN_WALK_W]
			)
			return
		if d.clear_rows() < 1:
			_fail(
				"FAIL %s: %s is %d courses tall, the arch alone takes %d"
				% [what, d.describe(), d.height, CastleDoorway.ARCH_COURSES]
			)
			return
		## Two leaves hinged on the jambs have to meet exactly on the centre line: any less
		## and the pair does not fill the opening, any more and they overlap in the middle.
		if not is_equal_approx(d.leaf_reach(), float(d.width / 2) + 0.5):
			_fail(
				"FAIL %s: %s hangs leaves reaching %.2f voxels from the jamb, the centre"
				% [what, d.describe(), d.leaf_reach()]
				+ " line is %.2f away" % (float(d.width / 2) + 0.5)
			)
			return
		if not d.leaf_is_recessed():
			_fail(
				(
					"FAIL %s: %s closes onto %.2f..%.2f along its axis but the masonry is"
					+ " only %.2f..%.2f deep — the door sticks out of its own reveal"
				)
				% [
					what,
					d.describe(),
					d.hang_plane() - d.leaf_half_t(),
					d.hang_plane() + d.leaf_half_t(),
					-0.5,
					float(d.depth) - 0.5,
				]
			)
			return
		var out := d.swing_out()
		if out > worst_swing:
			worst_swing = out
			worst_swing_on = d.describe()
	if worst_swing > float(CastleDoorway.SWING_REACH) + FIT_EPS:
		_fail(
			"FAIL %s: an open leaf reaches %.2f voxels into the room past the %d voxel"
			% [what, worst_swing, CastleDoorway.SWING_REACH]
			+ " apron, on %s" % worst_swing_on
		)
		return
	_check_door_tiers(what, layout)


## The opening a leaf is cut to fit, checked against the voxels course by course. `row_half()`
## is what the masonry was carved from and what the leaf is built to, so if the stone and the
## record ever disagree this is where it shows, rather than as a leaf clipping through a jamb
## in a screenshot. Returns the shoulder columns found to be masonry.
func _check_opening_voxels(d: CastleDoorway) -> int:
	var side := d.side()
	var shoulders := 0
	for row in range(1, d.height + 1):
		var half := d.row_half(row)
		if half < 0:
			continue
		var y := d.floor_y + row
		for u in range(d.depth):
			for t in range(-half, half + 1):
				var p := d.center + d.axis * u + side * t
				if _vox(p.x, y, p.y) != VoxelMaterial.AIR:
					_fail(
						(
							"FAIL %s: the leaf covers %s at Y=%d and that column is masonry —"
							+ " the door would hang through the wall"
						)
						% [d.describe(), p, y]
					)
					return shoulders
			if half >= d.width / 2:
				continue
			for sign: int in [-1, 1]:
				var q := d.center + d.axis * u + side * ((half + 1) * sign)
				if _vox(q.x, y, q.y) != VoxelMaterial.AIR:
					shoulders += 1
	return shoulders


## Which door hangs where, and which openings a lock would be allowed to touch.
##
## The three tiers get three leaves on purpose — the fortress gate and the keep's own front
## door are the two a player walks up to, and a barred grille is what makes a warren of cells
## read as cells rather than as a corridor of blank slabs. The tree/loop split is the other
## half: nothing bars anything in the prototype, but a spanning-tree edge is the only way into
## the rooms behind it, and that is knowable now and expensive to recover from a finished plan.
func _check_door_tiers(what: String, layout: CastleLayout) -> void:
	if layout.gate_doorway.leaf != CastleDoorway.LEAF_GATE:
		_fail("FAIL %s: the fortress gate hangs a %s"
			% [what, layout.gate_doorway.leaf_name()])
		return
	if layout.keep_entrance.leaf != CastleDoorway.LEAF_GATE:
		_fail("FAIL %s: the keep's front door hangs a %s"
			% [what, layout.keep_entrance.leaf_name()])
		return
	for d: CastleDoorway in layout.keep_doorways:
		if d.leaf != CastleDoorway.LEAF_DOOR or d.link != CastleDoorway.LINK_TREE:
			_fail("FAIL %s: %s is not an interior door on a tree edge" % [what, d.describe()])
			return
	var loops := 0
	var a_loop: CastleDoorway = null
	for d2: CastleDoorway in layout.dungeon_doorways:
		if d2.leaf != CastleDoorway.LEAF_GRATE:
			_fail("FAIL %s: %s is not a grille" % [what, d2.describe()])
			return
		if d2.link == CastleDoorway.LINK_LOOP:
			loops += 1
			a_loop = d2
	if loops == 0:
		_fail(
			"FAIL %s: not one of %d dungeon openings is past the spanning tree — every"
			% [what, layout.dungeon_doorways.size()]
			+ " level branches and nothing loops"
		)
		return
	## The guard the distinction exists for. Only ever exercised on a loop edge: refusing a
	## tree edge is a `push_error`, and this test may not print errors under a green result.
	if not a_loop.may_bar():
		_fail("FAIL %s: %s is a loop edge and may_bar() refused it" % [what, a_loop.describe()])


## Castle layouts must not hang sealed doors — openings stay AIR for dungeon circulation.
func _check_castle_doors_not_hung(layout: CastleLayout, res: Dictionary) -> void:
	var placer: CastleDoorPlacer = CastleDoorPlacerScript.new()
	placer.name = "CastleDoors"
	add_child(placer)
	var origin: Vector3i = res["origin_vox"]
	placer.place_from_layout(layout, VOXEL_SIZE, origin, null)
	if placer.door_count() != 0:
		_fail(
			"FAIL castle placer hung %d doors; castle openings must stay unsealed"
			% placer.door_count()
		)
		return
	## Doorway clears in the bake must not be filled with DOOR plugs.
	var plugged := 0
	for d: CastleDoorway in layout.doorways():
		for cell: Vector3i in DoorBarrierScript.barrier_cells(d, Vector3i.ZERO):
			var id := _vox(cell.x, cell.y, cell.z)
			if id == VoxelMaterial.DOOR:
				plugged += 1
	if plugged > 0:
		_fail("FAIL bake sealed %d DOOR voxels in castle doorway clears" % plugged)
		return
	print(
		"OK castle doors not hung (%d openings stay open)"
		% layout.doorways().size()
	)
	placer.queue_free()


# ---------------------------------------------------------------------------
# Navigation — the point of the whole exercise
# ---------------------------------------------------------------------------

func _report_nav_stats(res: Dictionary) -> void:
	var stats: Dictionary = res["nav_stats"]
	if not bool(stats.get("ok", false)):
		_fail("FAIL nav stats not ok: %s" % stats)
		return
	var columns := int(stats["columns"])
	var spans := int(stats["spans"])
	print(
		(
			"nav columns=%d spans=%d (%.2f/column, max %d) sectors=%d nodes=%d portals=%d"
			+ " links=%d bytes=%.2f MiB"
		)
		% [
			columns,
			spans,
			float(spans) / maxf(float(columns), 1.0),
			int(stats["max_spans_per_column"]),
			int(stats["sectors"]),
			int(stats["nodes"]),
			int(stats["portals"]),
			int(stats["links"]),
			float(int(stats["bytes"])) / (1024.0 * 1024.0),
		]
	)


## A pedestrian standing on the road stub the gate faces must be able to path to the middle
## of the bailey. Not "the geometry looks connected" — the profile that cannot climb or jump
## has to find the route over the causeway and through the gate.
func _check_path_to_courtyard(
	nav: NavService, coord: Vector2i, res: Dictionary, layout: CastleLayout
) -> void:
	var nav_bake := res["nav_bake"] as RefCounted
	if nav_bake == null:
		_fail("FAIL the bake returned no nav field")
		return
	if not nav.register_district(coord, nav_bake):
		_fail("FAIL NavService refused the castle district")
		return
	var origin: Vector3i = res["origin_vox"]
	var street := layout.road_target
	var from := _world(origin, street.x, _surface_y(street) + 1, street.y)
	var to := _world(
		origin, layout.courtyard_center.x, layout.courtyard_y + 1, layout.courtyard_center.y
	)
	var path := nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to)
	if not path.is_usable():
		_fail(
			"FAIL a pedestrian cannot walk from the road stub %s to the bailey %s: %s"
			% [street, layout.courtyard_center, path.status_name()]
		)
		return
	var climbed := path.points[path.points.size() - 1].y - path.points[0].y
	print(
		(
			"pedestrian path: road stub %s → bailey %s, %d points from %d searched,"
			+ " %.1f m of climb"
		)
		% [street, layout.courtyard_center, path.points.size(), path.raw_points, climbed]
	)
	## A route that never leaves the street deck is not a route into the castle.
	if climbed < float(CastleComposerScript.PLINTH_RISE) * VOXEL_SIZE * 0.9:
		_fail(
			"FAIL the path only climbed %.1f m — it never reached the plinth top" % climbed
		)
		return
	## And it has to go through the gate, not over a wall the undead profile could climb.
	## Measured against the legs, not the corners: a route this straight is returned as
	## four points and none of them need land on the threshold it walked over.
	var mouth := _world(
		origin, layout.gate_center.x, layout.courtyard_y + 1, layout.gate_center.y
	)
	if not _passes_near(path, mouth, float(layout.gate_width) * VOXEL_SIZE * 2.0):
		_fail("FAIL the path into the bailey never passed the gate at %s" % layout.gate_center)


## Each flight on its own, foot to head. The whole-keep path below would fail the same way
## for any broken flight; this says which one.
func _check_flights_walkable(
	nav: NavService, res: Dictionary, layout: CastleLayout
) -> void:
	var d := layout.keep_entrance
	var inside := d.center + d.axis * d.depth
	for st: CastleStair in layout.keep_stairs:
		var foot := st.center_column(0) - st.dir
		var head := st.center_column(st.run_len() - 1)
		if st.from_storey >= 0:
			## The chain matters as much as the flight: a landing that is walled off from
			## the next flight's foot leaves the storeys above it unreachable.
			if _walk(
				nav,
				res,
				"keep entrance → foot of %s" % st.describe(),
				inside,
				d.floor_y + 1,
				foot,
				st.y_from + 1
			) == null:
				_dump_storey(layout, st.from_storey)
				return
		if _walk(nav, res, st.describe(), foot, st.y_from + 1, head, st.top_y() + 1) == null:
			return
	print("flights: all %d climbable by a pedestrian" % layout.keep_stairs.size())


## From the bailey, through the keep's own gate, up every flight, to a room on the topmost
## storey. This is the Phase 2 headline: the keep is a building, not a solid block with
## windows.
func _check_path_into_keep(nav: NavService, res: Dictionary, layout: CastleLayout) -> void:
	var f := layout.keep_floor(layout.keep_top_storey())
	var probe := _room_probe(f, f.rooms[0])
	if probe.x < 0:
		_fail("FAIL no walkable column on the topmost storey")
		return
	var path := _walk(
		nav,
		res,
		"bailey → keep storey %d" % f.storey,
		layout.courtyard_center,
		layout.courtyard_y + 1,
		probe,
		f.floor_y + 1
	)
	if path == null:
		_dump_storey(layout, f.storey)
		return
	print(
		"keep path: bailey %s → storey %d %s, %d points from %d searched, %.1f m of climb"
		% [
			layout.courtyard_center,
			f.storey,
			probe,
			path.points.size(),
			path.raw_points,
			path.points[path.points.size() - 1].y - path.points[0].y,
		]
	)


func _check_path_to_crown(nav: NavService, res: Dictionary, layout: CastleLayout) -> void:
	var crown_y := layout.courtyard_y + layout.wall_height
	var at := layout.crown_walk
	if _vox(at.x, crown_y, at.y) != VoxelMaterial.CASTLE_BLOCK:
		_fail("FAIL the crown at %s is not masonry at Y=%d" % [at, crown_y])
		return
	var path := _walk(
		nav,
		res,
		"bailey → wall crown",
		layout.courtyard_center,
		layout.courtyard_y + 1,
		at,
		crown_y + 1
	)
	if path == null:
		return
	print(
		"crown path: bailey %s → rampart %s, %d points from %d searched, %.1f m of climb"
		% [
			layout.courtyard_center,
			at,
			path.points.size(),
			path.raw_points,
			path.points[path.points.size() - 1].y - path.points[0].y,
		]
	)


## The real test of "wide rooms, actually traversable": if the subdivision ever seals a
## room off, this fails loudly instead of the room quietly never being visited.
func _check_every_room_reachable(
	nav: NavService, res: Dictionary, layout: CastleLayout
) -> void:
	var d := layout.keep_entrance
	var inside := d.center + d.axis * d.depth
	var checked := 0
	var worst_raw := 0
	for f: CastleFloor in layout.keep_floors:
		if not f.has_slab:
			continue
		for r: Rect2i in f.rooms:
			var probe := _room_probe(f, r)
			if probe.x < 0:
				_fail("FAIL storey %d room %s has no walkable column" % [f.storey, r])
				return
			var path := _walk(
				nav,
				res,
				"keep entrance → storey %d room %s" % [f.storey, r],
				inside,
				d.floor_y + 1,
				probe,
				f.floor_y + 1
			)
			if path == null:
				_dump_storey(layout, f.storey)
				return
			checked += 1
			worst_raw = maxi(worst_raw, path.expanded)
	print(
		"reachability: all %d keep rooms reachable from the entrance %s (worst search %d nodes)"
		% [checked, inside, worst_raw]
	)


## Each route down, walked twice: the bailey to its head, then its head to its foot. A route
## that exists in the plan but that nothing can reach from the open courtyard is not an
## entrance, and a flight that is reachable but not descendable is a hole in the floor.
##
## Walked separately per route on purpose. One query from the bailey to the deepest level
## would be satisfied by whichever route happened to work, which is exactly the failure —
## two routes present and one of them impassable — that this is here to catch.
func _check_dungeon_descents(
	nav: NavService, res: Dictionary, layout: CastleLayout
) -> void:
	var top := layout.dungeon_top_level()
	for e: CastleDungeonEntry in layout.dungeon_entries:
		var st := e.stair
		var head := e.head()
		var foot := st.center_column(0) - st.dir
		if _walk(
			nav,
			res,
			"bailey → head of the %s route" % e.kind_name(),
			layout.courtyard_center,
			layout.courtyard_y + 1,
			head,
			layout.courtyard_y + 1
		) == null:
			_dump_area(
				"the %s route's head" % e.kind_name(),
				Rect2i(head - Vector2i.ONE * 16, Vector2i.ONE * 33),
				layout.courtyard_y
			)
			return
		var down := _walk(
			nav,
			res,
			"%s route, head → dungeon level %d" % [e.kind_name(), top],
			head,
			layout.courtyard_y + 1,
			foot,
			st.y_from + 1
		)
		if down == null:
			return
		var dropped := down.points[0].y - down.points[down.points.size() - 1].y
		print(
			"  %s: bailey → %s → foot %s, %.1f m of descent"
			% [e.kind_name(), head, foot, dropped]
		)
	print("descents: all %d routes walkable in both halves" % layout.dungeon_entries.size())


## Every chamber on every level, from every route down. The core assertion of the phase: an
## unreachable vault is worse than a boring one, and a partition or a doorway sited a column
## too close to a lane strands one silently. Exhaustive, because the small rooms and the tight
## corridors are precisely where the clearance rule bites and they are not the ones a spot
## check would pick.
func _check_dungeon_reachable(
	nav: NavService, res: Dictionary, layout: CastleLayout
) -> void:
	var checked := 0
	var worst_raw := 0
	for e: CastleDungeonEntry in layout.dungeon_entries:
		var foot := e.foot()
		var from_y := e.stair.y_from + 1
		for l in range(layout.dungeon_levels):
			for v: CastleVault in layout.dungeon_vaults_on(l):
				var probe := _vault_probe(v)
				if probe.x < 0:
					_fail("FAIL %s has no walkable column" % v.describe())
					return
				var path := _walk(
					nav,
					res,
					"%s route → %s" % [e.kind_name(), v.describe()],
					foot,
					from_y,
					probe,
					v.floor_y + 1
				)
				if path == null:
					_report_cut(nav, res, layout, l, foot, from_y)
					_dump_level(layout, l)
					return
				checked += 1
				worst_raw = maxi(worst_raw, path.expanded)
	print(
		(
			"dungeon reachability: all %d chambers reachable from every one of %d routes"
			+ " (%d queries, worst search %d nodes)"
		)
		% [
			layout.dungeon_vaults.size(),
			layout.dungeon_entries.size(),
			checked,
			worst_raw,
		]
	)


## Which side of the cut every chamber on the level ended up on, and what nav makes of the two
## columns the failed query used. One unreachable chamber is a doorway; a whole wing of them is
## a partition or a lane claim, and the level map printed after this says which — but only if
## you know what to look for in it.
func _report_cut(
	nav: NavService,
	res: Dictionary,
	layout: CastleLayout,
	level: int,
	foot: Vector2i,
	from_y: int
) -> void:
	var origin: Vector3i = res["origin_vox"]
	var from_world := _world(origin, foot.x, from_y, foot.y)
	var cut: Array[CastleVault] = []
	var open := 0
	for v: CastleVault in layout.dungeon_vaults_on(level):
		var probe := _vault_probe(v)
		if probe.x < 0:
			continue
		var to_world := _world(origin, probe.x, v.floor_y + 1, probe.y)
		var path := nav.find_path_now(
			NavProfile.Id.PEDESTRIAN, from_world, to_world, ROUTE_BUDGET
		)
		if path.is_complete():
			open += 1
		else:
			cut.append(v)
	print("cut: %d of %d chambers on level %d are unreachable" % [cut.size(), open + cut.size(), level])
	for v: CastleVault in cut:
		for d: CastleDoorway in layout.dungeon_doorways:
			if d.storey != v.level:
				continue
			var near := d.center - d.axis
			var far := d.center + d.axis * d.depth
			if not v.rect.has_point(near) and not v.rect.has_point(far):
				continue
			var inward := d.axis if v.rect.has_point(far) else -d.axis
			var out := far if v.rect.has_point(near) else near
			print(
				"    %s → %s (%s, far side %s)"
				% [
					d.describe(),
					out,
					"tree" if d.is_load_bearing() else "loop",
					(
						"standable"
						if _stands_on(out, d.floor_y)
						else "nothing to stand on"
					),
				]
			)
			## March the threshold column by column: the cell where reachable turns to
			## unreachable is the seal, and it is either in the opening or past it.
			var march := ""
			for step in range(-3, d.depth + 4):
				var at := d.center + inward * step
				if not _stands_on(at, d.floor_y):
					march += " %s:-" % at
					continue
				var ok := nav.find_path_now(
					NavProfile.Id.PEDESTRIAN,
					from_world,
					_world(origin, at.x, d.floor_y + 1, at.y),
					ROUTE_BUDGET
				).is_complete()
				march += " %s:%s" % [at, "R" if ok else "x"]
			print("     march%s" % march)
		for st: CastleStair in layout.dungeon_stairs:
			if v.rect.has_point(st.center_column(0)) or v.rect.has_point(
				st.center_column(st.run_len() - 1)
			):
				print("    %s lands in it" % st.describe())
		var probe := _vault_probe(v)
		## The neighbourhood of the probe, column by column: 'R' a pedestrian can reach from
		## the route's foot, 'x' one nav has a span for and cannot reach, '-' nothing to stand
		## on. A pocket of 'x' inside a room of 'R' is not a sealed chamber at all.
		for z in range(probe.y - 4, probe.y + 5):
			var line := ""
			for x in range(probe.x - 4, probe.x + 5):
				var at := Vector2i(x, z)
				if not _stands_on(at, v.floor_y):
					line += "-"
					continue
				line += (
					"R"
					if nav
					. find_path_now(
						NavProfile.Id.PEDESTRIAN,
						from_world,
						_world(origin, x, v.floor_y + 1, z),
						ROUTE_BUDGET
					)
					. is_complete()
					else "x"
				)
			print("     %4d %s" % [z, line])
		var hit := nav.nearest_surface(
			NavProfile.Id.PEDESTRIAN,
			_world(origin, probe.x, v.floor_y + 1, probe.y),
			VOXEL_SIZE * 4.0
		)
		print(
			"  %s probe %s — nav %s clearance=%d headroom=%d %.2f m off"
			% [
				v.describe(),
				probe,
				"snapped" if hit.found else "found nothing",
				hit.clearance,
				hit.headroom,
				(
					hit.position.distance_to(
						_world(origin, probe.x, v.floor_y + 1, probe.y)
					)
					if hit.found
					else -1.0
				),
			]
		)


## The Phase 1 promise, end to end at last: a pedestrian on the public street walks over the
## causeway, through the gate, down one of the routes and into a chamber on the deepest level.
##
## Checked against the legs of the returned path rather than its vertices. A route this long
## comes back as a handful of corners and none of them need land on the gate threshold or the
## stair head it walked over — the Phase 1 bug this test now avoids by construction.
func _check_path_to_deepest(
	nav: NavService, res: Dictionary, layout: CastleLayout
) -> void:
	var deepest := layout.dungeon_vaults_on(0)
	if deepest.is_empty():
		_fail("FAIL the deepest dungeon level has no chambers")
		return
	var target: CastleVault = deepest[0]
	var probe := _vault_probe(target)
	if probe.x < 0:
		_fail("FAIL %s has no walkable column" % target.describe())
		return
	var street := layout.road_target
	var path := _walk(
		nav,
		res,
		"street → the deepest dungeon level",
		street,
		_surface_y(street) + 1,
		probe,
		target.floor_y + 1
	)
	if path == null:
		return
	var origin: Vector3i = res["origin_vox"]
	## Net height says nothing here — the street deck and the deepest chamber are only five
	## voxels apart. What the route has to prove is that it went over the plinth and then under
	## it, so the crest and the trough are what get measured.
	var crest := -(1 << 30)
	var trough := 1 << 30
	for p: Vector3 in path.points:
		var y := int(roundf(p.y / VOXEL_SIZE)) - origin.y
		crest = maxi(crest, y)
		trough = mini(trough, y)
	print(
		(
			"street → dungeon: road stub %s → %s on level 0, %d points from %d searched,"
			+ " over the plinth at Y=%d and down to Y=%d"
		)
		% [street, probe, path.points.size(), path.raw_points, crest, trough]
	)
	if crest < layout.courtyard_y:
		_fail(
			"FAIL the route never rose to the courtyard datum Y=%d — it peaked at Y=%d"
			% [layout.courtyard_y, crest]
		)
		return
	if trough > target.floor_y + 1:
		_fail(
			"FAIL the route never got below Y=%d — the deepest level's floor is Y=%d"
			% [trough, target.floor_y]
		)
		return
	## Through the gate and down a planned route, not over a wall or through a hole in the
	## slab that nothing planned.
	var gate := _world(
		origin, layout.gate_center.x, layout.courtyard_y + 1, layout.gate_center.y
	)
	if not _passes_near(path, gate, float(layout.gate_width) * VOXEL_SIZE * 2.0):
		_fail("FAIL the route to the dungeon never passed the gate at %s" % layout.gate_center)
		return
	var used := ""
	for e: CastleDungeonEntry in layout.dungeon_entries:
		var head := e.head()
		var mouth := _world(origin, head.x, layout.courtyard_y + 1, head.y)
		if _passes_near(path, mouth, float(e.stair.lane_w) * VOXEL_SIZE * 2.0):
			used = e.kind_name()
			break
	if used.is_empty():
		_fail(
			"FAIL the route reached the dungeon without passing any of the %d planned routes down"
			% layout.dungeon_entries.size()
		)
		return
	print("  the route took the %s stair down" % used)


## Whether any leg of a path runs within `reach` of a point. Legs, not vertices: a straight
## run is returned as its two ends.
func _passes_near(path: NavPathResult, at: Vector3, reach: float) -> bool:
	for i in range(1, path.points.size()):
		var near := Geometry3D.get_closest_point_to_segment(at, path.points[i - 1], path.points[i])
		if near.distance_to(at) <= reach:
			return true
	return false


## Routes between two columns and insists the result really ran between those two.
##
## NavService snaps an endpoint it cannot stand on onto the nearest span it can, so a query
## aimed at a sealed room comes back as a perfectly good route to somewhere else entirely.
## Both endpoints are checked against the voxels first and both ends of the result against
## the endpoints, or these assertions prove nothing. Returns null on failure.
func _walk(
	nav: NavService,
	res: Dictionary,
	what: String,
	from_xz: Vector2i,
	from_y: int,
	to_xz: Vector2i,
	to_y: int,
	budget: int = ROUTE_BUDGET
) -> NavPathResult:
	if not _stands_on(from_xz, from_y - 1):
		_fail("FAIL %s: nothing to stand on at the start %s, Y=%d" % [what, from_xz, from_y - 1])
		return null
	if not _stands_on(to_xz, to_y - 1):
		_fail("FAIL %s: nothing to stand on at the goal %s, Y=%d" % [what, to_xz, to_y - 1])
		return null
	var origin: Vector3i = res["origin_vox"]
	var a := _world(origin, from_xz.x, from_y, from_xz.y)
	var b := _world(origin, to_xz.x, to_y, to_xz.y)
	var path := nav.find_path_now(NavProfile.Id.PEDESTRIAN, a, b, budget)
	## PARTIAL is a failure here even though an agent would happily walk it. It means one of
	## two things — the goal is unreachable, or the search ran out of expansions before it got
	## there — and the two are told apart by how much of the budget was spent.
	if not path.is_complete():
		_fail(
			"FAIL %s: no pedestrian route %s → %s (%s, %d nodes expanded of %d allowed)"
			% [what, from_xz, to_xz, path.status_name(), path.expanded, budget]
		)
		return null
	var tol := VOXEL_SIZE * 3.0
	var off_a := path.points[0].distance_to(a)
	var off_b := path.points[path.points.size() - 1].distance_to(b)
	if off_a > tol or off_b > tol:
		_fail(
			(
				"FAIL %s: the route runs %.1f m off the start and %.1f m off the goal —"
				+ " nav snapped %s → %s onto spans it could reach instead"
			)
			% [what, off_a, off_b, from_xz, to_xz]
		)
		return null
	return path


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func _check_determinism(coord: Vector2i, planner: DistrictPlanner, layout: CastleLayout) -> void:
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": _world_seed,
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL second bake: %s" % res.get("error", "?"))
		return
	var p2: DistrictPlanner = res["planner"]
	if p2.large_castle != planner.large_castle:
		_fail(
			"FAIL castle rect not deterministic: %s then %s"
			% [planner.large_castle, p2.large_castle]
		)
		return
	var again := (res["generator"] as DistrictGenerator).get_castle_layout()
	if again == null:
		_fail("FAIL the second bake produced no castle layout")
		return
	if not layout.matches(again):
		_fail(
			"FAIL the castle is not deterministic:\n  %s\n  %s"
			% [layout.describe(), again.describe()]
		)
		return
	print("determinism: two bakes of %s planned the same fortress" % coord)


# ---------------------------------------------------------------------------
# Distinctness across seeds
# ---------------------------------------------------------------------------

## The actual deliverable of the phase: two seeds have to produce dungeons a player would
## describe differently, not one plan with the walls moved.
##
## So it is measured rather than asserted. Six castles are planned and the numbers a player
## would notice are tabulated — which routes down exist, how many chambers there are and how
## they are distributed between levels, the wide/small split, whether there are vaulted halls,
## how the levels are stitched together. A generator that returned the same six rows would
## pass every other assertion in this file, which is why this one exists.
##
## Nav is not baked here. These bakes are about the plan, and the geometry the plan produces
## is what every check above already walks through.
func _check_distinctness() -> void:
	var seeds: Array[int] = []
	var coords: Array[Vector2i] = []
	var s := 1
	while seeds.size() < DISTINCT_SEEDS and s <= DISTINCT_SEED_MAX:
		var c := DistrictTheme.find_coord_for_theme(s, DistrictTheme.CASTLE, MAX_RING)
		if DistrictTheme.for_district(s, c).id == DistrictTheme.CASTLE:
			seeds.append(s)
			coords.append(c)
		s += 1
	if seeds.size() < DISTINCT_SEEDS:
		_fail(
			"FAIL only %d of world seeds 1..%d put a Castle in ring 0..%d"
			% [seeds.size(), DISTINCT_SEED_MAX, MAX_RING]
		)
		return
	var masks: Dictionary[int, bool] = {}
	var shapes: Dictionary[String, bool] = {}
	var moats := 0
	var wets := 0
	var rooms: Array[int] = []
	var talls: Array[int] = []
	var flights: Array[int] = []
	var smalls: Array[int] = []
	var wides: Array[int] = []
	var doors: Array[int] = []
	var loops: Array[int] = []
	var tallest := 0
	print("distinctness across %d seeds:" % seeds.size())
	for i in range(seeds.size()):
		var res: Dictionary = DistrictBakeJobScript.bake({
			"coord": coords[i],
			"world_seed": seeds[i],
		})
		if not bool(res.get("ok", false)):
			_fail("FAIL bake of seed %d: %s" % [seeds[i], res.get("error", "?")])
			return
		var l := (res["generator"] as DistrictGenerator).get_castle_layout()
		if l == null:
			_fail("FAIL seed %d baked a Castle district with no castle layout" % seeds[i])
			return
		var per_level: Array[String] = []
		for lv in range(l.dungeon_levels):
			per_level.append("%d" % l.dungeon_vaults_on(lv).size())
		## The ditch and the gardens are dug and planted here as well, so the first seed of
		## each kind is checked voxel by voxel rather than bought a bake of its own.
		if l.has_moat:
			moats += 1
			if l.moat_wet:
				wets += 1
			if not _moat_checked.has(l.moat_wet):
				_moat_checked[l.moat_wet] = true
				_check_moat_voxels(seeds[i], res, l)
		_check_gardens("seed %d" % seeds[i], res, l)
		if _failed:
			return
		print(
			(
				"  seed %2d %s: routes=%-26s rooms=%3d [%-8s] wide=%2d small=%2d"
				+ " tall=%d(%s) flights=%d bays=%2d grain=%d/%d"
			)
			% [
				seeds[i],
				coords[i],
				l.dungeon_entry_names(),
				l.dungeon_vaults.size(),
				"/".join(per_level),
				l.dungeon_wide_count(),
				l.dungeon_small_count(),
				l.dungeon_tall_count(),
				_tall_spans(l) if l.dungeon_tall_count() > 0 else "-",
				l.dungeon_stairs.size(),
				l.dungeon_bays.size(),
				l.dungeon_bay_min,
				l.dungeon_room_min,
			]
		)
		## The dungeon's lane claims compete with the keep's for the same plate, so every seed
		## is checked for a keep that still works as well as for a dungeon that differs.
		_check_keep_tree("seed %d" % seeds[i], l)
		## And for a dungeon whose chambers still form one graph from every route down — the
		## nav walk only ever ran on one seed, so a sealed vault elsewhere went unnoticed.
		_check_dungeon_tree("seed %d" % seeds[i], l)
		## And for doors that fit. A leaf is sized off its opening, so a seed that rolls an
		## opening no other seed produced is the one that would hang a door through a wall.
		_check_door_plan("seed %d" % seeds[i], l)
		if _failed:
			return
		doors.append(l.doorways().size())
		loops.append(l.doorway_link_count(CastleDoorway.LINK_LOOP))
		## A leaf fills its opening, so the tallest opening any seed rolls is the tallest door
		## the game will show. Reported rather than asserted: what "too tall to read as a door"
		## means is a judgement, and this is the number to judge it on.
		for d: CastleDoorway in l.doorways():
			tallest = maxi(tallest, d.height)
		if l.dungeon_entries.is_empty():
			_fail("FAIL seed %d planned a dungeon with no way in" % seeds[i])
			return
		if l.dungeon_stairs.is_empty():
			_fail("FAIL seed %d planned a dungeon with no flight between levels" % seeds[i])
			return
		if l.dungeon_wide_count() == 0 or l.dungeon_small_count() == 0:
			_fail(
				"FAIL seed %d has %d wide and %d small chambers — both are asked for"
				% [seeds[i], l.dungeon_wide_count(), l.dungeon_small_count()]
			)
			return
		masks[l.dungeon_entry_mask()] = true
		shapes[
			"%d|%s|%d|%d|%d|%d"
			% [
				l.dungeon_entry_mask(),
				"/".join(per_level),
				l.dungeon_wide_count(),
				l.dungeon_small_count(),
				l.dungeon_tall_count(),
				l.dungeon_stairs.size(),
			]
		] = true
		rooms.append(l.dungeon_vaults.size())
		talls.append(l.dungeon_tall_count())
		flights.append(l.dungeon_stairs.size())
		smalls.append(l.dungeon_small_count())
		wides.append(l.dungeon_wide_count())
	rooms.sort()
	print(
		(
			"spread: %d distinct entrance mixes, %d distinct dungeon shapes of %d seeds,"
			+ " rooms %d..%d, tall %d..%d, inter-level flights %d..%d,"
			+ " wide %d..%d, small %d..%d, doors %d..%d (loops %d..%d, tallest %d courses)"
		)
		% [
			masks.size(),
			shapes.size(),
			seeds.size(),
			rooms[0],
			rooms[rooms.size() - 1],
			talls.min(),
			talls.max(),
			flights.min(),
			flights.max(),
			wides.min(),
			wides.max(),
			smalls.min(),
			smalls.max(),
			doors.min(),
			doors.max(),
			loops.min(),
			loops.max(),
			tallest,
		]
	)
	if masks.size() < 3:
		_fail(
			"FAIL %d seeds produced only %d entrance mixes — the routes down are not varying"
			% [seeds.size(), masks.size()]
		)
		return
	if shapes.size() < seeds.size():
		_fail(
			"FAIL %d of %d seeds produced the same dungeon shape"
			% [seeds.size() - shapes.size() + 1, seeds.size()]
		)
		return
	print(
		"moats: %d of %d seeds dug one (%d wet, %d dry), %d garden props stamped in all"
		% [moats, seeds.size(), wets, moats - wets, _garden_props]
	)
	if wets == 0 or moats == wets:
		_fail(
			"FAIL %d seeds produced %d wet and %d dry moats — both kinds are asked for"
			% [seeds.size(), wets, moats - wets]
		)
		return
	if moats == seeds.size():
		_fail("FAIL every one of %d seeds dug a moat — a castle without one is the other half"
			% seeds.size())
		return
	if talls.max() == 0:
		_fail("FAIL not one of %d seeds produced a tall vaulted chamber" % seeds.size())
		return
	if rooms[rooms.size() - 1] - rooms[0] < rooms[0] / 4:
		_fail(
			"FAIL every seed has between %d and %d chambers — the grain is not varying"
			% [rooms[0], rooms[rooms.size() - 1]]
		)


# ---------------------------------------------------------------------------
# Moat and gardens
# ---------------------------------------------------------------------------

## The ditch, measured in the voxels rather than trusted from the plan: it has to be a
## barrier from the castle's side and a way out on the city's, it must not cut into the
## world floor or into the dungeon behind the scarp, and a wet one has to hold water at the
## meadow's level and nowhere above it.
func _check_moat_voxels(seed_no: int, res: Dictionary, l: CastleLayout) -> void:
	var keep := _volume
	_volume = (res["generator"] as DistrictGenerator).get_offline_volume()
	var deck := int(res["ground_thickness"])
	_check_moat_section(seed_no, l, deck)
	_check_moat_scarp(seed_no, l, deck)
	_check_moat_water(seed_no, l, deck)
	_check_bridge_voxels(seed_no, l)
	## The approach has to stay one continuous walkable line now that a ditch is cut across
	## it, which is exactly what this already measures — over the bridge this time.
	_check_causeway(l)
	_volume = keep


## One ray per side, from the lip of the ditch to the scarp. Every step down is a single
## voxel — a two-voxel riser bakes as a one-way drop and anything that falls in is stuck —
## and the bed sits where the plan put it, clear of the world floor.
func _check_moat_section(seed_no: int, l: CastleLayout, deck: int) -> void:
	if l.moat_bed_y < 1:
		_fail(
			"FAIL seed %d dug the moat bed to Y=%d — Y0 is the world floor"
			% [seed_no, l.moat_bed_y]
		)
		return
	var inner := l.moat_inner_rect()
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at := _moat_ray_start(l, step)
		if at.x < 0:
			_fail("FAIL seed %d: no place to sample the moat off the %s side" % [seed_no, step])
			return
		var prev := deck
		var reached := false
		while not inner.has_point(at):
			if _vox(at.x, 0, at.y) == VoxelMaterial.AIR:
				_fail("FAIL seed %d cut the world floor away under the moat at %s"
					% [seed_no, at])
				return
			var floor_y := _moat_floor_y(at, l)
			if floor_y > prev:
				_fail(
					"FAIL seed %d: the moat bed rises from Y=%d to Y=%d at %s on the way in"
					% [seed_no, prev, floor_y, at]
				)
				return
			if prev - floor_y > 1:
				_fail(
					"FAIL seed %d has a %d voxel drop into the moat at %s — the counterscarp"
					% [seed_no, prev - floor_y, at]
					+ " has to be walkable steps"
				)
				return
			reached = reached or floor_y == l.moat_bed_y
			prev = floor_y
			at += step
		if not reached:
			_fail(
				"FAIL seed %d: the ray toward %s never reached the planned bed Y=%d"
				% [seed_no, step, l.moat_bed_y]
			)
			return


## Where to start a cross-section on one side of the ditch: on the lip, somewhere along the
## side that the bridge does not cross. The middle is the honest place to sample, so it is
## tried first and the quarter points are the fallback for the side the gate faces.
func _moat_ray_start(l: CastleLayout, step: Vector2i) -> Vector2i:
	var outer := l.moat_rect
	var along := outer.size.y if step.x != 0 else outer.size.x
	var lo := outer.position.y if step.x != 0 else outer.position.x
	var clear := l.causeway_hw + 3
	var axis := l.gate_center.y if step.x != 0 else l.gate_center.x
	for f: float in [0.5, 0.25, 0.75]:
		var t := lo + int(float(along) * f)
		if absi(t - axis) <= clear:
			continue
		if step.x > 0:
			return Vector2i(outer.position.x, t)
		if step.x < 0:
			return Vector2i(outer.end.x - 1, t)
		if step.y > 0:
			return Vector2i(t, outer.position.y)
		return Vector2i(t, outer.end.y - 1)
	return Vector2i(-1, -1)


## The castle side of the ditch is masonry from the bed to the lip, with nothing behind it:
## an opening here would be a hole from the moat straight into the dungeon.
func _check_moat_scarp(seed_no: int, l: CastleLayout, deck: int) -> void:
	var inner := l.moat_inner_rect()
	var ashlar := 0
	var checked := 0
	for z in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			if x != inner.position.x and x != inner.end.x - 1:
				if z != inner.position.y and z != inner.end.y - 1:
					continue
			for y in range(l.moat_bed_y, deck):
				checked += 1
				var id := _vox(x, y, z)
				if id == VoxelMaterial.AIR:
					_fail(
						"FAIL seed %d: the moat scarp at (%d,%d) opens at Y=%d"
						% [seed_no, x, z, y]
					)
					return
				if id == VoxelMaterial.CASTLE_BLOCK:
					ashlar += 1
	if ashlar * 2 < checked:
		_fail(
			"FAIL seed %d revetted only %d of %d scarp voxels in ashlar"
			% [seed_no, ashlar, checked]
		)


## A wet ditch is full to the meadow's level and no higher; a dry one holds no water at all.
func _check_moat_water(seed_no: int, l: CastleLayout, deck: int) -> void:
	var outer := l.moat_rect
	var inner := l.moat_inner_rect()
	var surface := 0
	var spill := 0
	var below := 0
	for z in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			if inner.has_point(Vector2i(x, z)):
				continue
			if _vox(x, deck, z) == VoxelMaterial.WATER:
				surface += 1
			if _vox(x, deck + 1, z) == VoxelMaterial.WATER:
				spill += 1
			if _vox(x, l.moat_bed_y, z) == VoxelMaterial.WATER:
				below += 1
	print(
		"  moat seed %d: %s, bed Y=%d, %d water columns at the deck"
		% [seed_no, "wet" if l.moat_wet else "dry", l.moat_bed_y, surface]
	)
	if spill > 0:
		_fail("FAIL seed %d has %d water voxels above the deck" % [seed_no, spill])
		return
	if below > 0:
		_fail(
			"FAIL seed %d flooded the moat bed itself at %d columns — the bed is the floor"
			% [seed_no, below]
		)
		return
	if l.moat_wet:
		## A ring 12..18 voxels thick around a fortress is thousands of columns; a tenth of
		## the ring's area is a floor, not a target.
		var ring := outer.size.x * outer.size.y - inner.size.x * inner.size.y
		if surface * 10 < ring:
			_fail(
				"FAIL seed %d flooded only %d of %d moat columns" % [seed_no, surface, ring]
			)
	elif surface > 0:
		_fail("FAIL seed %d left %d water columns in a dry moat" % [seed_no, surface])


## The crossing: planking over the gap and the drawbridge's winch posts standing over it.
## That the deck is *walkable* is `_check_causeway`'s job — it walks the same line.
func _check_bridge_voxels(seed_no: int, l: CastleLayout) -> void:
	var edge: Vector2i = l.causeway_line[l.causeway_line.size() - 1]
	var planks := 0
	var leaf := 0
	for s in range(l.bridge_from, l.bridge_to + 1):
		var at := edge + l.gate_dir * s
		var y := _surface_y(at)
		if _vox(at.x, y, at.y) != VoxelMaterial.TIMBER:
			_fail(
				"FAIL seed %d: station %d of the bridge is %d at Y=%d, not planking"
				% [seed_no, s, _vox(at.x, y, at.y), y]
			)
			return
		planks += 1
		if l.drawbridge_rect.has_point(at):
			leaf += 1
	if leaf < 2:
		_fail("FAIL seed %d planked no drawbridge leaf into the crossing" % seed_no)
		return
	print(
		"  bridge seed %d: %d planked stations %d..%d, %d of them the leaf"
		% [seed_no, planks, l.bridge_from, l.bridge_to, leaf]
	)


## Topmost solid voxel of a column in the ditch. Water is what the moat holds, not what it
## stands on, so the terrace check has to look past it.
func _moat_floor_y(at: Vector2i, l: CastleLayout) -> int:
	for y in range(PROBE_Y_MAX, l.moat_bed_y - 1, -1):
		var id := _vox(at.x, y, at.y)
		if id != VoxelMaterial.AIR and id != VoxelMaterial.WATER:
			return y
	_fail("FAIL the moat column %s has no floor above Y=%d" % [at, l.moat_bed_y])
	return l.moat_bed_y


## Gardens, as planted rather than as planned: walks, hedges or planters where the plot says
## there are some, props standing in them, and nothing laid out on top of the fortress.
## Also: meadow plots must cover a real share of the open reserve, and leftover turf gets trees.
func _check_gardens(what: String, res: Dictionary, l: CastleLayout) -> void:
	if l.gardens.is_empty():
		_fail("FAIL %s laid out no garden at all — even a tight reserve has a bailey" % what)
		return
	var keep := _volume
	_volume = (res["generator"] as DistrictGenerator).get_offline_volume()
	var meadow_area := 0
	var meadow_plots := 0
	for g: CastleGarden in l.gardens:
		if g.kind != CastleGarden.KIND_PRIVY and g.rect.intersects(l.plinth_rect):
			_fail("FAIL %s put the %s garden %s on the fortress" % [what, g.kind_name(), g.rect])
			_volume = keep
			return
		if l.has_moat and g.kind != CastleGarden.KIND_PRIVY and g.rect.intersects(l.moat_rect):
			_fail("FAIL %s put the %s garden %s in the ditch" % [what, g.kind_name(), g.rect])
			_volume = keep
			return
		if g.kind != CastleGarden.KIND_PRIVY:
			meadow_area += g.rect.get_area()
			meadow_plots += 1
		var counts := _garden_counts(g)
		_garden_props += int(counts["props"])
		if int(counts["props"]) < 4:
			_fail(
				"FAIL %s: the %s garden %s got %d props stamped into it"
				% [what, g.kind_name(), g.rect, counts["props"]]
			)
			_volume = keep
			return
		if int(counts["ground"]) < g.rect.size.x:
			_fail(
				"FAIL %s: the %s garden %s has %d voxels of walk, bed or planter"
				% [what, g.kind_name(), g.rect, counts["ground"]]
			)
			_volume = keep
			return
		## An orchard is its trees, and it lays its lanes over the same ground it plants —
		## so it is exactly the plot that can come out as a fenced lawn with gravel stripes
		## and nothing growing on it, while still passing every count above.
		if g.style == GardenComposer.Style.ORCHARD and int(counts["trunks"]) < 4:
			_fail(
				"FAIL %s: the orchard %s grew %d trees"
				% [what, g.rect, counts["trunks"]]
			)
			_volume = keep
			return
		if g.style == GardenComposer.Style.PARTERRE and int(counts["hedge"]) == 0:
			_fail("FAIL %s: the parterre %s has no clipped hedge" % [what, g.rect])
			_volume = keep
			return
	var planner: DistrictPlanner = res["planner"]
	var cell := int(res["cell_size"])
	var lc: Rect2i = planner.large_castle
	var reserve_area := lc.get_area() * cell * cell
	var fortress: Rect2i = l.moat_rect if l.has_moat else l.plinth_rect
	var free_area := maxi(reserve_area - fortress.get_area(), 1)
	var share := float(meadow_area) / float(free_area)
	print(
		"%s gardens: %d meadow plots covering %.1f%% of open reserve (%d / %d)"
		% [what, meadow_plots, share * 100.0, meadow_area, free_area]
	)
	if share < 0.25:
		_fail(
			"FAIL %s: meadow gardens cover only %.1f%% of the open reserve (want ≥25%%)"
			% [what, share * 100.0]
		)
		_volume = keep
		return
	var gy := int(res["ground_thickness"])
	var outside_trunks := _count_meadow_trees_outside_gardens(l, gy)
	print("%s meadow dress trees outside formal plots: %d" % [what, outside_trunks])
	if outside_trunks < 3:
		_fail(
			"FAIL %s: leftover meadow has only %d trees outside formal gardens"
			% [what, outside_trunks]
		)
		_volume = keep
		return
	_volume = keep


## Bark trunks on the meadow that do not sit inside any planned garden footprint.
func _count_meadow_trees_outside_gardens(l: CastleLayout, ground_y: int) -> int:
	var fortress: Rect2i = l.moat_rect if l.has_moat else l.plinth_rect
	var trunks := 0
	const STRIDE := 4
	var z := 2
	while z < DistrictCoord.SIZE_Z_VOX - 2:
		var x := 2
		while x < DistrictCoord.SIZE_X_VOX - 2:
			if fortress.has_point(Vector2i(x, z)):
				x += STRIDE
				continue
			var inside := false
			for g: CastleGarden in l.gardens:
				if g.rect.has_point(Vector2i(x, z)):
					inside = true
					break
			if not inside and _vox(x, ground_y + 1, z) == VoxelMaterial.BARK:
				trunks += 1
			x += STRIDE
		z += STRIDE
	return trunks


## Props and made ground inside one plot. Gravel and soil are the parterre's walks and beds,
## planter its raised boxes, yew its hedges — one of them is there in every style.
func _garden_counts(g: CastleGarden) -> Dictionary:
	var props := 0
	var ground := 0
	var hedge := 0
	var trunks := 0
	for z in range(g.rect.position.y, g.rect.end.y):
		for x in range(g.rect.position.x, g.rect.end.x):
			## Counted per column, not per voxel: a trunk is five to seven of these and
			## the question here is how many trees stand in the plot.
			if _vox(x, g.surface_y + 1, z) == VoxelMaterial.BARK:
				trunks += 1
			for y in range(g.surface_y, g.surface_y + 6):
				var id := _vox(x, y, z)
				if RoomPropCatalog.is_prop_id(id) or id == VoxelMaterial.PROP_FOOTPRINT:
					props += 1
				elif id == VoxelMaterial.YEW:
					ground += 1
					hedge += 1
				elif (
					id == VoxelMaterial.GRAVEL
					or id == VoxelMaterial.DIRT
					or id == VoxelMaterial.PLANTER
				):
					ground += 1
	return {"props": props, "ground": ground, "hedge": hedge, "trunks": trunks}


# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

func _vox(x: int, y: int, z: int) -> int:
	return int(_volume.get_vox(Vector3i(x, y, z)))


## Topmost solid voxel of a district-local column.
func _surface_y(at: Vector2i) -> int:
	for y in range(PROBE_Y_MAX, -1, -1):
		if _vox(at.x, y, at.y) != VoxelMaterial.AIR:
			return y
	_fail("FAIL column %s is empty all the way to bedrock" % at)
	return 0


## Highest walkable surface of a column inside [y_lo, y_hi] — solid, with the profile's
## full body height clear above it. A column inside the keep has one of these per storey,
## so the window is what picks out the flight instead of the roof.
func _tread_y(at: Vector2i, y_lo: int, y_hi: int) -> int:
	for y in range(y_hi, y_lo - 1, -1):
		if _vox(at.x, y, at.y) == VoxelMaterial.AIR:
			continue
		if _headroom(at, y) >= MIN_HEAD:
			return y
	return NO_SURFACE


## Walkable surface of a column nearest the one a foot is leaving from.
##
## A flight is walked along its lane rather than probed per column, because a lane column
## genuinely has more than one walkable surface in it. A keep flight arrives through a well in
## the slab above it, so the column at its head is walkable both on the storey it left and the
## one it reaches; a dungeon flight climbs under the slab it is about to pierce, so the column
## at its foot is walkable both on the dungeon floor and on the courtyard datum overhead.
## Neither the topmost nor the lowest surface is the tread — the one nearest the last tread is.
##
## Deliberately reaches further than a pedestrian can step, so a broken flight is reported as
## the riser it measures instead of as a hole with no tread at all.
func _step_y(at: Vector2i, prev: int) -> int:
	if _stands_on(at, prev):
		return prev
	for d in range(1, STEP_REACH + 1):
		if _stands_on(at, prev + d):
			return prev + d
		if _stands_on(at, prev - d):
			return prev - d
	return NO_SURFACE


## Walks one flight tread by tread and measures it, as (worst riser, least tread headroom,
## station of the worst riser). Fails on the way if the lane breaks or if the voxels disagree
## with `CastleStair.surface_at()` — the tread contract the keep's flights and the dungeon's
## are both built to, so a disagreement means something else overwrote the lane.
func _measure_flight(st: CastleStair) -> Vector3i:
	if not _stands_on(st.center_column(0), st.y_from):
		_fail(
			"FAIL %s: nothing to stand on at its own first tread %s, Y=%d"
			% [st.describe(), st.center_column(0), st.y_from]
		)
		return Vector3i.ZERO
	var worst := 0
	var worst_at := 0
	var min_head := 99
	var climb := 0
	var prev := st.y_from
	for t in range(st.run_len()):
		var at := st.center_column(t)
		var y := prev if t == 0 else _step_y(at, prev)
		if y == NO_SURFACE:
			_fail(
				(
					"FAIL %s: no walkable surface within %d voxels of Y=%d at station %d (%s)"
					+ " — the lane breaks there"
				)
				% [st.describe(), STEP_REACH, prev, t, at]
			)
			return Vector3i.ZERO
		if y != st.surface_at(t):
			_fail(
				"FAIL %s: tread %d measures Y=%d, the plan says Y=%d"
				% [st.describe(), t, y, st.surface_at(t)]
			)
			return Vector3i.ZERO
		min_head = mini(min_head, _headroom(at, y))
		if absi(y - prev) > worst:
			worst = absi(y - prev)
			worst_at = t
		climb += y - prev
		prev = y
	if climb != st.rise:
		_fail("FAIL %s climbs %d voxels, not %d" % [st.describe(), climb, st.rise])
		return Vector3i.ZERO
	return Vector3i(worst, min_head, worst_at)


## Walkable-surface map of one storey, relative to its floor: '.' is the floor itself, '+'
## one voxel up, a digit that many voxels away, a blank nothing a body can stand on.
## Printed when an interior route fails, because a coordinate in an error message says
## nothing about which wall or well cut the route.
func _dump_storey(layout: CastleLayout, storey: int) -> void:
	var f := layout.keep_floor(storey)
	var p := layout.keep_plate_rect
	print("--- storey %d floor_y=%d ---" % [storey, f.floor_y])
	for z in range(p.position.y, p.end.y):
		var row := ""
		for x in range(p.position.x, p.end.x):
			var at := Vector2i(x, z)
			var y := _tread_y(at, f.floor_y - 3, f.floor_y + 3)
			if y == NO_SURFACE:
				row += " "
			elif y == f.floor_y:
				row += "."
			elif y == f.floor_y + 1:
				row += "+"
			else:
				row += "%d" % absi(y - f.floor_y)
		print("%4d %s" % [z, row])


## Walkable-surface map of one dungeon level, relative to its floor, in the same notation as
## `_dump_storey`. Printed when a chamber turns out unreachable, because the coordinate in the
## error says nothing about which partition or lane claim sealed it off.
func _dump_level(layout: CastleLayout, level: int) -> void:
	_dump_area(
		"dungeon level %d" % level, layout.dungeon_plate_rect, layout.dungeon_floor_y(level)
	)


func _dump_area(what: String, area: Rect2i, floor_y: int) -> void:
	print("--- %s floor_y=%d %s ---" % [what, floor_y, area])
	for z in range(area.position.y, area.end.y):
		var row := ""
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, z)
			var y := _tread_y(at, floor_y - 3, floor_y + 5)
			if y == NO_SURFACE:
				row += " "
			elif y == floor_y:
				row += "."
			elif y == floor_y + 1:
				row += "+"
			else:
				row += "%d" % absi(y - floor_y)
		print("%4d %s" % [z, row])


## A body can stand on this column at this exact Y: solid under its feet, its full height
## clear above.
func _stands_on(at: Vector2i, surface_y: int) -> bool:
	if _vox(at.x, surface_y, at.y) == VoxelMaterial.AIR:
		return false
	return _headroom(at, surface_y) >= MIN_HEAD


## Clear voxels above a surface, capped so an open-air column does not scan forever.
func _headroom(at: Vector2i, surface_y: int) -> int:
	var n := 0
	while n < MAX_HEAD and surface_y + 1 + n <= PROBE_Y_MAX:
		if _vox(at.x, surface_y + 1 + n, at.y) != VoxelMaterial.AIR:
			break
		n += 1
	return n


## Column of a room a body can stand in, nearest its middle. Rooms legitimately contain a
## stair's solid wedge, so the middle itself is not always free.
##
## The whole 3×3 around it has to be standable too: geodesic clearance is Chebyshev, so it is
## zero in any column touching an unwalkable one — a diagonal neighbour counts — and the
## pedestrian profile needs one cell of it. A probe tucked against a partition, or beside the
## corner of a chest, is a column nav refuses to stand in.
func _room_probe(f: CastleFloor, room: Rect2i) -> Vector2i:
	return _probe_in(room, f.floor_y)


func _vault_probe(v: CastleVault) -> Vector2i:
	return _probe_in(v.rect, v.floor_y)


func _probe_in(room: Rect2i, floor_y: int) -> Vector2i:
	var mid := room.position + room.size / 2
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if not _stands_clear(Vector2i(x, z), floor_y):
				continue
			var dx := x - mid.x
			var dz := z - mid.y
			var d := dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = Vector2i(x, z)
	return best


## Standable with a cell of geodesic clearance all round — nav's pedestrian radius.
func _stands_clear(at: Vector2i, floor_y: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not _stands_on(at + Vector2i(dx, dz), floor_y):
				return false
	return true


## Centre of a district-local voxel in world metres, the way an agent stands in it.
func _world(origin: Vector3i, x: int, y: int, z: int) -> Vector3:
	return Vector3(
		float(origin.x + x) + 0.5, float(origin.y + y), float(origin.z + z) + 0.5
	) * VOXEL_SIZE


func _count_above_deck(blocks: Dictionary, ground_thickness: int) -> Dictionary:
	var counts: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= ground_thickness + 1:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			var uid := int(data[0])
			if uid == VoxelMaterial.AIR:
				continue
			var layers := mini(BLOCK, block_y0 + BLOCK - (ground_thickness + 1))
			if layers > 0:
				counts[uid] = int(counts.get(uid, 0)) + layers * BLOCK * BLOCK
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			if block_y0 + (i % BLOCK) <= ground_thickness:
				continue
			var vid := int(data[i * 2])
			if vid == VoxelMaterial.AIR:
				continue
			counts[vid] = int(counts.get(vid, 0)) + 1
	return counts


func _quit() -> void:
	NavService.reset()
	if _failed:
		## Last line before the verdict, because a failing route dumps a level map far longer
		## than the tail a runner shows — the seed printed at the top has scrolled away by
		## then, and a fuzzed failure nobody can re-bake is only noise.
		print("reproduce with CITY_CASTLE_SEED=%d" % _world_seed)
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
