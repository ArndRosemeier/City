## Downtown massing inspection: boots the live city on the high-rise tile and saves a
## skyline, a plan view and a street-level shot, plus a footprint report.
##
## The plan view is the point: ground area per building is what decides whether a tower
## reads as a tower or as a needle, and it is invisible from any eye-level angle.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Run: powershell -File tools\run_test.ps1 shot_downtown_massing -Rendered -GodotArgs "--spawn-district=0,0"
extends Node

const WORLD_SEED := 42
const SKYLINE_PNG := "res://tools/downtown_skyline.png"
const PLAN_PNG := "res://tools/downtown_plan.png"
const STREET_PNG := "res://tools/downtown_street.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	## Wall-clock, not frame count: the district bakes on worker threads while the main loop
	## spins at hundreds of FPS, so a frame budget expires before the walker exists.
	var deadline := Time.get_ticks_msec() + 90_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 90 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	var coord := city.spawn_district_coord
	var theme := DistrictTheme.for_district(WORLD_SEED, coord)
	print("spawn district %s = %s" % [coord, theme.display_name])
	if theme.id != DistrictTheme.CORE_HIGHRISE:
		push_error(
			"FAIL spawned in %s — pass --spawn-district=0,0 to inspect downtown massing"
			% theme.display_name
		)
		get_tree().quit(1)
		return

	## Mid-tile first, just to get the district instance; the tile centre is the grand plaza,
	## which says nothing about massing.
	var center := DistrictCoord.center_world(coord, CityRoot.VOXEL_SIZE)
	walker.global_position = Vector3(center.x, 60.0, center.z)
	await _settle(8.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	_report(inst)

	## Park the walker on the biggest amalgamated parcel so the near voxels mesh around the
	## tallest thing downtown builds.
	var anchor := _biggest_parcel_world(inst)
	walker.global_position = Vector3(anchor.x, 60.0, anchor.z)
	await _settle(14.0)

	await _shoot(anchor, Vector3(-190.0, 150.0, 240.0), Vector3(-0.45, -0.66, 0.0), SKYLINE_PNG)
	await _shoot(anchor, Vector3(0.0, 460.0, 0.0), Vector3(-1.5707, 0.0, 0.0), PLAN_PNG)
	## Stand on a real road cell and look up the tower — an offset guess lands inside a
	## neighbouring building now that lots build flush to the block edge.
	var eye := float(inst.generator.ground_thickness) * CityRoot.VOXEL_SIZE + 2.5
	await _shoot_at(
		_street_stand(inst, eye), anchor + Vector3(0.0, 45.0, 0.0), STREET_PNG
	)
	print("RESULT: OK")
	get_tree().quit(0)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for d: Variant in districts:
		var di: DistrictInstance = d
		if di.coord == want and di.generator != null:
			return di
	return null


## World centre of the largest merged parcel — the tallest building downtown builds.
func _biggest_parcel_world(inst: DistrictInstance) -> Vector3:
	var gen: DistrictGenerator = inst.generator
	var planner: DistrictPlanner = gen.get_planner()
	var best := Rect2i()
	for rect: Rect2i in planner.tower_parcels:
		if rect.get_area() > best.get_area():
			best = rect
	if best.get_area() <= 0:
		push_error("FAIL downtown tile merged no parcels")
		return DistrictCoord.center_world(inst.coord, CityRoot.VOXEL_SIZE)
	var cs := float(gen.cell_size)
	return Vector3(
		(float(inst.origin_vox.x) + (float(best.position.x) + float(best.size.x) * 0.5) * cs)
		* CityRoot.VOXEL_SIZE,
		0.0,
		(float(inst.origin_vox.z) + (float(best.position.y) + float(best.size.y) * 0.5) * cs)
		* CityRoot.VOXEL_SIZE
	)


## Eye-height point on the road cell furthest from the biggest parcel but still within a few
## cells of it, so the whole tower fits in frame from the pavement.
func _street_stand(inst: DistrictInstance, eye: float) -> Vector3:
	var gen: DistrictGenerator = inst.generator
	var planner: DistrictPlanner = gen.get_planner()
	var best := Rect2i()
	for rect: Rect2i in planner.tower_parcels:
		if rect.get_area() > best.get_area():
			best = rect
	var center := Vector2(
		float(best.position.x) + float(best.size.x) * 0.5,
		float(best.position.y) + float(best.size.y) * 0.5
	)
	var stand := Vector3.ZERO
	var best_d := -1.0
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var cx := best.position.x + dx
			var cz := best.position.y + dz
			if not planner.has_road_cell(cx, cz):
				continue
			var d := (Vector2(float(cx) + 0.5, float(cz) + 0.5) - center).length()
			if d > 6.0 or d <= best_d:
				continue
			best_d = d
			stand = _cell_world(inst, Vector2(float(cx) + 0.5, float(cz) + 0.5))
	if best_d < 0.0:
		push_error("FAIL no road cell within 6 cells of parcel %s" % best)
		return Vector3(center.x, eye, center.y)
	return Vector3(stand.x, eye, stand.z)


func _cell_world(inst: DistrictInstance, cell: Vector2) -> Vector3:
	var cs := float(inst.generator.cell_size)
	return Vector3(
		(float(inst.origin_vox.x) + cell.x * cs) * CityRoot.VOXEL_SIZE,
		0.0,
		(float(inst.origin_vox.z) + cell.y * cs) * CityRoot.VOXEL_SIZE
	)


## Footprint area per painted lot, plus the tallest massing box, so the numbers behind the
## pictures land in the log next to them.
func _report(inst: DistrictInstance) -> void:
	var gen: DistrictGenerator = inst.generator
	var planner: DistrictPlanner = gen.get_planner()
	var vs := gen.voxel_size
	var areas: Array[float] = []
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_lot(planner.tag_at(cx, cz)):
				continue
			if planner.is_tower_parcel_secondary(cx, cz):
				continue
			if planner.rect_is_landlocked(gen._lot_rect(cx, cz)):
				continue
			var paint := gen._lot_paint_bounds(cx, cz)
			var inner := gen._buildable_bounds(paint[0], paint[1], cx, cz)
			var w := inner[1].x - inner[0].x
			var d := inner[1].z - inner[0].z
			if w < 6 or d < 6:
				continue
			areas.append(float(w) * float(d) * vs * vs)
	areas.sort()
	var top_m := 0.0
	for imp: Variant in gen.building_impostors:
		var part: Dictionary = imp
		var c: Vector3 = part["center"]
		var s: Vector3 = part["size"]
		top_m = maxf(top_m, c.y + s.y * 0.5)
	if areas.is_empty():
		push_error("FAIL downtown tile painted no lots")
		return
	var sum := 0.0
	for a in areas:
		sum += a
	print(
		(
			"downtown: %d buildings on %d merged parcels, footprint %.0f–%.0f m²"
			+ " (median %.0f, mean %.0f), tallest %.0f m"
		)
		% [
			areas.size(), planner.tower_parcels.size(), areas[0], areas[areas.size() - 1],
			areas[areas.size() / 2], sum / float(areas.size()), top_m,
		]
	)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(anchor: Vector3, offset: Vector3, rot: Vector3, path: String) -> void:
	var cam := _add_camera(anchor + offset)
	cam.rotation = rot
	await _capture(cam, path)


func _shoot_at(pos: Vector3, target: Vector3, path: String) -> void:
	var cam := _add_camera(pos)
	cam.look_at(target)
	await _capture(cam, path)


func _add_camera(pos: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.position = pos
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	return cam


func _capture(cam: Camera3D, path: String) -> void:
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
