## One straight flight of castle stairs, in district-local voxel coordinates.
##
## The lane is a grid of treads: `t` runs 0 .. rise+2 along `dir`, `k` runs 0 .. lane_w-1
## across it. `t = 0` is the flat approach at the bottom, `t = rise+1` the flat arrival at
## the top, and `t = rise+2` the first column of the floor being arrived at. Offset
## `k = lane_w` carries the rail; the far side abuts masonry.
##
## Every riser is exactly one voxel. Pedestrian `max_step` is 1.25 and `LinkParams`
## `min_drop` is 1.7, so a two-voxel riser leaves the walk graph and bakes as a one-way
## drop link instead: a trapdoor, not a stair. Sweep comes from the run, never the rise.
class_name CastleStair
extends RefCounted

## Column of tread (t = 0, k = 0).
var origin: Vector2i = Vector2i.ZERO
## Climb direction. Always cardinal.
var dir: Vector2i = Vector2i.ZERO
## Across direction. Always cardinal and perpendicular to `dir`.
var across: Vector2i = Vector2i.ZERO
var lane_w: int = 0
## Voxels of climb, and the surface the flight leaves from.
var rise: int = 0
var y_from: int = 0
## Keep storeys the flight links. -1 marks the courtyard ramp to the curtain crown.
var from_storey: int = -1
var to_storey: int = -1


## Treads along the lane, approach and arrival included.
func run_len() -> int:
	return rise + 3


func top_y() -> int:
	return y_from + rise


## Walking surface of tread `t`.
func surface_at(t: int) -> int:
	assert(t >= 0 and t < run_len())
	return y_from + clampi(t - 1, 0, rise)


func column(t: int, k: int) -> Vector2i:
	return origin + dir * t + across * k


## Centre lane column of tread `t`.
func center_column(t: int) -> Vector2i:
	return column(t, lane_w / 2)


## Everything the flight claims, rail included.
func footprint() -> Rect2i:
	var far := column(run_len() - 1, lane_w)
	var lo := Vector2i(mini(origin.x, far.x), mini(origin.y, far.y))
	var hi := Vector2i(maxi(origin.x, far.x), maxi(origin.y, far.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func matches(other: CastleStair) -> bool:
	if other == null:
		return false
	return (
		origin == other.origin
		and dir == other.dir
		and across == other.across
		and lane_w == other.lane_w
		and rise == other.rise
		and y_from == other.y_from
		and from_storey == other.from_storey
		and to_storey == other.to_storey
	)


func describe() -> String:
	return "stair %d→%d %s dir=%s w=%d rise=%d y=%d" % [
		from_storey, to_storey, origin, dir, lane_w, rise, y_from
	]
