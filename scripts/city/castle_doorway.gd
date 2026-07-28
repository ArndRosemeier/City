## One open doorway in the castle keep, in district-local voxel coordinates.
##
## Phase 2 leaves these as holes. Phase 4 hangs a door in each, so the plan records the
## opening rather than letting a later phase re-derive it by hunting for air in masonry.
class_name CastleDoorway
extends RefCounted

## Mid column of the opening, on the wall line it is cut through.
var center: Vector2i = Vector2i.ZERO
## Direction a body walks through the opening. Always cardinal.
var axis: Vector2i = Vector2i.ZERO
## Clear voxels across, measured perpendicular to `axis`. Odd, so `center` is the middle.
var width: int = 0
## Voxels of masonry the opening is cut through, along `axis`.
var depth: int = 0
## Keep storey the opening belongs to, and the walkable surface it stands on.
var storey: int = 0
var floor_y: int = 0
## Clear voxels above `floor_y`.
var height: int = 0


## Axis the width is measured along.
func side() -> Vector2i:
	return Vector2i(-axis.y, axis.x)


## Every column the opening occupies, threshold to threshold.
func columns() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := side()
	var half := width / 2
	for d in range(depth):
		for t in range(-half, half + 1):
			out.append(center + axis * d + s * t)
	return out


func matches(other: CastleDoorway) -> bool:
	if other == null:
		return false
	return (
		center == other.center
		and axis == other.axis
		and width == other.width
		and depth == other.depth
		and storey == other.storey
		and floor_y == other.floor_y
		and height == other.height
	)


func describe() -> String:
	return "door s%d %s dir=%s %dx%d" % [storey, center, axis, width, height]
