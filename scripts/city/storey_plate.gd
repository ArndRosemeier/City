## One walkable storey of a lot shell, in *district-local* voxel coordinates.
##
## BuildingGrammar._fill_shell records these as it paints; DistrictGenerator turns them
## into world-space InteriorRoom records so the JIT decorator can subdivide every floor,
## not just the ground one.
class_name StoreyPlate
extends RefCounted

## Clear floor footprint (walls outside this rect).
var rect: Rect2i = Rect2i()
## Topmost solid floor voxel Y a body stands on.
var floor_y: int = 0
## Clear voxels above `floor_y`.
var air_h: int = 0


static func make(p_rect: Rect2i, p_floor_y: int, p_air_h: int) -> StoreyPlate:
	var p := StoreyPlate.new()
	p.rect = p_rect
	p.floor_y = p_floor_y
	p.air_h = p_air_h
	return p
