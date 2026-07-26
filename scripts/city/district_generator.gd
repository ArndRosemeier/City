## Procedural district: planner → plazas/parks → building grammars → brush (live or offline).
class_name DistrictGenerator
extends RefCounted

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CarRoadMapScript := preload("res://scripts/city/car_roadmap.gd")
const StreetNavLayersScript := preload("res://scripts/city/street_nav_layers.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const PlazaComposerScript := preload("res://scripts/city/plaza_composer.gd")
const ParkComposerScript := preload("res://scripts/city/park_composer.gd")
const HillComposerScript := preload("res://scripts/city/hill_composer.gd")
const GraveyardComposerScript := preload("res://scripts/city/graveyard_composer.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

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
## Planner cell ≈ 14 m — mid-size city lot / street ROW (euro mid-rise depth).
@export var cell_size: int = 28

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
var _grammar: BuildingGrammar
## World-space building massing for far LOD: {shape, center, size, yaw, color, custom}.
var building_impostors: Array = []
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
	_brush = CityBrushScript.new(null, Vector3i.ZERO)
	_brush.use_offline_volume()
	_setup_composers()


func get_offline_volume():
	## Returns NativeOfflineVoxelVolume when baking off-thread; otherwise null.
	if _brush == null:
		return null
	return _brush.volume


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

	_graveyard = GraveyardComposerScript.new()
	_graveyard.brush = _brush
	_graveyard.rng = _rng
	_graveyard.ground_y = ground_thickness
	_graveyard.planner = _planner
	_graveyard.cell_size = cell_size

	_grammar = BuildingGrammarScript.new()
	_grammar.brush = _brush
	_grammar.rng = _rng
	_grammar.theme = theme
	_grammar.floor_height = maxi(floor_height_vox, 6)
	_grammar.ground_floor_height = 8  # ~4.0 m retail / lobby
	_grammar.max_height = max_building_height_vox
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
		LandUse.PARK, LandUse.HILL:
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
	_reseed_cell(cx, cz)
	var tag := _planner.tag_at(cx, cz)
	var smin := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
	var smax := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
	match tag:
		LandUse.AVENUE, LandUse.ROAD:
			pass  ## Surface already complete.
		LandUse.PLAZA, LandUse.PARK, LandUse.HILL, LandUse.GRAVEYARD:
			pass  ## Fancy open-space decorate runs after all cells.
		_:
			_paint_lot(smin, smax, cx, cz, tag, _grammar)


func paint_cell_impostor_only(cx: int, cz: int) -> void:
	## Far-LOD: record building massing boxes without voxel shells.
	if _planner == null:
		return
	if cx < 0 or cz < 0 or cx >= _planner.cells_x or cz >= _planner.cells_z:
		return
	var tag := _planner.tag_at(cx, cz)
	match tag:
		LandUse.AVENUE, LandUse.ROAD, LandUse.PLAZA, LandUse.PARK, LandUse.HILL, LandUse.GRAVEYARD:
			return
		_:
			pass
	var smin := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
	var smax := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
	var ring := 1 if cell_size < 20 else 2
	var bmin := smin + Vector3i(ring, 0, ring)
	var bmax := smax - Vector3i(ring, 0, ring)
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
	## Far tiles deliberately skip the grammar, so there is no real massing to describe —
	## one coarse block per lot. These sit beyond the voxel radius entirely; when a tile
	## is upgraded to "full" it re-bakes and gets the grammar's actual shapes.
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


func decorate_open_spaces() -> void:
	## Fancy plaza/park/hill pass — call only once the full feature AABBs are editable.
	if (
		_brush == null or _planner == null or _plaza == null or _park == null
		or _hill == null or _graveyard == null
	):
		return
	var lh := _planner.large_hill
	if lh.size.x > 0:
		_rng.seed = DistrictCoord.feature_seed(city_seed, 3)
		var hmin := Vector3i(lh.position.x * cell_size, ground_thickness, lh.position.y * cell_size)
		var hmax := Vector3i(lh.end.x * cell_size, ground_thickness + 1, lh.end.y * cell_size)
		_hill.compose(hmin, hmax)
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
		or _hill == null or _graveyard == null
	):
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


func end_generate() -> void:
	_brush = null
	_plaza = null
	_park = null
	_hill = null
	_graveyard = null
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
		LandUse.HILL:
			_brush.fill_box(min_v, max_v, VoxelMaterial.PARK)
		LandUse.GRAVEYARD:
			_brush.fill_box(min_v, max_v, VoxelMaterial.GRAVE_SOIL)
		_:
			_paint_lot(min_v, max_v, cx, cz, tag, _grammar)


func get_planner() -> DistrictPlanner:
	return _planner


func build_street_nav(tool: VoxelTool) -> StreetNavLayers:
	if _planner == null:
		push_error("DistrictGenerator.build_street_nav: planner missing — call generate() first")
		return null
	var layers: StreetNavLayers = StreetNavLayersScript.new()
	layers.build(_planner, tool, cell_size, ground_thickness, voxel_size, origin_vox)
	return layers


func build_ped_roadmap(tool: VoxelTool, _stride: int = 2) -> PedRoadMap:
	var layers := build_street_nav(tool)
	var map: PedRoadMap = PedRoadMapScript.new()
	if layers != null and layers.ped != null:
		map.bind_graph(layers.ped, layers)
	return map


func build_car_roadmap(tool: VoxelTool, _stride: int = 2) -> CarRoadMap:
	var layers := build_street_nav(tool)
	var map: CarRoadMap = CarRoadMapScript.new()
	if layers != null and layers.road != null:
		map.bind_graph(layers.road, layers)
	return map


func collect_walkable_world_positions(tool: VoxelTool, stride: int = 2) -> PackedVector3Array:
	return build_ped_roadmap(tool, stride).positions


func find_spawn_world(tool: VoxelTool) -> Vector3:
	## Feet slightly above the top of the ground voxel so we don't clip/tunnel.
	## Headroom must clear the walker crown (~2.65 m ≈ 6 voxels at 0.5 m); the old
	## 3-voxel check let hill-cave spawns start in crawl space.
	const HEADROOM_VOX := 6
	_brush = CityBrushScript.new(tool, origin_vox)
	var vs := voxel_size
	var floor_top_y := float(ground_thickness + 1) * vs
	var spawn_y := floor_top_y + 0.85
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
	# Small private setback (~0.5–1.0 m) — footprint stays ~12–13 m on a 14 m lot.
	var ring := 1 if cell_size < 20 else 2
	var bmin := min_v + Vector3i(ring, 0, ring)
	var bmax := max_v - Vector3i(ring, 0, ring)
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
	grammar.max_height = _height_cap_for(cx, cz, ceiling)
	var facing := _planner.street_facing(cx, cz)
	var corner := _planner.is_corner_lot(cx, cz)
	var on_plaza := _planner.faces_plaza(cx, cz)
	var on_park := _planner.faces_park(cx, cz)
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
	grammar.max_height = saved


func _height_cap_for(cx: int, cz: int, zone_ceiling: int) -> int:
	## Non-linear so only genuinely dense cells reach for the sky.
	var v := _planner.intensity_at(cx, cz)
	var shaped := pow(clampf(v, 0.0, 1.0), 1.7)
	var scaled := float(max_building_height_vox) * theme.height_scale * lerpf(0.14, 1.0, shaped)
	## 12 vox ≈ 6 m: never below a two-storey house.
	return clampi(int(round(scaled)), 12, zone_ceiling)


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
