## A patch of incremental navigation rebuild: the district it belongs to and the
## sector-aligned column rectangle inside it that has to be rescanned.
##
## The rectangle is in *world* voxel space and inclusive on both ends. It is snapped to the
## nav sector grid because `NativeNavWorld.rebuild_region` rebuilds whole sectors: the
## material box handed to it must cover every column of every sector it touches, or the
## rescan would read the outside-the-box fallback and invent walls.
##
## The same class is both a *queued region*, which coalescing grows and `take_unit` drains,
## and one *rebuild unit*, which is what a frame pays for and what the staleness log keeps.
class_name NavDirtyRegion
extends RefCounted

## Self-preload so the static factory type-checks before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_dirty_region.gd")

## Nav sector edge in voxels. Mirrors `SECTOR` in native/city_voxel/src/nav.rs and
## `DistrictCoord.CELL_SIZE` — one planner cell, so sector borders line up with street
## topology and, district sizes being whole multiples of it, with district borders too.
## NavService pins it against DistrictCoord at configure time.
const SECTOR_VOX := 28

var coord: Vector2i = Vector2i.ZERO
var min_x: int = 0
var min_z: int = 0
## Inclusive.
var max_x: int = 0
var max_z: int = 0

## Filled by NavDirtyTracker.fill_materials just before the rebuild: the dense material
## box, its origin and size in world voxels, and the bytes per voxel of the type channel.
var materials: PackedByteArray = PackedByteArray()
var box_min: Vector3i = Vector3i.ZERO
var box_size: Vector3i = Vector3i.ZERO
var stride: int = 0

## Nav version the finished rebuild produced. 0 while the region is still queued.
var version: int = 0
## Sectors `rebuild_region` reported touching, for the profiler and the tests.
var sectors: int = 0

## Where the next rebuild unit starts, as sector offsets from (min_x, min_z). A region is
## drained a unit at a time so a frame can stop between two of them, and the cursor is how
## much of it is left to do.
var _unit_x: int = 0
var _unit_z: int = 0


## Snap a column rectangle out to the sector grid. `p_max_x` / `p_max_z` are inclusive.
static func from_columns(
	p_coord: Vector2i, p_min_x: int, p_min_z: int, p_max_x: int, p_max_z: int
) -> _Self:
	var out: _Self = _Self.new()
	out.coord = p_coord
	out.min_x = floor_to_sector(p_min_x)
	out.min_z = floor_to_sector(p_min_z)
	out.max_x = floor_to_sector(p_max_x) + SECTOR_VOX - 1
	out.max_z = floor_to_sector(p_max_z) + SECTOR_VOX - 1
	return out


static func floor_to_sector(v: int) -> int:
	return int(floor(float(v) / float(SECTOR_VOX))) * SECTOR_VOX


func sectors_x() -> int:
	return (max_x - min_x + 1) / SECTOR_VOX


func sectors_z() -> int:
	return (max_z - min_z + 1) / SECTOR_VOX


func sector_count() -> int:
	return sectors_x() * sectors_z()


func columns() -> int:
	return (max_x - min_x + 1) * (max_z - min_z + 1)


## Has this region got a rebuild unit left in it?
func has_units() -> bool:
	return _unit_z < sectors_z()


## Nothing of this region has been rebuilt yet, so it may still grow. A region already part
## way through draining must not: its cursor counts sectors from `min_x` / `min_z`, and
## moving those would renumber the sectors it has already done.
func is_untouched() -> bool:
	return _unit_x == 0 and _unit_z == 0


## Rebuild units left at `max_sectors` per unit, for the profiler and the tests.
func units_left(max_sectors: int) -> int:
	if max_sectors < 1:
		push_error("NavDirtyRegion.units_left: %d sectors is not a unit" % max_sectors)
		return 0
	var per_row := (sectors_x() + max_sectors - 1) / max_sectors
	var done := _unit_z * per_row + (_unit_x + max_sectors - 1) / max_sectors
	return per_row * sectors_z() - done


## Carve off the next rebuild unit: a run of at most `max_sectors` sectors along X inside
## one sector row, rows in order.
##
## A unit is always a rectangle because `rebuild_region` is told a *box* and rebuilds the
## sectors that box carries whole — a run that wrapped a row would have a bounding box
## covering sectors this unit was not budgeted for.
func take_unit(max_sectors: int) -> _Self:
	if max_sectors < 1:
		push_error("NavDirtyRegion.take_unit: %d sectors is not a unit" % max_sectors)
		return null
	if not has_units():
		push_error("NavDirtyRegion.take_unit: %s is already fully drained" % _to_string())
		return null
	var run := mini(max_sectors, sectors_x() - _unit_x)
	var out: _Self = _Self.new()
	out.coord = coord
	out.min_x = min_x + _unit_x * SECTOR_VOX
	out.min_z = min_z + _unit_z * SECTOR_VOX
	out.max_x = out.min_x + run * SECTOR_VOX - 1
	out.max_z = out.min_z + SECTOR_VOX - 1
	_unit_x += run
	if _unit_x >= sectors_x():
		_unit_x = 0
		_unit_z += 1
	return out


## Same district and close enough that one rebuild should cover both: overlapping, or
## within one sector of each other. Neighbours one sector apart still merge, because the
## rebuild's clearance pass already refreshes that ring.
func adjoins(other: _Self) -> bool:
	if other.coord != coord:
		return false
	return (
		other.min_x <= max_x + SECTOR_VOX
		and other.max_x >= min_x - SECTOR_VOX
		and other.min_z <= max_z + SECTOR_VOX
		and other.max_z >= min_z - SECTOR_VOX
	)


## Sector extent of the union with `other`, as (x, z).
func union_sectors(other: _Self) -> Vector2i:
	return Vector2i(
		(maxi(max_x, other.max_x) - mini(min_x, other.min_x) + 1) / SECTOR_VOX,
		(maxi(max_z, other.max_z) - mini(min_z, other.min_z) + 1) / SECTOR_VOX
	)


func absorb(other: _Self) -> void:
	if other.coord != coord:
		push_error(
			"NavDirtyRegion.absorb: district %s cannot absorb %s"
			% [str(coord), str(other.coord)]
		)
		return
	min_x = mini(min_x, other.min_x)
	min_z = mini(min_z, other.min_z)
	max_x = maxi(max_x, other.max_x)
	max_z = maxi(max_z, other.max_z)


## Does this rectangle, grown by `margin` voxels, overlap an XZ box? Used by the staleness
## check, where the box is one corridor segment.
func touches_xz(x0: float, z0: float, x1: float, z1: float, margin: int) -> bool:
	return (
		x0 <= float(max_x + margin)
		and x1 >= float(min_x - margin)
		and z0 <= float(max_z + margin)
		and z1 >= float(min_z - margin)
	)


## Release the material copy: one region holds megabytes and the staleness log keeps
## finished regions alive for a while.
func drop_materials() -> void:
	materials = PackedByteArray()
	box_size = Vector3i.ZERO
	stride = 0


func _to_string() -> String:
	return (
		"NavDirtyRegion(%s x %d..%d z %d..%d, %dx%d sectors)"
		% [str(coord), min_x, max_x, min_z, max_z, sectors_x(), sectors_z()]
	)
