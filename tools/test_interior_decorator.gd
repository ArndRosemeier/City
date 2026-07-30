## Offline smoke: InteriorDecorator stamps once on enter; second tick is a no-op.
##
## Run: Godot --headless --path . -s res://tools/test_interior_decorator.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const InteriorRoomScript := preload("res://scripts/city/interior_room.gd")
const InteriorDecoratorScript := preload("res://scripts/city/interior_decorator.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")


## Stand-in for DistrictInstance (avoids CityProfiler autoload in -s runs).
class FakeDistrict:
	var is_ready: bool = true
	var bake_quality: String = "full"
	var coord: Vector2i = Vector2i(3, 7)
	var interior_rooms: Array = []


func _initialize() -> void:
	var failed := false
	failed = _check_emit_and_purpose(failed)
	failed = _check_foot_on_floor_slab(failed)
	failed = _check_decorate_once(failed)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	quit(1 if failed else 0)


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


func _shell_room(brush: CityBrush, volume: RoomVolume) -> void:
	var r := volume.rect
	brush.fill_box(
		Vector3i(r.position.x - 1, volume.floor_y, r.position.y - 1),
		Vector3i(r.end.x + 1, volume.floor_y + 1, r.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(r.position.x - 1, volume.floor_y + 1, r.position.y - 1),
		Vector3i(r.end.x + 1, volume.floor_y + volume.air_h + 1, r.end.y + 1),
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


func _check_emit_and_purpose(failed: bool) -> bool:
	## Offline full bake must produce InteriorRooms with zone-mapped purposes.
	var payload: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(0, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FULL,
		"bake_nav": false,
	})
	if not bool(payload.get("ok", false)):
		push_error("FAIL bake: %s" % payload.get("error", "?"))
		return true
	var rooms: Array = payload.get("interior_rooms", [])
	if rooms.is_empty():
		push_error("FAIL full bake emitted zero interior_rooms")
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
	var far_rooms: Array = far.get("interior_rooms", [])
	if not far_rooms.is_empty():
		push_error("FAIL far bake should not emit interior_rooms (got %d)" % far_rooms.size())
		failed = true
	var purpose_max := int(RoomDecoratorScript.Purpose.GENERIC)
	for room_v in rooms:
		var room: InteriorRoom = room_v as InteriorRoom
		if room == null:
			push_error("FAIL interior_rooms entry is not InteriorRoom")
			return true
		if room.decorated:
			push_error("FAIL room decorated before enter")
			failed = true
		if room.purpose < 0 or room.purpose > purpose_max:
			push_error("FAIL purpose out of range: %d" % room.purpose)
			failed = true
		if room.rect.size.x < 3 or room.rect.size.y < 3:
			push_error("FAIL room rect too small: %s" % room.rect)
			failed = true
	print("  bake rooms=%d sample_purpose=%d" % [rooms.size(), (rooms[0] as InteriorRoom).purpose])
	return failed


func _check_decorate_once(failed: bool) -> bool:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(4, 4, 12, 12), 10, 5)
	_shell_room(brush, volume)

	var room: InteriorRoom = InteriorRoomScript.make(
		volume.rect,
		volume.floor_y,
		volume.air_h,
		RoomDecoratorScript.Purpose.LIVING_ROOM
	)
	var inst := FakeDistrict.new()
	inst.interior_rooms = [room]

	var dec: InteriorDecorator = InteriorDecoratorScript.new() as InteriorDecorator
	dec.brush = brush
	dec.voxel_size = 0.5

	## Feet above the slab, inside the footprint.
	var foot := Vector3(
		(volume.rect.position.x + 2) * 0.5 + 0.25,
		(volume.floor_y + 1) * 0.5 + 0.1,
		(volume.rect.position.y + 2) * 0.5 + 0.25
	)
	if not dec.tick(foot, [inst]):
		push_error("FAIL first enter did not decorate")
		return true
	if not room.decorated:
		push_error("FAIL room.decorated still false after enter")
		failed = true
	var props := _count_props(brush, volume)
	if props <= 0:
		push_error("FAIL living room decorated with zero props")
		failed = true
	if dec.tick(foot, [inst]):
		push_error("FAIL second enter decorated again")
		failed = true
	var props2 := _count_props(brush, volume)
	if props2 != props:
		push_error("FAIL prop count changed on second enter (%d -> %d)" % [props, props2])
		failed = true
	print("  decorate-once props=%d" % props)
	return failed
