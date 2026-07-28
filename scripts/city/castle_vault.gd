## One chamber of the castle dungeon, in district-local voxel coordinates.
##
## A vault is floored on `level` and reaches up through `span_levels` of the band, so an
## ordinary cell and a two- or three-level vaulted hall are the same record with a different
## height. The levels a tall vault passes through carry no floor over its footprint, which is
## why the whole plan exists before the first slab is cast: a hall made by demolishing slabs
## afterwards leaves orphaned fragments hanging in its own air.
class_name CastleVault
extends RefCounted

## Narrowest span that still reads as a hall rather than a room, and the widest that reads as
## a cell. The gap between them is deliberate: a chamber may be neither.
const WIDE_MIN := 20
const SMALL_MAX := 12

var rect: Rect2i = Rect2i()
## Dungeon level the floor belongs to. 0 is the deepest.
var level: int = 0
## Walking surface: Y of the topmost solid floor voxel.
var floor_y: int = 0
## Clear voxels above `floor_y`.
var air_h: int = 0
## Levels the chamber occupies. 1 for an ordinary vault.
var span_levels: int = 1
## Index into `CastleLayout.dungeon_bays` of the bay the vault was cut from.
var bay: int = -1


func is_tall() -> bool:
	return span_levels > 1


## Highest clear voxel of the chamber.
func top_y() -> int:
	return floor_y + air_h


func narrow_span() -> int:
	return mini(rect.size.x, rect.size.y)


func is_wide() -> bool:
	return narrow_span() >= WIDE_MIN


func is_small() -> bool:
	return narrow_span() <= SMALL_MAX


func matches(other: CastleVault) -> bool:
	if other == null:
		return false
	return (
		rect == other.rect
		and level == other.level
		and floor_y == other.floor_y
		and air_h == other.air_h
		and span_levels == other.span_levels
		and bay == other.bay
	)


func describe() -> String:
	return "vault L%d %s y=%d air=%d span=%d bay=%d" % [
		level, rect, floor_y, air_h, span_levels, bay
	]
