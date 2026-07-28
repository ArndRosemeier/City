## Bake a Castle-theme district and assert the fortress is walkable: a walled keep on a
## plinth, a courtyard a pedestrian can reach from the street, a keep whose every room on
## every storey a pedestrian can reach from the keep's own door, and a way up to the crown.
##
## The headline assertions are those routes. Everything else here — the vertical budget, the
## gate opening, the one-voxel causeway steps and stair risers, the measured doorway widths
## and ceiling headrooms — exists because a route is the first thing any of them breaks, and
## a measurement says which one broke where a failed path only says "unreachable".
##
## Run: powershell -File tools\run_test.ps1 test_castle_district
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const CastleComposerScript := preload("res://scripts/city/castle_composer.gd")

const WORLD_SEED := 42
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

var _failed := false
var _volume: Object = null


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.CASTLE, MAX_RING)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.CASTLE:
		_fail("FAIL no Castle theme in ring 0..%d for seed %d" % [MAX_RING, WORLD_SEED])
		_quit()
		return
	print("baking Castle district at %s" % coord)

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
		"world_seed": WORLD_SEED,
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
	_volume = gen.get_offline_volume()
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
	_check_keep_shell(layout)
	_check_stair_treads(layout)
	_check_openings(layout)
	_check_rooms(layout)
	if _failed:
		_quit()
		return

	_report_nav_stats(res)
	_check_path_to_courtyard(nav, coord, res, layout)
	_check_flights_walkable(nav, res, layout)
	_check_path_into_keep(nav, res, layout)
	_check_path_to_crown(nav, res, layout)
	_check_every_room_reachable(nav, res, layout)
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

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Planner
# ---------------------------------------------------------------------------

## Castle tiles are street connectors, not neighbourhoods: edge stubs, no interior grid and
## no housing anywhere.
func _check_layout(coord: Vector2i) -> DistrictPlanner:
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
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
					if (
						m != VoxelMaterial.CASTLE_BLOCK
						and m != VoxelMaterial.CASTLE_BLOCK_MOSSY
					):
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
	if _vox(at.x, layout.courtyard_y, at.y) != VoxelMaterial.CASTLE_BLOCK:
		_fail(
			"FAIL the middle of the bailey is %d at Y=%d, not castle block"
			% [_vox(at.x, layout.courtyard_y, at.y), layout.courtyard_y]
		)
		return
	if _vox(at.x, layout.courtyard_y + 1, at.y) != VoxelMaterial.AIR:
		_fail("FAIL the bailey is roofed over at Y=%d" % (layout.courtyard_y + 1))
		return
	var hollow := 0
	for y in range(ground_thickness + 1, layout.courtyard_y):
		if _vox(at.x, y, at.y) == VoxelMaterial.AIR:
			hollow += 1
	if hollow > 0:
		_fail(
			"FAIL %d voxels of the plinth column under the bailey are already air"
			% hollow
		)
		return
	print(
		"budget: courtyard Y=%d over a solid %d voxel plinth, dungeon band Y%d..%d reserved"
		% [
			layout.courtyard_y,
			layout.courtyard_y - ground_thickness,
			layout.dungeon_y0,
			layout.dungeon_y1,
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
	var dug := 0
	for y2 in range(layout.dungeon_y0, layout.dungeon_y1 + 1):
		for z in range(kr.position.y, kr.end.y):
			for x in range(kr.position.x, kr.end.x):
				if _vox(x, y2, z) == VoxelMaterial.AIR:
					dug += 1
	if dug > 0:
		_fail(
			"FAIL the keep footprint has %d air voxels in the reserved dungeon band Y%d..%d"
			% [dug, layout.dungeon_y0, layout.dungeon_y1]
		)
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
		var prev := NO_SURFACE
		var climb := 0
		for t in range(st.run_len()):
			var at := st.center_column(t)
			var y := _tread_y(at, st.y_from, st.top_y())
			if y == NO_SURFACE:
				_fail(
					"FAIL %s has no walkable tread at station %d (%s)"
					% [st.describe(), t, at]
				)
				return
			if y != st.surface_at(t):
				_fail(
					"FAIL %s: tread %d measures Y=%d, the plan says Y=%d"
					% [st.describe(), t, y, st.surface_at(t)]
				)
				return
			min_head = mini(min_head, _headroom(at, y))
			if prev != NO_SURFACE:
				var step := absi(y - prev)
				climb += y - prev
				if step > worst:
					worst = step
					worst_on = "%s station %d" % [st.describe(), t]
			prev = y
		if climb != st.rise:
			_fail("FAIL %s climbs %d voxels, not %d" % [st.describe(), climb, st.rise])
			return
		if st.lane_w < MIN_WALK_W:
			_fail("FAIL %s is only %d voxels wide" % [st.describe(), st.lane_w])
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
	var through := false
	var mouth := _world(
		origin, layout.gate_center.x, layout.courtyard_y + 1, layout.gate_center.y
	)
	var reach := float(layout.gate_width) * VOXEL_SIZE * 2.0
	for i in range(1, path.points.size()):
		var near := Geometry3D.get_closest_point_to_segment(
			mouth, path.points[i - 1], path.points[i]
		)
		if near.distance_to(mouth) <= reach:
			through = true
			break
	if not through:
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
			worst_raw = maxi(worst_raw, path.raw_points)
	print(
		"reachability: all %d keep rooms reachable from the entrance %s (worst search %d)"
		% [checked, inside, worst_raw]
	)


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
	to_y: int
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
	var path := nav.find_path_now(NavProfile.Id.PEDESTRIAN, a, b)
	if not path.is_usable():
		_fail(
			"FAIL %s: no pedestrian route %s → %s (%s)"
			% [what, from_xz, to_xz, path.status_name()]
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
		"world_seed": WORLD_SEED,
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
## The four neighbours have to be standable too: geodesic clearance is zero in any column
## touching an unwalkable one, and the pedestrian profile needs one cell of it, so a probe
## tucked against a partition would be a column nav refuses to stand in.
func _room_probe(f: CastleFloor, room: Rect2i) -> Vector2i:
	var mid := room.position + room.size / 2
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if not _stands_on(Vector2i(x, z), f.floor_y):
				continue
			if not _stands_on(Vector2i(x - 1, z), f.floor_y):
				continue
			if not _stands_on(Vector2i(x + 1, z), f.floor_y):
				continue
			if not _stands_on(Vector2i(x, z - 1), f.floor_y):
				continue
			if not _stands_on(Vector2i(x, z + 1), f.floor_y):
				continue
			var dx := x - mid.x
			var dz := z - mid.y
			var d := dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = Vector2i(x, z)
	return best


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
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
