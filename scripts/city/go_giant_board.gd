## Live voxel giant Go board — mirrors BoardState via CityBrush.
class_name GoGiantBoard
extends Node3D

const GoGiantHandScript := preload("res://scripts/city/go_giant_hand.gd")

var board: GoBoardState = null
var live_brush: Callable = Callable()
var origin_vox: Vector3i = Vector3i.ZERO
var giant_origin_local: Vector3i = Vector3i.ZERO
var cell_vox: int = 4
var voxel_size: float = 0.5
## Slate black against chalk white. The graveyard pair (GRAVE_STONE / GRAVE_MARBLE) both
## sit mid-grey and washed out against the light board field.
var black_mat: int = VoxelMaterial.ASPHALT
var white_mat: int = VoxelMaterial.PLASTER
var _hand: Node3D = null
var _animating: bool = false
var _queue: Array[Dictionary] = []


func setup(
	p_board: GoBoardState,
	p_live_brush: Callable,
	p_origin_vox: Vector3i,
	p_giant_origin_local: Vector3i,
	p_cell_vox: int,
	p_voxel_size: float
) -> void:
	board = p_board
	live_brush = p_live_brush
	origin_vox = p_origin_vox
	giant_origin_local = p_giant_origin_local
	cell_vox = p_cell_vox
	voxel_size = p_voxel_size
	_hand = GoGiantHandScript.new()
	_hand.name = "GoGiantHand"
	add_child(_hand)
	_hand.call("configure", voxel_size)
	if board != null:
		if not board.moved.is_connected(_on_moved):
			board.moved.connect(_on_moved)
		if not board.captured.is_connected(_on_captured):
			board.captured.connect(_on_captured)
		if not board.reset.is_connected(_clear_all):
			board.reset.connect(_clear_all)


## Base voxel radius of a giant stone: leaves one voxel of board between neighbours.
func stone_radius() -> int:
	return maxi(cell_vox / 2 - 1, 1)


func world_pos_for(x: int, y: int) -> Vector3:
	## Stone sits on a grid crossing (line intersection), not in a cell centre.
	var wx := origin_vox.x + giant_origin_local.x + x * cell_vox
	var wz := origin_vox.z + giant_origin_local.z + y * cell_vox
	## Board surface is giant_origin.y; stones stack on the two layers above it.
	var wy := origin_vox.y + giant_origin_local.y + 3
	return Vector3(
		(float(wx) + 0.5) * voxel_size,
		float(wy) * voxel_size,
		(float(wz) + 0.5) * voxel_size
	)


## Write every stone of `board` at once, skipping the hand animation. Used when a board
## has to appear already played (district reload, look inspection).
func paint_snapshot(snapshot: GoBoardState) -> void:
	if snapshot == null:
		push_error("GoGiantBoard.paint_snapshot: null board")
		return
	for y in range(snapshot.size):
		for x in range(snapshot.size):
			var c := snapshot.at(x, y)
			var mat := VoxelMaterial.AIR
			if c == GoBoardState.BLACK:
				mat = black_mat
			elif c == GoBoardState.WHITE:
				mat = white_mat
			_set_stone_vox(x, y, mat)


func _on_moved(color: int, _vertex: String, loc: Vector2i) -> void:
	_queue.append({"op": "place", "color": color, "x": loc.x, "y": loc.y})
	_kick()


func _on_captured(_color: int, locs: Array) -> void:
	_queue.append({"op": "capture", "locs": locs})
	_kick()


func _clear_all() -> void:
	_queue.clear()
	if board == null:
		return
	for y in range(board.size):
		for x in range(board.size):
			_set_stone_vox(x, y, VoxelMaterial.AIR)


func _kick() -> void:
	if _animating:
		return
	_drain()


func _drain() -> void:
	if _queue.is_empty():
		_animating = false
		return
	_animating = true
	var job: Dictionary = _queue.pop_front()
	match String(job.get("op", "")):
		"place":
			await _animate_place(int(job["color"]), int(job["x"]), int(job["y"]))
		"capture":
			await _animate_capture(job.get("locs", []) as Array)
	_drain()


func _animate_place(color: int, x: int, y: int) -> void:
	var target := world_pos_for(x, y)
	var mat := black_mat if color == GoBoardState.BLACK else white_mat
	if _hand != null and _hand.has_method("place_at"):
		await _hand.call("place_at", target, color == GoBoardState.BLACK)
	_set_stone_vox(x, y, mat)


func _animate_capture(locs: Array) -> void:
	for loc_v in locs:
		var loc := loc_v as Vector2i
		if loc == null:
			continue
		_set_stone_vox(loc.x, loc.y, VoxelMaterial.AIR)
		await get_tree().create_timer(0.04).timeout


func _set_stone_vox(x: int, y: int, mat: int) -> void:
	if not live_brush.is_valid():
		return
	var brush: CityBrush = live_brush.call() as CityBrush
	if brush == null:
		return
	var wx := origin_vox.x + giant_origin_local.x + x * cell_vox
	var wz := origin_vox.z + giant_origin_local.z + y * cell_vox
	## Wide corner-cut base under a smaller cap: a domed lens, never a cube. Both layers
	## sit above the painted grid, so a capture can never hole the board itself.
	var base_y := origin_vox.y + giant_origin_local.y + 1
	var r := stone_radius()
	_stone_layer(brush, wx, wz, base_y, r, mat)
	_stone_layer(brush, wx, wz, base_y + 1, maxi(r - 1, 1), mat)


## One octagonal slice of a giant stone: a square with its four corners knocked off.
func _stone_layer(brush: CityBrush, wx: int, wz: int, y: int, half: int, mat: int) -> void:
	brush.fill_box(
		Vector3i(wx - half, y, wz - half),
		Vector3i(wx + half + 1, y + 1, wz + half + 1),
		mat
	)
	if half < 2:
		return
	for dz: int in [-half, half]:
		for dx: int in [-half, half]:
			brush.set_vox(Vector3i(wx + dx, y, wz + dz), VoxelMaterial.AIR)

