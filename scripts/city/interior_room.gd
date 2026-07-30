## One JIT-decoratable city interior, in *world* voxel coordinates.
##
## Emitted at district bake (one per walkable storey). Runtime subdivides the storey on
## first entry (`sub_rooms`), then sets `decorated` per room so the enter loop never
## stamps twice while the district is loaded.
class_name InteriorRoom
extends RefCounted

## Clear floor footprint (walls outside this rect).
var rect: Rect2i = Rect2i()
## Topmost solid floor voxel Y.
var floor_y: int = 0
## Clear voxels above `floor_y`.
var air_h: int = 0
## `RoomDecorator.Purpose` value.
var purpose: int = 0
## True after decorate finished (even if zero props).
var decorated: bool = false
## XZ cells the decorator must not furnish (elevator cabin, etc.).
var keep_clear: Array[Rect2i] = []
## Storey index within its building — 0 is the ground floor.
var storey: int = 0
## `FloorPlanner.Use` of the building this storey belongs to.
var use: int = 0
## True once the floor plan has been painted (even when it produced no partitions).
var subdivided: bool = false
## Rooms the floor plan cut this storey into. Empty while `subdivided` is false, and
## also afterwards for storeys too small to partition — those furnish as one room.
var sub_rooms: Array[InteriorRoom] = []


func contains_xz(world_xz: Vector2i) -> bool:
	return rect.has_point(world_xz)


## Standing in the room: on/in the floor slab through the clear band, inside the footprint.
## Inclusive of `floor_y` — the walker origin often sits in the top solid floor cell
## (world y just under the air band), not one voxel above it.
func contains_foot_voxel(world_vox: Vector3i) -> bool:
	if not contains_xz(Vector2i(world_vox.x, world_vox.z)):
		return false
	return world_vox.y >= floor_y and world_vox.y <= floor_y + air_h


## The sub-room the foot stands in once this storey is subdivided, or null.
func sub_room_at(world_vox: Vector3i) -> InteriorRoom:
	for sub in sub_rooms:
		if sub.contains_foot_voxel(world_vox):
			return sub
	return null


## First sub-room still waiting for furniture, or null when the floor is finished.
func next_undecorated() -> InteriorRoom:
	for sub in sub_rooms:
		if not sub.decorated:
			return sub
	return null


func to_volume() -> RoomVolume:
	var vol := RoomVolume.make(rect, floor_y, air_h)
	vol.level = storey
	vol.keep_clear = keep_clear.duplicate()
	return vol


static func make(
	p_rect: Rect2i, p_floor_y: int, p_air_h: int, p_purpose: int
) -> InteriorRoom:
	var r := InteriorRoom.new()
	r.rect = p_rect
	r.floor_y = p_floor_y
	r.air_h = p_air_h
	r.purpose = p_purpose
	r.decorated = false
	r.keep_clear = []
	r.sub_rooms = []
	return r
