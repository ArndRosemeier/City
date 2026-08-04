## Bake-time plan for a Gaming district plaza (Go first).
class_name GamingLayout
extends RefCounted

## Giant board SW corner (district-local voxels) at surface Y of the pad top.
## Bake paints the max field here; runtime may center a smaller n inside it.
var giant_origin: Vector3i = Vector3i.ZERO
## Bake-time spacing for the full field (usually 19×19).
var giant_cell_vox: int = 4
## Active board size (9 or 19). Setup UI can change this before a match.
var board_n: int = 19
## Fixed playfield span in voxels (first→last intersection of the baked max board).
## Live 9×9 uses a larger cell so the grid still fills this footprint.
var field_span_vox: int = 0
## Pad AABB (inclusive min, exclusive-ish max style as Rect2i XZ + y).
var pad_min: Vector3i = Vector3i.ZERO
var pad_max: Vector3i = Vector3i.ZERO
## Main play table: voxel furniture origin (SW) and facing yaw (radians, Godot Y).
var main_table_origin: Vector3i = Vector3i.ZERO
var main_table_yaw: float = 0.0
## Local metres: black seat (south), white seat (north), AI waiting bench.
var black_stand_local: Vector3 = Vector3.ZERO
var white_stand_local: Vector3 = Vector3.ZERO
var ai_wait_local: Vector3 = Vector3.ZERO
## District-local spawn suggestion (meters from tile origin on XZ, Y absolute later).
var spawn_local: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0
## Japanese-garden precinct around the Go furniture, in district-local voxels (max
## exclusive). GamingGarden fills this in; other zones on the tile should stay out of it.
var garden_min: Vector3i = Vector3i.ZERO
var garden_max: Vector3i = Vector3i.ZERO
## Tetris arcade precinct on the west lawn, district-local voxels (max exclusive).
var arcade_min: Vector3i = Vector3i.ZERO
var arcade_max: Vector3i = Vector3i.ZERO
## Ground anchors for the permanent Tetris cabinets: the base centre of each, in
## district-local voxels. Stream-in spawns one TetrisMachine per entry, all facing
## `arcade_yaw`. Baked by GamingArcade so the runtime needs no bake constants.
var arcade_cabinets: Array[Vector3i] = []
var arcade_yaw: float = 0.0
## Mid-row fallback spawn for a cabinet ped, district-local voxels. Runtime prefers a stand
## in front of each ped's own bay; this stays for layout dumps and older callers.
var arcade_ped_spawn: Vector3i = Vector3i.ZERO
## Monster-chess precinct on the east lawn, district-local voxels (max exclusive).
var chess_min: Vector3i = Vector3i.ZERO
var chess_max: Vector3i = Vector3i.ZERO
## Board SW corner (a1) and square pitch, so the runtime arena needs no bake constants.
## `chess_origin.y` is the voxel course the checkerboard is painted into; pieces stand
## one course above it.
var chess_origin: Vector3i = Vector3i.ZERO
var chess_square_vox: int = 8


## Distance from first to last intersection of the baked field.
func giant_span_vox() -> int:
	if field_span_vox > 0:
		return field_span_vox
	return (board_n - 1) * giant_cell_vox


## Cell spacing so `n` intersections fill `field_span_vox` (integer, may leave a
## centred inset of a few voxels).
func cell_vox_for(n: int) -> int:
	if n < 2:
		push_error("GamingLayout.cell_vox_for: bad n %d" % n)
		return giant_cell_vox
	var span := giant_span_vox()
	return maxi(span / (n - 1), 1)


## Edge length of the whole 8×8 checkerboard in voxels.
func chess_span_vox() -> int:
	return chess_square_vox * 8


## Centre of chess square (file, rank) in district-local voxel units, XZ only. File 0 is
## the a-file and rank 0 is white's home rank, both at the board's SW corner.
func chess_square_center(file: int, rank: int) -> Vector2:
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		push_error("GamingLayout.chess_square_center: off board (%d, %d)" % [file, rank])
		return Vector2.ZERO
	var half := float(chess_square_vox) * 0.5
	return Vector2(
		float(chess_origin.x + file * chess_square_vox) + half,
		float(chess_origin.z + rank * chess_square_vox) + half
	)


func describe() -> String:
	return "GamingLayout giant %dx%d cell=%d span=%d pad=%s..%s table=%s arcade=%s..%s(%d cabs) chess=%s..%s board=%s/%d" % [
		board_n, board_n, giant_cell_vox, giant_span_vox(), pad_min, pad_max, main_table_origin,
		arcade_min, arcade_max, arcade_cabinets.size(), chess_min, chess_max,
		chess_origin, chess_square_vox
	]
