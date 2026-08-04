## Japanese-garden dressing inspection for the Gaming plaza.
##
## The garden is judged from the ground: a torii is only a torii if the posts, the tie
## beam and the swept top rail read as three separate things at eye level. The aerial is
## here for the opposite question — how much of the tile the garden leaves alone.
##
## Run: powershell -File tools\run_test.ps1 shot_gaming_garden -Rendered -TimeoutSec 400 -GodotArgs "--spawn-theme=gaming"
extends Node

const APPROACH_PNG := "res://tools/garden_approach.png"
const GATE_PNG := "res://tools/garden_gate.png"
const COURT_PNG := "res://tools/garden_court.png"
const POND_PNG := "res://tools/garden_pond.png"
const WIDE_PNG := "res://tools/garden_wide.png"
const VS := 0.5


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")

	var theme := DistrictTheme.for_district(city.city_seed, city.spawn_district_coord)
	if theme.id != DistrictTheme.GAMING:
		push_error("FAIL spawn district is %s, expected Gaming" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var layout: GamingLayout = inst.generator.get_gaming_layout()
	if layout == null:
		push_error("FAIL no gaming layout on the loaded district")
		get_tree().quit(1)
		return
	if layout.garden_max == Vector3i.ZERO:
		push_error("FAIL layout carries no garden precinct — GamingGarden never ran")
		get_tree().quit(1)
		return

	var origin := inst.origin_vox
	var band_w := layout.garden_max.x - layout.garden_min.x
	var band_d := layout.garden_max.z - layout.garden_min.z
	print(
		"garden precinct %d x %d vox = %.1f%% of the %d x %d tile"
		% [
			band_w,
			band_d,
			(
				100.0 * float(band_w * band_d)
				/ float(DistrictCoord.SIZE_X_VOX * DistrictCoord.SIZE_Z_VOX)
			),
			DistrictCoord.SIZE_X_VOX,
			DistrictCoord.SIZE_Z_VOX,
		]
	)

	var table_mid := layout.main_table_origin + Vector3i(9, 2, 5)
	var pad_mid := (layout.pad_min + layout.pad_max) / 2

	## The walk up: stepping stones, the tall south gate, lanterns lining the corridor.
	var approach := _world(origin, table_mid + Vector3i(0, 0, -30))
	walker.global_position = approach + Vector3(0.0, 1.0, 0.0)
	await _settle(10.0)
	await _shoot(approach + Vector3(0.0, 1.7, 0.0), _world(origin, table_mid), APPROACH_PNG)

	## One gate close up, off-axis so the kasagi overhang and the sweep are both visible.
	## Stand well back on the meadow side: closer than the wings and the camera ends up
	## inside a lantern cap.
	var gate := _world(origin, Vector3i(pad_mid.x, layout.pad_min.y, layout.pad_max.z + 6))
	var gate_eye := gate + Vector3(-14.0, 3.0, 14.0)
	walker.global_position = gate_eye + Vector3(0.0, 1.0, 0.0)
	await _settle(8.0)
	await _shoot(gate_eye, gate + Vector3(0.0, 2.5, 0.0), GATE_PNG)

	## Raked court west of the table: do the ripple rings read as combed sand?
	var court := _world(origin, layout.main_table_origin + Vector3i(-18, 1, 6))
	var court_eye := court + Vector3(0.0, 4.0, -9.0)
	walker.global_position = court_eye
	await _settle(8.0)
	await _shoot(court_eye, court, COURT_PNG)

	## Pond east of the table, with the plank bridge.
	var pond := _world(origin, layout.main_table_origin + Vector3i(33, 1, 5))
	var pond_eye := pond + Vector3(0.0, 5.0, -11.0)
	walker.global_position = pond_eye
	await _settle(8.0)
	await _shoot(pond_eye, pond, POND_PNG)

	## Whole precinct from above: garden band against the meadow it deliberately leaves.
	var wide := _world(origin, pad_mid)
	walker.global_position = wide + Vector3(0.0, 60.0, 0.0)
	await _settle(12.0)
	await _shoot(wide + Vector3(0.0, 62.0, 62.0), wide, WIDE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _world(origin_vox: Vector3i, local: Vector3i) -> Vector3:
	return Vector3(
		float(origin_vox.x + local.x) * VS,
		float(origin_vox.y + local.y) * VS,
		float(origin_vox.z + local.z) * VS
	)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
