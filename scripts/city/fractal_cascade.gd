## One moving tip: peel a same-material column, hop to one random cardinal neighbour, repeat.
## A shot starts it; it never branches or backtracks.
extends RefCounted

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var _brush: CityBrush = null
var _mat: int = -1
var _x: int = 0
var _y: int = 0  ## current column bottom
var _z: int = 0
var _alive: bool = false
var _rng := RandomNumberGenerator.new()


func is_active() -> bool:
	return _alive


func seed_material() -> int:
	return _mat


func start(brush: CityBrush, hit_vox: Vector3i) -> Array:
	if brush == null or _alive:
		return []
	var mat := brush.get_vox(hit_vox)
	if not VoxelMaterial.is_fractal_display(mat):
		return []
	var bottom := _stack_bottom(brush, hit_vox.x, hit_vox.z, hit_vox.y, mat)
	if bottom < 0:
		return []
	_brush = brush
	_mat = mat
	_x = hit_vox.x
	_y = bottom
	_z = hit_vox.z
	_alive = true
	_rng.randomize()
	return _peel()


func tick() -> Array:
	if not _alive or _brush == null:
		return []
	var opts: Array[Vector3i] = []
	for d: Vector2i in _DIRS:
		var nx := _x + d.x
		var nz := _z + d.y
		## Neighbour must share this tip height with the same material, then we drop to its bottom.
		if _brush.get_vox(Vector3i(nx, _y, nz)) != _mat:
			continue
		var by := _stack_bottom(_brush, nx, nz, _y, _mat)
		if by >= 0:
			opts.append(Vector3i(nx, by, nz))
	if opts.is_empty():
		_alive = false
		_brush = null
		return []
	var next: Vector3i = opts[_rng.randi_range(0, opts.size() - 1)]
	_x = next.x
	_y = next.y
	_z = next.z
	return _peel()


func _peel() -> Array:
	var detached: Array = []
	var y := _y
	_brush.begin_edit()
	while _brush.get_vox(Vector3i(_x, y, _z)) == _mat:
		for entry in _brush.destroy_vox(Vector3i(_x, y, _z)):
			detached.append(entry)
		y += 1
	_brush.end_edit()
	return detached


func _stack_bottom(brush: CityBrush, x: int, z: int, hint_y: int, mat: int) -> int:
	if brush.get_vox(Vector3i(x, hint_y, z)) != mat:
		return -1
	var y := hint_y
	while y > 0 and brush.get_vox(Vector3i(x, y - 1, z)) == mat:
		y -= 1
	return y
