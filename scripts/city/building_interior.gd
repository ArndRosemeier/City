## Every walkable storey of one city lot, in *world* voxel coordinates.
##
## Districts index these by cell so the JIT decorator resolves "which floor is the
## walker on" in O(1) instead of scanning every room of every loaded tile each frame.
class_name BuildingInterior
extends RefCounted

## Buildable footprint of the lot (world XZ), outer walls included.
var lot_rect: Rect2i = Rect2i()
## `FloorPlanner.Use` value — decides how each storey gets subdivided.
var use: int = 0
## One entry per walkable storey, ascending by `floor_y`.
var storeys: Array[InteriorRoom] = []


## The storey whose clear band the foot voxel sits in, or null.
func storey_at(world_vox: Vector3i) -> InteriorRoom:
	for room in storeys:
		if room.contains_foot_voxel(world_vox):
			return room
	return null


## Reserve `rect` on every storey standing at one of `floor_ys` (elevator cabins).
func reserve_on_floors(rect: Rect2i, floor_ys: PackedInt32Array) -> void:
	for room in storeys:
		for y in floor_ys:
			if room.floor_y == int(y):
				room.keep_clear.append(rect)
				break


func describe() -> String:
	return "building %s use=%d storeys=%d" % [lot_rect, use, storeys.size()]


static func make(p_lot_rect: Rect2i, p_use: int) -> BuildingInterior:
	var b := BuildingInterior.new()
	b.lot_rect = p_lot_rect
	b.use = p_use
	b.storeys = []
	return b
