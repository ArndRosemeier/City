## One JIT-decoratable city interior, in *world* voxel coordinates.
##
## Emitted at district bake (ground-floor shells). Runtime sets `decorated` after
## RoomDecorator runs so the enter loop never stamps twice while the district is loaded.
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


func contains_xz(world_xz: Vector2i) -> bool:
	return rect.has_point(world_xz)


## Standing in the room: on/in the floor slab through the clear band, inside the footprint.
## Inclusive of `floor_y` — the walker origin often sits in the top solid floor cell
## (world y just under the air band), not one voxel above it.
func contains_foot_voxel(world_vox: Vector3i) -> bool:
	if not contains_xz(Vector2i(world_vox.x, world_vox.z)):
		return false
	return world_vox.y >= floor_y and world_vox.y <= floor_y + air_h


func to_volume() -> RoomVolume:
	return RoomVolume.make(rect, floor_y, air_h)


static func make(
	p_rect: Rect2i, p_floor_y: int, p_air_h: int, p_purpose: int
) -> InteriorRoom:
	var r := InteriorRoom.new()
	r.rect = p_rect
	r.floor_y = p_floor_y
	r.air_h = p_air_h
	r.purpose = p_purpose
	r.decorated = false
	return r
