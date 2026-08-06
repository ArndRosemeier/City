## Seeded land-use grid: organic avenues/streets, plazas, parks, zones (rectangular).
class_name DistrictPlanner
extends RefCounted

const WorldArterialsScript := preload("res://scripts/city/world_arterials.gd")

## Side of the besieged quarter in planner cells. Eight cells is 8 × 28 voxels × 0.5 m ≈ 112 m —
## a few blocks, which is what a readable defence needs. Spreading it over the whole 392 × 280 m
## tile would put the pads too far apart to support each other.
const SIEGE_QUARTER_CELLS := 8
## Side of each outer stone's monument square, in planner cells — 3 × 28 voxels × 0.5 m = 42 m.
const SIEGE_STONE_SQUARE_CELLS := 3
## How far a square may be nudged off its ideal cell, in cells, to find ground that is not road.
const SIEGE_STONE_NUDGE_CELLS := 3
## Cells of a square that must be off the carriageway for it to be worth reserving.
const SIEGE_STONE_MIN_OPEN := 3

## District personality — palette, density and height profile. Set before build().
var theme: DistrictTheme = null
var cell_size: int = 28
var cells_x: int = 0
var cells_z: int = 0
## grid[z][x] = LandUse tag
var grid: Array = []
## intensity[z][x] = 0..1 urban density. Computed from *world* cell coordinates, so
## clusters flow across district borders instead of restarting per tile.
var intensity: Array = []
var grand_plaza: Rect2i = Rect2i()
var satellite_plazas: Array[Rect2i] = []
var large_park: Rect2i = Rect2i()
var pocket_parks: Array[Vector2i] = []
## Bounding rect of LandUse.HILL cells (Hill theme). Empty when unused.
var large_hill: Rect2i = Rect2i()
## Bounding rect of LandUse.GRAVEYARD cells. Empty when unused.
var large_graveyard: Rect2i = Rect2i()
## Bounding rect of LandUse.LAKE cells. Empty when unused.
var large_lake: Rect2i = Rect2i()
## Bounding rect of LandUse.CASTLE cells. Empty when unused.
var large_castle: Rect2i = Rect2i()
## Bounding rect of LandUse.FRACTAL cells. Empty when unused.
var large_fractal: Rect2i = Rect2i()
## Bounding rect of LandUse.ARENA cells. Empty when unused.
var large_arena: Rect2i = Rect2i()
## Bounding rect of LandUse.ZOO cells. Empty when unused.
var large_zoo: Rect2i = Rect2i()
## Bounding rect of LandUse.GAMING cells. Empty when unused.
var large_gaming: Rect2i = Rect2i()
## Besieged ground on a Siege tile, in planner cells. Empty on every other theme.
##
## Cells inside it keep their ordinary tags: the siege is an overlay on the street grid, not a
## reserve that replaced it, because the streets are the lanes the horde walks.
var siege_quarter: Rect2i = Rect2i()
## Paved squares held open for the four outer stones, in planner cells. Empty on every other theme.
## Unlike the quarter this *does* steer the grid — see `_clear_siege_stone_squares`.
var siege_stone_squares: Array[Rect2i] = []
var civic_lot: Vector2i = Vector2i(-1, -1)
## The one teleport chamber plot on this tile, or (-1,-1) on spectacle themes that have no
## lots at all.
var teleport_lot: Vector2i = Vector2i(-1, -1)
## Multi-cell CORE tower parcels (planner cells). `position` is the anchor corner;
## every cell in the rect stays `CORE_LOT`, but only the anchor paints a building.
var tower_parcels: Array[Rect2i] = []
## Cell → index into `tower_parcels`, or -1. Downtown now merges every CORE block that
## fits, so the old linear scan per lookup turned into cells × parcels work per bake.
var _parcel_index: PackedInt32Array = PackedInt32Array()
## World-space tips for street lights (cell centers along avenues).
var avenue_light_cells: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()


func build(size_x: int, size_z: int, seed_value: int, p_cell_size: int = 28, district_coord: Vector2i = Vector2i.ZERO) -> void:
	if theme == null:
		push_error("DistrictPlanner.build: theme not set")
		return
	cell_size = p_cell_size
	cells_x = size_x / cell_size
	cells_z = size_z / cell_size
	_rng.seed = seed_value
	grid.clear()
	grid.resize(cells_z)
	for z in range(cells_z):
		var row: Array = []
		row.resize(cells_x)
		row.fill(LandUse.LOT)
		grid[z] = row
	_build_intensity(district_coord)
	satellite_plazas.clear()
	pocket_parks.clear()
	avenue_light_cells.clear()
	civic_lot = Vector2i(-1, -1)
	teleport_lot = Vector2i(-1, -1)
	_reset_tower_parcels()
	grand_plaza = Rect2i()
	large_park = Rect2i()
	large_hill = Rect2i()
	large_graveyard = Rect2i()
	large_lake = Rect2i()
	large_castle = Rect2i()
	large_fractal = Rect2i()
	large_arena = Rect2i()
	large_zoo = Rect2i()
	large_gaming = Rect2i()
	siege_quarter = Rect2i()
	siege_stone_squares.clear()

	if theme.id == DistrictTheme.HILL:
		## Edge stubs only — a full arterial cross would slice the massif into wedges.
		_stamp_hill_edge_connectors(district_coord)
		_build_hill_layout()
	elif theme.id == DistrictTheme.GRAVEYARD:
		## Same edge connectors as Hill — the necropolis keeps the middle streetless.
		_stamp_hill_edge_connectors(district_coord)
		_build_graveyard_layout()
	elif theme.id == DistrictTheme.LAKE:
		## Same edge connectors as Hill — the basin keeps the middle streetless.
		_stamp_hill_edge_connectors(district_coord)
		_build_lake_layout()
	elif theme.id == DistrictTheme.CASTLE:
		## Same edge connectors as Hill — the fortress owns the middle, and the causeway
		## is the only way in, so an interior street grid would defeat the point.
		_stamp_hill_edge_connectors(district_coord)
		_build_castle_layout()
	elif theme.id == DistrictTheme.FRACTAL:
		_stamp_hill_edge_connectors(district_coord)
		_build_fractal_layout()
	elif theme.id == DistrictTheme.ARENA:
		_stamp_hill_edge_connectors(district_coord)
		_build_arena_layout()
	elif theme.id == DistrictTheme.ZOO:
		_stamp_hill_edge_connectors(district_coord)
		_build_zoo_layout()
	elif theme.id == DistrictTheme.GAMING:
		_stamp_hill_edge_connectors(district_coord)
		_build_gaming_layout()
	else:
		_stamp_world_arterials(district_coord)
		_stamp_organic_interior_roads()
		_stamp_grand_plaza()
		_stamp_satellite_plazas()
		_stamp_large_park()
		_stamp_pocket_parks()
		_assign_zones()
		if theme.id == DistrictTheme.SIEGE:
			## Before every lot placer, because this one *does* steer the grid.
			_clear_siege_stone_squares()
		_place_civic()
		## Before the parcel merge on purpose: retagging the cell takes it out of CORE_LOT,
		## which is the only tag `_place_tower_parcels` will absorb, so the chamber can never
		## be swallowed by a tower plot.
		_place_teleport_chamber()
		_place_tower_parcels()
		if theme.id == DistrictTheme.SIEGE:
			## Last, and additive: the siege reads the finished grid rather than steering it, so
			## a Siege tile is a normal quarter that got barricaded.
			_build_siege_quarter()
	_collect_avenue_lights()


## Backward-compatible alias used by older call sites.
func build_square(size_xz: int, seed_value: int, p_cell_size: int = 28) -> void:
	build(size_xz, size_xz, seed_value, p_cell_size)


func tag_at(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return LandUse.ROAD
	return int(grid[cz][cx])


## Is this cell a road belonging to *this* district? `tag_at` calls everything outside the
## planner a road so that streets run off the edge and meet the neighbouring tile's, which is
## right for stamping voxels and wrong for anything building per-district topology: a lane or
## a kerb pad out there was never created, so asking for one is a bug rather than a border.
func has_road_cell(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return false
	return LandUse.is_road(int(grid[cz][cx]))


func is_corner_lot(cx: int, cz: int) -> bool:
	var road_n := 0
	if cz + 1 < cells_z and LandUse.is_road(tag_at(cx, cz + 1)):
		road_n += 1
	if cz - 1 >= 0 and LandUse.is_road(tag_at(cx, cz - 1)):
		road_n += 1
	if cx + 1 < cells_x and LandUse.is_road(tag_at(cx + 1, cz)):
		road_n += 1
	if cx - 1 >= 0 and LandUse.is_road(tag_at(cx - 1, cz)):
		road_n += 1
	return road_n >= 2


func faces_plaza(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if tag_at(cx + dx, cz + dz) == LandUse.PLAZA:
				return true
	return false


func faces_park(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if LandUse.is_open_nature(tag_at(cx + dx, cz + dz)):
				return true
	return false


## How far a connector stub reaches into a hill tile from each edge (planning cells).
## Short on purpose: long stubs carved flat valleys deep into the massif.
const HILL_STUB_CELLS := 2
## Edge band that must stay fully arterial so neighbouring districts still seam.
const HILL_EDGE_SEAM := 2


## Hill theme: stub the world arterials in from each edge, leave the middle open.
##
## A full arterial cross would split the tile into wedges and force the hill to
## ramp down into every corridor. Instead each arterial only keeps the cells that
## either sit on a district seam or form a short stub into the hillside, and the
## inland tip widens into a small turning pad so the road reads as a trailhead.
func _stamp_hill_edge_connectors(district_coord: Vector2i) -> void:
	var base_cx := district_coord.x * cells_x
	var base_cz := district_coord.y * cells_z
	var keep := PackedByteArray()
	keep.resize(cells_x * cells_z)
	for lz in range(cells_z):
		if not WorldArterialsScript.is_arterial_row(base_cz + lz):
			continue
		var on_ns_seam := lz < HILL_EDGE_SEAM or lz >= cells_z - HILL_EDGE_SEAM
		for lx in range(cells_x):
			if on_ns_seam or lx < HILL_STUB_CELLS or lx >= cells_x - HILL_STUB_CELLS:
				keep[lz * cells_x + lx] = 1
	for lx in range(cells_x):
		if not WorldArterialsScript.is_arterial_col(base_cx + lx):
			continue
		var on_ew_seam := lx < HILL_EDGE_SEAM or lx >= cells_x - HILL_EDGE_SEAM
		for lz in range(cells_z):
			if on_ew_seam or lz < HILL_STUB_CELLS or lz >= cells_z - HILL_STUB_CELLS:
				keep[lz * cells_x + lx] = 1
	for z in range(cells_z):
		for x in range(cells_x):
			if keep[z * cells_x + x] != 0:
				grid[z][x] = LandUse.AVENUE
	_stamp_hill_road_endings(base_cx, base_cz)


## Widen the inland tip of each stub into a 3×3 avenue pad (turning / trailhead).
func _stamp_hill_road_endings(base_cx: int, base_cz: int) -> void:
	for lz in range(cells_z):
		if not WorldArterialsScript.is_arterial_row(base_cz + lz):
			continue
		## Full seam rows have no inland tip — they continue into the neighbour.
		if lz < HILL_EDGE_SEAM or lz >= cells_z - HILL_EDGE_SEAM:
			continue
		_fill_hill_pad(HILL_STUB_CELLS - 1, lz)
		_fill_hill_pad(cells_x - HILL_STUB_CELLS, lz)
	for lx in range(cells_x):
		if not WorldArterialsScript.is_arterial_col(base_cx + lx):
			continue
		if lx < HILL_EDGE_SEAM or lx >= cells_x - HILL_EDGE_SEAM:
			continue
		_fill_hill_pad(lx, HILL_STUB_CELLS - 1)
		_fill_hill_pad(lx, cells_z - HILL_STUB_CELLS)


func _fill_hill_pad(cx: int, cz: int) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= cells_x or z >= cells_z:
				continue
			grid[z][x] = LandUse.AVENUE


## Hill theme: everything that is not a connector stub becomes open hillside.
func _build_hill_layout() -> void:
	large_hill = _fill_open_reserve(LandUse.HILL)
	if large_hill.size.x <= 0:
		push_error("DistrictPlanner._build_hill_layout: no hill cells after road stamp")


## Graveyard theme: non-road cells become consecrated ground for GraveyardComposer.
func _build_graveyard_layout() -> void:
	large_graveyard = _fill_open_reserve(LandUse.GRAVEYARD)
	if large_graveyard.size.x <= 0:
		push_error("DistrictPlanner._build_graveyard_layout: no graveyard cells after road stamp")


## Lake theme: non-road cells become the basin reserve for LakeComposer.
func _build_lake_layout() -> void:
	large_lake = _fill_open_reserve(LandUse.LAKE)
	if large_lake.size.x <= 0:
		push_error("DistrictPlanner._build_lake_layout: no lake cells after road stamp")


## Castle theme: non-road cells become the fortress reserve for CastleComposer.
func _build_castle_layout() -> void:
	large_castle = _fill_open_reserve(LandUse.CASTLE)
	if large_castle.size.x <= 0:
		push_error("DistrictPlanner._build_castle_layout: no castle cells after road stamp")


## Fractal theme: non-road cells become the open reserve (grass + centered glow square).
func _build_fractal_layout() -> void:
	large_fractal = _fill_open_reserve(LandUse.FRACTAL)
	if large_fractal.size.x <= 0:
		push_error("DistrictPlanner._build_fractal_layout: no fractal cells after road stamp")


## Arena theme: non-road cells become the colosseum reserve for ArenaComposer.
func _build_arena_layout() -> void:
	large_arena = _fill_open_reserve(LandUse.ARENA)
	if large_arena.size.x <= 0:
		push_error("DistrictPlanner._build_arena_layout: no arena cells after road stamp")


## Zoo theme: non-road cells become the fenced battlefield reserve for ZooComposer.
func _build_zoo_layout() -> void:
	large_zoo = _fill_open_reserve(LandUse.ZOO)
	if large_zoo.size.x <= 0:
		push_error("DistrictPlanner._build_zoo_layout: no zoo cells after road stamp")


## Gaming theme: non-road cells become the plaza reserve for GamingComposer.
func _build_gaming_layout() -> void:
	large_gaming = _fill_open_reserve(LandUse.GAMING)
	if large_gaming.size.x <= 0:
		push_error("DistrictPlanner._build_gaming_layout: no gaming cells after road stamp")


func _fill_open_reserve(tag: int) -> Rect2i:
	var min_x := cells_x
	var min_z := cells_z
	var max_x := -1
	var max_z := -1
	for z in range(cells_z):
		for x in range(cells_x):
			if LandUse.is_road(grid[z][x]):
				continue
			grid[z][x] = tag
			min_x = mini(min_x, x)
			min_z = mini(min_z, z)
			max_x = maxi(max_x, x)
			max_z = maxi(max_z, z)
	if max_x >= min_x and max_z >= min_z:
		return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)
	return Rect2i()


func street_facing(cx: int, cz: int) -> int:
	## 0=+Z, 1=-Z, 2=+X, 3=-X
	if cz + 1 < cells_z and LandUse.is_road(tag_at(cx, cz + 1)):
		return 0
	if cz - 1 >= 0 and LandUse.is_road(tag_at(cx, cz - 1)):
		return 1
	if cx + 1 < cells_x and LandUse.is_road(tag_at(cx + 1, cz)):
		return 2
	if cx - 1 >= 0 and LandUse.is_road(tag_at(cx - 1, cz)):
		return 3
	## No street: face whatever open space there is. A random side would put the front door
	## into a party wall now that lot-to-lot sides build flush against the neighbour.
	var rect := Rect2i(cx, cz, 1, 1)
	for side in range(4):
		if rect_side_open(rect, side):
			return side
	return _rng.randi() % 4


func _stamp_world_arterials(district_coord: Vector2i) -> void:
	## Fixed world avenues so adjacent districts share edge openings.
	var base_cx := district_coord.x * cells_x
	var base_cz := district_coord.y * cells_z
	for lz in range(cells_z):
		var wcz := base_cz + lz
		if WorldArterialsScript.is_arterial_row(wcz):
			_stamp_row(lz, LandUse.AVENUE)
	for lx in range(cells_x):
		var wcx := base_cx + lx
		if WorldArterialsScript.is_arterial_col(wcx):
			_stamp_col(lx, LandUse.AVENUE)


func _stamp_organic_interior_roads() -> void:
	## Secondary streets stay off the outer ring so edge seams stay arterial-only.
	var density := theme.road_density
	var z := 3
	while z < cells_z - 3:
		if not LandUse.is_road(tag_at(cells_x / 2, z)):
			if _rng.randf() < density:
				_stamp_row_interior(z, LandUse.ROAD)
			z += _rng.randi_range(3, 6)
		else:
			z += 1
	var x := 3
	while x < cells_x - 3:
		if not LandUse.is_road(tag_at(x, cells_z / 2)):
			if _rng.randf() < density:
				_stamp_col_interior(x, LandUse.ROAD)
			x += _rng.randi_range(3, 7)
		else:
			x += 1
	for _k in range(maxi(4, cells_x / 10)):
		var cx := _rng.randi_range(3, cells_x - 4)
		var cz := _rng.randi_range(3, cells_z - 4)
		if LandUse.is_road(tag_at(cx, cz)):
			continue
		var len_cells := _rng.randi_range(2, 5)
		if _rng.randf() < 0.5:
			for i in range(len_cells):
				if cx + i >= cells_x - 2:
					break
				if not LandUse.is_road(grid[cz][cx + i]):
					grid[cz][cx + i] = LandUse.ROAD
		else:
			for i in range(len_cells):
				if cz + i >= cells_z - 2:
					break
				if not LandUse.is_road(grid[cz + i][cx]):
					grid[cz + i][cx] = LandUse.ROAD


func _stamp_row_interior(z: int, tag: int) -> void:
	if z < 1 or z >= cells_z - 1:
		return
	for x in range(1, cells_x - 1):
		if grid[z][x] != LandUse.AVENUE:
			grid[z][x] = tag


func _stamp_col_interior(x: int, tag: int) -> void:
	if x < 1 or x >= cells_x - 1:
		return
	for z in range(1, cells_z - 1):
		if grid[z][x] != LandUse.AVENUE:
			grid[z][x] = tag


func _stamp_organic_roads() -> void:
	## Legacy single-district path (no world seams). Kept for tests.
	var z := 2 + _rng.randi() % 3
	while z < cells_z - 2:
		_stamp_row(z, LandUse.AVENUE)
		if z + 1 < cells_z - 1:
			_stamp_row(z + 1, LandUse.AVENUE)
		z += _rng.randi_range(5, 9)
	var x := 2 + _rng.randi() % 3
	while x < cells_x - 2:
		_stamp_col(x, LandUse.AVENUE)
		if x + 1 < cells_x - 1:
			_stamp_col(x + 1, LandUse.AVENUE)
		x += _rng.randi_range(6, 10)
	_stamp_organic_interior_roads()


func _stamp_row(z: int, tag: int) -> void:
	if z < 0 or z >= cells_z:
		return
	for x in range(cells_x):
		grid[z][x] = tag


func _stamp_col(x: int, tag: int) -> void:
	if x < 0 or x >= cells_x:
		return
	for z in range(cells_z):
		if grid[z][x] != LandUse.AVENUE or tag == LandUse.AVENUE:
			grid[z][x] = tag


func _stamp_grand_plaza() -> void:
	var px := cells_x / 2 - 3
	var pz := cells_z / 2 - 2
	grand_plaza = Rect2i(px, pz, 6, 5)
	grand_plaza = _clamp_rect(grand_plaza)
	_fill_rect(grand_plaza, LandUse.PLAZA, true)


## Monument squares for the four outer stones, held open before a single lot is placed.
##
## The rest of the siege is an overlay on whatever city the tile grew, and the stones tried to be too:
## they searched outward from an ideal point for open, flat, sky-clear ground. On a dense tile there is
## none — two of six sampled world seeds baked a Siege quarter with *no* stones and no gates, because
## the first stone found nowhere to stand and took the rest of the plan down with it. Clearing the
## ground up front is also the only cheap way round it: razing afterwards means slicing buildings with
## a cylinder and leaving their upper storeys hanging over an empty lot.
##
## Paved rather than planted, since a park would put trees in exactly the sky the obelisk needs, and
## three cells wide so both this and the composer's own clamp can pull toward a tile edge and still
## overlap. The composer's ideal point lands dead centre of its square by construction — its offsets
## are these, in voxels.
func _clear_siege_stone_squares() -> void:
	siege_stone_squares.clear()
	if grand_plaza.size.x <= 0 or grand_plaza.size.y <= 0:
		push_error("DistrictPlanner: a Siege tile has no grand plaza to measure stone squares from")
		assert(false, "DistrictPlanner: siege without a grand plaza")
		return
	var centre := grand_plaza.position + grand_plaza.size / 2
	var off := Vector2i(
		SiegeComposer.OUTER_RING_X / cell_size, SiegeComposer.OUTER_RING_Z / cell_size
	)
	for i in range(SiegeComposer.OUTER_STONE_COUNT):
		var sx := 1 if (i % 2) == 0 else -1
		var sz := 1 if i < 2 else -1
		var square := _open_stone_square(
			Vector2i(centre.x + sx * off.x, centre.y + sz * off.y)
		)
		_fill_rect(square, LandUse.PLAZA, true)
		siege_stone_squares.append(square)


## The square nearest `ideal_cell` with ground worth clearing. Roads are kept — a stone may not stand
## in a lane the horde walks down — and a two-cell avenue runs straight through some of these ideals,
## so the square laid on the ideal can be carriageway end to end and reserve nothing whatsoever. That
## is the shape of the bug this whole reservation exists to fix, one step further out.
func _open_stone_square(ideal_cell: Vector2i) -> Rect2i:
	var half := SIEGE_STONE_SQUARE_CELLS / 2
	var best := Rect2i()
	var best_open := -1
	for r in range(0, SIEGE_STONE_NUDGE_CELLS + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var sq := _clamp_rect(
					Rect2i(
						ideal_cell.x + dx - half,
						ideal_cell.y + dz - half,
						SIEGE_STONE_SQUARE_CELLS,
						SIEGE_STONE_SQUARE_CELLS
					)
				)
				var open_cells := _non_road_cells(sq)
				if open_cells > best_open:
					best = sq
					best_open = open_cells
		## Nearest wins: only look further out when this ring has nothing standable in it.
		if best_open >= SIEGE_STONE_MIN_OPEN:
			return best
	return best


func _non_road_cells(r: Rect2i) -> int:
	var n := 0
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or z < 0 or x >= cells_x or z >= cells_z:
				continue
			if not LandUse.is_road(grid[z][x]):
				n += 1
	return n


## Besieged ground: a square of blocks centred on the grand plaza, so the Lodestone ends up
## standing in the open square the urban pass already cleared.
##
## `_stamp_grand_plaza` is unconditional on every non-spectacle theme, so a Siege tile without
## one is a broken bake rather than a quiet variation.
func _build_siege_quarter() -> void:
	if grand_plaza.size.x <= 0 or grand_plaza.size.y <= 0:
		push_error("DistrictPlanner: a Siege tile has no grand plaza to stand the Lodestone in")
		assert(false, "DistrictPlanner: siege without a grand plaza")
		return
	var centre := grand_plaza.position + grand_plaza.size / 2
	var span_x := mini(SIEGE_QUARTER_CELLS, cells_x)
	var span_z := mini(SIEGE_QUARTER_CELLS, cells_z)
	var min_x := clampi(centre.x - span_x / 2, 0, cells_x - span_x)
	var min_z := clampi(centre.y - span_z / 2, 0, cells_z - span_z)
	siege_quarter = Rect2i(min_x, min_z, span_x, span_z)


func _stamp_satellite_plazas() -> void:
	var candidates: Array[Vector2i] = [
		Vector2i(cells_x / 5, cells_z / 4),
		Vector2i(4 * cells_x / 5, cells_z / 4),
		Vector2i(cells_x / 4, 3 * cells_z / 4),
		Vector2i(3 * cells_x / 4, 3 * cells_z / 4),
	]
	## Array.shuffle() draws from the global RNG, which made satellite plazas differ
	## between two bakes of the same tile. Shuffle from the seeded planner RNG instead.
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var count := 2 + _rng.randi() % 2
	for i in range(mini(count, candidates.size())):
		var c := candidates[i]
		var r := Rect2i(c.x - 1, c.y - 1, 3, 3)
		r = _clamp_rect(r)
		if _overlaps_open(r):
			continue
		_fill_rect(r, LandUse.PLAZA, true)
		satellite_plazas.append(r)


func _stamp_large_park() -> void:
	# Prefer one long side of the rectangle.
	var ox := 2 + _rng.randi() % maxi(1, cells_x / 4)
	var oz := 2 + _rng.randi() % maxi(1, cells_z / 5)
	if _rng.randf() < 0.5:
		ox = cells_x - ox - 8
	var r := Rect2i(ox, oz, 8, 6)
	r = _clamp_rect(r)
	if r.intersects(grand_plaza):
		r.position.x = clampi(r.position.x + 10, 1, cells_x - r.size.x - 1)
	r = _clamp_rect(r)
	_fill_rect(r, LandUse.PARK, true)
	large_park = r


func _stamp_pocket_parks() -> void:
	var tries := 0
	var target := theme.park_count + cells_x / 20
	while pocket_parks.size() < target and tries < 90:
		tries += 1
		var cx := _rng.randi_range(2, cells_x - 3)
		var cz := _rng.randi_range(2, cells_z - 3)
		if LandUse.is_road(tag_at(cx, cz)):
			continue
		if tag_at(cx, cz) == LandUse.PLAZA or tag_at(cx, cz) == LandUse.PARK:
			continue
		## Green prefers the quieter cells, but the gate opens as tries run out: a fully
		## dense tile like the downtown core used to end up with no pocket parks at all.
		if intensity_at(cx, cz) > 0.72 + 0.3 * float(tries) / 90.0:
			continue
		grid[cz][cx] = LandUse.PARK
		pocket_parks.append(Vector2i(cx, cz))


## Radius in planner cells over which the world core density falls off (~1.5 km).
const WORLD_CORE_CELLS := 55.0
## Extra density along arterials — commerce follows the big streets.
const AVENUE_INTENSITY_BONUS := 0.12


func intensity_at(cx: int, cz: int) -> float:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return 0.0
	return float(intensity[cz][cx])


func _build_intensity(district_coord: Vector2i) -> void:
	var base_cx := district_coord.x * cells_x
	var base_cz := district_coord.y * cells_z
	intensity.clear()
	intensity.resize(cells_z)
	for z in range(cells_z):
		var row: Array = []
		row.resize(cells_x)
		for x in range(cells_x):
			var wx := float(base_cx + x)
			var wz := float(base_cz + z)
			## Global downtown falloff plus two octaves of world noise: sub-centres and
			## quiet pockets appear on their own instead of one ring per tile.
			var dist := sqrt(wx * wx + wz * wz)
			var core := clampf(1.0 - dist / WORLD_CORE_CELLS, 0.0, 1.0)
			var n := _fbm2(wx * 0.045, wz * 0.045)
			row[x] = clampf(core * 0.5 + n * 0.5 + theme.intensity_bias, 0.0, 1.0)
		intensity[z] = row


func _apply_avenue_intensity_bonus() -> void:
	var boosted: Array = []
	boosted.resize(cells_z)
	for z in range(cells_z):
		var row: Array = []
		row.resize(cells_x)
		for x in range(cells_x):
			var v := float(intensity[z][x])
			if _near_avenue(x, z):
				v = clampf(v + AVENUE_INTENSITY_BONUS, 0.0, 1.0)
			row[x] = v
		boosted[z] = row
	intensity = boosted


func _near_avenue(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if tag_at(cx + dx, cz + dz) == LandUse.AVENUE:
				return true
	return false


func _assign_zones() -> void:
	_apply_avenue_intensity_bonus()
	for z in range(cells_z):
		for x in range(cells_x):
			var t: int = grid[z][x]
			if t != LandUse.LOT:
				continue
			var v := float(intensity[z][x])
			if v >= 0.72:
				grid[z][x] = LandUse.CORE_LOT
			elif v >= 0.54:
				grid[z][x] = LandUse.MID_LOT if _rng.randf() < 0.72 else LandUse.COURTYARD_LOT
			elif v >= 0.34:
				grid[z][x] = LandUse.MID_LOT if _rng.randf() < 0.4 else LandUse.TOWN_LOT
			else:
				grid[z][x] = LandUse.TOWN_LOT if _rng.randf() < 0.75 else LandUse.COURTYARD_LOT


## Deterministic value noise on world cell coordinates (independent of _rng state, so
## it cannot be shifted by unrelated changes in stamping order).
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


func _place_civic() -> void:
	var edges: Array[Vector2i] = []
	for z in range(grand_plaza.position.y - 1, grand_plaza.end.y + 1):
		for x in range(grand_plaza.position.x - 1, grand_plaza.end.x + 1):
			if x < 1 or z < 1 or x >= cells_x - 1 or z >= cells_z - 1:
				continue
			if not LandUse.is_lot(tag_at(x, z)):
				continue
			if faces_plaza(x, z):
				edges.append(Vector2i(x, z))
	if edges.is_empty():
		return
	civic_lot = edges[_rng.randi() % edges.size()]
	grid[civic_lot.y][civic_lot.x] = LandUse.CIVIC_LOT


## Reserve the one teleport chamber plot. Every normal district gets exactly one — it is the
## way off this tile, so leaving it to a dice roll would strand a district behind the J picker.
##
## Wants street frontage (the chamber needs a door) and a whole cell to itself. Landlocked
## cells are refused because the grammar turns those into parkland, which would silently drop
## the chamber for that tile.
func _place_teleport_chamber() -> void:
	var candidates: Array[Vector2i] = []
	for z in range(1, cells_z - 1):
		for x in range(1, cells_x - 1):
			var here := Vector2i(x, z)
			if here == civic_lot:
				continue
			if not LandUse.is_lot(tag_at(x, z)):
				continue
			if not _has_street_frontage(x, z):
				continue
			candidates.append(here)
	if candidates.is_empty():
		push_error("DistrictPlanner: no lot could host the teleport chamber")
		return
	teleport_lot = candidates[_rng.randi() % candidates.size()]
	grid[teleport_lot.y][teleport_lot.x] = LandUse.TELEPORT_LOT


func _has_street_frontage(cx: int, cz: int) -> bool:
	return (
		LandUse.is_road(tag_at(cx + 1, cz))
		or LandUse.is_road(tag_at(cx - 1, cz))
		or LandUse.is_road(tag_at(cx, cz + 1))
		or LandUse.is_road(tag_at(cx, cz - 1))
	)


## Parcel shapes in cells, biggest plate first. Rectangles matter: square-only packing
## stranded 40% of downtown as lone 14 m cells, and real amalgamated plots are irregular
## anyway — Manhattan's standard plot is 8×30 m and the tall ones are merged runs of those.
const PARCEL_SIZES: Array[Vector2i] = [
	Vector2i(4, 4),
	Vector2i(4, 3),
	Vector2i(3, 4),
	Vector2i(3, 3),
	Vector2i(4, 2),
	Vector2i(2, 4),
	Vector2i(3, 2),
	Vector2i(2, 3),
	Vector2i(2, 2),
]


## Merge contiguous CORE_LOT cells into 2×2 … 4×4 tower parcels (~26–56 m).
## Streets stay one cell wide; only the building footprint grows.
##
## Amalgamation is the rule downtown, not the exception: a single 14 m cell cannot carry a
## tower, and real cities got their tall buildings by merging plots for exactly that reason
## — Manhattan's average plot grew from 257 m² to 805 m², Melbourne's from 455 to 914, and
## its business blocks now average 7,500 m² plots built at only 40% land coverage.
func _place_tower_parcels() -> void:
	_reset_tower_parcels()
	if theme == null or theme.tower_chance <= 0.0:
		return
	var cap := _tower_parcel_cap()
	if cap == 0:
		return
	var occupied := PackedByteArray()
	occupied.resize(cells_x * cells_z)
	var candidates: Array[Dictionary] = []
	for z in range(cells_z):
		for x in range(cells_x):
			if tag_at(x, z) != LandUse.CORE_LOT:
				continue
			if civic_lot.x == x and civic_lot.y == z:
				continue
			for size in PARCEL_SIZES:
				var rect := Rect2i(Vector2i(x, z), size)
				if not _tower_parcel_cells_ok(rect):
					continue
				candidates.append({
					"rect": rect, "score": _tower_parcel_score(rect), "x": x, "z": z,
				})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := float(a["score"])
		var sb := float(b["score"])
		if not is_equal_approx(sa, sb):
			return sa > sb
		if int(a["z"]) != int(b["z"]):
			return int(a["z"]) < int(b["z"])
		return int(a["x"]) < int(b["x"])
	)
	for c in candidates:
		if cap > 0 and tower_parcels.size() >= cap:
			break
		var rect: Rect2i = c["rect"]
		if _tower_parcel_overlaps_occupied(rect, occupied):
			continue
		var idx := tower_parcels.size()
		tower_parcels.append(rect)
		for zz in range(rect.position.y, rect.end.y):
			for xx in range(rect.position.x, rect.end.x):
				occupied[zz * cells_x + xx] = 1
				_parcel_index[zz * cells_x + xx] = idx


func _reset_tower_parcels() -> void:
	tower_parcels.clear()
	_parcel_index.resize(cells_x * cells_z)
	_parcel_index.fill(-1)


## Maximum parcels to merge, or UNLIMITED_PARCELS to amalgamate every CORE block that fits.
const UNLIMITED_PARCELS := -1


func _tower_parcel_cap() -> int:
	match theme.id:
		DistrictTheme.CORE_HIGHRISE:
			## A downtown is made of amalgamated plots end to end; capping it left most
			## CORE cells as lone 14 m lots, which is where the needles came from.
			return UNLIMITED_PARCELS
		DistrictTheme.CIVIC_QUARTER:
			return UNLIMITED_PARCELS
		DistrictTheme.WATERFRONT_INDUSTRIAL:
			return 2
		_:
			## Occasional CORE pockets elsewhere — one landmark is enough.
			return 1 if theme.tower_chance >= 0.15 else 0


func _tower_parcel_cells_ok(rect: Rect2i) -> bool:
	if rect.position.x < 0 or rect.position.y < 0:
		return false
	if rect.end.x > cells_x or rect.end.y > cells_z:
		return false
	## An amalgamated plot has to front a street — a landlocked parcel is block courtyard
	## and gets no building, which would leave a hole the size of the whole parcel.
	if not _rect_touches_road(rect):
		return false
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if tag_at(x, z) != LandUse.CORE_LOT:
				return false
			if civic_lot.x == x and civic_lot.y == z:
				return false
	return true


## Intensity summed over the cells: it favours the denser spots and, because it grows with
## cell count, the bigger plate wherever one fits.
func _tower_parcel_score(rect: Rect2i) -> float:
	var sum := 0.0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			sum += intensity_at(x, z)
	return sum


func _tower_parcel_overlaps_occupied(rect: Rect2i, occupied: PackedByteArray) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if occupied[z * cells_x + x] != 0:
				return true
	return false


func _rect_touches_road(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if is_corner_lot(x, z) or _cell_touches_road(x, z):
				return true
	return false


func _cell_touches_road(cx: int, cz: int) -> bool:
	return (
		LandUse.is_road(tag_at(cx + 1, cz))
		or LandUse.is_road(tag_at(cx - 1, cz))
		or LandUse.is_road(tag_at(cx, cz + 1))
		or LandUse.is_road(tag_at(cx, cz - 1))
	)


## Parcel covering (cx, cz), or empty Rect2i if the cell is not in a tower parcel.
func tower_parcel_at(cx: int, cz: int) -> Rect2i:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return Rect2i()
	var idx := _parcel_index[cz * cells_x + cx]
	return Rect2i() if idx < 0 else tower_parcels[idx]


func is_tower_parcel_anchor(cx: int, cz: int) -> bool:
	var rect := tower_parcel_at(cx, cz)
	if rect.size.x <= 0:
		return false
	return rect.position.x == cx and rect.position.y == cz


func is_tower_parcel_secondary(cx: int, cz: int) -> bool:
	var rect := tower_parcel_at(cx, cz)
	if rect.size.x <= 0:
		return false
	return rect.position.x != cx or rect.position.y != cz


## Street façade for a multi-cell parcel (0=+Z … 3=-X), preferring road-touching sides.
func street_facing_rect(rect: Rect2i) -> int:
	if rect.size.x <= 0:
		return _rng.randi() % 4
	var scores := [0, 0, 0, 0]
	for x in range(rect.position.x, rect.end.x):
		if LandUse.is_road(tag_at(x, rect.end.y)):
			scores[0] += 1
		if LandUse.is_road(tag_at(x, rect.position.y - 1)):
			scores[1] += 1
	for z in range(rect.position.y, rect.end.y):
		if LandUse.is_road(tag_at(rect.end.x, z)):
			scores[2] += 1
		if LandUse.is_road(tag_at(rect.position.x - 1, z)):
			scores[3] += 1
	var best := 0
	for i in range(1, 4):
		if scores[i] > scores[best]:
			best = i
	if scores[best] > 0:
		return best
	## Same rule as the single-cell case: an open side, never a party wall.
	for side in range(4):
		if rect_side_open(rect, side):
			return side
	return street_facing(rect.position.x, rect.position.y)


func is_corner_parcel(rect: Rect2i) -> bool:
	var sides := 0
	for x in range(rect.position.x, rect.end.x):
		if LandUse.is_road(tag_at(x, rect.end.y)):
			sides |= 1
		if LandUse.is_road(tag_at(x, rect.position.y - 1)):
			sides |= 2
	for z in range(rect.position.y, rect.end.y):
		if LandUse.is_road(tag_at(rect.end.x, z)):
			sides |= 4
		if LandUse.is_road(tag_at(rect.position.x - 1, z)):
			sides |= 8
	var n := 0
	for bit in [1, 2, 4, 8]:
		if (sides & bit) != 0:
			n += 1
	return n >= 2


func faces_plaza_rect(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if faces_plaza(x, z):
				return true
	return false


func faces_park_rect(rect: Rect2i) -> bool:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if faces_park(x, z):
				return true
	return false


## True when this side of `rect` faces anything other than more buildable lot — a street,
## a plaza, a park or the district edge. Open sides carry the sidewalk setback; lot-to-lot
## sides do not, so neighbours meet in a party wall and the block reads as one mass.
## Sides are the `street_facing` convention: 0=+Z, 1=-Z, 2=+X, 3=-X.
func rect_side_open(rect: Rect2i, side: int) -> bool:
	match side:
		0:
			for x in range(rect.position.x, rect.end.x):
				if not LandUse.is_lot(tag_at(x, rect.end.y)):
					return true
		1:
			for x in range(rect.position.x, rect.end.x):
				if not LandUse.is_lot(tag_at(x, rect.position.y - 1)):
					return true
		2:
			for z in range(rect.position.y, rect.end.y):
				if not LandUse.is_lot(tag_at(rect.end.x, z)):
					return true
		3:
			for z in range(rect.position.y, rect.end.y):
				if not LandUse.is_lot(tag_at(rect.position.x - 1, z)):
					return true
		_:
			push_error("DistrictPlanner.rect_side_open: side %d out of range" % side)
	return false


## Lot with no street, plaza or park on any side. Real perimeter blocks leave these as
## courtyard: there is no frontage to put a door on, and `street_facing` would fall back
## to a random direction and hang the front door against a neighbour's blank wall.
func rect_is_landlocked(rect: Rect2i) -> bool:
	for side in range(4):
		if rect_side_open(rect, side):
			return false
	return true


func intensity_max_in_rect(rect: Rect2i) -> float:
	var best := 0.0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			best = maxf(best, intensity_at(x, z))
	return best


func _collect_avenue_lights() -> void:
	for z in range(cells_z):
		for x in range(cells_x):
			if tag_at(x, z) != LandUse.AVENUE:
				continue
			if (x + z) % 2 != 0:
				continue
			avenue_light_cells.append(Vector2i(x, z))


func _fill_rect(r: Rect2i, tag: int, skip_roads: bool) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or z < 0 or x >= cells_x or z >= cells_z:
				continue
			if skip_roads and LandUse.is_road(grid[z][x]):
				continue
			grid[z][x] = tag


func _clamp_rect(r: Rect2i) -> Rect2i:
	var x := clampi(r.position.x, 1, cells_x - 2)
	var z := clampi(r.position.y, 1, cells_z - 2)
	var w := mini(r.size.x, cells_x - 1 - x)
	var h := mini(r.size.y, cells_z - 1 - z)
	return Rect2i(x, z, maxi(1, w), maxi(1, h))


func _overlaps_open(r: Rect2i) -> bool:
	if r.intersects(grand_plaza):
		return true
	for s in satellite_plazas:
		if r.intersects(s):
			return true
	if large_park.size.x > 0 and r.intersects(large_park):
		return true
	return false
