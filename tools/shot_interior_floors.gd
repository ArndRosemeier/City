## Interior subdivision inspection: boots the live city downtown, stands the walker on a
## shop floor, an office floor and a floor of flats, and saves what the JIT decorator
## built there.
##
## The walker is re-pinned every frame while a floor decorates — InteriorDecorator only
## works on the storey under the foot, and one dropped frame stops it half-furnished.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload.
## Run: powershell -File tools\run_test.ps1 shot_interior_floors -Rendered -GodotArgs "--spawn-district=0,0"
extends Node

const WORLD_SEED := 42
const ENTRANCE_PNG := "res://tools/interior_entrance.png"
const SHOP_PNG := "res://tools/interior_shop.png"
const OFFICE_PNG := "res://tools/interior_office.png"
const FLATS_PNG := "res://tools/interior_flats.png"
## Seconds to hold the walker on a floor: plan, paint slices, then one room per frame.
const DWELL := 6.0


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
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
			"FAIL spawned in %s — pass --spawn-district=0,0 to inspect downtown interiors"
			% theme.display_name
		)
		get_tree().quit(1)
		return

	var center := DistrictCoord.center_world(coord, CityRoot.VOXEL_SIZE)
	walker.global_position = Vector3(center.x, 60.0, center.z)
	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return

	var offices := _pick(inst, [FloorPlanner.Use.OFFICE, FloorPlanner.Use.RETAIL_OVER_OFFICE])
	var homes := _pick(
		inst, [FloorPlanner.Use.RESIDENTIAL, FloorPlanner.Use.RETAIL_OVER_FLATS]
	)
	if offices == null:
		push_error("FAIL downtown tile has no office building")
		get_tree().quit(1)
		return
	var failed := false
	failed = await _shoot_entrance(walker, inst, offices, failed)
	failed = await _visit(city, walker, offices, 0, SHOP_PNG, failed)
	failed = await _visit(city, walker, offices, _best_storey(city, offices), OFFICE_PNG, failed)
	if homes == null:
		print("note: no residential building on this tile, skipping the flats shot")
	else:
		failed = await _visit(city, walker, homes, _best_storey(city, homes), FLATS_PNG, failed)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for d: Variant in districts:
		var di: DistrictInstance = d
		if di.coord == want and di.generator != null:
			return di
	return null


## Tallest building of one of `uses` whose plate is big enough to be partitioned.
func _pick(inst: DistrictInstance, uses: Array) -> BuildingInterior:
	var best: BuildingInterior = null
	for b_v in inst.interior_buildings.values():
		var b: BuildingInterior = b_v as BuildingInterior
		if not uses.has(b.use) or b.storeys.size() < 2:
			continue
		var plate := b.storeys[0].rect
		if plate.size.x * plate.size.y < FloorPlanner.MIN_PLAN_AREA:
			continue
		if best == null or b.storeys.size() > best.storeys.size():
			best = b
	return best


## Head on to a street door from the pavement: façade trim is painted after the shell,
## so this is where a storefront band or awning would be caught sealing the entrance.
func _shoot_entrance(
	walker: Node3D, inst: DistrictInstance, building: BuildingInterior, failed: bool
) -> bool:
	var door: CastleDoorway = null
	for d_v in inst.lot_doorways:
		var d: CastleDoorway = d_v as CastleDoorway
		if building.lot_rect.grow(2).has_point(d.center):
			door = d
			break
	if door == null:
		push_error("FAIL office building %s has no street door" % building.lot_rect)
		return true
	var vs := CityRoot.VOXEL_SIZE
	var out := -door.axis
	var stand := Vector2(door.center) + Vector2(out) * 7.0
	var eye := Vector3((stand.x + 0.5) * vs, float(door.floor_y) * vs + 1.6, (stand.y + 0.5) * vs)
	var target := Vector3(
		(float(door.center.x) + 0.5) * vs,
		float(door.floor_y + door.height / 2) * vs,
		(float(door.center.y) + 0.5) * vs
	)
	print("interior_entrance.png: door %s facing %s" % [door.center, out])
	## The streamer meshes around the walker, not around the camera — park it a few
	## voxels behind the lens so it does not photograph its own shoulder.
	var park := Vector2(stand) + Vector2(out) * 5.0
	await _pin(
		walker, Vector3((park.x + 0.5) * vs, float(door.floor_y) * vs + 0.2, (park.y + 0.5) * vs), DWELL
	)
	await _shoot_at(eye, target, ENTRANCE_PNG)
	return failed


## The upper storey with the most standable floor — massed and stepped archetypes leave
## some upper plates almost solid, and those are not worth photographing.
func _best_storey(city: CityRoot, building: BuildingInterior) -> int:
	var best := 1
	var best_free := -1
	for i in range(1, building.storeys.size()):
		var room: InteriorRoom = building.storeys[i]
		var mask := FloorMask.from_brush(city._brush, room.rect, room.floor_y, room.air_h)
		if mask.free_count() > best_free:
			best_free = mask.free_count()
			best = i
	return best


## Stand on a storey until the decorator has finished it, then shoot across the floor.
func _visit(
	city: CityRoot,
	walker: Node3D,
	building: BuildingInterior,
	storey: int,
	path: String,
	failed: bool
) -> bool:
	var room: InteriorRoom = building.storeys[storey]
	var stand := _world_of(room, room.rect.position + room.rect.size / 4, 0.6)
	await _pin(walker, stand, DWELL)
	if not room.subdivided:
		push_error("FAIL storey %d of %s never subdivided" % [storey, building.lot_rect])
		failed = true
	var left := 0
	for sub in room.sub_rooms:
		if not sub.decorated:
			left += 1
	## Standable columns decide whether a plate is plannable at all, so report them
	## next to the room count — an empty plan is usually a blocked floor, not a bug.
	var mask := FloorMask.from_brush(city._brush, room.rect, room.floor_y, room.air_h)
	print(
		"%s: use=%s storey=%d rect=%s air_h=%d free=%d/%d rooms=%d undecorated=%d"
		% [
			path.get_file(),
			FloorPlanner.use_name(building.use as FloorPlanner.Use),
			storey,
			room.rect,
			room.air_h,
			mask.free_count(),
			room.rect.size.x * room.rect.size.y,
			room.sub_rooms.size(),
			left,
		]
	)
	## Eye height in the near corner, looking diagonally across the plate.
	var eye := _world_of(room, room.rect.position + Vector2i(3, 3), 1.6)
	var target := _world_of(room, room.rect.end - Vector2i(4, 4), 1.2)
	await _shoot_at(eye, target, path)
	return failed


func _world_of(room: InteriorRoom, cell: Vector2i, height_m: float) -> Vector3:
	var vs := CityRoot.VOXEL_SIZE
	return Vector3(
		(float(cell.x) + 0.5) * vs,
		float(room.floor_y + 1) * vs + height_m,
		(float(cell.y) + 0.5) * vs
	)


## Hold the walker in place: the streamer keeps meshing around it and the decorator keeps
## ticking the storey it stands in.
func _pin(walker: Node3D, pos: Vector3, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		walker.global_position = pos
		await get_tree().process_frame


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot_at(pos: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = pos
	cam.fov = 80.0
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	cam.look_at(target)
	await _settle(2.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
