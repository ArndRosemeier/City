## Planning-grid cell tags for DistrictPlanner (not voxel material ids).
class_name LandUse
extends Object

const LOT := 0
const ROAD := 1
const AVENUE := 2
const PLAZA := 3
const PARK := 4
const CIVIC_LOT := 5
const CORE_LOT := 6
const MID_LOT := 7
const TOWN_LOT := 8
const COURTYARD_LOT := 9


static func is_road(tag: int) -> bool:
	return tag == ROAD or tag == AVENUE


static func is_lot(tag: int) -> bool:
	return (
		tag == LOT
		or tag == CIVIC_LOT
		or tag == CORE_LOT
		or tag == MID_LOT
		or tag == TOWN_LOT
		or tag == COURTYARD_LOT
	)
