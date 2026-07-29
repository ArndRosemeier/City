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

## ── Dungeon ───────────────────────────────────────────────────────────────
## A dungeon level is this much floor and the rest of `LEVEL_H` in air. Both numbers are read
## back out of the pitch rather than set beside it: the band above is derived from `LEVEL_H`,
## so a second opinion here would move the courtyard and the whole fortress with it.
const DUNGEON_SLAB_T := 2
const DUNGEON_HEAD := LEVEL_H - DUNGEON_SLAB_T
## Masonry between the dungeon's outer face and its chambers. The plate is the curtain's own
## footprint, which puts the dungeon's outer wall under the curtain and a corner tower exactly
## on a plate corner — the one place a flight can drop out of a tower base straight into the
## substructure instead of tunnelling diagonally to reach it.
const DUNGEON_WALL_T := 4
## Bay cross walls carry down through every level, the way a real substructure's do. That is
## what lets a chamber reach up through the level above it, because the footprint it claims is
## the same rectangle on every level. Partitions inside a bay are cut per level and thinner.
const DUNGEON_BAY_T := 3
const DUNGEON_PART_T := 2
const DUNGEON_BAY_DEPTH := 4
## Bay grain, re-rolled per castle. The coarsest lever on how a dungeon reads: a few long bays
## give a substructure of halls, many give a warren.
const DUNGEON_BAY_MIN_LO := 24
const DUNGEON_BAY_MIN_HI := 36
const DUNGEON_BAY_SPLIT_LO := 40
const DUNGEON_BAY_SPLIT_HI := 64
## Narrowest cell any cut may leave. Three clear columns is what nav needs down the middle of
## a room, plus the one either side whose clearance the wall zeroes.
const DUNGEON_CELL_MIN := 7
## Room grain inside a bay, also re-rolled per castle. Capped at `CastleVault.SMALL_MAX` so a
## fine-grained castle reaches the small band on its own: above it, no ordinary cut can leave a
## cramped room and the only ones in the dungeon are the ones forced below.
const DUNGEON_ROOM_MIN_LO := 8
const DUNGEON_ROOM_MIN_HI := CastleVault.SMALL_MAX
const DUNGEON_ROOM_SPLIT_LO := 18
const DUNGEON_ROOM_SPLIT_HI := 34
## Times a bay may be halved on one level, rolled per bay per level: one level of a dungeon is
## a different plan from the next even though the cross walls are shared.
const DUNGEON_SPLIT_DEPTH_MAX := 2
## A bay left whole, and a bay cut deliberately small. Both wide chambers and cramped rooms
## are wanted, and leaving that to the dice means some seeds have only one of the two.
const GRAIN_WHOLE := 0
const GRAIN_CLOSET := -1
const DUNGEON_DOOR_W := 5
const DUNGEON_STAIR_W := 5
## Air carved above each tread of a descent. One more than the chamber height: carving only
## `DUNGEON_HEAD` leaves the well through the slab above one station short (the earliest tread
## that still needs both slab courses cleared keeps a one-voxel lid), and a body climbing out
## jams against that lip.
const DUNGEON_SHAFT_HEAD := DUNGEON_HEAD + 1
## Openings past the spanning tree, so a level loops instead of being a tree of dead ends.
const DUNGEON_LOOP_CHANCE := 0.35
## Chambers that reach up through the level above. Never guaranteed: a dungeon of one storey
## height throughout is a legitimate roll, and that two seeds differ here is the point.
const DUNGEON_TALL_MAX := 3
## Flights between one pair of levels. At least one, so the deepest level is always walkable
## to, and up to this many so two dungeons do not circulate the same way.
const DUNGEON_FLIGHTS_MAX := 3
## Masonry left inside a hollowed tower base's shaft.
const DUNGEON_TOWER_BASE_WALL := 2
## Courses of the curtain the tower recess starts in from, so the wall keeps its outer face
## even where its corner has been opened into the bailey. Inside the tower's own footprint the
## tower shell is the outer face, which is what lets the guardroom reach this far out at all.
const DUNGEON_TOWER_RECESS := 3
## Lane offset along the curtain from a corner tower's centre, so the flight is not jammed
## into the corner where the two outer walls meet behind it.
const DUNGEON_TOWER_LANE_OFF := LANE_MARGIN + 2
## Courses in from the tower's corner the flight's top tread stands on. Far enough that the
## shaft over it cuts the curtain's inner courses rather than its face, and near enough that
## the tread is still under the tower.
const DUNGEON_TOWER_HEAD_IN := 4
## Width of the passage joining a hollowed tower base to the bailey. It meets the flight at the
## only place a flank can be stepped onto — the two flat treads at the head and the one below
## them. Five matches the flight: four leaves a one-column pinch that zeroes nav clearance.
const DUNGEON_TOWER_PASS_W := 5
## Clear bailey kept between a courtyard trench and the curtain, so the crown ramp still has a
## wall to climb and the trench does not undercut the terrace.
const DUNGEON_COURT_MARGIN := 8
## Stride candidate lanes are enumerated on.
const DUNGEON_SITE_STRIDE := 4

## ── Curtain crown access ──────────────────────────────────────────────────
## Walkable voxels of the courtyard ramp, its parapet excluded.
const CROWN_RAMP_W := 5

## District-local coordinates are never negative, so -1 reads as "no slot".
const NO_SLOT := -1

## Where the mossy course takes over from dressed ashlar.
const MOSS_T := 0.62

## Scratch plan for one dungeon level while it is being laid out. GDScript has no nested typed
## arrays, so the per-level lists live in an object rather than in an `Array[Array]`.
class DungeonLevel extends RefCounted:
	var level: int = 0
	var floor_y: int = 0
	## Lane footprints with their margin. No partition may be cut through one of these, and no
	## doorway may be sited where it would strand a flight's landing.
	var claims: Array[Rect2i] = []
	## Bays a chamber below reaches up through, so this level carries no floor over them.
	var holes: Array[int] = []
	var vaults: Array[CastleVault] = []


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
var _dungeon_voxels: int = 0
## Footprints the room subdivision must not cut through: the keep entrance approach and
## every stair lane with its parapet.
var _keep_reserved: Array[Rect2i] = []
## Storeys the keep was rolled at, held between the two halves of its interior planning.
var _keep_storeys: int = 0
## Courtyard-level footprints the crown ramp has to miss — a dungeon trench in the bailey and
## the recess that opens a tower base into it.
var _courtyard_claims: Array[Rect2i] = []
## One entry per dungeon level, deepest first.
var _levels: Array[DungeonLevel] = []
## Per bay: the level a tall chamber stands on and how many levels it occupies, or -1/0.
var _tall_base: PackedInt32Array = PackedInt32Array()
var _tall_span: PackedInt32Array = PackedInt32Array()


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
	_build_dungeon()
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
	_build_dungeon()


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
	_dungeon_voxels = 0
	_keep_reserved.clear()
	_keep_storeys = 0
	_courtyard_claims.clear()
	_levels.clear()
	_tall_base.clear()
	_tall_span.clear()
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
	## The ways down are sited between the keep's circulation and its subdivision. The keep's
	## own entrance and flights have first claim on the plate — a cellar well that took their
	## lane would leave a storey unreachable — the well then takes a lane out of what is left
	## and claims it through `_keep_reserved`, and only then may a partition be cut anywhere.
	## The crown ramp comes after all of it, so it knows where a courtyard trench already is.
	_plan_dungeon_shell(out)
	_plan_keep_circulation(out)
	_plan_dungeon_entrances(out)
	_plan_keep_floors(out, _keep_storeys)
	_plan_crown_ramp(out)
	_plan_dungeon_interior(out)
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
	## The passage as a doorway record, so Phase 4 hangs the gate the same way it hangs every
	## other door. Its depth is the curtain alone rather than the whole bore: that is the
	## reveal the leaves are set into, and the gatehouse block either side of it is the room
	## the open leaves stand in. Nothing here rolls a die — the door plan is derived from the
	## masonry, so adding it moved no seed's fortress by a voxel.
	var g := CastleDoorway.new()
	g.center = out.gate_center
	g.axis = -out.gate_dir
	g.width = out.gate_width
	g.depth = out.wall_thick
	g.storey = 0
	g.floor_y = COURTYARD_Y
	g.height = out.gate_height
	g.leaf = CastleDoorway.LEAF_GATE
	g.link = CastleDoorway.LINK_TREE
	out.gate_doorway = g


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
	## Set here rather than with the rest of the interior: the dungeon's cellar flight is
	## planned before `_plan_keep_interior` and needs the plate to lay a lane inside.
	out.keep_plate_rect = out.keep_rect.grow(-KEEP_WALL_T)
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


## Storeys and stair lanes for the keep. Every lane the keep needs is claimed here, before
## `_plan_keep_floors` is allowed to cut a partition anywhere — and before the dungeon's cellar
## well looks for a lane of its own, which is why the two halves are separate calls.
func _plan_keep_circulation(out: CastleLayout) -> void:
	out.keep_wall_thick = KEEP_WALL_T
	out.keep_level_h = KEEP_LEVEL_H
	out.keep_slab_thick = KEEP_SLAB_T
	_keep_storeys = rng.randi_range(KEEP_STOREYS_MIN, KEEP_STOREYS_MAX)
	## The hall swallows the storey above it, so it can be neither the top storey nor the
	## one below it.
	out.keep_hall_storey = rng.randi_range(0, _keep_storeys - 3)
	out.keep_roof_y = out.keep_floor_y(_keep_storeys - 1) + KEEP_LEVEL_H
	_plan_keep_entrance(out)
	_plan_keep_flights(out, _keep_storeys)


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
	## The keep's front door reads as a gate, not as an interior door: it is the second thing
	## on the fortress a player walks up to and the only way in.
	d.leaf = CastleDoorway.LEAF_GATE
	d.link = CastleDoorway.LINK_TREE
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
	_shuffle_ints(slots)
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
##
## A slot whose corner is taken is slid along its own face before the slot is given up. Eight
## corners sound like plenty for four flights, but a long flight grown by its margin eats most
## of a face and both corners of the faces beside it, so on a small plate the corners alone
## genuinely run out — and a keep one flight short has a storey nothing can reach.
func _pick_stair_slot(
	out: CastleLayout, slots: Array[int], rise: int, y_from: int, a: int, b: int
) -> CastleStair:
	for i in range(slots.size()):
		var off := 0
		var st := _stair_for_slot(out, slots[i], off, rise, y_from, a, b)
		## The head needs the margin off the far wall that the foot has off its corner. Run a
		## flight up to the opposite face and its top landing sits in a pocket the storey can
		## only be entered from along the wall, where geodesic clearance is zero — a flight
		## that measures perfectly and that nav will not walk off.
		while out.keep_plate_rect.encloses(_grow_along(st.footprint(), st.dir, LANE_MARGIN)):
			if not _keep_blocked(st.footprint().grow(LANE_MARGIN)):
				slots.remove_at(i)
				return st
			off += LANE_MARGIN + 1
			st = _stair_for_slot(out, slots[i], off, rise, y_from, a, b)
	push_error(
		"CastleComposer: no free lane in the %s keep plate for a %d voxel flight %d→%d"
		% [out.keep_plate_rect.size, rise, a, b]
	)
	return null


func _stair_for_slot(
	out: CastleLayout, slot: int, off: int, rise: int, y_from: int, a: int, b: int
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
		_corner_column(out.keep_plate_rect, fn, -along) + along * (LANE_MARGIN + 1 + off)
	)
	assert(
		off > 0 or out.keep_plate_rect.encloses(_grow_along(st.footprint(), along, LANE_MARGIN)),
		"keep plate is too small for a %d voxel flight" % rise
	)
	return st


## `r` grown at both ends of the axis `dir` runs along, the other axis left alone.
func _grow_along(r: Rect2i, dir: Vector2i, m: int) -> Rect2i:
	var d := Vector2i(absi(dir.x), absi(dir.y))
	return Rect2i(r.position - d * m, r.size + d * (2 * m))


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


## Local offsets a partition may start at: both halves keep KEEP_ROOM_MIN, and the band with a
## course either side of it misses every reserved lane. The course either side is what the
## doorway through the partition needs — a lane pressed against the partition leaves a cut with
## nowhere to put its one opening, and a cut that cannot be doored seals a room.
func _split_coords(cell: Rect2i, axis: int) -> Array[int]:
	var out: Array[int] = []
	var size := cell.size.x if axis == 0 else cell.size.y
	var normal := Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
	for c in range(KEEP_ROOM_MIN, size - KEEP_PART_T - KEEP_ROOM_MIN + 1):
		if _keep_blocked(_grow_along(_band_rect(cell, axis, c), normal, 1)):
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
	d.leaf = CastleDoorway.LEAF_DOOR
	## One opening per cut and the subdivision is a tree, so every keep doorway is
	## load-bearing: there is no second way between the two halves of a split.
	d.link = CastleDoorway.LINK_TREE
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
	var sides := _shuffled_dirs()
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
	if _rects_block(_courtyard_claims, claim):
		return true
	for t: CastleTower in out.towers:
		if claim.intersects(_tower_rect(t)):
			return true
	return false


func _keep_blocked(r: Rect2i) -> bool:
	return _rects_block(_keep_reserved, r)


func _rects_block(taken: Array[Rect2i], r: Rect2i) -> bool:
	for t: Rect2i in taken:
		if r.intersects(t):
			return true
	return false


func _tower_rect(tower: CastleTower) -> Rect2i:
	return Rect2i(
		tower.center - Vector2i(tower.radius, tower.radius),
		Vector2i.ONE * (2 * tower.radius + 1)
	)


# ---------------------------------------------------------------------------
# Dungeon planning
# ---------------------------------------------------------------------------

## Extent of the substructure and the cross-wall bays every level shares.
##
## The plate is the curtain's own footprint, so the dungeon's outer wall stands under the
## curtain and each corner tower sits on a plate corner. The whole band is virgin plinth at
## this point, and it is inside `plateau_rect` where the plinth is full height, so every
## chamber is cut out of solid mass rather than propped up over the batter.
func _plan_dungeon_shell(out: CastleLayout) -> void:
	out.dungeon_levels = DUNGEON_LEVELS
	out.dungeon_level_h = LEVEL_H
	out.dungeon_slab_thick = DUNGEON_SLAB_T
	out.dungeon_plate_rect = out.wall_rect
	out.dungeon_rect = out.wall_rect.grow(DUNGEON_WALL_T)
	assert(
		out.plateau_rect.encloses(out.dungeon_rect),
		"the dungeon's outer face has to stay inside the plateau, where the plinth is full height"
	)
	for l in range(DUNGEON_LEVELS):
		var plan := DungeonLevel.new()
		plan.level = l
		plan.floor_y = out.dungeon_floor_y(l)
		_levels.append(plan)
	out.dungeon_bay_min = rng.randi_range(DUNGEON_BAY_MIN_LO, DUNGEON_BAY_MIN_HI)
	out.dungeon_room_min = rng.randi_range(DUNGEON_ROOM_MIN_LO, DUNGEON_ROOM_MIN_HI)
	var bay_split := rng.randi_range(DUNGEON_BAY_SPLIT_LO, DUNGEON_BAY_SPLIT_HI)
	var free: Array[Rect2i] = []
	out.dungeon_bays = _dungeon_split(
		out.dungeon_plate_rect,
		out.dungeon_bay_min,
		bay_split,
		DUNGEON_BAY_T,
		DUNGEON_BAY_DEPTH,
		free
	)
	_tall_base.resize(out.dungeon_bays.size())
	_tall_base.fill(-1)
	_tall_span.resize(out.dungeon_bays.size())
	_tall_span.fill(0)
	if out.dungeon_bays.size() < 4:
		push_error(
			"CastleComposer: the %s dungeon plate only divides into %d bays"
			% [out.dungeon_plate_rect.size, out.dungeon_bays.size()]
		)


## The ways down, as a random non-empty subset of the routes this fortress can actually carry.
## Three are possible — a well through the keep's ground floor, a stepped trench in the open
## bailey, and a flight out of a hollowed corner tower base — and which of them a castle has is
## what makes two dungeons different before the player is underground.
func _plan_dungeon_entrances(out: CastleLayout) -> void:
	var top := out.dungeon_top_level()
	var y_from := out.dungeon_floor_y(top)
	var rise := out.courtyard_y - y_from
	var wanted := 1 + rng.randi() % ((1 << CastleDungeonEntry.KIND_COUNT) - 1)
	var order := _shuffled_ints(CastleDungeonEntry.KIND_COUNT)
	for kind: int in order:
		if (wanted & (1 << kind)) == 0:
			continue
		_add_dungeon_entry(out, kind, y_from, rise)
	## One way down is a hard requirement, so a roll whose whole subset turned out unplaceable
	## falls through to whichever route this fortress does have room for.
	if out.dungeon_entries.is_empty():
		for kind: int in order:
			_add_dungeon_entry(out, kind, y_from, rise)
			if not out.dungeon_entries.is_empty():
				break
	if out.dungeon_entries.is_empty():
		push_error("CastleComposer: no route down into the dungeon fits this fortress")


func _add_dungeon_entry(out: CastleLayout, kind: int, y_from: int, rise: int) -> void:
	var e: CastleDungeonEntry = null
	match kind:
		CastleDungeonEntry.KIND_KEEP_CELLAR:
			e = _plan_cellar_entry(out, y_from, rise)
		CastleDungeonEntry.KIND_COURTYARD:
			e = _plan_courtyard_entry(out, y_from, rise)
		CastleDungeonEntry.KIND_TOWER_BASE:
			e = _plan_tower_entry(out, y_from, rise)
		_:
			push_error("CastleComposer: unknown dungeon entry kind %d" % kind)
			return
	if e == null:
		return
	out.dungeon_entries.append(e)
	var claim := e.stair.footprint().grow(LANE_MARGIN)
	_levels[out.dungeon_top_level()].claims.append(claim)
	match kind:
		CastleDungeonEntry.KIND_KEEP_CELLAR:
			_keep_reserved.append(claim)
		CastleDungeonEntry.KIND_COURTYARD:
			_courtyard_claims.append(claim)
		CastleDungeonEntry.KIND_TOWER_BASE:
			_courtyard_claims.append(e.chamber_rect.grow(1))


## A well through the keep's ground floor. Storey 0 stands on the courtyard slab, which the
## plinth cast solid and which nothing else reserves a lane through, so this flight cuts the
## only one there is — and claims it before the keep's partitions are laid out.
func _plan_cellar_entry(out: CastleLayout, y_from: int, rise: int) -> CastleDungeonEntry:
	var st := _pick_descent(out, out.keep_plate_rect, y_from, rise, _keep_reserved)
	if st == null:
		return null
	var e := CastleDungeonEntry.new()
	e.kind = CastleDungeonEntry.KIND_KEEP_CELLAR
	e.stair = st
	return e


## A stepped trench in the open bailey, independent of the keep. Held clear of the curtain so
## the crown ramp still has an unbroken wall to climb, and clear of the courtyard datum point
## the rest of the castle paths through.
func _plan_courtyard_entry(out: CastleLayout, y_from: int, rise: int) -> CastleDungeonEntry:
	var avoid: Array[Rect2i] = [
		out.keep_rect.grow(LANE_MARGIN),
		out.gatehouse_rect.grow(LANE_MARGIN),
		Rect2i(out.courtyard_center - Vector2i.ONE * LANE_MARGIN, Vector2i.ONE * (2 * LANE_MARGIN + 1)),
	]
	for t: CastleTower in out.towers:
		avoid.append(_tower_rect(t).grow(LANE_MARGIN))
	avoid.append_array(_courtyard_claims)
	var host := out.courtyard_rect.grow(-DUNGEON_COURT_MARGIN)
	var st := _pick_descent(out, host, y_from, rise, avoid)
	if st == null:
		return null
	var e := CastleDungeonEntry.new()
	e.kind = CastleDungeonEntry.KIND_COURTYARD
	e.stair = st
	return e


## Down through a hollowed corner tower base.
##
## The corner is the tightest site on the fortress: the bailey starts a full `wall_thick` in on
## both axes, so the base is cut off from it diagonally, and a five-wide flight plus a five-wide
## passage do not both fit in a tower of these radii. So the two are laid out perpendicular. The
## flight climbs out of the plate along one wall and its top treads stand under the tower; the
## passage runs beside it in the other wall's inner courses and meets it at its head, which is
## the only part of a flight's flank a body standing on a floor can step onto.
func _plan_tower_entry(out: CastleLayout, y_from: int, rise: int) -> CastleDungeonEntry:
	var top := out.dungeon_top_level()
	assert(
		DUNGEON_TOWER_LANE_OFF + LANE_MARGIN >= WALL_THICK_MAX,
		"the tower passage has to clear the curtain to reach the bailey"
	)
	for ti: int in _shuffled_ints(out.towers.size()):
		var t: CastleTower = out.towers[ti]
		if t.kind != CastleTower.KIND_CORNER:
			continue
		var inward := _plate_inward(out.dungeon_plate_rect, t.center)
		if inward == Vector2i.ZERO:
			continue
		## The base has to be a room rather than a shaft, or there is nothing at the head of
		## the flight for the passage to arrive in.
		if t.radius - DUNGEON_TOWER_BASE_WALL < DUNGEON_TOWER_HEAD_IN + 1:
			continue
		for axis: int in _shuffled_ints(2):
			## `along` runs into the plate on the flight's axis, `side` along the other wall.
			var along := Vector2i(inward.x, 0) if axis == 0 else Vector2i(0, inward.y)
			var side := inward - along
			var st := _dungeon_flight(
				y_from,
				rise,
				t.center + along * DUNGEON_TOWER_HEAD_IN + side * DUNGEON_TOWER_LANE_OFF,
				-along,
				side,
				top,
				-1
			)
			var claim := st.footprint().grow(LANE_MARGIN)
			if _dungeon_bay_of(out, claim) < 0:
				continue
			if _rects_block(_levels[top].claims, claim):
				continue
			var e := CastleDungeonEntry.new()
			e.kind = CastleDungeonEntry.KIND_TOWER_BASE
			e.stair = st
			e.tower_index = ti
			var pass_off := DUNGEON_TOWER_LANE_OFF + LANE_MARGIN
			e.chamber_rect = _span_rect(
				t.center + along * DUNGEON_TOWER_RECESS + side * pass_off,
				(
					t.center
					+ along * (out.wall_thick + DUNGEON_TOWER_PASS_W + 1)
					+ side * (pass_off + DUNGEON_TOWER_PASS_W - 1)
				)
			)
			e.chamber_air_h = DUNGEON_HEAD
			return e
	return null


## First free lane for a flight down out of `host`, taken at random from every candidate that
## fits. The lane plus its margin has to sit inside the host, land inside one dungeon bay so it
## cannot notch a cross wall on the way, and miss everything already claimed.
func _pick_descent(
	out: CastleLayout, host: Rect2i, y_from: int, rise: int, avoid: Array[Rect2i]
) -> CastleStair:
	var top := out.dungeon_top_level()
	for fn: Vector2i in _shuffled_dirs():
		var across := Vector2i(-fn.y, fn.x)
		var picks: Array[CastleStair] = []
		for z in range(host.position.y, host.end.y, DUNGEON_SITE_STRIDE):
			for x in range(host.position.x, host.end.x, DUNGEON_SITE_STRIDE):
				var st := _dungeon_flight(
					y_from, rise, Vector2i(x, z), fn, across, top, -1
				)
				var claim := st.footprint().grow(LANE_MARGIN)
				if not host.encloses(claim):
					continue
				if _dungeon_bay_of(out, claim) < 0:
					continue
				if _rects_block(avoid, claim):
					continue
				if _rects_block(_levels[top].claims, claim):
					continue
				picks.append(st)
		if not picks.is_empty():
			return picks[rng.randi() % picks.size()]
	return null


## A carved flight whose top tread centre lands on `head`, climbing along `dir`. The treads are
## `CastleStair.surface_at()` exactly as the keep's are — one voxel per riser, because two
## leaves the walk graph and bakes as a one-way drop a pedestrian can never climb back up.
func _dungeon_flight(
	y_from: int,
	rise: int,
	head: Vector2i,
	dir: Vector2i,
	across: Vector2i,
	from_level: int,
	to_level: int
) -> CastleStair:
	var st := CastleStair.new()
	st.dir = dir
	st.across = across
	st.lane_w = DUNGEON_STAIR_W
	st.rise = rise
	st.y_from = y_from
	st.from_storey = from_level
	st.to_storey = to_level
	st.origin = head - dir * (rise + 1) - across * (DUNGEON_STAIR_W / 2)
	return st


## Tall chambers, then the flights between levels, then the rooms and the openings that join
## them. In that order because a chamber reaching up through a level takes that level's floor
## away, and a flight needs both its levels floored before it can claim a lane between them.
func _plan_dungeon_interior(out: CastleLayout) -> void:
	_plan_dungeon_tall(out)
	_plan_dungeon_flights(out)
	_plan_dungeon_rooms(out)
	_plan_dungeon_doors(out)


## Bays promoted to chambers that reach up through the level above them, which is the single
## biggest lever on how a dungeon reads: it changes the section, not just the floor plan. A
## bay is taken whole, so the hall is bounded by cross walls that already carry down.
func _plan_dungeon_tall(out: CastleLayout) -> void:
	## Halls are the exception that makes the rest read as a dungeon. Past a third of the bays
	## the substructure stops being a warren with halls in it and becomes one open cathedral.
	var want := mini(
		rng.randi_range(0, DUNGEON_TALL_MAX), maxi(1, out.dungeon_bays.size() / 3)
	)
	if want == 0:
		return
	var tries: Array[Vector3i] = []
	for bi in range(out.dungeon_bays.size()):
		for span in range(2, DUNGEON_LEVELS + 1):
			for base in range(0, DUNGEON_LEVELS - span + 1):
				tries.append(Vector3i(bi, base, span))
	for i in range(tries.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: Vector3i = tries[i]
		tries[i] = tries[j]
		tries[j] = swap
	var made := 0
	for t: Vector3i in tries:
		if made >= want:
			return
		if not _tall_fits(out, t.x, t.y, t.z):
			continue
		_tall_base[t.x] = t.y
		_tall_span[t.x] = t.z
		for l in range(t.y + 1, t.y + t.z):
			_levels[l].holes.append(t.x)
		made += 1


## A bay may only go tall when it is free on every level it would occupy, carries no lane, and
## taking its floor away leaves the levels above it still walkable end to end.
func _tall_fits(out: CastleLayout, bay: int, base: int, span: int) -> bool:
	if _tall_base[bay] >= 0:
		return false
	var rect: Rect2i = out.dungeon_bays[bay]
	for l in range(base, base + span):
		if _levels[l].holes.has(bay):
			return false
		if _rects_block(_levels[l].claims, rect):
			return false
	for l2 in range(base + 1, base + span):
		var holes := _levels[l2].holes.duplicate()
		holes.append(bay)
		if not _bays_connected(out, holes):
			return false
	return true


## Breadth-first over the bays a level still has a floor on. A hole that cuts one off from the
## rest would leave chambers nothing can reach, and the tall chamber that caused it is a plan
## decision, so it is refused here rather than discovered by a failing path later.
func _bays_connected(out: CastleLayout, holes: Array[int]) -> bool:
	var live: Array[int] = []
	for bi in range(out.dungeon_bays.size()):
		if not holes.has(bi):
			live.append(bi)
	if live.size() < 2:
		return not live.is_empty()
	var seen: Array[int] = [live[0]]
	var added := true
	while added:
		added = false
		for a: int in live:
			if not seen.has(a):
				continue
			for b: int in live:
				if seen.has(b):
					continue
				if _facing_axis(out.dungeon_bays[a], out.dungeon_bays[b], DUNGEON_DOOR_W + 2) < 0:
					continue
				seen.append(b)
				added = true
	return seen.size() == live.size()


## At least one flight per pair of levels and up to `DUNGEON_FLIGHTS_MAX`, each laid inside one
## bay so its lane never crosses a cross wall. A bay carrying a tall chamber is skipped: it has
## no floor on one of the two levels the flight would join.
func _plan_dungeon_flights(out: CastleLayout) -> void:
	for lower in range(out.dungeon_levels - 1):
		var upper := lower + 1
		var want := rng.randi_range(1, DUNGEON_FLIGHTS_MAX)
		var made := 0
		for bi: int in _shuffled_ints(out.dungeon_bays.size()):
			if made >= want:
				break
			if _tall_base[bi] >= 0:
				continue
			if _levels[lower].holes.has(bi) or _levels[upper].holes.has(bi):
				continue
			var st := _dungeon_flight_in_bay(out, out.dungeon_bays[bi], lower, upper)
			if st == null:
				continue
			out.dungeon_stairs.append(st)
			var claim := st.footprint().grow(LANE_MARGIN)
			_levels[lower].claims.append(claim)
			_levels[upper].claims.append(claim)
			made += 1
		if made == 0:
			push_error(
				"CastleComposer: no dungeon bay can carry a flight from level %d to %d"
				% [lower, upper]
			)


func _dungeon_flight_in_bay(
	out: CastleLayout, bay: Rect2i, lower: int, upper: int
) -> CastleStair:
	var y_from := out.dungeon_floor_y(lower)
	var rise := out.dungeon_floor_y(upper) - y_from
	for fn: Vector2i in _shuffled_dirs():
		var across := Vector2i(-fn.y, fn.x)
		var picks: Array[CastleStair] = []
		for z in range(bay.position.y, bay.end.y, DUNGEON_SITE_STRIDE):
			for x in range(bay.position.x, bay.end.x, DUNGEON_SITE_STRIDE):
				var st := _dungeon_flight(
					y_from, rise, Vector2i(x, z), fn, across, lower, upper
				)
				var claim := st.footprint().grow(LANE_MARGIN)
				if not bay.encloses(claim):
					continue
				if _rects_block(_levels[lower].claims, claim):
					continue
				if _rects_block(_levels[upper].claims, claim):
					continue
				picks.append(st)
		if not picks.is_empty():
			return picks[rng.randi() % picks.size()]
	return null


## Every bay on every level cut into the chambers that level has. A tall bay is never cut: it
## is one hall the full height of its span, which is what stops a partition being left hanging
## in the air over the level it reaches through.
func _plan_dungeon_rooms(out: CastleLayout) -> void:
	var room_split := rng.randi_range(DUNGEON_ROOM_SPLIT_LO, DUNGEON_ROOM_SPLIT_HI)
	var grains := _dungeon_grains(out)
	for l in range(out.dungeon_levels):
		var plan: DungeonLevel = _levels[l]
		for bi in range(out.dungeon_bays.size()):
			if plan.holes.has(bi):
				continue
			var bay: Rect2i = out.dungeon_bays[bi]
			var span := _tall_span[bi] if _tall_base[bi] == l else 1
			var cells: Array[Rect2i] = [bay]
			if span == 1:
				cells = _dungeon_cells(
					bay, int(grains[l * out.dungeon_bays.size() + bi]),
					out.dungeon_room_min, room_split, plan.claims
				)
			for r: Rect2i in cells:
				var v := CastleVault.new()
				v.rect = r
				v.level = l
				v.floor_y = plan.floor_y
				v.air_h = span * out.dungeon_level_h - out.dungeon_slab_thick
				v.span_levels = span
				v.bay = bi
				plan.vaults.append(v)
				out.dungeon_vaults.append(v)


## How finely each bay is cut, per level. Every level is forced to carry one bay cut down to a
## closet and one left whole, so "wide chambers and cramped cells, on every level" is a property
## of the plan rather than of how the dice happened to land on this seed.
func _dungeon_grains(out: CastleLayout) -> Dictionary[int, int]:
	var bays := out.dungeon_bays.size()
	var grains: Dictionary[int, int] = {}
	for l in range(out.dungeon_levels):
		var free: Array[int] = []
		for bi in range(bays):
			grains[l * bays + bi] = rng.randi_range(0, DUNGEON_SPLIT_DEPTH_MAX)
			if _levels[l].holes.has(bi) or _tall_base[bi] >= 0:
				continue
			free.append(l * bays + bi)
		_shuffle_ints(free)
		if free.is_empty():
			continue
		## A tall chamber is a wide one by construction, so the closet is claimed first: it is
		## the harder of the two to come by.
		var closet := -1
		for key: int in free:
			var bay: Rect2i = out.dungeon_bays[key % bays]
			if _dungeon_closet_coords(bay, _long_axis(bay), _levels[l].claims).is_empty():
				continue
			closet = key
			grains[key] = GRAIN_CLOSET
			break
		if closet < 0:
			push_error(
				"CastleComposer: no bay on dungeon level %d can be cut down to a small room" % l
			)
		for key2: int in free:
			if key2 == closet:
				continue
			grains[key2] = GRAIN_WHOLE
			break
	return grains


func _dungeon_cells(
	bay: Rect2i, grain: int, room_min: int, room_split: int, claims: Array[Rect2i]
) -> Array[Rect2i]:
	if grain != GRAIN_CLOSET:
		return _dungeon_split(bay, room_min, room_split, DUNGEON_PART_T, grain, claims)
	var axis := _long_axis(bay)
	var coords := _dungeon_closet_coords(bay, axis, claims)
	assert(not coords.is_empty(), "the closet bay was chosen for having a legal cut")
	var halves := _dungeon_cut(bay, axis, coords[rng.randi() % coords.size()], DUNGEON_PART_T)
	var cells: Array[Rect2i] = [halves[0]]
	cells.append_array(
		_dungeon_split(halves[1], room_min, room_split, DUNGEON_PART_T, 1, claims)
	)
	return cells


## Cuts that leave a cell no wider than `CastleVault.SMALL_MAX` on one side, with a room worth
## having on the other.
func _dungeon_closet_coords(cell: Rect2i, axis: int, claims: Array[Rect2i]) -> Array[int]:
	var out: Array[int] = []
	var size := cell.size.x if axis == 0 else cell.size.y
	for c in range(DUNGEON_CELL_MIN, CastleVault.SMALL_MAX + 1):
		if c + DUNGEON_PART_T + DUNGEON_CELL_MIN > size:
			break
		if _rects_block(claims, _dungeon_band(cell, axis, c, DUNGEON_PART_T)):
			continue
		out.append(c)
	return out


## Recursive halving into leaves at least `room_min` across, separated by `part_t` of masonry.
## Depth-limited, so the grain of a bay is a number the plan chose rather than however many
## times the dice came up.
func _dungeon_split(
	cell: Rect2i,
	room_min: int,
	split_at: int,
	part_t: int,
	depth: int,
	claims: Array[Rect2i]
) -> Array[Rect2i]:
	var leaf: Array[Rect2i] = [cell]
	if depth <= 0:
		return leaf
	var want := cell.size.x > split_at or cell.size.y > split_at
	if not want and rng.randf() < 0.5:
		return leaf
	var order: Array[int] = [0, 1]
	if cell.size.y > cell.size.x:
		order = [1, 0]
	for axis: int in order:
		var coords := _dungeon_split_coords(cell, axis, room_min, part_t, claims)
		if coords.is_empty():
			continue
		var halves := _dungeon_cut(
			cell, axis, coords[rng.randi() % coords.size()], part_t
		)
		var cells: Array[Rect2i] = _dungeon_split(
			halves[0], room_min, split_at, part_t, depth - 1, claims
		)
		cells.append_array(
			_dungeon_split(halves[1], room_min, split_at, part_t, depth - 1, claims)
		)
		return cells
	return leaf


func _dungeon_split_coords(
	cell: Rect2i, axis: int, room_min: int, part_t: int, claims: Array[Rect2i]
) -> Array[int]:
	var out: Array[int] = []
	var size := cell.size.x if axis == 0 else cell.size.y
	for c in range(room_min, size - part_t - room_min + 1):
		if _rects_block(claims, _dungeon_band(cell, axis, c, part_t)):
			continue
		out.append(c)
	return out


func _dungeon_band(cell: Rect2i, axis: int, c: int, part_t: int) -> Rect2i:
	if axis == 0:
		return Rect2i(cell.position.x + c, cell.position.y, part_t, cell.size.y)
	return Rect2i(cell.position.x, cell.position.y + c, cell.size.x, part_t)


func _dungeon_cut(cell: Rect2i, axis: int, c: int, part_t: int) -> Array[Rect2i]:
	var lo := cell
	var hi := cell
	if axis == 0:
		lo.size.x = c
		hi.position.x = cell.position.x + c + part_t
		hi.size.x = cell.size.x - c - part_t
	else:
		lo.size.y = c
		hi.position.y = cell.position.y + c + part_t
		hi.size.y = cell.size.y - c - part_t
	return [lo, hi]


## One doorway per edge of a spanning tree over each level's chambers, then extra openings on
## the edges left over. The tree is what makes "every chamber reachable" a property of the plan
## instead of a hope; the extras are what makes a level loop rather than branch.
##
## Which of the two an opening is gets recorded on it. Nothing consumes that yet — every door
## in the prototype is passable — but a tree edge is the one opening a room has, so locking or
## barring one strands everything behind it, and that distinction is knowable here and
## expensive to recover from a finished plan.
func _plan_dungeon_doors(out: CastleLayout) -> void:
	for l in range(out.dungeon_levels):
		_plan_level_doors(out, _levels[l])


func _plan_level_doors(out: CastleLayout, plan: DungeonLevel) -> void:
	var rooms := plan.vaults
	if rooms.is_empty():
		push_error("CastleComposer: dungeon level %d has no chambers at all" % plan.level)
		return
	var edges: Array[Vector3i] = []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var axis := _facing_axis(rooms[i].rect, rooms[j].rect, DUNGEON_DOOR_W + 2)
			if axis >= 0:
				edges.append(Vector3i(i, j, axis))
	var seen: Array[bool] = []
	seen.resize(rooms.size())
	seen.fill(false)
	seen[0] = true
	var used: Array[bool] = []
	used.resize(edges.size())
	used.fill(false)
	var added := true
	while added:
		added = false
		for k in range(edges.size()):
			if used[k]:
				continue
			var e: Vector3i = edges[k]
			if seen[e.x] == seen[e.y]:
				continue
			var door := _dungeon_door_between(
				rooms[e.x], rooms[e.y], e.z, plan, CastleDoorway.LINK_TREE
			)
			if door == null:
				continue
			out.dungeon_doorways.append(door)
			used[k] = true
			seen[e.x] = true
			seen[e.y] = true
			added = true
	for k2 in range(edges.size()):
		if used[k2] or rng.randf() >= DUNGEON_LOOP_CHANCE:
			continue
		var e2: Vector3i = edges[k2]
		var door2 := _dungeon_door_between(
			rooms[e2.x], rooms[e2.y], e2.z, plan, CastleDoorway.LINK_LOOP
		)
		if door2 == null:
			continue
		used[k2] = true
		out.dungeon_doorways.append(door2)
	for i2 in range(rooms.size()):
		if not seen[i2]:
			push_error(
				"CastleComposer: dungeon level %d chamber %s has no way in"
				% [plan.level, (rooms[i2] as CastleVault).rect]
			)


## Axis two chambers face each other across, or -1 when the masonry between them is too thick
## or they share too little wall to cut a doorway with a column of margin either side.
func _facing_axis(a: Rect2i, b: Rect2i, min_overlap: int) -> int:
	for axis: int in [0, 1]:
		var other := 1 - axis
		var gap := _axis_lo(b, axis) - _axis_hi(a, axis)
		if gap < 0:
			gap = _axis_lo(a, axis) - _axis_hi(b, axis)
		if gap < 1 or gap > DUNGEON_BAY_T:
			continue
		var lo := maxi(_axis_lo(a, other), _axis_lo(b, other))
		var hi := mini(_axis_hi(a, other), _axis_hi(b, other))
		if hi - lo < min_overlap:
			continue
		return axis
	return -1


func _dungeon_door_between(
	a: CastleVault, b: CastleVault, axis: int, plan: DungeonLevel, link: int
) -> CastleDoorway:
	var near := a
	var far := b
	if _axis_lo(b.rect, axis) < _axis_lo(a.rect, axis):
		near = b
		far = a
	var band_lo := _axis_hi(near.rect, axis)
	var gap := _axis_lo(far.rect, axis) - band_lo
	var other := 1 - axis
	var lo := maxi(_axis_lo(a.rect, other), _axis_lo(b.rect, other))
	var hi := mini(_axis_hi(a.rect, other), _axis_hi(b.rect, other))
	var t := _dungeon_door_slot(lo, hi, axis, band_lo, gap, plan.claims)
	if t == NO_SLOT:
		return null
	var d := CastleDoorway.new()
	d.axis = Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
	d.center = Vector2i(band_lo, t) if axis == 0 else Vector2i(t, band_lo)
	d.width = DUNGEON_DOOR_W
	d.depth = gap
	d.storey = plan.level
	d.floor_y = a.floor_y
	d.height = mini(a.air_h, b.air_h)
	d.leaf = CastleDoorway.LEAF_GRATE
	d.link = link
	return d


## Centre offset along a partition for an opening inside [lo, hi), closest to the middle of the
## overlap that still clears every claimed lane. NO_SLOT when nothing fits.
func _dungeon_door_slot(
	lo: int, hi: int, axis: int, band_lo: int, gap: int, claims: Array[Rect2i]
) -> int:
	var half := DUNGEON_DOOR_W / 2
	var first := lo + half + 1
	var last := hi - half - 2
	if last < first:
		return NO_SLOT
	var mid := (lo + hi) / 2
	for step in range(0, hi - lo):
		for sign: int in [1, -1]:
			var t := mid + step * sign
			if t < first or t > last:
				continue
			var check := (
				Rect2i(band_lo - 1, t - half, gap + 2, DUNGEON_DOOR_W)
				if axis == 0
				else Rect2i(t - half, band_lo - 1, DUNGEON_DOOR_W, gap + 2)
			)
			if not _rects_block(claims, check):
				return t
			if step == 0:
				break
	return NO_SLOT


## Index of the bay a footprint belongs to, or -1 when it straddles a cross wall or leaves the
## plate. Everything a flight claims has to sit in one bay: a lane that crossed a cross wall
## would notch a wall every level of the dungeon depends on.
func _dungeon_bay_of(out: CastleLayout, claim: Rect2i) -> int:
	var inside := claim.intersection(out.dungeon_plate_rect)
	if inside.size.x <= 0 or inside.size.y <= 0:
		return -1
	for bi in range(out.dungeon_bays.size()):
		if (out.dungeon_bays[bi] as Rect2i).encloses(inside):
			return bi
	return -1


## Inward cardinal pair of a column that sits on a corner of `rect`, or ZERO when it does not.
func _plate_inward(rect: Rect2i, col: Vector2i) -> Vector2i:
	var ix := 0
	var iz := 0
	if col.x == rect.position.x:
		ix = 1
	elif col.x == rect.end.x - 1:
		ix = -1
	if col.y == rect.position.y:
		iz = 1
	elif col.y == rect.end.y - 1:
		iz = -1
	if ix == 0 or iz == 0:
		return Vector2i.ZERO
	return Vector2i(ix, iz)


func _long_axis(rect: Rect2i) -> int:
	return 0 if rect.size.x >= rect.size.y else 1


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
	_shuffle_dirs(sides)
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
	var side_axis := Vector2i(-layout.gate_dir.y, layout.gate_dir.x)
	## Deep enough to clear the gatehouse, the curtain behind it and the turrets beside it.
	var depth := (gh.size.x if layout.gate_dir.x != 0 else gh.size.y) + GATE_TOWER_R_MAX
	var mouth := _gatehouse_face_point(layout) + layout.gate_dir * GATE_TOWER_R_MAX
	for row in range(1, layout.gate_height + 1):
		## Stepped arch over the opening — the threshold row keeps the full width. Read off
		## the gate's own doorway record, which is also what the leaves are cut to.
		var w := layout.gate_doorway.row_half(row)
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
		## Arrival treads through a storey slab are a single surface course, not a full wedge:
		## a two-course lip at the well edge is coplanar with the last rising tread and jams a
		## capsule that still has one foot on the step below.
		var fill_lo := (
			s if st.to_storey >= 0 and t >= st.rise + 1 else st.y_from + 1
		)
		for k in range(st.lane_w):
			var p := st.column(t, k)
			if not _in_region(p.x, p.y):
				continue
			brush.fill_box(
				Vector3i(p.x, fill_lo, p.y),
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
##
## Includes the arrival tread (`t = rise + 1`): that column carries only the thin landing the
## flight writes, not the two-course storey slab. Leaving the slab there made the well one
## voxel short at the lip — coplanar with the last rising tread — and jammed the walker.
func _well_columns(storey: int) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for st: CastleStair in layout.keep_stairs:
		if st.to_storey != storey:
			continue
		for t in range(1, st.rise + 2):
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
## above it draw in, so the opening reads as built rather than punched. The profile comes from
## the doorway record, which is the same one the door leaves are cut to.
func _carve_doorway(d: CastleDoorway) -> void:
	var side := d.side()
	for row in range(1, d.height + 1):
		var w := d.row_half(row)
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


# ---------------------------------------------------------------------------
# Dungeon
# ---------------------------------------------------------------------------

## Everything under the courtyard slab. The band is virgin plinth and district substrate, so
## the dungeon is subtractive where the keep is additive: chambers are carved out of the mass,
## flights are solid wedges with their shaft carved over them, and the openings are the same
## stepped arch the keep's doorways use.
##
## Order matters. The chambers go first because a flight has to re-fill its treads where a
## chamber has already taken the mass away; the doorways go last because a partition is only
## masonry once the rooms either side of it exist.
func _build_dungeon() -> void:
	for v: CastleVault in layout.dungeon_vaults:
		_carve_vault(v)
	for e: CastleDungeonEntry in layout.dungeon_entries:
		if e.kind == CastleDungeonEntry.KIND_TOWER_BASE:
			_carve_tower_base(e)
		_carve_descent(e.stair)
	for st: CastleStair in layout.dungeon_stairs:
		_carve_descent(st)
	for d: CastleDoorway in layout.dungeon_doorways:
		_carve_doorway(d)
	if _detail:
		for v2: CastleVault in layout.dungeon_vaults:
			_dress_vault(v2)


func _carve_vault(v: CastleVault) -> void:
	var r := v.rect
	assert(
		_in_region(r.position.x, r.position.y) and _in_region(r.end.x - 1, r.end.y - 1),
		"a dungeon chamber was planned outside the reserve"
	)
	brush.fill_box(
		Vector3i(r.position.x, v.floor_y + 1, r.position.y),
		Vector3i(r.end.x, v.top_y() + 1, r.end.y),
		VoxelMaterial.AIR
	)
	_dungeon_voxels += r.size.x * r.size.y * v.air_h


## Both halves of one flight, per lane column: the tread is filled where the chamber it stands
## in has already been carved away, and the shaft over it is carved where the mass is still
## there. One flight does both — it leaves a chamber's air, climbs through the slab above it
## and arrives on the floor that slab carries.
func _carve_descent(st: CastleStair) -> void:
	for t in range(st.run_len()):
		var s := st.surface_at(t)
		## Arrival columns are a single surface course over open shaft, matching the keep's
		## thin landing: a full wedge here re-builds the two-course lip the shaft just cut.
		var thin := t >= st.rise + 1
		for k in range(st.lane_w):
			var p := st.column(t, k)
			if not _in_region(p.x, p.y):
				continue
			if thin:
				_carve_column(p.x, p.y, st.y_from + 1, s - 1)
				brush.fill_box(
					Vector3i(p.x, s, p.y),
					Vector3i(p.x + 1, s + 1, p.y + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
			else:
				brush.fill_box(
					Vector3i(p.x, st.y_from + 1, p.y),
					Vector3i(p.x + 1, s + 1, p.y + 1),
					VoxelMaterial.CASTLE_BLOCK
				)
			_carve_column(p.x, p.y, s + 1, s + DUNGEON_SHAFT_HEAD)


## Hollowed base of a corner tower, following the tower's own plan rather than assuming a
## square one, plus the recess that joins it to the bailey across the curtain's inside corner.
## A round tower of these radii never projects far enough past the curtain for a cardinal
## passage of its own, so the recess is what a body walks through; the wall keeps its outer
## `DUNGEON_TOWER_RECESS` courses either way.
func _carve_tower_base(e: CastleDungeonEntry) -> void:
	var t: CastleTower = layout.towers[e.tower_index]
	var y0 := layout.courtyard_y + 1
	var y1 := layout.courtyard_y + e.chamber_air_h
	for z in range(t.center.y - t.radius, t.center.y + t.radius + 1):
		for x in range(t.center.x - t.radius, t.center.x + t.radius + 1):
			if not _in_region(x, z):
				continue
			if not _tower_inside(t, x, z, DUNGEON_TOWER_BASE_WALL):
				continue
			_carve_column(x, z, y0, y1)
	var rec := e.chamber_rect
	for z2 in range(rec.position.y, rec.end.y):
		for x2 in range(rec.position.x, rec.end.x):
			if not _in_region(x2, z2):
				continue
			_carve_column(x2, z2, y0, y1)


## Columns of a tower's plan at least `margin` in from its face.
func _tower_inside(tower: CastleTower, x: int, z: int, margin: int) -> bool:
	var r := tower.radius - margin
	if r < 0:
		return false
	var dx := x - tower.center.x
	var dz := z - tower.center.y
	if tower.round_plan:
		return dx * dx + dz * dz <= r * r
	return maxi(absi(dx), absi(dz)) <= r


## Only masonry is removed. Writing AIR over air would materialise blocks for nothing, and the
## sky above a courtyard trench is exactly where that would happen.
func _carve_column(x: int, z: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		var vox := Vector3i(x, y, z)
		if brush.get_vox(vox) == VoxelMaterial.AIR:
			continue
		brush.set_vox(vox, VoxelMaterial.AIR)
		_dungeon_voxels += 1


## Damp masonry: the chamber floor and the faces around it, mossier the deeper the level. The
## deepest level is cut into the district's own stone rather than into the plinth, so without
## this its floor would be the bedrock stack showing through.
func _dress_vault(v: CastleVault) -> void:
	var damp := 1.0 - float(v.level) / float(maxi(layout.dungeon_levels - 1, 1))
	var r := v.rect
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not _in_region(x, z):
				continue
			_dress_face(x, v.floor_y, z, damp * 0.22)
	## The ring one column out is the chamber's walls. Openings already cut through them are
	## air by now and stay that way.
	var ring := r.grow(1)
	for z2 in range(ring.position.y, ring.end.y):
		for x2 in range(ring.position.x, ring.end.x):
			if r.has_point(Vector2i(x2, z2)) or not _in_region(x2, z2):
				continue
			for y in range(v.floor_y + 1, v.top_y() + 1):
				_dress_face(x2, y, z2, damp * 0.3 - float(y - v.floor_y) * 0.02)
	if not v.is_tall():
		return
	## A string course where each omitted slab would have landed. Without it a hall reaching up
	## through two levels photographs exactly like a room that happens to be tall, and the one
	## thing a vault is for is that a body inside it can see how far down it has come.
	for l in range(v.level + 1, v.level + v.span_levels):
		var course := layout.dungeon_floor_y(l)
		for z3 in range(ring.position.y, ring.end.y):
			for x3 in range(ring.position.x, ring.end.x):
				if r.has_point(Vector2i(x3, z3)) or not _in_region(x3, z3):
					continue
				for y2 in range(course - layout.dungeon_slab_thick + 1, course + 1):
					var at := Vector3i(x3, y2, z3)
					if brush.get_vox(at) == VoxelMaterial.AIR:
						continue
					brush.set_vox(at, VoxelMaterial.CASTLE_BLOCK)


func _dress_face(x: int, y: int, z: int, bias: float) -> void:
	var vox := Vector3i(x, y, z)
	if brush.get_vox(vox) == VoxelMaterial.AIR:
		return
	brush.set_vox(
		vox,
		(
			VoxelMaterial.CASTLE_BLOCK_MOSSY
			if _moss_here(x + y * 3, z - y * 5, bias)
			else VoxelMaterial.CASTLE_BLOCK
		)
	)


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
		"CastleComposer: %s plinth=%d vox dungeon=%d vox"
		% [layout.describe(), _plinth_voxels, _dungeon_voxels]
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Fisher-Yates over the four cardinals, so a choice among faces is unbiased and a lane that
## does not fit falls through to the next face rather than to a fixed second choice.
func _shuffled_dirs() -> Array[Vector2i]:
	var out: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	_shuffle_dirs(out)
	return out


func _shuffle_dirs(items: Array[Vector2i]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: Vector2i = items[i]
		items[i] = items[j]
		items[j] = swap


func _shuffled_ints(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(n):
		out.append(i)
	_shuffle_ints(out)
	return out


func _shuffle_ints(items: Array[int]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: int = items[i]
		items[i] = items[j]
		items[j] = swap


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
