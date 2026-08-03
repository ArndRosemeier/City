## Builds a Gaming-theme plaza: meadow, giant Go pad, one wide main table.
class_name GamingComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28
var voxel_size: float = 0.5

var layout: GamingLayout = null

const BOARD_N := 19
## 3 m between crossings: wide enough for a rounded 5-voxel stone with a gap, and it
## makes the 1-voxel grid line a sixth of a cell instead of a quarter (which read as a
## white lattice rather than a board).
const GIANT_CELL := 6
## Light field carried past the outer lines, then the dark rim around it.
const BOARD_EDGE := 4
const BOARD_RIM := 2
const PAD_MARGIN := 8
## Light kaya-style playing surface; lines and rim are the dark timber.
const BOARD_FIELD_MAT := VoxelMaterial.GRAVEL
const BOARD_LINE_MAT := VoxelMaterial.TIMBER
## Wide enough for board Ui3D + settings panel side by side, and no wider — a bigger
## slab just reads as an empty timber field around two small panels.
const TABLE_W := 18
const TABLE_D := 10
## Low raised pad (no legs) — height in voxels above the meadow surface layer.
const TABLE_H := 2
## Board sits on the west half; settings on the east (fractions of table width).
const BOARD_X_FRAC := 0.33
const SETTINGS_X_FRAC := 0.76


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	print("GamingComposer: %s" % layout.describe())


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	_build_giant_pad()
	_build_main_table()


func _begin() -> bool:
	if brush == null or rng == null or planner == null:
		push_error("GamingComposer: brush / rng / planner not set")
		return false
	if planner.large_gaming.size.x <= 0:
		push_error("GamingComposer: empty large_gaming")
		return false
	return true


func _plan(min_v: Vector3i, max_v: Vector3i) -> GamingLayout:
	var la: Rect2i = planner.large_gaming
	var x0 := la.position.x * cell_size
	var z0 := la.position.y * cell_size
	var x1 := la.end.x * cell_size
	var z1 := la.end.y * cell_size
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2
	var span := (BOARD_N - 1) * GIANT_CELL
	var pad_side := span + (BOARD_EDGE + BOARD_RIM + PAD_MARGIN) * 2 + 1
	var ly := GamingLayout.new()
	ly.board_n = BOARD_N
	ly.giant_cell_vox = GIANT_CELL
	ly.pad_min = Vector3i(cx - pad_side / 2, ground_y, cz - pad_side / 2)
	ly.pad_max = Vector3i(ly.pad_min.x + pad_side, ground_y + 1, ly.pad_min.z + pad_side)
	var inset := PAD_MARGIN + BOARD_RIM + BOARD_EDGE
	ly.giant_origin = Vector3i(
		ly.pad_min.x + inset,
		ground_y + 1,
		ly.pad_min.z + inset
	)
	## Main table south of the pad, facing north toward the giant board.
	var table_z := ly.pad_min.z - 18
	var table_x := cx - TABLE_W / 2
	ly.main_table_origin = Vector3i(table_x, ground_y, table_z)
	ly.main_table_yaw = 0.0
	var vs := voxel_size
	var mid_x := (float(table_x) + float(TABLE_W) * 0.5) * vs
	ly.black_stand_local = Vector3(
		mid_x,
		float(ground_y + 1) * vs,
		(float(table_z) - 2.5) * vs
	)
	ly.white_stand_local = Vector3(
		mid_x,
		float(ground_y + 1) * vs,
		(float(table_z) + float(TABLE_D) + 2.5) * vs
	)
	## Waiting bench east of the table.
	ly.ai_wait_local = Vector3(
		(float(table_x) + float(TABLE_W) + 4.0) * vs,
		float(ground_y + 1) * vs,
		(float(table_z) + float(TABLE_D) * 0.5) * vs
	)
	ly.spawn_local = Vector3(
		float(cx) * vs,
		float(ground_y + 1) * vs + 0.85,
		(float(table_z) - 22.0) * vs
	)
	ly.spawn_yaw = 0.0
	return ly


func _paint_meadow(min_v: Vector3i, max_v: Vector3i) -> void:
	brush.fill_box(
		Vector3i(min_v.x, ground_y, min_v.z),
		Vector3i(max_v.x, ground_y + 1, max_v.z),
		VoxelMaterial.PARK
	)


func _build_giant_pad() -> void:
	var p0 := layout.pad_min
	var p1 := layout.pad_max
	## Plain stone apron — the walkable frame the board is read against.
	brush.fill_box(p0, Vector3i(p1.x, ground_y + 1, p1.z), VoxelMaterial.STONE)
	var go := layout.giant_origin
	var cell := layout.giant_cell_vox
	var span := layout.giant_span_vox()
	var board_y := ground_y + 1
	## Dark rim, then the light field inside it — both a single flush layer, so the
	## board is a slab you look at, not a lattice you walk through.
	var rim := BOARD_EDGE + BOARD_RIM
	brush.fill_box(
		Vector3i(go.x - rim, board_y, go.z - rim),
		Vector3i(go.x + span + rim + 1, board_y + 1, go.z + span + rim + 1),
		BOARD_LINE_MAT
	)
	brush.fill_box(
		Vector3i(go.x - BOARD_EDGE, board_y, go.z - BOARD_EDGE),
		Vector3i(go.x + span + BOARD_EDGE + 1, board_y + 1, go.z + span + BOARD_EDGE + 1),
		BOARD_FIELD_MAT
	)
	## n lines meet at n×n crossings — stones sit on those intersections.
	for i in range(BOARD_N):
		var lx := go.x + i * cell
		var lz := go.z + i * cell
		brush.fill_box(
			Vector3i(lx, board_y, go.z),
			Vector3i(lx + 1, board_y + 1, go.z + span + 1),
			BOARD_LINE_MAT
		)
		brush.fill_box(
			Vector3i(go.x, board_y, lz),
			Vector3i(go.x + span + 1, board_y + 1, lz + 1),
			BOARD_LINE_MAT
		)
	var hoshi: PackedInt32Array = PackedInt32Array([3, 9, 15])
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
			## Star point: a round dot on the crossing, same ink as the lines.
			brush.fill_disk(
				go.x + hx * cell, go.z + hz * cell, board_y, 1, BOARD_LINE_MAT
			)


func _build_main_table() -> void:
	_build_table_block(layout.main_table_origin)


func _build_table_block(origin: Vector3i) -> void:
	var y0 := ground_y + 1
	var y_top := y0 + TABLE_H
	if TABLE_H > 1:
		brush.fill_box(
			Vector3i(origin.x, y0, origin.z),
			Vector3i(origin.x + TABLE_W, y_top - 1, origin.z + TABLE_D),
			VoxelMaterial.STONE
		)
	brush.fill_box(
		Vector3i(origin.x, y_top - 1, origin.z),
		Vector3i(origin.x + TABLE_W, y_top, origin.z + TABLE_D),
		VoxelMaterial.TIMBER
	)
