## One room a FloorPlan cut out of a storey: clear footprint plus what it is for.
class_name FloorPlanRoom
extends RefCounted

## Clear floor footprint — partitions sit outside it, same as RoomVolume.rect.
var rect: Rect2i = Rect2i()
## `RoomDecorator.Purpose` value.
var purpose: int = 0


static func make(p_rect: Rect2i, p_purpose: int) -> FloorPlanRoom:
	var r := FloorPlanRoom.new()
	r.rect = p_rect
	r.purpose = p_purpose
	return r
