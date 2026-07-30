## One laid-out garden plot of a castle: where it is, what was planted there, and the
## ground it stands on.
##
## Planned with the rest of the fortress so the tests can read the plots instead of hunting
## for hedges in the voxels, and so a re-bake of the same seed puts the same gardens in the
## same places.
class_name CastleGarden
extends RefCounted

## Meadow parterres and the orchard sit outside the moat; the privy garden is inside the
## bailey, on the flags.
const KIND_MEADOW := 0
const KIND_ORCHARD := 1
const KIND_PRIVY := 2

## District-local voxel footprint.
var rect: Rect2i = Rect2i()
## Topmost solid voxel of the ground it was laid out on.
var surface_y: int = 0
var style: GardenComposer.Style = GardenComposer.Style.PARTERRE
var kind: int = KIND_MEADOW


func kind_name() -> String:
	match kind:
		KIND_MEADOW:
			return "meadow"
		KIND_ORCHARD:
			return "orchard"
		KIND_PRIVY:
			return "privy"
		_:
			push_error("CastleGarden.kind_name: unknown kind %d" % kind)
			return "?"


func matches(other: CastleGarden) -> bool:
	if other == null:
		return false
	return (
		rect == other.rect
		and surface_y == other.surface_y
		and style == other.style
		and kind == other.kind
	)


func describe() -> String:
	return "%s %s %s@%d" % [kind_name(), GardenComposer.style_name(style), rect, surface_y]
