## Voxel cells a standing structure holds against damage, keyed by whoever is standing.
##
## This is deliberately *not* `VoxelMaterial.hardness`. Hardness is a property of a material: bedrock
## never yields no matter where it sits, and the stone in a wall is carveable wherever that wall is.
## A siege tower is built out of the same ordinary stone, brick and lit glass as the city around it —
## what must not yield is *that tower, while it stands*, because its hit points are the only way it is
## meant to come down. Without this, a stray blast or a monster's bolt digs the footing out from under
## a live turret and leaves it firing from inside a hole, with two health models disagreeing about
## whether the thing exists.
##
## Ownership is by instance id, so the claim dies with the structure: once released the cells are
## ordinary again and whatever rubble is left can be cleared like any other.
##
## Cells are world voxel coordinates — the same space `CityBrush.get_vox` and the player's carve
## verdict work in. Small by construction (a tower stamp is tens of cells), so a plain hash of cells
## is cheaper than any box test and needs no assumption that a structure is convex.
class_name VoxelWard
extends RefCounted

## World voxel → owner instance id. One dictionary is enough: releases are rare (a tower dying)
## and a claim is tens of cells, so scanning it beats keeping a second index in step.
var _owner_of: Dictionary[Vector3i, int] = {}


## Hold `cells` for `owner_id` until it is released. Re-claiming an owner adds to what it holds.
func claim(owner_id: int, cells: Array[Vector3i]) -> void:
	if owner_id == 0:
		push_error("VoxelWard.claim: 0 is not an owner id")
		return
	if cells.is_empty():
		push_error("VoxelWard.claim: owner %d claimed nothing" % owner_id)
		return
	for vox: Vector3i in cells:
		var held := int(_owner_of.get(vox, 0))
		if held != 0 and held != owner_id:
			push_error(
				"VoxelWard.claim: %v is already held by %d, owner %d cannot have it"
				% [vox, held, owner_id]
			)
			continue
		_owner_of[vox] = owner_id


## Drop everything `owner_id` holds. Returns how many cells went back to being ordinary.
func release(owner_id: int) -> int:
	var dropped: Array[Vector3i] = []
	for vox: Vector3i in _owner_of:
		if _owner_of[vox] == owner_id:
			dropped.append(vox)
	for vox: Vector3i in dropped:
		_owner_of.erase(vox)
	return dropped.size()


func clear() -> void:
	_owner_of.clear()


## True when damage must leave this cell alone.
func holds(vox: Vector3i) -> bool:
	return _owner_of.has(vox)


## True when some structure holds a cell over `(x, z)` above height `y`.
##
## For the structural cascade, which drops everything standing over a carved cell. Blasting the plate
## under a tower must not bring the tower down with it: its hit points are the only way it falls, and
## a collapse here would take the very cells the carve was refused on.
func holds_above(x: int, z: int, y: int) -> bool:
	for vox: Vector3i in _owner_of:
		if vox.x == x and vox.z == z and vox.y > y:
			return true
	return false


## Instance id of the structure holding `vox`, or 0 when the cell is ordinary.
func owner_of(vox: Vector3i) -> int:
	return int(_owner_of.get(vox, 0))


func cell_count() -> int:
	return _owner_of.size()
