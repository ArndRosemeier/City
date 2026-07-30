## One 1-cell-thick partition run of a FloorPlan, with the openings punched back out.
##
## Coordinates match whatever space the FloorPlanner was called in (world XZ voxels at
## runtime). `gaps` are sub-rects of `rect`.
class_name FloorPlanWall
extends RefCounted

var rect: Rect2i = Rect2i()
## VoxelMaterial id — glass for office partitions, brick for party walls, plaster inside.
var mat: int = 0
var gaps: Array[Rect2i] = []


func is_gap(p: Vector2i) -> bool:
	for g in gaps:
		if g.has_point(p):
			return true
	return false


static func make(p_rect: Rect2i, p_mat: int, p_gaps: Array[Rect2i]) -> FloorPlanWall:
	var w := FloorPlanWall.new()
	w.rect = p_rect
	w.mat = p_mat
	w.gaps = p_gaps
	return w
