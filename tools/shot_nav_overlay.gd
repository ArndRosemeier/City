## Photographs the navigation debug overlay against one real baked district, so the span
## field, its colourings, the sector portals, a live corridor and the dynamic blocks are all
## reviewable in a picture instead of in numbers.
##
## Bakes and registers the tile directly rather than booting the streaming city: the overlay
## draws from NavService, not from voxels, and a bake takes seconds where a boot takes a
## minute and a half. Needs a renderer for the viewport capture, so run it windowed.
##
## Run: Godot --path . res://tools/shot_nav_overlay.tscn
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const NavDebugOverlayScript := preload("res://scripts/city/nav_debug_overlay.gd")

const WORLD_SEED := 42
const COORD := Vector2i(0, 0)
const VOXEL_SIZE := 0.5
## Small enough that one street corner reads clearly; a whole block of stacked building
## floors photographs as a jumble.
const RADIUS_M := 16.0
## Far enough for a corridor that turns a corner.
const PROBE_OFFSET := Vector3(38.0, 0.0, 16.0)
const PATH_TIMEOUT_MS := 5000
## Long enough that all three shots see the blocked columns.
const BLOCK_SEC := 600.0

const CLEARANCE_PNG := "res://tools/nav_overlay_clearance.png"
const COMPONENT_PNG := "res://tools/nav_overlay_component.png"
const CORRIDOR_PNG := "res://tools/nav_overlay_corridor.png"


func _ready() -> void:
	_build_backdrop()
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
		push_error("FAIL bake: %s" % res.get("error", "?"))
		get_tree().quit(1)
		return
	if not nav.register_district(COORD, res["nav_bake"] as RefCounted):
		push_error("FAIL NavService refused district %s" % str(COORD))
		get_tree().quit(1)
		return
	var stats: Dictionary = nav.district_stats(COORD)
	print(
		"district %s spans=%d portals=%d links=%d bytes=%d"
		% [
			str(COORD),
			int(stats["spans"]),
			int(stats["portals"]),
			int(stats["links"]),
			int(stats["bytes"]),
		]
	)

	var ground_y := float(int(res["ground_thickness"])) * VOXEL_SIZE
	var kerb := _street_beside_buildings(res["planner"] as DistrictPlanner, ground_y)
	if not kerb.is_finite():
		push_error("FAIL district %s has no street next to a lot" % str(COORD))
		get_tree().quit(1)
		return
	var start := nav.nearest_surface(NavProfile.Id.PEDESTRIAN, kerb, 20.0)
	if not start.found:
		push_error("FAIL no walkable span within 20 m of the kerb %s" % str(kerb))
		get_tree().quit(1)
		return
	print("overlay centred on %s" % start.position)

	var follow := Node3D.new()
	follow.name = "Follow"
	add_child(follow)
	follow.global_position = start.position

	var overlay: NavDebugOverlay = NavDebugOverlayScript.new() as NavDebugOverlay
	overlay.name = "NavDebugOverlay"
	add_child(overlay)
	overlay.radius_m = RADIUS_M
	overlay.bind_follow(follow)
	overlay.set_enabled(true)
	if not overlay.is_enabled():
		push_error("FAIL overlay refused to switch on")
		get_tree().quit(1)
		return

	var goal := nav.nearest_surface(
		NavProfile.Id.PEDESTRIAN, start.position + PROBE_OFFSET, 24.0
	)
	if not goal.found:
		push_error("FAIL no walkable span near the probe target")
		get_tree().quit(1)
		return
	overlay.probe_to(goal.position)
	var deadline := Time.get_ticks_msec() + PATH_TIMEOUT_MS
	while overlay.corridor_count() == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var corridor := overlay.corridor(NavDebugOverlay.PROBE_CORRIDOR)
	if corridor == null:
		push_error("FAIL probe produced no corridor in %d ms" % PATH_TIMEOUT_MS)
		get_tree().quit(1)
		return
	print(
		"corridor %s %d points %.1f m"
		% [corridor.status_name(), corridor.points.size(), corridor.length_m()]
	)

	## Dynamic blocks the way the failure ladder writes them: a short run of columns an
	## agent found impassable, straddling the corridor.
	for i in range(6):
		var t := 0.25 + 0.05 * float(i)
		overlay.block_column(
			start.position.lerp(goal.position, t) + Vector3(0.0, 0.0, float(i) * 0.5 - 1.0),
			BLOCK_SEC
		)

	var eye := start.position + Vector3(-17.0, 19.0, 21.0)
	await _shoot(overlay, eye, start.position, 60.0, CLEARANCE_PNG)
	overlay.span_colour = NavDebugOverlay.SpanColour.COMPONENT
	await _shoot(overlay, eye, start.position, 60.0, COMPONENT_PNG)
	## Straight down over the route, where the corridor ribbon, the blocked columns and the
	## portals it passes are all in one frame. The follow point moves to the middle of the
	## route first so the ribbon is photographed over spans rather than over the void.
	overlay.span_colour = NavDebugOverlay.SpanColour.HEADROOM
	var mid := start.position.lerp(goal.position, 0.45)
	follow.global_position = mid
	await _shoot(overlay, mid + Vector3(0.0, 30.0, 0.5), mid, 50.0, CORRIDOR_PNG)

	print("RESULT: OK")
	overlay.set_enabled(false)
	NavService.reset()
	get_tree().quit(0)


## A road cell with a built lot next to it, near the middle of the tile. A flat park would
## photograph as one uniform colour and prove nothing about the field.
func _street_beside_buildings(planner: DistrictPlanner, ground_y: float) -> Vector3:
	var origin := DistrictCoord.origin_world(COORD, VOXEL_SIZE)
	var cell_m := float(DistrictCoord.CELL_SIZE) * VOXEL_SIZE
	var mid := Vector2(float(planner.cells_x) * 0.5, float(planner.cells_z) * 0.5)
	var best := Vector3.INF
	var best_d := INF
	for cz in range(1, planner.cells_z - 1):
		for cx in range(1, planner.cells_x - 1):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var lots := 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if LandUse.is_lot(planner.tag_at(cx + d.x, cz + d.y)):
					lots += 1
			if lots < 2:
				continue
			var d2 := Vector2(float(cx), float(cz)).distance_squared_to(mid)
			if d2 >= best_d:
				continue
			best_d = d2
			best = origin + Vector3(
				(float(cx) + 0.5) * cell_m, ground_y, (float(cz) + 0.5) * cell_m
			)
	return best


## A dark, unlit backdrop: the overlay is unshaded, so anything else is only glare.
func _build_backdrop() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.2, 0.2)
	var holder := WorldEnvironment.new()
	holder.name = "Backdrop"
	holder.environment = env
	add_child(holder)


func _shoot(
	overlay: NavDebugOverlay, eye: Vector3, target: Vector3, fov: float, path: String
) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	for i in range(30):
		await get_tree().process_frame
	print("  %s: %s" % [path.get_file(), overlay.counter_line()])
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
