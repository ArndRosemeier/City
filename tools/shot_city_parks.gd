## Park look inspection: boots the live city, walks to the spawn district's large park
## and the nearest pocket park, and saves eye-level plus overhead shots of each.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Needs a tile that actually has a park in it — a lake or castle tile has none, and the
## seeded spawn is whatever the seed says:
##
##   powershell -Command "& '.\tools\run_test.ps1' -Scene shot_city_parks -Rendered
##     -GodotArgs @('--spawn-theme=garden')"
extends Node

const WORLD_SEED := 42
const LARGE_EYE_PNG := "res://tools/park_large_eye.png"
const LARGE_TOP_PNG := "res://tools/park_large_top.png"
const POCKET_EYE_PNG := "res://tools/park_pocket_eye.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	## Waited out on the clock, not on a frame count: the walker only appears once the spawn
	## district has baked, and an empty scene runs at several hundred frames a second, so a
	## frame budget expires in a few seconds and reports a city that was still loading.
	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	await _settle(10.0)

	var spawn_district := _spawn_district(city)
	if spawn_district == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	var planner := spawn_district.generator.get_planner()
	print("large park cells %s, %d pocket parks" % [planner.large_park, planner.pocket_parks.size()])
	var lp := planner.large_park
	## Without this the tool photographs the tile origin and reports OK, which is how a park
	## regression hides behind a picture of a street.
	if lp.size.x <= 0 or lp.size.y <= 0:
		push_error(
			"FAIL district %s has no large park — run with --spawn-theme=garden"
			% spawn_district.coord
		)
		get_tree().quit(1)
		return

	var large_center := _cell_world(spawn_district, Vector2(
		float(lp.position.x) + float(lp.size.x) * 0.5,
		float(lp.position.y) + float(lp.size.y) * 0.5
	))
	await _goto(walker, large_center)
	await _shoot(walker.global_position, Vector3(0.0, 2.5, 26.0), Vector3(-0.08, 0.0, 0.0), LARGE_EYE_PNG)
	await _shoot(walker.global_position, Vector3(0.0, 60.0, 42.0), Vector3(-0.85, 0.0, 0.0), LARGE_TOP_PNG)

	if not planner.pocket_parks.is_empty():
		var pocket: Vector2i = planner.pocket_parks[0]
		var pocket_center := _cell_world(spawn_district, Vector2(float(pocket.x) + 0.5, float(pocket.y) + 0.5))
		await _goto(walker, pocket_center)
		await _shoot(walker.global_position, Vector3(0.0, 6.0, 16.0), Vector3(-0.35, 0.0, 0.0), POCKET_EYE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.coord == want and di.generator != null:
			return di
	return null


func _cell_world(di: DistrictInstance, cell: Vector2) -> Vector3:
	var cs := float(di.generator.cell_size)
	return Vector3(
		(float(di.origin_vox.x) + cell.x * cs) * CityRoot.VOXEL_SIZE,
		0.0,
		(float(di.origin_vox.z) + cell.y * cs) * CityRoot.VOXEL_SIZE
	)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Terrain only meshes around the walker, so it is parked at the target and given time to
## mesh before anything is photographed.
func _goto(walker: Node3D, target: Vector3) -> void:
	walker.global_position = Vector3(target.x, 40.0, target.z)
	await _settle(12.0)


func _shoot(anchor: Vector3, offset: Vector3, rot: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = anchor + offset
	cam.rotation = rot
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	await _settle(2.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
