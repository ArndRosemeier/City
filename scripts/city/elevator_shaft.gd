## One vertical elevator volume in a city lot (world voxel coordinates).
##
## Phase 3: no cabin mesh — proximity + E rides between `floor_ys` landings.
## `rect` is the cabin footprint (XZ); keep furniture clear of it via InteriorRoom.keep_clear.
class_name ElevatorShaft
extends RefCounted

## Cabin footprint: Rect2i.x/size.x = voxel X, .y/size.y = voxel Z.
var rect: Rect2i = Rect2i()
## Walkable floor slab tops for each storey (ascending). At least 2 for a ride.
var floor_ys: PackedInt32Array = PackedInt32Array()


func landing_count() -> int:
	return floor_ys.size()


func contains_xz(world_xz: Vector2i) -> bool:
	return rect.has_point(world_xz)


## True when the foot is inside the cabin footprint near any landing (±1 voxel Y).
func contains_foot_voxel(world_vox: Vector3i) -> bool:
	if not contains_xz(Vector2i(world_vox.x, world_vox.z)):
		return false
	for y in floor_ys:
		if absi(world_vox.y - int(y)) <= 1:
			return true
	return false


## Index of the landing closest to `world_y_vox`, or -1 if none.
func nearest_landing_index(world_y_vox: int) -> int:
	if floor_ys.is_empty():
		return -1
	var best_i := 0
	var best_d := absi(world_y_vox - int(floor_ys[0]))
	for i in range(1, floor_ys.size()):
		var d := absi(world_y_vox - int(floor_ys[i]))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


## Next landing index cycling upward (wrap to 0).
func next_landing_index(from_index: int) -> int:
	if floor_ys.size() < 2:
		return from_index
	return (from_index + 1) % floor_ys.size()


## World-metre feet anchor at cabin centre on landing `index`.
## `floor_ys` matches InteriorRoom.floor_y (top solid); walker origin sits in that cell.
func world_anchor(index: int, voxel_size: float) -> Vector3:
	if index < 0 or index >= floor_ys.size():
		return Vector3.ZERO
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cz := float(rect.position.y) + float(rect.size.y) * 0.5
	var y := float(floor_ys[index]) + 0.05
	return Vector3(cx * voxel_size, y * voxel_size, cz * voxel_size)


static func make(p_rect: Rect2i, p_floor_ys: PackedInt32Array) -> ElevatorShaft:
	var s := ElevatorShaft.new()
	s.rect = p_rect
	s.floor_ys = p_floor_ys.duplicate()
	return s
