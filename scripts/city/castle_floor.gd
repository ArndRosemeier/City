## One storey of the castle keep, in district-local voxel coordinates.
##
## GDScript has no nested typed arrays, so the per-storey room list lives here rather than
## as an `Array[Array]` on CastleLayout.
class_name CastleFloor
extends RefCounted

var storey: int = 0
## Walking surface of the storey: Y of the topmost solid slab voxel.
var floor_y: int = 0
## Clear voxels above `floor_y`. Double for the lower storey of the great hall.
var air_h: int = 0
## The storey above the great hall has no slab of its own.
var has_slab: bool = true
var rooms: Array[Rect2i] = []
## Index into `rooms` of the great hall, or -1 on storeys that have none.
var hall_index: int = -1


func hall_rect() -> Rect2i:
	assert(hall_index >= 0)
	return rooms[hall_index]


func matches(other: CastleFloor) -> bool:
	if other == null:
		return false
	return (
		storey == other.storey
		and floor_y == other.floor_y
		and air_h == other.air_h
		and has_slab == other.has_slab
		and hall_index == other.hall_index
		and rooms == other.rooms
	)


func describe() -> String:
	return "s%d y=%d air=%d rooms=%d hall=%d" % [
		storey, floor_y, air_h, rooms.size(), hall_index
	]
