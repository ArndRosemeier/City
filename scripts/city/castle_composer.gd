## Builds a Castle-theme district: a battered plinth carrying a walled bailey, corner
## towers, a gatehouse, and the causeway that climbs to it from the nearest road stub.
##
## Castle tiles keep only short arterial stubs at the edges (see DistrictPlanner), so the
## middle is one open reserve. The fortress sits in the widest part of it, raised on a
## plinth tall enough for the Phase 3 dungeon to live *inside* the mass — only five voxels
## of stone separate the street deck from bedrock, so there is nowhere below to dig.
##
## The plinth's outer faces are battered one voxel in per BATTER_RUN of rise, which puts a
## three-voxel riser between neighbouring columns. That is deliberately outside the
## pedestrian step budget: the scarp is unclimbable and the causeway is the only way up,
## which is what makes the gate mean anything.
class_name CastleComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
## Land-use grid — road cells come from here instead of 400k voxel probes.
var planner: DistrictPlanner
var cell_size: int = 28

## The plan this compose built, kept for DistrictGenerator.get_castle_layout().
var layout: CastleLayout = null

## ── Vertical budget ────────────────────────────────────────────────────────
## Phase 3 carves the dungeon into DUNGEON_Y0..DUNGEON_Y1 without moving anything above
## it, so these numbers are load-bearing for a later phase and not free to retune.
## Bedrock owns Y0, so the band starts immediately above it.
const DUNGEON_LEVELS := 3
## Dungeon storey pitch: five voxels of air (2.5 m ceiling, comfortably over the 4-cell nav
## minimum) plus a two-voxel floor slab. The reserved band is measured in these, so this is
## Phase 3's number and not free to retune.
const LEVEL_H := 7
const DUNGEON_Y0 := 1
const DUNGEON_Y1 := DUNGEON_Y0 + DUNGEON_LEVELS * LEVEL_H - 1
## Slab between the top dungeon level and the bailey.
const COURTYARD_SLAB_H := 2
## Topmost solid voxel of the courtyard — what a body in the bailey stands on.
const COURTYARD_Y := DUNGEON_Y1 + COURTYARD_SLAB_H + 1
## Deck the budget was measured against. The band is anchored to bedrock, so a district
## with a different deck needs its own budget rather than a shifted one.
const BUDGET_GROUND_Y := 6
const PLINTH_RISE := COURTYARD_Y - BUDGET_GROUND_Y

## ── Plinth ────────────────────────────────────────────────────────────────
## Voxels of rise per voxel the batter leans in.
const BATTER_RUN := 3
## Skirt columns between the plinth footprint and the flat plateau.
const SKIRT_COLS := PLINTH_RISE / BATTER_RUN - 1
## Flat ground kept between the plinth footprint and the nearest road or tile seam.
const VERGE := 6
const SPAN_MIN := 120
const SPAN_MAX := 156

## ── Curtain wall ──────────────────────────────────────────────────────────
## Terrace between the plateau edge and the curtain's outer face. At least a tower
## radius, or a corner tower would hang off the plinth.
const WALL_INSET_MIN := 8
const WALL_INSET_MAX := 12
## Five voxels of crown leave three with clearance once the merlons take the outer
## course, which is the least a pedestrian-profile wall-walk can be baked from.
const WALL_THICK_MIN := 5
const WALL_THICK_MAX := 6
## The curtain has to out-mass the plinth it stands on: 18 voxels of scarp under a
## 10-voxel wall reads as a stepped platform wearing a fence, not as a rampart.
const WALL_H_MIN := 20
const WALL_H_MAX := 26
const MERLON_H := 2

## ── Towers ────────────────────────────────────────────────────────────────
const TOWER_R_MIN := 7
const TOWER_R_MAX := 9
## Kept relative to the curtain so the towers still crown a wall twice its old height.
const TOWER_EXTRA_MIN := 8
const TOWER_EXTRA_MAX := 16
const MID_TOWERS_MAX := 2
const GATE_TOWER_R_MIN := 4
const GATE_TOWER_R_MAX := 6

## ── Gatehouse ─────────────────────────────────────────────────────────────
const GATE_W_MIN := 5
const GATE_W_MAX := 7
const GATE_H_MIN := 8
const GATE_H_MAX := 10
## Masonry either side of the passage, and how far the block projects past the curtain.
const GATE_PIER := 3
const GATE_PROJECT := 4
const GATE_EXTRA_H_MIN := 3
const GATE_EXTRA_H_MAX := 5

## ── Causeway ──────────────────────────────────────────────────────────────
## Forward voxels per voxel of climb. Every riser is exactly one voxel: a two-voxel one
## leaves the pedestrian walk graph and bakes as a one-way drop instead.
const CAUSEWAY_STEP_RUN := 3
## Half-width of the deck, parapets included — 13 to 17 voxels of ramp. Anything
## narrower reads as a service ladder propped against a 60 m fortress.
const CAUSEWAY_HW_MIN := 6
const CAUSEWAY_HW_MAX := 8
const PARAPET_H := 2

## ── Keep ──────────────────────────────────────────────────────────────────
const KEEP_W_MIN := 44
const KEEP_W_MAX := 52
const KEEP_D_MIN := 42
const KEEP_D_MAX := 48
## Clear bailey kept between the keep and the curtain — wide enough that the crown
## ramp on the keep's own side of the wall does not leave a dead slot behind it.
const KEEP_MARGIN := 12

## ── Keep interior ─────────────────────────────────────────────────────────
const KEEP_WALL_T := 3
const KEEP_PART_T := 2
const KEEP_SLAB_T := 2
## Keep storey pitch: seven voxels of air (a 3.5 m ceiling) over a two-voxel slab. Wider
## than the dungeon's `LEVEL_H` on purpose — a 2.5 m ceiling over a 12 m wide hall reads as
## a crawlspace, and the great hall doubles this to 8 m of air.
const KEEP_LEVEL_H := 9
const KEEP_STOREYS_MIN := 4
const KEEP_STOREYS_MAX := 5
## Narrowest room the subdivision may produce. Two of these plus a partition is the
## smallest cell that can be cut, so this also sets the keep's minimum footprint.
const KEEP_ROOM_MIN := 14
## Above this a cell is always offered for splitting. It is not a cap: a cell whose only
## legal cuts would sever a stair lane stays whole rather than being forced apart.
const KEEP_ROOM_SPLIT := 24
## Nav needs three clear voxels to path through an opening. Five leaves two voxels of
## clearance either side of the centre line instead of one, and survives the arch.
const KEEP_DOOR_W := 5
const KEEP_STAIR_W := 5
const KEEP_RAIL_H := 2
## Clear columns kept around a stair lane, and off the corner the lane starts from.
##
## Geodesic clearance is zero in any column with a blocked neighbour and the pedestrian
## profile needs one cell of it, so two obstacles two columns apart leave a gap nothing can
## walk down. A lane is solid stone flanked by a parapet, so without an apron this wide a
## partition can land close enough to strand the flight's own landing.
const LANE_MARGIN := 3
## Loops through the outer wall, so an enclosed storey is not blind masonry.
const KEEP_WINDOW_PITCH := 8
const KEEP_TURRET_R := 3
const KEEP_TURRET_EXTRA := 5

## ── Curtain crown access ──────────────────────────────────────────────────
## Walkable voxels of the courtyard ramp, its parapet excluded.
const CROWN_RAMP_W := 5

## District-local coordinates are never negative, so -1 reads as "no slot".
const NO_SLOT := -1

## Where the mossy course takes over from dressed ashlar.
const MOSS_T := 0.62

## Reserve bounds in district-local voxel coords: [_x0, _x1) x [_z0, _z1). Everything the
## composer plans and writes is in this space — CastleLayout is what tests and later phases
## read, so it must not be in some private region-relative frame.
var _x0: int = 0
var _z0: int = 0
var _x1: int = 0
var _z1: int = 0
var _w: int = 0
var _d: int = 0
## Per-column distance to the nearest road or reserve edge, indexed reserve-relative.
var _clearance: PackedFloat32Array = PackedFloat32Array()
## Detail passes (merlons, weathering, parapets) run for near tiles only.
var _detail: bool = true
var _plinth_voxels: int = 0
## Footprints the room subdivision must not cut through: the keep entrance approach and
## every stair lane with its parapet.
var _keep_reserved: Array[Rect2i] = []


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	_detail = true
	_build_clearance()
	layout = _plan()
	if layout == null:
		return
	_build_plinth()
	_build_curtain()
	_build_towers()
	_build_gatehouse()
	_build_causeway()
	_build_keep()
	_build_crown_ramp()
	_report()


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Far tiles still need the silhouette — a castle is the landmark of its quarter.
	## Only the per-voxel dressing is dropped.
	if not _begin(min_v, max_v):
		return
	_detail = false
	_build_clearance()
	layout = _plan()
	if layout == null:
		return
	_build_plinth()
	_build_curtain()
	_build_towers()
	_build_gatehouse()
	_build_causeway()
	_build_keep()
	_build_crown_ramp()


func _begin(min_v: Vector3i, max_v: Vector3i) -> bool:
	if rng == null or brush == null:
		push_error("CastleComposer: brush / rng not set")
		return false
	if planner == null:
		push_error("CastleComposer: planner not set")
		return false
	if ground_y != BUDGET_GROUND_Y:
		push_error(
			"CastleComposer: vertical budget is anchored to deck Y=%d, district deck is Y=%d"
			% [BUDGET_GROUND_Y, ground_y]
		)
		return false
	_x0 = min_v.x
	_z0 = min_v.z
	_x1 = max_v.x
	_z1 = max_v.z
	_w = max_v.x - min_v.x
	_d = max_v.z - min_v.z
	## The causeway alone is PLINTH_RISE * CAUSEWAY_STEP_RUN long and has to land on flat
	## ground inside the reserve, so a castle needs far more room than a hill.
	var need := SPAN_MIN + 2 * (SKIRT_COLS + VERGE) + PLINTH_RISE * CAUSEWAY_STEP_RUN
	if _w < need or _d < need:
		push_error(
			"CastleComposer: reserve %dx%d is too small for a castle (needs %d in both axes)"
			% [_w, _d, need]
		)
		return false
	_clearance.resize(_w * _d)
	_plinth_voxels = 0
	_keep_reserved.clear()
	layout = null
	return true


## Chamfer distance transform seeded from road cells and the region border, so the plinth
## can be sized and placed by "how far is the nearest thing I must not bury".
func _build_clearance() -> void:
	const FAR := 1.0e9
	for z in range(_d):
		for x in range(_w):
			var edge := x == 0 or z == 0 or x == _w - 1 or z == _d - 1
			var road := _is_road_cell(_x0 + x, _z0 + z)
			_clearance[z * _w + x] = 0.0 if (edge or road) else FAR
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


# ---------------------------------------------------------------------------
# Planning
# ---------------------------------------------------------------------------

## Everything the castle is, decided before a voxel is written. Returns null when the
## reserve cannot hold one, which is a bake error rather than a smaller castle.
func _plan() -> CastleLayout:
	var site := _pick_site()
	if site.x < 0:
		return null
	var room := _room_at(site.x, site.y)
	## Largest span that still leaves the skirt and the verge inside the reserve.
	var fits := int((room - float(SKIRT_COLS + VERGE)) * 2.0)
	if fits < SPAN_MIN:
		push_error(
			"CastleComposer: widest pocket in the reserve fits a %d voxel castle, needs %d"
			% [maxi(fits, 0), SPAN_MIN]
		)
		return null
	var span_cap := mini(SPAN_MAX, fits)
	var out := CastleLayout.new()
	out.courtyard_y = COURTYARD_Y
	out.dungeon_y0 = DUNGEON_Y0
	out.dungeon_y1 = DUNGEON_Y1
	var span_x := rng.randi_range(SPAN_MIN, span_cap)
	var span_z := rng.randi_range(SPAN_MIN, span_cap)
	out.plateau_rect = Rect2i(
		site.x - span_x / 2, site.y - span_z / 2, span_x, span_z
	)
	out.plinth_rect = out.plateau_rect.grow(SKIRT_COLS)
	out.wall_inset = rng.randi_range(WALL_INSET_MIN, WALL_INSET_MAX)
	out.wall_rect = out.plateau_rect.grow(-out.wall_inset)
	out.wall_thick = rng.randi_range(WALL_THICK_MIN, WALL_THICK_MAX)
	out.wall_height = rng.randi_range(WALL_H_MIN, WALL_H_MAX)
	out.courtyard_rect = out.wall_rect.grow(-out.wall_thick)
	_plan_gate(out)
	_plan_keep(out)
	_plan_towers(out)
	_plan_causeway(out)
	_plan_keep_interior(out)
	_plan_crown_ramp(out)
	return out


## Widest pocket of the reserve near its middle. Searching the whole region instead would
## drift the castle out to whichever stub-free corner happens to be roomiest.
func _pick_site() -> Vector2i:
	var cx := _x0 + _w / 2
	var cz := _z0 + _d / 2
	var best := Vector2i(cx, cz)
	var best_room := _room_at(cx, cz)
	var window := mini(_w, _d) / 6
	var z := maxi(_z0 + 2, cz - window)
	while z <= mini(_z1 - 3, cz + window):
		var x := maxi(_x0 + 2, cx - window)
		while x <= mini(_x1 - 3, cx + window):
			var room := _room_at(x, z)
			if room > best_room:
				best_room = room
				best = Vector2i(x, z)
			x += 4
		z += 4
	if best_room < float(SPAN_MIN / 2 + SKIRT_COLS + VERGE):
		push_error(
			"CastleComposer: best pocket has %.1f voxels of room, a castle needs %d"
			% [best_room, SPAN_MIN / 2 + SKIRT_COLS + VERGE]
		)
		return Vector2i(-1, -1)
	## Jitter so two tiles with the same reserve shape do not sit their keeps on the same
	## voxel, then snap back if the nudge landed on a stub skirt.
	var jitter := Vector2i(
		clampi(best.x + rng.randi_range(-10, 10), _x0 + 2, _x1 - 3),
		clampi(best.y + rng.randi_range(-10, 10), _z0 + 2, _z1 - 3)
	)
	if _room_at(jitter.x, jitter.y) >= best_room * 0.92:
		return jitter
	return best


## The gate faces whichever cardinal direction looks at the nearest road stub, so the
## causeway always runs toward a street rather than into open country.
func _plan_gate(out: CastleLayout) -> void:
	var centre := Vector2i(
		out.plateau_rect.position.x + out.plateau_rect.size.x / 2,
		out.plateau_rect.position.y + out.plateau_rect.size.y / 2
	)
	out.road_target = _nearest_road_cell(centre)
	var away := out.road_target - centre
	if absi(away.x) >= absi(away.y):
		out.gate_dir = Vector2i(1 if away.x >= 0 else -1, 0)
	else:
		out.gate_dir = Vector2i(0, 1 if away.y >= 0 else -1)
	out.gate_width = rng.randi_range(GATE_W_MIN, GATE_W_MAX) | 1
	out.gate_height = rng.randi_range(GATE_H_MIN, GATE_H_MAX)
	## Slide the passage along the curtain, but keep the gatehouse and its turrets clear
	## of the corner towers.
	var lateral_span := out.wall_rect.size.y if out.gate_dir.x != 0 else out.wall_rect.size.x
	var slack := maxi(lateral_span / 2 - TOWER_R_MAX - GATE_PIER - GATE_TOWER_R_MAX - 4, 0)
	var shift := rng.randi_range(-slack, slack) if slack > 0 else 0
	if out.gate_dir.x != 0:
		out.gate_center = Vector2i(
			out.wall_rect.end.x - 1 if out.gate_dir.x > 0 else out.wall_rect.position.x,
			centre.y + shift
		)
	else:
		out.gate_center = Vector2i(
			centre.x + shift,
			out.wall_rect.end.y - 1 if out.gate_dir.y > 0 else out.wall_rect.position.y
		)
	out.gatehouse_rect = _gatehouse_rect(out)


func _gatehouse_rect(out: CastleLayout) -> Rect2i:
	var half := out.gate_width / 2 + GATE_PIER
	var wr := out.wall_rect
	if out.gate_dir.x != 0:
		var x_lo := (
			wr.end.x - out.wall_thick if out.gate_dir.x > 0 else wr.position.x - GATE_PROJECT
		)
		var x_hi := (
			wr.end.x - 1 + GATE_PROJECT
			if out.gate_dir.x > 0
			else wr.position.x + out.wall_thick - 1
		)
		return Rect2i(x_lo, out.gate_center.y - half, x_hi - x_lo + 1, half * 2 + 1)
	var z_lo := (
		wr.end.y - out.wall_thick if out.gate_dir.y > 0 else wr.position.y - GATE_PROJECT
	)
	var z_hi := (
		wr.end.y - 1 + GATE_PROJECT
		if out.gate_dir.y > 0
		else wr.position.y + out.wall_thick - 1
	)
	return Rect2i(out.gate_center.x - half, z_lo, half * 2 + 1, z_hi - z_lo + 1)


## Reserved footprint for the Phase 2 keep: at the back of the bailey, away from the gate,
## the way a motte keep faces down its own approach.
func _plan_keep(out: CastleLayout) -> void:
	var inner := out.courtyard_rect.grow(-KEEP_MARGIN)
	var kw := mini(rng.randi_range(KEEP_W_MIN, KEEP_W_MAX), inner.size.x)
	var kd := mini(rng.randi_range(KEEP_D_MIN, KEEP_D_MAX), inner.size.y)
	if kw < KEEP_W_MIN or kd < KEEP_D_MIN:
		push_error(
			"CastleComposer: bailey %dx%d cannot reserve a keep footprint"
			% [inner.size.x, inner.size.y]
		)
		return
	var centre := Vector2i(
		inner.position.x + inner.size.x / 2, inner.position.y + inner.size.y / 2
	)
	## Push the keep to the far side of the bailey, then jitter across the approach.
	var back := -out.gate_dir
	var push_x := (inner.size.x - kw) / 2
	var push_z := (inner.size.y - kd) / 2
	var lateral := rng.randi_range(-6, 6)
	var kx := centre.x + back.x * push_x + (lateral if back.x == 0 else 0) - kw / 2
	var kz := centre.y + back.y * push_z + (lateral if back.y == 0 else 0) - kd / 2
	out.keep_rect = Rect2i(
		clampi(kx, inner.position.x, inner.end.x - kw),
		clampi(kz, inner.position.y, inner.end.y - kd),
		kw,
		kd
	)
	## The path target has to stay out of the footprint Phase 2 will fill, so it sits in
	## the open half of the bailey between the keep and the gate.
	var target := Vector2i(
		out.courtyard_rect.position.x + out.courtyard_rect.size.x / 2,
		out.courtyard_rect.position.y + out.courtyard_rect.size.y / 2
	)
	if out.gate_dir.x != 0:
		var edge_x := (
			out.keep_rect.end.x + 6 if out.gate_dir.x > 0 else out.keep_rect.position.x - 6
		)
		target.x = clampi(
			maxi(target.x, edge_x) if out.gate_dir.x > 0 else mini(target.x, edge_x),
			out.courtyard_rect.position.x + 3,
			out.courtyard_rect.end.x - 4
		)
	else:
		var edge_z := (
			out.keep_rect.end.y + 6 if out.gate_dir.y > 0 else out.keep_rect.position.y - 6
		)
		target.y = clampi(
			maxi(target.y, edge_z) if out.gate_dir.y > 0 else mini(target.y, edge_z),
			out.courtyard_rect.position.y + 3,
			out.courtyard_rect.end.y - 4
		)
	if out.keep_rect.has_point(target):
		push_error(
			"CastleComposer: courtyard target %s fell inside the reserved keep %s"
			% [target, out.keep_rect]
		)
	out.courtyard_center = target


## Storeys, stair lanes and room subdivision for the keep. Planned in this order because a
## flight has to claim its lane before the subdivision is allowed to cut anywhere.
func _plan_keep_interior(out: CastleLayout) -> void:
	out.keep_wall_thick = KEEP_WALL_T
	out.keep_level_h = KEEP_LEVEL_H
	out.keep_slab_thick = KEEP_SLAB_T
	out.keep_plate_rect = out.keep_rect.grow(-KEEP_WALL_T)
	var storeys := rng.randi_range(KEEP_STOREYS_MIN, KEEP_STOREYS_MAX)
	## The hall swallows the storey above it, so it can be neither the top storey nor the
	## one below it.
	out.keep_hall_storey = rng.randi_range(0, storeys - 3)
	out.keep_roof_y = out.keep_floor_y(storeys - 1) + KEEP_LEVEL_H
	_plan_keep_entrance(out)
	_plan_keep_flights(out, storeys)
	_plan_keep_floors(out, storeys)


## The keep's own gate, in the face that looks back down the bailey at the gatehouse.
func _plan_keep_entrance(out: CastleLayout) -> void:
	var kr := out.keep_rect
	var fn := out.gate_dir
	var side := Vector2i(-fn.y, fn.x)
	var face_len := kr.size.y if fn.x != 0 else kr.size.x
	var slack := face_len / 2 - (KEEP_DOOR_W / 2 + KEEP_WALL_T + 4)
	var shift := rng.randi_range(-slack, slack) if slack > 0 else 0
	var c := Vector2i(
		kr.position.x + kr.size.x / 2, kr.position.y + kr.size.y / 2
	) + side * shift
	if fn.x != 0:
		c.x = kr.end.x - 1 if fn.x > 0 else kr.position.x
	else:
		c.y = kr.end.y - 1 if fn.y > 0 else kr.position.y
	var d := CastleDoorway.new()
	d.center = c
	d.axis = -fn
	d.width = KEEP_DOOR_W
	d.depth = KEEP_WALL_T
	d.storey = 0
	d.floor_y = out.courtyard_y
	d.height = KEEP_LEVEL_H - KEEP_SLAB_T
	out.keep_entrance = d
	## A partition butting into the entrance would split the opening into two slots too
	## narrow for nav, so the three columns inside the threshold are off limits.
	var half := KEEP_DOOR_W / 2 + 1
	_keep_reserved.append(
		_span_rect(
			c + d.axis * KEEP_WALL_T - side * half,
			c + d.axis * (KEEP_WALL_T + 2) + side * half
		)
	)


## One flight per pair of consecutive floored storeys. The pair either side of the great
## hall gets a single long flight, which is what makes the hall read as double height from
## inside rather than as two rooms with a missing slab.
func _plan_keep_flights(out: CastleLayout, storeys: int) -> void:
	var floored: Array[int] = []
	for n in range(storeys):
		if n != out.keep_hall_storey + 1:
			floored.append(n)
	var slots: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: int = slots[i]
		slots[i] = slots[j]
		slots[j] = swap
	for i in range(floored.size() - 1):
		var a: int = floored[i]
		var b: int = floored[i + 1]
		var st := _pick_stair_slot(
			out, slots, (b - a) * KEEP_LEVEL_H, out.keep_floor_y(a), a, b
		)
		if st == null:
			return
		out.keep_stairs.append(st)
		_keep_reserved.append(st.footprint().grow(LANE_MARGIN))


## Takes the first free lane out of the shuffled slot order. Slots hug an inside face and
## start at one of its corners: a flight parked in the middle of the plate would block
## every legal partition cut on that axis.
func _pick_stair_slot(
	out: CastleLayout, slots: Array[int], rise: int, y_from: int, a: int, b: int
) -> CastleStair:
	for i in range(slots.size()):
		var st := _stair_for_slot(out, slots[i], rise, y_from, a, b)
		if _keep_blocked(st.footprint().grow(LANE_MARGIN)):
			continue
		slots.remove_at(i)
		return st
	push_error(
		"CastleComposer: no free lane in the %s keep plate for a %d voxel flight %d→%d"
		% [out.keep_plate_rect.size, rise, a, b]
	)
	return null


func _stair_for_slot(
	out: CastleLayout, slot: int, rise: int, y_from: int, a: int, b: int
) -> CastleStair:
	var faces: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var fn: Vector2i = faces[slot / 2]
	var along := Vector2i(-fn.y, fn.x)
	if (slot % 2) == 1:
		along = -along
	var st := CastleStair.new()
	st.dir = along
	st.across = -fn
	st.lane_w = KEEP_STAIR_W
	st.rise = rise
	st.y_from = y_from
	st.from_storey = a
	st.to_storey = b
	## Off the corner by the lane margin, or the bottom tread would be boxed in by the two
	## outer walls meeting behind it and the flight could only be entered from above.
	st.origin = (
		_corner_column(out.keep_plate_rect, fn, -along) + along * (LANE_MARGIN + 1)
	)
	assert(
		out.keep_plate_rect.encloses(st.footprint()),
		"keep plate is too small for a %d voxel flight" % rise
	)
	return st


func _plan_keep_floors(out: CastleLayout, storeys: int) -> void:
	for n in range(storeys):
		var f := CastleFloor.new()
		f.storey = n
		f.floor_y = out.keep_floor_y(n)
		f.has_slab = n != out.keep_hall_storey + 1
		if not f.has_slab:
			out.keep_floors.append(f)
			continue
		if n == out.keep_hall_storey:
			f.air_h = 2 * KEEP_LEVEL_H - KEEP_SLAB_T
			var whole: Array[Rect2i] = [out.keep_plate_rect]
			f.rooms = whole
			f.hall_index = 0
		else:
			f.air_h = KEEP_LEVEL_H - KEEP_SLAB_T
			f.rooms = _subdivide(out.keep_plate_rect, f, out)
		out.keep_floors.append(f)


## Binary subdivision with one doorway per cut, so a floor is a spanning tree of rooms and
## no branch of the recursion can produce a sealed one.
func _subdivide(cell: Rect2i, f: CastleFloor, out: CastleLayout) -> Array[Rect2i]:
	var leaf: Array[Rect2i] = [cell]
	var want := cell.size.x > KEEP_ROOM_SPLIT or cell.size.y > KEEP_ROOM_SPLIT
	if not want and rng.randf() < 0.5:
		return leaf
	## Cut the long way first, so a cell tends toward square rooms rather than corridors.
	var order: Array[int] = [0, 1]
	if cell.size.y > cell.size.x:
		order = [1, 0]
	for axis: int in order:
		var coords := _split_coords(cell, axis)
		if coords.is_empty():
			continue
		var c: int = coords[rng.randi() % coords.size()]
		var lo := cell
		var hi := cell
		if axis == 0:
			lo.size.x = c
			hi.position.x = cell.position.x + c + KEEP_PART_T
			hi.size.x = cell.size.x - c - KEEP_PART_T
		else:
			lo.size.y = c
			hi.position.y = cell.position.y + c + KEEP_PART_T
			hi.size.y = cell.size.y - c - KEEP_PART_T
		var rooms_lo := _subdivide(lo, f, out)
		var rooms_hi := _subdivide(hi, f, out)
		_link_across(rooms_lo, rooms_hi, axis, _axis_lo(cell, axis) + c, f, out)
		var rooms: Array[Rect2i] = []
		rooms.append_array(rooms_lo)
		rooms.append_array(rooms_hi)
		return rooms
	return leaf


## Local offsets a partition may start at: both halves keep KEEP_ROOM_MIN, and the band
## itself misses every reserved lane.
func _split_coords(cell: Rect2i, axis: int) -> Array[int]:
	var out: Array[int] = []
	var size := cell.size.x if axis == 0 else cell.size.y
	for c in range(KEEP_ROOM_MIN, size - KEEP_PART_T - KEEP_ROOM_MIN + 1):
		if _keep_blocked(_band_rect(cell, axis, c)):
			continue
		out.append(c)
	return out


func _band_rect(cell: Rect2i, axis: int, c: int) -> Rect2i:
	if axis == 0:
		return Rect2i(cell.position.x + c, cell.position.y, KEEP_PART_T, cell.size.y)
	return Rect2i(cell.position.x, cell.position.y + c, cell.size.x, KEEP_PART_T)


## Cuts the one doorway that joins the two halves of a split, through the widest pair of
## rooms that face each other across the partition.
func _link_across(
	rooms_lo: Array[Rect2i],
	rooms_hi: Array[Rect2i],
	axis: int,
	band_lo: int,
	f: CastleFloor,
	out: CastleLayout
) -> void:
	var other := 1 - axis
	var band_hi := band_lo + KEEP_PART_T
	var best_span := 0
	var best_t := 0
	for ra: Rect2i in rooms_lo:
		if _axis_hi(ra, axis) != band_lo:
			continue
		for rb: Rect2i in rooms_hi:
			if _axis_lo(rb, axis) != band_hi:
				continue
			var lo := maxi(_axis_lo(ra, other), _axis_lo(rb, other))
			var hi := mini(_axis_hi(ra, other), _axis_hi(rb, other))
			if hi - lo <= best_span:
				continue
			var t := _door_slot(lo, hi, axis, band_lo)
			if t == NO_SLOT:
				continue
			best_span = hi - lo
			best_t = t
	if best_span == 0:
		push_error(
			(
				"CastleComposer: storey %d has no room pair wide enough to door across"
				+ " the partition at %d"
			)
			% [f.storey, band_lo]
		)
		return
	var d := CastleDoorway.new()
	d.axis = Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
	d.center = (
		Vector2i(band_lo, best_t) if axis == 0 else Vector2i(best_t, band_lo)
	)
	d.width = KEEP_DOOR_W
	d.depth = KEEP_PART_T
	d.storey = f.storey
	d.floor_y = f.floor_y
	d.height = f.air_h
	out.keep_doorways.append(d)


## Centre offset along the partition for a doorway inside [lo, hi), closest to the middle
## of the overlap that clears the reserved lanes. NO_SLOT when nothing fits.
func _door_slot(lo: int, hi: int, axis: int, band_lo: int) -> int:
	var half := KEEP_DOOR_W / 2
	var first := lo + half
	var last := hi - half - 1
	if last < first:
		return NO_SLOT
	var mid := (lo + hi) / 2
	for step in range(0, hi - lo):
		for sign: int in [1, -1]:
			var t := mid + step * sign
			if t < first or t > last:
				continue
			var check := (
				Rect2i(band_lo - 1, t - half, KEEP_PART_T + 2, KEEP_DOOR_W)
				if axis == 0
				else Rect2i(t - half, band_lo - 1, KEEP_DOOR_W, KEEP_PART_T + 2)
			)
			if not _keep_blocked(check):
				return t
			if step == 0:
				break
	return NO_SLOT


## Ramp from the bailey to the curtain crown, laid against the inside face of one wall.
## Every riser is one voxel, same as the causeway, so the crown is a two-way walk.
func _plan_crown_ramp(out: CastleLayout) -> void:
	var sides: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for i in range(sides.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap := sides[i]
		sides[i] = sides[j]
		sides[j] = swap
	var rise := out.wall_height
	for sn: Vector2i in sides:
		if sn == out.gate_dir:
			continue
		var st := _crown_ramp_on(out, sn, rise)
		if st == null:
			continue
		out.crown_stair = st
		out.keep_stairs.append(st)
		out.crown_walk = st.column(rise + 1, 0) - st.across * 3
		return
	push_error("CastleComposer: no curtain side is clear enough for a crown ramp")


func _crown_ramp_on(out: CastleLayout, sn: Vector2i, rise: int) -> CastleStair:
	var cr := out.courtyard_rect
	var along := Vector2i(-sn.y, sn.x)
	var run := rise + 3
	var span := cr.size.y if sn.x != 0 else cr.size.x
	if run + 2 * LANE_MARGIN + 2 > span:
		return null
	var starts: Array[int] = []
	for off in range(LANE_MARGIN + 1, span - run - LANE_MARGIN):
		var st := _crown_ramp_at(out, sn, along, rise, off)
		## The ramp and the crown it lands on both have to miss every tower bulge, the
		## gatehouse block and the keep.
		var claim := st.footprint().grow(1).merge(
			_span_rect(
				st.column(0, 0), st.column(run - 1, 0) - st.across * out.wall_thick
			)
		)
		if _crown_blocked(out, claim):
			continue
		starts.append(off)
	if starts.is_empty():
		return null
	return _crown_ramp_at(out, sn, along, rise, starts[rng.randi() % starts.size()])


func _crown_ramp_at(
	out: CastleLayout, sn: Vector2i, along: Vector2i, rise: int, off: int
) -> CastleStair:
	var st := CastleStair.new()
	st.dir = along
	st.across = -sn
	st.lane_w = CROWN_RAMP_W
	st.rise = rise
	st.y_from = out.courtyard_y
	st.from_storey = -1
	st.to_storey = -1
	st.origin = _corner_column(out.courtyard_rect, sn, -along) + along * off
	return st


func _crown_blocked(out: CastleLayout, claim: Rect2i) -> bool:
	if claim.intersects(out.gatehouse_rect.grow(2)):
		return true
	if claim.intersects(out.keep_rect.grow(3)):
		return true
	for t: CastleTower in out.towers:
		if claim.intersects(
			Rect2i(t.center - Vector2i(t.radius, t.radius), Vector2i.ONE * (2 * t.radius + 1))
		):
			return true
	return false


func _keep_blocked(r: Rect2i) -> bool:
	for taken: Rect2i in _keep_reserved:
		if r.intersects(taken):
			return true
	return false


## Four corner towers plus up to two mid-wall bastions, and the pair flanking the gate.
func _plan_towers(out: CastleLayout) -> void:
	var wr := out.wall_rect
	var corners: Array[Vector2i] = [
		Vector2i(wr.position.x, wr.position.y),
		Vector2i(wr.end.x - 1, wr.position.y),
		Vector2i(wr.position.x, wr.end.y - 1),
		Vector2i(wr.end.x - 1, wr.end.y - 1),
	]
	## One plan for the whole castle: mixing round and square turrets on one curtain reads
	## as two builds, not one fortress.
	var round_plan := rng.randf() < 0.5
	for corner: Vector2i in corners:
		var t := CastleTower.new()
		t.center = corner
		t.radius = mini(rng.randi_range(TOWER_R_MIN, TOWER_R_MAX), out.wall_inset)
		t.top_y = COURTYARD_Y + out.wall_height + rng.randi_range(
			TOWER_EXTRA_MIN, TOWER_EXTRA_MAX
		)
		t.round_plan = round_plan
		t.kind = CastleTower.KIND_CORNER
		out.towers.append(t)
	var sides: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var mids := rng.randi_range(0, MID_TOWERS_MAX)
	for i in range(sides.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap := sides[i]
		sides[i] = sides[j]
		sides[j] = swap
	for side: Vector2i in sides:
		if out.towers.size() >= 4 + mids:
			break
		if side == out.gate_dir:
			continue
		var t2 := CastleTower.new()
		t2.center = _wall_mid_point(out, side)
		t2.radius = mini(rng.randi_range(TOWER_R_MIN, TOWER_R_MAX - 1), out.wall_inset)
		t2.top_y = COURTYARD_Y + out.wall_height + rng.randi_range(
			TOWER_EXTRA_MIN, TOWER_EXTRA_MAX
		)
		t2.round_plan = round_plan
		t2.kind = CastleTower.KIND_MID
		out.towers.append(t2)
	## Gate turrets straddle the passage on the outer face of the gatehouse.
	var gate_r := rng.randi_range(GATE_TOWER_R_MIN, GATE_TOWER_R_MAX)
	var lateral := out.gate_width / 2 + gate_r
	var side_axis := Vector2i(-out.gate_dir.y, out.gate_dir.x)
	var face := _gatehouse_face_point(out)
	for sign: int in [-1, 1]:
		var t3 := CastleTower.new()
		t3.center = face + side_axis * lateral * sign
		t3.radius = gate_r
		t3.top_y = COURTYARD_Y + out.wall_height + rng.randi_range(
			GATE_EXTRA_H_MIN + 4, GATE_EXTRA_H_MAX + 7
		)
		t3.round_plan = round_plan
		t3.kind = CastleTower.KIND_GATE
		out.towers.append(t3)


func _wall_mid_point(out: CastleLayout, side: Vector2i) -> Vector2i:
	var wr := out.wall_rect
	if side.x > 0:
		return Vector2i(wr.end.x - 1, wr.position.y + wr.size.y / 2)
	if side.x < 0:
		return Vector2i(wr.position.x, wr.position.y + wr.size.y / 2)
	if side.y > 0:
		return Vector2i(wr.position.x + wr.size.x / 2, wr.end.y - 1)
	return Vector2i(wr.position.x + wr.size.x / 2, wr.position.y)


## Outer face of the gatehouse on the gate axis, on the passage centre line.
func _gatehouse_face_point(out: CastleLayout) -> Vector2i:
	var gh := out.gatehouse_rect
	if out.gate_dir.x > 0:
		return Vector2i(gh.end.x - 1, out.gate_center.y)
	if out.gate_dir.x < 0:
		return Vector2i(gh.position.x, out.gate_center.y)
	if out.gate_dir.y > 0:
		return Vector2i(out.gate_center.x, gh.end.y - 1)
	return Vector2i(out.gate_center.x, gh.position.y)


func _plan_causeway(out: CastleLayout) -> void:
	out.causeway_hw = rng.randi_range(CAUSEWAY_HW_MIN, CAUSEWAY_HW_MAX)
	out.causeway_run = PLINTH_RISE * CAUSEWAY_STEP_RUN
	var edge := _plateau_edge_point(out)
	var line: Array[Vector2i] = []
	for s in range(out.causeway_run, -1, -1):
		line.append(edge + out.gate_dir * s)
	out.causeway_line = line


## Plateau boundary column on the gate axis, on the passage centre line. Station 0 of the
## causeway — everything further out is ramp.
func _plateau_edge_point(out: CastleLayout) -> Vector2i:
	var pr := out.plateau_rect
	if out.gate_dir.x > 0:
		return Vector2i(pr.end.x - 1, out.gate_center.y)
	if out.gate_dir.x < 0:
		return Vector2i(pr.position.x, out.gate_center.y)
	if out.gate_dir.y > 0:
		return Vector2i(out.gate_center.x, pr.end.y - 1)
	return Vector2i(out.gate_center.x, pr.position.y)


func _nearest_road_cell(from_xz: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var half := cell_size / 2
	var cx0 := _x0 / cell_size
	var cz0 := _z0 / cell_size
	var cx1 := (_x1 - 1) / cell_size
	var cz1 := (_z1 - 1) / cell_size
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var here := Vector2i(cx * cell_size + half, cz * cell_size + half)
			var dx := here.x - from_xz.x
			var dz := here.y - from_xz.y
			var dist := dx * dx + dz * dz
			if dist < best_d:
				best_d = dist
				best = here
	if best.x < 0:
		push_error("CastleComposer: reserve has no road cell for the causeway to reach")
		return from_xz + Vector2i(0, 1)
	return best


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

## Solid battered mass from the deck to the courtyard datum. Nothing but castle block goes
## into it: Phase 3 hollows the DUNGEON_Y0..DUNGEON_Y1 band out of exactly this fill.
func _build_plinth() -> void:
	var pr := layout.plinth_rect
	var plateau := layout.plateau_rect
	for z in range(pr.position.y, pr.end.y):
		for x in range(pr.position.x, pr.end.x):
			if not _in_region(x, z):
				continue
			var k := _outside_dist(plateau, x, z)
			var h := PLINTH_RISE - BATTER_RUN * k
			if h <= 0:
				continue
			var top := ground_y + h
			brush.fill_box(
				Vector3i(x, ground_y + 1, z),
				Vector3i(x + 1, top + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			_plinth_voxels += h
			if not _detail:
				continue
			if k > 0:
				## The whole riser weathers as one face, so the exposed side and its top
				## cap have to agree — a per-voxel dice speckles the scarp instead.
				if _moss_here(x, z, float(k) * 0.05):
					brush.fill_box(
						Vector3i(x, top - BATTER_RUN + 1, z),
						Vector3i(x + 1, top + 1, z + 1),
						VoxelMaterial.CASTLE_BLOCK_MOSSY
					)
				continue
			## Moss creeping between the courtyard flags.
			if _moss_here(x, z, -0.14):
				brush.set_vox(Vector3i(x, top, z), VoxelMaterial.CASTLE_BLOCK_MOSSY)


func _build_curtain() -> void:
	var wr := layout.wall_rect
	var y0 := COURTYARD_Y + 1
	var y1 := COURTYARD_Y + layout.wall_height
	for z in range(wr.position.y, wr.end.y):
		for x in range(wr.position.x, wr.end.x):
			if not _in_region(x, z):
				continue
			var inset := _inside_dist(wr, x, z)
			if inset >= layout.wall_thick:
				continue
			brush.fill_box(
				Vector3i(x, y0, z), Vector3i(x + 1, y1 + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if not _detail:
				continue
			_weather_base(x, z, y0)
			## Merlons on the outer line only, so the course behind them stays a wall-walk.
			if inset == 0 and ((x + z) % 2) == 0:
				brush.fill_box(
					Vector3i(x, y1 + 1, z),
					Vector3i(x + 1, y1 + 1 + MERLON_H, z + 1),
					VoxelMaterial.CASTLE_BLOCK
				)


func _build_towers() -> void:
	for tower: CastleTower in layout.towers:
		_build_tower(tower)


func _build_tower(tower: CastleTower) -> void:
	var r := tower.radius
	var y0 := COURTYARD_Y + 1
	for z in range(tower.center.y - r, tower.center.y + r + 1):
		for x in range(tower.center.x - r, tower.center.x + r + 1):
			if not _in_region(x, z):
				continue
			var edge := _tower_edge(tower, x, z)
			if edge < 0:
				continue
			## A tower on the curtain corner overhangs the terrace, so its shaft has to
			## carry down to whatever the plinth offers under it.
			var base := ground_y + PLINTH_RISE - BATTER_RUN * _outside_dist(
				layout.plateau_rect, x, z
			)
			brush.fill_box(
				Vector3i(x, mini(base + 1, y0), z),
				Vector3i(x + 1, tower.top_y + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if not _detail:
				continue
			_weather_base(x, z, y0)
			if edge == 0 and ((x + z) % 2) == 0:
				brush.fill_box(
					Vector3i(x, tower.top_y + 1, z),
					Vector3i(x + 1, tower.top_y + 1 + MERLON_H, z + 1),
					VoxelMaterial.CASTLE_BLOCK
				)


## -1 outside the tower, 0 on its rim, 1 inside. Round plans use the Euclidean radius so
## the turret reads as a drum rather than a chamfered box.
func _tower_edge(tower: CastleTower, x: int, z: int) -> int:
	var dx := x - tower.center.x
	var dz := z - tower.center.y
	if tower.round_plan:
		var d2 := dx * dx + dz * dz
		if d2 > tower.radius * tower.radius:
			return -1
		return 0 if d2 > (tower.radius - 1) * (tower.radius - 1) else 1
	var cheb := maxi(absi(dx), absi(dz))
	if cheb > tower.radius:
		return -1
	return 0 if cheb == tower.radius else 1


## Gatehouse block, then the passage bored through it. The carve runs last so it wins over
## the curtain and the turrets it is cut through.
func _build_gatehouse() -> void:
	var gh := layout.gatehouse_rect
	var y0 := COURTYARD_Y + 1
	var y1 := COURTYARD_Y + layout.wall_height + rng.randi_range(
		GATE_EXTRA_H_MIN, GATE_EXTRA_H_MAX
	)
	for z in range(gh.position.y, gh.end.y):
		for x in range(gh.position.x, gh.end.x):
			if not _in_region(x, z):
				continue
			brush.fill_box(
				Vector3i(x, y0, z), Vector3i(x + 1, y1 + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if not _detail:
				continue
			_weather_base(x, z, y0)
			var rim := _inside_dist(gh, x, z) == 0
			if rim and ((x + z) % 2) == 0:
				brush.fill_box(
					Vector3i(x, y1 + 1, z),
					Vector3i(x + 1, y1 + 1 + MERLON_H, z + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
	_carve_gate_passage()


func _carve_gate_passage() -> void:
	var gh := layout.gatehouse_rect
	var half := layout.gate_width / 2
	var side_axis := Vector2i(-layout.gate_dir.y, layout.gate_dir.x)
	## Deep enough to clear the gatehouse, the curtain behind it and the turrets beside it.
	var depth := (gh.size.x if layout.gate_dir.x != 0 else gh.size.y) + GATE_TOWER_R_MAX
	var mouth := _gatehouse_face_point(layout) + layout.gate_dir * GATE_TOWER_R_MAX
	for row in range(1, layout.gate_height + 1):
		## Stepped arch over the opening — the threshold row keeps the full width.
		var shoulder := maxi(row - (layout.gate_height - 2), 0)
		var w := half - shoulder
		if w < 0:
			continue
		var y := COURTYARD_Y + row
		for s in range(depth + 1):
			var at := mouth - layout.gate_dir * s
			for t in range(-w, w + 1):
				var p := at + side_axis * t
				if not _in_region(p.x, p.y):
					continue
				var vox := Vector3i(p.x, y, p.y)
				## Only masonry is bored out. Writing AIR over open sky in front of the
				## gate would materialise empty blocks for nothing.
				if brush.get_vox(vox) == VoxelMaterial.AIR:
					continue
				brush.set_vox(vox, VoxelMaterial.AIR)


## Ramped embankment from the street deck up to the gate, one voxel of rise per
## CAUSEWAY_STEP_RUN forward, with a battlemented parapet down each side.
func _build_causeway() -> void:
	var hw := layout.causeway_hw
	var side_axis := Vector2i(-layout.gate_dir.y, layout.gate_dir.x)
	var edge := _plateau_edge_point(layout)
	for s in range(1, layout.causeway_run):
		var h := PLINTH_RISE - s / CAUSEWAY_STEP_RUN
		if h <= 0:
			continue
		var top := ground_y + h
		var centre := edge + layout.gate_dir * s
		for t in range(-hw, hw + 1):
			var p := centre + side_axis * t
			if not _in_region(p.x, p.y):
				continue
			brush.fill_box(
				Vector3i(p.x, ground_y + 1, p.y),
				Vector3i(p.x + 1, top + 1, p.y + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if not _detail:
				continue
			if absi(t) == hw:
				## Parapet, alternating full and half height so the ramp reads as built.
				var ph := PARAPET_H if (s % 2) == 0 else PARAPET_H - 1
				brush.fill_box(
					Vector3i(p.x, top + 1, p.y),
					Vector3i(p.x + 1, top + 1 + ph, p.y + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
			elif _moss_here(p.x, p.y, 0.0):
				brush.set_vox(Vector3i(p.x, top, p.y), VoxelMaterial.CASTLE_BLOCK_MOSSY)
	_pave_approach()


## Gravel track from the foot of the ramp to the road stub it was aimed at. The meadow is
## already walkable, so this is what the approach *reads* as, not what makes it passable.
func _pave_approach() -> void:
	var hw := layout.causeway_hw
	var side_axis := Vector2i(-layout.gate_dir.y, layout.gate_dir.x)
	var at := _plateau_edge_point(layout) + layout.gate_dir * layout.causeway_run
	var target := layout.road_target
	var along_x := layout.gate_dir.x != 0
	## Straight out along the gate axis first, then one lateral leg — an approach road is
	## laid out, not worn in.
	var guard := _w + _d
	while guard > 0:
		guard -= 1
		if not _in_region(at.x, at.y):
			break
		if _is_road_cell(at.x, at.y):
			break
		for t in range(-hw, hw + 1):
			var p := at + side_axis * t
			if not _in_region(p.x, p.y):
				continue
			brush.set_vox(Vector3i(p.x, ground_y, p.y), VoxelMaterial.GRAVEL)
		if along_x and at.x != target.x:
			at.x += 1 if target.x > at.x else -1
		elif not along_x and at.y != target.y:
			at.y += 1 if target.y > at.y else -1
		elif at.x != target.x:
			at.x += 1 if target.x > at.x else -1
		elif at.y != target.y:
			at.y += 1 if target.y > at.y else -1
		else:
			break


# ---------------------------------------------------------------------------
# Keep
# ---------------------------------------------------------------------------

## Only the masonry is written: the room air is voxels nobody ever touches, so a keep
## costs its shell, its slabs and its partitions and nothing else. The four carves that
## follow are the only AIR the keep writes, and every one of them is bounded to the
## opening it cuts.
func _build_keep() -> void:
	_build_keep_shell()
	for f: CastleFloor in layout.keep_floors:
		_build_keep_floor(f)
	for st: CastleStair in layout.keep_stairs:
		if st.from_storey >= 0:
			_build_flight(st)
	_build_keep_roof()
	_carve_doorway(layout.keep_entrance)
	for d: CastleDoorway in layout.keep_doorways:
		_carve_doorway(d)
	if _detail:
		_carve_keep_windows()


func _build_keep_shell() -> void:
	var kr := layout.keep_rect
	var y0 := layout.courtyard_y + 1
	for z in range(kr.position.y, kr.end.y):
		for x in range(kr.position.x, kr.end.x):
			if not _in_region(x, z):
				continue
			if _inside_dist(kr, x, z) >= KEEP_WALL_T:
				continue
			brush.fill_box(
				Vector3i(x, y0, z),
				Vector3i(x + 1, layout.keep_roof_y + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if _detail:
				_weather_base(x, z, y0)


func _build_keep_floor(f: CastleFloor) -> void:
	if not f.has_slab:
		return
	var plate := layout.keep_plate_rect
	var wells := _well_columns(f.storey)
	for z in range(plate.position.y, plate.end.y):
		for x in range(plate.position.x, plate.end.x):
			if not _in_region(x, z):
				continue
			var col := Vector2i(x, z)
			## Storey 0 stands on the courtyard, which the plinth already cast solid.
			if f.storey > 0 and not wells.has(col):
				brush.fill_box(
					Vector3i(x, f.floor_y - KEEP_SLAB_T + 1, z),
					Vector3i(x + 1, f.floor_y + 1, z + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
			if _room_at_column(f, col) >= 0:
				continue
			brush.fill_box(
				Vector3i(x, f.floor_y + 1, z),
				Vector3i(x + 1, f.floor_y + f.air_h + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)


## Roof slab plus corner turrets, so the keep tops the curtain with a silhouette of its
## own instead of a flat lid.
func _build_keep_roof() -> void:
	var kr := layout.keep_rect
	var roof := layout.keep_roof_y
	for z in range(kr.position.y, kr.end.y):
		for x in range(kr.position.x, kr.end.x):
			if not _in_region(x, z):
				continue
			brush.fill_box(
				Vector3i(x, roof - KEEP_SLAB_T + 1, z),
				Vector3i(x + 1, roof + 1, z + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
			if not _detail:
				continue
			if _inside_dist(kr, x, z) == 0 and ((x + z) % 2) == 0:
				brush.fill_box(
					Vector3i(x, roof + 1, z),
					Vector3i(x + 1, roof + 1 + MERLON_H, z + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
	var corners: Array[Vector2i] = [
		Vector2i(kr.position.x + KEEP_TURRET_R, kr.position.y + KEEP_TURRET_R),
		Vector2i(kr.end.x - 1 - KEEP_TURRET_R, kr.position.y + KEEP_TURRET_R),
		Vector2i(kr.position.x + KEEP_TURRET_R, kr.end.y - 1 - KEEP_TURRET_R),
		Vector2i(kr.end.x - 1 - KEEP_TURRET_R, kr.end.y - 1 - KEEP_TURRET_R),
	]
	var top := roof + KEEP_TURRET_EXTRA
	for c: Vector2i in corners:
		for z2 in range(c.y - KEEP_TURRET_R, c.y + KEEP_TURRET_R + 1):
			for x2 in range(c.x - KEEP_TURRET_R, c.x + KEEP_TURRET_R + 1):
				if not _in_region(x2, z2):
					continue
				brush.fill_box(
					Vector3i(x2, roof + 1, z2),
					Vector3i(x2 + 1, top + 1, z2 + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
				if not _detail:
					continue
				var rim := maxi(absi(x2 - c.x), absi(z2 - c.y)) == KEEP_TURRET_R
				if rim and ((x2 + z2) % 2) == 0:
					brush.fill_box(
						Vector3i(x2, top + 1, z2),
						Vector3i(x2 + 1, top + 1 + MERLON_H, z2 + 1),
						VoxelMaterial.CASTLE_BLOCK
					)


## Solid masonry ramp of one-voxel treads, with a parapet down the open side. The far side
## abuts the wall the lane was laid against, so a body cannot walk off it either way.
func _build_flight(st: CastleStair) -> void:
	## A keep flight arrives on the slab of the storey above; the crown ramp has no slab
	## waiting for it, so its landing is the last two treads of the ramp itself.
	var last := st.run_len() - 1 if st.to_storey < 0 else st.run_len() - 2
	for t in range(last + 1):
		var s := st.surface_at(t)
		for k in range(st.lane_w):
			var p := st.column(t, k)
			if not _in_region(p.x, p.y):
				continue
			brush.fill_box(
				Vector3i(p.x, st.y_from + 1, p.y),
				Vector3i(p.x + 1, s + 1, p.y + 1),
				VoxelMaterial.CASTLE_BLOCK
			)
	for t2 in range(st.run_len()):
		var p2 := st.column(t2, st.lane_w)
		if not _in_region(p2.x, p2.y):
			continue
		brush.fill_box(
			Vector3i(p2.x, st.y_from + 1, p2.y),
			Vector3i(p2.x + 1, st.surface_at(t2) + KEEP_RAIL_H + 1, p2.y + 1),
			VoxelMaterial.CASTLE_BLOCK
		)
	if st.to_storey < 0:
		return
	## Kerb across the head of the well, or the floor above ends in an unfenced drop the
	## length of the flight.
	var y_top := st.top_y()
	for k2 in range(st.lane_w):
		var p3 := st.column(0, k2)
		if not _in_region(p3.x, p3.y):
			continue
		brush.fill_box(
			Vector3i(p3.x, y_top + 1, p3.y),
			Vector3i(p3.x + 1, y_top + KEEP_RAIL_H + 1, p3.y + 1),
			VoxelMaterial.CASTLE_BLOCK
		)


func _build_crown_ramp() -> void:
	if layout.crown_stair == null:
		return
	_build_flight(layout.crown_stair)


## Columns a slab must leave open for the flight climbing into it.
func _well_columns(storey: int) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for st: CastleStair in layout.keep_stairs:
		if st.to_storey != storey:
			continue
		for t in range(1, st.rise + 1):
			for k in range(st.lane_w):
				out[st.column(t, k)] = true
	return out


## Index of the room a column belongs to, or -1 for partition and outer-wall columns.
func _room_at_column(f: CastleFloor, col: Vector2i) -> int:
	for i in range(f.rooms.size()):
		if (f.rooms[i] as Rect2i).has_point(col):
			return i
	return -1


## Stepped arch, same as the gate: the threshold keeps the full width and the courses
## above it draw in, so the opening reads as built rather than punched.
func _carve_doorway(d: CastleDoorway) -> void:
	var half := d.width / 2
	var side := d.side()
	for row in range(1, d.height + 1):
		var w := half - maxi(row - (d.height - 2), 0)
		if w < 0:
			continue
		var y := d.floor_y + row
		for s in range(d.depth):
			for t in range(-w, w + 1):
				var p := d.center + d.axis * s + side * t
				if not _in_region(p.x, p.y):
					continue
				var vox := Vector3i(p.x, y, p.y)
				if brush.get_vox(vox) == VoxelMaterial.AIR:
					continue
				brush.set_vox(vox, VoxelMaterial.AIR)


## Loops through the outer wall at head height, one per KEEP_WINDOW_PITCH of face.
func _carve_keep_windows() -> void:
	var kr := layout.keep_rect
	var faces: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for n in range(layout.keep_storeys()):
		var owner := layout.keep_floor(n if layout.keep_floor(n).has_slab else n - 1)
		var floor_y := layout.keep_floor_y(n)
		for fn: Vector2i in faces:
			var side := Vector2i(-fn.y, fn.x)
			var start := _corner_column(kr, fn, -side)
			var face_len := kr.size.y if fn.x != 0 else kr.size.x
			for off in range(KEEP_WINDOW_PITCH / 2, face_len, KEEP_WINDOW_PITCH):
				var outer := start + side * off
				var inner := outer - fn * KEEP_WALL_T
				if _room_at_column(owner, inner) < 0:
					continue
				for s in range(KEEP_WALL_T):
					var p := outer - fn * s
					if not _in_region(p.x, p.y):
						continue
					for y in range(floor_y + 2, floor_y + 4):
						var vox := Vector3i(p.x, y, p.y)
						if brush.get_vox(vox) == VoxelMaterial.AIR:
							continue
						brush.set_vox(vox, VoxelMaterial.AIR)


## Damp mossy courses along the foot of a wall — the strongest read that the masonry is
## old, and cheap because it only touches the bottom few voxels of each column.
func _weather_base(x: int, z: int, y0: int) -> void:
	var n := _fbm2(float(x) * 0.07 + 3.0, float(z) * 0.07 - 5.0)
	if n < 0.5:
		return
	var courses := 1 + int((n - 0.5) * 6.0)
	brush.fill_box(
		Vector3i(x, y0, z), Vector3i(x + 1, y0 + courses, z + 1),
		VoxelMaterial.CASTLE_BLOCK_MOSSY
	)


func _moss_here(x: int, z: int, bias: float) -> bool:
	return _fbm2(float(x) * 0.055, float(z) * 0.055) + bias > MOSS_T


func _report() -> void:
	print(
		"CastleComposer: %s plinth=%d vox"
		% [layout.describe(), _plinth_voxels]
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Smallest rect covering both columns, inclusive.
func _span_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Corner column of a rect, extreme along both cardinal directions.
func _corner_column(rect: Rect2i, a: Vector2i, b: Vector2i) -> Vector2i:
	var d := a + b
	assert(d.x != 0 and d.y != 0, "corner needs one perpendicular direction pair")
	return Vector2i(
		rect.end.x - 1 if d.x > 0 else rect.position.x,
		rect.end.y - 1 if d.y > 0 else rect.position.y
	)


func _axis_lo(rect: Rect2i, axis: int) -> int:
	return rect.position.x if axis == 0 else rect.position.y


func _axis_hi(rect: Rect2i, axis: int) -> int:
	return rect.end.x if axis == 0 else rect.end.y


## Chebyshev distance from a column to the rect, 0 when the column is inside it.
func _outside_dist(rect: Rect2i, x: int, z: int) -> int:
	var dx := maxi(rect.position.x - x, x - (rect.end.x - 1))
	var dz := maxi(rect.position.y - z, z - (rect.end.y - 1))
	return maxi(maxi(dx, 0), maxi(dz, 0))


## How many columns a point sits in from the nearest edge of a rect it is inside.
func _inside_dist(rect: Rect2i, x: int, z: int) -> int:
	return mini(
		mini(x - rect.position.x, rect.end.x - 1 - x),
		mini(z - rect.position.y, rect.end.y - 1 - z)
	)


func _in_region(x: int, z: int) -> bool:
	return x >= _x0 and z >= _z0 and x < _x1 and z < _z1


func _room_at(x: int, z: int) -> float:
	if not _in_region(x, z):
		push_error("CastleComposer._room_at: column (%d,%d) is outside the reserve" % [x, z])
		return 0.0
	return _clearance[(z - _z0) * _w + (x - _x0)]


func _is_road_cell(x: int, z: int) -> bool:
	return LandUse.is_road(planner.tag_at(x / cell_size, z / cell_size))


func _fbm2(x: float, z: float) -> float:
	return _value_noise2(x, z) * 0.65 + _value_noise2(x * 2.7 + 5.1, z * 2.7 - 3.3) * 0.35


func _value_noise2(x: float, z: float) -> float:
	var xi := floori(x)
	var zi := floori(z)
	var fx := x - float(xi)
	var fz := z - float(zi)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var n00 := _hash2(xi, zi)
	var n10 := _hash2(xi + 1, zi)
	var n01 := _hash2(xi, zi + 1)
	var n11 := _hash2(xi + 1, zi + 1)
	return lerpf(lerpf(n00, n10, fx), lerpf(n01, n11, fx), fz)


func _hash2(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0
