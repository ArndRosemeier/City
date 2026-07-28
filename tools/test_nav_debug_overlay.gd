## Headless check on the navigation debug overlay: with one real district registered it must
## draw the span field and the sector portals near the followed node, turn a queued path
## request into a corridor, show a dynamic block until it expires, and draw nothing at all
## while switched off.
##
## Run: Godot --headless --path . res://tools/test_nav_debug_overlay.tscn
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const NavDebugOverlayScript := preload("res://scripts/city/nav_debug_overlay.gd")

const WORLD_SEED := 42
const COORD := Vector2i(0, 0)
const VOXEL_SIZE := 0.5
const RADIUS_M := 16.0
## Far enough that the corridor needs more than one segment, near enough to stay inside the
## tile so the test does not depend on a second district being loaded.
const PROBE_OFFSET := Vector3(34.0, 0.0, 12.0)
const BLOCK_SEC := 0.35
const PATH_TIMEOUT_MS := 4000
## One refresh is a Rust radius query plus one MultiMesh buffer upload; a built lot measures
## about 2 ms. Generous enough not to be flaky on a loaded machine, tight enough that losing
## the buffer upload or the colour table is loud.
const REFRESH_BUDGET_USEC := 6000

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var nav := NavService.instance()
	nav.ensure_configured(VOXEL_SIZE)

	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": COORD,
		"world_seed": WORLD_SEED,
		"bake_nav": true,
		"nav_solidity": nav.solidity_tables(),
		"nav_link_params": nav.link_params(),
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL bake: %s" % res.get("error", "?"))
		_quit()
		return
	if not nav.register_district(COORD, res["nav_bake"] as RefCounted):
		_fail("FAIL NavService refused district %s" % str(COORD))
		_quit()
		return
	var stats: Dictionary = nav.district_stats(COORD)
	print(
		"district %s spans=%d portals=%d links=%d"
		% [str(COORD), int(stats["spans"]), int(stats["portals"]), int(stats["links"])]
	)

	## A built lot rather than the tile centre: stacked building floors are the dense case,
	## and a refresh budget measured on an empty park proves nothing.
	var ground_y := float(int(res["ground_thickness"])) * VOXEL_SIZE
	var lot := _built_lot(res["planner"] as DistrictPlanner, ground_y)
	if not lot.is_finite():
		_fail("FAIL district %s has no built lot" % str(COORD))
		_quit()
		return
	var start := nav.nearest_surface(NavProfile.Id.PEDESTRIAN, lot, 20.0)
	if not start.found:
		_fail("FAIL no walkable span within 20 m of the lot %s" % str(lot))
		_quit()
		return
	print("following %s (clearance %d, headroom %d)" % [start.position, start.clearance, start.headroom])

	var follow := Node3D.new()
	follow.name = "Follow"
	add_child(follow)
	follow.global_position = start.position

	var overlay: NavDebugOverlay = NavDebugOverlayScript.new() as NavDebugOverlay
	overlay.name = "NavDebugOverlay"
	add_child(overlay)
	overlay.radius_m = RADIUS_M
	overlay.bind_follow(follow)

	if overlay.is_enabled():
		_fail("FAIL overlay is on before anything asked for it")
		_quit()
		return
	await _frames(2)
	if overlay.spans_drawn != 0:
		_fail("FAIL a disabled overlay drew %d spans" % overlay.spans_drawn)
		_quit()
		return

	if not overlay.toggle():
		_fail("FAIL toggle refused to switch the overlay on")
		_quit()
		return
	await _frames(3)
	print(
		"drawn spans=%d portals=%d in a %.0f m ring" % [
			overlay.spans_drawn, overlay.portals_drawn, RADIUS_M
		]
	)
	if overlay.spans_drawn <= 0:
		_fail("FAIL overlay drew no spans next to a registered district")
		_quit()
		return
	if overlay.portals_drawn <= 0:
		_fail("FAIL overlay drew no sector portals")
		_quit()
		return

	## Walking one step must not cost a frame: this is the whole refresh, span buffer
	## upload included, for however many spans a dense block puts inside the ring.
	follow.global_position += Vector3(5.0, 0.0, 0.0)
	## Re-assigning the radius marks the field dirty, which bypasses the movement throttle,
	## so the next frame is guaranteed to be the one that re-queries.
	overlay.radius_m = RADIUS_M
	var refresh_us := await _peak_overlay_cost(4)
	print("refresh of %d spans cost %d us" % [overlay.spans_drawn, refresh_us])
	if refresh_us <= 0:
		_fail("FAIL no overlay frame was measured, the cost check proved nothing")
		_quit()
		return
	if refresh_us > REFRESH_BUDGET_USEC:
		_fail(
			"FAIL a refresh of %d spans took %d us, over the %d us budget"
			% [overlay.spans_drawn, refresh_us, REFRESH_BUDGET_USEC]
		)
		_quit()
		return

	## Every colouring must survive a redraw — a bad mode is a silent grey field otherwise.
	for i in range(3):
		var mode := overlay.cycle_span_colour()
		await _frames(2)
		if overlay.spans_drawn <= 0:
			_fail("FAIL span layer emptied after switching to '%s' colouring" % mode)
			_quit()
			return
		print("colouring '%s' drew %d spans" % [mode, overlay.spans_drawn])

	var goal := nav.nearest_surface(
		NavProfile.Id.PEDESTRIAN, start.position + PROBE_OFFSET, 24.0
	)
	if not goal.found:
		_fail("FAIL no walkable span near the probe target %s" % str(start.position + PROBE_OFFSET))
		_quit()
		return
	overlay.probe_to(goal.position)
	var deadline := Time.get_ticks_msec() + PATH_TIMEOUT_MS
	while overlay.corridor_count() == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(2)
	if overlay.corridor_count() == 0:
		_fail("FAIL probe path never produced a corridor within %d ms" % PATH_TIMEOUT_MS)
		_quit()
		return
	var corridor := overlay.corridor(NavDebugOverlay.PROBE_CORRIDOR)
	if corridor == null:
		_fail("FAIL corridor is not filed under the probe id")
		_quit()
		return
	print(
		"corridor %s %d points %.1f m, drawn points=%d"
		% [corridor.status_name(), corridor.points.size(), corridor.length_m(), overlay.corridor_points]
	)
	if overlay.corridor_points < 2:
		_fail("FAIL corridor has %d drawn points" % overlay.corridor_points)
		_quit()
		return

	overlay.block_column(start.position, BLOCK_SEC)
	await _frames(2)
	if overlay.blocks_drawn != 1:
		_fail("FAIL a fresh block drew %d columns" % overlay.blocks_drawn)
		_quit()
		return
	await _wait_ms(int(BLOCK_SEC * 1000.0) + 250)
	if overlay.blocks_drawn != 0:
		_fail("FAIL %d blocks outlived their duration" % overlay.blocks_drawn)
		_quit()
		return
	print("dynamic block appeared and expired after %.2f s" % BLOCK_SEC)

	## A block an agent wrote goes through NavService and never touches this overlay, and it
	## used to be invisible here for exactly that reason.
	nav.block_column(start.position + Vector3(2.0, 0.0, 2.0), BLOCK_SEC)
	await _frames(2)
	if overlay.blocks_drawn != 1:
		_fail(
			"FAIL a block written straight through NavService drew %d columns"
			% overlay.blocks_drawn
		)
		_quit()
		return
	print("block written through NavService is drawn by the overlay")
	await _wait_ms(int(BLOCK_SEC * 1000.0) + 250)

	overlay.set_enabled(false)
	if overlay.is_enabled():
		_fail("FAIL overlay stayed on after being switched off")
		_quit()
		return
	if overlay.spans_drawn != 0 or overlay.portals_drawn != 0 or overlay.corridor_points != 0:
		_fail(
			"FAIL switching off left spans=%d portals=%d corridor points=%d"
			% [overlay.spans_drawn, overlay.portals_drawn, overlay.corridor_points]
		)
		_quit()
		return
	await _frames(3)
	if overlay.spans_drawn != 0:
		_fail("FAIL a switched-off overlay re-queried the field")
		_quit()
		return

	print("RESULT: OK")
	_quit()


## A lot cell with buildings on it, as close to the middle of the tile as one gets.
func _built_lot(planner: DistrictPlanner, ground_y: float) -> Vector3:
	var origin := DistrictCoord.origin_world(COORD, VOXEL_SIZE)
	var cell_m := float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE
	var mid := Vector2(float(planner.cells_x) * 0.5, float(planner.cells_z) * 0.5)
	var best := Vector3.INF
	var best_d := INF
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_lot(planner.tag_at(cx, cz)):
				continue
			var d2 := Vector2(float(cx), float(cz)).distance_squared_to(mid)
			if d2 >= best_d:
				continue
			best_d = d2
			best = origin + Vector3(
				(float(cx) + 0.5) * cell_m, ground_y, (float(cz) + 0.5) * cell_m
			)
	return best


## Worst overlay frame over the next `frames`, straight out of the profiler scope the
## overlay reports itself under.
func _peak_overlay_cost(frames: int) -> int:
	var peak := 0
	for i in range(frames):
		await get_tree().process_frame
		peak = maxi(peak, CityProfiler._scope_last_us("nav_debug_overlay"))
	return peak


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _wait_ms(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
