## Turns a block of ordinary city into besieged ground: a Lodestone in the grand plaza, four outer
## stones that shield it out toward the tile corners, eight hell gates beyond those, a dense field
## of tower foundations over every buildable surface, and a barricade ring broken by breaches.
##
## This composer is additive, unlike every other themed one. The others own an open reserve and
## sculpt it from nothing; this runs after `paint_tile` has already laid the roads, sidewalks and
## buildings, and only adds to what is there. That is the whole point of the theme — the streets
## the horde walks are real streets, so the fight geometry is the city's own.
##
## It is also the only composer that writes well outside its reserve. The barricaded quarter is one
## rectangle; the outer stones, their build rings and the hell gates stand in ordinary city up to
## 150 m away, which is why `DistrictGenerator.open_space_bounds` has to hand out a box for each of
## them — a write outside those boxes is silently dropped on the streamed path.
class_name SiegeComposer
extends RefCounted

## Lodestone: a crystal mass on a stone plinth, tall enough to be the thing you navigate by.
const LODESTONE_RADIUS := 5
const LODESTONE_HEIGHT := 16
## Nothing may be built inside this many voxels of the Lodestone centre — it needs its own square.
const LODESTONE_CLEAR := 12

## Outer stones: four obelisks partway to the tile corners. They are what makes the run a map
## instead of a plaza — the centre cannot be hurt while one of them stands.
##
## Deliberately *not* shaped like the Lodestone. They used to be smaller copies of it, and the field
## report was the obvious one: a player who walked to a stone could not tell it from the objective,
## found no console there, and had no way to start. The Lodestone is a broad crystal mass; these are
## slender needles, so the two read apart from across the tile.
const OUTER_STONE_COUNT := 4
## Footprint radius, which is what the plinth, the pad exclusion and the vulnerability ring are all
## measured from. The shaft inside it is far narrower — see `_paint_obelisk`.
const OUTER_STONE_RADIUS := 4
## Taller than the Lodestone and a fraction of its girth: height is how a needle reads at distance.
const OUTER_STONE_HEIGHT := 22
## Half-width of the obelisk shaft in voxels, so the shaft is 3 voxels (1.5 m) across.
const OBELISK_SHAFT_HALF := 1
## Courses at the top drawn one voxel wide, which is what makes it end in a point.
const OBELISK_TIP_COURSES := 3
## Ideal offset from the *Lodestone*, in voxels: ±(98, 70) m at 0.5 m per voxel. Measured from the
## objective rather than from the tile centre, because the Lodestone stands in the grand plaza and
## the planner puts that wherever the urban pass cleared a square — on a tile whose plaza is off
## centre, a ring around the tile's middle is not a ring around the thing it is supposed to shield.
const OUTER_RING_X := 196
const OUTER_RING_Z := 140
## Two outer stones this close together would be one flank with two crystals on it. Only bites when
## the tile edge forced their ideal points together.
const OUTER_STONE_MIN_GAP := 100
## Nothing may be built inside this many voxels of an outer stone centre.
const OUTER_STONE_CLEAR := 10
## Build sites are swept this far around each outer stone (40 m), so holding a flank means having
## somewhere out there to build. `open_space_bounds` sizes its per-stone box from this.
const OUTER_PAD_RING := 80

## Hell gates: two flanking each outer stone, so every corner approach is a pair of mouths.
const HELL_GATE_COUNT := 8
## How far outboard of its own stone a gate stands, in voxels — 60 m.
##
## Measured radially from the stone rather than as a point on a wider ellipse around the centre. The
## ellipse version distorted the flank angle badly enough that one gate of each pair landed ~25 m
## from the stone it was supposed to threaten, which gave the player no ground to meet a wave on.
const GATE_STANDOFF := 120
## No mouth may stand closer than this to *any* stone, the Lodestone included. This is the rule that
## actually holds the line; the standoff above is only where the search starts.
const GATE_STONE_CLEAR := 120
## How far either side of its stone's outward bearing a flanking gate sits, in radians (~20°).
const GATE_FLANK_RAD := 0.35
## Mouth half-width in voxels: 5 m of opening, wider than the largest body's clearance.
const HELL_GATE_HALF_W := 5
## Frame height in voxels (6 m) and how wide each side pillar is. The whole portal is one plane —
## a tunnel would have to be cut into whatever the tile put behind it, and this reads as a doorway
## from the ranges these stand at anyway.
const HELL_GATE_H := 12
const HELL_GATE_PILLAR_W := 2
## No build site within this many voxels of a mouth. The frame is indestructible, so a mouth walled
## in by towers would trap that lane's horde in a box the player never has to fight.
const HELL_GATE_CLEAR := 16
## Clear ground in front of a mouth, in voxels. Must stay at or above `SiegeController.SPAWN_STEP_VOX`
## — that is where bodies are actually dropped, and a mouth whose apron is a wall spawns the wave
## inside a building. Checking only the voxel next to the frame let that through.
const HELL_GATE_APRON := 4

## How far the site search may wander from an ideal point before giving up, and how it steps. The
## ideal lands wherever the tile's own city put it, which is often a facade or a lot interior.
const SITE_SEARCH_MAX := 72
const SITE_SEARCH_STEP := 4
const SITE_SEARCH_ANGLES := 12
## A gate is allowed to wander much further than a stone. Its ideal point is outboard of a stone that
## has already been nudged off its own ideal, it needs a wide flat plane for the frame, and it has a
## minimum distance to every stone to satisfy — on a cramped tile edge, the first acceptable spot can
## be a long way from where the geometry wanted it.
const GATE_SEARCH_MAX := 140

## A foundation pad is this many voxels either side of its centre, so 5 × 5 (2.5 m).
const PAD_HALF := 2
## Minimum centre-to-centre gap between two build sites, in voxels — 5 m at 0.5 m per voxel,
## which leaves 2.5 m of walkable ground between neighbouring foundations. This is the *only*
## density limit; there is no target count. The policy is that room for a tower which will not
## interfere means a site, so the sweeps below take every position that passes the rules.
const PAD_SPACING := 10
## Street sweep step. Deliberately finer than the spacing so narrow sidewalks and ragged plaza
## edges still yield sites; `PAD_SPACING` thins whatever the sweep over-offers.
const SITE_SCAN_STEP := 4
## Roof sweep step. As fine as the street sweep: flat roof platforms wide enough for a foundation
## are rare, so a coarse sweep finds almost none and the elevated tier stops existing.
const ROOF_SCAN_STEP := 4
## Ceiling on total sites. Not a design limit — a backstop so a pathological tile cannot ask the
## runtime for thousands of "+" plates.
const SITE_MAX := 600
## Height difference, in voxels, within which two sites count as sharing a surface. The spacing
## rule only applies between those: a rooftop tower and the sidewalk under it are not the same
## firing position, and treating them as one strips exactly the roof *edges* worth building on,
## since a sidewalk runs along every facade.
const SAME_LEVEL_VOX := 3

## Barricade courses above the deck. Five voxels is 2.5 m: too tall for anything on the ground to
## step over, and irrelevant to a player who jumps 10 m.
const BARRICADE_H := 5
## Barricade depth into the quarter, in voxels.
const BARRICADE_T := 2

## Barricade breaches, which is also how many approaches into the quarter the defence has to cover.
## These are gaps in the wall, not spawn points — the horde comes out of the hell gates.
const BREACH_MIN := 2
const BREACH_MAX := 3
## Half-width of a breach mouth in voxels, measured from the road cell centre.
const BREACH_HALF_W := 7

## Mirrors `CityWalker.jump_height_max_m`. A roof within this is a ROOF_JUMP pad and anything
## higher is ROOF_HIGH, which wants a cloudstone. `test_siege_district` asserts the two agree, so
## retuning the player's jump cannot quietly put every roof pad out of reach.
const PLAYER_JUMP_M := 10.0
## Tallest roof that may carry a pad, in voxels over the deck. This also sets how tall the
## quarter's editable box has to be in `DistrictGenerator.open_space_bounds` — a pad written above
## that box is silently dropped on the streamed path.
const ROOF_PAD_MAX_VOX := 60
## How far over the deck anything outside the quarter reaches. `open_space_bounds` sizes the tile-wide
## band the outer work writes into from this, and a write above it is silently dropped on the streamed
## path — so it is derived from the tallest outer structure rather than typed in. The obelisk tip
## (base + 2 + height) is that structure; a gate lintel is base + 2 + `HELL_GATE_H`, well under it.
const OUTER_WRITE_HEIGHT_VOX := OUTER_STONE_HEIGHT + 6

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1
var planner: DistrictPlanner
var cell_size: int = 28
## Metres per voxel, so the jump reach above can be compared against voxel heights.
var voxel_size: float = 0.5
## Filled by `compose`, then read by the generator and handed to the runtime controller.
var layout: SiegeLayout = null
## Spatial hash of taken site centres, bin edge `PAD_SPACING`, so the spacing test stays O(1)
## per candidate. A linear scan over every site was fine at eighteen pads and is not at hundreds.
var _site_bins: Dictionary = {}


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
	_plan_outer_stones()
	_plan_hell_gates()
	_plan_breaches()
	## Street sites first so they win the spacing contest — a defence has to be mountable from the
	## ground before roofs become an upgrade — and the quarter before the outer rings, since the
	## quarter is the ground the player cannot give up.
	_site_bins.clear()
	_plan_street_sites()
	_plan_roof_sites()
	_plan_outer_sites()

	_paint_lodestone()
	_paint_outer_stones()
	_paint_hell_gates()
	_paint_barricades()
	_paint_pads()

	if not layout.is_valid():
		push_error(
			"SiegeComposer.compose: unusable siege plan — %s" % layout.describe()
		)
		assert(false, "SiegeComposer: siege plan is missing stones, gates, breaches or pads")
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


## Tile extent in district-local voxels. The composer plans the whole tile, not just its reserve.
func _tile_size_vox() -> Vector2i:
	return Vector2i(planner.cells_x * cell_size, planner.cells_z * cell_size)


func _inside_tile(x: int, z: int, margin: int) -> bool:
	var size := _tile_size_vox()
	return (
		x - margin >= 0
		and z - margin >= 0
		and x + margin < size.x
		and z + margin < size.y
	)


## The barricaded quarter plus a little slack. Outer stones and hell gates must stand clear of it:
## a stone inside the wall would shield nothing, and a mouth inside it would put the horde behind
## the barricade it is supposed to have to break through.
func _quarter_keepout() -> Rect2i:
	return layout.quarter_vox.grow(16)


## Four outer stones, one per corner direction *from the Lodestone*. Each ideal point lands wherever
## the urban pass happened to put a facade, so the real site is the first open, flat, sky-clear spot
## near it — and the ideal is pulled back inside the tile first, since a Lodestone near a border would
## otherwise send half the ring off the map.
func _plan_outer_stones() -> void:
	var centre := layout.lodestone_xz
	for i in range(OUTER_STONE_COUNT):
		var sx := 1 if (i % 2) == 0 else -1
		var sz := 1 if i < 2 else -1
		var ideal := _clamp_into_tile(
			Vector2i(centre.x + sx * OUTER_RING_X, centre.y + sz * OUTER_RING_Z),
			OUTER_STONE_RADIUS + 3
		)
		var at := _search_outward(ideal, _is_outer_stone_site, SITE_SEARCH_MAX)
		if at.x < 0:
			push_error(
				"SiegeComposer: no open ground for outer stone %d near %s" % [i, ideal]
			)
			assert(false, "SiegeComposer: outer stone has nowhere to stand")
			continue
		layout.add_outer_stone(at, ground_y, OUTER_STONE_RADIUS, OUTER_STONE_HEIGHT)


## Two hell gates flanking each outer stone, standing `GATE_STANDOFF` beyond it along the line out
## from the Lodestone. Pairing them to the stones is what makes a wave read as pressure on a flank
## rather than as noise from all sides, and putting them *past* their stone is what gives the player
## ground to meet a wave on before it reaches what it came for.
func _plan_hell_gates() -> void:
	var centre := layout.lodestone_xz
	for stone: SiegeLayout.Stone in layout.outer_stones:
		var bearing := atan2(
			float(stone.xz.y - centre.y), float(stone.xz.x - centre.x)
		)
		for flank: float in [-GATE_FLANK_RAD, GATE_FLANK_RAD]:
			var b := bearing + flank
			## Radial from the stone, so the flank angle means what it says. Offsetting on a wider
			## ellipse around the centre instead squashed the angle and dropped one gate of every
			## pair almost on top of the stone it was meant to threaten.
			var ideal := _clamp_into_tile(
				Vector2i(
					stone.xz.x + int(round(cos(b) * float(GATE_STANDOFF))),
					stone.xz.y + int(round(sin(b) * float(GATE_STANDOFF)))
				),
				HELL_GATE_HALF_W + HELL_GATE_PILLAR_W + 3
			)
			var outward := _cardinal_of(b)
			var at := _search_outward(
				ideal, _is_hell_gate_site.bind(outward), GATE_SEARCH_MAX
			)
			if at.x < 0:
				push_error("SiegeComposer: no open ground for a hell gate near %s" % ideal)
				assert(false, "SiegeComposer: hell gate has nowhere to stand")
				continue
			layout.add_hell_gate(Vector3i(at.x, ground_y, at.y), outward, b)


## Dominant cardinal of a bearing. Voxel painting is axis-aligned, so a gate faces one of four ways
## even though its bearing is continuous — and the flanking pair around a corner ends up facing
## along different axes, which is what makes the corner read as a funnel.
func _cardinal_of(bearing_rad: float) -> Vector2i:
	var dx := cos(bearing_rad)
	var dz := sin(bearing_rad)
	if absf(dx) >= absf(dz):
		return Vector2i(1 if dx >= 0.0 else -1, 0)
	return Vector2i(0, 1 if dz >= 0.0 else -1)


## Pull a point inside the tile, keeping `margin` voxels of slack on every side. An ideal offset from
## the Lodestone can land off the map, because the Lodestone is wherever the grand plaza is.
func _clamp_into_tile(p: Vector2i, margin: int) -> Vector2i:
	var size := _tile_size_vox()
	return Vector2i(
		clampi(p.x, margin, maxi(size.x - 1 - margin, margin)),
		clampi(p.y, margin, maxi(size.y - 1 - margin, margin))
	)


## Walk outward from `ideal` in rings until `probe.call(x, z)` accepts. Deterministic on purpose:
## the ring order is fixed and no RNG is drawn, so two bakes of the same tile stand the stone in
## exactly the same place — the runtime controller finds it by layout, and a wandering site would
## mean the bake and the run disagree. Returns (-1, -1) when nothing near the ideal works.
func _search_outward(ideal: Vector2i, probe: Callable, reach: int) -> Vector2i:
	if _inside_tile(ideal.x, ideal.y, 1) and bool(probe.call(ideal.x, ideal.y)):
		return ideal
	for r in range(SITE_SEARCH_STEP, reach + 1, SITE_SEARCH_STEP):
		for a in range(SITE_SEARCH_ANGLES):
			var ang := TAU * float(a) / float(SITE_SEARCH_ANGLES)
			var x := ideal.x + int(round(cos(ang) * float(r)))
			var z := ideal.y + int(round(sin(ang) * float(r)))
			if not _inside_tile(x, z, 1):
				continue
			if bool(probe.call(x, z)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)


## An outer stone wants open, flat ground with clear sky. It is a landmark, a target and the anchor
## of a shield arc all at once, so one wedged into a courtyard would be three kinds of useless.
func _is_outer_stone_site(x: int, z: int) -> bool:
	var plinth := OUTER_STONE_RADIUS + 1
	if not _inside_tile(x, z, plinth + 2):
		return false
	if _quarter_keepout().has_point(Vector2i(x, z)):
		return false
	for other: SiegeLayout.Stone in layout.outer_stones:
		if _flat_dist(x, z, other.xz.x, other.xz.y) < float(OUTER_STONE_MIN_GAP):
			return false
	for dz in range(-plinth, plinth + 1):
		for dx in range(-plinth, plinth + 1):
			if _flat_dist(x + dx, z + dz, x, z) > float(plinth):
				continue
			if not _is_buildable_column(x + dx, z + dz):
				return false
	for y in range(ground_y + 1, ground_y + OUTER_STONE_HEIGHT + 4):
		if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
			return false
	return true


## A hell gate may straddle a road — bodies walk out along the lane and the mouth is walk-through —
## so this is laxer than `_is_buildable_column`: solid ground under the frame and nothing overhead.
func _is_hell_gate_site(x: int, z: int, outward: Vector2i) -> bool:
	var span := HELL_GATE_HALF_W + HELL_GATE_PILLAR_W
	if not _inside_tile(x, z, span + 2):
		return false
	if _quarter_keepout().has_point(Vector2i(x, z)):
		return false
	for i in range(layout.hell_gate_count()):
		var other := layout.hell_gates[i]
		if _flat_dist(x, z, other.mouth.x, other.mouth.z) < float(span * 4):
			return false
	## Clear of every stone, the Lodestone included. A mouth beside the thing it is besieging means
	## the wave arrives already on top of the objective, with no ground for the player to hold.
	if _flat_dist(x, z, layout.lodestone_xz.x, layout.lodestone_xz.y) < float(GATE_STONE_CLEAR):
		return false
	for stone: SiegeLayout.Stone in layout.outer_stones:
		if _flat_dist(x, z, stone.xz.x, stone.xz.y) < float(GATE_STONE_CLEAR):
			return false
	## Centre column first: it rejects lot interiors and anything under a canopy before the
	## footprint sweep runs, and the centre is what a body is dropped in front of.
	if not _is_clear_gate_column(x, z):
		return false
	var along := Vector2i(-outward.y, outward.x)
	## Ground under the frame plane and immediately either side of it.
	for t in range(-span, span + 1):
		for d: int in [-1, 0, 1]:
			var px := x + along.x * t + outward.x * d
			var pz := z + along.y * t + outward.y * d
			if not _is_open_ground(px, pz):
				return false
	## The apron the horde is dropped onto, in front of the mouth (bodies step out along `-outward`).
	for t in range(-HELL_GATE_HALF_W, HELL_GATE_HALF_W + 1):
		for d in range(2, HELL_GATE_APRON + 1):
			var ax := x + along.x * t - outward.x * d
			var az := z + along.y * t - outward.y * d
			if not _is_open_ground(ax, az):
				return false
	## Sky over the frame ends, so the lintel is not buried in a facade.
	return (
		_is_clear_gate_column(x + along.x * span, z + along.y * span)
		and _is_clear_gate_column(x - along.x * span, z - along.y * span)
	)


func _is_open_ground(x: int, z: int) -> bool:
	if not VoxelMaterial.is_solid(brush.get_vox(Vector3i(x, ground_y, z))):
		return false
	return brush.get_vox(Vector3i(x, ground_y + 1, z)) == VoxelMaterial.AIR


func _is_clear_gate_column(x: int, z: int) -> bool:
	if not _is_open_ground(x, z):
		return false
	for y in range(ground_y + 1, ground_y + HELL_GATE_H + 3):
		if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
			return false
	return true


## Barricade breaches on roads that cross the quarter boundary, at most one per side, two or three
## in total. Everything else on the perimeter gets walled, so these are the only ways in.
func _plan_breaches() -> void:
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
	## the same tile disagree about where the breaches are.
	for i in range(candidates.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var want := BREACH_MIN + int(rng.randi() % (BREACH_MAX - BREACH_MIN + 1))
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
		layout.add_breach(_breach_mouth_for(side, cell), _inward_for(side))
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


## Mouth centre on the quarter boundary for a breach on `side` in `cell`.
func _breach_mouth_for(side: int, cell: Vector2i) -> Vector3i:
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
	push_error("SiegeComposer._breach_mouth_for: %d is not a side" % side)
	assert(false, "SiegeComposer: bad side")
	return Vector3i.ZERO


## Street-level build sites: a fine sweep of the whole quarter, keeping every position that
## passes. Rows start on a random offset so the accepted lattice does not read as a printed grid.
func _plan_street_sites() -> void:
	var q := layout.quarter_vox
	for z in range(q.position.y, q.position.y + q.size.y, SITE_SCAN_STEP):
		var x0 := q.position.x + int(rng.randi_range(0, SITE_SCAN_STEP - 1))
		for x in range(x0, q.position.x + q.size.x, SITE_SCAN_STEP):
			if layout.pad_count() >= SITE_MAX:
				return
			if not _is_pad_ground(x, z, q):
				continue
			_add_site(Vector3i(x, ground_y, z), SiegeLayout.PadKind.STREET)


## Build rings out at the outer stones. Without these, holding a flank would mean standing on it in
## person — the quarter's towers are 100 m away and no gun reaches that far, so a stone with no
## sites near it is a stone that cannot be defended at all.
func _plan_outer_sites() -> void:
	for stone: SiegeLayout.Stone in layout.outer_stones:
		var ring := Rect2i(
			stone.xz.x - OUTER_PAD_RING,
			stone.xz.y - OUTER_PAD_RING,
			OUTER_PAD_RING * 2,
			OUTER_PAD_RING * 2
		)
		for z in range(ring.position.y, ring.position.y + ring.size.y, SITE_SCAN_STEP):
			var x0 := ring.position.x + int(rng.randi_range(0, SITE_SCAN_STEP - 1))
			for x in range(x0, ring.position.x + ring.size.x, SITE_SCAN_STEP):
				if layout.pad_count() >= SITE_MAX:
					return
				if not _inside_tile(x, z, PAD_HALF + 1):
					continue
				if _flat_dist(x, z, stone.xz.x, stone.xz.y) > float(OUTER_PAD_RING):
					continue
				if not _is_pad_ground(x, z, ring):
					continue
				_add_site(Vector3i(x, ground_y, z), SiegeLayout.PadKind.STREET)


## True when a 5 × 5 pad can stand here: flat open deck inside `bounds`, clear of every stone, clear
## of the breach and hell-gate mouths, clear of other sites, and off the carriageway so lanes stay
## walkable. The carriageway rule is the one that makes a permissive site policy safe — roads are
## never buildable and the road graph spans the tile, so no amount of building can seal the map.
func _is_pad_ground(x: int, z: int, bounds: Rect2i) -> bool:
	if (
		x - PAD_HALF < bounds.position.x
		or x + PAD_HALF >= bounds.position.x + bounds.size.x
		or z - PAD_HALF < bounds.position.y
		or z + PAD_HALF >= bounds.position.y + bounds.size.y
	):
		return false
	if _flat_dist(x, z, layout.lodestone_xz.x, layout.lodestone_xz.y) < float(LODESTONE_CLEAR):
		return false
	for stone: SiegeLayout.Stone in layout.outer_stones:
		if _flat_dist(x, z, stone.xz.x, stone.xz.y) < float(OUTER_STONE_CLEAR + PAD_HALF):
			return false
	for i in range(layout.hell_gate_count()):
		var mouth := layout.hell_gates[i].mouth
		if _flat_dist(x, z, mouth.x, mouth.z) < float(HELL_GATE_CLEAR + PAD_HALF):
			return false
	for i in range(layout.breach_count()):
		var b := layout.breaches[i]
		if _flat_dist(x, z, b.x, b.z) < float(BREACH_HALF_W + PAD_HALF):
			return false
	if _too_close_to_site(x, ground_y, z):
		return false
	## Centre column first: two probes reject asphalt, building interiors and rubble before the
	## 25-column footprint sweep runs at all, which is most of what a fine sweep offers.
	if not _is_buildable_column(x, z):
		return false
	for dz in range(-PAD_HALF, PAD_HALF + 1):
		for dx in range(-PAD_HALF, PAD_HALF + 1):
			if not _is_buildable_column(x + dx, z + dz):
				return false
	return true


## Roof sites: the best sightlines in the quarter, and the ones that cost the most to reach.
func _plan_roof_sites() -> void:
	var q := layout.quarter_vox
	for z in range(q.position.y, q.position.y + q.size.y, ROOF_SCAN_STEP):
		var x0 := q.position.x + int(rng.randi_range(0, ROOF_SCAN_STEP - 1))
		for x in range(x0, q.position.x + q.size.x, ROOF_SCAN_STEP):
			if layout.pad_count() >= SITE_MAX:
				return
			var y := _roof_surface_y(x, z)
			if y < 0:
				continue
			if not _is_roof_pad_site(x, y, z):
				continue
			_add_site(Vector3i(x, y, z), _roof_kind_for(y))


func _add_site(surface_vox: Vector3i, kind: SiegeLayout.PadKind) -> void:
	layout.add_pad(surface_vox, kind)
	var bin := _site_bin(surface_vox.x, surface_vox.z)
	if not _site_bins.has(bin):
		var fresh: Array[Vector3i] = []
		_site_bins[bin] = fresh
	var taken: Array[Vector3i] = _site_bins[bin]
	taken.append(surface_vox)


func _site_bin(x: int, z: int) -> Vector2i:
	return Vector2i(
		floori(float(x) / float(PAD_SPACING)), floori(float(z) / float(PAD_SPACING))
	)


## Spacing test against the 3 × 3 bin neighbourhood, and only against sites on the same surface.
## A bin edge of `PAD_SPACING` means nothing outside that neighbourhood can be within the spacing.
func _too_close_to_site(x: int, y: int, z: int) -> bool:
	var bin := _site_bin(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(bin.x + dx, bin.y + dz)
			if not _site_bins.has(key):
				continue
			var taken: Array[Vector3i] = _site_bins[key]
			for p: Vector3i in taken:
				if absi(p.y - y) > SAME_LEVEL_VOX:
					continue
				if _flat_dist(x, z, p.x, p.z) < float(PAD_SPACING):
					return true
	return false


## Top solid voxel of this column above the deck, or -1 when there is no roof here. A column whose
## building carries on past the probe band is rejected rather than clamped: the voxel at the top of
## the band is inside the mass, not a surface anything could stand on.
func _roof_surface_y(x: int, z: int) -> int:
	## Roofs only exist over building lots, and the land-use tag answers that in one array read
	## instead of a 60-voxel column walk that finds nothing. Open pavement is the majority of a
	## swept quarter, so this is most of the sweep's cost. Probing the voxels instead does not
	## work: buildings are hollow, so an interior column is air well above the deck.
	if not LandUse.is_lot(planner.tag_at(x / cell_size, z / cell_size)):
		return -1
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
	if _too_close_to_site(x, y, z):
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
	_paint_stone(
		layout.lodestone_xz,
		layout.lodestone_base_y,
		layout.lodestone_radius_vox,
		layout.lodestone_height_vox
	)


func _paint_outer_stones() -> void:
	for stone: SiegeLayout.Stone in layout.outer_stones:
		_paint_obelisk(stone.xz, stone.base_y, stone.radius_vox, stone.height_vox)


## An obelisk: a stepped square base and a slender square needle in the same lit glass as the
## Lodestone, capped with a point.
##
## Shape is the whole job here. These stood as scaled-down copies of the Lodestone, and a player who
## walked to one could not tell it from the objective — same round tapered mass, same materials, three
## quarters of the size, and no console to be found. A square needle twice as tall as it is wide reads
## as a marker rather than as *the* crystal from anywhere on the tile, while the shared glass keeps it
## legible as part of the same system.
func _paint_obelisk(centre: Vector2i, base: int, footprint: int, height: int) -> void:
	var cx := centre.x
	var cz := centre.y

	## Two square steps, the lower one the full footprint. Square on purpose: the Lodestone's plinth
	## is round, and the footprints differ even where the shafts are hidden behind a building.
	for step in range(2):
		var r := footprint - step
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				brush.set_vox(Vector3i(cx + dx, base + step, cz + dz), VoxelMaterial.STONE)

	## The needle. `GEM_*` would be collectible, which would let the player mine the objective's
	## own shield.
	for course in range(height):
		var y := base + 2 + course
		## Single-voxel tip over the last few courses, so the silhouette ends in a point instead of
		## a flat-topped post.
		var r := 0 if course >= height - OBELISK_TIP_COURSES else OBELISK_SHAFT_HALF
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				brush.set_vox(Vector3i(cx + dx, y, cz + dz), VoxelMaterial.GLASS_LIT)


## A crystal mass on a stone plinth: round, broad and tapered. The Lodestone only — the outer stones
## are obelisks, so the objective cannot be mistaken for one of the things guarding it.
func _paint_stone(centre: Vector2i, base: int, radius: int, height: int) -> void:
	var cx := centre.x
	var cz := centre.y

	## Plinth one voxel proud of the crystal, so the mass reads as placed rather than grown.
	var plinth_r := radius + 1
	for dz in range(-plinth_r, plinth_r + 1):
		for dx in range(-plinth_r, plinth_r + 1):
			if _flat_dist(cx + dx, cz + dz, cx, cz) > float(plinth_r):
				continue
			brush.set_vox(Vector3i(cx + dx, base, cz + dz), VoxelMaterial.STONE)
			brush.set_vox(Vector3i(cx + dx, base + 1, cz + dz), VoxelMaterial.STONE)

	## Crystal: a tapered mass in lit glass. GEM_* materials would be collectible, which would let
	## the player mine the objective they are defending.
	for course in range(height):
		var t := float(course) / float(height)
		var course_r := maxf(float(radius) * (1.0 - t * 0.85), 1.0)
		var y := base + 2 + course
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if _flat_dist(cx + dx, cz + dz, cx, cz) > course_r:
					continue
				brush.set_vox(Vector3i(cx + dx, y, cz + dz), VoxelMaterial.GLASS_LIT)


func _paint_hell_gates() -> void:
	for i in range(layout.hell_gate_count()):
		_paint_hell_gate(layout.hell_gates[i])


## Frame from the zoo containment kit, whose materials are already unbreakable, so nothing the
## player can carry takes a portal apart. The mouth is `LOS_VEIL`: walk-through, invisible, and
## opaque to combat line of sight — bodies leave freely and the player cannot shoot into a gate,
## which is what stops spawn-camping mechanically instead of by rule.
func _paint_hell_gate(gate: SiegeLayout.HellGate) -> void:
	var along := Vector2i(-gate.outward.y, gate.outward.x)
	var base := gate.mouth.y
	var span := HELL_GATE_HALF_W + HELL_GATE_PILLAR_W

	for side: int in [-1, 1]:
		for t in range(HELL_GATE_HALF_W + 1, span + 1):
			var px := gate.mouth.x + along.x * t * side
			var pz := gate.mouth.z + along.y * t * side
			for course in range(HELL_GATE_H):
				var mat := VoxelMaterial.ZOO_FENCE_FRAME
				if course % 4 == 2:
					mat = VoxelMaterial.ZOO_FENCE_LINE
				brush.set_vox(Vector3i(px, base + 1 + course, pz), mat)

	for t in range(-span, span + 1):
		var lx := gate.mouth.x + along.x * t
		var lz := gate.mouth.z + along.y * t
		brush.set_vox(
			Vector3i(lx, base + 1 + HELL_GATE_H, lz), VoxelMaterial.ZOO_FENCE_FRAME
		)
		brush.set_vox(
			Vector3i(lx, base + 2 + HELL_GATE_H, lz), VoxelMaterial.ZOO_FENCE_LINE
		)

	for t in range(-HELL_GATE_HALF_W, HELL_GATE_HALF_W + 1):
		var vx := gate.mouth.x + along.x * t
		var vz := gate.mouth.z + along.y * t
		for course in range(HELL_GATE_H):
			brush.set_vox(Vector3i(vx, base + 1 + course, vz), VoxelMaterial.LOS_VEIL)


## Wall the quarter perimeter everywhere the ground is open, leaving the breach mouths clear.
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
	if _inside_a_breach(x, z):
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


func _inside_a_breach(x: int, z: int) -> bool:
	for i in range(layout.breach_count()):
		var b := layout.breaches[i]
		if _flat_dist(x, z, b.x, b.z) <= float(BREACH_HALF_W):
			return true
	return false


## Flush plating only. The pads used to carry corner studs so an empty one read from across the
## street; at hundreds of sites that is a field of ankle-high metal bumps over every sidewalk in
## the quarter, and the lay-flat "+" plate is the marker now.
func _paint_pads() -> void:
	for i in range(layout.pad_count()):
		var pad := layout.pads[i]
		for dz in range(-PAD_HALF, PAD_HALF + 1):
			for dx in range(-PAD_HALF, PAD_HALF + 1):
				brush.set_vox(
					Vector3i(pad.x + dx, pad.y, pad.z + dz), VoxelMaterial.METAL_PLATE
				)


func _flat_dist(ax: int, az: int, bx: int, bz: int) -> float:
	return Vector2(float(ax - bx), float(az - bz)).length()
