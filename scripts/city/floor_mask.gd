## Which columns of a storey plate a floor plan may use.
##
## One byte per XZ cell of `rect`: 1 when there is floor to stand on and clear air above
## it, 0 for courtyard voids, punched sky holes, stairs, shaft walls and anything else
## the shell already occupies. Built once from the voxels, then read by FloorPlanner
## (which never touches a brush) and FloorPlanPainter.
class_name FloorMask
extends RefCounted

var rect: Rect2i = Rect2i()
var _free: PackedByteArray = PackedByteArray()
var _free_n: int = 0


static func make(p_rect: Rect2i) -> FloorMask:
	var m := FloorMask.new()
	m.rect = p_rect
	m._free.resize(p_rect.size.x * p_rect.size.y)
	m._free.fill(0)
	m._free_n = 0
	return m


## Probe the clear band of `volume`: floor solid at `floor_y`, air all the way up.
static func from_brush(brush: CityBrush, rect: Rect2i, floor_y: int, air_h: int) -> FloorMask:
	var m := FloorMask.make(rect)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if brush.get_vox(Vector3i(x, floor_y, z)) == VoxelMaterial.AIR:
				continue
			var clear := true
			for y in range(floor_y + 1, floor_y + air_h + 1):
				if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
					clear = false
					break
			if clear:
				m.set_free(Vector2i(x, z), true)
	return m


func set_free(p: Vector2i, value: bool) -> void:
	var i := _index(p)
	if i < 0:
		return
	var was := _free[i] == 1
	if was == value:
		return
	_free[i] = 1 if value else 0
	_free_n += 1 if value else -1


func is_free(p: Vector2i) -> bool:
	var i := _index(p)
	return i >= 0 and _free[i] == 1


func free_count() -> int:
	return _free_n


func free_count_in(r: Rect2i) -> int:
	var n := 0
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if is_free(Vector2i(x, z)):
				n += 1
	return n


func _index(p: Vector2i) -> int:
	if not rect.has_point(p):
		return -1
	return (p.y - rect.position.y) * rect.size.x + (p.x - rect.position.x)
