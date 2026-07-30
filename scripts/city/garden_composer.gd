## Formal gardens, stamped out of the outdoor prop kit rather than faked with PLANTER
## boxes: gravel walks, clipped hedges, quadrant beds, a centre feature, topiary, seats,
## lanterns and an iron railing round the whole thing.
##
## Pure voxel composer over a CityBrush, so the castle meadow, the bailey flags and a city
## park quarter can all ask for the same garden. It only ever writes inside `rect` and
## never inside a `keep_clear` footprint — a caller's route stays a route.
##
## PARTERRE and ORCHARD expect open ground they may re-turf; RAISED is for paved ground
## (the bailey) where the beds stand on the flags as planters instead of being dug.
class_name GardenComposer
extends RefCounted

enum Style {
	## Four quadrant beds inside a walk ring, hedged, around a centre feature.
	PARTERRE,
	## Tree rows on lawn between mown lanes, fenced.
	ORCHARD,
	## Parterre geometry on paving: raised planter boxes, no digging, no re-turfing.
	RAISED,
}

var brush: CityBrush
var rng: RandomNumberGenerator
var stamper: TreeStamper

## Props stamped across every compose on this instance — what the report line and the
## tests read.
var props_placed: int = 0
var beds_made: int = 0

## Gravel border between the railing and the first bed.
const WALK_W := 3
## Width of the cross axes through the middle.
const AXIS_W := 3
## Narrowest bed a quadrant may be cut to. Two of these plus the axis and both walks is
## the smallest square that still reads as a parterre rather than as a hedge with a path.
const BED_MIN := 5
const PARTERRE_MIN := WALK_W * 2 + AXIS_W + BED_MIN * 2
const ORCHARD_MIN := 16
## Orchard row pitch. A round_tree crown is 3–4 voxels of radius, so anything tighter
## merges the rows into one canopy.
const ROW_PITCH := 9
const LANE_W := 3
## Ground kept between the fence and the first row, so a crown does not overhang the pales.
const ROW_INSET := 5
## Railing panels are four voxels long; corner posts take the first column of each run.
const PANEL := 4
const HEDGE_H := 2
## Half-width of the paved crossing the centre feature stands on.
const CROSS_HW := 3

## What a bed is planted with. A bed picks one for its border and one for its figure, so the
## planting reads as two colours laid out rather than as confetti.
const BLOOMS: Array[String] = [
	"flower_purpleA",
	"flower_purpleB",
	"flower_redA",
	"flower_redB",
	"flower_yellowA",
	"flower_yellowB",
]

## Rects no write may touch — routes, doorway aprons, stair lanes.
var _clear: Array[Rect2i] = []


static func min_side(style: Style) -> int:
	return ORCHARD_MIN if style == Style.ORCHARD else PARTERRE_MIN


static func fits(rect: Rect2i, style: Style) -> bool:
	var m := min_side(style)
	return rect.size.x >= m and rect.size.y >= m


static func style_name(style: Style) -> String:
	match style:
		Style.PARTERRE:
			return "parterre"
		Style.ORCHARD:
			return "orchard"
		_:
			return "raised"


## Lay out one garden. `surface_y` is the topmost solid voxel of the ground it stands on;
## everything is written at `surface_y` and above. A rect too small for the style is a
## caller bug, not a smaller garden — check `fits` first.
func compose(
	rect: Rect2i, surface_y: int, style: Style, keep_clear: Array[Rect2i] = []
) -> void:
	if brush == null or rng == null:
		push_error("GardenComposer: brush / rng not set")
		return
	if not fits(rect, style):
		push_error(
			"GardenComposer: %s plot %s is smaller than the %d voxel minimum"
			% [style_name(style), rect, min_side(style)]
		)
		return
	_clear = keep_clear
	match style:
		Style.ORCHARD:
			_compose_orchard(rect, surface_y)
		_:
			_compose_parterre(rect, surface_y, style == Style.RAISED)
	_clear = []


# ---------------------------------------------------------------------------
# Parterre
# ---------------------------------------------------------------------------

func _compose_parterre(rect: Rect2i, y: int, raised: bool) -> void:
	if not raised:
		_lawn(rect, y)
	var inner := rect.grow(-WALK_W)
	_walk_ring(rect, inner, y, raised)
	var cx := inner.position.x + inner.size.x / 2
	var cz := inner.position.y + inner.size.y / 2
	_axis_cross(inner, cx, cz, y, raised)
	for bed in _quadrants(inner, cx, cz):
		_bed(bed, y, raised)
		beds_made += 1
	_centre_feature(cx, cz, y)
	_topiary(inner, cx, cz, y)
	_seats(inner, cx, cz, y)
	_lamps(rect, y)
	_railing(rect, y)


## The four beds a cross leaves in `inner`. Empty when the axes ate the whole plot, which
## `fits` already ruled out for the minimum size.
func _quadrants(inner: Rect2i, cx: int, cz: int) -> Array[Rect2i]:
	var half := AXIS_W / 2
	var x_lo := inner.position.x
	var x_a := cx - half
	var x_b := cx + half + 1
	var x_hi := inner.end.x
	var z_lo := inner.position.y
	var z_a := cz - half
	var z_b := cz + half + 1
	var z_hi := inner.end.y
	var out: Array[Rect2i] = []
	for xs: Vector2i in [Vector2i(x_lo, x_a), Vector2i(x_b, x_hi)]:
		for zs: Vector2i in [Vector2i(z_lo, z_a), Vector2i(z_b, z_hi)]:
			var r := Rect2i(xs.x, zs.x, xs.y - xs.x, zs.y - zs.x)
			if r.size.x >= BED_MIN and r.size.y >= BED_MIN:
				out.append(r)
	return out


func _lawn(rect: Rect2i, y: int) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_paint(x, y, z, VoxelMaterial.PARK)


func _walk_ring(rect: Rect2i, inner: Rect2i, y: int, raised: bool) -> void:
	## On flags the walk is already paved and gravel over ashlar reads as spoil.
	if raised:
		return
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if inner.has_point(Vector2i(x, z)):
				continue
			_paint(x, y, z, VoxelMaterial.GRAVEL)


func _axis_cross(inner: Rect2i, cx: int, cz: int, y: int, raised: bool) -> void:
	if raised:
		return
	var half := AXIS_W / 2
	for z in range(inner.position.y, inner.end.y):
		for x in range(cx - half, cx + half + 1):
			_paint(x, y, z, VoxelMaterial.GRAVEL)
	for x2 in range(inner.position.x, inner.end.x):
		for z2 in range(cz - half, cz + half + 1):
			_paint(x2, y, z2, VoxelMaterial.GRAVEL)
	## The crossing itself is paved wider, so the centre feature stands in a square.
	for z3 in range(cz - CROSS_HW, cz + CROSS_HW + 1):
		for x3 in range(cx - CROSS_HW, cx + CROSS_HW + 1):
			_paint(x3, y, z3, VoxelMaterial.GRAVEL)


## One quadrant: a clipped hedge round soil, planted in bands. On paving the soil sits in
## a PLANTER box one course up instead of replacing the flags.
func _bed(bed: Rect2i, y: int, raised: bool) -> void:
	var soil_y := y + 1 if raised else y
	var plant_y := soil_y + 1
	for z in range(bed.position.y, bed.end.y):
		for x in range(bed.position.x, bed.end.x):
			var rim := (
				x == bed.position.x
				or z == bed.position.y
				or x == bed.end.x - 1
				or z == bed.end.y - 1
			)
			if raised:
				_paint(x, soil_y, z, VoxelMaterial.PLANTER if rim else VoxelMaterial.DIRT)
			elif rim:
				_hedge_column(x, z, y)
			else:
				_paint(x, soil_y, z, VoxelMaterial.DIRT)
	_plant_bed(bed.grow(-1), plant_y)


func _hedge_column(x: int, z: int, y: int) -> void:
	_paint(x, y, z, VoxelMaterial.DIRT)
	for dy in range(1, HEDGE_H + 1):
		_paint(x, y + dy, z, VoxelMaterial.YEW)


## A bed is planted in a figure, not filled: one bloom worked round the border of the soil,
## a second picked out on the diagonals, and a clipped bush where they cross. Planting every
## other column right across the bed instead reads as a vegetable plot from the walk.
func _plant_bed(area: Rect2i, y: int) -> void:
	if area.size.x <= 0 or area.size.y <= 0:
		return
	var border := BLOOMS[rng.randi() % BLOOMS.size()]
	var saltire := BLOOMS[rng.randi() % BLOOMS.size()]
	var cx := area.position.x + area.size.x / 2
	var cz := area.position.y + area.size.y / 2
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var on_border := (
				x == area.position.x
				or z == area.position.y
				or x == area.end.x - 1
				or z == area.end.y - 1
			)
			var dx := x - cx
			var dz := z - cz
			if on_border:
				## Every other one: shoulder to shoulder they merge into a hedge of
				## the wrong colour.
				if (x + z) % 2 == 0:
					_place(border, x, y, z)
			elif absi(dx) == absi(dz) and dx != 0:
				_place(saltire, x, y, z)
	if area.size.x >= 5 and area.size.y >= 5:
		_place_centred("plant_bushSmall", cx, y, cz)


## Basin or statue at the crossing. Both stand on the paving rather than being dug in, so
## the same code works on the bailey flags.
func _centre_feature(cx: int, cz: int, y: int) -> void:
	if rng.randf() < 0.5:
		var r := CROSS_HW - 1
		for z in range(cz - r, cz + r + 1):
			for x in range(cx - r, cx + r + 1):
				var dx := x - cx
				var dz := z - cz
				var d2 := dx * dx + dz * dz
				if d2 > r * r:
					continue
				var rim := d2 > (r - 1) * (r - 1)
				_paint(x, y + 1, z, VoxelMaterial.STONE if rim else VoxelMaterial.WATER)
		return
	var statues: Array[String] = ["statue_column", "statue_obelisk", "pillarObelisk"]
	var stem := statues[rng.randi() % statues.size()]
	for z in range(cz - 1, cz + 2):
		for x in range(cx - 1, cx + 2):
			_paint(x, y + 1, z, VoxelMaterial.STONE)
	_place_centred(stem, cx, y + 2, cz)


## Clipped cones on the bed corners that face the crossing — the vertical accents that
## make a flat bed read as a garden room.
func _topiary(inner: Rect2i, cx: int, cz: int, y: int) -> void:
	var off := AXIS_W / 2 + 2
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var x := cx + sx * off
			var z := cz + sz * off
			if not inner.has_point(Vector2i(x, z)):
				continue
			_place_centred("tree_cone", x, y + 1, z)


func _seats(inner: Rect2i, cx: int, cz: int, y: int) -> void:
	var reach := AXIS_W / 2 + 3
	## Facing in along both axes, set back far enough not to block the walk itself.
	_place("benchStone", inner.position.x + 1, y + 1, cz - 1)
	_place("benchStone", inner.end.x - 4, y + 1, cz - 1)
	_place("benchStone_z", cx - 1, y + 1, inner.position.y + 1)
	_place("benchStone_z", cx - 1, y + 1, inner.end.y - 4)
	## Urns on short pillars where the axes meet the walk.
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var x := cx + d.x * reach
		var z := cz + d.y * reach
		if not inner.has_point(Vector2i(x, z)):
			continue
		if _place("pillarSmall", x, y + 1, z):
			_place("urnRound", x, y + 4, z)


func _lamps(rect: Rect2i, y: int) -> void:
	var inset := WALK_W / 2
	var corners: Array[Vector2i] = [
		Vector2i(rect.position.x + inset, rect.position.y + inset),
		Vector2i(rect.end.x - 1 - inset, rect.position.y + inset),
		Vector2i(rect.position.x + inset, rect.end.y - 1 - inset),
		Vector2i(rect.end.x - 1 - inset, rect.end.y - 1 - inset),
	]
	for c: Vector2i in corners:
		_place("lightpostSingle", c.x, y + 1, c.y)


## Iron railing round the plot with a gate panel in the middle of the long side, and a
## stone post on every corner. Panels are stamped from the run's start so a partial panel
## at the end is left off rather than poking out of the garden.
func _railing(rect: Rect2i, y: int) -> void:
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x - 1
	var z1 := rect.end.y - 1
	for c: Vector2i in [
		Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)
	]:
		_place("pillarSmall", c.x, y + 1, c.y)
	var gate_x := x0 + rect.size.x / 2 - PANEL / 2
	var x := x0 + 1
	while x + PANEL <= x1:
		var at_gate := x <= gate_x and gate_x < x + PANEL
		_place("ironFenceBorderGate" if at_gate else "ironFence", x, y + 1, z0)
		_place("ironFence", x, y + 1, z1)
		x += PANEL
	var z := z0 + 1
	while z + PANEL <= z1:
		_place("ironFence_z", x0, y + 1, z)
		_place("ironFence_z", x1, y + 1, z)
		z += PANEL


# ---------------------------------------------------------------------------
# Orchard
# ---------------------------------------------------------------------------

func _compose_orchard(rect: Rect2i, y: int) -> void:
	_lawn(rect, y)
	var along_x := rect.size.x >= rect.size.y
	## The rows run along the plot's long axis and `row` walks across it.
	var across_hi := (rect.end.y if along_x else rect.end.x) - ROW_INSET
	var along_lo := (rect.position.x if along_x else rect.position.y) + ROW_INSET
	var along_hi := (rect.end.x if along_x else rect.end.y) - ROW_INSET
	var row := (rect.position.y if along_x else rect.position.x) + ROW_INSET
	while row < across_hi:
		var t := along_lo
		while t < along_hi:
			var x := t if along_x else row
			var z := row if along_x else t
			if _plantable(x, y, z):
				_tree(x, y, z)
			t += ROW_PITCH
		## A lane belongs between two rows, and gravel is not plantable — so it is mown
		## after the row is planted, and only once there is a further row to mow towards.
		if row + ROW_PITCH < across_hi:
			_mown_lane(rect, y, along_x, row + (ROW_PITCH - LANE_W) / 2 + 1)
		row += ROW_PITCH
	_orchard_fence(rect, y)
	## Windfall and a chopping stump: the orchard is worked, not ornamental.
	for _i in range(3):
		var px := rng.randi_range(rect.position.x + 2, rect.end.x - 4)
		var pz := rng.randi_range(rect.position.y + 2, rect.end.y - 4)
		_place("stump_old" if rng.randf() < 0.5 else "log_stack", px, y + 1, pz)


## One mown strip across the plot, `LANE_W` wide, stopping short of the fence at both ends.
func _mown_lane(rect: Rect2i, y: int, along_x: bool, lane: int) -> void:
	for k in range(LANE_W):
		if along_x:
			for x in range(rect.position.x + 1, rect.end.x - 1):
				_paint(x, y, lane + k, VoxelMaterial.GRAVEL)
		else:
			for z in range(rect.position.y + 1, rect.end.y - 1):
				_paint(lane + k, y, z, VoxelMaterial.GRAVEL)


func _tree(x: int, y: int, z: int) -> void:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	if _blocked(Rect2i(x - 1, z - 1, 3, 3)):
		return
	stamper.round_tree(x, y, z)


func _orchard_fence(rect: Rect2i, y: int) -> void:
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x - 1
	var z1 := rect.end.y - 1
	var gate_x := x0 + rect.size.x / 2 - PANEL / 2
	var x := x0
	while x + PANEL <= x1:
		var at_gate := x <= gate_x and gate_x < x + PANEL
		_place("fence_gate" if at_gate else "fence_simple", x, y + 1, z0)
		_place("fence_simple", x, y + 1, z1)
		x += PANEL
	var z := z0 + PANEL
	while z + PANEL <= z1:
		_place("fence_simple_z", x0, y + 1, z)
		_place("fence_simple_z", x1, y + 1, z)
		z += PANEL


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

## Every voxel this composer writes goes through here, so one check keeps the whole
## garden out of the caller's reserved footprints.
func _paint(x: int, y: int, z: int, material_id: int) -> void:
	if _blocked(Rect2i(x, z, 1, 1)):
		return
	brush.set_vox(Vector3i(x, y, z), material_id)


## Stamp a prop with its origin at (x, y, z). Refuses unless the whole footprint is air
## standing on solid ground, so a garden never grows out of a pond or into a hedge.
func _place(stem: String, x: int, y: int, z: int) -> bool:
	var size := RoomPropCatalog.size_of_stem(stem)
	var foot := Rect2i(x, z, size.x, size.z)
	if _blocked(foot):
		return false
	for dz in range(size.z):
		for dx in range(size.x):
			if not VoxelMaterial.is_solid(brush.get_vox(Vector3i(x + dx, y - 1, z + dz))):
				return false
			for dy in range(size.y):
				if brush.get_vox(Vector3i(x + dx, y + dy, z + dz)) != VoxelMaterial.AIR:
					return false
	if not RoomPropKit.stamp_brush(brush, Vector3i(x, y, z), stem):
		return false
	props_placed += 1
	return true


## Same, with the footprint centred on the column instead of starting at it.
func _place_centred(stem: String, x: int, y: int, z: int) -> bool:
	var size := RoomPropCatalog.size_of_stem(stem)
	return _place(stem, x - size.x / 2, y, z - size.z / 2)


func _plantable(x: int, y: int, z: int) -> bool:
	if _blocked(Rect2i(x, z, 1, 1)):
		return false
	var id := brush.get_vox(Vector3i(x, y, z))
	return id == VoxelMaterial.PARK or id == VoxelMaterial.DIRT


func _blocked(foot: Rect2i) -> bool:
	for r: Rect2i in _clear:
		if r.intersects(foot):
			return true
	return false
