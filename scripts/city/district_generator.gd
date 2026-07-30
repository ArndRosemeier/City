## Procedural district: planner → plazas/parks → building grammars → brush (live or offline).
class_name DistrictGenerator
extends RefCounted

const StreetTopologyScript := preload("res://scripts/city/street_topology.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const PlazaComposerScript := preload("res://scripts/city/plaza_composer.gd")
const ParkComposerScript := preload("res://scripts/city/park_composer.gd")
const HillComposerScript := preload("res://scripts/city/hill_composer.gd")
const GraveyardComposerScript := preload("res://scripts/city/graveyard_composer.gd")
const LakeComposerScript := preload("res://scripts/city/lake_composer.gd")
const CastleComposerScript := preload("res://scripts/city/castle_composer.gd")
const FractalComposerScript := preload("res://scripts/city/fractal_composer.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CastleDoorwayScript := preload("res://scripts/city/castle_doorway.gd")
const ElevatorShaftScript := preload("res://scripts/city/elevator_shaft.gd")

@export var city_seed: int = 42
## Rectangular district in voxels (0.5 m each). Default 784×560 → 392×280 m.
@export var size_x: int = 784
@export var size_z: int = 560
## Kept for older callers; equals max(size_x, size_z).
@export var size_xz: int = 784
## Indestructible world floor band [0, bedrock_thickness).
@export var bedrock_thickness: int = 1
## Diggable STONE under the street deck (between bedrock and surface).
@export var stone_depth: int = 5
## Surface voxel Y (sidewalk / road / park). Equals bedrock_thickness + stone_depth.
@export var ground_thickness: int = 6
## 200 voxels * 0.5 m = 100 m ceiling.
@export var max_building_height_vox: int = 200
## Typical residential floor-to-floor ≈ 3.0 m.
@export var floor_height_vox: int = 6
@export var voxel_size: float = 0.5
## Planner cell ≈ 14 m — street ROW / single lot. CORE towers merge 2×2–4×4 cells.
@export var cell_size: int = 28

## Real massing limits, from how actual cities size tall buildings.
##
## Floor plate: an occupiable tower runs 500–700 m² (economy residential) up to
## 1,500–2,500 m² (prime office). Core-to-glass is capped at 12–15 m for daylight, so
## a tower needs ~24 m across before a core plus usable depth fits at all — below that
## the core alone (20–28% of the plate) eats the floor. A single 12 m lot is 144 m²:
## row-house scale, never a tower.
const MIN_TOWER_PLATE_M2 := 600.0
const MIN_TOWER_SIDE_M := 24.0
## Slenderness λ = height ÷ shortest base side. Structural optimum is 5–7; both original
## WTC towers sat at 7 and needed 20,000 dampers to stay comfortable. λ ≥ 10 is the
## super-slender luxury outlier (432 Park is 15, Steinway Tower 24). The grammar insets
## tower shafts to ~80% of the lot, so a lot-relative 5 keeps the built shaft inside 7.
const MAX_SLENDERNESS := 5.0
## Lots too small for a tower become perimeter-block fabric: Barcelona's Eixample caps
## block height at 22 m over 140–450 m² plots.
const FABRIC_HEIGHT_M := 26.0

## District personality. DistrictBakeJob sets it from the world seed + coord; the
## one-shot generate() path derives it in _setup_composers().
var theme: DistrictTheme = null

var _rng := RandomNumberGenerator.new()
var _brush: CityBrush
var _planner: DistrictPlanner
var _plaza: PlazaComposer
var _park: ParkComposer
var _hill: HillComposer
var _graveyard: GraveyardComposer
var _lake: LakeComposer
var _castle: CastleComposer
var _fractal: FractalComposer
## Survives end_generate so DistrictInstance can spawn MandelbrotArena.
var _fractal_world_bounds: Dictionary = {}
var _grammar: BuildingGrammar
## World-space building massing for far LOD: {shape, center, size, yaw, color, custom}.
var building_impostors: Array = []
## Per-lot interiors for the JIT decorator, keyed by district cell (Vector2i) so a foot
## position resolves to its building in one lookup. Merged parcels register every cell
## they cover, so all keys of one parcel point at the same BuildingInterior.
var interior_buildings: Dictionary = {}
## City lot street doors (CastleDoorway, world voxel coords).
var lot_doorways: Array = []
## Multi-storey lot elevator cabins (ElevatorShaft, world voxel coords).
var elevator_shafts: Array = []
## Hill gem ore (world voxel coords + material ids) collected during compose.
var _hill_gem_positions: PackedVector3Array = PackedVector3Array()
var _hill_gem_mats: PackedInt32Array = PackedInt32Array()
## Castle plan from the compose pass; outlives the composer so the bake can hand it on.
var _castle_layout: CastleLayout = null
## World voxel origin of this district tile (local paint stays 0..size).
var origin_vox: Vector3i = Vector3i.ZERO
var district_coord: Vector2i = Vector2i.ZERO


func generate(tool: VoxelTool, seed_value: int = -1, p_origin: Vector3i = Vector3i.ZERO, p_coord: Vector2i = Vector2i.ZERO) -> void:
	## One-shot stamp — requires the district AABB to already be editable.
	begin_generate(tool, seed_value, p_origin, p_coord)
	paint_tile(0, 0, size_x, size_z)
	decorate_open_spaces()
	end_generate()


func begin_generate(
	tool: VoxelTool,
	seed_value: int = -1,
	p_origin: Vector3i = Vector3i.ZERO,
	p_coord: Vector2i = Vector2i.ZERO
) -> void:
	origin_vox = p_origin
	district_coord = p_coord
	## `seed_value` is the per-district seed (DistrictCoord.district_seed(world, coord)).
	if seed_value >= 0:
		city_seed = seed_value
	_rng.seed = city_seed
	size_xz = maxi(size_x, size_z)
	ground_thickness = bedrock_thickness + stone_depth
	building_impostors.clear()
	interior_buildings.clear()
	lot_doorways.clear()
	elevator_shafts.clear()
	_brush = CityBrushScript.new(tool, origin_vox)
	_setup_composers()


func begin_generate_offline(
	seed_value: int,
	p_origin: Vector3i,
	p_coord: Vector2i
) -> void:
	## Thread-safe path: paint into a NativeOfflineVoxelVolume (no VoxelTool).
	origin_vox = p_origin
	district_coord = p_coord
	city_seed = seed_value
	_rng.seed = city_seed
	size_xz = maxi(size_x, size_z)
	ground_thickness = bedrock_thickness + stone_depth
	building_impostors.clear()
	interior_buildings.clear()
	lot_doorways.clear()
	elevator_shafts.clear()
	_brush = CityBrushScript.new(null, Vector3i.ZERO)
	_brush.use_offline_volume()
	_setup_composers()


func get_offline_volume():
	## Returns NativeOfflineVoxelVolume when baking off-thread; otherwise null.
	if _brush == null:
		return null
	return _brush.volume


## The castle plan in *district-local* voxel coords, or null outside Castle districts.
## Survives end_generate() so a finished bake can still be asked what it built.
func get_castle_layout() -> CastleLayout:
	return _castle_layout


## World-voxel gem ore placed by the hill compose pass (empty outside Hill districts).
func get_hill_gems() -> Dictionary:
	var positions := PackedVector3Array()
	positions.resize(_hill_gem_positions.size())
	for i in range(_hill_gem_positions.size()):
		var p := _hill_gem_positions[i]
		positions[i] = Vector3(
			p.x + float(origin_vox.x),
			p.y + float(origin_vox.y),
			p.z + float(origin_vox.z)
		)
	return {"positions": positions, "mats": _hill_gem_mats.duplicate()}


func _setup_composers() -> void:
	if theme == null:
		## Standalone path (tools, single-district tests): derive from the district seed.
		theme = DistrictTheme.for_district(city_seed, district_coord)

	_planner = DistrictPlannerScript.new()
	_planner.theme = theme
	_planner.build(size_x, size_z, city_seed, cell_size, district_coord)

	_plaza = PlazaComposerScript.new()
	_plaza.brush = _brush
	_plaza.rng = _rng
	_plaza.ground_y = ground_thickness
	_plaza.pave_mat = theme.plaza_mat
	_plaza.pave_inner_mat = theme.plaza_inner_mat

	_park = ParkComposerScript.new()
	_park.brush = _brush
	_park.rng = _rng
	_park.ground_y = ground_thickness

	_hill = HillComposerScript.new()
	_hill.brush = _brush
	_hill.rng = _rng
	_hill.ground_y = ground_thickness
	_hill.planner = _planner
	_hill.cell_size = cell_size
	## Cleared each begin; filled by HillComposer.compose().
	_hill_gem_positions = PackedVector3Array()
	_hill_gem_mats = PackedInt32Array()

	_graveyard = GraveyardComposerScript.new()
	_graveyard.brush = _brush
	_graveyard.rng = _rng
	_graveyard.ground_y = ground_thickness
	_graveyard.planner = _planner
	_graveyard.cell_size = cell_size

	_lake = LakeComposerScript.new()
	_lake.brush = _brush
	_lake.rng = _rng
	_lake.ground_y = ground_thickness
	_lake.planner = _planner
	_lake.cell_size = cell_size

	_castle = CastleComposerScript.new()
	_castle.brush = _brush
	_castle.rng = _rng
	_castle.ground_y = ground_thickness
	_castle.planner = _planner
	_castle.cell_size = cell_size
	_castle_layout = null

	_fractal = FractalComposerScript.new()
	_fractal.brush = _brush
	_fractal.rng = _rng
	_fractal.ground_y = ground_thickness
	_fractal.planner = _planner
	_fractal.cell_size = cell_size

	_grammar = BuildingGrammarScript.new()
	_grammar.brush = _brush
	_grammar.rng = _rng
	_grammar.theme = theme
	_grammar.floor_height = maxi(floor_height_vox, 6)
	_grammar.ground_floor_height = 8  # ~4.0 m retail / lobby
	_grammar.max_height = max_building_height_vox
	_grammar.min_tower_side_vox = int(round(MIN_TOWER_SIDE_M / voxel_size))
	_grammar.min_tower_plate_vox2 = int(round(MIN_TOWER_PLATE_M2 / (voxel_size * voxel_size)))
	_grammar.park = _park


func _reseed_cell(cx: int, cz: int) -> void:
	## Order-independent randomness — same cell always gets the same rolls.
	_rng.seed = DistrictCoord.cell_seed(city_seed, cx, cz)


func paint_tile(min_x: int, min_z: int, max_x: int, max_z: int) -> void:
	## Clear + paint planner cells whose origins lie inside [min,max). Tile bounds must be editable.
	## Multi-cell plaza/park *decoration* is deferred to decorate_open_spaces().
	if _brush == null or _planner == null:
		push_error("DistrictGenerator.paint_tile: call begin_generate() first")
		return
	min_x = clampi(min_x, 0, size_x)
	max_x = clampi(max_x, 0, size_x)
	min_z = clampi(min_z, 0, size_z)
	max_z = clampi(max_z, 0, size_z)
	if max_x <= min_x or max_z <= min_z:
		return
	var cx0 := min_x / cell_size
	var cz0 := min_z / cell_size
	var cx1 := (max_x - 1) / cell_size
	var cz1 := (max_z - 1) / cell_size
	paint_district_ground_slab()
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			paint_cell_ground(cx, cz)
	for cz2 in range(cz0, cz1 + 1):
		for cx2 in range(cx0, cx1 + 1):
			paint_cell_structures(cx2, cz2)


func paint_cell(cx: int, cz: int) -> void:
	## Full cell (ground + structures). Prefer the split APIs when streaming.
	## Do not blanket-fill AIR — that materializes empty sky into the voxel stream.
	if _brush == null or _planner == null:
		return
	if cx < 0 or cz < 0 or cx >= _planner.cells_x or cz >= _planner.cells_z:
		return
	_paint_substrate(
		Vector3i(cx * cell_size, 0, cz * cell_size),
		Vector3i((cx + 1) * cell_size, 0, (cz + 1) * cell_size)
	)
	_brush.fill_box(
		Vector3i(cx * cell_size, ground_thickness, cz * cell_size),
		Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size),
		VoxelMaterial.SIDEWALK
	)
	paint_cell_ground(cx, cz)
	paint_cell_structures(cx, cz)


func paint_district_ground_slab() -> void:
	## One-shot walkable slab for the whole tile — avoids cell-by-cell air holes.
	## Stack: BEDROCK (1) + diggable STONE (stone_depth) + surface deck at ground_thickness.
	if _brush == null:
		return
	_paint_substrate(Vector3i(0, 0, 0), Vector3i(size_x, 0, size_z))
	_brush.fill_box(
		Vector3i(0, ground_thickness, 0),
		Vector3i(size_x, ground_thickness + 1, size_z),
		VoxelMaterial.SIDEWALK
	)


## Bedrock floor + diggable stone fill. `min_v`/`max_v` supply XZ; Y is owned by the stack.
func _paint_substrate(min_v: Vector3i, max_v: Vector3i) -> void:
	var bed_top := maxi(bedrock_thickness, 1)
	var stone_top := bed_top + maxi(stone_depth, 0)
	_brush.fill_box(
		Vector3i(min_v.x, 0, min_v.z),
		Vector3i(max_v.x, bed_top, max_v.z),
		VoxelMaterial.BEDROCK
	)
	if stone_top > bed_top:
		_brush.fill_box(
			Vector3i(min_v.x, bed_top, min_v.z),
			Vector3i(max_v.x, stone_top, max_v.z),
			VoxelMaterial.STONE
		)


func paint_cell_ground(cx: int, cz: int) -> void:
	## Surface materials only (streets / plaza / park). Assumes substrate+sidewalk slab exists.
	if _brush == null or _planner == null:
		return
	if cx < 0 or cz < 0 or cx >= _planner.cells_x or cz >= _planner.cells_z:
		return
	_reseed_cell(cx, cz)
	var tag := _planner.tag_at(cx, cz)
	var smin := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
	var smax := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
	match tag:
		LandUse.AVENUE:
			_paint_street_cell(smin, smax, cx, cz, true)
		LandUse.ROAD:
			_paint_street_cell(smin, smax, cx, cz, false)
		LandUse.PLAZA:
			_brush.fill_box(smin, smax, theme.plaza_mat)
		LandUse.PARK, LandUse.HILL, LandUse.LAKE, LandUse.CASTLE:
			## Lake tiles start as meadow; LakeComposer carves the basin into it. Castle
			## tiles keep the meadow as the open field the fortress stands in.
			_brush.fill_box(smin, smax, VoxelMaterial.PARK)
		LandUse.FRACTAL:
			## Meadow verge; FractalComposer stamps the centered glowing square.
			_brush.fill_box(smin, smax, VoxelMaterial.PARK)
		LandUse.GRAVEYARD:
			## Consecrated ground is turned earth, never lawn — park green under the
			## composer's mound leaks through every verge it does not overwrite.
			_brush.fill_box(smin, smax, VoxelMaterial.GRAVE_SOIL)
		_:
			pass  ## Sidewalk already from slab.


func paint_cell_structures(cx: int, cz: int) -> void:
	## Buildings / vertical detail. Ground slab is left intact.
	## Never AIR-fill the sky column — AirGenerator already provides empty space, and
	## writing AIR would allocate sparse blocks for nothing (huge RAM cost).
	if _brush == null or _planner == null:
		return
	if cx < 0 or cz < 0 or cx >= _planner.cells_x or cz >= _planner.cells_z:
		return
	## Secondary cells of a multi-cell tower parcel only carry sidewalk from the slab —
	## the anchor paints the whole building.
	if _planner.is_tower_parcel_secondary(cx, cz):
		return
	_reseed_cell(cx, cz)
	var tag := _planner.tag_at(cx, cz)
	var bounds := _lot_paint_bounds(cx, cz)
	var smin: Vector3i = bounds[0]
	var smax: Vector3i = bounds[1]
	match tag:
		LandUse.AVENUE, LandUse.ROAD:
			pass  ## Surface already complete.
		LandUse.PLAZA, LandUse.PARK, LandUse.HILL, LandUse.GRAVEYARD, LandUse.LAKE, LandUse.CASTLE, LandUse.FRACTAL:
			pass  ## Fancy open-space decorate runs after all cells.
		_:
			_paint_lot(smin, smax, cx, cz, tag, _grammar)


func paint_cell_impostor_only(cx: int, cz: int) -> void:
	## Far-LOD: record building massing boxes without voxel shells.
	if _planner == null:
		return
	if cx < 0 or cz < 0 or cx >= _planner.cells_x or cz >= _planner.cells_z:
		return
	if _planner.is_tower_parcel_secondary(cx, cz):
		return
	var tag := _planner.tag_at(cx, cz)
	match tag:
		LandUse.AVENUE, LandUse.ROAD, LandUse.PLAZA, LandUse.PARK, LandUse.HILL, LandUse.GRAVEYARD, LandUse.LAKE, LandUse.CASTLE, LandUse.FRACTAL:
			return
		_:
			pass
	if _planner.rect_is_landlocked(_lot_rect(cx, cz)):
		return
	var bounds := _lot_paint_bounds(cx, cz)
	var inner := _buildable_bounds(bounds[0], bounds[1], cx, cz)
	var bmin: Vector3i = inner[0]
	var bmax: Vector3i = inner[1]
	if bmax.x - bmin.x < 6 or bmax.z - bmin.z < 6:
		return
	var mass_h := 48
	match tag:
		LandUse.CORE_LOT:
			mass_h = max_building_height_vox
		LandUse.CIVIC_LOT:
			mass_h = mini(max_building_height_vox, 48)
		LandUse.MID_LOT:
			mass_h = 66
		LandUse.TOWN_LOT:
			mass_h = 28
		LandUse.COURTYARD_LOT:
			mass_h = 40
		_:
			mass_h = 48
	## Same ground-area limit the near grammar obeys, or the far skyline keeps the needles.
	mass_h = mini(mass_h, _footprint_height_cap(bmin, bmax))
	## Far tiles deliberately skip the grammar, so there is no real massing to describe —
	## one coarse block per lot (or one block per multi-cell tower parcel).
	_record_building_impostor(
		[{
			"shape": int(BuildingGrammar.ImpostorShape.BOX),
			"center": Vector3(
				float(bmin.x + bmax.x) * 0.5,
				float(bmin.y) + float(mass_h) * 0.5,
				float(bmin.z + bmax.z) * 0.5
			),
			"size": Vector3(float(bmax.x - bmin.x), float(mass_h), float(bmax.z - bmin.z)),
			"yaw": 0.0,
		}] as Array[Dictionary],
		tag
	)


## World-voxel AABB for painting a lot cell. Tower parcel anchors span the full rect.
func _lot_paint_bounds(cx: int, cz: int) -> Array[Vector3i]:
	var parcel := _planner.tower_parcel_at(cx, cz)
	if parcel.size.x > 0 and _planner.is_tower_parcel_anchor(cx, cz):
		return [
			Vector3i(parcel.position.x * cell_size, ground_thickness, parcel.position.y * cell_size),
			Vector3i(parcel.end.x * cell_size, ground_thickness + 1, parcel.end.y * cell_size),
		] as Array[Vector3i]
	return [
		Vector3i(cx * cell_size, ground_thickness, cz * cell_size),
		Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size),
	] as Array[Vector3i]


## The planner cell or parcel a lot cell builds on.
func _lot_rect(cx: int, cz: int) -> Rect2i:
	var parcel := _planner.tower_parcel_at(cx, cz)
	return parcel if parcel.size.x > 0 else Rect2i(cx, cz, 1, 1)


## Buildable AABB inside a painted lot: sidewalk setback only on sides that face a street,
## plaza or park. Lot-to-lot sides build to the cell edge so neighbours share a party wall.
func _buildable_bounds(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int) -> Array[Vector3i]:
	var ring := 1 if cell_size < 20 else 2
	var rect := _lot_rect(cx, cz)
	return [
		min_v
		+ Vector3i(
			ring if _planner.rect_side_open(rect, 3) else 0,
			0,
			ring if _planner.rect_side_open(rect, 1) else 0
		),
		max_v
		- Vector3i(
			ring if _planner.rect_side_open(rect, 2) else 0,
			0,
			ring if _planner.rect_side_open(rect, 0) else 0
		),
	] as Array[Vector3i]


func decorate_open_spaces() -> void:
	## Fancy plaza/park/hill pass — call only once the full feature AABBs are editable.
	if (
		_brush == null or _planner == null or _plaza == null or _park == null
		or _hill == null or _graveyard == null or _lake == null or _castle == null
		or _fractal == null
	):
		return
	var lf := _planner.large_fractal
	if lf.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 7)
		var fmin := Vector3i(
			lf.position.x * cell_size, ground_thickness, lf.position.y * cell_size
		)
		var fmax := Vector3i(
			lf.end.x * cell_size, ground_thickness + 1, lf.end.y * cell_size
		)
		_fractal.compose(fmin, fmax)
		_fractal_world_bounds = _compute_fractal_glow_world_bounds()
		return
	var lc := _planner.large_castle
	if lc.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 6)
		var cmin := Vector3i(
			lc.position.x * cell_size, ground_thickness, lc.position.y * cell_size
		)
		var cmax := Vector3i(
			lc.end.x * cell_size, ground_thickness + 1, lc.end.y * cell_size
		)
		_castle.compose(cmin, cmax)
		_castle_layout = _castle.layout
		return
	var ll := _planner.large_lake
	if ll.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 5)
		var lmin := Vector3i(
			ll.position.x * cell_size, ground_thickness, ll.position.y * cell_size
		)
		var lmax := Vector3i(
			ll.end.x * cell_size, ground_thickness + 1, ll.end.y * cell_size
		)
		_lake.compose(lmin, lmax)
		return
	var lh := _planner.large_hill
	if lh.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 3)
		var hmin := Vector3i(lh.position.x * cell_size, ground_thickness, lh.position.y * cell_size)
		var hmax := Vector3i(lh.end.x * cell_size, ground_thickness + 1, lh.end.y * cell_size)
		_hill.compose(hmin, hmax)
		_hill_gem_positions = _hill.gem_positions.duplicate()
		_hill_gem_mats = _hill.gem_mats.duplicate()
		return
	var lg := _planner.large_graveyard
	if lg.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 4)
		var gmin_gy := Vector3i(
			lg.position.x * cell_size, ground_thickness, lg.position.y * cell_size
		)
		var gmax_gy := Vector3i(
			lg.end.x * cell_size, ground_thickness + 1, lg.end.y * cell_size
		)
		_graveyard.compose(gmin_gy, gmax_gy)
		return
	var g := _planner.grand_plaza
	if g.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 1)
		var gmin := Vector3i(g.position.x * cell_size, ground_thickness, g.position.y * cell_size)
		var gmax := Vector3i(g.end.x * cell_size, ground_thickness + 1, g.end.y * cell_size)
		_plaza.compose_grand(gmin, gmax)
	var sat_i := 0
	for s in _planner.satellite_plazas:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 100 + sat_i)
		sat_i += 1
		var smin := Vector3i(s.position.x * cell_size, ground_thickness, s.position.y * cell_size)
		var smax := Vector3i(s.end.x * cell_size, ground_thickness + 1, s.end.y * cell_size)
		_plaza.compose_satellite(smin, smax)
	var lp := _planner.large_park
	if lp.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 2)
		var pmin := Vector3i(lp.position.x * cell_size, ground_thickness, lp.position.y * cell_size)
		var pmax := Vector3i(lp.end.x * cell_size, ground_thickness + 1, lp.end.y * cell_size)
		_park.compose_large(pmin, pmax)
	## Pocket parks: the streamed path never called _paint_park_cell, so every square
	## outside the large park stayed an empty lawn rectangle.
	var pocket_i := 0
	for p in _planner.pocket_parks:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 200 + pocket_i)
		pocket_i += 1
		var qmin := Vector3i(p.x * cell_size, ground_thickness, p.y * cell_size)
		var qmax := Vector3i((p.x + 1) * cell_size, ground_thickness + 1, (p.y + 1) * cell_size)
		_park.compose_pocket(qmin, qmax)


func decorate_open_spaces_far() -> void:
	## Sparse trees / benches so distant greens aren't empty until upgrade.
	if (
		_brush == null or _planner == null or _plaza == null or _park == null
		or _hill == null or _graveyard == null or _lake == null or _castle == null
		or _fractal == null
	):
		return
	var lf := _planner.large_fractal
	if lf.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 37)
		var fmin := Vector3i(
			lf.position.x * cell_size, ground_thickness, lf.position.y * cell_size
		)
		var fmax := Vector3i(
			lf.end.x * cell_size, ground_thickness + 1, lf.end.y * cell_size
		)
		_fractal.compose_far_sparse(fmin, fmax)
		_fractal_world_bounds = _compute_fractal_glow_world_bounds()
		return
	var lc := _planner.large_castle
	if lc.size.x > 0:
		## Same feature seed as the near pass on purpose: the castle *is* the landmark of
		## its quarter, so the distant silhouette has to be the fortress the player will
		## walk up to, not a differently-planned one that swaps out on approach.
		_rng.seed = DistrictCoord.feature_seed(city_seed, 6)
		var cmin := Vector3i(
			lc.position.x * cell_size, ground_thickness, lc.position.y * cell_size
		)
		var cmax := Vector3i(
			lc.end.x * cell_size, ground_thickness + 1, lc.end.y * cell_size
		)
		_castle.compose_far_sparse(cmin, cmax)
		_castle_layout = _castle.layout
		return
	var ll := _planner.large_lake
	if ll.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 35)
		var lmin := Vector3i(
			ll.position.x * cell_size, ground_thickness, ll.position.y * cell_size
		)
		var lmax := Vector3i(
			ll.end.x * cell_size, ground_thickness + 1, ll.end.y * cell_size
		)
		_lake.compose_far_sparse(lmin, lmax)
		return
	var lh := _planner.large_hill
	if lh.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 33)
		var hmin := Vector3i(lh.position.x * cell_size, ground_thickness, lh.position.y * cell_size)
		var hmax := Vector3i(lh.end.x * cell_size, ground_thickness + 1, lh.end.y * cell_size)
		_hill.compose_far_sparse(hmin, hmax)
		return
	var lg := _planner.large_graveyard
	if lg.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 34)
		var gmin_gy := Vector3i(
			lg.position.x * cell_size, ground_thickness, lg.position.y * cell_size
		)
		var gmax_gy := Vector3i(
			lg.end.x * cell_size, ground_thickness + 1, lg.end.y * cell_size
		)
		_graveyard.compose_far_sparse(gmin_gy, gmax_gy)
		return
	var g := _planner.grand_plaza
	if g.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 31)
		var gmin := Vector3i(g.position.x * cell_size, ground_thickness, g.position.y * cell_size)
		var gmax := Vector3i(g.end.x * cell_size, ground_thickness + 1, g.end.y * cell_size)
		_plaza.compose_far_sparse(gmin, gmax)
	var sat_i := 0
	for s in _planner.satellite_plazas:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 130 + sat_i)
		sat_i += 1
		var smin := Vector3i(s.position.x * cell_size, ground_thickness, s.position.y * cell_size)
		var smax := Vector3i(s.end.x * cell_size, ground_thickness + 1, s.end.y * cell_size)
		_plaza.compose_far_sparse(smin, smax)
	var lp := _planner.large_park
	if lp.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 32)
		var pmin := Vector3i(lp.position.x * cell_size, ground_thickness, lp.position.y * cell_size)
		var pmax := Vector3i(lp.end.x * cell_size, ground_thickness + 1, lp.end.y * cell_size)
		_park.compose_far_sparse(pmin, pmax)
	var pocket_i := 0
	for p in _planner.pocket_parks:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 230 + pocket_i)
		pocket_i += 1
		var qmin := Vector3i(p.x * cell_size, ground_thickness, p.y * cell_size)
		var qmax := Vector3i((p.x + 1) * cell_size, ground_thickness + 1, (p.y + 1) * cell_size)
		_park.compose_far_sparse(qmin, qmax)


func open_space_bounds() -> Array[AABB]:
	## World voxel-space AABBs that decorate_open_spaces() will write.
	var out: Array[AABB] = []
	if _planner == null:
		return out
	var y0 := float(ground_thickness)
	var yh := 12.0
	var ox := float(origin_vox.x)
	var oz := float(origin_vox.z)
	var lf := _planner.large_fractal
	if lf.size.x > 0:
		out.append(
			AABB(
				Vector3(ox + lf.position.x * cell_size, y0, oz + lf.position.y * cell_size),
				Vector3(lf.size.x * cell_size, 20.0, lf.size.y * cell_size)
			)
		)
		return out
	var lc := _planner.large_castle
	if lc.size.x > 0:
		## Plinth, curtain, towers and keep — the causeway stays inside the same reserve, so
		## one box covers the whole fortress. The keep is the tallest of them: an 18-voxel
		## plinth, five storeys at nine voxels each and a corner turret over that, so the box
		## has to reach as high as the hill sculpt's does.
		out.append(
			AABB(
				Vector3(ox + lc.position.x * cell_size, y0, oz + lc.position.y * cell_size),
				Vector3(lc.size.x * cell_size, 90.0, lc.size.y * cell_size)
			)
		)
		return out
	var ll := _planner.large_lake
	if ll.size.x > 0:
		## The basin is carved *below* the deck, so the region has to start at the
		## world floor — trees on the islands set the top.
		out.append(
			AABB(
				Vector3(ox + ll.position.x * cell_size, 0.0, oz + ll.position.y * cell_size),
				Vector3(ll.size.x * cell_size, y0 + 30.0, ll.size.y * cell_size)
			)
		)
		return out
	var lh := _planner.large_hill
	if lh.size.x > 0:
		## Hills reach ~40 m; bounds must cover the full sculpt volume.
		out.append(
			AABB(
				Vector3(ox + lh.position.x * cell_size, y0, oz + lh.position.y * cell_size),
				Vector3(lh.size.x * cell_size, 90.0, lh.size.y * cell_size)
			)
		)
		return out
	var lg := _planner.large_graveyard
	if lg.size.x > 0:
		## Elevated yard + chapel steeple + catacombs in the fill.
		out.append(
			AABB(
				Vector3(ox + lg.position.x * cell_size, y0, oz + lg.position.y * cell_size),
				Vector3(lg.size.x * cell_size, 40.0, lg.size.y * cell_size)
			)
		)
		return out
	var g := _planner.grand_plaza
	if g.size.x > 0:
		out.append(
			AABB(
				Vector3(ox + g.position.x * cell_size, y0, oz + g.position.y * cell_size),
				Vector3(g.size.x * cell_size, yh, g.size.y * cell_size)
			)
		)
	for s in _planner.satellite_plazas:
		out.append(
			AABB(
				Vector3(ox + s.position.x * cell_size, y0, oz + s.position.y * cell_size),
				Vector3(s.size.x * cell_size, yh, s.size.y * cell_size)
			)
		)
	var lp := _planner.large_park
	if lp.size.x > 0:
		out.append(
			AABB(
				Vector3(ox + lp.position.x * cell_size, y0, oz + lp.position.y * cell_size),
				Vector3(lp.size.x * cell_size, yh, lp.size.y * cell_size)
			)
		)
	for p in _planner.pocket_parks:
		out.append(
			AABB(
				Vector3(ox + p.x * cell_size, y0, oz + p.y * cell_size),
				Vector3(cell_size, yh, cell_size)
			)
		)
	return out


## World-space glow-square AABB for MandelbrotArena (empty if not a Fractal tile).
func get_fractal_world_bounds() -> Dictionary:
	return _fractal_world_bounds.duplicate()


func _compute_fractal_glow_world_bounds() -> Dictionary:
	if _fractal == null:
		return {}
	var gmin: Vector3i = _fractal.last_glow_min as Vector3i
	var gmax: Vector3i = _fractal.last_glow_max as Vector3i
	if gmax.x <= gmin.x or gmax.z <= gmin.z:
		return {}
	var vs := voxel_size
	## Walkable top of the one-voxel glow deck.
	var ground_y_m := float(ground_thickness + 1) * vs
	var min_w := Vector3(
		(float(origin_vox.x) + float(gmin.x)) * vs,
		ground_y_m,
		(float(origin_vox.z) + float(gmin.z)) * vs
	)
	var max_w := Vector3(
		(float(origin_vox.x) + float(gmax.x)) * vs,
		ground_y_m,
		(float(origin_vox.z) + float(gmax.z)) * vs
	)
	return {"min": min_w, "max": max_w, "ground_y_m": ground_y_m}


func end_generate() -> void:
	_brush = null
	_plaza = null
	_park = null
	_hill = null
	_graveyard = null
	_lake = null
	_castle = null
	_fractal = null
	_grammar = null


func _paint_cell(cx: int, cz: int) -> void:
	var tag := _planner.tag_at(cx, cz)
	var min_v := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
	var max_v := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
	match tag:
		LandUse.AVENUE:
			_paint_street_cell(min_v, max_v, cx, cz, true)
		LandUse.ROAD:
			_paint_street_cell(min_v, max_v, cx, cz, false)
		LandUse.PLAZA:
			_paint_plaza_cell(min_v, max_v, cx, cz, _plaza)
		LandUse.PARK:
			_paint_park_cell(min_v, max_v, cx, cz, _park)
		LandUse.HILL, LandUse.LAKE, LandUse.CASTLE:
			_brush.fill_box(min_v, max_v, VoxelMaterial.PARK)
		LandUse.FRACTAL:
			_brush.fill_box(min_v, max_v, VoxelMaterial.PARK)
		LandUse.GRAVEYARD:
			_brush.fill_box(min_v, max_v, VoxelMaterial.GRAVE_SOIL)
		_:
			if _planner.is_tower_parcel_secondary(cx, cz):
				return
			var bounds := _lot_paint_bounds(cx, cz)
			_paint_lot(bounds[0], bounds[1], cx, cz, tag, _grammar)


func get_planner() -> DistrictPlanner:
	return _planner


## The planner-derived lane and pavement annotations for this district. No voxels are read:
## the span field owns heights, so this is pure topology and costs nothing on the main thread.
func build_street_topology() -> StreetTopology:
	if _planner == null:
		push_error(
			"DistrictGenerator.build_street_topology: planner missing — call generate() first"
		)
		return null
	var topology: StreetTopology = StreetTopologyScript.new()
	topology.build(_planner, cell_size, voxel_size, ground_thickness, origin_vox)
	return topology


## Yaw applied after the last successful find_spawn_world (NaN = leave walker default).
var last_spawn_yaw: float = NAN


func find_spawn_world(tool: VoxelTool) -> Vector3:
	## Feet slightly above the top of the ground voxel so we don't clip/tunnel.
	## Headroom must clear the walker crown (~2.65 m ≈ 6 voxels at 0.5 m); the old
	## 3-voxel check let hill-cave spawns start in crawl space.
	const HEADROOM_VOX := 6
	last_spawn_yaw = NAN
	_brush = CityBrushScript.new(tool, origin_vox)
	var vs := voxel_size
	var floor_top_y := float(ground_thickness + 1) * vs
	var spawn_y := floor_top_y + 0.85
	if theme != null and theme.id == DistrictTheme.FRACTAL:
		var panel_spawn := _find_fractal_panel_spawn(spawn_y, HEADROOM_VOX)
		if is_finite(panel_spawn.x):
			_brush = null
			return panel_spawn
	var cx := size_x / 2
	var cz := size_z / 2
	for radius in range(0, maxi(size_x, size_z) / 2, 2):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius and radius > 0:
					continue
				var x := cx + dx
				var z := cz + dz
				if x < 1 or z < 1 or x >= size_x - 1 or z >= size_z - 1:
					continue
				var mat := _brush.get_vox(Vector3i(x, ground_thickness, z))
				if not VoxelMaterial.is_walkable_surface(mat):
					continue
				if not _has_spawn_headroom(x, z, HEADROOM_VOX):
					continue
				_brush = null
				return Vector3(
					(float(origin_vox.x + x) + 0.5) * vs,
					spawn_y,
					(float(origin_vox.z + z) + 0.5) * vs
				)
	_brush = null
	return Vector3(
		(float(origin_vox.x + cx) + 0.5) * vs,
		spawn_y,
		(float(origin_vox.z + cz) + 0.5) * vs
	)


## Stand outside the south Mandelbrot panel (facing it / plaza behind the glass).
func _find_fractal_panel_spawn(spawn_y: float, headroom_vox: int) -> Vector3:
	if _fractal_world_bounds.is_empty():
		return Vector3(INF, INF, INF)
	var min_w: Vector3 = _fractal_world_bounds["min"] as Vector3
	var max_w: Vector3 = _fractal_world_bounds["max"] as Vector3
	var side := minf(max_w.x - min_w.x, max_w.z - min_w.z)
	if side < 20.0:
		return Vector3(INF, INF, INF)
	var center_x := (min_w.x + max_w.x) * 0.5
	var center_z := (min_w.z + max_w.z) * 0.5
	## Must match MandelbrotArena.EDGE_INSET_M — panel sits on the south glow edge.
	const EDGE_INSET_M := 0.5
	const STAND_OFF_M := 3.5
	var half := side * 0.5 - EDGE_INSET_M
	var target := Vector3(center_x, spawn_y, center_z - half - STAND_OFF_M)
	var vs := voxel_size
	var lx := int(floor((target.x / vs) - float(origin_vox.x)))
	var lz := int(floor((target.z / vs) - float(origin_vox.z)))
	for radius in range(0, 24):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius and radius > 0:
					continue
				var x := lx + dx
				var z := lz + dz
				if x < 1 or z < 1 or x >= size_x - 1 or z >= size_z - 1:
					continue
				var mat := _brush.get_vox(Vector3i(x, ground_thickness, z))
				if not VoxelMaterial.is_walkable_surface(mat):
					continue
				if not _has_spawn_headroom(x, z, headroom_vox):
					continue
				## Walker forward is −Z at yaw 0; face +Z toward the south panel.
				last_spawn_yaw = PI
				return Vector3(
					(float(origin_vox.x + x) + 0.5) * vs,
					spawn_y,
					(float(origin_vox.z + z) + 0.5) * vs
				)
	return Vector3(INF, INF, INF)


func _has_spawn_headroom(x: int, z: int, air_voxels: int) -> bool:
	for dy in range(1, air_voxels + 1):
		if _brush.get_vox(Vector3i(x, ground_thickness + dy, z)) != VoxelMaterial.AIR:
			return false
	return true


func _sidewalk_depth_vox() -> int:
	## ~2.0–2.5 m sidewalk band inside the street cell.
	return clampi(int(round(2.0 / voxel_size)), 3, maxi(3, cell_size / 6))


func _paint_street_cell(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, avenue: bool) -> void:
	## Sidewalk corridors on both sides, curb step, asphalt carriageway.
	var y := ground_thickness
	var horiz := LandUse.is_road(_planner.tag_at(cx - 1, cz)) or LandUse.is_road(_planner.tag_at(cx + 1, cz))
	var vert := LandUse.is_road(_planner.tag_at(cx, cz - 1)) or LandUse.is_road(_planner.tag_at(cx, cz + 1))
	var intersection := horiz and vert

	# Base fill sidewalk so edges connect to lots.
	_brush.fill_box(min_v, max_v, theme.sidewalk_mat)

	var sw := _sidewalk_depth_vox()
	var curb := 1
	if intersection:
		# Asphalt diamond/cross in the middle; sidewalks on corners; crosswalks bridging.
		var inset := sw + curb
		_brush.fill_box(
			Vector3i(min_v.x + inset, y, min_v.z + inset),
			Vector3i(max_v.x - inset, y + 1, max_v.z - inset),
			VoxelMaterial.ASPHALT
		)
		_paint_curb_ring(
			Vector3i(min_v.x + sw, y, min_v.z + sw),
			Vector3i(max_v.x - sw, y + 1, max_v.z - sw)
		)
		_paint_crosswalk_bridges(min_v, max_v)
	elif horiz and not vert:
		# East-west street: sidewalks on N/S, asphalt band in middle.
		_brush.fill_box(
			Vector3i(min_v.x, y, min_v.z + sw + curb),
			Vector3i(max_v.x, y + 1, max_v.z - sw - curb),
			VoxelMaterial.ASPHALT
		)
		for x in range(min_v.x, max_v.x):
			_brush.set_vox(Vector3i(x, y, min_v.z + sw), VoxelMaterial.CURB)
			_brush.set_vox(Vector3i(x, y, max_v.z - sw - 1), VoxelMaterial.CURB)
		_paint_lane_ew(min_v, max_v, avenue)
		if _should_crosswalk(cx, cz):
			_paint_crosswalk_bridges(min_v, max_v)
	elif vert and not horiz:
		_brush.fill_box(
			Vector3i(min_v.x + sw + curb, y, min_v.z),
			Vector3i(max_v.x - sw - curb, y + 1, max_v.z),
			VoxelMaterial.ASPHALT
		)
		for z in range(min_v.z, max_v.z):
			_brush.set_vox(Vector3i(min_v.x + sw, y, z), VoxelMaterial.CURB)
			_brush.set_vox(Vector3i(max_v.x - sw - 1, y, z), VoxelMaterial.CURB)
		_paint_lane_ns(min_v, max_v, avenue)
		if _should_crosswalk(cx, cz):
			_paint_crosswalk_bridges(min_v, max_v)
	else:
		# Isolated / stub: treat as NS.
		_brush.fill_box(
			Vector3i(min_v.x + sw + curb, y, min_v.z),
			Vector3i(max_v.x - sw - curb, y + 1, max_v.z),
			VoxelMaterial.ASPHALT
		)
		for z in range(min_v.z, max_v.z):
			_brush.set_vox(Vector3i(min_v.x + sw, y, z), VoxelMaterial.CURB)
			_brush.set_vox(Vector3i(max_v.x - sw - 1, y, z), VoxelMaterial.CURB)

	if avenue and not intersection and theme.median_planting:
		_paint_avenue_median(min_v, max_v, horiz)


func _paint_curb_ring(min_v: Vector3i, max_v: Vector3i) -> void:
	var y := min_v.y
	for z in range(min_v.z, max_v.z):
		_brush.set_vox(Vector3i(min_v.x, y, z), VoxelMaterial.CURB)
		_brush.set_vox(Vector3i(max_v.x - 1, y, z), VoxelMaterial.CURB)
	for x in range(min_v.x, max_v.x):
		_brush.set_vox(Vector3i(x, y, min_v.z), VoxelMaterial.CURB)
		_brush.set_vox(Vector3i(x, y, max_v.z - 1), VoxelMaterial.CURB)


func _paint_lane_ew(min_v: Vector3i, max_v: Vector3i, avenue: bool) -> void:
	if not avenue and _rng.randf() > 0.4:
		return
	var y := ground_thickness
	var mz := (min_v.z + max_v.z) / 2
	for x in range(min_v.x + 3, max_v.x - 3):
		if (x % 3) == 0:
			_brush.set_vox(Vector3i(x, y, mz), VoxelMaterial.ROAD_LINE)


func _paint_lane_ns(min_v: Vector3i, max_v: Vector3i, avenue: bool) -> void:
	if not avenue and _rng.randf() > 0.4:
		return
	var y := ground_thickness
	var mx := (min_v.x + max_v.x) / 2
	for z in range(min_v.z + 3, max_v.z - 3):
		if (z % 3) == 0:
			_brush.set_vox(Vector3i(mx, y, z), VoxelMaterial.ROAD_LINE)


func _paint_avenue_median(min_v: Vector3i, max_v: Vector3i, horiz: bool) -> void:
	var y := ground_thickness
	if horiz:
		var mz := (min_v.z + max_v.z) / 2
		for x in range(min_v.x + 3, max_v.x - 3, 4):
			_brush.set_vox(Vector3i(x, y, mz), VoxelMaterial.PLANTER)
			## LEAVES is walk-through — PARK cubes were solid snags on the median.
			_brush.set_vox(Vector3i(x, y + 1, mz), VoxelMaterial.LEAVES)
	else:
		var mx := (min_v.x + max_v.x) / 2
		for z in range(min_v.z + 3, max_v.z - 3, 4):
			_brush.set_vox(Vector3i(mx, y, z), VoxelMaterial.PLANTER)
			_brush.set_vox(Vector3i(mx, y + 1, z), VoxelMaterial.LEAVES)


func _should_crosswalk(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := _planner.tag_at(cx + dx, cz + dz)
			if t == LandUse.PLAZA or LandUse.is_open_nature(t):
				return true
	var roads := 0
	if LandUse.is_road(_planner.tag_at(cx - 1, cz)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx + 1, cz)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx, cz - 1)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx, cz + 1)):
		roads += 1
	return roads >= 3


func _paint_crosswalk_bridges(min_v: Vector3i, max_v: Vector3i) -> void:
	## Stripe bands connecting opposite sidewalks across the carriageway.
	var y := ground_thickness
	var sw := _sidewalk_depth_vox()
	# East-west stripes along N and S edges of the asphalt.
	for i in range(min_v.x + sw, max_v.x - sw):
		if (i % 2) != 0:
			continue
		_brush.set_vox(Vector3i(i, y, min_v.z + sw), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(i, y, min_v.z + sw + 1), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(i, y, max_v.z - sw - 1), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(i, y, max_v.z - sw - 2), VoxelMaterial.CROSSWALK)
	# North-south stripes along W and E edges.
	for i in range(min_v.z + sw, max_v.z - sw):
		if (i % 2) != 0:
			continue
		_brush.set_vox(Vector3i(min_v.x + sw, y, i), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(min_v.x + sw + 1, y, i), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(max_v.x - sw - 1, y, i), VoxelMaterial.CROSSWALK)
		_brush.set_vox(Vector3i(max_v.x - sw - 2, y, i), VoxelMaterial.CROSSWALK)


func _paint_plaza_cell(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, plaza: PlazaComposer
) -> void:
	## Base pave every plaza cell. Fancy compose runs once in decorate_open_spaces().
	_brush.fill_box(min_v, max_v, theme.plaza_mat)
	var in_grand := _planner.grand_plaza.has_point(Vector2i(cx, cz))
	if in_grand:
		return
	for s in _planner.satellite_plazas:
		if s.has_point(Vector2i(cx, cz)):
			return
	# Orphan single-cell plaza — compose immediately (won't be wiped by neighbors).
	plaza.compose_satellite(min_v, max_v)


func _paint_park_cell(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, park: ParkComposer
) -> void:
	## Base lawn every park cell. Large-park compose runs in decorate_open_spaces().
	var lp := _planner.large_park
	if lp.size.x > 0 and lp.has_point(Vector2i(cx, cz)):
		_brush.fill_box(min_v, max_v, VoxelMaterial.PARK)
		return
	park.compose_pocket(min_v, max_v)


func _paint_lot(
	min_v: Vector3i,
	max_v: Vector3i,
	cx: int,
	cz: int,
	zone: int,
	grammar: BuildingGrammar
) -> void:
	_brush.fill_box(min_v, max_v, theme.sidewalk_mat)
	## Landlocked lots stay the block's courtyard — see DistrictPlanner.rect_is_landlocked.
	if _planner.rect_is_landlocked(_lot_rect(cx, cz)):
		_brush.fill_box(min_v, max_v, VoxelMaterial.PARK)
		return
	var bounds := _buildable_bounds(min_v, max_v, cx, cz)
	var bmin: Vector3i = bounds[0]
	var bmax: Vector3i = bounds[1]
	if bmax.x - bmin.x < 6 or bmax.z - bmin.z < 6:
		return
	## The zone is a ceiling; the planner intensity field decides the actual height, so
	## the skyline gets peaks and valleys instead of one flat step per zone ring.
	var saved := grammar.max_height
	var ceiling := max_building_height_vox
	match zone:
		LandUse.CORE_LOT, LandUse.CIVIC_LOT:
			ceiling = max_building_height_vox
		LandUse.MID_LOT:
			ceiling = mini(saved, 120)  # 60 m
		LandUse.TOWN_LOT:
			ceiling = mini(saved, 80)  # 40 m
		LandUse.COURTYARD_LOT:
			ceiling = mini(saved, 72)  # 36 m
		_:
			pass
	var parcel := _planner.tower_parcel_at(cx, cz)
	var intensity := (
		_planner.intensity_max_in_rect(parcel)
		if parcel.size.x > 0
		else _planner.intensity_at(cx, cz)
	)
	grammar.max_height = mini(
		_height_cap_for_intensity(intensity, ceiling), _footprint_height_cap(bmin, bmax)
	)
	var facing: int
	var corner: bool
	var on_plaza: bool
	var on_park: bool
	if parcel.size.x > 0:
		facing = _planner.street_facing_rect(parcel)
		corner = _planner.is_corner_parcel(parcel)
		on_plaza = _planner.faces_plaza_rect(parcel)
		on_park = _planner.faces_park_rect(parcel)
	else:
		facing = _planner.street_facing(cx, cz)
		corner = _planner.is_corner_lot(cx, cz)
		on_plaza = _planner.faces_plaza(cx, cz)
		on_park = _planner.faces_park(cx, cz)
	grammar.build_for_zone(bmin, bmax, zone, facing, corner, on_plaza, on_park)
	## Far LOD uses the height the grammar actually painted. Deriving it from the cap
	## instead made distant impostors overshoot the real voxels — archetypes routinely
	## build well below their ceiling.
	if grammar.built_height_vox <= 0:
		push_error(
			"DistrictGenerator: grammar reported no built height for zone %d at cell (%d, %d)"
			% [zone, cx, cz]
		)
	if grammar.impostor_parts.is_empty():
		push_error(
			"DistrictGenerator: grammar reported no massing parts for zone %d at cell (%d, %d)"
			% [zone, cx, cz]
		)
	_record_building_impostor(grammar.impostor_parts, zone)
	var building := _record_building_interior(bmin, bmax, cx, cz, zone, grammar)
	_record_lot_doorways(grammar)
	_record_elevator_shaft(bmin, bmax, grammar, building)
	grammar.max_height = saved


## One InteriorRoom per walkable storey of a lot (world voxels), indexed under every
## district cell the lot covers. Walls are 1 cell thick; ground fill raises the walking
## surface one voxel above the deck (see BuildingGrammar._fill_shell).
func _record_building_interior(
	bmin: Vector3i, bmax: Vector3i, cx: int, cz: int, zone: int, grammar: BuildingGrammar
) -> BuildingInterior:
	var plates: Array[StoreyPlate] = grammar.storey_plates.duplicate()
	if plates.is_empty():
		## Round archetypes (cylinder, spiral, blob) never paint a rect shell — they keep
		## the single ground room the bake has always emitted.
		var ground := _ground_plate(bmin, bmax, grammar)
		if ground != null:
			plates.append(ground)
	plates.sort_custom(_plate_is_lower)
	var world_lot := Rect2i(
		bmin.x + origin_vox.x, bmin.z + origin_vox.z, bmax.x - bmin.x, bmax.z - bmin.z
	)
	var building := BuildingInterior.make(
		world_lot, _building_use_for(zone, world_lot, plates.size())
	)
	var storey := -1
	var prev_floor_y := -1
	for plate in plates:
		## Arch legs paint two shells per storey — they share one index.
		if plate.floor_y != prev_floor_y:
			storey += 1
			prev_floor_y = plate.floor_y
		building.storeys.append(_storey_room(plate, storey, building.use, zone))
	if building.storeys.is_empty():
		return building
	var cells := _lot_rect(cx, cz)
	for z in range(cells.position.y, cells.end.y):
		for x in range(cells.position.x, cells.end.x):
			interior_buildings[Vector2i(x, z)] = building
	return building


func _plate_is_lower(a: StoreyPlate, b: StoreyPlate) -> bool:
	return a.floor_y < b.floor_y


func _storey_room(plate: StoreyPlate, storey: int, use: int, zone: int) -> InteriorRoom:
	var world_rect := Rect2i(
		plate.rect.position.x + origin_vox.x,
		plate.rect.position.y + origin_vox.z,
		plate.rect.size.x,
		plate.rect.size.y
	)
	var room := InteriorRoom.make(
		world_rect,
		plate.floor_y + origin_vox.y,
		plate.air_h,
		_interior_purpose_for_zone(zone, world_rect)
	)
	room.storey = storey
	room.use = use
	return room


func _ground_plate(
	bmin: Vector3i, bmax: Vector3i, grammar: BuildingGrammar
) -> StoreyPlate:
	var inner := Rect2i(
		bmin.x + 1,
		bmin.z + 1,
		maxi(bmax.x - bmin.x - 2, 0),
		maxi(bmax.z - bmin.z - 2, 0)
	)
	if inner.size.x < 3 or inner.size.y < 3:
		return null
	## Clear band under the ceiling slab at y0+fh-1.
	return StoreyPlate.make(
		inner, bmin.y + 1, maxi(grammar.ground_floor_height - 3, 2)
	)


## Multi-storey lots: 3×3 cabin in the corner opposite the street door.
## Carves the cabin voxels, then records the shaft and its InteriorRoom keep_clear.
func _record_elevator_shaft(
	bmin: Vector3i, bmax: Vector3i, grammar: BuildingGrammar, building: BuildingInterior
) -> void:
	var floors := grammar.last_floors
	if floors < 2:
		return
	var clear := Rect2i(
		bmin.x + 1,
		bmin.z + 1,
		maxi(bmax.x - bmin.x - 2, 0),
		maxi(bmax.z - bmin.z - 2, 0)
	)
	const CABIN := 3
	## Cabin + its enclosure walls is CABIN + 2 wide; the extra margin keeps a walkable
	## lobby beside the shaft instead of a bay that swallows the whole room.
	if clear.size.x < CABIN + 5 or clear.size.y < CABIN + 5:
		return
	var local_rect := _elevator_cabin_rect(clear, grammar.last_facing, CABIN)
	## Storeys the cabin actually stands on. Tower shafts and courtyard voids sit inside
	## the lot AABB, so upper storeys can have no floor under this corner — riding to one
	## would drop the player outside the building.
	var local_ys := PackedInt32Array()
	for f in range(floors):
		var pad_y := grammar.landing_y(bmin.y, f)
		if not _cabin_floor_is_solid(local_rect, pad_y):
			break
		local_ys.append(pad_y)
	if local_ys.size() < 2:
		return
	var bay_dir := _elevator_bay_dir(grammar.last_facing)
	var ceil_ys := _cabin_ceiling_ys(local_ys, grammar.floor_height)
	_paint_elevator_cabin(local_rect, local_ys, ceil_ys, bay_dir)
	var floor_ys := PackedInt32Array()
	for y in local_ys:
		floor_ys.append(int(y) + origin_vox.y)
	var world_rect := Rect2i(
		local_rect.position.x + origin_vox.x,
		local_rect.position.y + origin_vox.z,
		local_rect.size.x,
		local_rect.size.y
	)
	var shaft: RefCounted = (
		ElevatorShaftScript.make(world_rect, floor_ys, bay_dir) as RefCounted
	)
	elevator_shafts.append(shaft)
	## Reserve the enclosure too — props stamped into the shaft walls would sink halfway
	## into metal, and props in the bay would block the doorway. Every storey the cabin
	## serves needs the reservation, not just the ground one.
	building.reserve_on_floors(world_rect.grow(1), floor_ys)


## Every cabin cell rests on building floor at `pad_y` (district-local).
func _cabin_floor_is_solid(cabin: Rect2i, pad_y: int) -> bool:
	for z in range(cabin.position.y, cabin.end.y):
		for x in range(cabin.position.x, cabin.end.x):
			if _brush.get_vox(Vector3i(x, pad_y, z)) == VoxelMaterial.AIR:
				return false
	return true


## Ceiling slab Y per storey: the next landing's deck, or one storey up for the top.
func _cabin_ceiling_ys(local_ys: PackedInt32Array, floor_height: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(local_ys.size()):
		if i + 1 < local_ys.size():
			out.append(int(local_ys[i + 1]) - 1)
		else:
			out.append(int(local_ys[i]) + maxi(floor_height, 3) - 1)
	return out


## Metal bay per storey: walkable pad, clear cabin, and a three-sided enclosure whose
## opening faces the street door so the elevator reads from the entrance.
func _paint_elevator_cabin(
	cabin: Rect2i, local_ys: PackedInt32Array, ceil_ys: PackedInt32Array, bay_dir: Vector2i
) -> void:
	var bay := _elevator_bay_rect(cabin, bay_dir)
	for i in range(local_ys.size()):
		var pad_y := int(local_ys[i])
		var ceil_y := int(ceil_ys[i])
		## Two clear rows minimum, else the bay is a crawlspace, not a cabin.
		if ceil_y - pad_y < 3:
			continue
		_brush.fill_box(
			Vector3i(cabin.position.x, pad_y, cabin.position.y),
			Vector3i(cabin.end.x, pad_y + 1, cabin.end.y),
			VoxelMaterial.METAL_PLATE
		)
		## Enclosure over the grown footprint, then the cabin void back out of it.
		_brush.fill_box(
			Vector3i(cabin.position.x - 1, pad_y + 1, cabin.position.y - 1),
			Vector3i(cabin.end.x + 1, ceil_y, cabin.end.y + 1),
			VoxelMaterial.METAL_PLATE
		)
		_brush.fill_box(
			Vector3i(cabin.position.x, pad_y + 1, cabin.position.y),
			Vector3i(cabin.end.x, ceil_y, cabin.end.y),
			VoxelMaterial.AIR
		)
		## Bay doorway. Tall storeys keep a lintel course; a 2 m storey opens full height
		## because a 1 m head clearance is not walkable.
		var band_h := ceil_y - pad_y - 1
		var open_top := ceil_y - 1 if band_h >= 5 else ceil_y
		_brush.fill_box(
			Vector3i(bay.position.x, pad_y + 1, bay.position.y),
			Vector3i(bay.end.x, open_top, bay.end.y),
			VoxelMaterial.AIR
		)


## Cabin side left open as the doorway: the street side, so the bay reads from the
## entrance. facing: 0=+Z, 1=−Z, 2=+X, 3=−X (DistrictPlanner.street_facing).
func _elevator_bay_dir(facing: int) -> Vector2i:
	match facing:
		0:
			return Vector2i(0, 1)
		1:
			return Vector2i(0, -1)
		2:
			return Vector2i(1, 0)
		_:
			return Vector2i(-1, 0)


## The one-cell strip hugging the cabin's open face.
func _elevator_bay_rect(cabin: Rect2i, bay_dir: Vector2i) -> Rect2i:
	if bay_dir.x > 0:
		return Rect2i(cabin.end.x, cabin.position.y, 1, cabin.size.y)
	if bay_dir.x < 0:
		return Rect2i(cabin.position.x - 1, cabin.position.y, 1, cabin.size.y)
	if bay_dir.y > 0:
		return Rect2i(cabin.position.x, cabin.end.y, cabin.size.x, 1)
	return Rect2i(cabin.position.x, cabin.position.y - 1, cabin.size.x, 1)


## Cabin footprint inside `clear` (district-local XZ), opposite street `facing`.
## facing: 0=+Z, 1=-Z, 2=+X, 3=-X (DistrictPlanner.street_facing).
func _elevator_cabin_rect(clear: Rect2i, facing: int, cabin: int) -> Rect2i:
	var x_lo := clear.position.x + 1
	var z_lo := clear.position.y + 1
	var x_hi := clear.position.x + clear.size.x - cabin - 1
	var z_hi := clear.position.y + clear.size.y - cabin - 1
	match facing:
		0: ## Street +Z → back at −Z.
			return Rect2i(x_hi, z_lo, cabin, cabin)
		1: ## Street −Z → back at +Z.
			return Rect2i(x_hi, z_hi, cabin, cabin)
		2: ## Street +X → back at −X.
			return Rect2i(x_lo, z_hi, cabin, cabin)
		_: ## Street −X → back at +X.
			return Rect2i(x_hi, z_hi, cabin, cabin)


## Promote grammar-local door punches to world-space CastleDoorway records.
## Drop openings whose façade was carved open after the punch (arcade, U-court, …).
func _record_lot_doorways(grammar: BuildingGrammar) -> void:
	for item in grammar.lot_doorways:
		var local_d: CastleDoorway = item as CastleDoorway
		if local_d == null:
			continue
		if not DoorBarrier.has_wall_frame(_brush, local_d):
			## Window / trim passes sometimes glaze posts after the grammar seal —
			## restore masonry from a neighbouring solid wall cell when possible.
			_repair_lot_door_frame(local_d)
			if not DoorBarrier.has_wall_frame(_brush, local_d):
				continue
		var world_d: CastleDoorway = CastleDoorwayScript.new() as CastleDoorway
		world_d.center = Vector2i(
			local_d.center.x + origin_vox.x, local_d.center.y + origin_vox.z
		)
		world_d.axis = local_d.axis
		world_d.width = local_d.width
		world_d.depth = local_d.depth
		world_d.storey = local_d.storey
		world_d.floor_y = local_d.floor_y + origin_vox.y
		world_d.height = local_d.height
		world_d.leaf = local_d.leaf
		world_d.link = local_d.link
		world_d.arch_courses = local_d.arch_courses
		lot_doorways.append(world_d)


## Sample a solid non-glass wall id beside the opening and repaint full jamb columns.
func _repair_lot_door_frame(d: CastleDoorway) -> void:
	var mat := _sample_door_frame_mat(d)
	if mat < 0:
		return
	var s := d.side()
	var half := d.width / 2
	for row in range(1, d.height + 1):
		var y := d.floor_y + row
		for j in [-1, 1]:
			var jxz: Vector2i = d.center + s * ((half + 1) * j)
			_brush.set_vox(Vector3i(jxz.x, y, jxz.y), mat)
	_brush.set_vox(Vector3i(d.center.x, d.floor_y + d.height + 1, d.center.y), mat)


func _sample_door_frame_mat(d: CastleDoorway) -> int:
	var s := d.side()
	var half := d.width / 2
	var y := d.floor_y + mini(2, d.height)
	## Prefer cells just outside the clear (true jambs), then further along the wall.
	var probes: Array[Vector2i] = [
		d.center + s * (half + 1),
		d.center - s * (half + 1),
		d.center + s * (half + 2),
		d.center - s * (half + 2),
	]
	for xz in probes:
		var id := _brush.get_vox(Vector3i(xz.x, y, xz.y))
		if id == VoxelMaterial.AIR:
			continue
		if id == VoxelMaterial.GLASS or id == VoxelMaterial.GLASS_LIT:
			continue
		if VoxelMaterial.is_solid(id):
			return id
	return -1


## What the building is *for*: FloorPlanner turns this into a partition layout per
## storey. Downtown gets offices over a shop floor, the fabric gets flats, and anything
## single-storey skips the retail podium because there is nothing above it.
func _building_use_for(zone: int, rect: Rect2i, storeys: int) -> int:
	var h := absi(rect.position.x * 73856093 ^ rect.position.y * 19349663 ^ zone * 83492791)
	match zone:
		LandUse.CORE_LOT, LandUse.CIVIC_LOT:
			if storeys < 2:
				return FloorPlanner.Use.OFFICE
			return FloorPlanner.Use.RETAIL_OVER_OFFICE
		LandUse.MID_LOT:
			if storeys < 2:
				return FloorPlanner.Use.OFFICE if h % 2 == 0 else FloorPlanner.Use.RESIDENTIAL
			return (
				FloorPlanner.Use.RETAIL_OVER_OFFICE
				if h % 2 == 0
				else FloorPlanner.Use.RETAIL_OVER_FLATS
			)
		_:
			return FloorPlanner.Use.RESIDENTIAL


func _interior_purpose_for_zone(zone: int, rect: Rect2i) -> int:
	var h := absi(rect.position.x * 73856093 ^ rect.position.y * 19349663 ^ zone * 83492791)
	match zone:
		LandUse.CORE_LOT, LandUse.CIVIC_LOT:
			return RoomDecorator.Purpose.OFFICE
		LandUse.MID_LOT:
			var mid: Array[int] = [
				RoomDecorator.Purpose.OFFICE,
				RoomDecorator.Purpose.LIVING_ROOM,
				RoomDecorator.Purpose.DINING_ROOM,
			]
			return mid[h % mid.size()]
		LandUse.COURTYARD_LOT:
			return RoomDecorator.Purpose.LIVING_ROOM
		_:
			## Town / generic lots — domestic mix.
			var home: Array[int] = [
				RoomDecorator.Purpose.LIVING_ROOM,
				RoomDecorator.Purpose.BEDROOM,
				RoomDecorator.Purpose.KITCHEN,
				RoomDecorator.Purpose.DINING_ROOM,
			]
			return home[h % home.size()]


func _height_cap_for(cx: int, cz: int, zone_ceiling: int) -> int:
	return _height_cap_for_intensity(_planner.intensity_at(cx, cz), zone_ceiling)


func _height_cap_for_intensity(intensity: float, zone_ceiling: int) -> int:
	## Non-linear so only genuinely dense cells reach for the sky.
	var shaped := pow(clampf(intensity, 0.0, 1.0), 1.7)
	var scaled := float(max_building_height_vox) * theme.height_scale * lerpf(0.14, 1.0, shaped)
	## 12 vox ≈ 6 m: never below a two-storey house.
	return clampi(int(round(scaled)), 12, zone_ceiling)


## Ground area decides how tall a lot may build. Without this the intensity field alone
## granted 100 m to a 12 m lot — a 10:1 needle on a 100 m² plate.
func _footprint_height_cap(bmin: Vector3i, bmax: Vector3i) -> int:
	var short_m := float(mini(bmax.x - bmin.x, bmax.z - bmin.z)) * voxel_size
	var area_m2 := float(bmax.x - bmin.x) * float(bmax.z - bmin.z) * voxel_size * voxel_size
	if area_m2 < MIN_TOWER_PLATE_M2 or short_m < MIN_TOWER_SIDE_M:
		return int(round(FABRIC_HEIGHT_M / voxel_size))
	return int(round(short_m * MAX_SLENDERNESS / voxel_size))


## Turn the grammar's massing description into far-LOD shells. The grammar knows whether
## it built a cylinder, an arch or an L-plan; deriving the shape from the zone here (as
## this used to) gave every round or pierced building a plain box silhouette.
func _record_building_impostor(parts: Array[Dictionary], zone: int) -> void:
	var vs := voxel_size
	var color := Color(0.62, 0.58, 0.52)
	var lit := 0.32
	match zone:
		LandUse.CORE_LOT:
			color = Color(0.55, 0.58, 0.62)
			lit = 0.48
		LandUse.CIVIC_LOT:
			color = Color(0.72, 0.70, 0.66)
			lit = 0.22
		LandUse.MID_LOT:
			color = Color(0.66, 0.48, 0.40)
			lit = 0.38
		LandUse.TOWN_LOT:
			color = Color(0.70, 0.55, 0.42)
			lit = 0.28
		LandUse.COURTYARD_LOT:
			color = Color(0.58, 0.52, 0.46)
			lit = 0.3
		_:
			pass

	for part in parts:
		var pc: Vector3 = part["center"]
		var ps: Vector3 = part["size"]
		## Ground-floor shells read as podium: slightly darker, fewer lit windows.
		var near_ground := pc.y - ps.y * 0.5 < 3.0
		_append_impostor_part(
			int(part["shape"]),
			Vector3(
				(float(origin_vox.x) + pc.x) * vs,
				pc.y * vs,
				(float(origin_vox.z) + pc.z) * vs
			),
			ps * vs,
			float(part["yaw"]),
			color * (1.02 if near_ground else 1.0),
			lit * (0.65 if near_ground else 1.0)
		)


## Fractional part, i.e. the shader `fract()` which GDScript does not have.
func _unit_hash(v: float) -> float:
	return v - floorf(v)


func _append_impostor_part(
	shape: int, center: Vector3, size: Vector3, yaw: float, color: Color, lit: float
) -> void:
	if size.x < 1.0 or size.y < 1.0 or size.z < 1.0:
		return
	## Per-lot brightness/hue spread, mirroring `tint_variation` in voxel_surface so the
	## far skyline is as varied as the near one instead of one flat colour per zone.
	## Quantised to the lot grid so all parts of one building share a tint.
	var lot_m := VoxelBlockLibrary.LOT_METERS
	var lot := Vector2(floorf(center.x / lot_m), floorf(center.z / lot_m))
	var hash := _unit_hash(sin(lot.x * 12.9898 + lot.y * 78.233) * 43758.5453)
	var bright := 1.0 + (hash - 0.5) * 0.3
	var varied := Color(
		clampf(color.r * bright * (1.0 + (_unit_hash(hash * 7.31) - 0.5) * 0.12), 0.0, 1.0),
		clampf(color.g * bright, 0.0, 1.0),
		clampf(color.b * bright * (1.0 - (_unit_hash(hash * 13.77) - 0.5) * 0.12), 0.0, 1.0),
		1.0
	)
	building_impostors.append({
		"shape": shape,
		"center": center,
		"size": size,
		"yaw": yaw,
		"color": varied,
		"custom": Color(size.x, size.y, size.z, clampf(lit, 0.05, 0.85)),
	})
