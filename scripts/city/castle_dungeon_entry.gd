## One way down into the castle dungeon, in district-local voxel coordinates.
##
## Which routes a castle has is rolled per seed from the three the fortress can offer, and at
## least one is always present. That mix is the first thing that makes two castles feel
## different: one is entered through a hole in the keep's floor, the next through a trench in
## the open bailey, the next through a guardroom in a corner tower.
class_name CastleDungeonEntry
extends RefCounted

## A well through the keep's ground floor — which *is* the courtyard slab, so the flight cuts
## its own lane down through masonry the plinth cast solid.
const KIND_KEEP_CELLAR := 0
## A stepped trench in the open bailey, independent of the keep.
const KIND_COURTYARD := 1
## Down through a hollowed corner tower base, reached from the bailey by the wall-corner
## recess the tower shares with the curtain.
const KIND_TOWER_BASE := 2
const KIND_COUNT := 3

var kind: int = KIND_COURTYARD
## Climbs from the top dungeon level up to the courtyard datum, so `origin` is the bottom
## tread and `dir` points up and out. The treads are solid; the shaft over them is carved.
var stair: CastleStair = null
## Index into `CastleLayout.towers`, or -1 on the routes that use no tower.
var tower_index: int = -1
## The recess joining a hollowed tower base to the bailey. Empty on the other two routes.
var chamber_rect: Rect2i = Rect2i()
## Clear voxels over the tower base floor, 0 on the other two routes.
var chamber_air_h: int = 0


static func kind_name_of(k: int) -> String:
	match k:
		KIND_KEEP_CELLAR:
			return "keep-cellar"
		KIND_COURTYARD:
			return "courtyard"
		KIND_TOWER_BASE:
			return "tower-base"
		_:
			push_error("CastleDungeonEntry: unknown kind %d" % k)
			return "?"


func kind_name() -> String:
	return kind_name_of(kind)


## Column at the head of the flight, on the surface a body walks in from.
func head() -> Vector2i:
	return stair.center_column(stair.run_len() - 1)


## Column at the foot of the flight, on the top dungeon level's floor.
func foot() -> Vector2i:
	return stair.center_column(0)


func matches(other: CastleDungeonEntry) -> bool:
	if other == null:
		return false
	if not stair.matches(other.stair):
		return false
	return (
		kind == other.kind
		and tower_index == other.tower_index
		and chamber_rect == other.chamber_rect
		and chamber_air_h == other.chamber_air_h
	)


func describe() -> String:
	return "entry %s head=%s foot=%s tower=%d" % [
		kind_name(), head(), foot(), tower_index
	]
