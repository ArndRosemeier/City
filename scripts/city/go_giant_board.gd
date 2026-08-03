## Live voxel giant Go board — mirrors BoardState via CityBrush.
class_name GoGiantBoard
extends Node3D

const GoGiantBeamScript := preload("res://scripts/city/go_giant_beam.gd")

const BOARD_EDGE := 4
const BOARD_FIELD_MAT := VoxelMaterial.GRAVEL
const BOARD_LINE_MAT := VoxelMaterial.TIMBER

var board: GoBoardState = null
var live_brush: Callable = Callable()
var origin_vox: Vector3i = Vector3i.ZERO
## Bake-time SW corner of the full field (rim / field painted here).
var giant_origin_local: Vector3i = Vector3i.ZERO
## SW corner of the active n×n grid (may be inset when n < bake size).
var grid_origin_local: Vector3i = Vector3i.ZERO
var cell_vox: int = 4
var field_span_vox: int = 0
var board_n: int = 19
var voxel_size: float = 0.5
## Slate black against chalk white. The graveyard pair (GRAVE_STONE / GRAVE_MARBLE) both
## sit mid-grey and washed out against the light board field.
var black_mat: int = VoxelMaterial.ASPHALT
var white_mat: int = VoxelMaterial.PLASTER
var _beam: GoGiantBeam = null
var _animating: bool = false
var _queue: Array[Dictionary] = []
## Bumped by cancel_animations so in-flight place/capture awaits discard their writes.
var _anim_epoch: int = 0


func setup(
	p_board: GoBoardState,
	p_live_brush: Callable,
	p_origin_vox: Vector3i,
	p_giant_origin_local: Vector3i,
	p_cell_vox: int,
	p_voxel_size: float,
	p_field_span_vox: int = 0
) -> void:
	board = p_board
	live_brush = p_live_brush
	origin_vox = p_origin_vox
	giant_origin_local = p_giant_origin_local
	grid_origin_local = p_giant_origin_local
	cell_vox = p_cell_vox
	voxel_size = p_voxel_size
	board_n = board.size if board != null else 19
	field_span_vox = p_field_span_vox if p_field_span_vox > 0 else (board_n - 1) * cell_vox
	_beam = GoGiantBeamScript.new() as GoGiantBeam
	_beam.name = "GoGiantBeam"
	add_child(_beam)
	_beam.configure(cell_world_m())
	_connect_board_signals()


## Crossing-to-crossing spacing in metres — the scale everything animated works from.
func cell_world_m() -> float:
	return float(cell_vox) * voxel_size


## Switch 9↔19 (or any supported n): clear stones, retile the grid in the same pad.
func set_board_size(n: int, p_board: GoBoardState) -> void:
	if n < 2:
		push_error("GoGiantBoard.set_board_size: bad n %d" % n)
		return
	_disconnect_board_signals()
	_clear_all()
	board = p_board
	board_n = n
	cell_vox = maxi(field_span_vox / (n - 1), 1)
	var used := (n - 1) * cell_vox
	var inset := (field_span_vox - used) / 2
	grid_origin_local = Vector3i(
		giant_origin_local.x + inset,
		giant_origin_local.y,
		giant_origin_local.z + inset
	)
	_paint_grid()
	if _beam != null:
		_beam.configure(cell_world_m())
	_connect_board_signals()
	if board != null:
		paint_snapshot(board)


## Base voxel radius of a giant stone: leaves one voxel of board between neighbours.
func stone_radius() -> int:
	return maxi(cell_vox / 2 - 1, 1)


func world_pos_for(x: int, y: int) -> Vector3:
	## Stone sits on a grid crossing (line intersection), not in a cell centre.
	var wx := origin_vox.x + grid_origin_local.x + x * cell_vox
	var wz := origin_vox.z + grid_origin_local.z + y * cell_vox
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


func cancel_animations() -> void:
	_anim_epoch += 1
	_queue.clear()
	_animating = false
	if _beam != null:
		_beam.cancel()


func _clear_all() -> void:
	cancel_animations()
	var n := board.size if board != null else board_n
	for y in range(n):
		for x in range(n):
			_set_stone_vox(x, y, VoxelMaterial.AIR)


func _connect_board_signals() -> void:
	if board == null:
		return
	if not board.moved.is_connected(_on_moved):
		board.moved.connect(_on_moved)
	if not board.captured.is_connected(_on_captured):
		board.captured.connect(_on_captured)
	if not board.reset.is_connected(_clear_all):
		board.reset.connect(_clear_all)


func _disconnect_board_signals() -> void:
	if board == null:
		return
	if board.moved.is_connected(_on_moved):
		board.moved.disconnect(_on_moved)
	if board.captured.is_connected(_on_captured):
		board.captured.disconnect(_on_captured)
	if board.reset.is_connected(_clear_all):
		board.reset.disconnect(_clear_all)


func _paint_grid() -> void:
	if not live_brush.is_valid():
		return
	var brush: CityBrush = live_brush.call() as CityBrush
	if brush == null:
		return
	var go := Vector3i(
		origin_vox.x + giant_origin_local.x,
		origin_vox.y + giant_origin_local.y,
		origin_vox.z + giant_origin_local.z
	)
	var board_y := go.y
	var span := field_span_vox
	## Refill the light field so previous line ink disappears, then draw the new grid.
	brush.fill_box(
		Vector3i(go.x - BOARD_EDGE, board_y, go.z - BOARD_EDGE),
		Vector3i(go.x + span + BOARD_EDGE + 1, board_y + 1, go.z + span + BOARD_EDGE + 1),
		BOARD_FIELD_MAT
	)
	var g0 := Vector3i(
		origin_vox.x + grid_origin_local.x,
		board_y,
		origin_vox.z + grid_origin_local.z
	)
	var used := (board_n - 1) * cell_vox
	for i in range(board_n):
		var lx := g0.x + i * cell_vox
		var lz := g0.z + i * cell_vox
		brush.fill_box(
			Vector3i(lx, board_y, g0.z),
			Vector3i(lx + 1, board_y + 1, g0.z + used + 1),
			BOARD_LINE_MAT
		)
		brush.fill_box(
			Vector3i(g0.x, board_y, lz),
			Vector3i(g0.x + used + 1, board_y + 1, lz + 1),
			BOARD_LINE_MAT
		)
	var hoshi := GamingComposer.hoshi_points(board_n)
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
			brush.fill_disk(
				g0.x + hx * cell_vox, g0.z + hz * cell_vox, board_y, 1, BOARD_LINE_MAT
			)


func _kick() -> void:
	if _animating:
		return
	_drain()


func _drain() -> void:
	if _queue.is_empty():
		_animating = false
		return
	_animating = true
	var epoch := _anim_epoch
	var job: Dictionary = _queue.pop_front()
	match String(job.get("op", "")):
		"place":
			await _animate_place(int(job["color"]), int(job["x"]), int(job["y"]), epoch)
		"capture":
			await _animate_capture(job.get("locs", []) as Array, epoch)
	if epoch != _anim_epoch:
		_animating = false
		return
	_drain()


func _animate_place(color: int, x: int, y: int, epoch: int) -> void:
	var target := world_pos_for(x, y)
	var mat := black_mat if color == GoBoardState.BLACK else white_mat
	if _beam != null:
		await _beam.place_at(target, color == GoBoardState.BLACK)
	if epoch != _anim_epoch:
		return
	_set_stone_vox(x, y, mat)


func _animate_capture(locs: Array, epoch: int) -> void:
	for loc_v in locs:
		if epoch != _anim_epoch:
			return
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
	var wx := origin_vox.x + grid_origin_local.x + x * cell_vox
	var wz := origin_vox.z + grid_origin_local.z + y * cell_vox
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
