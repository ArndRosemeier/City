## Pins the dynamic half of the write funnel: a live voxel edit published through CityBrush
## turns into a budgeted sector rebuild, bumps the nav version, and makes exactly the paths
## that cross the rebuilt columns read stale.
##
## The world is hand-painted twice — once into an offline volume for the district bake, once
## into the live terrain through a brush — so the field and the terrain start out agreeing
## and every later difference is the edit under test.
##
## This node joins the `city_root` group and answers `voxel_brush()`, which is how the real
## CityRoot publishes its brush, so the tracker's own attachment path is what gets tested.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_nav_dirty_rebuild.tscn
extends Node

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
## A district coordinate no other nav test bakes, so the registry cannot collide.
const DISTRICT := Vector2i(3, 3)
## Live terrain Y size (exclusive). Must cover FIELD_Y_MAX + link_reach_y headroom.
const TERRAIN_HEIGHT_VOX := 256
## Deep enough that headroom is never the reason a span is missing.
const FIELD_Y_MAX := 47
## Four sectors square: room for two routes and for sectors the edits must not touch.
const FIELD_X := 112
const FIELD_Z := 112

## Sheer brick wall splitting the deck, with two 3 m gaps in it.
const WALL_X := 56
const WALL_TOP := 9
const GAP_A_Z0 := 28
const GAP_A_Z1 := 34
const GAP_B_Z0 := 84
const GAP_B_Z1 := 90

## Straddles the sector border at local x 84, well clear of both routes.
const BLAST_X := 84
const BLAST_Z := 14
## 3 m across at 0.5 m voxels.
const BLAST_RADIUS := 6

## A pillar in a sector no other edit in this file reaches, so the cascade's regions are
## unmistakably its own.
const PILLAR_X := 20
const PILLAR_Z := 100
const PILLAR_TOP := 6

const ROUTE_Z := 31
const ROUTE_FROM_X := 10
const ROUTE_TO_X := 100
## Well inside sector (0, 0), more than the staleness margin away from the wall.
const QUIET_FROM := Vector3i(4, 1, 4)
const QUIET_TO := Vector3i(20, 1, 20)

const PATH_BUDGET := 400000

## What a budgeted drain costs beyond the rebuild units themselves: walking the queue and
## publishing the profiler counters. Measured in tens of microseconds, so this is a ceiling
## on bookkeeping rather than a budget for it.
const DRAIN_OVERHEAD_USEC := 250

var _origin: Vector3i = Vector3i.ZERO
var _terrain: VoxelTerrain
var _tool: VoxelTool
var _brush: CityBrush
var _nav: NavService
var _cascade_aabbs: Array[AABB] = []
var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


## The seam CityRoot publishes. NavDirtyTracker finds it through the group.
func voxel_brush() -> CityBrush:
	return _brush


func _ready() -> void:
	add_to_group("city_root")
	_origin = DistrictCoord.origin_vox(DISTRICT)
	CityVoxelNativeScript.require_loaded()
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		_quit()
		return

	if not _check_margin():
		_quit()
		return

	await _make_terrain()
	if _failed:
		_quit()
		return
	_paint_world()
	if not _register_field():
		_quit()
		return
	if not _check_y_band():
		_quit()
		return

	## One frame for the tracker to find this node's brush through the group.
	await get_tree().process_frame
	if not _nav.dirty().is_attached():
		_fail("FAIL the dirty tracker never attached to the published brush")
		_quit()
		return
	if _nav.dirty().regions_queued() != 0:
		_fail("FAIL %d regions queued before the first edit" % _nav.dirty().regions_queued())
		_quit()
		return
	print("tracker attached to the city_root brush, queue empty")

	await _test_block_the_route()
	if _failed:
		_quit()
		return
	await _test_destructive_blast()
	if _failed:
		_quit()
		return
	await _test_split_budget()
	if _failed:
		_quit()
		return
	_test_coalescing()
	if _failed:
		_quit()
		return
	await _test_budget()
	if _failed:
		_quit()
		return
	_test_district_straddle()
	if _failed:
		_quit()
		return
	await _test_brush_replacement()
	if _failed:
		_quit()
		return
	await _test_cascade_signal()
	if _failed:
		_quit()
		return
	_test_full_district_cost()
	if _failed:
		_quit()
		return
	await _test_band_past_terrain_ceiling()
	if _failed:
		_quit()
		return

	if _nav.dirty().skipped_unloaded() != 0:
		_fail("FAIL %d regions found the terrain unloaded" % _nav.dirty().skipped_unloaded())
		_quit()
		return
	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Context margin
# ---------------------------------------------------------------------------

## The tracker copies a fixed margin of untouched world around every region because the
## bake's links reach that far. Rust refuses a short box loudly, but only for the sectors a
## region happens to touch, so pin the two numbers together here instead of finding out
## from a region that never rebuilt.
func _check_margin() -> bool:
	var probe := CityVoxelNativeScript.make_nav_world() as NativeNavWorld
	var tables := _nav.solidity_tables()
	probe.configure(
		VOXEL_SIZE,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	var reach := int(probe.link_reach_vox())
	if NavDirtyTracker.MARGIN_VOX != reach:
		_fail(
			"FAIL the tracker copies %d columns of context, the bake reaches %d"
			% [NavDirtyTracker.MARGIN_VOX, reach]
		)
		return false
	print("context margin: %d columns, matching the link reach of the bake" % reach)
	return true


## The rebuild reads the rows the field was baked over plus what the link probes reach above
## them. Registration is where NavService learns the band; if it ever stopped doing so the
## copy would fall back to nothing at all, so this pins the band against the bake.
func _check_y_band() -> bool:
	var band := _nav.dirty().district_y_band(DISTRICT)
	if band.x != 0 or band.y <= FIELD_Y_MAX or band.y >= FIELD_Y_MAX + 32:
		_fail(
			"FAIL district %s reports nav rows %d..%d for a field baked over 0..%d"
			% [str(DISTRICT), band.x, band.y, FIELD_Y_MAX]
		)
		return false
	var rows := band.y - band.x + 1
	print(
		"nav Y band: rows %d..%d (%d rows; terrain ceiling %d)"
		% [band.x, band.y, rows, TERRAIN_HEIGHT_VOX]
	)
	return true


## Regression: the live terrain ceiling used to truncate the material copy below
## `rebuild_y_range` (field.y_max + link_reach_y). Native then refused the short box and
## GDScript reported "rebuilt no sector". Shrink the terrain under a registered band, copy
## materials, require the full band, then drain a real edit through rebuild_region.
func _test_band_past_terrain_ceiling() -> void:
	var band := _nav.dirty().district_y_band(DISTRICT)
	if band.y < band.x:
		_fail("FAIL no nav Y band before ceiling regression")
		return
	## Ceiling ends at field.y_max (exclusive of link headroom): the old clamp produced
	## exactly that short box.
	var short_top := FIELD_Y_MAX
	if short_top >= band.y:
		_fail(
			"FAIL cannot reproduce short ceiling: terrain top %d >= band %d"
			% [short_top, band.y]
		)
		return
	var saved_bounds := _terrain.bounds
	_terrain.bounds = AABB(
		Vector3(float(_origin.x) - 512.0, 0.0, float(_origin.z) - 512.0),
		Vector3(1536.0, float(short_top + 1), 1536.0)
	)
	## Shrinking the ceiling can unload blocks; wait until the pillar columns are editable.
	var wait_box := AABB(
		Vector3(float(_origin.x + PILLAR_X - 4), 0.0, float(_origin.z + PILLAR_Z - 4)),
		Vector3(24.0, float(short_top + 1), 24.0)
	)
	var ready := false
	for _i in range(600):
		await get_tree().process_frame
		if _tool.is_area_editable(wait_box):
			ready = true
			break
	if not ready:
		_terrain.bounds = saved_bounds
		_fail("FAIL short-ceiling terrain never became editable again")
		return
	var probe := NavDirtyRegion.from_columns(
		DISTRICT,
		_origin.x + PILLAR_X,
		_origin.z + PILLAR_Z,
		_origin.x + PILLAR_X,
		_origin.z + PILLAR_Z
	)
	if not _nav.dirty().fill_materials(probe):
		_terrain.bounds = saved_bounds
		_fail("FAIL fill_materials refused a short-ceiling copy")
		return
	var box_y0 := probe.box_min.y
	var box_y1 := probe.box_min.y + probe.box_size.y - 1
	probe.drop_materials()
	if box_y0 > band.x or box_y1 < band.y:
		_terrain.bounds = saved_bounds
		_fail(
			"FAIL short-ceiling copy carried rows %d..%d, district needs %d..%d"
			% [box_y0, box_y1, band.x, band.y]
		)
		return
	var before_ver := _nav.version()
	var before_rebuilds := _nav.dirty().rebuilds()
	var before_skipped := _nav.dirty().skipped_unloaded()
	## Local district coords — brush origin is `_origin`.
	_brush.set_vox(Vector3i(PILLAR_X + 8, 1, PILLAR_Z - 8), VoxelMaterial.BRICK)
	var handled := _nav.flush_dirty()
	var skipped_delta := _nav.dirty().skipped_unloaded() - before_skipped
	_terrain.bounds = saved_bounds
	if handled < 1:
		_fail(
			"FAIL short-ceiling flush handled %d units (pending=%d skipped_unloaded+=%d)"
			% [handled, _nav.dirty().pending(), skipped_delta]
		)
		return
	if skipped_delta != 0:
		_fail("FAIL short-ceiling rebuild skipped %d regions as unloaded" % skipped_delta)
		return
	if _nav.dirty().rebuilds() <= before_rebuilds:
		_fail("FAIL short-ceiling edit never rebuilt a sector")
		return
	if _nav.version() <= before_ver:
		_fail("FAIL short-ceiling rebuild did not bump nav_version")
		return
	print(
		"short-ceiling rebuild: terrain top %d, band %d..%d, box %d..%d, nav_version %d→%d"
		% [short_top, band.x, band.y, box_y0, box_y1, before_ver, _nav.version()]
	)


# ---------------------------------------------------------------------------
# The blast that closes a route
# ---------------------------------------------------------------------------

func _test_block_the_route() -> void:
	var from := _world_of(Vector3i(ROUTE_FROM_X, 1, ROUTE_Z))
	var to := _world_of(Vector3i(ROUTE_TO_X, 1, ROUTE_Z))
	var before := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to, PATH_BUDGET)
	if not before.is_complete():
		_fail("FAIL the open route is %s, expected OK" % before.status_name())
		return
	if _used_gap_b(before):
		_fail("FAIL the open route took the far gap instead of the near one")
		return
	var quiet := _nav.find_path_now(
		NavProfile.Id.PEDESTRIAN, _world_of(QUIET_FROM), _world_of(QUIET_TO), PATH_BUDGET
	)
	if not quiet.is_complete():
		_fail("FAIL the corner route is %s, expected OK" % quiet.status_name())
		return
	print(
		"open route: %s length=%.1f m · corner route: %s length=%.1f m · nav_version=%d"
		% [
			before.status_name(),
			before.length_m(),
			quiet.status_name(),
			quiet.length_m(),
			before.nav_version,
		]
	)
	if _nav.is_path_stale(before):
		_fail("FAIL a path was stale the moment it was built")
		return

	## Plug the near gap with the same brick the wall is made of. One begin/end scope, so
	## the whole logical edit arrives as one region.
	var version_before := _nav.version()
	var rebuilds_before := _nav.dirty().rebuilds()
	_brush.begin_edit()
	_brush.fill_box(
		Vector3i(WALL_X, 1, GAP_A_Z0), Vector3i(WALL_X + 1, WALL_TOP, GAP_A_Z1), VoxelMaterial.BRICK
	)
	_brush.end_edit()
	if _nav.dirty().pending() != 1:
		_fail("FAIL the plug queued %d regions, expected 1" % _nav.dirty().pending())
		return
	if _nav.version() != version_before:
		_fail("FAIL the nav version moved before the rebuild ran")
		return

	await get_tree().process_frame
	if _nav.dirty().pending() != 0:
		_fail("FAIL %d regions survived the frame budget" % _nav.dirty().pending())
		return
	if _nav.dirty().rebuilds() != rebuilds_before + 1:
		_fail(
			"FAIL the frame ran %d rebuilds, expected 1"
			% (_nav.dirty().rebuilds() - rebuilds_before)
		)
		return
	if _nav.version() <= version_before:
		_fail("FAIL the rebuild did not bump the nav version (still %d)" % _nav.version())
		return
	print(
		"plug rebuild: %d sectors in %.2f ms (copy %.2f ms) · nav_version %d -> %d"
		% [
			_nav.dirty().sectors_rebuilt(),
			float(_nav.dirty().last_rebuild_usec()) * 0.001,
			float(_nav.dirty().last_copy_usec()) * 0.001,
			version_before,
			_nav.version(),
		]
	)

	if not _nav.is_path_stale(before):
		_fail("FAIL the path through the plugged gap does not read stale")
		return
	if _nav.is_path_stale(quiet):
		_fail("FAIL a route four sectors away was invalidated by the plug")
		return
	print("staleness: the route through the gap is stale, the corner route is not")

	var after := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to, PATH_BUDGET)
	if not after.is_complete():
		_fail("FAIL the reroute is %s, expected OK through the far gap" % after.status_name())
		return
	if not _used_gap_b(after):
		_fail("FAIL the reroute still crosses the wall at the plugged gap")
		return
	if after.length_m() <= before.length_m():
		_fail(
			"FAIL the reroute is %.1f m, no longer than the %.1f m it replaced"
			% [after.length_m(), before.length_m()]
		)
		return
	if _nav.is_path_stale(after):
		_fail("FAIL the fresh path is already stale")
		return
	print(
		"reroute: %s length=%.1f m (was %.1f m) points=%d"
		% [after.status_name(), after.length_m(), before.length_m(), after.points.size()]
	)


## Did the corridor cross the wall through the far gap?
func _used_gap_b(path: NavPathResult) -> bool:
	var wall_x := float(_origin.x + WALL_X) * VOXEL_SIZE
	var gap_b_z := float(_origin.z + GAP_B_Z0) * VOXEL_SIZE
	for p: Vector3 in path.points:
		if p.x >= wall_x and p.z >= gap_b_z:
			return true
	return false


# ---------------------------------------------------------------------------
# Destruction
# ---------------------------------------------------------------------------

## The plan's reference case: a 3 m blast, here punched clean through the deck so the
## columns under it lose their only span. Straddles a sector border on purpose, because that
## is where the rebuild has to fix up portals rather than just spans.
func _test_destructive_blast() -> void:
	var centre := Vector3i(BLAST_X, 0, BLAST_Z)
	var before := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, _world_of(centre), 0.5)
	if not before.found:
		_fail("FAIL there was no deck to blast at %s" % str(centre))
		return
	var spans_before := int(_nav.district_stats(DISTRICT)["spans"])
	var version_before := _nav.version()

	_brush.fill_cylinder(BLAST_X, BLAST_Z, 0, 1, BLAST_RADIUS, VoxelMaterial.AIR)
	if _nav.dirty().pending() != 1:
		_fail("FAIL the blast queued %d regions, expected 1" % _nav.dirty().pending())
		return
	var region: NavDirtyRegion = _nav.dirty().peek_next()
	if region.sectors_x() != 2:
		_fail("FAIL the blast region spans %d sectors in x, expected 2" % region.sectors_x())
		return
	if _nav.dirty().pending_units() != 2:
		_fail(
			"FAIL the two-sector blast is %d rebuild units, expected 2"
			% _nav.dirty().pending_units()
		)
		return

	var rebuilds_before := _nav.dirty().rebuilds()
	var sectors_before := _nav.dirty().sectors_rebuilt()
	var frames := 0
	while _nav.dirty().pending() > 0 and frames < 30:
		await get_tree().process_frame
		frames += 1
	if _nav.dirty().rebuilds() != rebuilds_before + 2 or _nav.dirty().pending() != 0:
		_fail(
			"FAIL the blast ran %d rebuild units and left %d regions"
			% [_nav.dirty().rebuilds() - rebuilds_before, _nav.dirty().pending()]
		)
		return
	if _nav.version() <= version_before:
		_fail("FAIL the blast did not bump the nav version")
		return
	var spans_after := int(_nav.district_stats(DISTRICT)["spans"])
	if spans_after >= spans_before:
		_fail("FAIL the field still holds %d spans over the hole" % spans_after)
		return
	var after := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, _world_of(centre), 0.5)
	if after.found:
		_fail("FAIL the hole still offers footing at y=%.2f m" % after.position.y)
		return
	print(
		(
			"3 m blast across a sector border: %d columns gone, %d sectors over %d frames,"
			+ " worst unit %.2f ms (copy %.2f ms), spans %d -> %d"
		)
		% [
			spans_before - spans_after,
			_nav.dirty().sectors_rebuilt() - sectors_before,
			frames,
			float(_nav.dirty().worst_unit_usec()) * 0.001,
			float(_nav.dirty().last_copy_usec()) * 0.001,
			spans_before,
			spans_after,
		]
	)
	print("  phases: %s" % _phases())


## Where one rebuild unit's time goes, as the extension measured it.
func _phases() -> String:
	var t := _nav.last_rebuild_timing()
	return (
		"spans %.2f · clearance %.2f · links %.2f · inbound %.2f · components %.2f · portals %.2f = %.2f ms"
		% [
			float(t["spans_us"]) * 0.001,
			float(t["clearance_us"]) * 0.001,
			float(t["links_us"]) * 0.001,
			float(t["inbound_us"]) * 0.001,
			float(t["components_us"]) * 0.001,
			float(t["portals_us"]) * 0.001,
			float(t["total_us"]) * 0.001,
		]
	)


# ---------------------------------------------------------------------------
# The frame budget against the largest region the tracker can build
# ---------------------------------------------------------------------------

## The worst case the queue can hand a frame is its largest merged region, and while a region
## was indivisible that was one rebuild of four sectors whatever the budget said. What matters
## is not how long the whole edit takes but what the dearest *frame* costs, so this drives the
## drain explicitly and times every one of them.
##
## Twice: once starved, which is what proves the region is divisible at all, and once at the
## real budget, which is what the game actually pays. An agent queries between the frames as
## well — half of a four sector edit is allowed to be stale, never to be unanswerable.
func _test_split_budget() -> void:
	var corners: Array[Vector2i] = [Vector2i(30, 58), Vector2i(14, 14)]
	for pass_index in range(corners.size()):
		var starved := pass_index == 0
		var budget := 1 if starved else _nav.dirty_budget_usec
		var corner := corners[pass_index]
		for dx: int in [0, NavDirtyRegion.SECTOR_VOX]:
			for dz: int in [0, NavDirtyRegion.SECTOR_VOX]:
				_brush.set_vox(Vector3i(corner.x + dx, 20, corner.y + dz), VoxelMaterial.AIR)
		if _nav.dirty().pending() != 1:
			_fail("FAIL the 2x2 edit queued %d regions" % _nav.dirty().pending())
			return
		var units := _nav.dirty().pending_units()
		if units != 4:
			_fail("FAIL the 2x2 region is %d rebuild units, expected 4" % units)
			return

		var worst_frame := 0
		var frames := 0
		var drained := 0
		while _nav.dirty().pending() > 0 and frames < 30:
			var t0 := Time.get_ticks_usec()
			drained += _nav.drain_dirty(budget)
			worst_frame = maxi(worst_frame, Time.get_ticks_usec() - t0)
			frames += 1
			var mid := _nav.find_path_now(
				NavProfile.Id.PEDESTRIAN,
				_world_of(Vector3i(ROUTE_FROM_X, 1, ROUTE_Z)),
				_world_of(Vector3i(ROUTE_TO_X, 1, ROUTE_Z)),
				PATH_BUDGET
			)
			if not mid.is_usable():
				_fail(
					"FAIL a query after %d of %d units came back %s"
					% [drained, units, mid.status_name()]
				)
				return
		if _nav.dirty().pending() != 0 or drained != units:
			_fail("FAIL the 2x2 region drained %d of %d units" % [drained, units])
			return
		if starved and frames != units:
			_fail(
				"FAIL a 1 us budget ran %d units over %d frames, so the region did not split"
				% [units, frames]
			)
			return
		## A frame starts a unit only while the budget it has left covers the dearest one
		## measured, so it can overrun by at most the amount that estimate was out by, plus
		## the drain's own bookkeeping around the units — the queue walk and the profiler
		## counters, which are not part of a unit's measured cost.
		var worst_unit := _nav.dirty().worst_unit_usec()
		if worst_frame > budget + worst_unit + DRAIN_OVERHEAD_USEC:
			_fail(
				"FAIL the dearest frame cost %.2f ms against a %.2f ms budget and %.2f ms units"
				% [float(worst_frame) * 0.001, float(budget) * 0.001, float(worst_unit) * 0.001]
			)
			return
		print(
			(
				"2x2 region at %.2f ms budget: %d units over %d frames,"
				+ " dearest frame %.2f ms, dearest unit %.2f ms"
			)
			% [
				float(budget) * 0.001,
				units,
				frames,
				float(worst_frame) * 0.001,
				float(worst_unit) * 0.001,
			]
		)
		print("  phases: %s" % _phases())


# ---------------------------------------------------------------------------
# Coalescing and budget
# ---------------------------------------------------------------------------

## A hundred cell writes in one sector must cost one rescan, which is the whole reason a
## blast is affordable.
func _test_coalescing() -> void:
	var queued_before := _nav.dirty().regions_queued()
	var coalesced_before := _nav.dirty().regions_coalesced()
	for i in range(24):
		_brush.set_vox(Vector3i(4 + i % 6, 20, 4 + i / 6), VoxelMaterial.AIR)
	if _nav.dirty().pending() != 1:
		_fail("FAIL 24 writes in one sector queued %d regions" % _nav.dirty().pending())
		return
	var queued := _nav.dirty().regions_queued() - queued_before
	var coalesced := _nav.dirty().regions_coalesced() - coalesced_before
	if queued != 24 or coalesced != 23:
		_fail("FAIL 24 writes reported %d queued and %d coalesced" % [queued, coalesced])
		return
	if _nav.flush_dirty() != 1:
		_fail("FAIL the flush handled more than the one coalesced region")
		return
	print(
		"coalescing: 24 writes in one sector -> 1 rebuild of %d sectors in %.2f ms"
		% [_nav.dirty().last_sectors(), float(_nav.dirty().last_rebuild_usec()) * 0.001]
	)

	## Four separate sectors in a square merge transitively into the largest unit the
	## tracker allows, which is the most expensive single rebuild it can produce.
	for vox: Vector3i in [
		Vector3i(42, 20, 42), Vector3i(70, 20, 42), Vector3i(42, 20, 70), Vector3i(70, 20, 70)
	]:
		_brush.set_vox(vox, VoxelMaterial.AIR)
	if _nav.dirty().pending() != 1:
		_fail("FAIL four sectors in a square queued %d regions" % _nav.dirty().pending())
		return
	var merged: NavDirtyRegion = _nav.dirty().peek_next()
	if merged.sectors_x() != 2 or merged.sectors_z() != 2:
		_fail(
			"FAIL the merged region is %dx%d sectors, expected 2x2"
			% [merged.sectors_x(), merged.sectors_z()]
		)
		return
	if _nav.flush_dirty() != 4:
		_fail("FAIL the merged region did not flush as four units")
		return
	print(
		"coalescing: 4 sectors in a square -> 1 region of 4 units, last %.2f ms (copy %.2f ms)"
		% [
			float(_nav.dirty().last_rebuild_usec()) * 0.001,
			float(_nav.dirty().last_copy_usec()) * 0.001,
		]
	)


## Regions in sectors far enough apart to stay separate must drain one per frame under a
## starved budget, and the pump must never stall on them.
func _test_budget() -> void:
	var far: Array[Vector3i] = [
		Vector3i(4, 20, 4), Vector3i(60, 20, 4), Vector3i(4, 20, 60), Vector3i(60, 20, 60)
	]
	for vox: Vector3i in far:
		_brush.set_vox(vox, VoxelMaterial.AIR)
	if _nav.dirty().pending() != far.size():
		_fail(
			"FAIL %d spread-out writes queued %d regions"
			% [far.size(), _nav.dirty().pending()]
		)
		return
	_nav.dirty_budget_usec = 1
	var rebuilds_before := _nav.dirty().rebuilds()
	await get_tree().process_frame
	if _nav.dirty().rebuilds() != rebuilds_before + 1:
		_fail(
			"FAIL a 1 us budget ran %d rebuilds, expected exactly 1"
			% (_nav.dirty().rebuilds() - rebuilds_before)
		)
		return
	if _nav.dirty().pending() != far.size() - 1:
		_fail("FAIL the starved frame left %d regions" % _nav.dirty().pending())
		return
	var frames := 0
	while _nav.dirty().pending() > 0 and frames < 30:
		await get_tree().process_frame
		frames += 1
	if _nav.dirty().pending() != 0:
		_fail("FAIL %d regions never drained" % _nav.dirty().pending())
		return
	_nav.dirty_budget_usec = NavService.DEFAULT_DIRTY_BUDGET_USEC
	print("budget: %d far-apart regions drained one per frame over %d frames" % [far.size(), frames + 1])


# ---------------------------------------------------------------------------
# District borders
# ---------------------------------------------------------------------------

## One edit can straddle a district border: each side becomes its own region, and the side
## whose tile the nav world does not hold is counted and dropped. That happens whenever a
## tile is still baking or has already streamed out, so it is a counter, not an error.
##
## The edit has to paint material. Clearing to AIR publishes nothing across this border:
## `CityBrush.fill_box` routes AIR through `_clear_box`, which skips cells that are already
## empty, and nothing was ever painted past x=0 — the touched box would end at the border and
## queue one region. The slab is left standing in mid-air, clear of every later probe.
func _test_district_straddle() -> void:
	var skipped_before := _nav.dirty().skipped_unregistered()
	var rebuilds_before := _nav.dirty().rebuilds()
	var version_before := _nav.version()
	_brush.fill_box(Vector3i(-2, 20, 4), Vector3i(3, 21, 7), VoxelMaterial.BRICK)
	if _nav.dirty().pending() != 2:
		_fail(
			"FAIL an edit across the district border queued %d regions, expected 2"
			% _nav.dirty().pending()
		)
		return
	var coords: Array[Vector2i] = []
	for i in range(2):
		coords.append(_nav.dirty().peek_at(i).coord)
	if not coords.has(DISTRICT) or not coords.has(DISTRICT - Vector2i(1, 0)):
		_fail("FAIL the straddling edit landed in districts %s" % str(coords))
		return
	## Only the loaded side is work: the other district is dropped whole rather than a unit
	## at a time, since there is no field to rebuild into.
	if _nav.flush_dirty() != 1:
		_fail("FAIL the flush did not handle the loaded side of the border")
		return
	if _nav.dirty().rebuilds() != rebuilds_before + 1:
		_fail("FAIL the loaded side ran %d rebuilds" % (_nav.dirty().rebuilds() - rebuilds_before))
		return
	if _nav.dirty().skipped_unregistered() != skipped_before + 1:
		_fail("FAIL the unregistered side was not counted as skipped")
		return
	if _nav.version() <= version_before:
		_fail("FAIL the loaded side of the border did not rebuild")
		return
	print("district straddle: 1 side rebuilt, 1 side skipped as unregistered")


# ---------------------------------------------------------------------------
# Regenerated world
# ---------------------------------------------------------------------------

## CityRoot._regenerate() builds a new terrain, a new VoxelTool and a new brush. The tracker
## has to follow it, and let go of the old one.
func _test_brush_replacement() -> void:
	var old := _brush
	_brush = CityBrushScript.new(_tool, _origin) as CityBrush
	await get_tree().process_frame
	old.set_vox(Vector3i(8, 20, 8), VoxelMaterial.AIR)
	if _nav.dirty().pending() != 0:
		_fail("FAIL the tracker still listens to the replaced brush")
		return
	_brush.set_vox(Vector3i(8, 20, 8), VoxelMaterial.AIR)
	if _nav.dirty().pending() != 1:
		_fail("FAIL the tracker did not follow the brush the world replaced")
		return
	_nav.flush_dirty()
	print("brush replacement: the tracker moved to the new brush")


# ---------------------------------------------------------------------------
# The other write path
# ---------------------------------------------------------------------------

## A cascade clears collapsing columns from Rust, picking spread neighbours and canopy
## cells GDScript cannot predict, so it publishes its own `voxels_changed`. The tracker has
## to pick it up out of the city_root group and treat it exactly like a brush edit.
func _test_cascade_signal() -> void:
	var debris_root := Node3D.new()
	debris_root.name = "DebrisRoot"
	add_child(debris_root)
	var cascade = CityVoxelNativeScript.make_cascade_debris()
	cascade.name = "NativeCascadeDebris"
	add_child(cascade)
	var mats: Array = []
	mats.resize(VoxelMaterial.COUNT)
	for i in range(1, VoxelMaterial.COUNT):
		mats[i] = VoxelBlockLibraryScript.debris_material_for(i)
	cascade.call(
		"setup",
		_terrain,
		_tool,
		debris_root,
		VOXEL_SIZE,
		mats,
		VoxelBuffer.CHANNEL_TYPE,
		VoxelTool.MODE_SET,
		VoxelMaterial.AIR
	)
	await get_tree().process_frame
	if not _nav.dirty().is_cascade_attached():
		_fail("FAIL the tracker never found the cascade in the city_root group")
		return

	## A free-standing pillar, far from every other edit, so the collapse cannot spread
	## into the deck it stands on.
	_brush.fill_box(
		Vector3i(PILLAR_X, 1, PILLAR_Z),
		Vector3i(PILLAR_X + 1, PILLAR_TOP, PILLAR_Z + 1),
		VoxelMaterial.BRICK
	)
	_nav.flush_dirty()
	if _nav.dirty().pending() != 0:
		_fail("FAIL the pillar left %d regions queued" % _nav.dirty().pending())
		return

	## Listen in as well, so the AABB contract itself is under test and not just its effect.
	_cascade_aabbs.clear()
	cascade.connect(&"voxels_changed", _on_cascade_voxels_changed)
	var queued_before := _nav.dirty().regions_queued()
	var version_before := _nav.version()
	cascade.call("collapse_column_above", _origin + Vector3i(PILLAR_X, 0, PILLAR_Z))
	var frames := 0
	while frames < 240:
		await get_tree().physics_frame
		frames += 1
		if not _cascade_aabbs.is_empty() and _nav.dirty().pending() == 0:
			break
	if _cascade_aabbs.is_empty():
		_fail("FAIL the cascade cleared the pillar without publishing anything")
		return
	if _nav.dirty().regions_queued() == queued_before:
		_fail("FAIL the tracker ignored the cascade's %d edits" % _cascade_aabbs.size())
		return
	var pillar_x := float(_origin.x + PILLAR_X)
	var pillar_z := float(_origin.z + PILLAR_Z)
	for aabb: AABB in _cascade_aabbs:
		if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
			_fail("FAIL the cascade published an empty region %s" % str(aabb))
			return
		if (
			aabb.position.x > pillar_x
			or aabb.end.x <= pillar_x
			or aabb.position.z > pillar_z
			or aabb.end.z <= pillar_z
		):
			_fail("FAIL the cascade region %s is nowhere near the pillar" % str(aabb))
			return
	if _nav.version() <= version_before:
		_fail("FAIL the cascade never moved the nav version")
		return
	var standing := _nav.nearest_surface(
		NavProfile.Id.PEDESTRIAN, _world_of(Vector3i(PILLAR_X, PILLAR_TOP, PILLAR_Z)), 4.0
	)
	if not standing.found:
		_fail("FAIL nothing to stand on where the pillar used to be")
		return
	if standing.position.y > float(_origin.y + 2) * VOXEL_SIZE:
		_fail(
			"FAIL nav still has footing at y=%.2f m on top of the collapsed pillar"
			% standing.position.y
		)
		return
	print(
		"cascade: %d signals -> %d tracker regions over %d frames, nav_version %d -> %d"
		% [
			_cascade_aabbs.size(),
			_nav.dirty().regions_queued() - queued_before,
			frames,
			version_before,
			_nav.version(),
		]
	)
	cascade.disconnect(&"voxels_changed", _on_cascade_voxels_changed)
	cascade.call("clear_debris")
	cascade.queue_free()
	debris_root.queue_free()
	await get_tree().process_frame


func _on_cascade_voxels_changed(aabb_vox: AABB) -> void:
	_cascade_aabbs.append(aabb_vox)


# ---------------------------------------------------------------------------
# Cost at district scale
# ---------------------------------------------------------------------------

## What one rebuild costs on a field the size of a real tile, because parts of the Rust
## rebuild scale with the whole district rather than with the dirty columns.
##
## The field is baked over all 784 x 560 columns; the live terrain only holds the patch this
## test painted, so the region under test sits inside the patch and its context margin reads
## back exactly the geometry the bake saw.
func _test_full_district_cost() -> void:
	if not _nav.unregister_district(DISTRICT):
		_fail("FAIL could not drop the patch-sized field")
		return
	var t_bake := Time.get_ticks_msec()
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	var offline: CityBrush = CityBrushScript.new() as CityBrush
	offline.use_offline_volume(volume)
	var size := DistrictCoord.size_vox()
	offline.fill_box(Vector3i.ZERO, Vector3i(size.x, 1, size.z), VoxelMaterial.CONCRETE)
	_paint_into(offline)
	## Everything the live patch has taken since: the plugged gap and the blast crater.
	offline.fill_box(
		Vector3i(WALL_X, 1, GAP_A_Z0), Vector3i(WALL_X + 1, WALL_TOP, GAP_A_Z1), VoxelMaterial.BRICK
	)
	offline.fill_disk(BLAST_X, BLAST_Z, 0, BLAST_RADIUS, VoxelMaterial.AIR)
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var tables := _nav.solidity_tables()
	var ok: bool = bake.bake_from_volume(
		volume,
		_origin,
		size.x,
		size.z,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL the district-sized bake was refused")
		return
	if not _nav.register_district(DISTRICT, bake):
		_fail("FAIL NavService refused the district-sized field")
		return
	var stats := _nav.district_stats(DISTRICT)
	print(
		"district-sized field: %d columns, %d spans, %d portals, baked in %d ms"
		% [
			int(stats["columns"]),
			int(stats["spans"]),
			int(stats["portals"]),
			Time.get_ticks_msec() - t_bake,
		]
	)

	## Sector (1, 2) of the patch: nothing but deck, and its margin stays inside the patch.
	_brush.set_vox(Vector3i(42, 20, 70), VoxelMaterial.AIR)
	if _nav.dirty().pending() != 1:
		_fail("FAIL the probe write queued %d regions" % _nav.dirty().pending())
		return
	if _nav.flush_dirty() != 1:
		_fail("FAIL the probe region did not rebuild")
		return
	var usec := _nav.dirty().last_rebuild_usec()
	print(
		"one unit on a district-sized field: %.2f ms (copy %.2f ms)"
		% [float(usec) * 0.001, float(_nav.dirty().last_copy_usec()) * 0.001]
	)
	print("  phases: %s" % _phases())
	## Not a budget: a ceiling that catches the rebuild turning into a whole-district job.
	if usec > 40000:
		_fail("FAIL one region cost %.1f ms on a district-sized field" % (float(usec) * 0.001))
		return


# ---------------------------------------------------------------------------
# World
# ---------------------------------------------------------------------------

## Deck, wall and gaps, painted through a brush nobody listens to yet — this is scenery the
## bake also sees, not an edit under test.
func _paint_world() -> void:
	var setup: CityBrush = CityBrushScript.new(_tool, _origin) as CityBrush
	setup.begin_edit()
	_paint_into(setup)
	setup.end_edit()
	_brush = CityBrushScript.new(_tool, _origin) as CityBrush


## The same geometry the live terrain gets, so the baked field and the terrain agree.
func _paint_into(brush: CityBrush) -> void:
	brush.fill_box(Vector3i.ZERO, Vector3i(FIELD_X, 1, FIELD_Z), VoxelMaterial.CONCRETE)
	brush.fill_box(
		Vector3i(WALL_X, 1, 0), Vector3i(WALL_X + 1, WALL_TOP, GAP_A_Z0), VoxelMaterial.BRICK
	)
	brush.fill_box(
		Vector3i(WALL_X, 1, GAP_A_Z1),
		Vector3i(WALL_X + 1, WALL_TOP, GAP_B_Z0),
		VoxelMaterial.BRICK
	)
	brush.fill_box(
		Vector3i(WALL_X, 1, GAP_B_Z1),
		Vector3i(WALL_X + 1, WALL_TOP, FIELD_Z),
		VoxelMaterial.BRICK
	)


func _register_field() -> bool:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	var offline: CityBrush = CityBrushScript.new() as CityBrush
	offline.use_offline_volume(volume)
	_paint_into(offline)
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		_origin,
		FIELD_X,
		FIELD_Z,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test field")
		return false
	if not _nav.register_district(DISTRICT, bake):
		_fail("FAIL NavService refused district %s" % str(DISTRICT))
		return false
	var stats := _nav.district_stats(DISTRICT)
	print(
		"field %s: spans=%d nodes=%d portals=%d links=%d"
		% [
			str(DISTRICT),
			int(stats["spans"]),
			int(stats["nodes"]),
			int(stats["portals"]),
			int(stats["links"]),
		]
	)
	return true


func _make_terrain() -> void:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	## Same ceiling CityRoot uses: tall enough for field.y_max + link_reach_y headroom.
	_terrain.bounds = AABB(
		Vector3(float(_origin.x) - 512.0, 0.0, float(_origin.z) - 512.0),
		Vector3(1536.0, float(TERRAIN_HEIGHT_VOX), 1536.0)
	)
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = false
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 400
	anchor.requires_visuals = false
	anchor.requires_collisions = false
	add_child(anchor)
	anchor.global_position = (
		Vector3(float(_origin.x + FIELD_X / 2), 8.0, float(_origin.z + FIELD_Z / 2)) * VOXEL_SIZE
	)

	## The whole field, full height: exactly what one rebuild region has to read back.
	var box := AABB(
		Vector3(float(_origin.x) - 32.0, 0.0, float(_origin.z) - 32.0),
		Vector3(float(FIELD_X) + 64.0, float(TERRAIN_HEIGHT_VOX), float(FIELD_Z) + 64.0)
	)
	for _i in range(900):
		await get_tree().process_frame
		if _tool.is_area_editable(box):
			return
	_fail("FAIL the field never became editable")


func _world_of(local: Vector3i) -> Vector3:
	var vox := _origin + local
	return Vector3(float(vox.x), float(vox.y), float(vox.z)) * VOXEL_SIZE


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
