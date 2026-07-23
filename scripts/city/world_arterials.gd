## Deterministic world arterial skeleton so neighboring districts meet at edges.
class_name WorldArterials
extends RefCounted

## Double-wide avenues on a fixed world cell lattice (independent of district seed).
const ROW_PERIOD := 7
const COL_PERIOD := 8


static func is_arterial_row(world_cz: int) -> bool:
	var m := posmod(world_cz, ROW_PERIOD)
	return m == 0 or m == 1


static func is_arterial_col(world_cx: int) -> bool:
	var m := posmod(world_cx, COL_PERIOD)
	return m == 0 or m == 1


static func is_arterial_cell(world_cx: int, world_cz: int) -> bool:
	return is_arterial_row(world_cz) or is_arterial_col(world_cx)
