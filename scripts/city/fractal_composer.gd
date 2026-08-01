## Fractal-theme district: square glowing uni-voxel deck; grass fills the rest of the
## open reserve (edge street stubs stay as roads from the planner).
##
## Above the plaza: a glass viewing cross at 60 m with a circular platform in the
## middle. Stairs climb *sideways along each panel edge* up to that height, then
## meet the cross-arm tip — they never cut inward through the sculpture volume.
class_name FractalComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28

## Local-district voxel AABB of the last compose (full reserve).
var last_min: Vector3i = Vector3i.ZERO
var last_max: Vector3i = Vector3i.ZERO
## Centered square deck painted with FRACTAL_GLOW (min inclusive, max exclusive on xz/y).
var last_glow_min: Vector3i = Vector3i.ZERO
var last_glow_max: Vector3i = Vector3i.ZERO
## Viewing deck Y (inclusive solid row) after the last compose; -1 if none.
var last_view_y: int = -1
## Sheltered dead end at the top of the spiral ramp (district-local x, floor Y, z). `x` is -1
## when the surface search found no such pocket.
var last_niche: Vector3i = Vector3i(-1, 0, -1)

## One planner cell of meadow between road stubs and the glowing square.
const GRASS_MARGIN_CELLS := 1
## Matches CityRoot.VOXEL_SIZE — composers work in voxels.
const VOXEL_M := 0.5
## Walkable glass deck height above the glow top.
const VIEW_HEIGHT_M := 60.0
## 60 m / 0.5 m — keep in sync with VOXEL_M / VIEW_HEIGHT_M.
const VIEW_RISE_VOX := 120
## Cross walkway half-width (full width = 2*half+1).
const ARM_HALF_W := 2
## Circular platform radius at the crossing.
const CIRCLE_RADIUS_VOX := 16
## Horizontal voxels per stair riser along the edge.
const STAIR_RUN := 1
## Stair strip just inside the glow edge (stays outside the Create morph margin).
const EDGE_INSET_VOX := 2
const MAT_VIEW := VoxelMaterial.GLASS

## A single-turn spiral ramp on the deck, walled on both flanks and capped at the top.
##
## The plaza used to be a flat square under a cross on stilts: nowhere on it was sheltered, and
## nowhere on it was worth walking to. The ramp gives the tile a ground-level destination, and
## its capped head is the one place on the deck that matches the niche shape below.
const SPIRAL_RADIUS := 14
## Ring cells walked per voxel of rise. One full turn is 8 × radius cells.
const SPIRAL_RISE_EVERY := 4
## Half-width of the walkable tread, measured off the ring line.
const SPIRAL_TREAD_HALF := 1
## Flank walls sit one cell outside the tread on both sides.
const SPIRAL_WALL_OFFSET := 2
const MAT_SPIRAL := VoxelMaterial.FRACTAL_INTERIOR

## What counts as a hiding place: three cardinal neighbours standing at least this much higher,
## and the fourth exactly one voxel lower — the way in. The walls are built a voxel taller than
## the threshold so a wall that a bake rounds down by one still reads as a wall.
const NICHE_WALL_RISE := 4
const NICHE_WALL_H := NICHE_WALL_RISE + 1
const NICHE_STEP_DOWN := 1
## How far above the deck the surface scan starts looking for the topmost solid voxel.
const NICHE_SCAN_HEIGHT := 48


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	last_min = min_v
	last_max = max_v
	last_glow_min = Vector3i.ZERO
	last_glow_max = Vector3i.ZERO
	last_view_y = -1
	last_niche = Vector3i(-1, 0, -1)
	if brush == null or planner == null:
		push_error("FractalComposer.compose: brush/planner missing")
		return
	var lf: Rect2i = planner.large_fractal
	if lf.size.x <= 0 or lf.size.y <= 0:
		push_error("FractalComposer.compose: empty large_fractal")
		return
	var x0 := lf.position.x * cell_size
	var z0 := lf.position.y * cell_size
	var x1 := lf.end.x * cell_size
	var z1 := lf.end.y * cell_size
	var width := x1 - x0
	var depth := z1 - z0
	var margin := GRASS_MARGIN_CELLS * cell_size
	var inner_w := width - 2 * margin
	var inner_d := depth - 2 * margin
	if inner_w < cell_size or inner_d < cell_size:
		margin = 0
		inner_w = width
		inner_d = depth
	var side := mini(inner_w, inner_d)
	## Largest centered square inside the grass-inset reserve.
	var gx0 := x0 + (width - side) / 2
	var gz0 := z0 + (depth - side) / 2
	var gx1 := gx0 + side
	var gz1 := gz0 + side
	var y0 := ground_y
	var y1 := ground_y + 1
	brush.fill_box(
		Vector3i(gx0, y0, gz0),
		Vector3i(gx1, y1, gz1),
		VoxelMaterial.FRACTAL_GLOW
	)
	last_glow_min = Vector3i(gx0, y0, gz0)
	last_glow_max = Vector3i(gx1, y1, gz1)
	_build_viewing_cross()
	_build_spiral_ramp()
	print(
		"FractalComposer: glow square %dx%d at %s .. %s (reserve %dx%d margin=%d view_y=%d)"
		% [side, side, str(last_glow_min), str(last_glow_max), width, depth, margin, last_view_y]
	)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	compose(min_v, max_v)


func _build_viewing_cross() -> void:
	var gx0 := last_glow_min.x
	var gz0 := last_glow_min.z
	var gx1 := last_glow_max.x
	var gz1 := last_glow_max.z
	var side := mini(gx1 - gx0, gz1 - gz0)
	var rise := VIEW_RISE_VOX
	var run_needed := rise * STAIR_RUN
	var half := side / 2
	## Sideways flight ends at the panel centre-line — needs run along half the edge.
	if half < run_needed + ARM_HALF_W + 4:
		push_error(
			"FractalComposer: glow %d too small for sideways %dm stairs (half=%d need ~%d)"
			% [side, int(VIEW_HEIGHT_M), half, run_needed + ARM_HALF_W + 4]
		)
		return
	if half < CIRCLE_RADIUS_VOX + EDGE_INSET_VOX + 8:
		push_error(
			"FractalComposer: glow %d too small for viewing circle/arms"
			% side
		)
		return
	var cx := (gx0 + gx1) / 2
	var cz := (gz0 + gz1) / 2
	var deck_y := ground_y
	var top_y := deck_y + rise
	last_view_y = top_y
	_fill_view_circle(cx, cz, top_y, CIRCLE_RADIUS_VOX)
	## Arm tips sit on each panel edge centre — stairs meet them only at view height.
	var south_z := gz0 + EDGE_INSET_VOX
	var north_z := gz1 - EDGE_INSET_VOX - 1
	var west_x := gx0 + EDGE_INSET_VOX
	var east_x := gx1 - EDGE_INSET_VOX - 1
	_fill_arm_z(cx, top_y, south_z, cz - CIRCLE_RADIUS_VOX)
	_fill_arm_z(cx, top_y, cz + CIRCLE_RADIUS_VOX + 1, north_z + 1)
	_fill_arm_x(cz, top_y, west_x, cx - CIRCLE_RADIUS_VOX)
	_fill_arm_x(cz, top_y, cx + CIRCLE_RADIUS_VOX + 1, east_x + 1)
	## Sideways climb along the edge → arm tip at (cx/cz, top_y). No mid-height inward path.
	_build_side_stair_x(south_z, cx - run_needed, +1, deck_y, top_y, gx0, gx1)
	_build_side_stair_x(north_z, cx + run_needed, -1, deck_y, top_y, gx0, gx1)
	_build_side_stair_z(west_x, cz - run_needed, +1, deck_y, top_y, gz0, gz1)
	_build_side_stair_z(east_x, cz + run_needed, -1, deck_y, top_y, gz0, gz1)


## One turn of walled ramp on the deck, sitting in a quadrant clear of the edge stair strips.
## The search for the niche runs afterwards over the finished voxels rather than assuming where
## the head ended up, so a ramp that gets clipped simply yields no niche instead of a scroll
## floating in the open.
func _build_spiral_ramp() -> void:
	var gx0 := last_glow_min.x
	var gz0 := last_glow_min.z
	var gx1 := last_glow_max.x
	var gz1 := last_glow_max.z
	var extent := SPIRAL_RADIUS + SPIRAL_WALL_OFFSET
	var span := extent * 2 + 1
	if gx1 - gx0 < span + EDGE_INSET_VOX * 6 or gz1 - gz0 < span + EDGE_INSET_VOX * 6:
		return
	var cx := (gx0 + gx1) / 2
	var cz := (gz0 + gz1) / 2
	var off := mini(gx1 - gx0, gz1 - gz0) / 5
	## Clamped well inside the glow edge: the four climbing stairs run in bands hard against it.
	var lo_x := gx0 + extent + EDGE_INSET_VOX * 3
	var hi_x := gx1 - extent - EDGE_INSET_VOX * 3 - 1
	var lo_z := gz0 + extent + EDGE_INSET_VOX * 3
	var hi_z := gz1 - extent - EDGE_INSET_VOX * 3 - 1
	var centre := Vector2i(clampi(cx - off, lo_x, hi_x), clampi(cz - off, lo_z, hi_z))
	var ring := _ring_cells(centre, SPIRAL_RADIUS)
	if ring.size() < SPIRAL_RISE_EVERY * 4:
		return
	var deck_y := ground_y
	var heights: PackedInt32Array = PackedInt32Array()
	heights.resize(ring.size())
	for i in range(ring.size()):
		heights[i] = deck_y + 1 + i / SPIRAL_RISE_EVERY
	## The head has to stand exactly one voxel over the cell behind it, or the way in reads as
	## level ground and the pocket no longer matches what the search is looking for.
	heights[ring.size() - 1] = heights[ring.size() - 2] + 1
	for i in range(ring.size()):
		_build_ramp_cell(centre, ring[i], heights[i], deck_y)
	## Cap across the path just past the head, turning the last tread into a dead end.
	var head: Vector2i = ring[ring.size() - 1]
	var head_y: int = heights[ring.size() - 1]
	_build_ramp_cap(centre, head, ring[0], head_y)
	last_niche = _find_niche(
		centre.x - extent, centre.y - extent, centre.x + extent + 1, centre.y + extent + 1, deck_y
	)


## Cells of a square ring, walked anticlockwise from one corner. 8 × radius of them.
func _ring_cells(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(centre.x - radius, centre.x + radius):
		out.append(Vector2i(x, centre.y - radius))
	for z in range(centre.y - radius, centre.y + radius):
		out.append(Vector2i(centre.x + radius, z))
	for x in range(centre.x + radius, centre.x - radius, -1):
		out.append(Vector2i(x, centre.y + radius))
	for z in range(centre.y + radius, centre.y - radius, -1):
		out.append(Vector2i(centre.x - radius, z))
	return out


## Tread plus the solid wedge under it plus both flank walls, for one cell of the ring.
func _build_ramp_cell(centre: Vector2i, cell: Vector2i, y: int, deck_y: int) -> void:
	var normal := _ring_normal(centre, cell)
	for k in range(-SPIRAL_TREAD_HALF, SPIRAL_TREAD_HALF + 1):
		var p := cell + normal * k
		brush.fill_box(
			Vector3i(p.x, deck_y + 1, p.y), Vector3i(p.x + 1, y + 1, p.y + 1), MAT_SPIRAL
		)
	for side: int in [-1, 1]:
		var w := cell + normal * (SPIRAL_WALL_OFFSET * side)
		brush.fill_box(
			Vector3i(w.x, deck_y + 1, w.y),
			Vector3i(w.x + 1, y + NICHE_WALL_H + 1, w.y + 1),
			MAT_SPIRAL
		)


## Wall shut across the tread one cell past the head. `behind` is the ring's first cell, which
## is where the run would carry on into if it were not stopped here.
func _build_ramp_cap(centre: Vector2i, head: Vector2i, behind: Vector2i, head_y: int) -> void:
	var travel := behind - head
	if travel == Vector2i.ZERO:
		travel = Vector2i(1, 0)
	travel = Vector2i(signi(travel.x), signi(travel.y))
	var normal := _ring_normal(centre, head)
	var at := head + travel
	for k in range(-SPIRAL_WALL_OFFSET, SPIRAL_WALL_OFFSET + 1):
		var p := at + normal * k
		brush.fill_box(
			Vector3i(p.x, head_y + 1, p.y),
			Vector3i(p.x + 1, head_y + NICHE_WALL_H + 1, p.y + 1),
			MAT_SPIRAL
		)


## Outward unit step from the ring centre for a ring cell: the axis the cell is furthest out on.
func _ring_normal(centre: Vector2i, cell: Vector2i) -> Vector2i:
	var dx := cell.x - centre.x
	var dz := cell.y - centre.y
	if absi(dx) >= absi(dz):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dz))


## Topmost solid voxel of a column, or -1 when the column is empty over the deck.
func _surface_y(x: int, z: int, deck_y: int) -> int:
	for y in range(deck_y + NICHE_SCAN_HEIGHT, deck_y - 1, -1):
		if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
			return y
	return -1


## The first column in the box that is walled on three sides and stepped down on the fourth.
## Ties are broken by height so the search prefers the top of the ramp over anything lower that
## happens to match.
func _find_niche(x0: int, z0: int, x1: int, z1: int, deck_y: int) -> Vector3i:
	var best := Vector3i(-1, 0, -1)
	for z in range(z0 + 1, z1 - 1):
		for x in range(x0 + 1, x1 - 1):
			var here := _surface_y(x, z, deck_y)
			if here <= deck_y:
				continue
			if here <= best.y:
				continue
			var walls := 0
			var ways_in := 0
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var there := _surface_y(x + step.x, z + step.y, deck_y)
				if there < 0:
					continue
				if there - here >= NICHE_WALL_RISE:
					walls += 1
				elif here - there == NICHE_STEP_DOWN:
					ways_in += 1
			if walls == 3 and ways_in == 1:
				best = Vector3i(x, here, z)
	return best


func _fill_view_circle(cx: int, cz: int, y: int, radius: int) -> void:
	for dz in range(-radius, radius + 1):
		var span_sq := radius * radius - dz * dz
		if span_sq < 0:
			continue
		var w := int(floor(sqrt(float(span_sq))))
		brush.fill_box(
			Vector3i(cx - w, y, cz + dz),
			Vector3i(cx + w + 1, y + 1, cz + dz + 1),
			MAT_VIEW
		)


func _fill_arm_x(cz: int, y: int, x0: int, x1: int) -> void:
	if x1 <= x0:
		return
	brush.fill_box(
		Vector3i(x0, y, cz - ARM_HALF_W),
		Vector3i(x1, y + 1, cz + ARM_HALF_W + 1),
		MAT_VIEW
	)


func _fill_arm_z(cx: int, y: int, z0: int, z1: int) -> void:
	if z1 <= z0:
		return
	brush.fill_box(
		Vector3i(cx - ARM_HALF_W, y, z0),
		Vector3i(cx + ARM_HALF_W + 1, y + 1, z1),
		MAT_VIEW
	)


## Climb along ±X at fixed edge z; ends on the N/S arm tip at centre-x.
func _build_side_stair_x(
	z: int, x_start: int, dir: int, deck_y: int, top_y: int, gx0: int, gx1: int
) -> void:
	var rise := top_y - deck_y
	var run_needed := rise * STAIR_RUN
	var xs := x_start
	if dir > 0 and xs < gx0 + 2:
		xs = gx0 + 2
	elif dir < 0 and xs > gx1 - 2 - run_needed:
		xs = gx1 - 2 - run_needed
	for step in range(rise):
		var y := deck_y + 1 + step
		var x0 := xs + dir * step * STAIR_RUN
		var x1 := x0 + dir * STAIR_RUN
		var xa := mini(x0, x1)
		var xb := maxi(x0, x1)
		brush.fill_box(
			Vector3i(xa, y, z - ARM_HALF_W),
			Vector3i(xb, y + 1, z + ARM_HALF_W + 1),
			MAT_VIEW
		)


## Climb along ±Z at fixed edge x; ends on the W/E arm tip at centre-z.
func _build_side_stair_z(
	x: int, z_start: int, dir: int, deck_y: int, top_y: int, gz0: int, gz1: int
) -> void:
	var rise := top_y - deck_y
	var run_needed := rise * STAIR_RUN
	var zs := z_start
	if dir > 0 and zs < gz0 + 2:
		zs = gz0 + 2
	elif dir < 0 and zs > gz1 - 2 - run_needed:
		zs = gz1 - 2 - run_needed
	for step in range(rise):
		var y := deck_y + 1 + step
		var z0 := zs + dir * step * STAIR_RUN
		var z1 := z0 + dir * STAIR_RUN
		var za := mini(z0, z1)
		var zb := maxi(z0, z1)
		brush.fill_box(
			Vector3i(x - ARM_HALF_W, y, za),
			Vector3i(x + ARM_HALF_W + 1, y + 1, zb),
			MAT_VIEW
		)
