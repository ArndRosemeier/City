## Composes park voxels: lawns, paths, ponds, groves, hedges.
class_name ParkComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1
var stamper: TreeStamper
var garden: GardenComposer

## District-local centre of the rare gazebo: X and Z in `x`/`z`, the deck's walk surface Y in
## `y`. `x` is -1 until a park rolls one. Read by the generator so a recipe scroll can be stood
## under the roof; the district resets it before each compose.
var gazebo_center: Vector3i = Vector3i(-1, 0, -1)


## Main promenade / loop path width in voxels (0.5 m each).
const PROMENADE_W := 5
const LOOP_W := 3
## How far the loop path sits inside the park border.
const LOOP_INSET := 7
## Side of the formal quarter dropped into a large park, and the inset that keeps it
## inside the loop path rather than straddling it.
const FORMAL_SIDE_MIN := GardenComposer.PARTERRE_MIN
const FORMAL_SIDE_MAX := 34
const FORMAL_INSET := LOOP_INSET + LOOP_W + 2

## A bandstand of a gazebo: rare enough that finding one is an event, and never in a pocket
## green — this wants a park with room to walk up to it.
const GAZEBO_CHANCE_PCT := 18
## Half-width of the deck (11×11 footprint) and how far its corners are chamfered off.
const GAZEBO_HALF := 5
const GAZEBO_CHAMFER := 2
## Posts this far in from each face corner. Must stay on the chamfered deck (HALF-1 is
## off the footprint); everything between the two posts is the doorway.
const GAZEBO_POST_INSET := 2
## Deck step, column height above the deck, and the pitch of the little roof.
const GAZEBO_DECK_RISE := 1
const GAZEBO_COLUMN_H := 6
const GAZEBO_ROOF_H := 4
## Smallest park that can hold one with a walkable ring left around it.
const GAZEBO_PARK_MIN := 46
const GAZEBO_INSET := LOOP_INSET + LOOP_W + 3


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper


func compose_large(min_v: Vector3i, max_v: Vector3i) -> void:
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 30 or d < 30:
		compose_pocket(min_v, max_v)
		return
	var along_x := w >= d
	_lawn(min_v, max_v)
	## Layout order matters: paths first, then water, then anything that plants only
	## on remaining lawn voxels — that keeps trees and beds off the walkways for free.
	var promenade := _curved_path(min_v, max_v, along_x, PROMENADE_W, 0.0)
	_loop_path(min_v, max_v)
	var pond := _pond(min_v, max_v, along_x)
	_pond_approach(min_v, max_v, pond, along_x)
	_allee(min_v, max_v, promenade, along_x)
	_groves(min_v, max_v)
	_edge_planting(min_v, max_v)
	_flower_beds(min_v, max_v)
	_benches(min_v, max_v, promenade, along_x)
	_formal_quarter(min_v, max_v)
	_gazebo(min_v, max_v)


func compose_pocket(min_v: Vector3i, max_v: Vector3i) -> void:
	_lawn(min_v, max_v)
	_simple_path(min_v, max_v)
	## Keep crowns clear of the surrounding street: a canopy is a few metres wide now.
	for _i in range(3 + rng.randi() % 3):
		var x := rng.randi_range(min_v.x + 5, max_v.x - 6)
		var z := rng.randi_range(min_v.z + 5, max_v.z - 6)
		if not _is_plantable(x, z):
			continue
		_stamper().round_tree(x, ground_y, z)
	var cz := (min_v.z + max_v.z) / 2
	var bx := (min_v.x + max_v.x) / 2 - 1
	var bz := cz + 3
	if _area_is_lawn(bx, bz, 3, 1):
		brush.fill_box(
			Vector3i(bx, ground_y + 1, bz),
			Vector3i(bx + 3, ground_y + 2, bz + 1),
			VoxelMaterial.PLANTER
		)
	var fx := min_v.x + 4
	var fz := min_v.z + 4
	if _area_is_lawn(fx, fz, 4, 2):
		brush.fill_box(
			Vector3i(fx, ground_y + 1, fz),
			Vector3i(fx + 4, ground_y + 2, fz + 2),
			VoxelMaterial.PLANTER
		)
		brush.fill_box(
			Vector3i(fx, ground_y + 2, fz),
			Vector3i(fx + 4, ground_y + 3, fz + 2),
			VoxelMaterial.PAINT
		)


func compose_courtyard_garden(hole_min: Vector3i, hole_max: Vector3i) -> void:
	## hole spans building height in y; garden only on ground slab.
	var gmin := Vector3i(hole_min.x, ground_y, hole_min.z)
	var gmax := Vector3i(hole_max.x, ground_y + 1, hole_max.z)
	if gmax.x - gmin.x < 3 or gmax.z - gmin.z < 3:
		brush.fill_box(gmin, gmax, VoxelMaterial.PARK)
		return
	brush.fill_box(
		Vector3i(gmin.x, ground_y, gmin.z),
		Vector3i(gmax.x, ground_y + 1, gmax.z),
		VoxelMaterial.DIRT
	)
	brush.fill_box(
		Vector3i(gmin.x, ground_y, gmin.z),
		Vector3i(gmax.x, ground_y + 1, gmax.z),
		VoxelMaterial.PARK
	)
	var cx := (gmin.x + gmax.x) / 2
	var cz := (gmin.z + gmax.z) / 2
	# Path cross
	brush.fill_box(
		Vector3i(cx, ground_y, gmin.z),
		Vector3i(cx + 1, ground_y + 1, gmax.z),
		VoxelMaterial.GRAVEL
	)
	brush.fill_box(
		Vector3i(gmin.x, ground_y, cz),
		Vector3i(gmax.x, ground_y + 1, cz + 1),
		VoxelMaterial.GRAVEL
	)
	brush.set_vox(Vector3i(cx, ground_y + 1, cz), VoxelMaterial.PLANTER)
	brush.set_vox(Vector3i(cx, ground_y + 2, cz), VoxelMaterial.LEAVES)
	_stamper().plant_random(cx - 2, ground_y, cz - 2)


func _lawn(min_v: Vector3i, max_v: Vector3i) -> void:
	brush.fill_box(min_v, max_v, VoxelMaterial.DIRT)
	brush.fill_box(min_v, max_v, VoxelMaterial.PARK)


## Meandering promenade across the long axis. Returns the centre line so plantings and
## benches can follow it. Entry x for along_x paths, entry z otherwise.
func _curved_path(
	min_v: Vector3i, max_v: Vector3i, along_x: bool, width: int, phase_offset: float
) -> PackedInt32Array:
	var centers := PackedInt32Array()
	var phase := rng.randf() * TAU + phase_offset
	var span := float(max_v.z - min_v.z) if along_x else float(max_v.x - min_v.x)
	var amp := span * 0.13
	var run := (max_v.x - min_v.x) if along_x else (max_v.z - min_v.z)
	var mid := float(min_v.z + max_v.z) * 0.5 if along_x else float(min_v.x + max_v.x) * 0.5
	centers.resize(run)
	for i in range(run):
		var t := float(i)
		var c := mid + sin(t * 0.042 + phase) * amp + sin(t * 0.015 + phase * 1.7) * amp * 0.45
		var ci := int(round(c))
		centers[i] = ci
		var lo := ci - width / 2
		for k in range(width):
			var cross := lo + k
			if along_x:
				if cross <= min_v.z or cross >= max_v.z - 1:
					continue
				brush.set_vox(Vector3i(min_v.x + i, ground_y, cross), VoxelMaterial.GRAVEL)
			else:
				if cross <= min_v.x or cross >= max_v.x - 1:
					continue
				brush.set_vox(Vector3i(cross, ground_y, min_v.z + i), VoxelMaterial.GRAVEL)
	return centers


func _loop_path(min_v: Vector3i, max_v: Vector3i) -> void:
	## Strolling loop just inside the border — gives the park an edge to read against
	## the surrounding sidewalk instead of a lawn that stops mid-air.
	var x0 := min_v.x + LOOP_INSET
	var z0 := min_v.z + LOOP_INSET
	var x1 := max_v.x - LOOP_INSET
	var z1 := max_v.z - LOOP_INSET
	if x1 - x0 < LOOP_W * 3 or z1 - z0 < LOOP_W * 3:
		return
	brush.fill_box(Vector3i(x0, ground_y, z0), Vector3i(x1, ground_y + 1, z0 + LOOP_W), VoxelMaterial.GRAVEL)
	brush.fill_box(Vector3i(x0, ground_y, z1 - LOOP_W), Vector3i(x1, ground_y + 1, z1), VoxelMaterial.GRAVEL)
	brush.fill_box(Vector3i(x0, ground_y, z0), Vector3i(x0 + LOOP_W, ground_y + 1, z1), VoxelMaterial.GRAVEL)
	brush.fill_box(Vector3i(x1 - LOOP_W, ground_y, z0), Vector3i(x1, ground_y + 1, z1), VoxelMaterial.GRAVEL)


func _simple_path(min_v: Vector3i, max_v: Vector3i) -> void:
	var cz := (min_v.z + max_v.z) / 2
	brush.fill_box(
		Vector3i(min_v.x, ground_y, cz),
		Vector3i(max_v.x, ground_y + 1, cz + 1),
		VoxelMaterial.GRAVEL
	)


## Pond scaled to the park (the old fixed 4 m puddle vanished in a 100 m park).
## Returns its voxel footprint, or an empty rect when no clear spot was found.
func _pond(min_v: Vector3i, max_v: Vector3i, along_x: bool) -> Rect2i:
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	var rx := clampi(int(float(w) * 0.15), 5, 24)
	var rz := clampi(int(float(d) * 0.17), 4, 18)
	## Wobble the outline so it does not read as a stamped ellipse.
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for _try in range(6):
		## Sit in one quadrant, off the promenade's own axis.
		var fx := 0.3 if rng.randf() < 0.5 else 0.7
		var fz := 0.28 if rng.randf() < 0.5 else 0.72
		if along_x:
			fx = rng.randf() * 0.4 + 0.15 if rng.randf() < 0.5 else rng.randf() * 0.4 + 0.45
		var cx := min_v.x + int(float(w) * fx)
		var cz := min_v.z + int(float(d) * fz)
		var cells := _pond_cells(min_v, max_v, cx, cz, rx, rz, p1, p2)
		if cells.is_empty():
			continue
		var blocked := 0
		for c: Vector3i in cells:
			if brush.get_vox(c) != VoxelMaterial.PARK:
				blocked += 1
		## A pond that swallows a walkway looks like a bug, so retry elsewhere.
		if float(blocked) / float(cells.size()) > 0.04:
			continue
		for c2: Vector3i in cells:
			brush.set_vox(c2, VoxelMaterial.WATER)
		_pond_rim(min_v, max_v, cx, cz, rx, rz, p1, p2)
		return Rect2i(cx - rx, cz - rz, rx * 2, rz * 2)
	return Rect2i()


func _pond_cells(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, rx: int, rz: int, p1: float, p2: float
) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(cz - rz - 1, cz + rz + 2):
		for x in range(cx - rx - 1, cx + rx + 2):
			if x < min_v.x + 3 or z < min_v.z + 3 or x >= max_v.x - 3 or z >= max_v.z - 3:
				return []
			if _pond_norm(x, z, cx, cz, rx, rz, p1, p2) > 1.0:
				continue
			out.append(Vector3i(x, ground_y, z))
	return out


func _pond_rim(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, rx: int, rz: int, p1: float, p2: float
) -> void:
	for z in range(cz - rz - 2, cz + rz + 3):
		for x in range(cx - rx - 2, cx + rx + 3):
			if x < min_v.x + 2 or z < min_v.z + 2 or x >= max_v.x - 2 or z >= max_v.z - 2:
				continue
			var n := _pond_norm(x, z, cx, cz, rx, rz, p1, p2)
			if n <= 1.0 or n > 1.4:
				continue
			if brush.get_vox(Vector3i(x, ground_y, z)) != VoxelMaterial.PARK:
				continue
			brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.STONE)


func _pond_norm(
	x: int, z: int, cx: int, cz: int, rx: int, rz: int, p1: float, p2: float
) -> float:
	var nx := float(x - cx) / float(rx)
	var nz := float(z - cz) / float(rz)
	var a := atan2(nz, nx)
	var wobble := 1.0 + 0.16 * sin(3.0 * a + p1) + 0.1 * sin(5.0 * a + p2)
	return (nx * nx + nz * nz) / (wobble * wobble)


func _pond_approach(min_v: Vector3i, max_v: Vector3i, pond: Rect2i, along_x: bool) -> void:
	## Short spur from the loop path to the water's edge, plus a gravel overlook.
	if pond.size.x <= 0:
		return
	var cx := pond.position.x + pond.size.x / 2
	var cz := pond.position.y + pond.size.y / 2
	if along_x:
		var near_top := cz < (min_v.z + max_v.z) / 2
		var z_loop := min_v.z + LOOP_INSET + LOOP_W if near_top else max_v.z - LOOP_INSET - LOOP_W
		var z_shore := cz - pond.size.y / 2 - 2 if near_top else cz + pond.size.y / 2 + 2
		_spur_z(cx, mini(z_loop, z_shore), maxi(z_loop, z_shore))
	else:
		var near_left := cx < (min_v.x + max_v.x) / 2
		var x_loop := min_v.x + LOOP_INSET + LOOP_W if near_left else max_v.x - LOOP_INSET - LOOP_W
		var x_shore := cx - pond.size.x / 2 - 2 if near_left else cx + pond.size.x / 2 + 2
		_spur_x(cz, mini(x_loop, x_shore), maxi(x_loop, x_shore))


func _spur_z(x: int, z_from: int, z_to: int) -> void:
	for z in range(z_from, z_to + 1):
		for k in range(-1, 2):
			_pave_if_lawn(Vector3i(x + k, ground_y, z))


func _spur_x(z: int, x_from: int, x_to: int) -> void:
	for x in range(x_from, x_to + 1):
		for k in range(-1, 2):
			_pave_if_lawn(Vector3i(x, ground_y, z + k))


func _pave_if_lawn(p: Vector3i) -> void:
	if brush.get_vox(p) != VoxelMaterial.PARK:
		return
	brush.set_vox(p, VoxelMaterial.GRAVEL)


func _grove(min_v: Vector3i, max_v: Vector3i, count: int) -> void:
	for _i in range(count):
		var x := rng.randi_range(min_v.x + 2, max_v.x - 3)
		var z := rng.randi_range(min_v.z + 2, max_v.z - 3)
		if brush.get_vox(Vector3i(x, ground_y, z)) == VoxelMaterial.WATER:
			continue
		_stamper().plant_random(x, ground_y, z)


func _allee(
	min_v: Vector3i, max_v: Vector3i, centers: PackedInt32Array, along_x: bool
) -> void:
	## Formal tree rows flanking the promenade, following its curve. Spacing keeps the
	## crowns apart — closer together they merged into one canopy roof over the path.
	var step := 11
	var off := PROMENADE_W / 2 + 3
	var i := 4
	while i < centers.size() - 4:
		var c := centers[i]
		var sides := PackedInt32Array([-off, off])
		for side in sides:
			var x: int = min_v.x + i if along_x else c + side
			var z: int = c + side if along_x else min_v.z + i
			if x < min_v.x + 2 or z < min_v.z + 2 or x >= max_v.x - 2 or z >= max_v.z - 2:
				continue
			if not _is_plantable(x, z):
				continue
			_stamper().tall_tree(x, ground_y, z)
		i += step


func _groves(min_v: Vector3i, max_v: Vector3i) -> void:
	## Clustered planting: a handful of grove centres with a scatter of mixed trees
	## around each, so the lawn reads as landscaping instead of evenly spread dots.
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	var clusters := clampi((w * d) / 1100, 3, 14)
	for _c in range(clusters):
		var gx := rng.randi_range(min_v.x + 5, max_v.x - 6)
		var gz := rng.randi_range(min_v.z + 5, max_v.z - 6)
		var spread := rng.randi_range(4, 9)
		var trees := rng.randi_range(3, 7)
		## Worn earth under the canopy — breaks the uniform green.
		for z in range(gz - spread / 2, gz + spread / 2 + 1):
			for x in range(gx - spread / 2, gx + spread / 2 + 1):
				if brush.get_vox(Vector3i(x, ground_y, z)) != VoxelMaterial.PARK:
					continue
				if rng.randf() < 0.35:
					brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.DIRT)
		for _t in range(trees):
			var tx := gx + rng.randi_range(-spread, spread)
			var tz := gz + rng.randi_range(-spread, spread)
			if tx < min_v.x + 2 or tz < min_v.z + 2 or tx >= max_v.x - 2 or tz >= max_v.z - 2:
				continue
			if not _is_plantable(tx, tz):
				continue
			_stamper().plant_random(tx, ground_y, tz)


func _edge_planting(min_v: Vector3i, max_v: Vector3i) -> void:
	## Hedge band around the border with gaps where paths reach the street, so the park
	## has a frame instead of a lawn that simply stops.
	var y0 := ground_y
	var inset := 2
	for x in range(min_v.x + inset, max_v.x - inset):
		_hedge_run(x, min_v.z + inset, y0)
		_hedge_run(x, max_v.z - inset - 1, y0)
	for z in range(min_v.z + inset, max_v.z - inset):
		_hedge_run(min_v.x + inset, z, y0)
		_hedge_run(max_v.x - inset - 1, z, y0)


func _hedge_run(x: int, z: int, y0: int) -> void:
	if not _is_plantable(x, z):
		return
	## Broken line, not a wall: leave roughly a fifth of the run open.
	if rng.randf() < 0.2:
		return
	brush.set_vox(Vector3i(x, y0 + 1, z), VoxelMaterial.LEAVES)
	if rng.randf() < 0.55:
		brush.set_vox(Vector3i(x, y0 + 2, z), VoxelMaterial.LEAVES)


func _flower_beds(min_v: Vector3i, max_v: Vector3i) -> void:
	## A few real beds beside the walkways, replacing the old lattice of 300 identical
	## planter boxes that read as scattered crates.
	var target := clampi((max_v.x - min_v.x) * (max_v.z - min_v.z) / 2600, 3, 9)
	var made := 0
	var tries := 0
	while made < target and tries < 120:
		tries += 1
		var bw := rng.randi_range(4, 9)
		var bd := rng.randi_range(2, 3)
		if rng.randf() < 0.5:
			var swap := bw
			bw = bd
			bd = swap
		var x0 := rng.randi_range(min_v.x + 4, max_v.x - 5 - bw)
		var z0 := rng.randi_range(min_v.z + 4, max_v.z - 5 - bd)
		if not _area_is_lawn(x0, z0, bw, bd):
			continue
		if not _near_path(x0, z0, bw, bd):
			continue
		var y0 := ground_y
		brush.fill_box(
			Vector3i(x0, y0 + 1, z0), Vector3i(x0 + bw, y0 + 2, z0 + bd), VoxelMaterial.PLANTER
		)
		var bloom := VoxelMaterial.PAINT if rng.randf() < 0.6 else VoxelMaterial.LEAVES
		brush.fill_box(
			Vector3i(x0, y0 + 2, z0), Vector3i(x0 + bw, y0 + 3, z0 + bd), bloom
		)
		made += 1


func _benches(
	min_v: Vector3i, max_v: Vector3i, centers: PackedInt32Array, along_x: bool
) -> void:
	var step := 17
	var off := PROMENADE_W / 2 + 1
	var i := 9
	while i < centers.size() - 9:
		var c := centers[i]
		var side := off if (i / step) % 2 == 0 else -off
		var x := min_v.x + i if along_x else c + side
		var z := c + side if along_x else min_v.z + i
		if x < min_v.x + 3 or z < min_v.z + 3 or x >= max_v.x - 4 or z >= max_v.z - 4:
			i += step
			continue
		## A promenade bench is a real seat now, turned to face the path it stands beside.
		var stem := "benchStone_z" if along_x else "benchStone"
		var size := RoomPropCatalog.size_of_stem(stem)
		if _area_is_lawn(x, z, size.x, size.z):
			RoomPropKit.stamp_brush(brush, Vector3i(x, ground_y + 1, z), stem)
		i += step


## One corner of a big park is laid out formally — the same parterre the castle gets, so
## the walk through a park ends somewhere composed instead of in more scattered lawn.
func _formal_quarter(min_v: Vector3i, max_v: Vector3i) -> void:
	var side := mini(
		FORMAL_SIDE_MAX,
		mini(max_v.x - min_v.x, max_v.z - min_v.z) / 2 - FORMAL_INSET
	)
	if side < FORMAL_SIDE_MIN:
		return
	## Try each corner: the pond and the promenade have already claimed their ground, and
	## turfing over either would undo them.
	var corners: Array[Vector2i] = [
		Vector2i(min_v.x + FORMAL_INSET, min_v.z + FORMAL_INSET),
		Vector2i(max_v.x - FORMAL_INSET - side, min_v.z + FORMAL_INSET),
		Vector2i(min_v.x + FORMAL_INSET, max_v.z - FORMAL_INSET - side),
		Vector2i(max_v.x - FORMAL_INSET - side, max_v.z - FORMAL_INSET - side),
	]
	var first := rng.randi() % corners.size()
	for i in range(corners.size()):
		var at: Vector2i = corners[(first + i) % corners.size()]
		if not _area_is_lawn(at.x, at.y, side, side):
			continue
		if garden == null:
			garden = GardenComposer.new()
			garden.brush = brush
			garden.rng = rng
			garden.stamper = _stamper()
		garden.compose(
			Rect2i(at.x, at.y, side, side), ground_y, GardenComposer.Style.PARTERRE
		)
		return


## A rare stone bandstand on the lawn. Rolled once per large park and skipped outright when the
## park is small or the good ground is already spoken for by the pond, promenade or parterre.
func _gazebo(min_v: Vector3i, max_v: Vector3i) -> void:
	if gazebo_center.x >= 0:
		## One to a district. A second would make the first stop being a landmark.
		return
	if max_v.x - min_v.x < GAZEBO_PARK_MIN or max_v.z - min_v.z < GAZEBO_PARK_MIN:
		return
	if rng.randi_range(1, 100) > GAZEBO_CHANCE_PCT:
		return
	var side := GAZEBO_HALF * 2 + 1
	for _try in range(12):
		var x0 := rng.randi_range(
			min_v.x + GAZEBO_INSET, maxi(min_v.x + GAZEBO_INSET, max_v.x - GAZEBO_INSET - side)
		)
		var z0 := rng.randi_range(
			min_v.z + GAZEBO_INSET, maxi(min_v.z + GAZEBO_INSET, max_v.z - GAZEBO_INSET - side)
		)
		if not _area_is_lawn(x0, z0, side, side):
			continue
		_build_gazebo(Vector2i(x0 + GAZEBO_HALF, z0 + GAZEBO_HALF))
		return


func _build_gazebo(centre: Vector2i) -> void:
	var deck_y := ground_y + GAZEBO_DECK_RISE
	var rim: Array[Vector2i] = []
	for dz in range(-GAZEBO_HALF, GAZEBO_HALF + 1):
		for dx in range(-GAZEBO_HALF, GAZEBO_HALF + 1):
			## Chamfered corners: a square bandstand looks like a shed, an octagon looks built.
			if absi(dx) + absi(dz) > GAZEBO_HALF * 2 - GAZEBO_CHAMFER:
				continue
			var x := centre.x + dx
			var z := centre.y + dz
			brush.fill_box(
				Vector3i(x, ground_y, z), Vector3i(x + 1, deck_y + 1, z + 1), VoxelMaterial.STONE
			)
			brush.set_vox(Vector3i(x, deck_y, z), VoxelMaterial.TILES)
			if maxi(absi(dx), absi(dz)) == GAZEBO_HALF:
				rim.append(Vector2i(dx, dz))
	## One step on the south face, so the deck is walked onto rather than jumped onto.
	for sx in range(-1, 2):
		brush.set_vox(
			Vector3i(centre.x + sx, ground_y, centre.y + GAZEBO_HALF + 1), VoxelMaterial.STONE
		)
	var column_top := deck_y + GAZEBO_COLUMN_H
	for offset: Vector2i in rim:
		if not _gazebo_column_at(offset):
			continue
		brush.fill_box(
			Vector3i(centre.x + offset.x, deck_y + 1, centre.y + offset.y),
			Vector3i(centre.x + offset.x + 1, column_top + 1, centre.y + offset.y + 1),
			VoxelMaterial.STONE
		)
	_build_gazebo_roof(centre, column_top)
	gazebo_center = Vector3i(centre.x, deck_y, centre.y)


## Two posts per face, parked at the ends — the middle of every side stays a walkable door.
func _gazebo_column_at(offset: Vector2i) -> bool:
	var ax := absi(offset.x)
	var az := absi(offset.y)
	var on_ns := az == GAZEBO_HALF and ax < GAZEBO_HALF
	var on_ew := ax == GAZEBO_HALF and az < GAZEBO_HALF
	if not on_ns and not on_ew:
		return false
	var along := ax if on_ns else az
	return along == GAZEBO_HALF - GAZEBO_POST_INSET


## Stepped clay cone over the columns, narrowing a ring at a time to a finial.
func _build_gazebo_roof(centre: Vector2i, column_top: int) -> void:
	var y := column_top + 1
	var half := GAZEBO_HALF
	for step in range(GAZEBO_ROOF_H):
		for dz in range(-half, half + 1):
			for dx in range(-half, half + 1):
				if absi(dx) + absi(dz) > half * 2 - GAZEBO_CHAMFER:
					continue
				brush.set_vox(
					Vector3i(centre.x + dx, y, centre.y + dz), VoxelMaterial.ROOF_CLAY
				)
		y += 1
		half -= 1
		if half < 1:
			break
	brush.set_vox(Vector3i(centre.x, y, centre.y), VoxelMaterial.METAL)


func _is_plantable(x: int, z: int) -> bool:
	## Lawn or bare earth: keeps paths, water and stone rims clear without extra bookkeeping.
	var id := brush.get_vox(Vector3i(x, ground_y, z))
	return id == VoxelMaterial.PARK or id == VoxelMaterial.DIRT


func _area_is_lawn(x0: int, z0: int, w: int, d: int) -> bool:
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if not _is_plantable(x, z):
				return false
	return true


func _near_path(x0: int, z0: int, w: int, d: int) -> bool:
	for z in range(z0 - 2, z0 + d + 2):
		for x in range(x0 - 2, x0 + w + 2):
			if brush.get_vox(Vector3i(x, ground_y, z)) == VoxelMaterial.GRAVEL:
				return true
	return false


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Cheap far-tile greens: lawn already painted; drop a few canopy blobs only.
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 8 or d < 8:
		return
	var count := clampi((w * d) / 220, 2, 7)
	for _i in range(count):
		var x := rng.randi_range(min_v.x + 2, max_v.x - 3)
		var z := rng.randi_range(min_v.z + 2, max_v.z - 3)
		_stamper().round_tree(x, ground_y, z)
