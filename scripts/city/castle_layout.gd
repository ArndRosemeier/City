## Deterministic plan of one castle, in district-local voxel coordinates.
##
## CastleComposer plans the whole fortress before it writes a voxel, and DistrictGenerator
## keeps the plan after the bake (see `get_castle_layout()`). Tests read the plan instead of
## reverse-engineering the geometry, and Phase 2/3 get the keep footprint and the dungeon
## band without having to re-derive either from the voxels.
class_name CastleLayout
extends RefCounted

## Footprint of the battered plinth where it meets the street deck.
var plinth_rect: Rect2i = Rect2i()
## Flat top of the plinth — the courtyard datum, wider than the curtain by `wall_inset`.
var plateau_rect: Rect2i = Rect2i()
## Outer face of the curtain wall.
var wall_rect: Rect2i = Rect2i()
var wall_inset: int = 0
var wall_thick: int = 0
## Curtain height above the courtyard surface, merlons excluded.
var wall_height: int = 0
## Open bailey inside the curtain.
var courtyard_rect: Rect2i = Rect2i()
## Walkable courtyard datum (Y of the topmost solid voxel).
var courtyard_y: int = 0
## A point in the bailey that is guaranteed clear of the reserved keep footprint.
var courtyard_center: Vector2i = Vector2i.ZERO
## Outer face of the keep.
var keep_rect: Rect2i = Rect2i()
## Inside face of the keep's outer wall — the area every storey is subdivided in.
var keep_plate_rect: Rect2i = Rect2i()
var keep_wall_thick: int = 0
## Voxels from one floor surface to the next: the slab plus the clear air above it.
var keep_level_h: int = 0
var keep_slab_thick: int = 0
## Lower storey of the double-height great hall. Storey `keep_hall_storey + 1` carries no
## slab of its own, so the hall is one room two storeys tall.
var keep_hall_storey: int = 0
## Y of the topmost solid roof voxel, merlons excluded.
var keep_roof_y: int = 0
## One entry per storey, in order.
var keep_floors: Array[CastleFloor] = []
var keep_doorways: Array[CastleDoorway] = []
## Keep flights, then the courtyard ramp to the curtain crown as the last entry.
var keep_stairs: Array[CastleStair] = []
var keep_entrance: CastleDoorway = null
var crown_stair: CastleStair = null
## Crown column the ramp arrives at, three voxels in from the curtain's outer face.
var crown_walk: Vector2i = Vector2i.ZERO

## Voxel band the Phase 3 dungeon carves into, inclusive.
var dungeon_y0: int = 0
var dungeon_y1: int = 0

## Cardinal direction the gate faces, chosen so it looks at a road stub.
var gate_dir: Vector2i = Vector2i.ZERO
## Centre of the gate passage at the threshold (Y = courtyard_y + 1).
var gate_center: Vector2i = Vector2i.ZERO
var gate_width: int = 0
## Clear height of the passage at its centre line.
var gate_height: int = 0
var gatehouse_rect: Rect2i = Rect2i()

## Half-width of the causeway deck, parapets included.
var causeway_hw: int = 0
## Horizontal run from the plateau edge down to the street deck.
var causeway_run: int = 0
## Centre line of the causeway from the street end up to the gate, one entry per station.
var causeway_line: Array[Vector2i] = []
## Road cell centre the approach track is aimed at.
var road_target: Vector2i = Vector2i.ZERO

var towers: Array[CastleTower] = []


func keep_storeys() -> int:
	return keep_floors.size()


func keep_top_storey() -> int:
	assert(not keep_floors.is_empty())
	return keep_floors.size() - 1


func keep_floor(storey: int) -> CastleFloor:
	assert(storey >= 0 and storey < keep_floors.size())
	return keep_floors[storey]


## Y of a storey's walking surface, whether or not it carries a slab of its own.
func keep_floor_y(storey: int) -> int:
	return courtyard_y + storey * keep_level_h


## Doorways cut on one storey.
func keep_doorways_on(storey: int) -> Array[CastleDoorway]:
	var out: Array[CastleDoorway] = []
	for d: CastleDoorway in keep_doorways:
		if d.storey == storey:
			out.append(d)
	return out


func tower_count(kind: int) -> int:
	var n := 0
	for t: CastleTower in towers:
		if t.kind == kind:
			n += 1
	return n


func tallest_tower_y() -> int:
	var top := courtyard_y
	for t: CastleTower in towers:
		top = maxi(top, t.top_y)
	return top


## Same-shape comparison used by the determinism check: every planned number, so a drifting
## RNG shows up as a failure rather than as a castle that merely looks similar.
func matches(other: CastleLayout) -> bool:
	if other == null:
		return false
	if (
		towers.size() != other.towers.size()
		or keep_floors.size() != other.keep_floors.size()
		or keep_doorways.size() != other.keep_doorways.size()
		or keep_stairs.size() != other.keep_stairs.size()
	):
		return false
	for i in range(keep_floors.size()):
		if not (keep_floors[i] as CastleFloor).matches(other.keep_floors[i]):
			return false
	for i in range(keep_doorways.size()):
		if not (keep_doorways[i] as CastleDoorway).matches(other.keep_doorways[i]):
			return false
	for i in range(keep_stairs.size()):
		if not (keep_stairs[i] as CastleStair).matches(other.keep_stairs[i]):
			return false
	if not keep_entrance.matches(other.keep_entrance):
		return false
	if not crown_stair.matches(other.crown_stair):
		return false
	for i in range(towers.size()):
		var a: CastleTower = towers[i]
		var b: CastleTower = other.towers[i]
		if (
			a.center != b.center
			or a.radius != b.radius
			or a.top_y != b.top_y
			or a.round_plan != b.round_plan
			or a.kind != b.kind
		):
			return false
	return (
		plinth_rect == other.plinth_rect
		and plateau_rect == other.plateau_rect
		and wall_rect == other.wall_rect
		and wall_inset == other.wall_inset
		and wall_thick == other.wall_thick
		and wall_height == other.wall_height
		and courtyard_rect == other.courtyard_rect
		and courtyard_y == other.courtyard_y
		and courtyard_center == other.courtyard_center
		and keep_rect == other.keep_rect
		and keep_plate_rect == other.keep_plate_rect
		and keep_wall_thick == other.keep_wall_thick
		and keep_level_h == other.keep_level_h
		and keep_slab_thick == other.keep_slab_thick
		and keep_hall_storey == other.keep_hall_storey
		and keep_roof_y == other.keep_roof_y
		and crown_walk == other.crown_walk
		and gate_dir == other.gate_dir
		and gate_center == other.gate_center
		and gate_width == other.gate_width
		and gate_height == other.gate_height
		and gatehouse_rect == other.gatehouse_rect
		and causeway_hw == other.causeway_hw
		and causeway_run == other.causeway_run
		and causeway_line == other.causeway_line
		and road_target == other.road_target
	)


func describe() -> String:
	return (
		(
			"castle plateau=%s wall=%s inset=%d thick=%d h=%d courtyard_y=%d"
			+ " gate=%s dir=%s %dx%d towers=%d (corner=%d mid=%d gate=%d) top=%d"
			+ " causeway run=%d width=%d keep=%s dungeon=Y%d..%d"
			+ " storeys=%d hall=%d roof=%d rooms=%d doors=%d flights=%d"
		)
		% [
			plateau_rect,
			wall_rect,
			wall_inset,
			wall_thick,
			wall_height,
			courtyard_y,
			gate_center,
			gate_dir,
			gate_width,
			gate_height,
			towers.size(),
			tower_count(CastleTower.KIND_CORNER),
			tower_count(CastleTower.KIND_MID),
			tower_count(CastleTower.KIND_GATE),
			tallest_tower_y(),
			causeway_run,
			causeway_hw * 2 + 1,
			keep_rect,
			dungeon_y0,
			dungeon_y1,
			keep_floors.size(),
			keep_hall_storey,
			keep_roof_y,
			keep_room_count(),
			keep_doorways.size(),
			keep_stairs.size(),
		]
	)


## Rooms across every storey. The hall counts once, on the storey that owns it.
func keep_room_count() -> int:
	var n := 0
	for f: CastleFloor in keep_floors:
		n += f.rooms.size()
	return n
