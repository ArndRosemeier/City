## World-level NavService: district registration, pathing across a district border,
## profile filtering at a narrow gap, and the budgeted query queue.
##
## Synthetic tiles carry the geometric assertions because a hand-painted volume states
## exactly what is being tested; two real baked districts then prove the same registry
## works on DistrictBakeJob output and a genuine street grid.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_nav_service.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const VOXEL_SIZE := 0.5
const WORLD_SEED := 42
## Deep enough that even a giant's headroom requirement is met on open ground.
const FIELD_Y_MAX := 47

## Two adjacent synthetic tiles, parked far from every real district coordinate.
const TILE_A := Vector2i(50, 50)
const TILE_B := Vector2i(51, 50)
const TILE_ORIGIN := Vector3i(10000, 0, 10000)
const TILE_VOX := 84

## One tile split by a sheer wall with a 3 m gap in it.
const ALLEY_TILE := Vector2i(60, 60)
const ALLEY_ORIGIN := Vector3i(20000, 0, 20000)
const ALLEY_X := 96
const ALLEY_Z := 64
const ALLEY_WALL_X := 48
const ALLEY_GAP_Z0 := 30
## Exclusive — six columns is 3 m at 0.5 m voxels.
const ALLEY_GAP_Z1 := 36

## A giant that refuses to break anything, registered by the test to isolate the effect
## of can_break from the effect of the body size.
const PROFILE_GIANT_PACIFIST := 100

## One tile of stepped lake bed under a flat water surface, so every wade depth from 1 to 5
## cells exists side by side and a profile's max_wade is the only thing that varies.
const LAKE_TILE := Vector2i(65, 65)
const LAKE_ORIGIN := Vector3i(35000, 0, 35000)
const LAKE_X := 96
const LAKE_Z := 64
## Shore top, and therefore the water surface. Depth i is bed top LAKE_RIM_Y - i.
const LAKE_RIM_Y := 6
const LAKE_SHORE_X := 24
const LAKE_BAND_X := 12
const LAKE_DEPTH_MAX := 5

## Seconds a test block lives. Long enough to survive the frames the assertions need, short
## enough that waiting it out does not dominate the scene.
const BLOCK_SEC := 0.4

## Real tiles for the integration pass. "far" quality is ground plus impostors, which is
## a full 784 x 560 street deck without the building shells.
const REAL_A := Vector2i(0, 0)
const REAL_B := Vector2i(1, 0)

## Frames a starved queue is given to drain. One query per frame is the worst the budget can
## do, so anything past this is a queue that has stopped serving — and a test that waited on
## it without a bound would hang instead of saying so.
const DRAIN_FRAMES_MAX := 120

var _failed := false
var _nav: NavService
var _served: Array[NavPathResult] = []


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
	for id: int in [NavProfile.Id.PEDESTRIAN, NavProfile.Id.UNDEAD, NavProfile.Id.GIANT]:
		if not _nav.has_profile(id):
			_fail("FAIL default profile %d is not registered" % id)
			_quit()
			return
	print("profiles registered: %s" % str(_nav.profile_ids()))

	_test_border()
	if _failed:
		_quit()
		return
	_test_profile_filter()
	if _failed:
		_quit()
		return
	await _test_queue()
	if _failed:
		_quit()
		return
	await _test_blocked_columns()
	if _failed:
		_quit()
		return
	_test_water_depth()
	if _failed:
		_quit()
		return
	_test_real_districts()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# Border
# ---------------------------------------------------------------------------

func _test_border() -> void:
	var a := _bake_flat(TILE_ORIGIN, TILE_VOX, TILE_VOX)
	var b_origin := TILE_ORIGIN + Vector3i(TILE_VOX, 0, 0)
	var b := _bake_flat(b_origin, TILE_VOX, TILE_VOX)
	if a == null or b == null:
		_fail("FAIL synthetic bake produced no field")
		return

	if not _nav.register_district(TILE_A, a):
		_fail("FAIL NavService refused tile A")
		return
	var v_one := _nav.version()

	var from := _vox_to_world(TILE_ORIGIN + Vector3i(10, 1, 42))
	var to := _vox_to_world(b_origin + Vector3i(70, 1, 42))
	var border_x := float(b_origin.x) * VOXEL_SIZE

	var alone := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to)
	if alone.is_complete():
		_fail("FAIL path into an unloaded neighbour reported %s" % alone.status_name())
		return
	print("one tile loaded: %s (expanded %d)" % [alone.status_name(), alone.expanded])

	if not _nav.register_district(TILE_B, b):
		_fail("FAIL NavService refused tile B")
		return
	if _nav.district_count() != 2:
		_fail("FAIL district_count is %d, expected 2" % _nav.district_count())
		return
	if _nav.version() <= v_one:
		_fail("FAIL registering a district did not bump the nav version")
		return

	var crossing := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to)
	if not crossing.is_complete():
		_fail("FAIL cross-border path is %s, expected OK" % crossing.status_name())
		return
	var reached_far := false
	for p: Vector3 in crossing.points:
		if p.x > border_x:
			reached_far = true
			break
	if not reached_far:
		_fail("FAIL path never entered the neighbour tile (border x=%.1f m)" % border_x)
		return
	var end: Vector3 = crossing.points[crossing.points.size() - 1]
	if end.distance_to(to) > 2.0:
		_fail("FAIL path ends %.2f m from the goal" % end.distance_to(to))
		return
	print(
		"border path: %s points=%d length=%.1f m expanded=%d end=%.1f,%.1f"
		% [
			crossing.status_name(),
			crossing.points.size(),
			crossing.length_m(),
			crossing.expanded,
			end.x,
			end.z,
		]
	)

	var stats := _nav.district_stats(TILE_A)
	print(
		"tile A stats: spans=%d nodes=%d portals=%d links=%d bytes=%d"
		% [
			int(stats["spans"]),
			int(stats["nodes"]),
			int(stats["portals"]),
			int(stats["links"]),
			int(stats["bytes"]),
		]
	)


# ---------------------------------------------------------------------------
# Profile filtering
# ---------------------------------------------------------------------------

func _test_profile_filter() -> void:
	var field := _bake_alley()
	if field == null:
		_fail("FAIL alley bake produced no field")
		return
	if not _nav.register_district(ALLEY_TILE, field):
		_fail("FAIL NavService refused the alley tile")
		return

	var pacifist := NavProfile.giant().duplicate_as(PROFILE_GIANT_PACIFIST, "giant_pacifist")
	pacifist.can_break = false
	_nav.register_profile(pacifist)

	var from := _vox_to_world(ALLEY_ORIGIN + Vector3i(24, 1, 32))
	var to := _vox_to_world(ALLEY_ORIGIN + Vector3i(72, 1, 32))
	var wall_x := float(ALLEY_ORIGIN.x + ALLEY_WALL_X) * VOXEL_SIZE

	var walker := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, from, to, 200000)
	if not walker.is_complete():
		_fail("FAIL a pedestrian should fit the 3 m gap, got %s" % walker.status_name())
		return
	var walker_crossed := false
	for p: Vector3 in walker.points:
		if p.x > wall_x + 0.5:
			walker_crossed = true
			break
	if not walker_crossed:
		_fail("FAIL pedestrian path never passed the wall at x=%.1f m" % wall_x)
		return
	print(
		"pedestrian through the gap: %s points=%d length=%.1f m expanded=%d"
		% [walker.status_name(), walker.points.size(), walker.length_m(), walker.expanded]
	)

	var giant := _nav.find_path_now(PROFILE_GIANT_PACIFIST, from, to, 200000)
	if giant.is_complete():
		_fail("FAIL a 5.5 m wide giant squeezed through a 3 m gap")
		return
	for p: Vector3 in giant.points:
		if p.x > wall_x:
			_fail("FAIL giant path leaked past the wall to x=%.1f m" % p.x)
			return
	print(
		"giant without can_break: %s points=%d expanded=%d"
		% [giant.status_name(), giant.points.size(), giant.expanded]
	)

	var breaker := _nav.find_path_now(NavProfile.Id.GIANT, from, to, 200000)
	if breaker.status != NavPathResult.Status.BREACH:
		_fail("FAIL giant with can_break got %s, expected BREACH" % breaker.status_name())
		return
	var breach_end: Vector3 = breaker.points[breaker.points.size() - 1]
	if breach_end.distance_to(to) > 1.0:
		_fail("FAIL breach route stops %.2f m short of the goal" % breach_end.distance_to(to))
		return
	print(
		"giant with can_break: %s points=%d length=%.1f m"
		% [breaker.status_name(), breaker.points.size(), breaker.length_m()]
	)

	## reachable() answers from the permissive high-level graph, so it may say yes where a
	## wide body's fine search says no. What it must never do is deny a route find_path
	## then walks — that would make goal selection abandon reachable goals.
	if not _nav.reachable(NavProfile.Id.PEDESTRIAN, from, to):
		_fail("FAIL reachable() denies the route the pedestrian just walked")
		return
	print("reachable(): pedestrian=true giant=%s (high-level graph is permissive)"
		% _nav.reachable(PROFILE_GIANT_PACIFIST, from, to))

	var hit := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, from + Vector3(0.0, 6.0, 0.0), 8.0)
	if not hit.found:
		_fail("FAIL nearest_surface found nothing above open ground")
		return
	print(
		"nearest_surface: y=%.2f m clearance=%d headroom=%d"
		% [hit.position.y, hit.clearance, hit.headroom]
	)


# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

func _test_queue() -> void:
	var from := _vox_to_world(TILE_ORIGIN + Vector3i(10, 1, 42))
	var to := _vox_to_world(TILE_ORIGIN + Vector3i(TILE_VOX + 70, 1, 42))

	## Count cap first: a flood of cheap queries must still spread over frames.
	_nav.frame_budget_usec = 100000
	_nav.max_queries_per_frame = 4
	_served.clear()
	const FLOOD := 20
	var ids: Array[int] = []
	for i in range(FLOOD):
		var id := _nav.request_path(
			NavProfile.Id.PEDESTRIAN, from + Vector3(float(i) * 0.5, 0.0, 0.0), to, _on_path
		)
		if id == 0:
			_fail("FAIL request %d was rejected" % i)
			return
		ids.append(id)
	if _nav.queue_size() != FLOOD:
		_fail("FAIL queue holds %d of %d requests" % [_nav.queue_size(), FLOOD])
		return

	var frames := 0
	var worst_per_frame := 0
	while _served.size() < FLOOD and frames < 60:
		await get_tree().process_frame
		frames += 1
		worst_per_frame = maxi(worst_per_frame, _nav.served_last_frame())
	if _served.size() != FLOOD:
		_fail("FAIL queue delivered %d of %d in %d frames" % [_served.size(), FLOOD, frames])
		return
	if worst_per_frame > _nav.max_queries_per_frame:
		_fail("FAIL queue served %d in one frame, cap is %d" % [worst_per_frame, _nav.max_queries_per_frame])
		return
	if frames < FLOOD / _nav.max_queries_per_frame:
		_fail("FAIL %d requests drained in %d frames — the budget did nothing" % [FLOOD, frames])
		return
	for r: NavPathResult in _served:
		if not r.is_usable():
			_fail("FAIL queued request %d came back %s" % [r.request_id, r.status_name()])
			return
		if r.nav_version != _nav.version():
			_fail("FAIL result %d carries nav_version %d" % [r.request_id, r.nav_version])
			return
	print(
		"queue: %d requests over %d frames, worst %d per frame"
		% [FLOOD, frames, worst_per_frame]
	)

	## Time cap: one query always runs, so an expensive path cannot stall the queue.
	_nav.frame_budget_usec = 1
	_nav.max_queries_per_frame = 8
	_served.clear()
	for i in range(4):
		_nav.request_path(NavProfile.Id.PEDESTRIAN, from, to, _on_path)
	await get_tree().process_frame
	if _nav.served_last_frame() != 1:
		_fail("FAIL a 1 us budget served %d queries, expected exactly 1" % _nav.served_last_frame())
		return
	var drain := 0
	while _nav.queue_size() > 0 and drain < DRAIN_FRAMES_MAX:
		await get_tree().process_frame
		drain += 1
	if _nav.queue_size() > 0:
		_fail(
			"FAIL a 1 us budget left %d queries queued after %d frames"
			% [_nav.queue_size(), drain]
		)
		return
	print("starved queue served 1 query per frame")

	## Cancellation, because agents die while they wait.
	_nav.frame_budget_usec = 100000
	_nav.max_queries_per_frame = 8
	_served.clear()
	var keep_a := _nav.request_path(NavProfile.Id.PEDESTRIAN, from, to, _on_path)
	var drop := _nav.request_path(NavProfile.Id.PEDESTRIAN, from, to, _on_path)
	var keep_b := _nav.request_path(NavProfile.Id.PEDESTRIAN, from, to, _on_path)
	if not _nav.cancel_path(drop):
		_fail("FAIL cancel_path could not find request %d" % drop)
		return
	await get_tree().process_frame
	if _served.size() != 2:
		_fail("FAIL cancellation left %d results, expected 2" % _served.size())
		return
	for r: NavPathResult in _served:
		if r.request_id != keep_a and r.request_id != keep_b:
			_fail("FAIL cancelled request %d was served anyway" % r.request_id)
			return
	if _nav.cancel_path(drop):
		_fail("FAIL cancelling a spent request reported success")
		return
	print("cancellation: 1 of 3 dropped, 2 delivered")
	_nav.frame_budget_usec = NavService.DEFAULT_FRAME_BUDGET_USEC
	_nav.max_queries_per_frame = NavService.DEFAULT_MAX_PER_FRAME


func _on_path(result: NavPathResult) -> void:
	_served.append(result)


# ---------------------------------------------------------------------------
# Real districts
# ---------------------------------------------------------------------------

func _test_real_districts() -> void:
	for coord: Vector2i in [TILE_A, TILE_B, ALLEY_TILE]:
		if not _nav.unregister_district(coord):
			_fail("FAIL could not unregister synthetic tile %s" % str(coord))
			return
	if _nav.district_count() != 0:
		_fail("FAIL %d districts survived unregistration" % _nav.district_count())
		return

	var a := _bake_real(REAL_A)
	if a.is_empty():
		return
	var b := _bake_real(REAL_B)
	if b.is_empty():
		return

	var planner_a: DistrictPlanner = a["planner"]
	var planner_b: DistrictPlanner = b["planner"]
	var from := _road_point(planner_a, REAL_A, planner_a.cells_x - 3, planner_a.cells_z / 2)
	var to := _road_point(planner_b, REAL_B, 2, planner_b.cells_z / 2)
	if from == Vector3.INF or to == Vector3.INF:
		_fail("FAIL no road cell near the shared border")
		return

	var snap_from := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, from, 6.0)
	var snap_to := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, to, 6.0)
	if not snap_from.found or not snap_to.found:
		_fail(
			"FAIL road cells have no pedestrian surface (from=%s to=%s)"
			% [snap_from.found, snap_to.found]
		)
		return

	var border_x := float(DistrictCoord.origin_vox(REAL_B).x) * VOXEL_SIZE
	var t0 := Time.get_ticks_usec()
	var path := _nav.find_path_now(
		NavProfile.Id.PEDESTRIAN, snap_from.position, snap_to.position, 400000
	)
	var query_us := Time.get_ticks_usec() - t0
	if not path.is_usable():
		_fail(
			"FAIL real cross-border path is %s from %.1f,%.1f to %.1f,%.1f"
			% [
				path.status_name(),
				snap_from.position.x,
				snap_from.position.z,
				snap_to.position.x,
				snap_to.position.z,
			]
		)
		return
	var crossed := false
	for p: Vector3 in path.points:
		if p.x > border_x:
			crossed = true
			break
	if not crossed:
		_fail("FAIL real path never crossed the border at x=%.1f m" % border_x)
		return
	print(
		"real border path: %s points=%d length=%.1f m expanded=%d query=%.2f ms"
		% [
			path.status_name(),
			path.points.size(),
			path.length_m(),
			path.expanded,
			float(query_us) * 0.001,
		]
	)

	## What a 5.5 m body makes of a real street grid. Reported rather than asserted — the
	## pinned profile-filtering case is the synthetic wall above, where the geometry is
	## stated instead of generated.
	var giant_spot := _nav.nearest_surface(NavProfile.Id.GIANT, snap_from.position, 12.0)
	var giant_path := _nav.find_path_now(
		NavProfile.Id.GIANT, snap_from.position, snap_to.position, 400000
	)
	print(
		"real giant: footing=%s clearance=%d path=%s points=%d length=%.1f m"
		% [
			giant_spot.found,
			giant_spot.clearance,
			giant_path.status_name(),
			giant_path.points.size(),
			giant_path.length_m(),
		]
	)


func _bake_real(coord: Vector2i) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
		"quality": DistrictBakeJobScript.QUALITY_FAR,
		"bake_nav": true,
		"nav_solidity": _nav.solidity_tables(),
		"nav_link_params": _nav.link_params(),
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL real bake %s: %s" % [str(coord), res.get("error", "?")])
		return {}
	var bake_ms := Time.get_ticks_msec() - t0
	var nav_bake: RefCounted = res["nav_bake"] as RefCounted
	if nav_bake == null:
		_fail("FAIL real bake %s returned no nav field" % str(coord))
		return {}
	var stats: Dictionary = res["nav_stats"]
	var t1 := Time.get_ticks_usec()
	if not _nav.register_district(coord, nav_bake):
		_fail("FAIL NavService refused real district %s" % str(coord))
		return {}
	print(
		(
			"real district %s: bake=%d ms register=%.2f ms columns=%d spans=%d"
			+ " max/col=%d nodes=%d portals=%d links=%d bytes=%d"
		)
		% [
			str(coord),
			bake_ms,
			float(Time.get_ticks_usec() - t1) * 0.001,
			int(stats["columns"]),
			int(stats["spans"]),
			int(stats["max_spans_per_column"]),
			int(stats["nodes"]),
			int(stats["portals"]),
			int(stats["links"]),
			int(stats["bytes"]),
		]
	)
	if int(stats["spans"]) <= 0:
		_fail("FAIL real district %s baked no spans" % str(coord))
		return {}
	return res


## Centre of the road cell nearest to a preferred planner cell, in world metres.
func _road_point(planner: DistrictPlanner, coord: Vector2i, want_cx: int, want_cz: int) -> Vector3:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var d := absi(cx - want_cx) * 4 + absi(cz - want_cz)
			if d < best_d:
				best_d = d
				best = Vector2i(cx, cz)
	if best.x < 0:
		return Vector3.INF
	var origin := DistrictCoord.origin_world(coord, VOXEL_SIZE)
	var cell_m := float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE
	return origin + Vector3(
		(float(best.x) + 0.5) * cell_m, 4.0, (float(best.y) + 0.5) * cell_m
	)


# ---------------------------------------------------------------------------
# Blocked columns
# ---------------------------------------------------------------------------

## The blocked-column read-back. NativeNavWorld answers nothing about its own overlay, so
## every consumer that wants to know what is blocked — the debug overlay, a HUD, a test —
## depends on this mirror being the same set on the same clock.
func _test_blocked_columns() -> void:
	var probe := _vox_to_world(TILE_ORIGIN + Vector3i(20, 1, 20))
	var column := _nav.column_of(probe)
	if _nav.blocked_column_count() != 0:
		_fail("FAIL %d columns were blocked before anything blocked one"
			% _nav.blocked_column_count())
		return
	if _nav.is_column_blocked(probe):
		_fail("FAIL %s reads blocked on an untouched deck" % str(column))
		return

	var version_before := _nav.blocked_version()
	_nav.block_column(probe, BLOCK_SEC)
	if not _nav.is_column_blocked(probe):
		_fail("FAIL the column just blocked reads clear")
		return
	if _nav.blocked_column_count() != 1:
		_fail("FAIL one block gave a count of %d" % _nav.blocked_column_count())
		return
	var live := _nav.blocked_columns()
	if live.size() != 1 or live[0] != column:
		_fail("FAIL blocked_columns() is %s, expected one entry for %s"
			% [str(live), str(column)])
		return
	if not is_equal_approx(_nav.blocked_column_y(column), probe.y):
		_fail("FAIL block remembers y=%.3f m, was written at %.3f m"
			% [_nav.blocked_column_y(column), probe.y])
		return
	if _nav.blocked_version() == version_before:
		_fail("FAIL blocked_version stayed at %d across a write" % version_before)
		return

	## A neighbouring column is a different key, so the mirror cannot be answering "any
	## block at all" and calling it a hit.
	if _nav.is_column_blocked(probe + Vector3(VOXEL_SIZE * 4.0, 0.0, 0.0)):
		_fail("FAIL a column four voxels away reads blocked too")
		return
	print("blocked column %s live, count=%d v%d"
		% [str(column), _nav.blocked_column_count(), _nav.blocked_version()])

	## Expiry runs off the clock the pump hands the nav world, so it takes frames and not
	## just wall time.
	var deadline := Time.get_ticks_msec() + int(BLOCK_SEC * 1000.0) + 500
	while _nav.is_column_blocked(probe) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _nav.is_column_blocked(probe):
		_fail("FAIL the block outlived its %.2f s duration" % BLOCK_SEC)
		return
	if _nav.blocked_column_count() != 0:
		_fail("FAIL %d expired blocks are still counted" % _nav.blocked_column_count())
		return
	print("block expired after %.2f s, count back to 0" % BLOCK_SEC)


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------

## Water is a wading depth, not a wall and not a floor.
##
## The bed under water is a real surface, so the span field covers a lake bottom to its
## deepest cell — which is what the debug overlay draws and why the field looks like it
## extends over open water. What must hold is that a body only ever stands where the water
## over that bed is within its own max_wade: a pedestrian paddles one cell, undead two, and
## nothing that cannot swim gets past that.
func _test_water_depth() -> void:
	var field := _bake_lake()
	if field == null:
		_fail("FAIL lake bake produced no field")
		return
	if not _nav.register_district(LAKE_TILE, field):
		_fail("FAIL NavService refused the lake tile")
		return

	var shore := _vox_to_world(LAKE_ORIGIN + Vector3i(12, LAKE_RIM_Y, 32))
	var far_shore := _vox_to_world(
		LAKE_ORIGIN + Vector3i(LAKE_X - 6, LAKE_RIM_Y, 32)
	)

	## Deepest band first: nothing about it is walkable for a pedestrian, and the giant
	## proves the spans are there and only the wade limit is refusing them.
	var deep := _vox_to_world(LAKE_ORIGIN + Vector3i(_band_centre_x(4), LAKE_RIM_Y, 32))
	var ped_hit := _nav.nearest_surface(NavProfile.Id.PEDESTRIAN, deep, 6.0)
	if ped_hit.found:
		_fail(
			"FAIL a pedestrian found standing ground %.2f m from the middle of 2 m of water"
			% deep.distance_to(ped_hit.position)
		)
		return
	var giant_hit := _nav.nearest_surface(NavProfile.Id.GIANT, deep, 6.0)
	if not giant_hit.found:
		_fail("FAIL the lake bed carries no span at all, so the depth test proves nothing")
		return
	if giant_hit.water_depth < 4:
		_fail("FAIL the giant stood in %d cells of water, expected 4 or more"
			% giant_hit.water_depth)
		return
	print(
		"deep band: pedestrian finds nothing, giant wades %d cells at y=%.2f m"
		% [giant_hit.water_depth, giant_hit.position.y]
	)

	## Shallows within max_wade stay walkable, or a ford would be a wall.
	var shallow := _vox_to_world(LAKE_ORIGIN + Vector3i(_band_centre_x(1), LAKE_RIM_Y, 32))
	var wade := _nav.find_path_now(NavProfile.Id.PEDESTRIAN, shore, shallow, 200000)
	if not wade.is_complete():
		_fail("FAIL a pedestrian will not wade one cell of water: %s" % wade.status_name())
		return
	print("pedestrian wades into the 0.5 m band: %s %.1f m"
		% [wade.status_name(), wade.length_m()])

	## And the crossing every profile with a wade limit has to refuse.
	var lake_x_min := float(LAKE_ORIGIN.x + LAKE_SHORE_X) * VOXEL_SIZE
	for id: int in [NavProfile.Id.PEDESTRIAN, NavProfile.Id.UNDEAD]:
		var limit := _nav.profile(id).max_wade
		var crossing := _nav.find_path_now(id, shore, far_shore, 400000)
		if crossing.is_complete():
			_fail(
				"FAIL profile %d walked across %d cells of water on a max_wade of %d"
				% [id, LAKE_DEPTH_MAX, limit]
			)
			return
		## Where it gave up matters as much as that it did: the last point must be no deeper
		## into the lake than the last band that profile can stand in.
		var reach_x := lake_x_min
		for p: Vector3 in crossing.points:
			reach_x = maxf(reach_x, p.x)
		var allowed_x := float(
			LAKE_ORIGIN.x + LAKE_SHORE_X + limit * LAKE_BAND_X
		) * VOXEL_SIZE
		if reach_x > allowed_x + VOXEL_SIZE:
			_fail(
				"FAIL profile %d reached x=%.1f m, past the %d-cell band that ends at %.1f m"
				% [id, reach_x, limit, allowed_x]
			)
			return
		print(
			"profile %d (max_wade %d): %s, stopped %.1f m into the lake of %.1f m"
			% [
				id,
				limit,
				crossing.status_name(),
				reach_x - lake_x_min,
				float(LAKE_X - LAKE_SHORE_X) * VOXEL_SIZE,
			]
		)

	if not _nav.unregister_district(LAKE_TILE):
		_fail("FAIL the lake tile would not unregister")
		return


## Middle of the band that holds `depth` cells of water.
func _band_centre_x(depth: int) -> int:
	if depth < 1 or depth > LAKE_DEPTH_MAX:
		_fail("FAIL no lake band holds %d cells of water" % depth)
		return LAKE_SHORE_X
	return LAKE_SHORE_X + (depth - 1) * LAKE_BAND_X + LAKE_BAND_X / 2


# ---------------------------------------------------------------------------
# Synthetic fields
# ---------------------------------------------------------------------------

## Flat concrete deck one voxel thick, open sky above.
func _bake_flat(origin: Vector3i, size_x: int, size_z: int) -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(size_x, 1, size_z), VoxelMaterial.CONCRETE)
	return _bake_volume(volume, origin, size_x, size_z)


## The same deck, split by a sheer brick wall with one 3 m gap in it.
func _bake_alley() -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(ALLEY_X, 1, ALLEY_Z), VoxelMaterial.CONCRETE)
	volume.fill_box(
		Vector3i(ALLEY_WALL_X, 1, 0),
		Vector3i(ALLEY_WALL_X + 1, 9, ALLEY_GAP_Z0),
		VoxelMaterial.BRICK
	)
	volume.fill_box(
		Vector3i(ALLEY_WALL_X, 1, ALLEY_GAP_Z1),
		Vector3i(ALLEY_WALL_X + 1, 9, ALLEY_Z),
		VoxelMaterial.BRICK
	)
	return _bake_volume(volume, ALLEY_ORIGIN, ALLEY_X, ALLEY_Z)


## Shore, then five bands of lake bed a cell deeper each, all under one water surface at
## LAKE_RIM_Y. Depth i runs from x = LAKE_SHORE_X + (i - 1) * LAKE_BAND_X.
func _bake_lake() -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(LAKE_X, LAKE_RIM_Y, LAKE_Z), VoxelMaterial.CONCRETE)
	for depth in range(1, LAKE_DEPTH_MAX + 1):
		var x0 := LAKE_SHORE_X + (depth - 1) * LAKE_BAND_X
		volume.fill_box(
			Vector3i(x0, LAKE_RIM_Y - depth, 0),
			Vector3i(x0 + LAKE_BAND_X, LAKE_RIM_Y, LAKE_Z),
			VoxelMaterial.WATER
		)
	return _bake_volume(volume, LAKE_ORIGIN, LAKE_X, LAKE_Z)


func _bake_volume(volume: Variant, origin: Vector3i, size_x: int, size_z: int) -> RefCounted:
	var tables := _nav.solidity_tables()
	var bake = CityVoxelNativeScript.make_nav_bake()
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
	return bake as RefCounted


func _vox_to_world(vox: Vector3i) -> Vector3:
	return Vector3(float(vox.x), float(vox.y), float(vox.z)) * VOXEL_SIZE


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
