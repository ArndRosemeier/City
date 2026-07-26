## Traffic look inspection: boots the live city and photographs the cars where they
## actually drive, so the showroom pad cannot hide street-level problems.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Pass --spawn-theme=… after a bare -- to pick the district.
extends Node

const WORLD_SEED := 42
const WALKER_TIMEOUT_MS := 90000
const SETTLE_MS := 8000
const PROMOTE_MS := 4000
const SHOT_HOUR := 10.0
const CLOSE_PNG := "res://tools/traffic_close.png"
const STREET_PNG := "res://tools/traffic_street.png"
const ABOVE_PNG := "res://tools/traffic_above.png"


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
	## Let traffic spawn and settle onto the road graph.
	var settle := Time.get_ticks_msec() + SETTLE_MS
	while Time.get_ticks_msec() < settle:
		await get_tree().process_frame

	var director := _busiest_director(city)
	if director == null:
		push_error("FAIL no vehicle director loaded")
		get_tree().quit(1)
		return
	print("director has %d cars" % director.vehicle_live_count())

	## Cars only get full visuals near the city camera, so walk to one first.
	var target := _nearest_agent(director, walker.global_position)
	if target == Vector3.ZERO:
		push_error("FAIL director has no cars")
		get_tree().quit(1)
		return
	walker.global_position = target + Vector3(6.0, 1.0, 6.0)
	var promote := Time.get_ticks_msec() + PROMOTE_MS
	while Time.get_ticks_msec() < promote:
		await get_tree().process_frame
	if director.count_lod_tiers().x <= 0:
		push_error("FAIL no car promoted to near LOD")
		get_tree().quit(1)
		return

	_hide_hud(city)
	_pin_hour(city)
	## Freeze traffic so all three shots frame the same car.
	get_tree().paused = true
	var car := _nearest_visual(director, walker.global_position)
	if car == Vector3.ZERO:
		push_error("FAIL no visible car visual to photograph")
		get_tree().quit(1)
		return
	print("photographing car visual at %s" % car)

	await _shoot(car + Vector3(4.5, 1.7, 5.5), car + Vector3(0.0, 0.7, 0.0), 50.0, CLOSE_PNG)
	await _shoot(car + Vector3(9.0, 2.2, 11.0), car + Vector3(0.0, 1.0, 0.0), 60.0, STREET_PNG)
	await _shoot(car + Vector3(6.0, 14.0, 10.0), car + Vector3(1.5, 0.0, 1.5), 60.0, ABOVE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _busiest_director(city: CityRoot) -> VehicleDirector:
	var best: VehicleDirector = null
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.vehicles == null or not is_instance_valid(di.vehicles):
			continue
		if best == null or di.vehicles.count_lod_tiers().x > best.count_lod_tiers().x:
			best = di.vehicles
	return best


func _nearest_agent(director: VehicleDirector, from: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for i in range(director.vehicle_live_count()):
		var p := director.sample_agent_position(i)
		if p == Vector3.ZERO:
			continue
		var d := from.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


## Aims at a spawned visual rather than an agent's logical position, so a car that
## failed to get a mesh cannot leave the camera pointed at empty road.
func _nearest_visual(director: VehicleDirector, from: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for child in director.get_children():
		var vis := child as VehicleVisual
		if vis == null or not vis.visible:
			continue
		var d := from.distance_to(vis.global_position)
		if d < best_d:
			best_d = d
			best = vis.global_position
	return best


## Boot time drifts between runs, so shots are pinned to mid-morning to keep the
## sun angle (and therefore the shadows) comparable run to run.
func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)
	print("pinned hour to %.1f" % SHOT_HOUR)


func _hide_hud(city: CityRoot) -> void:
	for child in city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _shoot(eye: Vector3, target: Vector3, fov: float, path: String) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	for _k in range(60):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
