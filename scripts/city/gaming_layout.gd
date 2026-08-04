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


func describe() -> String:
	return "GamingLayout giant %dx%d cell=%d span=%d pad=%s..%s table=%s" % [
		board_n, board_n, giant_cell_vox, giant_span_vox(), pad_min, pad_max, main_table_origin
	]
