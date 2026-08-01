## Sculpts a Graveyard-theme district: elevated consecrated yard, hedge, chapel,
## graves / mausoleums, and shallow catacombs carved into the raised fill.
##
## Edge arterial stubs stay at street level (see DistrictPlanner). Paths climb the
## terraced approaches through hedge gates; the yard deck sits high enough that a
## crypt network fits under it without touching the world floor slab.
class_name GraveyardComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var stamper: TreeStamper
var planner: DistrictPlanner
var cell_size: int = 28


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper

## Yard height above the street deck — room for walkable catacombs underneath.
const YARD_RISE := 8
## Walkable approaches: one voxel of rise per horizontal voxel.
const RAMP_SLOPE := 1.0
## How far the flat yard pulls in from roads / tile edges before it is full height.
const VERGE := 4
## Hedge wall height above the yard deck.
const HEDGE_H := 5
## Approach path half-width in voxels (ramps and gate runs).
const PATH_HW := 1
## Plot lattice: cinder aisles every PLOT_PITCH voxels, kerbed blocks between them.
## Everything is snapped to this grid so rows read as rows from any angle.
const PLOT_PITCH := 20
## Half-width of a plot aisle, and of the processional aisles through the chapel.
const AISLE_HW := 1
const AISLE_MAIN_HW := 2
## One burial slot: 3 wide, 5 deep (headstone band + mound + walking margin).
const GRAVE_SLOT_W := 3
const GRAVE_SLOT_D := 5
## Monument kinds, chosen per grave slot.
const GRAVE_TABLET := 0
const GRAVE_CROSS := 1
const GRAVE_OBELISK := 2
const GRAVE_CHEST := 3
const GRAVE_STELE := 4
const GRAVE_RUINED := 5
## What a plot block is used for.
const BLOCK_GRAVES := 0
const BLOCK_MAUSOLEUM := 1
const BLOCK_MONUMENT := 2
const BLOCK_GROVE := 3
## Built crypts: fixed clear height (air voxels) and corridor half-width.
## Walker crown needs ~6 air; keep one extra for lintels.
const CRYPT_H := 7
const CRYPT_CORRIDOR_HW := 1
## Rock kept between crypt air and the yard surface / mound skin.
const CRYPT_SHELL := 2

var _ox: int = 0
var _oz: int = 0
var _w: int = 0
var _d: int = 0
## Distance to nearest road or region border.
var _clearance: PackedFloat32Array = PackedFloat32Array()
## Fill height above the street deck.
var _height: PackedInt32Array = PackedInt32Array()
## Path footprint (1 = path column).
var _path: PackedByteArray = PackedByteArray()
## Anything a prop already claimed, so trees never grow out of a headstone.
var _taken: PackedByteArray = PackedByteArray()
## Flat deck mask, eroded in from the mound rim (1 = plantable yard).
var _yard: PackedByteArray = PackedByteArray()
## Aisle centre lines and the plot blocks they enclose.
var _aisle_x: PackedInt32Array = PackedInt32Array()
var _aisle_z: PackedInt32Array = PackedInt32Array()
var _blocks: Array[Rect2i] = []
var _graves: int = 0
## Columns opened by the crypt carve.
var _crypt_lo: PackedInt32Array = PackedInt32Array()
var _crypt_hi: PackedInt32Array = PackedInt32Array()
var _chapel: Vector3i = Vector3i.ZERO
## Side chambers of the catacombs in district-local voxels (x, floor Y, z). The hub under the
## chapel stair is deliberately left out — the first room off the steps is not a find.
var crypt_rooms: Array[Vector3i] = []


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	_build_clearance()
	_build_heightfield()
	_paint_mound()
	_lay_out_aisles()
	_link_road_stubs()
	_paint_paths()
	_build_hedge()
	_build_chapel()
	_build_gate_piers()
	_plant_avenue()
	_dress_blocks()
	_plant_trees(1.0)
	_carve_catacombs()
	_dress_catacombs()
	print(
		(
			"GraveyardComposer: yard rise=%d chapel=(%d,%d) aisles=%dx%d blocks=%d"
			+ " graves=%d path cols=%d crypt air cols=%d"
		)
		% [
			_yard_rise_at_center(),
			_chapel.x,
			_chapel.z,
			_aisle_x.size(),
			_aisle_z.size(),
			_blocks.size(),
			_graves,
			_path_count(),
			_crypt_column_count(),
		]
	)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	_build_clearance()
	_build_heightfield()
	_paint_mound()
	_build_yard_mask()
	_build_chapel()
	_plant_trees(0.18)


func _begin(min_v: Vector3i, max_v: Vector3i) -> bool:
	if rng == null or brush == null:
		push_error("GraveyardComposer: brush / rng not set")
		return false
	if planner == null:
		push_error("GraveyardComposer: planner not set")
		return false
	_ox = min_v.x
	_oz = min_v.z
	_w = max_v.x - min_v.x
	_d = max_v.z - min_v.z
	if _w < 64 or _d < 64:
		push_error("GraveyardComposer: region %dx%d is too small" % [_w, _d])
		return false
	_clearance.resize(_w * _d)
	_height.resize(_w * _d)
	_path.resize(_w * _d)
	_path.fill(0)
	_taken.resize(_w * _d)
	_taken.fill(0)
	_blocks.clear()
	_graves = 0
	_crypt_lo.resize(_w * _d)
	_crypt_hi.resize(_w * _d)
	_crypt_lo.fill(-1)
	_crypt_hi.fill(-1)
	crypt_rooms.clear()
	_chapel = Vector3i(_w / 2, ground_y + YARD_RISE, _d / 2)
	return true


func _build_clearance() -> void:
	const FAR := 1.0e9
	for z in range(_d):
		for x in range(_w):
			var edge := x == 0 or z == 0 or x == _w - 1 or z == _d - 1
			_clearance[z * _w + x] = 0.0 if (edge or _is_road_cell(x, z)) else FAR
	for z in range(_d):
		for x in range(_w):
			var i := z * _w + x
			var v := _clearance[i]
			if v == 0.0:
				continue
			if x > 0:
				v = minf(v, _clearance[i - 1] + 1.0)
			if z > 0:
				v = minf(v, _clearance[i - _w] + 1.0)
			if x > 0 and z > 0:
				v = minf(v, _clearance[i - _w - 1] + 1.4142)
			if x < _w - 1 and z > 0:
				v = minf(v, _clearance[i - _w + 1] + 1.4142)
			_clearance[i] = v
	for z2 in range(_d - 1, -1, -1):
		for x2 in range(_w - 1, -1, -1):
			var i2 := z2 * _w + x2
			var v2 := _clearance[i2]
			if v2 == 0.0:
				continue
			if x2 < _w - 1:
				v2 = minf(v2, _clearance[i2 + 1] + 1.0)
			if z2 < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w] + 1.0)
			if x2 < _w - 1 and z2 < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w + 1] + 1.4142)
			if x2 > 0 and z2 < _d - 1:
				v2 = minf(v2, _clearance[i2 + _w - 1] + 1.4142)
			_clearance[i2] = v2


## Flat elevated pad with 1-voxel terraces climbing out from every road stub.
func _build_heightfield() -> void:
	for z in range(_d):
		for x in range(_w):
			var c := _clearance[z * _w + x]
			if c <= float(VERGE):
				_height[z * _w + x] = 0
				continue
			var rise := int(floor((c - float(VERGE)) * RAMP_SLOPE))
			_height[z * _w + x] = clampi(rise, 0, YARD_RISE)
	## Smooth so neighbouring columns never jump more than one voxel (walkable).
	for _pass in range(3):
		for z2 in range(1, _d - 1):
			for x2 in range(1, _w - 1):
				var i := z2 * _w + x2
				var h := _height[i]
				var lo := h
				lo = mini(lo, _height[i - 1] + 1)
				lo = mini(lo, _height[i + 1] + 1)
				lo = mini(lo, _height[i - _w] + 1)
				lo = mini(lo, _height[i + _w] + 1)
				_height[i] = lo


func _paint_mound() -> void:
	for z in range(_d):
		var row := z * _w
		for x in range(_w):
			var h := _height[row + x]
			if h <= 0:
				## Sour verge outside the wall: bald subsoil scabs over the turned earth.
				if not _is_road_cell(x, z) and rng.randf() < 0.3:
					brush.set_vox(Vector3i(_ox + x, ground_y, _oz + z), VoxelMaterial.DIRT)
				continue
			var wx := _ox + x
			var wz := _oz + z
			for dy in range(h):
				var y := ground_y + 1 + dy
				var mat := VoxelMaterial.STONE
				if dy >= h - 1:
					mat = VoxelMaterial.GRAVE_SOIL
				elif dy >= h - 3:
					mat = VoxelMaterial.DIRT
				elif dy < 2:
					mat = VoxelMaterial.STONE
				else:
					## Dressed courses in the retaining flank so the mound reads as built.
					mat = VoxelMaterial.GRAVE_STONE if (dy % 4) == 0 else VoxelMaterial.STONE
				brush.set_vox(Vector3i(wx, y, wz), mat)
			## Moss creeping over the consecrated ground.
			if h >= YARD_RISE and rng.randf() < 0.12:
				brush.set_vox(Vector3i(wx, ground_y + h, wz), VoxelMaterial.YEW)


## Aisle lattice anchored on the chapel: a 5-wide processional cross plus 3-wide
## plot aisles every PLOT_PITCH voxels. Graves only ever go in the kerbed blocks
## between them, which is what makes the rows and the paths read from the ground.
func _lay_out_aisles() -> void:
	_build_yard_mask()
	_aisle_x = _lattice_lines(_chapel.x, _w)
	_aisle_z = _lattice_lines(_chapel.z, _d)
	for lx: int in _aisle_x:
		var hw := _aisle_hw(lx, _chapel.x)
		for z in range(_d):
			for dx in range(-hw, hw + 1):
				_mark_aisle(lx + dx, z)
	for lz: int in _aisle_z:
		var hwz := _aisle_hw(lz, _chapel.z)
		for x in range(_w):
			for dz in range(-hwz, hwz + 1):
				_mark_aisle(x, lz + dz)
	for i in range(_aisle_x.size() - 1):
		var x0 := _aisle_x[i] + _aisle_hw(_aisle_x[i], _chapel.x) + 1
		var x1 := _aisle_x[i + 1] - _aisle_hw(_aisle_x[i + 1], _chapel.x) - 1
		if x1 - x0 + 1 < GRAVE_SLOT_W or x1 < 0 or x0 >= _w:
			continue
		for j in range(_aisle_z.size() - 1):
			var z0 := _aisle_z[j] + _aisle_hw(_aisle_z[j], _chapel.z) + 1
			var z1 := _aisle_z[j + 1] - _aisle_hw(_aisle_z[j + 1], _chapel.z) - 1
			if z1 - z0 + 1 < GRAVE_SLOT_D or z1 < 0 or z0 >= _d:
				continue
			_blocks.append(Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1))


## Lines through `center` at PLOT_PITCH spacing, one past each end so the strips
## along the hedge are still enclosed blocks.
func _lattice_lines(center: int, extent: int) -> PackedInt32Array:
	var first := center
	while first > -PLOT_PITCH:
		first -= PLOT_PITCH
	var lines := PackedInt32Array()
	var v := first
	while v < extent + PLOT_PITCH:
		lines.append(v)
		v += PLOT_PITCH
	return lines


func _aisle_hw(line: int, main: int) -> int:
	return AISLE_MAIN_HW if line == main else AISLE_HW


## The flat deck, pulled 3 voxels in from the mound rim so aisles and rows never
## run into the hedge or spill down the terraces.
func _build_yard_mask() -> void:
	_yard.resize(_w * _d)
	for i in range(_w * _d):
		_yard[i] = 1 if _height[i] >= YARD_RISE else 0
	for _pass in range(3):
		var prev := _yard.duplicate()
		for z in range(_d):
			var row := z * _w
			for x in range(_w):
				if prev[row + x] == 0:
					continue
				if x == 0 or z == 0 or x == _w - 1 or z == _d - 1:
					_yard[row + x] = 0
					continue
				if (
					prev[row + x - 1] == 0
					or prev[row + x + 1] == 0
					or prev[row - _w + x] == 0
					or prev[row + _w + x] == 0
				):
					_yard[row + x] = 0


func _mark_aisle(x: int, z: int) -> void:
	if x < 0 or z < 0 or x >= _w or z >= _d:
		return
	if _yard[z * _w + x] == 0:
		return
	_path[z * _w + x] = 1


## Straight approaches from each edge stub up the terraces to the nearest aisle.
## These are the only cells allowed to breach the hedge, so each one is a gate.
func _link_road_stubs() -> void:
	var starts := _stub_tips()
	if starts.is_empty():
		starts.append(Vector2i(4, _d / 2))
		starts.append(Vector2i(_w - 5, _d / 2))
	for start: Vector2i in starts:
		var goal := _nearest_aisle_cell(start)
		if goal.x < 0:
			continue
		_trace_approach(start, goal)


func _stub_tips() -> Array[Vector2i]:
	var tips: Array[Vector2i] = []
	for z in range(_d):
		for x in range(_w):
			if not _is_road_cell(x, z):
				continue
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var nx := x + step.x
				var nz := z + step.y
				if nx < 0 or nz < 0 or nx >= _w or nz >= _d:
					continue
				if _is_road_cell(nx, nz):
					continue
				if _height[nz * _w + nx] <= 0:
					continue
				var tip := Vector2i(nx, nz)
				var ok := true
				for s: Vector2i in tips:
					if tip.distance_squared_to(s) < 12 * 12:
						ok = false
						break
				if ok:
					tips.append(tip)
				break
	return tips


func _nearest_aisle_cell(from_xz: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in range(_d):
		var row := z * _w
		for x in range(_w):
			if _path[row + x] != 1:
				continue
			var dx := x - from_xz.x
			var dz := z - from_xz.y
			var dist := dx * dx + dz * dz
			if dist < best_d:
				best_d = dist
				best = Vector2i(x, z)
	return best


func _trace_approach(from_xz: Vector2i, to_xz: Vector2i) -> void:
	var x := from_xz.x
	var z := from_xz.y
	_stamp_path(x, z, 2)
	## One axis at a time — a churchyard walk is laid out, not worn in.
	while x != to_xz.x:
		x += 1 if to_xz.x > x else -1
		_stamp_path(x, z, 2)
	while z != to_xz.y:
		z += 1 if to_xz.y > z else -1
		_stamp_path(x, z, 2)


func _stamp_path(x: int, z: int, kind: int) -> void:
	for dz in range(-PATH_HW, PATH_HW + 1):
		for dx in range(-PATH_HW, PATH_HW + 1):
			var px := x + dx
			var pz := z + dz
			if px < 0 or pz < 0 or px >= _w or pz >= _d:
				continue
			if _height[pz * _w + px] <= 0:
				continue
			_path[pz * _w + px] = kind


func _paint_paths() -> void:
	for z in range(_d):
		var row := z * _w
		for x in range(_w):
			if _path[row + x] == 0:
				continue
			var h := _height[row + x]
			var y := ground_y + maxi(h, 0)
			brush.set_vox(Vector3i(_ox + x, y, _oz + z), VoxelMaterial.GRAVE_PATH)


## Clipped yew ring around the flat yard. Only gate approaches (path kind 2) breach
## it — the interior aisle lattice stops short of the rim so the ring stays closed.
func _build_hedge() -> void:
	for z in range(1, _d - 1):
		var row := z * _w
		for x in range(1, _w - 1):
			if _height[row + x] < YARD_RISE:
				continue
			var edge := (
				_height[row + x - 1] < YARD_RISE
				or _height[row + x + 1] < YARD_RISE
				or _height[row - _w + x] < YARD_RISE
				or _height[row + _w + x] < YARD_RISE
			)
			if not edge:
				continue
			if _near_gate(x, z, 2):
				continue
			var wx := _ox + x
			var wz := _oz + z
			var base := ground_y + YARD_RISE + 1
			## Two voxels thick so the ring reads from the approaches, not just overhead.
			for oz in range(-1, 1):
				for ox in range(-1, 1):
					var hx := x + ox
					var hz := z + oz
					if hx < 0 or hz < 0 or hx >= _w or hz >= _d:
						continue
					if _path[hz * _w + hx] == 2:
						continue
					if _height_at(hx, hz) < YARD_RISE:
						continue
					_taken[hz * _w + hx] = 1
					for dy in range(HEDGE_H):
						brush.set_vox(Vector3i(wx + ox, base + dy, wz + oz), VoxelMaterial.YEW)


func _near_gate(x: int, z: int, radius: int) -> bool:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= _w or nz >= _d:
				continue
			if _path[nz * _w + nx] == 2:
				return true
	return false


## Dressed piers with iron finials and a lintel wherever a walk breaches the hedge.
func _build_gate_piers() -> void:
	var gates: Array[Vector2i] = []
	for z in range(2, _d - 2):
		var row := z * _w
		for x in range(2, _w - 2):
			if _path[row + x] != 2:
				continue
			if _height[row + x] < YARD_RISE:
				continue
			## The gate cell is the last full-height walk before the terraces drop.
			if not (
				_height[row + x - 1] < YARD_RISE
				or _height[row + x + 1] < YARD_RISE
				or _height[row - _w + x] < YARD_RISE
				or _height[row + _w + x] < YARD_RISE
			):
				continue
			var g := Vector2i(x, z)
			var ok := true
			for prev: Vector2i in gates:
				if g.distance_squared_to(prev) < 8 * 8:
					ok = false
					break
			if ok:
				gates.append(g)
	for gate: Vector2i in gates:
		_gate_piers_at(gate)


func _gate_piers_at(gate: Vector2i) -> void:
	## Piers straddle the walk, so their axis is perpendicular to the way out.
	var out := Vector2i.ZERO
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _height_at(gate.x + step.x, gate.y + step.y) < YARD_RISE:
			out = step
			break
	if out == Vector2i.ZERO:
		return
	var side := Vector2i(-out.y, out.x)
	var deck := ground_y + YARD_RISE
	var pier_h := HEDGE_H + 3
	for sign: int in [-1, 1]:
		var px := gate.x + side.x * 2 * sign
		var pz := gate.y + side.y * 2 * sign
		if _height_at(px, pz) < YARD_RISE:
			continue
		_taken[pz * _w + px] = 1
		var wx := _ox + px
		var wz := _oz + pz
		for dy in range(pier_h):
			brush.set_vox(Vector3i(wx, deck + 1 + dy, wz), VoxelMaterial.GRAVE_STONE)
		brush.set_vox(Vector3i(wx, deck + 1 + pier_h, wz), VoxelMaterial.GRAVE_MARBLE)
		brush.set_vox(Vector3i(wx, deck + 2 + pier_h, wz), VoxelMaterial.WROUGHT_IRON)
	## Iron lintel spanning the opening, high enough to walk under.
	var span_y := deck + pier_h
	for t in range(-1, 2):
		var lx := gate.x + side.x * t
		var lz := gate.y + side.y * t
		if _height_at(lx, lz) < YARD_RISE:
			continue
		brush.set_vox(Vector3i(_ox + lx, span_y, _oz + lz), VoxelMaterial.WROUGHT_IRON)


func _build_chapel() -> void:
	var cx := _chapel.x
	var cz := _chapel.z
	## Nudge chapel onto the flat yard if the geometric centre is still on a ramp.
	if _height_at(cx, cz) < YARD_RISE:
		for r in range(1, 40):
			var found := false
			for z in range(maxi(cz - r, 8), mini(cz + r + 1, _d - 8)):
				for x in range(maxi(cx - r, 8), mini(cx + r + 1, _w - 8)):
					if _height_at(x, z) >= YARD_RISE:
						cx = x
						cz = z
						found = true
						break
				if found:
					break
			if found:
				break
	_chapel = Vector3i(cx, ground_y + YARD_RISE, cz)
	var deck := ground_y + YARD_RISE
	var wx0 := _ox + cx - 10
	var wz0 := _oz + cz - 7
	var wx1 := _ox + cx + 11
	var wz1 := _oz + cz + 8
	## Clear footprint of graves / hedge leftovers.
	brush.fill_box(
		Vector3i(wx0 - 1, deck + 1, wz0 - 1),
		Vector3i(wx1 + 1, deck + 18, wz1 + 1),
		VoxelMaterial.AIR
	)
	## Dressed plinth.
	brush.fill_box(
		Vector3i(wx0, deck, wz0),
		Vector3i(wx1, deck + 1, wz1),
		VoxelMaterial.GRAVE_STONE
	)
	## Nave walls: rubble stone with dressed buttresses and lit lancet windows.
	var wall_top := deck + 11
	for z in range(wz0, wz1):
		for x in range(wx0, wx1):
			var edge := x == wx0 or x == wx1 - 1 or z == wz0 or z == wz1 - 1
			if not edge:
				continue
			## Door on the south face.
			if z == wz1 - 1 and absi(x - (_ox + cx)) <= 1:
				continue
			var long_wall := x == wx0 or x == wx1 - 1
			var pier := ((z - wz0) % 4 == 0) if long_wall else ((x - wx0) % 4 == 0)
			var lancet := (
				not pier
				and (((z - wz0) % 4 == 2) if long_wall else ((x - wx0) % 4 == 2))
				and z != wz1 - 1
			)
			for y in range(deck + 1, wall_top):
				## Dark rubble wall with lighter dressed quoins on the buttresses.
				var mat := VoxelMaterial.STONE if pier else VoxelMaterial.GRAVE_STONE
				if lancet and y >= deck + 4 and y <= deck + 7:
					mat = VoxelMaterial.GLASS_LIT
				brush.set_vox(Vector3i(x, y, z), mat)
	## Nave flagstones.
	brush.fill_box(
		Vector3i(wx0 + 1, deck + 1, wz0 + 1),
		Vector3i(wx1 - 1, deck + 2, wz1 - 1),
		VoxelMaterial.GRAVE_MARBLE
	)
	## Pitched roof ridge along X — solid fill under a 45° slope skin.
	var roof_peak := wall_top + 4
	var ridge_z := _oz + cz
	for z in range(wz0 - 1, wz1 + 1):
		for x in range(wx0 - 1, wx1 + 1):
			var dist := absi(z - ridge_z)
			var y_top := roof_peak - dist
			if y_top < wall_top:
				continue
			for y in range(wall_top, y_top):
				brush.set_vox(Vector3i(x, y, z), VoxelMaterial.ROOF)
			var skin := VoxelMaterial.ROOF
			if z < ridge_z:
				skin = VoxelMaterial.roof_slope(
					VoxelMaterial.ROOF, VoxelMaterial.SLOPE_HIGH_POS_Z
				)
			elif z > ridge_z:
				skin = VoxelMaterial.roof_slope(
					VoxelMaterial.ROOF, VoxelMaterial.SLOPE_HIGH_NEG_Z
				)
			brush.set_vox(Vector3i(x, y_top, z), skin)
	## Steeple on the north end.
	var sx := _ox + cx
	var sz := _oz + cz - 4
	brush.fill_box(
		Vector3i(sx - 2, deck + 1, sz - 2),
		Vector3i(sx + 3, roof_peak + 6, sz + 3),
		VoxelMaterial.GRAVE_STONE
	)
	brush.fill_box(
		Vector3i(sx - 1, roof_peak + 6, sz - 1),
		Vector3i(sx + 2, roof_peak + 10, sz + 2),
		VoxelMaterial.GRAVE_STONE
	)
	## Iron cross on the spire.
	var cross_y := roof_peak + 10
	for dy in range(4):
		brush.set_vox(Vector3i(sx, cross_y + dy, sz), VoxelMaterial.WROUGHT_IRON)
	brush.set_vox(Vector3i(sx - 1, cross_y + 2, sz), VoxelMaterial.WROUGHT_IRON)
	brush.set_vox(Vector3i(sx + 1, cross_y + 2, sz), VoxelMaterial.WROUGHT_IRON)
	## Rectangular stair shaft: one step per voxel of rise, straight south into the crypt.
	var crypt_floor := _crypt_floor_y()
	var stair_w0 := _ox + cx - 1
	var stair_w1 := _ox + cx + 2
	var stair_z0 := _oz + cz - 1
	brush.fill_box(
		Vector3i(stair_w0, crypt_floor, stair_z0),
		Vector3i(stair_w1, deck + 2, stair_z0 + YARD_RISE + 2),
		VoxelMaterial.AIR
	)
	for i in range(YARD_RISE + 1):
		var step_y := deck - i
		var step_z := stair_z0 + i
		brush.fill_box(
			Vector3i(stair_w0, crypt_floor - 1, step_z),
			Vector3i(stair_w1, step_y + 1, step_z + 1),
			VoxelMaterial.GRAVE_STONE
		)
		brush.fill_box(
			Vector3i(stair_w0, step_y + 1, step_z),
			Vector3i(stair_w1, deck + 2, step_z + 1),
			VoxelMaterial.AIR
		)
		## Track the shaft so dressing lines the walls.
		for x in range(cx - 1, cx + 2):
			for z in range(cz - 1 + i, cz + 1 + i):
				if x < 0 or z < 0 or x >= _w or z >= _d:
					continue
				var i2 := z * _w + x
				var lo := crypt_floor
				var hi := deck + 1
				if _crypt_hi[i2] < 0:
					_crypt_lo[i2] = lo
					_crypt_hi[i2] = hi
				else:
					_crypt_lo[i2] = mini(_crypt_lo[i2], lo)
					_crypt_hi[i2] = maxi(_crypt_hi[i2], hi)


## ── Plot blocks ────────────────────────────────────────────────────────────


func _dress_blocks() -> void:
	var chapel_keep := Rect2i(_chapel.x - 14, _chapel.z - 10, 29, 22 + YARD_RISE)
	for block: Rect2i in _blocks:
		if chapel_keep.intersects(block):
			continue
		if _block_free_cells(block) * 2 < block.size.x * block.size.y:
			continue
		_kerb_block(block)
		var inner := Rect2i(
			block.position.x + 1, block.position.y + 1, block.size.x - 2, block.size.y - 2
		)
		if inner.size.x < GRAVE_SLOT_W or inner.size.y < GRAVE_SLOT_D:
			continue
		var roll := rng.randf()
		if roll < 0.1 and inner.size.x >= 9 and inner.size.y >= 11:
			_fill_block_mausoleum(inner)
		elif roll < 0.16 and inner.size.x >= 11 and inner.size.y >= 11:
			_fill_block_monument(inner)
		elif roll < 0.24:
			_fill_block_grove(inner)
		else:
			_fill_block_graves(inner)


func _block_free_cells(block: Rect2i) -> int:
	var n := 0
	for z in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			if x < 0 or z < 0 or x >= _w or z >= _d:
				continue
			var i := z * _w + x
			if _yard[i] != 0 and _path[i] == 0 and _taken[i] == 0:
				n += 1
	return n


## Dressed kerb around the section — the single strongest read that these are
## plots between walks, not props dropped on a lawn.
func _kerb_block(block: Rect2i) -> void:
	var deck := ground_y + YARD_RISE
	for z in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			var on_edge := (
				x == block.position.x
				or x == block.end.x - 1
				or z == block.position.y
				or z == block.end.y - 1
			)
			if not on_edge:
				continue
			if not _free_cell(x, z):
				continue
			_taken[z * _w + x] = 1
			brush.set_vox(Vector3i(_ox + x, deck + 1, _oz + z), VoxelMaterial.GRAVE_STONE)


func _fill_block_graves(inner: Rect2i) -> void:
	var cols := inner.size.x / GRAVE_SLOT_W
	var rows := inner.size.y / GRAVE_SLOT_D
	if cols <= 0 or rows <= 0:
		return
	var ox := inner.position.x + (inner.size.x - cols * GRAVE_SLOT_W) / 2
	var oz := inner.position.y + (inner.size.y - rows * GRAVE_SLOT_D) / 2
	## One section faces one way and mostly buries one family style.
	var facing := 1 if rng.randf() < 0.5 else -1
	var house_kind := _roll_grave_kind()
	for r in range(rows):
		for c in range(cols):
			var sx := ox + c * GRAVE_SLOT_W
			var sz := oz + r * GRAVE_SLOT_D
			if not _slot_free(sx, sz):
				continue
			var kind := house_kind if rng.randf() < 0.6 else _roll_grave_kind()
			_grave_slot(sx, sz, facing, kind)
			_graves += 1


func _roll_grave_kind() -> int:
	var r := rng.randf()
	if r < 0.3:
		return GRAVE_TABLET
	if r < 0.52:
		return GRAVE_CROSS
	if r < 0.66:
		return GRAVE_STELE
	if r < 0.78:
		return GRAVE_CHEST
	if r < 0.88:
		return GRAVE_OBELISK
	return GRAVE_RUINED


func _slot_free(sx: int, sz: int) -> bool:
	for dz in range(GRAVE_SLOT_D):
		for dx in range(GRAVE_SLOT_W):
			if not _free_cell(sx + dx, sz + dz):
				return false
	return true


func _free_cell(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= _w or z >= _d:
		return false
	var i := z * _w + x
	return _yard[i] != 0 and _path[i] == 0 and _taken[i] == 0


## One burial slot: GRAVE_SLOT_W x GRAVE_SLOT_D, headstone at the `facing` end.
func _grave_slot(sx: int, sz: int, facing: int, kind: int) -> void:
	var deck := ground_y + YARD_RISE
	for dz in range(GRAVE_SLOT_D):
		for dx in range(GRAVE_SLOT_W):
			_taken[(sz + dz) * _w + sx + dx] = 1
			brush.set_vox(
				Vector3i(_ox + sx + dx, deck, _oz + sz + dz), VoxelMaterial.GRAVE_SOIL
			)
	var head_z := sz if facing > 0 else sz + GRAVE_SLOT_D - 1
	var mound_z0 := sz + 1 if facing > 0 else sz
	var cx := sx + 1
	## Turned mound over the plot, one voxel proud of the walk.
	for dz in range(3):
		for dx in range(GRAVE_SLOT_W):
			brush.set_vox(
				Vector3i(_ox + sx + dx, deck + 1, _oz + mound_z0 + dz),
				VoxelMaterial.GRAVE_SOIL
			)
	## A share of plots stay unmarked — paupers' ground, and the gaps stop the rows
	## from fusing into one continuous wall of stone.
	if rng.randf() < 0.1:
		return
	match kind:
		GRAVE_TABLET:
			_grave_tablet(cx, head_z, deck)
		GRAVE_CROSS:
			_grave_cross(cx, head_z, deck)
		GRAVE_STELE:
			_grave_stele(cx, head_z, deck, mound_z0)
		GRAVE_CHEST:
			_grave_chest(cx, head_z, deck, mound_z0)
		GRAVE_OBELISK:
			_grave_obelisk(cx, head_z, deck)
		GRAVE_RUINED:
			_grave_ruined(cx, head_z, deck)
		_:
			push_error("GraveyardComposer: unknown grave kind %d" % kind)


## Arched tablet: 4-7 voxels (2.0-3.5 m) of dressed stone, shouldered top.
func _grave_tablet(cx: int, hz: int, deck: int) -> void:
	var h := 4 + rng.randi() % 4
	var mat := VoxelMaterial.GRAVE_MARBLE if rng.randf() < 0.18 else VoxelMaterial.GRAVE_STONE
	var wz := _oz + hz
	for dy in range(h):
		brush.set_vox(Vector3i(_ox + cx, deck + 1 + dy, wz), mat)
	for dy in range(h - 1):
		brush.set_vox(Vector3i(_ox + cx - 1, deck + 1 + dy, wz), mat)
		brush.set_vox(Vector3i(_ox + cx + 1, deck + 1 + dy, wz), mat)
	if h >= 6:
		brush.set_vox(Vector3i(_ox + cx, deck + 1 + h, wz), mat)


## Standing cross: the tallest common marker, 5-8 voxels plus arms.
func _grave_cross(cx: int, hz: int, deck: int) -> void:
	var h := 5 + rng.randi() % 4
	var mat := VoxelMaterial.GRAVE_STONE if rng.randf() < 0.75 else VoxelMaterial.WROUGHT_IRON
	var wz := _oz + hz
	for dy in range(h):
		brush.set_vox(Vector3i(_ox + cx, deck + 1 + dy, wz), mat)
	var arm_y := deck + h - 1
	brush.set_vox(Vector3i(_ox + cx - 1, arm_y, wz), mat)
	brush.set_vox(Vector3i(_ox + cx + 1, arm_y, wz), mat)
	## Squat plinth so the shaft does not sprout straight out of the soil.
	for dx in range(-1, 2):
		brush.set_vox(Vector3i(_ox + cx + dx, deck + 1, wz), VoxelMaterial.GRAVE_STONE)


## Family stele: full-width slab with a marble cornice and an iron plot rail.
func _grave_stele(cx: int, hz: int, deck: int, mound_z0: int) -> void:
	var h := 5 + rng.randi() % 3
	var wz := _oz + hz
	var cap := VoxelMaterial.GRAVE_MARBLE if rng.randf() < 0.35 else VoxelMaterial.GRAVE_STONE
	for dx in range(-1, 2):
		for dy in range(h):
			brush.set_vox(
				Vector3i(_ox + cx + dx, deck + 1 + dy, wz), VoxelMaterial.GRAVE_STONE
			)
		brush.set_vox(Vector3i(_ox + cx + dx, deck + 1 + h, wz), cap)
	## Rail posts at the far corners of the plot.
	var far_z := _oz + mound_z0 + (2 if hz <= mound_z0 else 0)
	for dx in [-1, 1]:
		brush.set_vox(Vector3i(_ox + cx + dx, deck + 2, far_z), VoxelMaterial.WROUGHT_IRON)


## Chest tomb: a boxed plot with a marble lid instead of a mound.
func _grave_chest(cx: int, hz: int, deck: int, mound_z0: int) -> void:
	var wx0 := _ox + cx - 1
	var wx1 := _ox + cx + 2
	var wz0 := _oz + mound_z0
	var wz1 := _oz + mound_z0 + 3
	brush.fill_box(
		Vector3i(wx0, deck + 1, wz0), Vector3i(wx1, deck + 3, wz1), VoxelMaterial.GRAVE_STONE
	)
	brush.fill_box(
		Vector3i(wx0, deck + 3, wz0), Vector3i(wx1, deck + 4, wz1), VoxelMaterial.GRAVE_MARBLE
	)
	var h := 3 + rng.randi() % 3
	for dy in range(h):
		brush.set_vox(
			Vector3i(_ox + cx, deck + 1 + dy, _oz + hz), VoxelMaterial.GRAVE_STONE
		)


## Obelisk: the district's mid-scale landmark, 8-13 voxels of marble.
func _grave_obelisk(cx: int, hz: int, deck: int) -> void:
	var wz := _oz + hz
	for dx in range(-1, 2):
		for dy in range(2):
			brush.set_vox(
				Vector3i(_ox + cx + dx, deck + 1 + dy, wz), VoxelMaterial.GRAVE_STONE
			)
	var h := 6 + rng.randi() % 5
	for dy in range(h):
		brush.set_vox(Vector3i(_ox + cx, deck + 3 + dy, wz), VoxelMaterial.GRAVE_MARBLE)
	brush.set_vox(Vector3i(_ox + cx, deck + 3 + h, wz), VoxelMaterial.GRAVE_STONE)


## Collapsed marker: short, gap-toothed, with rubble in the soil.
func _grave_ruined(cx: int, hz: int, deck: int) -> void:
	var h := 2 + rng.randi() % 3
	var lean := -1 if rng.randf() < 0.5 else 1
	var wz := _oz + hz
	for dy in range(h):
		brush.set_vox(Vector3i(_ox + cx, deck + 1 + dy, wz), VoxelMaterial.GRAVE_STONE)
	for dy in range(maxi(h - 1, 1)):
		brush.set_vox(Vector3i(_ox + cx + lean, deck + 1 + dy, wz), VoxelMaterial.GRAVE_STONE)
	brush.set_vox(Vector3i(_ox + cx - lean, deck + 1, wz), VoxelMaterial.GRAVE_PATH)


func _fill_block_mausoleum(inner: Rect2i) -> void:
	var cx := inner.position.x + inner.size.x / 2
	var cz := inner.position.y + inner.size.y / 2
	var hw := 3 + rng.randi() % 2
	var hd := 4 + rng.randi() % 2
	if _area_free(cx - hw - 1, cz - hd - 1, 2 * hw + 3, 2 * hd + 3):
		_mausoleum_at(cx, cz, hw, hd)
	## Whatever room is left in the section still takes rows of graves.
	_fill_block_graves(inner)


func _mausoleum_at(x: int, z: int, hw: int, hd: int) -> void:
	var deck := ground_y + YARD_RISE
	var hh := 7 + rng.randi() % 4
	var wx0 := _ox + x - hw
	var wz0 := _oz + z - hd
	var wx1 := _ox + x + hw + 1
	var wz1 := _oz + z + hd + 1
	_claim(x - hw - 1, z - hd - 1, 2 * hw + 3, 2 * hd + 3)
	## Two-step plinth.
	brush.fill_box(
		Vector3i(wx0 - 1, deck, wz0 - 1),
		Vector3i(wx1 + 1, deck + 1, wz1 + 1),
		VoxelMaterial.GRAVE_STONE
	)
	brush.fill_box(
		Vector3i(wx0, deck + 1, wz0), Vector3i(wx1, deck + 2, wz1), VoxelMaterial.GRAVE_STONE
	)
	for zz in range(wz0, wz1):
		for xx in range(wx0, wx1):
			var edge := xx == wx0 or xx == wx1 - 1 or zz == wz0 or zz == wz1 - 1
			if not edge:
				continue
			var corner := (xx == wx0 or xx == wx1 - 1) and (zz == wz0 or zz == wz1 - 1)
			var door := zz == wz1 - 1 and absi(xx - (_ox + x)) == 0
			for y in range(deck + 2, deck + 2 + hh):
				if door and y < deck + 5:
					brush.set_vox(Vector3i(xx, y, zz), VoxelMaterial.WROUGHT_IRON)
					continue
				var mat := VoxelMaterial.GRAVE_MARBLE if corner else VoxelMaterial.GRAVE_STONE
				if y == deck + 1 + hh:
					mat = VoxelMaterial.GRAVE_MARBLE
				brush.set_vox(Vector3i(xx, y, zz), mat)
	## Hollow interior above the plinth.
	brush.fill_box(
		Vector3i(wx0 + 1, deck + 2, wz0 + 1),
		Vector3i(wx1 - 1, deck + 1 + hh, wz1 - 1),
		VoxelMaterial.AIR
	)
	## Overhanging cornice and iron corner finials.
	brush.fill_box(
		Vector3i(wx0 - 1, deck + 1 + hh, wz0 - 1),
		Vector3i(wx1 + 1, deck + 2 + hh, wz1 + 1),
		VoxelMaterial.GRAVE_STONE
	)
	brush.fill_box(
		Vector3i(wx0, deck + 2 + hh, wz0), Vector3i(wx1, deck + 3 + hh, wz1),
		VoxelMaterial.GRAVE_STONE
	)
	for cxx: int in [wx0 - 1, wx1]:
		for czz: int in [wz0 - 1, wz1]:
			brush.set_vox(Vector3i(cxx, deck + 2 + hh, czz), VoxelMaterial.WROUGHT_IRON)


## A section given over to one tall memorial — the skyline of the graveyard.
func _fill_block_monument(inner: Rect2i) -> void:
	var cx := inner.position.x + inner.size.x / 2
	var cz := inner.position.y + inner.size.y / 2
	if not _area_free(cx - 4, cz - 4, 9, 9):
		_fill_block_graves(inner)
		return
	_claim(cx - 4, cz - 4, 9, 9)
	var deck := ground_y + YARD_RISE
	var wx := _ox + cx
	var wz := _oz + cz
	## Stepped base.
	for step in range(3):
		var r := 3 - step
		brush.fill_box(
			Vector3i(wx - r, deck + 1 + step, wz - r),
			Vector3i(wx + r + 1, deck + 2 + step, wz + r + 1),
			VoxelMaterial.GRAVE_STONE
		)
	var shaft_y := deck + 4
	var shaft_h := 8 + rng.randi() % 5
	brush.fill_box(
		Vector3i(wx - 1, shaft_y, wz - 1),
		Vector3i(wx + 2, shaft_y + shaft_h, wz + 2),
		VoxelMaterial.GRAVE_MARBLE
	)
	for dy in range(3):
		brush.set_vox(Vector3i(wx, shaft_y + shaft_h + dy, wz), VoxelMaterial.GRAVE_MARBLE)
	brush.set_vox(Vector3i(wx, shaft_y + shaft_h + 3, wz), VoxelMaterial.WROUGHT_IRON)
	## Iron railing around the memorial.
	for t in range(-4, 5):
		for pair: Vector2i in [Vector2i(t, -4), Vector2i(t, 4), Vector2i(-4, t), Vector2i(4, t)]:
			if (pair.x + pair.y) % 2 != 0:
				continue
			brush.set_vox(
				Vector3i(wx + pair.x, deck + 1, wz + pair.y), VoxelMaterial.WROUGHT_IRON
			)
			brush.set_vox(
				Vector3i(wx + pair.x, deck + 2, wz + pair.y), VoxelMaterial.WROUGHT_IRON
			)


## Overgrown section: yews closing in over toppled slabs.
func _fill_block_grove(inner: Rect2i) -> void:
	var deck := ground_y + YARD_RISE
	var trees := 3 + rng.randi() % 4
	for _i in range(trees):
		var x := inner.position.x + rng.randi() % maxi(inner.size.x, 1)
		var z := inner.position.y + rng.randi() % maxi(inner.size.y, 1)
		if not _area_free(x - 1, z - 1, 3, 3):
			continue
		_claim(x - 1, z - 1, 3, 3)
		_cypress_at(x, z)
	for _j in range(2 + rng.randi() % 3):
		var sx := inner.position.x + rng.randi() % maxi(inner.size.x - 2, 1)
		var sz := inner.position.y + rng.randi() % maxi(inner.size.y - 3, 1)
		if not _area_free(sx, sz, 2, 3):
			continue
		_claim(sx, sz, 2, 3)
		## Toppled slab lying flat in the moss.
		brush.fill_box(
			Vector3i(_ox + sx, deck + 1, _oz + sz),
			Vector3i(_ox + sx + 2, deck + 2, _oz + sz + 3),
			VoxelMaterial.GRAVE_STONE
		)


func _area_free(x0: int, z0: int, w: int, d: int) -> bool:
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if not _free_cell(x, z):
				return false
	return true


func _claim(x0: int, z0: int, w: int, d: int) -> void:
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if x < 0 or z < 0 or x >= _w or z >= _d:
				continue
			_taken[z * _w + x] = 1


## ── Planting ───────────────────────────────────────────────────────────────


## Cypresses on the corners of the aisle crossings. Planted before the plots are
## laid so the kerbs and rows part around them instead of the other way round.
func _plant_avenue() -> void:
	## Far enough back that the crowns never close over the walk itself.
	var off := AISLE_MAIN_HW + 3
	for lx: int in _aisle_x:
		for lz: int in _aisle_z:
			for corner: Vector2i in [
				Vector2i(-off, -off), Vector2i(off, -off), Vector2i(-off, off), Vector2i(off, off)
			]:
				if rng.randf() > 0.12:
					continue
				var x := lx + corner.x
				var z := lz + corner.y
				if not _area_free(x - 1, z - 1, 3, 3):
					continue
				_claim(x - 1, z - 1, 3, 3)
				_cypress_at(x, z)


func _plant_trees(density: float) -> void:
	var target := int((70.0 + float(rng.randi() % 30)) * density)
	var placed := 0
	var tries := 0
	while placed < target and tries < target * 14:
		tries += 1
		var x := rng.randi_range(4, _w - 5)
		var z := rng.randi_range(4, _d - 5)
		if not _area_free(x - 1, z - 1, 3, 3):
			continue
		if _height_at(x, z) < YARD_RISE - 2:
			continue
		_claim(x - 1, z - 1, 3, 3)
		if rng.randf() < 0.7:
			_cypress_at(x, z)
		else:
			_dead_tree_at(x, z)
		placed += 1


## Churchyard cypress: a narrow black spire, not a round park canopy.
func _cypress_at(x: int, z: int) -> void:
	var base := ground_y + _height_at(x, z)
	_stamper().cypress(_ox + x, base, _oz + z)


## Bare skeleton tree — silhouette only, no foliage at all.
func _dead_tree_at(x: int, z: int) -> void:
	var base := ground_y + _height_at(x, z)
	_stamper().dead_tree(_ox + x, base, _oz + z)


## ── Catacombs (dressed masonry — boxes and right angles only) ──────────────


func _crypt_floor_y() -> int:
	return ground_y + 2


func _carve_catacombs() -> void:
	var floor_y := _crypt_floor_y()
	var rooms: Array[Dictionary] = []
	## Hub under the chapel stair — rectangular hall, grid-aligned.
	var hub := {
		"x": _chapel.x,
		"z": _chapel.z + 8,
		"rx": 6,
		"rz": 5,
		"kind": "hub",
	}
	rooms.append(hub)
	## Side chambers on a cardinal lattice — no polar jitter, no diagonal corridors.
	var slots: Array[Vector2i] = [
		Vector2i(0, 22), Vector2i(0, -22), Vector2i(24, 0), Vector2i(-24, 0),
		Vector2i(20, 18), Vector2i(-20, 18), Vector2i(20, -18), Vector2i(-20, -18),
	]
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap := slots[i]
		slots[i] = slots[j]
		slots[j] = swap
	var want := 4 + rng.randi() % 3
	for slot: Vector2i in slots:
		if rooms.size() > want:
			break
		var rx := clampi(_chapel.x + slot.x, 14, _w - 15)
		var rz := clampi(_chapel.z + slot.y, 14, _d - 15)
		if _height_at(rx, rz) < YARD_RISE - 1:
			continue
		## Snap chamber sizes to odd widths so walls sit on whole voxels.
		rooms.append({
			"x": rx,
			"z": rz,
			"rx": 3 + (rng.randi() % 3),
			"rz": 3 + (rng.randi() % 3),
			"kind": "chamber",
		})
	for room: Dictionary in rooms:
		if str(room["kind"]) == "chamber":
			crypt_rooms.append(
				Vector3i(_ox + int(room["x"]), floor_y, _oz + int(room["z"]))
			)
		_carve_crypt_box(
			int(room["x"]) - int(room["rx"]),
			int(room["z"]) - int(room["rz"]),
			int(room["x"]) + int(room["rx"]),
			int(room["z"]) + int(room["rz"]),
			floor_y,
			floor_y + CRYPT_H - 1
		)
	## Orthogonal links only: every chamber → hub, plus one cross-link.
	for i2 in range(1, rooms.size()):
		_carve_crypt_corridor(
			Vector2i(int(rooms[0]["x"]), int(rooms[0]["z"])),
			Vector2i(int(rooms[i2]["x"]), int(rooms[i2]["z"])),
			floor_y
		)
	if rooms.size() >= 3:
		var a := 1
		var b := 2 + rng.randi() % (rooms.size() - 2)
		_carve_crypt_corridor(
			Vector2i(int(rooms[a]["x"]), int(rooms[a]["z"])),
			Vector2i(int(rooms[b]["x"]), int(rooms[b]["z"])),
			floor_y
		)
	## Stair landing → hub, axis-aligned.
	_carve_crypt_corridor(
		Vector2i(_chapel.x, _chapel.z),
		Vector2i(int(hub["x"]), int(hub["z"])),
		floor_y
	)


## Inclusive XZ box of air at a flat floor / ceiling — masonry, not an ellipsoid.
func _carve_crypt_box(x0: int, z0: int, x1: int, z1: int, y0: int, y1: int) -> void:
	if x0 > x1:
		var tx := x0
		x0 = x1
		x1 = tx
	if z0 > z1:
		var tz := z0
		z0 = z1
		z1 = tz
	x0 = clampi(x0, 2, _w - 3)
	x1 = clampi(x1, 2, _w - 3)
	z0 = clampi(z0, 2, _d - 3)
	z1 = clampi(z1, 2, _d - 3)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var top := ground_y + _height_at(x, z) - CRYPT_SHELL
			for y in range(y0, mini(y1, top) + 1):
				if y < ground_y + 1:
					continue
				_set_crypt_air(x, y, z)


## Manhattan corridor: one X run, then one Z run (or the reverse). Flat floor.
func _carve_crypt_corridor(from_xz: Vector2i, to_xz: Vector2i, floor_y: int) -> void:
	var hw := CRYPT_CORRIDOR_HW
	var y1 := floor_y + CRYPT_H - 1
	var bend_first_x := rng.randf() < 0.5
	if bend_first_x:
		_carve_crypt_box(
			mini(from_xz.x, to_xz.x) - hw,
			from_xz.y - hw,
			maxi(from_xz.x, to_xz.x) + hw,
			from_xz.y + hw,
			floor_y,
			y1
		)
		_carve_crypt_box(
			to_xz.x - hw,
			mini(from_xz.y, to_xz.y) - hw,
			to_xz.x + hw,
			maxi(from_xz.y, to_xz.y) + hw,
			floor_y,
			y1
		)
	else:
		_carve_crypt_box(
			from_xz.x - hw,
			mini(from_xz.y, to_xz.y) - hw,
			from_xz.x + hw,
			maxi(from_xz.y, to_xz.y) + hw,
			floor_y,
			y1
		)
		_carve_crypt_box(
			mini(from_xz.x, to_xz.x) - hw,
			to_xz.y - hw,
			maxi(from_xz.x, to_xz.x) + hw,
			to_xz.y + hw,
			floor_y,
			y1
		)


func _set_crypt_air(x: int, y: int, z: int) -> void:
	## Never bore under thin approaches — that daylights the crypt through the ramp.
	if _height_at(x, z) < YARD_RISE - 1:
		return
	var wx := _ox + x
	var wz := _oz + z
	brush.set_vox(Vector3i(wx, y, wz), VoxelMaterial.AIR)
	## Worn marble flagstones under the flat crypt datum — laid with the carve so
	## every hall shares one smooth floor plane.
	if y == _crypt_floor_y():
		brush.set_vox(Vector3i(wx, y - 1, wz), VoxelMaterial.GRAVE_MARBLE)
	var i := z * _w + x
	if _crypt_hi[i] < 0:
		_crypt_lo[i] = y
		_crypt_hi[i] = y
	else:
		_crypt_lo[i] = mini(_crypt_lo[i], y)
		_crypt_hi[i] = maxi(_crypt_hi[i], y)


## Line exposed crypt faces in dressed stone — not the organic cave textures.
func _dress_catacombs() -> void:
	for z in range(1, _d - 1):
		var row := z * _w
		for x in range(1, _w - 1):
			## A wall voxel belongs to the *neighbouring* column, so the dressing pass
			## has to sweep the dilated footprint or every hall keeps raw mound stone.
			var lo := 1 << 30
			var hi := -1
			for i: int in [row + x, row + x - 1, row + x + 1, row - _w + x, row + _w + x]:
				if _crypt_hi[i] < 0:
					continue
				lo = mini(lo, _crypt_lo[i])
				hi = maxi(hi, _crypt_hi[i])
			if hi < 0:
				continue
			var wx := _ox + x
			var wz := _oz + z
			## Re-assert the flagstone plane (stair masonry may have overwritten it).
			if brush.get_vox(Vector3i(wx, _crypt_floor_y(), wz)) == VoxelMaterial.AIR:
				brush.set_vox(
					Vector3i(wx, _crypt_floor_y() - 1, wz), VoxelMaterial.GRAVE_MARBLE
				)
			for y in range(maxi(lo - 1, ground_y + 1), hi + 2):
				var here := brush.get_vox(Vector3i(wx, y, wz))
				if here == VoxelMaterial.AIR or here == VoxelMaterial.GRAVE_MARBLE:
					continue
				if not _is_crypt_shellable(here):
					continue
				if not _air_neighbour(wx, y, wz):
					continue
				## Pale ashlar string course every fourth lift so a long hall still
				## reads as coursed masonry instead of one flat dark slab.
				var course := (
					VoxelMaterial.STONE
					if (y - _crypt_floor_y()) % 4 == 0
					else VoxelMaterial.GRAVE_STONE
				)
				brush.set_vox(Vector3i(wx, y, wz), course)


func _is_crypt_shellable(id: int) -> bool:
	match id:
		VoxelMaterial.STONE, VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK, VoxelMaterial.DIRT, VoxelMaterial.GRAVEL, VoxelMaterial.CAVE_WALL, VoxelMaterial.TILES, VoxelMaterial.GRAVE_SOIL, VoxelMaterial.GRAVE_PATH:
			return true
		_:
			return false


func _air_neighbour(wx: int, y: int, wz: int) -> bool:
	return (
		brush.get_vox(Vector3i(wx, y - 1, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y + 1, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx + 1, y, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx - 1, y, wz)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y, wz + 1)) == VoxelMaterial.AIR
		or brush.get_vox(Vector3i(wx, y, wz - 1)) == VoxelMaterial.AIR
	)


## ── helpers ────────────────────────────────────────────────────────────────


func _height_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= _w or z >= _d:
		return 0
	return _height[z * _w + x]


func _is_road_cell(x: int, z: int) -> bool:
	return LandUse.is_road(planner.tag_at((_ox + x) / cell_size, (_oz + z) / cell_size))


func _yard_rise_at_center() -> int:
	return _height_at(_w / 2, _d / 2)


func _path_count() -> int:
	var n := 0
	for i in range(_path.size()):
		if _path[i] != 0:
			n += 1
	return n


func _crypt_column_count() -> int:
	var n := 0
	for i in range(_crypt_hi.size()):
		if _crypt_hi[i] >= 0:
			n += 1
	return n
