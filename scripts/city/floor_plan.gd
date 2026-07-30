## The subdivision of one storey: partitions to paint and the rooms they leave behind.
##
## Empty (`rooms.is_empty()`) means "do not subdivide" — the storey furnishes as one
## room, exactly as it did before floor planning existed.
class_name FloorPlan
extends RefCounted

var walls: Array[FloorPlanWall] = []
var rooms: Array[FloorPlanRoom] = []
## Circulation the rooms open onto. Also rooms in their own right (furnished as CORRIDOR).
var corridors: Array[Rect2i] = []
## Cells forced back to air after the partitions land, so entries (elevator bay, street
## door) always reach the circulation. Only ever clears voxels this plan painted.
var carves: Array[Rect2i] = []
## Clear voxels above the floor — the height every partition is painted to.
var air_h: int = 0


func add_wall(rect: Rect2i, mat: int, gaps: Array[Rect2i]) -> void:
	walls.append(FloorPlanWall.make(rect, mat, gaps))


func add_room(rect: Rect2i, purpose: int) -> void:
	rooms.append(FloorPlanRoom.make(rect, purpose))


## L-shaped clearance from `from` to `to`, three cells wide so a body fits.
func add_link(from: Vector2i, to: Vector2i) -> void:
	const W := 3
	var x0 := mini(from.x, to.x)
	var x1 := maxi(from.x, to.x)
	var z0 := mini(from.y, to.y)
	var z1 := maxi(from.y, to.y)
	carves.append(Rect2i(x0, from.y - W / 2, x1 - x0 + 1, W))
	carves.append(Rect2i(to.x - W / 2, z0, W, z1 - z0 + 1))


func wall_voxel_count() -> int:
	var n := 0
	for w in walls:
		n += w.rect.size.x * w.rect.size.y
	return n


func describe() -> String:
	return "plan rooms=%d walls=%d corridors=%d carves=%d" % [
		rooms.size(), walls.size(), corridors.size(), carves.size()
	]


## Loud structural check: overlapping or doorless rooms are generator bugs, not something
## the painter should paper over at runtime. Returns false and reports the first fault.
func verify(bounds: Rect2i) -> bool:
	if walls.is_empty():
		## Nothing was partitioned, so nothing can be shut in.
		return true
	for r in rooms:
		if not bounds.encloses(r.rect):
			push_error("FloorPlan: room %s escapes plate %s" % [r.rect, bounds])
			return false
		if r.rect.size.x < 3 or r.rect.size.y < 3:
			push_error("FloorPlan: room %s is too small to furnish" % r.rect)
			return false
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if rooms[i].rect.intersects(rooms[j].rect):
				push_error(
					"FloorPlan: rooms %s and %s overlap" % [rooms[i].rect, rooms[j].rect]
				)
				return false
	for c in corridors:
		if not bounds.encloses(c):
			push_error("FloorPlan: corridor %s escapes plate %s" % [c, bounds])
			return false
		for r in rooms:
			if c.intersects(r.rect):
				push_error("FloorPlan: corridor %s overlaps room %s" % [c, r.rect])
				return false
	for r in rooms:
		if not _has_opening(r.rect):
			push_error("FloorPlan: room %s has no door" % r.rect)
			return false
	return true


## A room is served when a gap or a carve touches it.
func _has_opening(room: Rect2i) -> bool:
	var reach := room.grow(1)
	for w in walls:
		for g in w.gaps:
			if reach.intersects(g):
				return true
	for c in carves:
		if reach.intersects(c):
			return true
	return false
