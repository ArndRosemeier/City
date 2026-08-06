## The apothecary on a vanilla city tile: which lot it is, and the tells that say so from
## the street.
##
## A lab is nothing but a normal building until the player walks in and shoots the vat, so
## the whole layer hangs off one deterministic question — "does this tile have a lab, and
## which cell is it" — answered here from the district seed alone. Stream time paints the
## exterior (sick panes + a sign over the door). The vat itself is stamped much later, when
## the interior decorator finally furnishes that ground-floor room, and both sides agree
## because they ask `lab_cell` rather than remembering anything.
class_name AlchemyLabSite
extends Node3D

## No lot chosen — a tile without a lab, which is most of them.
const NO_CELL := Vector2i(0x40000000, 0x40000000)

## Chance a vanilla tile hides one. Low on purpose: a lab on every corner is scenery, a lab
## every few blocks is a find.
const LAB_CHANCE := 0.34

## Ground-floor panes swapped to `LAB_WINDOW` at most. A whole shopfront reads better than
## one pane, but a lot wall ring can be long and the tell should stay a tell.
const MAX_PANES := 28

## Voxels of sign board across the door, and how far above its head it sits.
const SIGN_HALF_WIDTH := 1
const SIGN_RISE := 1

## World voxel of the sign board's middle, or `NO_CELL`-ish sentinel when nothing was painted.
var sign_vox: Vector3i = Vector3i(0x40000000, 0, 0x40000000)
## Lot cell this site marks, for the interior decorator to match against.
var lab_cell: Vector2i = NO_CELL
## Ground-storey footprint of the lab, so the decorator's room pick can be checked in tests.
var lot_rect: Rect2i = Rect2i()
var panes_painted: int = 0


## Themes that get labs: the ordinary urban five. Special tiles have their own content and
## siege tiles are already a fight.
static func is_vanilla_theme(theme_id: int) -> bool:
	if DistrictTheme.is_special_id(theme_id):
		return false
	return theme_id != DistrictTheme.SIEGE


## The lot this tile hides a lab in, or `NO_CELL`. Pure function of the district seed and
## the baked building set, so stream time and the JIT decorator never disagree.
static func lab_cell_for(dseed: int, theme_id: int, buildings: Dictionary) -> Vector2i:
	if not is_vanilla_theme(theme_id):
		return NO_CELL
	if buildings.is_empty():
		return NO_CELL
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dseed) ^ 0x1ABA1AB
	if rng.randf() >= LAB_CHANCE:
		return NO_CELL
	## Sorted so a Dictionary's insertion order cannot decide which lot it is.
	var cells: Array[Vector2i] = []
	for key: Vector2i in buildings.keys():
		var b := buildings[key] as BuildingInterior
		if b == null or b.storeys.is_empty():
			continue
		cells.append(key)
	if cells.is_empty():
		return NO_CELL
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return cells[rng.randi_range(0, cells.size() - 1)]


## Paint the street tells for `building`. Returns false when the lot has no facade glass and
## no doorway to hang a sign over — the tile then simply has no lab, because a lab the player
## cannot spot from outside is a trap rather than an invitation.
func setup(
	brush: CityBrush, cell: Vector2i, building: BuildingInterior, doorways: Array
) -> bool:
	if brush == null:
		push_error("AlchemyLabSite.setup: brush is null")
		return false
	if building == null or building.storeys.is_empty():
		push_error("AlchemyLabSite.setup: building has no storeys")
		return false
	lab_cell = cell
	lot_rect = building.lot_rect
	var ground := building.storeys[0]
	brush.begin_edit()
	panes_painted = _paint_panes(brush, ground)
	var signed := _paint_sign(brush, ground, doorways)
	brush.end_edit()
	if panes_painted == 0 and not signed:
		lab_cell = NO_CELL
		return false
	return true


## Sick green glass on the ground floor. Only existing panes are swapped: punching new
## windows into a facade the grammar did not put them in reads as damage, not as a shop.
func _paint_panes(brush: CityBrush, ground: InteriorRoom) -> int:
	var ring := lot_rect.grow(1)
	var painted := 0
	for y in range(ground.floor_y + 1, ground.floor_y + ground.air_h + 1):
		for x in range(ring.position.x, ring.end.x):
			for z in range(ring.position.y, ring.end.y):
				var on_ring := (
					x == ring.position.x or x == ring.end.x - 1
					or z == ring.position.y or z == ring.end.y - 1
				)
				if not on_ring:
					continue
				var v := Vector3i(x, y, z)
				var id := brush.get_vox(v)
				if id != VoxelMaterial.GLASS and id != VoxelMaterial.GLASS_LIT:
					continue
				brush.set_vox(v, VoxelMaterial.LAB_WINDOW)
				painted += 1
				if painted >= MAX_PANES:
					return painted
	return painted


## A board over the street door with one glowing pane in it — the apothecary's shingle.
func _paint_sign(brush: CityBrush, ground: InteriorRoom, doorways: Array) -> bool:
	var door := _street_door(ground, doorways)
	if door == null:
		return false
	var y := door.floor_y + door.height + SIGN_RISE
	var side := door.side()
	var painted := 0
	for t in range(-SIGN_HALF_WIDTH, SIGN_HALF_WIDTH + 1):
		var v := Vector3i(door.center.x + side.x * t, y, door.center.y + side.y * t)
		## Only dress masonry that is already there; a board floating in a window hole
		## would be the one thing on the street that looks generated.
		if brush.get_vox(v) == VoxelMaterial.AIR:
			continue
		brush.set_vox(v, VoxelMaterial.LAB_WINDOW if t == 0 else VoxelMaterial.TIMBER)
		painted += 1
		if t == 0:
			sign_vox = v
	return painted > 0


## The ground-floor doorway of this lot, if the bake cut one.
func _street_door(ground: InteriorRoom, doorways: Array) -> CastleDoorway:
	var ring := lot_rect.grow(1)
	for item: Variant in doorways:
		var d := item as CastleDoorway
		if d == null:
			continue
		if not ring.has_point(d.center):
			continue
		if d.floor_y < ground.floor_y - 1 or d.floor_y > ground.floor_y + 1:
			continue
		return d
	return null


func has_sign() -> bool:
	return sign_vox.x != 0x40000000


## World position of the shingle, for crows to gather on.
func sign_world(voxel_size: float) -> Vector3:
	if not has_sign():
		return Vector3.INF
	return Vector3(
		(float(sign_vox.x) + 0.5) * voxel_size,
		(float(sign_vox.y) + 0.5) * voxel_size,
		(float(sign_vox.z) + 0.5) * voxel_size
	)
