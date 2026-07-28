## One tower of a castle: where it stands, how wide it is, and how high it reaches.
##
## Phase 1 builds these solid. Phase 2 hollows them into stair turrets and chambers, so
## the footprint has to survive the bake as data rather than being re-derived from voxels.
class_name CastleTower
extends RefCounted

## Curtain corner, mid-wall bastion, or one of the pair flanking the gate passage.
const KIND_CORNER := 0
const KIND_MID := 1
const KIND_GATE := 2

## District-local voxel column the tower is centred on.
var center: Vector2i = Vector2i.ZERO
## Half-width (square) or radius (round), in voxels.
var radius: int = 0
## Highest solid voxel of the shaft, merlons excluded.
var top_y: int = 0
var round_plan: bool = false
var kind: int = KIND_CORNER


func kind_name() -> String:
	match kind:
		KIND_CORNER:
			return "corner"
		KIND_MID:
			return "mid"
		KIND_GATE:
			return "gate"
		_:
			push_error("CastleTower.kind_name: unknown kind %d" % kind)
			return "?"
