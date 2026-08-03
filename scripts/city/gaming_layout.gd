## Bake-time plan for a Gaming district plaza (Go first).
class_name GamingLayout
extends RefCounted

## Giant board SW corner (district-local voxels) at surface Y of the pad top.
var giant_origin: Vector3i = Vector3i.ZERO
## Spacing between intersections in voxels (default 4 → 2 m).
var giant_cell_vox: int = 4
var board_n: int = 19
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


## Distance from first to last intersection (n points → n lines, n−1 gaps).
func giant_span_vox() -> int:
	return (board_n - 1) * giant_cell_vox


func describe() -> String:
	return "GamingLayout giant %dx%d cell=%d pad=%s..%s table=%s" % [
		board_n, board_n, giant_cell_vox, pad_min, pad_max, main_table_origin
	]
