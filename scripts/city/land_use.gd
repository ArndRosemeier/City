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
## Open hillside reserve — no buildings; sculpted by HillComposer.
const HILL := 10
## Consecrated ground — no housing; sculpted by GraveyardComposer.
const GRAVEYARD := 11
## Open water reserve — no housing; sculpted by LakeComposer.
const LAKE := 12
## Fortress reserve — no housing; built by CastleComposer.
const CASTLE := 13
## Fractal plaza — no housing; glowing deck + Mandelbrot UI panels.
const FRACTAL := 14
## Colosseum reserve — no housing; built by ArenaComposer.
const ARENA := 15
## Monster Zoo reserve — no housing; fenced battlefield built by ZooComposer.
const ZOO := 16
## Gaming plaza reserve — no housing; built by GamingComposer.
const GAMING := 17
## Teleport chamber plot — exactly one per normal district. A building on a building plot, not
## an open reserve like the spectacle tags above, so it counts as a lot.
const TELEPORT_LOT := 18


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
		or tag == TELEPORT_LOT
	)


static func is_open_nature(tag: int) -> bool:
	return (
		tag == PARK
		or tag == HILL
		or tag == GRAVEYARD
		or tag == LAKE
		or tag == CASTLE
		or tag == FRACTAL
		or tag == ARENA
		or tag == ZOO
		or tag == GAMING
	)
