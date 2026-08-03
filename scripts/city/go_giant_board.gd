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
var black_mat: int = VoxelMaterial.GRAVE_STONE
var white_mat: int = VoxelMaterial.GRAVE_MARBLE
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


func world_pos_for(x: int, y: int) -> Vector3:
	## Stone sits in the centre of an empty field (half-cell inset).
	var half := cell_vox / 2
	var wx := origin_vox.x + giant_origin_local.x + x * cell_vox + half
	var wz := origin_vox.z + giant_origin_local.z + y * cell_vox + half
	var wy := origin_vox.y + giant_origin_local.y
	return Vector3(
		(float(wx) + 0.5) * voxel_size,
		float(wy + 1) * voxel_size,
		(float(wz) + 0.5) * voxel_size
	)


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
	var half_cell := cell_vox / 2
	var wx := origin_vox.x + giant_origin_local.x + x * cell_vox + half_cell
	var wz := origin_vox.z + giant_origin_local.z + y * cell_vox + half_cell
	var wy := origin_vox.y + giant_origin_local.y
	## Short disc centred in the field; keep clear of grid lines.
	var half := maxi(cell_vox / 4, 1)
	brush.fill_box(
		Vector3i(wx - half, wy, wz - half),
		Vector3i(wx + half + 1, wy + 2, wz + half + 1),
		mat
	)

