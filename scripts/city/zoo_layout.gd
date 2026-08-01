## Planned geometry for a Monster Zoo district (district-local voxel coords).
##
## Survives the composer so the runtime can run the forever war: it holds the containment
## ring, the visitor gate, and the ~40 dice-rolled faction territories with their spawn
## pads and their coarse ownership grid.
##
## Territories are parallel arrays rather than a nested class: every consumer walks them by
## index (census, spawn timers, plate lookups), and an index is the identity the ownership
## grid stores anyway.
class_name ZooLayout
extends RefCounted

## Outer footprint of the containment ring, fence posts included.
var fence_rect: Rect2i = Rect2i()
## Walkable battlefield inside the ring (inclusive min, exclusive end in XZ).
var field_rect: Rect2i = Rect2i()
## Top solid Y of the field floor. Air starts at `deck_y + 1`.
var deck_y: int = 0
## Top solid Y of the fence posts.
var fence_top_y: int = 0
## The one opening in the ring, in district-local XZ.
var gate_rect: Rect2i = Rect2i()
## Unit step pointing from the gate into the field.
var gate_dir: Vector2i = Vector2i(0, 1)
## Plate-free visitor apron just inside the gate.
var plaza_rect: Rect2i = Rect2i()
## Where the cloak gate interactable stands (x, floor Y, z). `x` is -1 on an unbuilt zoo.
var cloak_gate_vox: Vector3i = Vector3i(-1, 0, -1)

## Territory seeds in district-local XZ, one per dice-rolled cell.
var seed_xz: Array[Vector2i] = []
## MonsterFaction.Id that owns each seed, same order as `seed_xz`.
var seed_faction: PackedInt32Array = PackedInt32Array()
## Spawn pad centre for each seed (x, floor Y, z).
var spawner_vox: Array[Vector3i] = []
## Roof peaks of summon stations and battlefield gazebos (x, peak Y, z) — recipe sites.
var gazebo_roof_vox: Array[Vector3i] = []
## Nominal reach of one territory in voxels — the plate density falloff radius.
var seed_radius_vox: int = 0

## Coarse ownership grid: cell pitch in voxels, and the grid origin / extent in cells.
var owner_cell_vox: int = 4
var owner_origin: Vector2i = Vector2i.ZERO
var owner_size: Vector2i = Vector2i.ZERO
## Cell → territory index, row-major over `owner_size`. -1 where no seed reaches.
var ownership: PackedInt32Array = PackedInt32Array()


func territory_count() -> int:
	return seed_xz.size()


## Territory index owning a district-local XZ voxel, or -1 outside the graded field.
func territory_at_local(x: int, z: int) -> int:
	if owner_size.x <= 0 or owner_size.y <= 0:
		return -1
	var cx := (x - owner_origin.x) / owner_cell_vox
	var cz := (z - owner_origin.y) / owner_cell_vox
	if x < owner_origin.x or z < owner_origin.y:
		return -1
	if cx < 0 or cz < 0 or cx >= owner_size.x or cz >= owner_size.y:
		return -1
	return ownership[cz * owner_size.x + cx]


## MonsterFaction.Id owning a district-local XZ voxel, or -1 where nothing does.
func faction_at_local(x: int, z: int) -> int:
	var t := territory_at_local(x, z)
	if t < 0:
		return -1
	return seed_faction[t]


## Territory index owning a *world* voxel column, or -1.
func territory_at_world(world_x: int, world_z: int, district_origin: Vector3i) -> int:
	return territory_at_local(world_x - district_origin.x, world_z - district_origin.z)


## World-space centre of one spawn pad, standing height above the pad surface.
func spawner_world(index: int, district_origin: Vector3i, voxel_size: float) -> Vector3:
	if index < 0 or index >= spawner_vox.size():
		push_error("ZooLayout.spawner_world: no spawner %d" % index)
		assert(false, "ZooLayout: bad spawner index")
		return Vector3.ZERO
	var pad := spawner_vox[index]
	return Vector3(
		(float(district_origin.x + pad.x) + 0.5) * voxel_size,
		float(district_origin.y + pad.y + 1) * voxel_size,
		(float(district_origin.z + pad.z) + 0.5) * voxel_size
	)


func describe() -> String:
	return (
		"zoo fence=%s field=%s deck_y=%d gate=%s territories=%d gazebo_roofs=%d seed_r=%d grid=%s"
		% [
			fence_rect,
			field_rect,
			deck_y,
			gate_rect,
			territory_count(),
			gazebo_roof_vox.size(),
			seed_radius_vox,
			owner_size,
		]
	)
