## Builds a Gaming-theme games quarter: meadow, giant Go pad and main table at the centre,
## a Japanese garden banded around them (GamingGarden), and one satellite court on each
## flanking lawn — a Tetris arcade to the west (GamingArcade) and a monster-chess board to
## the east (GamingChessCourt). The north and south lawns stay open meadow on purpose.
class_name GamingComposer
extends RefCounted

const GamingGardenScript := preload("res://scripts/city/gaming_garden.gd")
const GamingArcadeScript := preload("res://scripts/city/gaming_arcade.gd")
const GamingChessCourtScript := preload("res://scripts/city/gaming_chess_court.gd")

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28
var voxel_size: float = 0.5

var layout: GamingLayout = null
var _garden: GamingGarden = null
var _arcade: GamingArcade = null
var _chess_court: GamingChessCourt = null

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

## Satellite zones flank the garden on the west and east lawns, at the same depth as the
## garden band so the three read as one row of courts rather than a scatter.
## Kept clear of the reserve edge, where a perimeter road can run.
const ZONE_INSET := 6
## Gap between the garden band and a satellite: neither writes into the other.
const ZONE_GAP := 4
## Narrowest lawn worth a court at all — below this the zone is dropped, loudly.
const ZONE_MIN_W := 96
## 4 m per chess square: two 2.3 m monsters stand on adjacent squares without their
## silhouettes touching.
const CHESS_SQUARE_VOX := 8


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	## Garden first: it repaints ground courses, and the pad / table must sit on top.
	_garden_for().decorate(layout, min_v, max_v)
	_plan_zones(min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	_arcade_for().build(layout)
	_chess_court_for().build(layout)
	print("GamingComposer: %s" % layout.describe())


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	_garden_for().decorate_far(layout, min_v, max_v)
	_plan_zones(min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	## Both satellites are mostly silhouette (a lit pavilion, a checkerboard slab), so the
	## far pass builds the same shells — they are cheap and the quarter reads wrong without.
	_arcade_for().build(layout)
	_chess_court_for().build(layout)


func _garden_for() -> GamingGarden:
	if _garden == null:
		_garden = GamingGardenScript.new() as GamingGarden
		_garden.brush = brush
		_garden.rng = rng
		_garden.ground_y = ground_y
		_garden.table_w = TABLE_W
		_garden.table_d = TABLE_D
	return _garden


func _arcade_for() -> GamingArcade:
	if _arcade == null:
		_arcade = GamingArcadeScript.new() as GamingArcade
		_arcade.brush = brush
		_arcade.rng = rng
		_arcade.ground_y = ground_y
	return _arcade


func _chess_court_for() -> GamingChessCourt:
	if _chess_court == null:
		_chess_court = GamingChessCourtScript.new() as GamingChessCourt
		_chess_court.brush = brush
		_chess_court.rng = rng
		_chess_court.ground_y = ground_y
	return _chess_court


## Carve the two lawns either side of the garden band and put the chess board in the
## middle of the eastern one. Runs after the garden, because the band it flanks is only
## known once GamingGarden has published it.
func _plan_zones(min_v: Vector3i, max_v: Vector3i) -> void:
	var g0 := layout.garden_min
	var g1 := layout.garden_max
	if g1.x <= g0.x or g1.z <= g0.z:
		push_error("GamingComposer: no garden band to flank — the satellites have no anchor")
		return
	var west_x0 := min_v.x + ZONE_INSET
	var west_x1 := g0.x - ZONE_GAP
	if west_x1 - west_x0 >= ZONE_MIN_W:
		layout.arcade_min = Vector3i(west_x0, ground_y, g0.z)
		layout.arcade_max = Vector3i(west_x1, ground_y + 1, g1.z)
	else:
		push_error(
			"GamingComposer: west lawn is only %d voxels wide — no arcade here"
			% [west_x1 - west_x0]
		)
	var east_x0 := g1.x + ZONE_GAP
	var east_x1 := max_v.x - ZONE_INSET
	if east_x1 - east_x0 < ZONE_MIN_W:
		push_error(
			"GamingComposer: east lawn is only %d voxels wide — no chess court here"
			% [east_x1 - east_x0]
		)
		return
	layout.chess_min = Vector3i(east_x0, ground_y, g0.z)
	layout.chess_max = Vector3i(east_x1, ground_y + 1, g1.z)
	layout.chess_square_vox = CHESS_SQUARE_VOX
	var span := layout.chess_span_vox()
	layout.chess_origin = Vector3i(
		(east_x0 + east_x1) / 2 - span / 2,
		ground_y + 1,
		(g0.z + g1.z) / 2 - span / 2
	)


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
	ly.field_span_vox = span
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
	var hoshi := hoshi_points(BOARD_N)
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
			## Star point: a round dot on the crossing, same ink as the lines.
			brush.fill_disk(
				go.x + hx * cell, go.z + hz * cell, board_y, 1, BOARD_LINE_MAT
			)


## Star-point indices for a board of size `n` (GTP coordinates from the SW corner).
static func hoshi_points(n: int) -> PackedInt32Array:
	if n >= 19:
		return PackedInt32Array([3, 9, 15])
	if n >= 13:
		return PackedInt32Array([3, 6, 9])
	if n >= 9:
		return PackedInt32Array([2, 4, 6])
	return PackedInt32Array()


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
