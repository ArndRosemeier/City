## End-to-end proof for the navigation overlay: boots the real city, switches the overlay on
## by feeding the bound key through the input system, and photographs it over the streamed
## voxel world where a reviewer will actually use it.
##
## The synthetic tools/shot_nav_overlay.tscn is the fast picture of the span field; this one
## is the slow picture of the whole wiring — CityRoot's toggle, the walker as the followed
## node, and a probed corridor drawn over the streamed world.
##
## Needs a renderer both for the capture and because the district bake waits on
## `is_area_editable`, which never becomes true headless.
##
## Run: Godot --path . res://tools/shot_nav_overlay_city.tscn
extends Node

const WORLD_SEED := 42
const WALKER_TIMEOUT_MS := 120000
const SETTLE_MS := 6000
const CORRIDOR_TIMEOUT_MS := 8000
const SHOT_HOUR := 10.0

const STREET_PNG := "res://tools/nav_overlay_city_street.png"
const ABOVE_PNG := "res://tools/nav_overlay_city_above.png"
const WATER_PNG := "res://tools/nav_overlay_city_water.png"

## Water search around the walker, in metres. The lake a booted seed-42 walker spawns beside
## is what makes the span field look as though it runs out to sea.
const WATER_PROBE_STEP_M := 4.0
const WATER_PROBE_RINGS := 14

## Cursor hunt over the lower half of the frame: rows as a fraction of viewport height,
## columns as an offset from its centre, and how far each candidate ray reaches.
const AIM_ROW_FROM := 0.54
const AIM_ROW_STEP := 0.04
const AIM_ROWS := 9
const AIM_COLS: Array[float] = [0.0, -0.14, 0.14, -0.28, 0.28, -0.40, 0.40]
const AIM_RAY_M := 90.0
const AIM_SNAP_M := 3.0


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)

	var walker: Node3D = null
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		walker = city.get_node_or_null("Walker") as Node3D
		if walker != null:
			break
	if walker == null:
		push_error("FAIL no walker after %d ms" % WALKER_TIMEOUT_MS)
		get_tree().quit(1)
		return
	var settle := Time.get_ticks_msec() + SETTLE_MS
	while Time.get_ticks_msec() < settle:
		await get_tree().process_frame

	var nav := NavService.peek()
	if nav == null or not nav.is_configured():
		push_error("FAIL the booted city never configured NavService")
		get_tree().quit(1)
		return
	print("nav has %d districts at v%d" % [nav.district_count(), nav.version()])

	var overlay := city.get_node_or_null("NavDebugOverlay") as NavDebugOverlay
	if overlay == null:
		push_error("FAIL CityRoot built no NavDebugOverlay")
		get_tree().quit(1)
		return
	if overlay.is_enabled():
		push_error("FAIL the overlay was already on before anyone pressed anything")
		get_tree().quit(1)
		return

	## The whole point of this tool: the bound key, not the API behind it.
	_press(PlayerControls.default_binding("nav_overlay"))
	await _frames(6)
	if not overlay.is_enabled():
		push_error("FAIL pressing the nav_overlay key left the overlay off")
		get_tree().quit(1)
		return
	if overlay.spans_drawn <= 0:
		push_error("FAIL the overlay drew no spans around the player")
		get_tree().quit(1)
		return

	var shot_cam := walker.call("get_camera") as Camera3D
	if shot_cam == null:
		push_error("FAIL the walker has no camera to shoot from")
		get_tree().quit(1)
		return

	## The probe aims with the cursor, so the cursor has to sit on ground a pedestrian can
	## actually reach — the crosshair points at whatever the walker happens to face, and on
	## this lakeside spawn that is open water no pedestrian corridor can end on.
	## CityRoot aims the probe with the OS cursor, which a capture run does not own: the window
	## is not focused, `Input.warp_mouse` is ignored, and the live provider would repoint the
	## corridor at whatever the operator's mouse happens to rest on every half second. So take
	## the provider off and probe at a point this camera's own aim ray finds.
	overlay.bind_aim_provider(Callable())
	var target := _pathable_target(nav, shot_cam, walker)
	if not target.is_finite():
		push_error("FAIL nothing under the lower half of the frame is pedestrian-reachable")
		get_tree().quit(1)
		return
	print("aim: probing %s, %.1f m out" % [
		str(target), walker.global_position.distance_to(target)
	])
	overlay.probe_to(target)
	var corridor_deadline := Time.get_ticks_msec() + CORRIDOR_TIMEOUT_MS
	while overlay.corridor_count() == 0 and Time.get_ticks_msec() < corridor_deadline:
		await get_tree().process_frame
	if overlay.corridor_count() == 0:
		push_error("FAIL the cursor aim probe produced no corridor in %d ms" % CORRIDOR_TIMEOUT_MS)
		get_tree().quit(1)
		return

	## A block where the player stands, the way the failure ladder writes one.
	overlay.block_column(walker.global_position, 600.0)
	_hide_city_hud(city)
	_hide_error_panel()
	_pin_hour(city)
	await _frames(10)
	print("in-game counters: %s" % overlay.counter_line())

	await _shoot(STREET_PNG)

	## Second angle from above, so the street layout the spans describe is legible.
	var eye := walker.global_position + Vector3(-9.0, 13.0, 11.0)
	await _shoot_from(eye, walker.global_position, 55.0, ABOVE_PNG)

	await _shoot_water(nav, overlay, walker)

	print("RESULT: OK")
	get_tree().quit(0)


## The span field over open water, and what a pedestrian can actually do with it.
##
## The field carries the lake bed, so the overlay draws spans under the water surface out to
## the deepest cell — which is what looks like a walkable sea. The numbers printed here are
## the answer: the same column a giant wades, a pedestrian has no footing on at all, and a
## corridor from the shore stops at the depth its profile's max_wade allows.
func _shoot_water(nav: NavService, overlay: NavDebugOverlay, walker: Node3D) -> void:
	var shore := walker.global_position
	var deepest := Vector3.INF
	var deepest_cells := 0
	for ring in range(1, WATER_PROBE_RINGS + 1):
		var reach := float(ring) * WATER_PROBE_STEP_M
		for step in range(16):
			var angle := TAU * float(step) / 16.0
			var probe := shore + Vector3(sin(angle) * reach, 0.0, cos(angle) * reach)
			## The giant wades six cells, so it is the profile that can stand on a lake bed
			## at all and therefore the one that can report how deep the water over it is.
			var hit := nav.nearest_surface(NavProfile.Id.GIANT, probe, 3.0)
			if not hit.found or hit.water_depth <= deepest_cells:
				continue
			deepest_cells = hit.water_depth
			deepest = hit.position
	if deepest_cells <= 0:
		push_error("FAIL no submerged span within %.0f m of the walker, nothing to photograph"
			% (float(WATER_PROBE_RINGS) * WATER_PROBE_STEP_M))
		return
	var ped := nav.nearest_surface(NavProfile.Id.PEDESTRIAN, deepest, 1.0)
	var route := nav.find_path_now(NavProfile.Id.PEDESTRIAN, shore, deepest, 200000)
	var reached := 0
	if route.points.size() > 0:
		var end: Vector3 = route.points[route.points.size() - 1]
		var end_hit := nav.nearest_surface(NavProfile.Id.GIANT, end, 1.0)
		if end_hit.found:
			reached = end_hit.water_depth
	print(
		(
			"water: deepest span %.1f m out is under %d cells; pedestrian footing there=%s;"
			+ " a pedestrian route from the shore is %s and stops in %d cells"
		)
		% [
			shore.distance_to(deepest),
			deepest_cells,
			str(ped.found),
			route.status_name(),
			reached,
		]
	)

	## Centre the layers on the water and photograph it from just above the surface, where a
	## submerged span reads as submerged instead of as a floor.
	var at_water := Node3D.new()
	at_water.name = "WaterCentre"
	add_child(at_water)
	at_water.global_position = deepest
	overlay.bind_follow(at_water)
	await _frames(12)
	## Steep enough to see through the surface: at a grazing angle the water reflects and the
	## submerged spans would be the reviewer's word against the picture.
	var eye := deepest + Vector3(4.0, 11.0, 15.0)
	await _shoot_from(eye, deepest, 55.0, WATER_PNG)
	overlay.bind_follow(walker)
	at_water.queue_free()


## Point in shot that a pedestrian corridor can end on, found the way the player's cursor
## would find it: a camera ray into the lower half of the frame, where the ground is.
##
## A seed-42 walker faces the lake, and no pedestrian has footing anywhere on it, so the
## sweep sits off the view axis as well as below it.
func _pathable_target(nav: NavService, cam: Camera3D, walker: Node3D) -> Vector3:
	var body := walker as CollisionObject3D
	if body == null:
		push_error("FAIL the walker is not a collision object, cannot copy its aim ray")
		return Vector3.INF
	var space := cam.get_world_3d().direct_space_state
	var view := get_viewport().get_visible_rect().size
	var here := walker.global_position
	var candidates: Array[Vector3] = []
	for row in range(AIM_ROWS):
		var sy := view.y * (AIM_ROW_FROM + AIM_ROW_STEP * float(row))
		for col in range(AIM_COLS.size()):
			var screen := Vector2(view.x * (0.5 + AIM_COLS[col]), sy)
			var from := cam.project_ray_origin(screen)
			var query := PhysicsRayQueryParameters3D.create(
				from, from + cam.project_ray_normal(screen) * AIM_RAY_M
			)
			query.collision_mask = 1
			query.exclude = [body.get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var surface := nav.nearest_surface(
				NavProfile.Id.PEDESTRIAN, hit["position"] as Vector3, AIM_SNAP_M
			)
			if surface.found:
				candidates.append(surface.position)
	## Farthest first: a corridor a metre long is a dot in the picture.
	candidates.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return a.distance_to(here) > b.distance_to(here)
	)
	for point: Vector3 in candidates:
		var route := nav.find_path_now(NavProfile.Id.PEDESTRIAN, here, point, 200000)
		if route.is_usable() and route.points.size() >= 2:
			return point
	return Vector3.INF


## Feed one PlayerControls binding through the input system as a press and a release.
func _press(binding: Dictionary) -> void:
	if str(binding.get("device", "")) != "key":
		push_error("FAIL binding %s is not a key" % PlayerControls.format_binding(binding))
		return
	var code := int(binding["code"]) as Key
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.shift_pressed = bool(binding.get("shift", false))
		ev.ctrl_pressed = bool(binding.get("ctrl", false))
		ev.alt_pressed = bool(binding.get("alt", false))
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _hide_city_hud(city: CityRoot) -> void:
	for child in city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


## The autoloaded error panel sits over the middle of the frame. Everything it lists is also on
## stdout, so hiding it for the capture hides nothing from the reviewer.
func _hide_error_panel() -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		push_error("FAIL no ErrorOverlay autoload to hide")
		return
	panel.visible = false


func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)


## Capture whatever camera is current — for the first shot that is the player's own.
func _shoot(path: String) -> void:
	for i in range(20):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)


func _shoot_from(eye: Vector3, target: Vector3, fov: float, path: String) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _shoot(path)
	cam.queue_free()


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
