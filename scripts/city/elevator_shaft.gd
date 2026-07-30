## One vertical elevator volume in a city lot (world voxel coordinates).
##
## The cabin is carved per storey: a metal pad at every `floor_ys` inside a three-sided
## enclosure whose fourth side is the bay doorway. Riding between landings is scripted
## (see CityWalker.begin_elevator_ride); ElevatorPanel picks the destination floor.
## `rect` is the cabin footprint (XZ); keep furniture clear of it via InteriorRoom.keep_clear.
class_name ElevatorShaft
extends RefCounted

## Cabin footprint: Rect2i.x/size.x = voxel X, .y/size.y = voxel Z.
var rect: Rect2i = Rect2i()
## Walkable floor slab tops for each storey (ascending). At least 2 for a ride.
var floor_ys: PackedInt32Array = PackedInt32Array()
## Unit XZ step from the cabin toward its open bay side; the other three sides are walled.
var bay_dir: Vector2i = Vector2i.ZERO


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


## Landing the foot is standing at, counting the cabin plus a 1-cell apron so the bay
## doorway also counts. -1 when the foot is elsewhere. Landings are storeys apart, so
## the ±1 Y tolerance can only ever match one of them.
func foot_landing_index(world_vox: Vector3i) -> int:
	var apron := Rect2i(rect.position - Vector2i.ONE, rect.size + Vector2i.ONE * 2)
	if not apron.has_point(Vector2i(world_vox.x, world_vox.z)):
		return -1
	for i in range(floor_ys.size()):
		if absi(world_vox.y - int(floor_ys[i])) <= 1:
			return i
	return -1


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


## Walkable surface of landing `index` in metres: the pad cell is solid, so a body
## stands on its top face. `world_anchor` instead sinks feet into that cell by design.
func floor_surface_y(index: int, voxel_size: float) -> float:
	if index < 0 or index >= floor_ys.size():
		push_error("ElevatorShaft.floor_surface_y: index %d of %d" % [index, floor_ys.size()])
		return NAN
	return float(int(floor_ys[index]) + 1) * voxel_size


## Yaw for a Ui3D mounted on the wall opposite the bay, so its readable −Z face looks
## back across the cabin at whoever steps through the doorway.
func bay_yaw() -> float:
	if bay_dir.x > 0:
		return -PI * 0.5
	if bay_dir.x < 0:
		return PI * 0.5
	if bay_dir.y > 0:
		return PI
	return 0.0


## Centre of the cabin's back wall (the side opposite the bay) at landing `index`,
## in metres, on the wall's inner face. `inset_m` pushes the point into the cabin.
func back_wall_center(index: int, voxel_size: float, inset_m: float = 0.0) -> Vector3:
	var y := floor_surface_y(index, voxel_size)
	if is_nan(y):
		return Vector3.INF
	var cx := (float(rect.position.x) + float(rect.size.x) * 0.5) * voxel_size
	var cz := (float(rect.position.y) + float(rect.size.y) * 0.5) * voxel_size
	var half_x := float(rect.size.x) * 0.5 * voxel_size
	var half_z := float(rect.size.y) * 0.5 * voxel_size
	return Vector3(
		cx - float(bay_dir.x) * (half_x - inset_m),
		y,
		cz - float(bay_dir.y) * (half_z - inset_m)
	)


static func make(
	p_rect: Rect2i, p_floor_ys: PackedInt32Array, p_bay_dir: Vector2i
) -> ElevatorShaft:
	var s := ElevatorShaft.new()
	s.rect = p_rect
	s.floor_ys = p_floor_ys.duplicate()
	s.bay_dir = p_bay_dir
	return s
