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
## World-space stand for the player seat (set at runtime from origin_vox).
var main_player_stand_local: Vector3 = Vector3.ZERO
var main_ped_stand_local: Vector3 = Vector3.ZERO
## Side ped-vs-ped tables: Array of {origin: Vector3i, yaw: float, ped_a: Vector3, ped_b: Vector3}
var side_tables: Array[Dictionary] = []
## Invite roster stands along the plaza edge (local meters relative to district 0,0 ground).
var invite_stands: Array[Dictionary] = []
## District-local spawn suggestion (meters from tile origin on XZ, Y absolute later).
var spawn_local: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0


## Pad / grid extent for an n×n field board (n cells → n+1 grid lines).
func giant_span_vox() -> int:
	return board_n * giant_cell_vox


func describe() -> String:
	return "GamingLayout giant %dx%d cell=%d pad=%s..%s sides=%d" % [
		board_n, board_n, giant_cell_vox, pad_min, pad_max, side_tables.size()
	]
