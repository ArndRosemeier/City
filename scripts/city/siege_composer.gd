## Turns a block of ordinary city into besieged ground: a Lodestone in the grand plaza, tower
## foundation pads spread along the streets, and a barricade ring broken by a few gates.
##
## This composer is additive, unlike every other themed one. The others own an open reserve and
## sculpt it from nothing; this runs after `paint_tile` has already laid the roads, sidewalks and
## buildings, and only adds to what is there. That is the whole point of the theme — the streets
## the horde walks are real streets, so the fight geometry is the city's own.
class_name SiegeComposer
extends RefCounted

## Lodestone: a crystal mass on a stone plinth, tall enough to be the thing you navigate by.
const LODESTONE_RADIUS := 5
const LODESTONE_HEIGHT := 16
## Nothing may be built inside this many voxels of the Lodestone centre — it needs its own square.
const LODESTONE_CLEAR := 12

## A foundation pad is this many voxels either side of its centre, so 5 × 5 (2.5 m).
const PAD_HALF := 2
## How many street pads to aim for. Enough to cover two or three approaches without turning the
## quarter into a shooting gallery.
const PAD_TARGET := 12
## Pads are hunted for on this cell stride, which is what spreads them over the whole quarter
## instead of clustering them wherever the scan started.
const PAD_CELL_STRIDE := 2
## Keep pads off each other so two towers never share a firing position.
const PAD_SPACING := 10

## Barricade courses above the deck. Five voxels is 2.5 m: too tall for anything on the ground to
## step over, and irrelevant to a player who jumps 10 m.
const BARRICADE_H := 5
## Barricade depth into the quarter, in voxels.
const BARRICADE_T := 2

## Breach gates, which is also how many approaches the defence has to cover.
const GATE_MIN := 2
const GATE_MAX := 3
## Half-width of a gate mouth in voxels, measured from the road cell centre.
const GATE_HALF_W := 7

## Mirrors `CityWalker.jump_height_max_m`. A roof within this is a ROOF_JUMP pad and anything
## higher is ROOF_HIGH, which wants a cloudstone. `test_siege_district` asserts the two agree, so
## retuning the player's jump cannot quietly put every roof pad out of reach.
const PLAYER_JUMP_M := 10.0
## Tallest roof that may carry a pad, in voxels over the deck. This also sets how tall the
## quarter's editable box has to be in `DistrictGenerator.open_space_bounds` — a pad written above
## that box is silently dropped on the streamed path.
const ROOF_PAD_MAX_VOX := 60
## Roof pads to aim for, on top of the street ones.
const ROOF_PAD_TARGET := 6

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1
var planner: DistrictPlanner
var cell_size: int = 28
## Metres per voxel, so the jump reach above can be compared against voxel heights.
var voxel_size: float = 0.5
## Filled by `compose`, then read by the generator and handed to the runtime controller.
var layout: SiegeLayout = null


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if brush == null or rng == null or planner == null:
		push_error("SiegeComposer.compose: brush, rng and planner are all required")
		assert(false, "SiegeComposer: not configured")
		return
	var quarter := planner.siege_quarter
	if quarter.size.x <= 0 or quarter.size.y <= 0:
		push_error("SiegeComposer.compose: the planner reserved no siege quarter")
		assert(false, "SiegeComposer: empty quarter")
		return

	layout = SiegeLayout.new()
	layout.quarter_cells = quarter
	layout.quarter_vox = Rect2i(
		min_v.x, min_v.z, max_v.x - min_v.x, max_v.z - min_v.z
	)
	layout.deck_y = ground_y

	_plan_lodestone()
	_plan_gates()
	## Street pads first so they win the spacing contest — a defence has to be mountable from the
	## ground before roofs become an upgrade.
	_plan_street_pads()
	_plan_roof_pads()

	_paint_lodestone()
	_paint_barricades()
	_paint_pads()

	if not layout.is_valid():
		push_error(
			"SiegeComposer.compose: unusable siege plan — %s" % layout.describe()
		)
		assert(false, "SiegeComposer: siege plan has no objective, gates or pads")
		return
	print("SiegeComposer: %s" % layout.describe())


# --- planning ---------------------------------------------------------------

func _plan_lodestone() -> void:
	## The grand plaza is where the urban pass already cleared a square, so the objective stands
	## in the open instead of wedged between facades.
	var plaza := planner.grand_plaza
	if plaza.size.x <= 0 or plaza.size.y <= 0:
		push_error("SiegeComposer: no grand plaza to stand the Lodestone in")
		assert(false, "SiegeComposer: siege without a grand plaza")
		return
	var centre_cell := plaza.position + plaza.size / 2
	layout.lodestone_xz = Vector2i(
		centre_cell.x * cell_size + cell_size / 2,
		centre_cell.y * cell_size + cell_size / 2
	)
	layout.lodestone_base_y = ground_y
	layout.lodestone_radius_vox = LODESTONE_RADIUS
	layout.lodestone_height_vox = LODESTONE_HEIGHT


## Breach gates on roads that cross the quarter boundary, at most one per side, two or three in
## total. Everything else on the perimeter gets walled, so these are the only ways in.
func _plan_gates() -> void:
	var q := layout.quarter_cells
	var x0 := q.position.x
	var z0 := q.position.y
	var x1 := q.position.x + q.size.x - 1
	var z1 := q.position.y + q.size.y - 1

	## Road cells on each edge, by side: 0 = -Z, 1 = +Z, 2 = -X, 3 = +X.
	var north: Array[Vector2i] = []
	var south: Array[Vector2i] = []
	var west: Array[Vector2i] = []
	var east: Array[Vector2i] = []
	for cx in range(x0, x1 + 1):
		if planner.has_road_cell(cx, z0):
			north.append(Vector2i(cx, z0))
		if planner.has_road_cell(cx, z1):
			south.append(Vector2i(cx, z1))
	for cz in range(z0, z1 + 1):
		if planner.has_road_cell(x0, cz):
			west.append(Vector2i(x0, cz))
		if planner.has_road_cell(x1, cz):
			east.append(Vector2i(x1, cz))

	var candidates: Array[int] = []
	if not north.is_empty():
		candidates.append(0)
	if not south.is_empty():
		candidates.append(1)
	if not west.is_empty():
		candidates.append(2)
	if not east.is_empty():
		candidates.append(3)
	if candidates.is_empty():
		push_error("SiegeComposer: no road crosses the quarter boundary, so there is no way in")
		assert(false, "SiegeComposer: siege quarter has no road access")
		return

	## Seeded shuffle — Array.shuffle() draws from the global RNG, which would make two bakes of
	## the same tile disagree about where the gates are.
	for i in range(candidates.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var want := GATE_MIN + int(rng.randi() % (GATE_MAX - GATE_MIN + 1))
	var made := 0
	for side: int in candidates:
		if made >= want:
			break
		var cells: Array[Vector2i] = north
		if side == 1:
			cells = south
		elif side == 2:
			cells = west
		elif side == 3:
			cells = east
		var cell := cells[int(rng.randi() % cells.size())]
		layout.add_gate(_gate_mouth_for(side, cell), _inward_for(side))
		made += 1


func _inward_for(side: int) -> Vector2i:
	match side:
		0:
			return Vector2i(0, 1)
		1:
			return Vector2i(0, -1)
		2:
			return Vector2i(1, 0)
		3:
			return Vector2i(-1, 0)
	push_error("SiegeComposer._inward_for: %d is not a side" % side)
	assert(false, "SiegeComposer: bad side")
	return Vector2i.ZERO


## Mouth centre on the quarter boundary for a gate on `side` in `cell`.
func _gate_mouth_for(side: int, cell: Vector2i) -> Vector3i:
	var q := layout.quarter_vox
	var cx := cell.x * cell_size + cell_size / 2
	var cz := cell.y * cell_size + cell_size / 2
	match side:
		0:
			return Vector3i(cx, ground_y, q.position.y)
		1:
			return Vector3i(cx, ground_y, q.position.y + q.size.y - 1)
		2:
			return Vector3i(q.position.x, ground_y, cz)
		3:
			return Vector3i(q.position.x + q.size.x - 1, ground_y, cz)
	push_error("SiegeComposer._gate_mouth_for: %d is not a side" % side)
	assert(false, "SiegeComposer: bad side")
	return Vector3i.ZERO


## Street-level foundation pads, spread across the quarter on a coarse cell stride so they end up
## covering the approaches rather than piling into whichever corner got scanned first.
func _plan_street_pads() -> void:
	var q := layout.quarter_cells
	for cz in range(q.position.y, q.position.y + q.size.y, PAD_CELL_STRIDE):
		for cx in range(q.position.x, q.position.x + q.size.x, PAD_CELL_STRIDE):
			if layout.pad_count() >= PAD_TARGET:
				return
			var spot := _find_pad_ground_in_cell(cx, cz)
			if spot.x < 0:
				continue
			layout.add_pad(spot, SiegeLayout.PadKind.STREET)


## A buildable column inside one planner cell, or x = -1 when the cell offers none. Jittered off
## the cell centre so a row of pads does not read as a grid.
func _find_pad_ground_in_cell(cx: int, cz: int) -> Vector3i:
	var base_x := cx * cell_size + cell_size / 2
	var base_z := cz * cell_size + cell_size / 2
	var jitter := cell_size / 3
	for _attempt in range(6):
		var x := base_x + int(rng.randi_range(-jitter, jitter))
		var z := base_z + int(rng.randi_range(-jitter, jitter))
		if _is_pad_ground(x, z):
			return Vector3i(x, ground_y, z)
	return Vector3i(-1, 0, -1)


## True when a 5 × 5 pad can stand here: flat open deck, clear of the Lodestone square, clear of
## the gate mouths, clear of other pads, and off the carriageway so lanes stay walkable.
func _is_pad_ground(x: int, z: int) -> bool:
	var q := layout.quarter_vox
	if (
		x - PAD_HALF < q.position.x
		or x + PAD_HALF >= q.position.x + q.size.x
		or z - PAD_HALF < q.position.y
		or z + PAD_HALF >= q.position.y + q.size.y
	):
		return false
	if _flat_dist(x, z, layout.lodestone_xz.x, layout.lodestone_xz.y) < float(LODESTONE_CLEAR):
		return false
	for i in range(layout.gate_count()):
		var g := layout.gates[i]
		if _flat_dist(x, z, g.x, g.z) < float(GATE_HALF_W + PAD_HALF):
			return false
	for pad: Vector3i in layout.pads:
		if _flat_dist(x, z, pad.x, pad.z) < float(PAD_SPACING):
			return false
	for dz in range(-PAD_HALF, PAD_HALF + 1):
		for dx in range(-PAD_HALF, PAD_HALF + 1):
			if not _is_buildable_column(x + dx, z + dz):
				return false
	return true


## Roof pads: the best sightlines in the quarter, and the ones that cost the most to reach. Every
## cell is tried rather than a stride, because flat roofs wide enough to stand a tower on are much
## rarer than open pavement.
func _plan_roof_pads() -> void:
	var q := layout.quarter_cells
	var made := 0
	for cz in range(q.position.y, q.position.y + q.size.y):
		for cx in range(q.position.x, q.position.x + q.size.x):
			if made >= ROOF_PAD_TARGET:
				return
			var spot := _find_roof_pad_in_cell(cx, cz)
			if spot.x < 0:
				continue
			layout.add_pad(spot, _roof_kind_for(spot.y))
			made += 1


func _find_roof_pad_in_cell(cx: int, cz: int) -> Vector3i:
	var base_x := cx * cell_size + cell_size / 2
	var base_z := cz * cell_size + cell_size / 2
	var jitter := cell_size / 3
	for _attempt in range(6):
		var x := base_x + int(rng.randi_range(-jitter, jitter))
		var z := base_z + int(rng.randi_range(-jitter, jitter))
		var y := _roof_surface_y(x, z)
		if y < 0:
			continue
		if not _is_roof_pad_site(x, y, z):
			continue
		return Vector3i(x, y, z)
	return Vector3i(-1, 0, -1)


## Top solid voxel of this column above the deck, or -1 when there is no roof here. A column whose
## building carries on past the probe band is rejected rather than clamped: the voxel at the top of
## the band is inside the mass, not a surface anything could stand on.
func _roof_surface_y(x: int, z: int) -> int:
	var ceiling := ground_y + ROOF_PAD_MAX_VOX
	if brush.get_vox(Vector3i(x, ceiling, z)) != VoxelMaterial.AIR:
		return -1
	for y in range(ceiling - 1, ground_y, -1):
		if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
			return y
	return -1


## A roof site needs a flat 5 × 5 platform with clear air over all of it, which is also what rules
## out the sloped roof materials — a pitched roof is never level across the footprint.
func _is_roof_pad_site(x: int, y: int, z: int) -> bool:
	var q := layout.quarter_vox
	if (
		x - PAD_HALF < q.position.x
		or x + PAD_HALF >= q.position.x + q.size.x
		or z - PAD_HALF < q.position.y
		or z + PAD_HALF >= q.position.y + q.size.y
	):
		return false
	for pad: Vector3i in layout.pads:
		if _flat_dist(x, z, pad.x, pad.z) < float(PAD_SPACING):
			return false
	for dz in range(-PAD_HALF, PAD_HALF + 1):
		for dx in range(-PAD_HALF, PAD_HALF + 1):
			if brush.get_vox(Vector3i(x + dx, y, z + dz)) == VoxelMaterial.AIR:
				return false
			if brush.get_vox(Vector3i(x + dx, y + 1, z + dz)) != VoxelMaterial.AIR:
				return false
	return true


func _roof_kind_for(surface_y: int) -> SiegeLayout.PadKind:
	var reach_vox := int(PLAYER_JUMP_M / voxel_size)
	if surface_y - ground_y <= reach_vox:
		return SiegeLayout.PadKind.ROOF_JUMP
	return SiegeLayout.PadKind.ROOF_HIGH


## A column is buildable when the deck is its top solid voxel and the surface is something a
## foundation may sit on. Carriageway materials are absent from this list on purpose: a pad in the
## road would block the lane the horde is meant to walk down.
func _is_buildable_column(x: int, z: int) -> bool:
	if brush.get_vox(Vector3i(x, ground_y + 1, z)) != VoxelMaterial.AIR:
		return false
	var surface := brush.get_vox(Vector3i(x, ground_y, z))
	return (
		surface == VoxelMaterial.SIDEWALK
		or surface == VoxelMaterial.PLAZA
		or surface == VoxelMaterial.TILES
		or surface == VoxelMaterial.GRAVEL
		or surface == VoxelMaterial.PARK
		or surface == VoxelMaterial.DIRT
		or surface == VoxelMaterial.STONE
		or surface == VoxelMaterial.CONCRETE
	)


# --- painting ---------------------------------------------------------------

func _paint_lodestone() -> void:
	if layout.lodestone_xz.x < 0:
		return
	var cx := layout.lodestone_xz.x
	var cz := layout.lodestone_xz.y
	var base := layout.lodestone_base_y

	## Plinth one voxel proud of the crystal, so the mass reads as placed rather than grown.
	var plinth_r := LODESTONE_RADIUS + 1
	for dz in range(-plinth_r, plinth_r + 1):
		for dx in range(-plinth_r, plinth_r + 1):
			if _flat_dist(cx + dx, cz + dz, cx, cz) > float(plinth_r):
				continue
			brush.set_vox(Vector3i(cx + dx, base, cz + dz), VoxelMaterial.STONE)
			brush.set_vox(Vector3i(cx + dx, base + 1, cz + dz), VoxelMaterial.STONE)

	## Crystal: a tapered mass in lit glass. GEM_* materials would be collectible, which would let
	## the player mine the objective they are defending.
	for course in range(LODESTONE_HEIGHT):
		var t := float(course) / float(LODESTONE_HEIGHT)
		var radius := maxf(float(LODESTONE_RADIUS) * (1.0 - t * 0.85), 1.0)
		var y := base + 2 + course
		for dz in range(-LODESTONE_RADIUS, LODESTONE_RADIUS + 1):
			for dx in range(-LODESTONE_RADIUS, LODESTONE_RADIUS + 1):
				if _flat_dist(cx + dx, cz + dz, cx, cz) > radius:
					continue
				brush.set_vox(Vector3i(cx + dx, y, cz + dz), VoxelMaterial.GLASS_LIT)


## Wall the quarter perimeter everywhere the ground is open, leaving the gate mouths clear.
## Columns already sealed by a building are left alone — the city is part of the wall.
func _paint_barricades() -> void:
	var q := layout.quarter_vox
	var x0 := q.position.x
	var z0 := q.position.y
	var x1 := q.position.x + q.size.x - 1
	var z1 := q.position.y + q.size.y - 1
	for x in range(x0, x1 + 1):
		for t in range(BARRICADE_T):
			_raise_barricade(x, z0 + t)
			_raise_barricade(x, z1 - t)
	for z in range(z0, z1 + 1):
		for t in range(BARRICADE_T):
			_raise_barricade(x0 + t, z)
			_raise_barricade(x1 - t, z)


func _raise_barricade(x: int, z: int) -> void:
	if _inside_a_gate(x, z):
		return
	if brush.get_vox(Vector3i(x, ground_y + 1, z)) != VoxelMaterial.AIR:
		## A facade, a wall or a tree already holds this column.
		return
	if not VoxelMaterial.is_solid(brush.get_vox(Vector3i(x, ground_y, z))):
		return
	for course in range(BARRICADE_H):
		## Rubble reads better with two stones than one, and the alternation is positional so a
		## rebake of the same tile paints the same wall.
		var mat := VoxelMaterial.STONE if (x + z + course) % 3 != 0 else VoxelMaterial.CONCRETE
		brush.set_vox(Vector3i(x, ground_y + 1 + course, z), mat)


func _inside_a_gate(x: int, z: int) -> bool:
	for i in range(layout.gate_count()):
		var g := layout.gates[i]
		if _flat_dist(x, z, g.x, g.z) <= float(GATE_HALF_W):
			return true
	return false


func _paint_pads() -> void:
	for i in range(layout.pad_count()):
		var pad := layout.pads[i]
		for dz in range(-PAD_HALF, PAD_HALF + 1):
			for dx in range(-PAD_HALF, PAD_HALF + 1):
				brush.set_vox(
					Vector3i(pad.x + dx, pad.y, pad.z + dz), VoxelMaterial.METAL_PLATE
				)
		## Corner studs, so an empty pad is legible from across the street.
		var studs: Array[Vector2i] = [
			Vector2i(-PAD_HALF, -PAD_HALF),
			Vector2i(-PAD_HALF, PAD_HALF),
			Vector2i(PAD_HALF, -PAD_HALF),
			Vector2i(PAD_HALF, PAD_HALF),
		]
		for s: Vector2i in studs:
			brush.set_vox(
				Vector3i(pad.x + s.x, pad.y + 1, pad.z + s.y), VoxelMaterial.METAL
			)


func _flat_dist(ax: int, az: int, bx: int, bz: int) -> float:
	return Vector2(float(ax - bx), float(az - bz)).length()
