## Turns a FloorPlan into voxels, a budgeted slice at a time.
##
## Only writes into columns the FloorMask marked standable, so shaft enclosures, stairs,
## courtyard voids and punched sky holes survive untouched. Carves only clear voxels this
## painter wrote, so a link path can never breach the building shell or an elevator.
class_name FloorPlanPainter
extends RefCounted

var brush: CityBrush
## Voxels written per `paint_step` call. A downtown plate is 100+ cells on a side, so a
## full storey of partitions is thousands of writes — too many for one frame.
var budget: int = 3000

var _plan: FloorPlan
var _mask: FloorMask
var _floor_y: int = 0
## Index of the next wall to paint.
var _wall_i: int = 0
## Columns this painter filled, so carves know what they may take back out.
var _painted: Dictionary = {}
var _done: bool = false


func begin(p_plan: FloorPlan, p_mask: FloorMask, p_floor_y: int) -> void:
	_plan = p_plan
	_mask = p_mask
	_floor_y = p_floor_y
	_wall_i = 0
	_painted = {}
	_done = p_plan == null or p_plan.walls.is_empty()


func is_done() -> bool:
	return _done


## Paint up to `budget` voxels. Returns how many were written; call again until
## `is_done()`.
func paint_step() -> int:
	if _done:
		return 0
	if brush == null:
		push_error("FloorPlanPainter.paint_step: brush is null")
		_done = true
		return 0
	brush.begin_edit()
	var written := 0
	while _wall_i < _plan.walls.size() and written < budget:
		written += _paint_wall(_plan.walls[_wall_i])
		_wall_i += 1
	if _wall_i >= _plan.walls.size():
		_carve_links()
		_done = true
	brush.end_edit()
	return written


func _paint_wall(wall: FloorPlanWall) -> int:
	var y0 := _floor_y + 1
	var y1 := _floor_y + _plan.air_h + 1
	var written := 0
	for z in range(wall.rect.position.y, wall.rect.end.y):
		for x in range(wall.rect.position.x, wall.rect.end.x):
			var p := Vector2i(x, z)
			if wall.is_gap(p):
				continue
			if not _mask.is_free(p):
				continue
			brush.fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), wall.mat)
			_painted[p] = true
			written += _plan.air_h
	return written


## Reopen the entry paths. Columns we did not paint are shell, shaft or furniture — they
## stay, so a carve can never punch a hole in the building.
func _carve_links() -> void:
	var y0 := _floor_y + 1
	var y1 := _floor_y + _plan.air_h + 1
	for c in _plan.carves:
		for z in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				var p := Vector2i(x, z)
				if not _painted.has(p):
					continue
				brush.fill_box(
					Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), VoxelMaterial.AIR
				)
				_painted.erase(p)
