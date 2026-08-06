## Builds a Gaming-theme games quarter: a festive outer wall rings the district, a dense
## maze fills the band inside it, attractions sit in a zoo-fence court (Go garden, Tetris
## arcade, monster-chess) with their own four gates — then the venues are baked inside.
class_name GamingComposer
extends RefCounted

const GamingGardenScript := preload("res://scripts/city/gaming_garden.gd")
const GamingArcadeScript := preload("res://scripts/city/gaming_arcade.gd")
const GamingChessCourtScript := preload("res://scripts/city/gaming_chess_court.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28
var voxel_size: float = 0.5
## Exact remaining gems for the maze scatter (district constant, or that minus harvested).
var gem_mats_to_place: PackedInt32Array = PackedInt32Array()

var layout: GamingLayout = null
var _garden: GamingGarden = null
var _arcade: GamingArcade = null
var _chess_court: GamingChessCourt = null

const BOARD_N := 19
## 3 m between crossings: wide enough for a rounded 5-voxel stone with a gap, and it
## makes the 1-voxel grid line a sixth of a cell instead of a quarter (which read as a
## white lattice rather than a board).
const GIANT_CELL := 6
## Light field carried past the outer lines, then the dark rim around it.
const BOARD_EDGE := 4
const BOARD_RIM := 2
const PAD_MARGIN := 8
## Light kaya-style playing surface; lines and rim are the dark timber.
const BOARD_FIELD_MAT := VoxelMaterial.GRAVEL
const BOARD_LINE_MAT := VoxelMaterial.TIMBER
## Wide enough for board Ui3D + settings panel side by side, and no wider — a bigger
## slab just reads as an empty timber field around two small panels.
const TABLE_W := 18
const TABLE_D := 10
## Low raised pad (no legs) — height in voxels above the meadow surface layer.
const TABLE_H := 2
## Board sits on the west half; settings on the east (fractions of table width).
const BOARD_X_FRAC := 0.33
const SETTINGS_X_FRAC := 0.76

## Satellite zones flank the garden on the west and east lawns, at the same depth as the
## garden band so the three read as one row of courts rather than a scatter.
## Kept clear of the reserve edge, where a perimeter road can run.
const ZONE_INSET := 6
## Gap between the garden band and a satellite: neither writes into the other.
const ZONE_GAP := 4
## Narrowest lawn worth a court at all — below this the zone is dropped, loudly.
const ZONE_MIN_W := 96
## 4 m per chess square: two 2.3 m monsters stand on adjacent squares without their
## silhouettes touching.
const CHESS_SQUARE_VOX := 8

## Festive outer district wall — inviting, uneven, not a quarantine look.
const WALL_INSET := 2
const WALL_THICK := 3
const WALL_H_BASE := 8
const WALL_H_VAR := 4
const WALL_PILLAR_PITCH := 11
const WALL_TOWER_H := 14
## Wide mid-edge openings so the quarter reads as a fairground, not a fort.
const OUTER_GATE_HALF := 8
const WALL_PALETTE: Array[int] = [
	VoxelMaterial.PLASTER,
	VoxelMaterial.BRICK,
	VoxelMaterial.ROOF_CLAY,
	VoxelMaterial.PAINT,
	VoxelMaterial.PLAZA,
	VoxelMaterial.BRICK_DARK,
]

## Zoo-style containment ring around the attractions (same materials / post rhythm).
const FENCE_THICK := 2
const FENCE_H := 16
const FENCE_POST_PITCH := 9
const FENCE_LINE_OFFSETS: Array[int] = [3, 8, 13]
## Walk room between the attraction AABBs and the inner face of the ring.
const FENCE_INNER_PAD := 8
## Mid-edge gate half-width (opening = 2*half+1), matching the zoo visitor gate.
const GATE_HALF := 5


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	if not _garden_for().plan_band(layout, min_v, max_v):
		return
	_plan_zones(min_v, max_v)
	if not _plan_fence_and_gates(min_v, max_v):
		return
	if not _plan_district_wall(min_v, max_v):
		return
	## Outer wall before the maze so the labyrinth fills the court band, not the verge.
	_build_district_wall()
	_build_district_wall_gates()
	## Maze reserves the attraction enclosure; then zoo ring, then venues.
	_paint_outer_maze()
	_scatter_maze_gems()
	_build_fence()
	_build_gates()
	_garden_for().decorate(layout, min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	_arcade_for().build(layout)
	_chess_court_for().build(layout)
	print("GamingComposer: %s" % layout.describe())


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin():
		return
	layout = _plan(min_v, max_v)
	if layout == null:
		return
	_paint_meadow(min_v, max_v)
	if not _garden_for().plan_band(layout, min_v, max_v):
		return
	_plan_zones(min_v, max_v)
	if not _plan_fence_and_gates(min_v, max_v):
		return
	if not _plan_district_wall(min_v, max_v):
		return
	_build_district_wall()
	_build_district_wall_gates()
	_paint_outer_maze()
	## Far bakes leave gem_mats_to_place empty — no ore until the full stream bake.
	_scatter_maze_gems()
	_build_fence()
	_build_gates()
	_garden_for().decorate_far(layout, min_v, max_v)
	_build_giant_pad()
	_build_main_table()
	## Both satellites are mostly silhouette (a lit pavilion, a checkerboard slab), so the
	## far pass builds the same shells — they are cheap and the quarter reads wrong without.
	_arcade_for().build(layout)
	_chess_court_for().build(layout)


func _garden_for() -> GamingGarden:
	if _garden == null:
		_garden = GamingGardenScript.new() as GamingGarden
		_garden.brush = brush
		_garden.rng = rng
		_garden.ground_y = ground_y
		_garden.table_w = TABLE_W
		_garden.table_d = TABLE_D
	return _garden


func _arcade_for() -> GamingArcade:
	if _arcade == null:
		_arcade = GamingArcadeScript.new() as GamingArcade
		_arcade.brush = brush
		_arcade.rng = rng
		_arcade.ground_y = ground_y
	return _arcade


func _chess_court_for() -> GamingChessCourt:
	if _chess_court == null:
		_chess_court = GamingChessCourtScript.new() as GamingChessCourt
		_chess_court.brush = brush
		_chess_court.rng = rng
		_chess_court.ground_y = ground_y
	return _chess_court


## Carve the two lawns either side of the garden band. Both satellites hug the garden —
## arcade on the west edge of its lawn, chess on the east lawn's west edge — so the row
## reads as one quarter, not a board parked in a distant meadow.
func _plan_zones(min_v: Vector3i, max_v: Vector3i) -> void:
	var g0 := layout.garden_min
	var g1 := layout.garden_max
	if g1.x <= g0.x or g1.z <= g0.z:
		push_error("GamingComposer: no garden band to flank — the satellites have no anchor")
		return
	var west_x0 := min_v.x + ZONE_INSET
	var west_x1 := g0.x - ZONE_GAP
	if west_x1 - west_x0 >= ZONE_MIN_W:
		var west_lawn := Rect2i(west_x0, g0.z, west_x1 - west_x0, g1.z - g0.z)
		GamingArcadeScript.plan_precinct(layout, west_lawn, ground_y)
	else:
		push_error(
			"GamingComposer: west lawn is only %d voxels wide — no arcade here"
			% [west_x1 - west_x0]
		)
	var east_x0 := g1.x + ZONE_GAP
	var east_x1 := max_v.x - ZONE_INSET
	if east_x1 - east_x0 < ZONE_MIN_W:
		push_error(
			"GamingComposer: east lawn is only %d voxels wide — no chess court here"
			% [east_x1 - east_x0]
		)
		return
	layout.chess_square_vox = CHESS_SQUARE_VOX
	var span := layout.chess_span_vox()
	## Match GamingChessCourt / GamingArcade: apron+rim west of the board, then a 2-voxel
	## garden margin so the court sits hard against the Go band.
	var court_pad: int = GamingChessCourtScript.RIM + GamingChessCourtScript.APRON
	var garden_margin: int = GamingArcadeScript.GARDEN_MARGIN
	var court_w := span + court_pad * 2 + garden_margin
	if east_x1 - east_x0 < court_w:
		push_error(
			"GamingComposer: east lawn %d cannot hold a %d-wide chess court"
			% [east_x1 - east_x0, court_w]
		)
		return
	layout.chess_origin = Vector3i(
		east_x0 + garden_margin + court_pad,
		ground_y + 1,
		(g0.z + g1.z) / 2 - span / 2
	)
	layout.chess_min = Vector3i(
		layout.chess_origin.x - court_pad,
		ground_y,
		layout.chess_origin.z - court_pad
	)
	layout.chess_max = Vector3i(
		layout.chess_origin.x + span + court_pad,
		ground_y + 1,
		layout.chess_origin.z + span + court_pad
	)


## Axis-aligned zoo ring that encloses every attraction, plus four mid-edge gate openings.
func _plan_fence_and_gates(min_v: Vector3i, max_v: Vector3i) -> bool:
	var core := _attraction_union()
	if core.size.x <= 0 or core.size.y <= 0:
		push_error("GamingComposer: no attraction footprints for the containment ring")
		return false
	var field := core.grow(FENCE_INNER_PAD)
	var fence := field.grow(FENCE_THICK)
	var reserve := Rect2i(min_v.x, min_v.z, max_v.x - min_v.x, max_v.z - min_v.z)
	if not reserve.encloses(fence):
		push_error(
			"GamingComposer: attraction fence %s does not fit reserve %s" % [fence, reserve]
		)
		return false
	layout.field_rect = field
	layout.fence_rect = fence
	layout.fence_top_y = ground_y + FENCE_H
	layout.gate_rects = _mid_edge_gates(fence, FENCE_THICK, GATE_HALF)
	return true


## Festive wall hugging the reserve edge, wide enough that the maze still fits inside.
func _plan_district_wall(min_v: Vector3i, max_v: Vector3i) -> bool:
	var reserve := Rect2i(min_v.x, min_v.z, max_v.x - min_v.x, max_v.z - min_v.z)
	var wall := reserve.grow(-WALL_INSET)
	if wall.size.x < 48 or wall.size.y < 48:
		push_error("GamingComposer: reserve %s too small for a district wall" % reserve)
		return false
	var inner := wall.grow(-WALL_THICK)
	if not inner.encloses(layout.fence_rect):
		push_error(
			"GamingComposer: district wall %s does not clear attraction fence %s"
			% [wall, layout.fence_rect]
		)
		return false
	layout.wall_rect = wall
	layout.wall_gate_rects = _mid_edge_gates(wall, WALL_THICK, OUTER_GATE_HALF)
	return true


func _mid_edge_gates(ring: Rect2i, thick: int, half: int) -> Array[Rect2i]:
	var mid_x := ring.position.x + ring.size.x / 2
	var mid_z := ring.position.y + ring.size.y / 2
	var gate_w := half * 2 + 1
	var out: Array[Rect2i] = []
	out.append(Rect2i(mid_x - half, ring.position.y, gate_w, thick))
	out.append(Rect2i(mid_x - half, ring.end.y - thick, gate_w, thick))
	out.append(Rect2i(ring.position.x, mid_z - half, thick, gate_w))
	out.append(Rect2i(ring.end.x - thick, mid_z - half, thick, gate_w))
	return out


func _attraction_union() -> Rect2i:
	var rects: Array[Rect2i] = [
		_xz_rect(layout.garden_min, layout.garden_max),
		_xz_rect(layout.arcade_min, layout.arcade_max),
		_xz_rect(layout.chess_min, layout.chess_max),
	]
	var core := Rect2i()
	var has := false
	for r: Rect2i in rects:
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		if not has:
			core = r
			has = true
		else:
			core = core.merge(r)
	return core


func _xz_rect(p0: Vector3i, p1: Vector3i) -> Rect2i:
	if p1.x <= p0.x or p1.z <= p0.z:
		return Rect2i()
	return Rect2i(p0.x, p0.z, p1.x - p0.x, p1.z - p0.z)


func _begin() -> bool:
	if brush == null or rng == null or planner == null:
		push_error("GamingComposer: brush / rng / planner not set")
		return false
	if planner.large_gaming.size.x <= 0:
		push_error("GamingComposer: empty large_gaming")
		return false
	return true


func _plan(min_v: Vector3i, max_v: Vector3i) -> GamingLayout:
	var la: Rect2i = planner.large_gaming
	var x0 := la.position.x * cell_size
	var z0 := la.position.y * cell_size
	var x1 := la.end.x * cell_size
	var z1 := la.end.y * cell_size
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2
	var span := (BOARD_N - 1) * GIANT_CELL
	var pad_side := span + (BOARD_EDGE + BOARD_RIM + PAD_MARGIN) * 2 + 1
	var ly := GamingLayout.new()
	ly.board_n = BOARD_N
	ly.giant_cell_vox = GIANT_CELL
	ly.field_span_vox = span
	ly.pad_min = Vector3i(cx - pad_side / 2, ground_y, cz - pad_side / 2)
	ly.pad_max = Vector3i(ly.pad_min.x + pad_side, ground_y + 1, ly.pad_min.z + pad_side)
	var inset := PAD_MARGIN + BOARD_RIM + BOARD_EDGE
	ly.giant_origin = Vector3i(
		ly.pad_min.x + inset,
		ground_y + 1,
		ly.pad_min.z + inset
	)
	## Main table south of the pad, facing north toward the giant board.
	var table_z := ly.pad_min.z - 18
	var table_x := cx - TABLE_W / 2
	ly.main_table_origin = Vector3i(table_x, ground_y, table_z)
	ly.main_table_yaw = 0.0
	var vs := voxel_size
	var mid_x := (float(table_x) + float(TABLE_W) * 0.5) * vs
	ly.black_stand_local = Vector3(
		mid_x,
		float(ground_y + 1) * vs,
		(float(table_z) - 2.5) * vs
	)
	ly.white_stand_local = Vector3(
		mid_x,
		float(ground_y + 1) * vs,
		(float(table_z) + float(TABLE_D) + 2.5) * vs
	)
	## Waiting bench east of the table.
	ly.ai_wait_local = Vector3(
		(float(table_x) + float(TABLE_W) + 4.0) * vs,
		float(ground_y + 1) * vs,
		(float(table_z) + float(TABLE_D) * 0.5) * vs
	)
	ly.spawn_local = Vector3(
		float(cx) * vs,
		float(ground_y + 1) * vs + 0.85,
		(float(table_z) - 22.0) * vs
	)
	ly.spawn_yaw = 0.0
	return ly


func _paint_meadow(min_v: Vector3i, max_v: Vector3i) -> void:
	brush.fill_box(
		Vector3i(min_v.x, ground_y, min_v.z),
		Vector3i(max_v.x, ground_y + 1, max_v.z),
		VoxelMaterial.PARK
	)


## Dense labyrinth in the band between the festive wall and the attraction fence.
func _paint_outer_maze() -> void:
	## Inside face of the district wall — maze must not stamp over the festive ring.
	var rect := layout.wall_rect.grow(-WALL_THICK)
	if rect.size.x < 16 or rect.size.y < 16:
		push_error("GamingComposer: maze court %s too small" % rect)
		return
	var vol: RoomVolume = RoomVolumeScript.make(
		rect, ground_y, RoomDecoratorScript.ARENA_MAZE_WALL_H
	) as RoomVolume
	## Reserve the attraction enclosure so walls only stamp in the maze band.
	vol.keep_clear.append(layout.fence_rect)
	var dec: RoomDecorator = RoomDecoratorScript.new() as RoomDecorator
	dec.brush = brush
	dec.rng = rng
	dec.arena_punch_rooms = false
	var walls := dec.decorate(vol, RoomDecoratorScript.Purpose.ARENA)
	if walls <= 0:
		push_error("GamingComposer: maze band left no wall columns in %s" % rect)


## Sit exactly `gem_mats_to_place` on labyrinth passage floors — air above the meadow deck,
## never replacing a wall column. Same remaining-list contract as the hill quota scatter.
func _scatter_maze_gems() -> void:
	var quota := gem_mats_to_place.size()
	if quota <= 0 or layout == null:
		return
	var rect := layout.wall_rect.grow(-WALL_THICK)
	if rect.size.x < 16 or rect.size.y < 16:
		push_error("GamingComposer: maze gem scatter skipped — court %s too small" % rect)
		return
	var floor_y := ground_y + 1
	var hosts: Array[Vector3i] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if layout.fence_rect.has_point(Vector2i(x, z)):
				continue
			## Passage only: wall columns keep fractal ore out of the walking surface.
			if VoxelMaterial.is_fractal_band(brush.get_vox(Vector3i(x, floor_y, z))):
				continue
			var cursor := Vector3i(x, floor_y, z)
			if brush.get_vox(cursor) != VoxelMaterial.AIR:
				continue
			hosts.append(cursor)
	if hosts.is_empty():
		push_error("GamingComposer: no maze floor hosts for %d budgeted gems" % quota)
		return
	for i in range(hosts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := hosts[i]
		hosts[i] = hosts[j]
		hosts[j] = tmp
	var placed := 0
	brush.begin_edit()
	while placed < quota and placed < hosts.size():
		brush.set_vox(hosts[placed], int(gem_mats_to_place[placed]))
		placed += 1
	brush.end_edit()
	if placed < quota:
		push_error(
			"GamingComposer: only placed %d of %d budgeted maze gems (hosts %d)"
			% [placed, quota, hosts.size()]
		)
	print("GamingComposer: maze floor gems=%d (quota %d)" % [placed, quota])


## Uneven fairground curtain: waving height, mixed colours, lit pillars, corner towers.
func _build_district_wall() -> void:
	var wall := layout.wall_rect
	var deck := ground_y
	brush.begin_edit()
	for z in range(wall.position.y, wall.end.y):
		for x in range(wall.position.x, wall.end.x):
			var depth := _ring_depth(x, z, wall, WALL_THICK)
			if depth < 0:
				continue
			if _wall_gate_covers(Vector2i(x, z)):
				continue
			var along := x if _ring_runs_along_x(x, z, wall) else z
			var corner := _is_ring_corner(x, z, wall, WALL_THICK + 2)
			var pillar := (not corner) and along % WALL_PILLAR_PITCH == 0
			var h := _wall_column_h(along, pillar, corner)
			var body := _wall_body_mat(along, depth)
			brush.set_vox(Vector3i(x, deck, z), VoxelMaterial.STONE)
			for y in range(deck + 1, deck + 1 + h):
				var mat := body
				var up := y - deck
				## Candy stripe every third course — reads as bunting from a distance.
				if up > 1 and up % 3 == 0 and not pillar and not corner:
					mat = WALL_PALETTE[(along / 2 + up) % WALL_PALETTE.size()]
				## Outer face gets the brighter panels; inner face stays a calmer brick.
				if depth == WALL_THICK - 1 and not pillar and not corner and up % 3 != 0:
					mat = VoxelMaterial.BRICK
				brush.set_vox(Vector3i(x, y, z), mat)
			## Cap: lit jewel on pillars/towers, plaster merlon elsewhere.
			var cap_y := deck + h
			if pillar or corner:
				brush.set_vox(Vector3i(x, cap_y, z), VoxelMaterial.GLASS_LIT)
				if corner:
					brush.set_vox(Vector3i(x, cap_y + 1, z), VoxelMaterial.ROOF_CLAY)
			elif along % 2 == 0:
				brush.set_vox(Vector3i(x, cap_y, z), VoxelMaterial.PLASTER)
	brush.end_edit()


func _wall_column_h(along: int, pillar: bool, corner: bool) -> int:
	if corner:
		return WALL_TOWER_H
	## Gentle wave so the skyline is never a flat rampart.
	var wave := int((sin(float(along) * 0.28) + 1.0) * 0.5 * float(WALL_H_VAR))
	var h := WALL_H_BASE + wave
	if pillar:
		h += 3
	return h


func _wall_body_mat(along: int, depth: int) -> int:
	## Segment the run into coloured bays — not one repeating brick.
	var bay := along / 7
	var mat: int = WALL_PALETTE[absi(bay) % WALL_PALETTE.size()]
	if depth == 0 and (along % 5 == 0):
		return VoxelMaterial.METAL_PLATE
	return mat


func _is_ring_corner(x: int, z: int, ring: Rect2i, reach: int) -> bool:
	var near_x := (
		x < ring.position.x + reach or x >= ring.end.x - reach
	)
	var near_z := (
		z < ring.position.y + reach or z >= ring.end.y - reach
	)
	return near_x and near_z


## Wide colourful gatehouses: clear the opening, gravel threshold, lit arch + jamb towers.
func _build_district_wall_gates() -> void:
	var deck := ground_y
	var arch_y := deck + WALL_H_BASE + 1
	for g: Rect2i in layout.wall_gate_rects:
		brush.fill_box(
			Vector3i(g.position.x, deck + 1, g.position.y),
			Vector3i(g.end.x, deck + WALL_TOWER_H + 3, g.end.y),
			VoxelMaterial.AIR
		)
		brush.fill_box(
			Vector3i(g.position.x, deck, g.position.y),
			Vector3i(g.end.x, deck + 1, g.end.y),
			VoxelMaterial.PLAZA
		)
		## Rainbow lintel stack — three bright courses so the mouth reads from the maze.
		brush.fill_box(
			Vector3i(g.position.x, arch_y, g.position.y),
			Vector3i(g.end.x, arch_y + 1, g.end.y),
			VoxelMaterial.ROOF_CLAY
		)
		brush.fill_box(
			Vector3i(g.position.x, arch_y + 1, g.position.y),
			Vector3i(g.end.x, arch_y + 2, g.end.y),
			VoxelMaterial.PAINT
		)
		brush.fill_box(
			Vector3i(g.position.x, arch_y + 2, g.position.y),
			Vector3i(g.end.x, arch_y + 3, g.end.y),
			VoxelMaterial.GLASS_LIT
		)
		_build_gate_jambs(g)


## Little tower on each side of an outer gate so the entrance feels like a ticket booth.
func _build_gate_jambs(g: Rect2i) -> void:
	var deck := ground_y
	var along_x := g.size.x > g.size.y
	var jambs: Array[Vector2i] = []
	if along_x:
		jambs.append(Vector2i(g.position.x - 2, g.position.y))
		jambs.append(Vector2i(g.end.x + 1, g.position.y))
	else:
		jambs.append(Vector2i(g.position.x, g.position.y - 2))
		jambs.append(Vector2i(g.position.x, g.end.y + 1))
	for j: Vector2i in jambs:
		for dz in range(WALL_THICK):
			for dx in range(2):
				var x := j.x + (dx if along_x else dz)
				var z := j.y + (dz if along_x else dx)
				if not layout.wall_rect.has_point(Vector2i(x, z)):
					continue
				for y in range(deck, deck + WALL_TOWER_H):
					var mat := VoxelMaterial.BRICK_DARK
					if (y - deck) % 3 == 0:
						mat = VoxelMaterial.ROOF_CLAY
					brush.set_vox(Vector3i(x, y, z), mat)
				brush.set_vox(
					Vector3i(x, deck + WALL_TOWER_H, z), VoxelMaterial.GLASS_LIT
				)


func _wall_gate_covers(p: Vector2i) -> bool:
	for g: Rect2i in layout.wall_gate_rects:
		if g.has_point(p):
			return true
	return false


func _ring_depth(x: int, z: int, ring: Rect2i, thick: int) -> int:
	var dx := mini(x - ring.position.x, ring.end.x - 1 - x)
	var dz := mini(z - ring.position.y, ring.end.y - 1 - z)
	var d := mini(dx, dz)
	if d < 0 or d >= thick:
		return -1
	return d


func _ring_runs_along_x(x: int, z: int, ring: Rect2i) -> bool:
	var dz := mini(z - ring.position.y, ring.end.y - 1 - z)
	var dx := mini(x - ring.position.x, ring.end.x - 1 - x)
	return dz <= dx


## Same quarantine look as ZooComposer._build_fence: posts, red energy bands, outer glass.
func _build_fence() -> void:
	var fence := layout.fence_rect
	var deck := ground_y
	var top := layout.fence_top_y
	brush.begin_edit()
	for z in range(fence.position.y, fence.end.y):
		for x in range(fence.position.x, fence.end.x):
			var depth := _ring_depth(x, z, fence, FENCE_THICK)
			if depth < 0:
				continue
			if _gate_covers(Vector2i(x, z)):
				continue
			var along := x if _ring_runs_along_x(x, z, fence) else z
			var post := along % FENCE_POST_PITCH == 0
			brush.set_vox(Vector3i(x, deck, z), VoxelMaterial.ZOO_FENCE_FRAME)
			for y in range(deck + 1, top + 1):
				var mat := VoxelMaterial.ZOO_FENCE_FRAME
				if FENCE_LINE_OFFSETS.has(y - deck):
					mat = VoxelMaterial.ZOO_FENCE_LINE
				elif depth == 0 and not post and y != top and y != deck + 1:
					mat = VoxelMaterial.ZOO_FENCE_GLASS
				brush.set_vox(Vector3i(x, y, z), mat)
	brush.end_edit()


func _gate_covers(p: Vector2i) -> bool:
	for g: Rect2i in layout.gate_rects:
		if g.has_point(p):
			return true
	return false


## Open the four mid-edge ring cuts and hang a zoo-style frame lintel on each.
func _build_gates() -> void:
	var deck := ground_y
	var lintel := deck + 9
	for g: Rect2i in layout.gate_rects:
		brush.fill_box(
			Vector3i(g.position.x, deck + 1, g.position.y),
			Vector3i(g.end.x, layout.fence_top_y + 1, g.end.y),
			VoxelMaterial.AIR
		)
		brush.fill_box(
			Vector3i(g.position.x, deck, g.position.y),
			Vector3i(g.end.x, deck + 1, g.end.y),
			VoxelMaterial.GRAVEL
		)
		brush.fill_box(
			Vector3i(g.position.x, lintel, g.position.y),
			Vector3i(g.end.x, lintel + 1, g.end.y),
			VoxelMaterial.ZOO_FENCE_FRAME
		)
		brush.fill_box(
			Vector3i(g.position.x, lintel + 1, g.position.y),
			Vector3i(g.end.x, lintel + 2, g.end.y),
			VoxelMaterial.ZOO_FENCE_LINE
		)


func _build_giant_pad() -> void:
	var p0 := layout.pad_min
	var p1 := layout.pad_max
	## Plain stone apron — the walkable frame the board is read against.
	brush.fill_box(p0, Vector3i(p1.x, ground_y + 1, p1.z), VoxelMaterial.STONE)
	var go := layout.giant_origin
	var cell := layout.giant_cell_vox
	var span := layout.giant_span_vox()
	var board_y := ground_y + 1
	## Dark rim, then the light field inside it — both a single flush layer, so the
	## board is a slab you look at, not a lattice you walk through.
	var rim := BOARD_EDGE + BOARD_RIM
	brush.fill_box(
		Vector3i(go.x - rim, board_y, go.z - rim),
		Vector3i(go.x + span + rim + 1, board_y + 1, go.z + span + rim + 1),
		BOARD_LINE_MAT
	)
	brush.fill_box(
		Vector3i(go.x - BOARD_EDGE, board_y, go.z - BOARD_EDGE),
		Vector3i(go.x + span + BOARD_EDGE + 1, board_y + 1, go.z + span + BOARD_EDGE + 1),
		BOARD_FIELD_MAT
	)
	## n lines meet at n×n crossings — stones sit on those intersections.
	for i in range(BOARD_N):
		var lx := go.x + i * cell
		var lz := go.z + i * cell
		brush.fill_box(
			Vector3i(lx, board_y, go.z),
			Vector3i(lx + 1, board_y + 1, go.z + span + 1),
			BOARD_LINE_MAT
		)
		brush.fill_box(
			Vector3i(go.x, board_y, lz),
			Vector3i(go.x + span + 1, board_y + 1, lz + 1),
			BOARD_LINE_MAT
		)
	var hoshi := hoshi_points(BOARD_N)
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
			## Star point: a round dot on the crossing, same ink as the lines.
			brush.fill_disk(
				go.x + hx * cell, go.z + hz * cell, board_y, 1, BOARD_LINE_MAT
			)


## Star-point indices for a board of size `n` (GTP coordinates from the SW corner).
static func hoshi_points(n: int) -> PackedInt32Array:
	if n >= 19:
		return PackedInt32Array([3, 9, 15])
	if n >= 13:
		return PackedInt32Array([3, 6, 9])
	if n >= 9:
		return PackedInt32Array([2, 4, 6])
	return PackedInt32Array()


func _build_main_table() -> void:
	_build_table_block(layout.main_table_origin)


func _build_table_block(origin: Vector3i) -> void:
	var y0 := ground_y + 1
	var y_top := y0 + TABLE_H
	if TABLE_H > 1:
		brush.fill_box(
			Vector3i(origin.x, y0, origin.z),
			Vector3i(origin.x + TABLE_W, y_top - 1, origin.z + TABLE_D),
			VoxelMaterial.STONE
		)
	brush.fill_box(
		Vector3i(origin.x, y_top - 1, origin.z),
		Vector3i(origin.x + TABLE_W, y_top, origin.z + TABLE_D),
		VoxelMaterial.TIMBER
	)
