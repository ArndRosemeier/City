## The JIT interior pipeline: bake emits a room per storey, entering one subdivides it,
## and each room is furnished exactly once.
##
## Run: powershell -File tools\run_test.ps1 test_interior_decorator
extends Node

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const InteriorRoomScript := preload("res://scripts/city/interior_room.gd")
const BuildingInteriorScript := preload("res://scripts/city/building_interior.gd")
const InteriorDecoratorScript := preload("res://scripts/city/interior_decorator.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")

## Downtown tile: tall lots, so storeys and elevators actually appear.
const CORE_COORD := Vector2i(0, 0)


## Stand-in for DistrictInstance, exposing only what InteriorDecorator reads.
class FakeDistrict:
	var is_ready: bool = true
	var bake_quality: String = "full"
	var coord: Vector2i = Vector2i(3, 7)
	var origin_vox: Vector3i = Vector3i.ZERO
	var interior_cell_size: int = 512
	var interior_buildings: Dictionary = {}


func _ready() -> void:
	var failed := false
	failed = _check_foot_on_floor_slab(failed)
	failed = _check_bake_storeys(failed)
	failed = _check_decorate_once(failed)
	failed = _check_subdivides_big_floor(failed)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)


## Walker soles often land in the top solid floor cell (y == floor_y), not above it.
func _check_foot_on_floor_slab(failed: bool) -> bool:
	var room: InteriorRoom = InteriorRoomScript.make(
		Rect2i(339, -137, 22, 22), 7, 5, RoomDecoratorScript.Purpose.OFFICE
	)
	var on_slab := Vector3i(352, 7, -132)
	if not room.contains_foot_voxel(on_slab):
		push_error("FAIL foot on floor slab should count as inside: %s" % on_slab)
		failed = true
	if room.contains_foot_voxel(Vector3i(352, 6, -132)):
		push_error("FAIL foot below floor_y should be outside")
		failed = true
	print("  foot-on-slab: ok")
	return failed


## A full bake indexes one BuildingInterior per lot, with a room per walkable storey and
## the elevator reservation on every floor its cabin serves.
func _check_bake_storeys(failed: bool) -> bool:
	var payload: Dictionary = DistrictBakeJobScript.bake({
		"coord": CORE_COORD,
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FULL,
		"bake_nav": false,
	})
	if not bool(payload.get("ok", false)):
		push_error("FAIL bake: %s" % payload.get("error", "?"))
		return true
	var index: Dictionary = payload.get("interior_buildings", {})
	if index.is_empty():
		push_error("FAIL full bake emitted zero interior_buildings")
		return true
	var far: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(1, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FAR,
		"bake_nav": false,
	})
	if not bool(far.get("ok", false)):
		push_error("FAIL far bake: %s" % far.get("error", "?"))
		return true
	if not (far.get("interior_buildings", {}) as Dictionary).is_empty():
		push_error("FAIL far bake should not emit interiors")
		failed = true

	var buildings := _unique_buildings(index)
	var storeys := 0
	var tallest := 0
	var purpose_max := int(RoomDecoratorScript.Purpose.SHOP)
	for b_v in buildings:
		var b: BuildingInterior = b_v as BuildingInterior
		if b.storeys.is_empty():
			push_error("FAIL building %s has no storeys" % b.lot_rect)
			return true
		tallest = maxi(tallest, b.storeys.size())
		var prev_y := -2147483648
		for room in b.storeys:
			storeys += 1
			if room.decorated or room.subdivided:
				push_error("FAIL storey flagged done before enter")
				failed = true
			if room.purpose < 0 or room.purpose > purpose_max:
				push_error("FAIL purpose out of range: %d" % room.purpose)
				failed = true
			if room.rect.size.x < 3 or room.rect.size.y < 3:
				push_error("FAIL storey rect too small: %s" % room.rect)
				failed = true
			if room.floor_y < prev_y:
				push_error("FAIL storeys are not ordered by height")
				failed = true
			prev_y = room.floor_y
			if not b.lot_rect.encloses(room.rect):
				push_error("FAIL storey %s escapes lot %s" % [room.rect, b.lot_rect])
				failed = true
	if tallest < 2:
		push_error("FAIL downtown bake produced no multi-storey interior")
		failed = true
	failed = _check_shaft_landings(payload, buildings, failed)
	print(
		"  bake: %d buildings, %d storeys, tallest=%d"
		% [buildings.size(), storeys, tallest]
	)
	return failed


## Every elevator landing is a storey the decorator knows, and the cabin is reserved there.
func _check_shaft_landings(payload: Dictionary, buildings: Array, failed: bool) -> bool:
	var shafts: Array = payload.get("elevator_shafts", [])
	if shafts.is_empty():
		push_error("FAIL downtown bake produced no elevator shafts")
		return true
	var checked := 0
	for shaft_v in shafts:
		var shaft: ElevatorShaft = shaft_v as ElevatorShaft
		var host := _building_for(buildings, shaft.rect)
		if host == null:
			push_error("FAIL no building hosts shaft %s" % shaft.rect)
			failed = true
			continue
		for y in shaft.floor_ys:
			var room := _storey_at_y(host, int(y))
			if room == null:
				push_error("FAIL shaft landing y=%d has no storey in %s" % [y, host.lot_rect])
				failed = true
				continue
			if not _reserves(room, shaft.rect):
				push_error("FAIL storey y=%d does not reserve its cabin %s" % [y, shaft.rect])
				failed = true
			checked += 1
	print("  shafts: %d landings line up with storeys" % checked)
	return failed


func _unique_buildings(index: Dictionary) -> Array:
	var seen: Array = []
	for b in index.values():
		if not seen.has(b):
			seen.append(b)
	return seen


func _building_for(buildings: Array, rect: Rect2i) -> BuildingInterior:
	for b_v in buildings:
		var b: BuildingInterior = b_v as BuildingInterior
		if b.lot_rect.intersects(rect):
			return b
	return null


func _storey_at_y(building: BuildingInterior, y: int) -> InteriorRoom:
	for room in building.storeys:
		if room.floor_y == y:
			return room
	return null


func _reserves(room: InteriorRoom, cabin: Rect2i) -> bool:
	for c in room.keep_clear:
		if c.encloses(cabin):
			return true
	return false


# ------------------------------------------------------------------- JIT ticks


func _fake_district(building: BuildingInterior) -> FakeDistrict:
	var inst := FakeDistrict.new()
	inst.interior_buildings = {Vector2i.ZERO: building}
	return inst


func _building_of(room: InteriorRoom) -> BuildingInterior:
	var b: BuildingInterior = BuildingInteriorScript.make(
		room.rect.grow(1), room.use
	) as BuildingInterior
	b.storeys.append(room)
	return b


func _foot_in(rect: Rect2i, floor_y: int, offset: Vector2i) -> Vector3:
	return Vector3(
		(rect.position.x + offset.x) * 0.5 + 0.25,
		(floor_y + 1) * 0.5 + 0.1,
		(rect.position.y + offset.y) * 0.5 + 0.25
	)


func _shell_room(brush: CityBrush, volume: RoomVolume) -> void:
	var r := volume.rect
	brush.fill_box(
		Vector3i(r.position.x - 1, volume.floor_y, r.position.y - 1),
		Vector3i(r.end.x + 1, volume.floor_y + volume.air_h + 2, r.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(volume.air_min(), volume.air_max(), VoxelMaterial.AIR)


func _count_props(brush: CityBrush, volume: RoomVolume) -> int:
	var n := 0
	var a := volume.air_min()
	var b := volume.air_max()
	for y in range(a.y, b.y):
		for z in range(a.z, b.z):
			for x in range(a.x, b.x):
				if VoxelMaterial.is_room_prop(brush.get_vox(Vector3i(x, y, z))):
					n += 1
	return n


## A plate too small to partition still furnishes as one room, exactly as before.
func _check_decorate_once(failed: bool) -> bool:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(4, 4, 12, 12), 10, 5)
	_shell_room(brush, volume)

	var room: InteriorRoom = InteriorRoomScript.make(
		volume.rect, volume.floor_y, volume.air_h, RoomDecoratorScript.Purpose.LIVING_ROOM
	)
	var inst := _fake_district(_building_of(room))
	var dec: InteriorDecorator = InteriorDecoratorScript.new() as InteriorDecorator
	dec.brush = brush
	dec.voxel_size = 0.5

	var foot := _foot_in(volume.rect, volume.floor_y, Vector2i(2, 2))
	## First tick plans (and finds nothing to partition), second furnishes.
	if not dec.tick(foot, [inst]):
		push_error("FAIL first enter did nothing")
		return true
	if not room.subdivided:
		push_error("FAIL small room was not marked subdivided")
		failed = true
	if not room.sub_rooms.is_empty():
		push_error("FAIL small room was partitioned anyway (%d parts)" % room.sub_rooms.size())
		failed = true
	if not dec.tick(foot, [inst]):
		push_error("FAIL second tick did not furnish")
		return true
	if not room.decorated:
		push_error("FAIL room.decorated still false after furnishing")
		failed = true
	var props := _count_props(brush, volume)
	if props <= 0:
		push_error("FAIL living room decorated with zero props")
		failed = true
	if dec.tick(foot, [inst]):
		push_error("FAIL a finished room kept working")
		failed = true
	if _count_props(brush, volume) != props:
		push_error("FAIL prop count changed after the room was finished")
		failed = true
	print("  decorate-once props=%d" % props)
	return failed


## A big office storey gets partitioned over several ticks, then every room furnished once.
func _check_subdivides_big_floor(failed: bool) -> bool:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var rect := Rect2i(20, 20, 56, 44)
	var floor_y := 30
	var air_h := 5
	var volume: RoomVolume = RoomVolumeScript.make(rect, floor_y, air_h)
	_shell_room(brush, volume)

	var room: InteriorRoom = InteriorRoomScript.make(
		rect, floor_y, air_h, RoomDecoratorScript.Purpose.OFFICE
	)
	room.use = FloorPlanner.Use.RETAIL_OVER_OFFICE
	room.storey = 4
	var inst := _fake_district(_building_of(room))
	var dec: InteriorDecorator = InteriorDecoratorScript.new() as InteriorDecorator
	dec.brush = brush
	dec.voxel_size = 0.5

	var foot := _foot_in(rect, floor_y, Vector2i(3, 3))
	var ticks := 0
	while dec.tick(foot, [inst]) and ticks < 400:
		ticks += 1
	if ticks >= 400:
		push_error("FAIL the floor never finished (runaway ticks)")
		return true
	if not room.subdivided:
		push_error("FAIL big floor was not subdivided")
		return true
	if room.sub_rooms.size() < 4:
		push_error("FAIL big office floor cut into only %d rooms" % room.sub_rooms.size())
		failed = true
	for sub in room.sub_rooms:
		if not sub.decorated:
			push_error("FAIL sub-room %s never furnished" % sub.rect)
			failed = true
			break
	var glass := 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if brush.get_vox(Vector3i(x, floor_y + 2, z)) == VoxelMaterial.GLASS:
				glass += 1
	if glass <= 0:
		push_error("FAIL office floor got no glass partitions")
		failed = true
	var props := _count_props(brush, volume)
	if props <= 0:
		push_error("FAIL subdivided floor got no props")
		failed = true
	## Partitioning must not take one giant frame: the painter is budgeted per tick.
	if ticks < room.sub_rooms.size() + 1:
		push_error(
			"FAIL expected a tick per room plus paint slices, got %d for %d rooms"
			% [ticks, room.sub_rooms.size()]
		)
		failed = true
	print(
		"  subdivide: %d ticks, %d rooms, %d glass cells, %d props"
		% [ticks, room.sub_rooms.size(), glass, props]
	)
	return failed
