## Enters undecorated city InteriorRooms and stamps furniture via RoomDecorator.
##
## Call `tick` from the main thread with the live CityBrush. At most one room per
## call (budget). Districts own the room records and the `decorated` flags.
class_name InteriorDecorator
extends RefCounted

var brush: CityBrush
var voxel_size: float = 0.5
## Last room key we logged an enter for (edge-trigger; avoids per-frame spam).
var _last_enter_key: String = ""
## Throttled "still looking" probe while outside every room.
var _last_miss_msec: int = 0


## If the foot is inside an undecorated room, decorate it and return true.
## `districts` entries must expose `is_ready`, `bake_quality`, `coord`, `interior_rooms`
## (DistrictInstance does). Typed loosely so headless -s tests need no CityProfiler.
func tick(foot_world: Vector3, districts: Array) -> bool:
	if brush == null:
		_note("interior: brush null — tick skipped")
		return false
	var foot := _world_to_vox(foot_world)
	var ready_n := 0
	var room_n := 0
	var hit_room: InteriorRoom = null
	var hit_coord := Vector2i.ZERO
	for entry in districts:
		if entry == null or not bool(entry.is_ready):
			continue
		if str(entry.bake_quality) != "full":
			continue
		ready_n += 1
		var rooms: Array = entry.interior_rooms as Array
		room_n += rooms.size()
		for room_v in rooms:
			var room: InteriorRoom = room_v as InteriorRoom
			if room == null:
				continue
			if not room.contains_foot_voxel(foot):
				continue
			hit_room = room
			hit_coord = entry.coord as Vector2i
			break
		if hit_room != null:
			break

	if hit_room == null:
		if _last_enter_key != "":
			_note("interior: left room (foot=%s ready=%d rooms=%d)" % [foot, ready_n, room_n])
			_last_enter_key = ""
		var now := Time.get_ticks_msec()
		if now - _last_miss_msec >= 4000:
			_last_miss_msec = now
			_note(
				"interior: no room at foot=%s world=%.1f,%.1f,%.1f ready=%d rooms=%d"
				% [foot, foot_world.x, foot_world.y, foot_world.z, ready_n, room_n]
			)
		return false

	var key := "%s|%s|%d|%s" % [
		hit_coord, hit_room.rect, hit_room.floor_y, hit_room.decorated
	]
	if key != _last_enter_key:
		_last_enter_key = key
		_note(
			"interior: ENTER d=%s rect=%s floor_y=%d air_h=%d purpose=%s decorated=%s foot=%s"
			% [
				hit_coord,
				hit_room.rect,
				hit_room.floor_y,
				hit_room.air_h,
				RoomDecorator.purpose_name(hit_room.purpose as RoomDecorator.Purpose),
				hit_room.decorated,
				foot,
			]
		)

	if hit_room.decorated:
		return false

	var placed := _decorate(hit_room, hit_coord)
	var sample := Vector3i(
		hit_room.rect.position.x + mini(hit_room.rect.size.x - 1, 1),
		hit_room.floor_y + 1,
		hit_room.rect.position.y + mini(hit_room.rect.size.y - 1, 1)
	)
	var sample_id := brush.get_vox(sample) if brush != null else -1
	_note(
		"interior: DECORATED purpose=%s placed=%d rect=%s sample@%s id=%d"
		% [
			RoomDecorator.purpose_name(hit_room.purpose as RoomDecorator.Purpose),
			placed,
			hit_room.rect,
			sample,
			sample_id,
		]
	)
	## Re-key so a later re-enter of the now-decorated room logs again as ENTER.
	_last_enter_key = "%s|%s|%d|%s" % [
		hit_coord, hit_room.rect, hit_room.floor_y, hit_room.decorated
	]
	return true


func _decorate(room: InteriorRoom, district_coord: Vector2i) -> int:
	var dec := RoomDecorator.new()
	dec.brush = brush
	var rng := RandomNumberGenerator.new()
	## Stable per room so re-stream (fresh decorated=false) tends to restamp the same kit
	## when voxel seeding leaves overlaps alone.
	rng.seed = (
		hash(Vector3i(room.rect.position.x, room.floor_y, room.rect.position.y))
		^ int(district_coord.x)
		^ (int(district_coord.y) << 16)
	)
	dec.rng = rng
	var volume := room.to_volume()
	var placed := dec.decorate(volume, room.purpose as RoomDecorator.Purpose)
	room.decorated = true
	return placed


func _world_to_vox(world: Vector3) -> Vector3i:
	var vs := voxel_size
	return Vector3i(
		int(floor(world.x / vs)),
		int(floor(world.y / vs)),
		int(floor(world.z / vs))
	)


func _note(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var log_node := tree.root.get_node_or_null("DamageLog")
	if log_node != null and log_node.has_method("note"):
		log_node.call("note", text)
