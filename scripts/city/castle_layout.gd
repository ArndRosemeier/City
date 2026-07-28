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

## Voxel band the dungeon is carved into, inclusive.
var dungeon_y0: int = 0
var dungeon_y1: int = 0
## Levels stacked inside the band, and the pitch of one: its slab plus the air above it.
var dungeon_levels: int = 0
var dungeon_level_h: int = 0
var dungeon_slab_thick: int = 0
## Outer face of the substructure, and the area its chambers are cut in. The plate is the
## curtain's own footprint, so a corner tower stands on a plate corner and a flight can drop
## out of its base straight into the dungeon.
var dungeon_rect: Rect2i = Rect2i()
var dungeon_plate_rect: Rect2i = Rect2i()
## Cross-wall bays. Shared by every level, the way a real substructure's cross walls carry
## down, which is also what lets a chamber reach up through the level above it.
var dungeon_bays: Array[Rect2i] = []
## The grain the bays and the per-level partitions were rolled at, kept because it is what a
## seed comparison is actually measuring.
var dungeon_bay_min: int = 0
var dungeon_room_min: int = 0
## Every chamber on every level, in plan order.
var dungeon_vaults: Array[CastleVault] = []
var dungeon_doorways: Array[CastleDoorway] = []
## Flights between two dungeon levels. `from_storey`/`to_storey` are level indices here.
var dungeon_stairs: Array[CastleStair] = []
var dungeon_entries: Array[CastleDungeonEntry] = []

## Cardinal direction the gate faces, chosen so it looks at a road stub.
var gate_dir: Vector2i = Vector2i.ZERO
## Centre of the gate passage at the threshold (Y = courtyard_y + 1).
var gate_center: Vector2i = Vector2i.ZERO
var gate_width: int = 0
## Clear height of the passage at its centre line.
var gate_height: int = 0
var gatehouse_rect: Rect2i = Rect2i()
## The gate passage as a doorway record, so the most prominent door on the fortress is the
## same kind of thing as the keep's and the dungeon's rather than a special case. It covers
## the curtain's own thickness; the gatehouse passage carries on either side of it.
var gate_doorway: CastleDoorway = null

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


## Deepest level is 0, so the topmost one sits immediately under the courtyard slab.
func dungeon_top_level() -> int:
	assert(dungeon_levels > 0)
	return dungeon_levels - 1


## Walking surface of a dungeon level: Y of the topmost solid voxel of its slab.
func dungeon_floor_y(level: int) -> int:
	assert(level >= 0 and level < dungeon_levels)
	return dungeon_y0 + dungeon_slab_thick - 1 + level * dungeon_level_h


## Chambers floored on one level. A tall vault belongs to the level it stands on; the levels
## it reaches up through have no floor over it at all.
func dungeon_vaults_on(level: int) -> Array[CastleVault]:
	var out: Array[CastleVault] = []
	for v: CastleVault in dungeon_vaults:
		if v.level == level:
			out.append(v)
	return out


func dungeon_doorways_on(level: int) -> Array[CastleDoorway]:
	var out: Array[CastleDoorway] = []
	for d: CastleDoorway in dungeon_doorways:
		if d.storey == level:
			out.append(d)
	return out


## Every opening in the fortress that carries a door, gate first. One list, because a door
## placer and the checks that measure the doors both want all three tiers at once.
func doorways() -> Array[CastleDoorway]:
	var out: Array[CastleDoorway] = []
	if gate_doorway != null:
		out.append(gate_doorway)
	if keep_entrance != null:
		out.append(keep_entrance)
	out.append_array(keep_doorways)
	out.append_array(dungeon_doorways)
	return out


func doorway_link_count(link: int) -> int:
	var n := 0
	for d: CastleDoorway in doorways():
		if d.link == link:
			n += 1
	return n


func dungeon_tall_count() -> int:
	var n := 0
	for v: CastleVault in dungeon_vaults:
		if v.is_tall():
			n += 1
	return n


func dungeon_wide_count() -> int:
	var n := 0
	for v: CastleVault in dungeon_vaults:
		if v.is_wide():
			n += 1
	return n


func dungeon_small_count() -> int:
	var n := 0
	for v: CastleVault in dungeon_vaults:
		if v.is_small():
			n += 1
	return n


## Bit per CastleDungeonEntry kind present, so a seed's entrance mix is one comparable number.
func dungeon_entry_mask() -> int:
	var mask := 0
	for e: CastleDungeonEntry in dungeon_entries:
		mask |= 1 << e.kind
	return mask


func dungeon_entry_names() -> String:
	var parts: Array[String] = []
	for e: CastleDungeonEntry in dungeon_entries:
		parts.append(e.kind_name())
	return "+".join(parts)


func dungeon_entry_of(kind: int) -> CastleDungeonEntry:
	for e: CastleDungeonEntry in dungeon_entries:
		if e.kind == kind:
			return e
	return null


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
		or dungeon_vaults.size() != other.dungeon_vaults.size()
		or dungeon_doorways.size() != other.dungeon_doorways.size()
		or dungeon_stairs.size() != other.dungeon_stairs.size()
		or dungeon_entries.size() != other.dungeon_entries.size()
	):
		return false
	for i in range(dungeon_vaults.size()):
		if not (dungeon_vaults[i] as CastleVault).matches(other.dungeon_vaults[i]):
			return false
	for i in range(dungeon_doorways.size()):
		if not (dungeon_doorways[i] as CastleDoorway).matches(other.dungeon_doorways[i]):
			return false
	for i in range(dungeon_stairs.size()):
		if not (dungeon_stairs[i] as CastleStair).matches(other.dungeon_stairs[i]):
			return false
	for i in range(dungeon_entries.size()):
		if not (dungeon_entries[i] as CastleDungeonEntry).matches(other.dungeon_entries[i]):
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
	if not gate_doorway.matches(other.gate_doorway):
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
		and dungeon_y0 == other.dungeon_y0
		and dungeon_y1 == other.dungeon_y1
		and dungeon_levels == other.dungeon_levels
		and dungeon_level_h == other.dungeon_level_h
		and dungeon_slab_thick == other.dungeon_slab_thick
		and dungeon_rect == other.dungeon_rect
		and dungeon_plate_rect == other.dungeon_plate_rect
		and dungeon_bays == other.dungeon_bays
		and dungeon_bay_min == other.dungeon_bay_min
		and dungeon_room_min == other.dungeon_room_min
	)


func describe() -> String:
	return (
		(
			"castle plateau=%s wall=%s inset=%d thick=%d h=%d courtyard_y=%d"
			+ " gate=%s dir=%s %dx%d towers=%d (corner=%d mid=%d gate=%d) top=%d"
			+ " causeway run=%d width=%d keep=%s"
			+ " storeys=%d hall=%d roof=%d rooms=%d doors=%d flights=%d"
			+ " leaves=%d (tree=%d loop=%d) | %s"
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
			keep_floors.size(),
			keep_hall_storey,
			keep_roof_y,
			keep_room_count(),
			keep_doorways.size(),
			keep_stairs.size(),
			doorways().size(),
			doorway_link_count(CastleDoorway.LINK_TREE),
			doorway_link_count(CastleDoorway.LINK_LOOP),
			dungeon_describe(),
		]
	)


## The numbers a seed comparison reads: what makes one dungeon a different place from the
## next rather than the same plan with the walls moved.
func dungeon_describe() -> String:
	var per_level: Array[String] = []
	for l in range(dungeon_levels):
		per_level.append("%d" % dungeon_vaults_on(l).size())
	return (
		(
			"dungeon Y%d..%d %d levels plate=%s bays=%d(min=%d) rooms=%d [%s]"
			+ " wide=%d small=%d tall=%d flights=%d entries=%s"
		)
		% [
			dungeon_y0,
			dungeon_y1,
			dungeon_levels,
			dungeon_plate_rect,
			dungeon_bays.size(),
			dungeon_bay_min,
			dungeon_vaults.size(),
			"/".join(per_level),
			dungeon_wide_count(),
			dungeon_small_count(),
			dungeon_tall_count(),
			dungeon_stairs.size(),
			dungeon_entry_names(),
		]
	)


## Rooms across every storey. The hall counts once, on the storey that owns it.
func keep_room_count() -> int:
	var n := 0
	for f: CastleFloor in keep_floors:
		n += f.rooms.size()
	return n
