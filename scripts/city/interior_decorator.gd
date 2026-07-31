## Subdivides and furnishes city interiors as the walker enters them, or when a door into
## an undecorated storey is opened (`prime_at`).
##
## Call `tick` from the main thread with the live CityBrush. One action per call: paint a
## slice of partitions, or furnish one room. Districts own the BuildingInterior records
## and the `subdivided` / `decorated` flags.
class_name InteriorDecorator
extends RefCounted

const FloorPlanPainterScript := preload("res://scripts/city/floor_plan_painter.gd")

var brush: CityBrush
var voxel_size: float = 0.5
## Last room key we logged an enter for (edge-trigger; avoids per-frame spam).
var _last_enter_key: String = ""
## Throttled "still looking" probe while outside every room.
var _last_miss_msec: int = 0
## Partition paint in flight, spread over frames.
var _painter: FloorPlanPainter = null
var _painting: InteriorRoom = null
var _painting_plan: FloorPlan = null
## District of the storey being subdivided or furnished.
var _hit_coord: Vector2i = Vector2i.ZERO
## Door-open probe: while set, `tick` uses this voxel instead of the walker's feet so
## partitions (and the room beyond the door) can finish while the player is still outside.
var _prime_vox: Vector3i = Vector3i.ZERO
var _has_prime: bool = false


## Ask the next ticks to work the storey under `world` — used when a street door opens
## into an undecorated interior. Cleared once that storey is subdivided and the room under
## the probe is furnished (or the probe hits no building at all).
func prime_at(world: Vector3) -> void:
	_prime_vox = _world_to_vox(world)
	_has_prime = true
	_note("interior: PRIME at %s (world=%.1f,%.1f,%.1f)" % [_prime_vox, world.x, world.y, world.z])


## Advance the interior of whatever storey the foot (or a door prime) is on. Returns true
## when work was done. `districts` entries must expose `is_ready`, `bake_quality`, `coord`,
## `origin_vox`, `interior_cell_size` and `interior_buildings` (DistrictInstance does).
## Typed loosely so headless -s tests need no CityProfiler.
func tick(foot_world: Vector3, districts: Array) -> bool:
	if brush == null:
		_note("interior: brush null — tick skipped")
		return false
	if _painter != null:
		_advance_paint()
		return true
	var foot := _prime_vox if _has_prime else _world_to_vox(foot_world)
	var ready_n := 0
	var building_n := 0
	var hit_room: InteriorRoom = null
	for entry in districts:
		if entry == null or not bool(entry.is_ready):
			continue
		if str(entry.bake_quality) != "full":
			continue
		ready_n += 1
		var buildings: Dictionary = entry.interior_buildings as Dictionary
		building_n += buildings.size()
		var building := _building_at(entry, buildings, foot)
		if building == null:
			continue
		var room := building.storey_at(foot)
		if room == null:
			continue
		hit_room = room
		_hit_coord = entry.coord as Vector2i
		break

	if hit_room == null:
		if _has_prime:
			_note("interior: prime cleared, no room at %s" % foot)
			_has_prime = false
		if _last_enter_key != "":
			_note(
				"interior: left room (foot=%s ready=%d buildings=%d)"
				% [foot, ready_n, building_n]
			)
			_last_enter_key = ""
		var now := Time.get_ticks_msec()
		if now - _last_miss_msec >= 4000:
			_last_miss_msec = now
			_note(
				"interior: no room at foot=%s world=%.1f,%.1f,%.1f ready=%d buildings=%d"
				% [foot, foot_world.x, foot_world.y, foot_world.z, ready_n, building_n]
			)
		return false

	_log_enter(hit_room, foot)
	if not hit_room.subdivided:
		_begin_subdivision(hit_room)
		return true
	if _has_prime:
		return _furnish_prime(hit_room, foot)
	return _furnish_next(hit_room, foot)


## The building whose lot the foot stands on, via the district's cell index.
func _building_at(entry: Variant, buildings: Dictionary, foot: Vector3i) -> BuildingInterior:
	if buildings.is_empty():
		return null
	var cell_size := int(entry.interior_cell_size)
	if cell_size <= 0:
		return null
	var origin: Vector3i = entry.origin_vox as Vector3i
	var cell := Vector2i(
		int(floor(float(foot.x - origin.x) / float(cell_size))),
		int(floor(float(foot.z - origin.z) / float(cell_size)))
	)
	return buildings.get(cell) as BuildingInterior


# ------------------------------------------------------------------ subdivision


## Plan the storey, then paint its partitions over the following ticks.
func _begin_subdivision(room: InteriorRoom) -> void:
	var mask := FloorMask.from_brush(brush, room.rect, room.floor_y, room.air_h)
	var planner := FloorPlanner.new()
	planner.rng = _rng_for(room)
	var plan := planner.plan(
		room.use as FloorPlanner.Use,
		room.storey,
		room.rect,
		room.air_h,
		mask,
		room.keep_clear,
		_entries_for(room, mask)
	)
	_note(
		"interior: PLAN use=%s storey=%d rect=%s %s"
		% [
			FloorPlanner.use_name(room.use as FloorPlanner.Use),
			room.storey,
			room.rect,
			plan.describe(),
		]
	)
	if plan.walls.is_empty():
		room.sub_rooms = _sub_rooms_from(plan, room)
		room.subdivided = true
		return
	_painting_plan = plan
	_painting = room
	_painter = FloorPlanPainterScript.new() as FloorPlanPainter
	_painter.brush = brush
	_painter.begin(plan, mask, room.floor_y)
	_advance_paint()


func _advance_paint() -> void:
	var written := _painter.paint_step()
	if not _painter.is_done():
		return
	_painting.sub_rooms = _sub_rooms_from(_painting_plan, _painting)
	_painting.subdivided = true
	_note(
		"interior: PARTITIONED rect=%s rooms=%d last_write=%d"
		% [_painting.rect, _painting.sub_rooms.size(), written]
	)
	_painter = null
	_painting = null
	_painting_plan = null


## Plan rooms and corridors become the storey's furnishable sub-rooms.
func _sub_rooms_from(plan: FloorPlan, storey: InteriorRoom) -> Array[InteriorRoom]:
	var out: Array[InteriorRoom] = []
	for r in plan.rooms:
		out.append(_sub_room(storey, r.rect, r.purpose))
	for c in plan.corridors:
		out.append(_sub_room(storey, c, RoomDecorator.Purpose.CORRIDOR))
	return out


func _sub_room(storey: InteriorRoom, rect: Rect2i, purpose: int) -> InteriorRoom:
	var sub := InteriorRoom.make(rect, storey.floor_y, storey.air_h, purpose)
	sub.storey = storey.storey
	sub.use = storey.use
	for c in storey.keep_clear:
		if c.intersects(rect):
			sub.keep_clear.append(c)
	return sub


## Cells the layout has to stay reachable from: the elevator bay beside each reserved
## enclosure, and the façade doorways punched into the shell.
func _entries_for(room: InteriorRoom, mask: FloorMask) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in room.keep_clear:
		var mid := c.position + c.size / 2
		for p in [
			Vector2i(c.position.x - 1, mid.y),
			Vector2i(c.end.x, mid.y),
			Vector2i(mid.x, c.position.y - 1),
			Vector2i(mid.x, c.end.y),
		]:
			if mask.is_free(p):
				out.append(p)
	out.append_array(_doorway_entries(room))
	return out


## Walk the wall ring outside the plate: an air or door cell there is a way in, so the
## cell behind it must keep a path to the circulation.
func _doorway_entries(room: InteriorRoom) -> Array[Vector2i]:
	var r := room.rect
	var y := room.floor_y + 1
	var out: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		if _is_opening(Vector3i(x, y, r.position.y - 1)):
			out.append(Vector2i(x, r.position.y))
		if _is_opening(Vector3i(x, y, r.end.y)):
			out.append(Vector2i(x, r.end.y - 1))
	for z in range(r.position.y, r.end.y):
		if _is_opening(Vector3i(r.position.x - 1, y, z)):
			out.append(Vector2i(r.position.x, z))
		if _is_opening(Vector3i(r.end.x, y, z)):
			out.append(Vector2i(r.end.x - 1, z))
	return out


func _is_opening(wall_vox: Vector3i) -> bool:
	var id := brush.get_vox(wall_vox)
	return id == VoxelMaterial.AIR or VoxelMaterial.is_door(id)


# ------------------------------------------------------------------- furnishing


## Door-open path: furnish only the room the probe stands in, then drop the prime so the
## rest of the floor waits for a real enter. Opening a door should dress what you see, not
## the whole plate behind the player's back.
func _furnish_prime(storey: InteriorRoom, foot: Vector3i) -> bool:
	var target: InteriorRoom = storey
	if not storey.sub_rooms.is_empty():
		target = storey.sub_room_at(foot)
	if target == null or target.decorated:
		_has_prime = false
		_note("interior: prime cleared, room under %s already done" % foot)
		return false
	var placed := _decorate(target)
	_has_prime = false
	_note(
		"interior: DECORATED (door) purpose=%s placed=%d rect=%s storey=%d"
		% [
			RoomDecorator.purpose_name(target.purpose as RoomDecorator.Purpose),
			placed,
			target.rect,
			target.storey,
		]
	)
	return true


## Furnish the room under the foot first, then fill the rest of the floor in behind it.
func _furnish_next(storey: InteriorRoom, foot: Vector3i) -> bool:
	var target: InteriorRoom = null
	if storey.sub_rooms.is_empty():
		target = storey if not storey.decorated else null
	else:
		target = storey.sub_room_at(foot)
		if target != null and target.decorated:
			target = null
		if target == null:
			target = storey.next_undecorated()
	if target == null:
		return false
	var placed := _decorate(target)
	_note(
		"interior: DECORATED purpose=%s placed=%d rect=%s storey=%d"
		% [
			RoomDecorator.purpose_name(target.purpose as RoomDecorator.Purpose),
			placed,
			target.rect,
			target.storey,
		]
	)
	return true


func _decorate(room: InteriorRoom) -> int:
	var dec := RoomDecorator.new()
	dec.brush = brush
	dec.rng = _rng_for(room)
	var placed := dec.decorate(room.to_volume(), room.purpose as RoomDecorator.Purpose)
	room.decorated = true
	return placed


## Stable per room so a re-streamed district (fresh flags) stamps the same kit again.
func _rng_for(room: InteriorRoom) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		hash(Vector3i(room.rect.position.x, room.floor_y, room.rect.position.y))
		^ int(_hit_coord.x)
		^ (int(_hit_coord.y) << 16)
	)
	return rng


func _log_enter(room: InteriorRoom, foot: Vector3i) -> void:
	var key := "%s|%s|%d|%s|%s" % [
		_hit_coord, room.rect, room.floor_y, room.subdivided, room.decorated
	]
	if key == _last_enter_key:
		return
	_last_enter_key = key
	_note(
		"interior: ENTER d=%s rect=%s floor_y=%d air_h=%d storey=%d use=%s subdivided=%s foot=%s"
		% [
			_hit_coord,
			room.rect,
			room.floor_y,
			room.air_h,
			room.storey,
			FloorPlanner.use_name(room.use as FloorPlanner.Use),
			room.subdivided,
			foot,
		]
	)


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
