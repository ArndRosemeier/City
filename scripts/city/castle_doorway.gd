## One open doorway in the castle, in district-local voxel coordinates.
##
## Phases 2 and 3 left these as holes. Phase 4 hangs a door in each, so the record now carries
## the leaf as well as the masonry: the opening is a stepped arch, and a leaf sized to
## `width x height` does not fit the hole it is meant to fill. Everything a door needs to be
## built is derived here, off the numbers the carve itself uses, so a mesh door and the stone
## it hangs in cannot disagree.
class_name CastleDoorway
extends RefCounted

## Iron-banded double gate — the fortress gate and the keep's own front door.
const LEAF_GATE := 0
## Planked timber on iron ledgers — the keep's interior doorways.
const LEAF_DOOR := 1
## Barred grille — the dungeon's. Sight lines through a closed door are what makes a warren
## of cells read as a warren rather than as a corridor of blank slabs.
const LEAF_GRATE := 2

## An edge of the spanning tree its level's chambers were joined by: bar it and every room
## behind it is stranded. Nothing bars anything in the prototype, but which openings are
## load-bearing is far cheaper to record while the tree is being built than to reconstruct
## from a finished plan later.
const LINK_TREE := 0
## An opening past the tree, so a level loops instead of branching. Safe to bar.
const LINK_LOOP := 1

## Courses at the head of the opening the stepped arch draws in. `CastleComposer` cuts the
## arch from `row_half()`, so the profile a leaf is built to and the profile the masonry is
## cut to are the same one and cannot drift apart.
const ARCH_COURSES := 2

## Leaf thickness and the setback of its face from the reveal, in voxels. Both fit inside
## `depth`: the leaf lives *in* the masonry, so no part of the door narrows the hole a body
## walks through. This is the whole reason a five-column opening stays five columns wide.
const LEAF_T := 0.4
const LEAF_SETBACK := 0.35

## Iron standing off each face of a leaf: the ledgers, and the studs a gate carries over them.
## Named here rather than in the placer because they are what decides whether a closed door is
## really inside its reveal, and `LEAF_SETBACK` has to cover them.
const BAND_STANDOFF := 0.14
const STUD_STANDOFF := 0.09

## Voxels a leaf may reach out of its own opening at full swing.
##
## Geodesic clearance is zero in any column with a blocked neighbour, so every stair lane and
## every doorway in this fortress already keeps an apron this wide clear — it is
## `CastleComposer.LANE_MARGIN`, asserted equal in the test rather than derived here, because
## a constant that reaches across to the composer would close a cycle between the two files.
## A leaf that never swings past the apron can never be the thing that narrows a route.
const SWING_REACH := 3

## Leaves per opening. Always two: five columns is 2.5 m of opening, one leaf that size would
## be a barn door, and two halve how far the swing reaches into the room.
const LEAVES := 2

## Mid column of the opening, on the wall line it is cut through.
var center: Vector2i = Vector2i.ZERO
## Direction a body walks through the opening. Always cardinal.
var axis: Vector2i = Vector2i.ZERO
## Clear voxels across, measured perpendicular to `axis`. Odd, so `center` is the middle.
var width: int = 0
## Voxels of masonry the opening is cut through, along `axis`.
var depth: int = 0
## Keep storey (or dungeon level) the opening belongs to, and the surface it stands on.
var storey: int = 0
var floor_y: int = 0
## Clear voxels above `floor_y` on the centre line. The arch takes `arch_courses` of it back
## at the shoulders, so this is taller than the rectangle a leaf can fill.
var height: int = 0
## Which door hangs here.
var leaf: int = LEAF_DOOR
## Whether the opening is load-bearing for reachability.
var link: int = LINK_TREE
## Stepped arch courses (castle). City lot punches are rectangles — set to 0.
var arch_courses: int = ARCH_COURSES


## Axis the width is measured along.
func side() -> Vector2i:
	return Vector2i(-axis.y, axis.x)


## Every column the opening occupies, threshold to threshold.
func columns() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := side()
	var half := width / 2
	for d in range(depth):
		for t in range(-half, half + 1):
			out.append(center + axis * d + s * t)
	return out


## Half-width of the opening at `row` courses above `floor_y`, the stepped arch included.
## Negative above the crown, where the arch has closed over.
func row_half(row: int) -> int:
	return width / 2 - maxi(row - (height - arch_courses), 0)


## Courses at the foot of the opening that keep its full width: the clear rectangle a
## rectangular leaf would have to fit inside. The leaf this plan hangs is stepped to
## `row_half()` instead, so it fills the arch rather than sitting under it.
func clear_rows() -> int:
	return height - arch_courses


## Offset of the leaf's own mid-plane from `center`'s column centre, along `axis`, in voxels.
## The leaf hangs on the far face of the reveal and swings the way a body walks.
func hang_plane() -> float:
	return float(depth) - 0.5 - LEAF_SETBACK - LEAF_T * 0.5


## Half the thickest part of a leaf, the ironwork on both faces included.
func leaf_half_t() -> float:
	return LEAF_T * 0.5 + BAND_STANDOFF + STUD_STANDOFF


## How far one leaf reaches from its hinge, in voxels: half the opening, hinged at the jamb.
func leaf_reach() -> float:
	return float(width) * 0.5


## Angle a leaf opens to, in radians, capped so its tip stops at the clearance apron. A
## five-column opening swings the full quarter turn; a seven-column gate stands ajar instead,
## which is what a leaf that wide has to do to stay inside the apron.
func swing_angle() -> float:
	return asin(minf(1.0, float(SWING_REACH) / leaf_reach()))


## Voxels the open leaf's far corner reaches past the face of the masonry it hangs on. The
## leaf's own thickness counts: at a part-open angle the outer corner leads the tip.
func swing_out() -> float:
	var a := swing_angle()
	var tip := hang_plane() + leaf_reach() * sin(a) + leaf_half_t() * cos(a)
	return tip - (float(depth) - 0.5)


## Whether the closed leaf, ironwork and all, lies inside the masonry it is set into. If this
## is ever false the door is a thing sticking out of the wall, and — the failure that matters —
## a body walking the opening would clip it.
func leaf_is_recessed() -> bool:
	return (
		hang_plane() - leaf_half_t() >= -0.5
		and hang_plane() + leaf_half_t() <= float(depth) - 0.5
	)


func is_load_bearing() -> bool:
	return link == LINK_TREE


## Guard for anything that ever wants to lock or bar this opening. A tree edge strands every
## room behind it, and a stranded room is the failure this whole phase was written around, so
## it is refused loudly here rather than discovered by a route test three phases later.
func may_bar() -> bool:
	if link == LINK_TREE:
		push_error(
			"CastleDoorway: %s is a spanning-tree edge — barring it strands the rooms behind it"
			% describe()
		)
		return false
	return true


func leaf_name() -> String:
	match leaf:
		LEAF_GATE:
			return "gate"
		LEAF_DOOR:
			return "door"
		LEAF_GRATE:
			return "grate"
		_:
			push_error("CastleDoorway: unknown leaf %d" % leaf)
			return "?"


func link_name() -> String:
	match link:
		LINK_TREE:
			return "tree"
		LINK_LOOP:
			return "loop"
		_:
			push_error("CastleDoorway: unknown link %d" % link)
			return "?"


func matches(other: CastleDoorway) -> bool:
	if other == null:
		return false
	return (
		center == other.center
		and axis == other.axis
		and width == other.width
		and depth == other.depth
		and storey == other.storey
		and floor_y == other.floor_y
		and height == other.height
		and leaf == other.leaf
		and link == other.link
		and arch_courses == other.arch_courses
	)


func describe() -> String:
	return "door s%d %s dir=%s %dx%d %s/%s" % [
		storey, center, axis, width, height, leaf_name(), link_name()
	]
