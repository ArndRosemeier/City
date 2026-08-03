## Builds a Gaming-theme plaza: meadow, giant Go pad, main table, side tables.
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
const GIANT_CELL := 4
const PAD_MARGIN := 6
const TABLE_W := 14
const TABLE_D := 10
## Low raised pad (no legs) — height in voxels above the meadow surface layer.
const TABLE_H := 2
const SIDE_BOARD_CELL := 2


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	for side in layout.side_tables:
		_build_side_table(side)
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
	var span := BOARD_N * GIANT_CELL
	var pad_side := span + PAD_MARGIN * 2
	var ly := GamingLayout.new()
	ly.board_n = BOARD_N
	ly.giant_cell_vox = GIANT_CELL
	ly.pad_min = Vector3i(cx - pad_side / 2, ground_y, cz - pad_side / 2)
	ly.pad_max = Vector3i(ly.pad_min.x + pad_side, ground_y + 1, ly.pad_min.z + pad_side)
	ly.giant_origin = Vector3i(
		ly.pad_min.x + PAD_MARGIN,
		ground_y + 1,
		ly.pad_min.z + PAD_MARGIN
	)
	## Main table south of the pad, facing north toward the giant board.
	var table_z := ly.pad_min.z - 18
	var table_x := cx - TABLE_W / 2
	ly.main_table_origin = Vector3i(table_x, ground_y, table_z)
	ly.main_table_yaw = 0.0
	var vs := voxel_size
	ly.main_player_stand_local = Vector3(
		(float(table_x) + float(TABLE_W) * 0.5) * vs,
		float(ground_y + 1) * vs,
		(float(table_z) - 2.0) * vs
	)
	ly.main_ped_stand_local = Vector3(
		(float(table_x) + float(TABLE_W) * 0.5) * vs,
		float(ground_y + 1) * vs,
		(float(table_z) + float(TABLE_D) + 2.0) * vs
	)
	## Side tables east and west of the pad.
	ly.side_tables = [
		_side_spec(ly.pad_max.x + 10, cz - 8, -PI * 0.5, vs),
		_side_spec(ly.pad_min.x - 10 - TABLE_W, cz - 8, PI * 0.5, vs),
	]
	## Invite stands further south, facing the main table.
	ly.invite_stands = [
		{"tier": "novice", "local": Vector3((float(cx) - 8.0) * vs, float(ground_y + 1) * vs, (float(table_z) - 14.0) * vs), "yaw": 0.0},
		{"tier": "club", "local": Vector3(float(cx) * vs, float(ground_y + 1) * vs, (float(table_z) - 14.0) * vs), "yaw": 0.0},
		{"tier": "dan", "local": Vector3((float(cx) + 8.0) * vs, float(ground_y + 1) * vs, (float(table_z) - 14.0) * vs), "yaw": 0.0},
	]
	ly.spawn_local = Vector3(
		float(cx) * vs,
		float(ground_y + 1) * vs + 0.85,
		(float(table_z) - 22.0) * vs
	)
	ly.spawn_yaw = 0.0
	return ly


func _side_spec(ox: int, oz: int, yaw: float, vs: float) -> Dictionary:
	return {
		"origin": Vector3i(ox, ground_y, oz),
		"yaw": yaw,
		"ped_a": Vector3((float(ox) + 2.0) * vs, float(ground_y + 1) * vs, (float(oz) - 2.0) * vs),
		"ped_b": Vector3((float(ox) + float(TABLE_W) - 2.0) * vs, float(ground_y + 1) * vs, (float(oz) + float(TABLE_D) + 2.0) * vs),
		"cell_vox": SIDE_BOARD_CELL,
	}


func _paint_meadow(min_v: Vector3i, max_v: Vector3i) -> void:
	brush.fill_box(
		Vector3i(min_v.x, ground_y, min_v.z),
		Vector3i(max_v.x, ground_y + 1, max_v.z),
		VoxelMaterial.PARK
	)


func _build_giant_pad() -> void:
	var p0 := layout.pad_min
	var p1 := layout.pad_max
	brush.fill_box(p0, Vector3i(p1.x, ground_y + 1, p1.z), VoxelMaterial.TILES)
	## Timber playing surface one voxel up.
	var go := layout.giant_origin
	var cell := layout.giant_cell_vox
	var span := layout.giant_span_vox()
	brush.fill_box(
		Vector3i(go.x - 1, ground_y + 1, go.z - 1),
		Vector3i(go.x + span + 2, ground_y + 2, go.z + span + 2),
		VoxelMaterial.TIMBER
	)
	## Grid lines between n×n empty fields (n+1 lines).
	for i in range(BOARD_N + 1):
		var lx := go.x + i * cell
		var lz := go.z + i * cell
		brush.fill_box(
			Vector3i(lx, ground_y + 1, go.z),
			Vector3i(lx + 1, ground_y + 2, go.z + span + 1),
			VoxelMaterial.GRAVEL
		)
		brush.fill_box(
			Vector3i(go.x, ground_y + 1, lz),
			Vector3i(go.x + span + 1, ground_y + 2, lz + 1),
			VoxelMaterial.GRAVEL
		)
	## Hoshi dots at field centres (4-4 style indices for 19).
	var hoshi: PackedInt32Array = PackedInt32Array([3, 9, 15])
	var half := cell / 2
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
			var sx: int = go.x + hx * cell + half
			var sz: int = go.z + hz * cell + half
			brush.set_vox(Vector3i(sx, ground_y + 1, sz), VoxelMaterial.STONE)


func _build_main_table() -> void:
	_build_table_block(layout.main_table_origin)


func _build_side_table(side: Dictionary) -> void:
	var origin: Vector3i = side["origin"]
	_build_table_block(origin)
	## Compact timber board on the table top.
	var cell: int = int(side.get("cell_vox", SIDE_BOARD_CELL))
	var span := BOARD_N * cell
	var bx := origin.x + (TABLE_W - span) / 2
	var bz := origin.z + (TABLE_D - span) / 2
	brush.fill_box(
		Vector3i(bx, ground_y + TABLE_H, bz),
		Vector3i(bx + span + 1, ground_y + TABLE_H + 1, bz + span + 1),
		VoxelMaterial.TIMBER
	)


func _build_table_block(origin: Vector3i) -> void:
	## Solid low platform (no legs) — stone bulk + timber cap.
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
