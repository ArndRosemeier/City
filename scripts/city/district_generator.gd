## Procedural district: planner → plazas/parks → building grammars → VoxelTool.
class_name DistrictGenerator
extends RefCounted

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const PlazaComposerScript := preload("res://scripts/city/plaza_composer.gd")
const ParkComposerScript := preload("res://scripts/city/park_composer.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

@export var city_seed: int = 42
## District size in voxels. 384 * 0.5m = 192m across.
@export var size_xz: int = 384
@export var ground_thickness: int = 1
## 60 voxels * 0.5m = 30m.
@export var max_building_height_vox: int = 60
@export var floor_height_vox: int = 3
@export var voxel_size: float = 0.5
@export var cell_size: int = 10

var _rng := RandomNumberGenerator.new()
var _brush: CityBrush
var _planner: DistrictPlanner


func generate(tool: VoxelTool, seed_value: int = -1) -> void:
	if seed_value >= 0:
		city_seed = seed_value
	_rng.seed = city_seed
	_brush = CityBrushScript.new(tool)

	_brush.fill_box(
		Vector3i(0, 0, 0),
		Vector3i(size_xz, max_building_height_vox + 8, size_xz),
		VoxelMaterial.AIR
	)
	_brush.fill_box(
		Vector3i(0, 0, 0),
		Vector3i(size_xz, ground_thickness, size_xz),
		VoxelMaterial.BEDROCK
	)

	_planner = DistrictPlannerScript.new()
	_planner.build(size_xz, city_seed, cell_size)

	var plaza := PlazaComposerScript.new()
	plaza.brush = _brush
	plaza.rng = _rng
	plaza.ground_y = ground_thickness

	var park := ParkComposerScript.new()
	park.brush = _brush
	park.rng = _rng
	park.ground_y = ground_thickness

	var grammar := BuildingGrammarScript.new()
	grammar.brush = _brush
	grammar.rng = _rng
	grammar.floor_height = maxi(floor_height_vox, 4)
	grammar.ground_floor_height = 5
	grammar.max_height = max_building_height_vox
	grammar.park = park

	var cells := _planner.cells
	for cz in range(cells):
		for cx in range(cells):
			var tag := _planner.tag_at(cx, cz)
			var min_v := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
			var max_v := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
			match tag:
				LandUse.AVENUE:
					_paint_avenue_cell(min_v, max_v, cx, cz)
				LandUse.ROAD:
					_paint_road_cell(min_v, max_v, cx, cz)
				LandUse.PLAZA:
					_paint_plaza_cell(min_v, max_v, cx, cz, plaza)
				LandUse.PARK:
					_paint_park_cell(min_v, max_v, cx, cz, park)
				_:
					_paint_lot(min_v, max_v, cx, cz, tag, grammar)

	_brush = null
	_planner = null


func build_ped_roadmap(tool: VoxelTool, stride: int = 2) -> PedRoadMap:
	var map: PedRoadMap = PedRoadMapScript.new()
	map.build_from_district(tool, size_xz, ground_thickness, voxel_size, stride)
	return map


func collect_walkable_world_positions(tool: VoxelTool, stride: int = 2) -> PackedVector3Array:
	return build_ped_roadmap(tool, stride).positions


func find_spawn_world(tool: VoxelTool) -> Vector3:
	_brush = CityBrushScript.new(tool)
	var vs := voxel_size
	var cx := size_xz / 2
	var cz := size_xz / 2
	for radius in range(0, size_xz / 2, 2):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius and radius > 0:
					continue
				var x := cx + dx
				var z := cz + dz
				if x < 1 or z < 1 or x >= size_xz - 1 or z >= size_xz - 1:
					continue
				var mat := _brush.get_vox(Vector3i(x, ground_thickness, z))
				if VoxelMaterial.is_walkable_surface(mat):
					if (
						_brush.get_vox(Vector3i(x, ground_thickness + 1, z)) == VoxelMaterial.AIR
						and _brush.get_vox(Vector3i(x, ground_thickness + 2, z)) == VoxelMaterial.AIR
					):
						_brush = null
						return Vector3(
							(float(x) + 0.5) * vs,
							float(ground_thickness + 1) * vs,
							(float(z) + 0.5) * vs
						)
	_brush = null
	return Vector3(float(cx) * vs, 2.0, float(cz) * vs)


func _paint_road_cell(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int) -> void:
	_brush.fill_box(min_v, max_v, VoxelMaterial.ASPHALT)
	_paint_curbs(min_v, max_v)
	_paint_lane_if_straight(min_v, max_v, cx, cz, false)
	_paint_crosswalks(min_v, max_v, cx, cz)


func _paint_avenue_cell(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int) -> void:
	_brush.fill_box(min_v, max_v, VoxelMaterial.ASPHALT)
	_paint_curbs(min_v, max_v)
	# Center median planter
	var mx := (min_v.x + max_v.x) / 2
	var mz := (min_v.z + max_v.z) / 2
	var horiz := LandUse.is_road(_planner.tag_at(cx - 1, cz)) and LandUse.is_road(_planner.tag_at(cx + 1, cz))
	if horiz:
		_brush.fill_box(
			Vector3i(min_v.x, ground_thickness, mz),
			Vector3i(max_v.x, ground_thickness + 1, mz + 1),
			VoxelMaterial.PLANTER
		)
		for x in range(min_v.x + 2, max_v.x - 2, 3):
			_brush.set_vox(Vector3i(x, ground_thickness + 1, mz), VoxelMaterial.PARK)
	else:
		_brush.fill_box(
			Vector3i(mx, ground_thickness, min_v.z),
			Vector3i(mx + 1, ground_thickness + 1, max_v.z),
			VoxelMaterial.PLANTER
		)
		for z in range(min_v.z + 2, max_v.z - 2, 3):
			_brush.set_vox(Vector3i(mx, ground_thickness + 1, z), VoxelMaterial.PARK)
	_paint_lane_if_straight(min_v, max_v, cx, cz, true)
	_paint_crosswalks(min_v, max_v, cx, cz)


func _paint_curbs(min_v: Vector3i, max_v: Vector3i) -> void:
	var y := ground_thickness
	for z in range(min_v.z, max_v.z):
		_brush.set_vox(Vector3i(min_v.x, y, z), VoxelMaterial.CURB)
		_brush.set_vox(Vector3i(max_v.x - 1, y, z), VoxelMaterial.CURB)
	for x in range(min_v.x, max_v.x):
		_brush.set_vox(Vector3i(x, y, min_v.z), VoxelMaterial.CURB)
		_brush.set_vox(Vector3i(x, y, max_v.z - 1), VoxelMaterial.CURB)


func _paint_lane_if_straight(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, avenue: bool) -> void:
	if not avenue and _rng.randf() > 0.35:
		return
	var y := ground_thickness
	var horiz := LandUse.is_road(_planner.tag_at(cx - 1, cz)) or LandUse.is_road(_planner.tag_at(cx + 1, cz))
	var vert := LandUse.is_road(_planner.tag_at(cx, cz - 1)) or LandUse.is_road(_planner.tag_at(cx, cz + 1))
	if horiz and not vert:
		var mz := (min_v.z + max_v.z) / 2
		for x in range(min_v.x + 1, max_v.x - 1):
			if (x % 3) == 0:
				_brush.set_vox(Vector3i(x, y, mz), VoxelMaterial.ROAD_LINE)
	elif vert and not horiz:
		var mx := (min_v.x + max_v.x) / 2
		for z in range(min_v.z + 1, max_v.z - 1):
			if (z % 3) == 0:
				_brush.set_vox(Vector3i(mx, y, z), VoxelMaterial.ROAD_LINE)


func _paint_crosswalks(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int) -> void:
	# At intersections with plaza/park entries.
	var near_open := false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := _planner.tag_at(cx + dx, cz + dz)
			if t == LandUse.PLAZA or t == LandUse.PARK:
				near_open = true
	var intersection := false
	var roads := 0
	if LandUse.is_road(_planner.tag_at(cx - 1, cz)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx + 1, cz)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx, cz - 1)):
		roads += 1
	if LandUse.is_road(_planner.tag_at(cx, cz + 1)):
		roads += 1
	intersection = roads >= 3
	if not near_open and not intersection:
		return
	var y := ground_thickness
	for i in range(min_v.x + 2, max_v.x - 2):
		if (i % 2) == 0:
			_brush.set_vox(Vector3i(i, y, min_v.z + 1), VoxelMaterial.CROSSWALK)
			_brush.set_vox(Vector3i(i, y, max_v.z - 2), VoxelMaterial.CROSSWALK)
	for i in range(min_v.z + 2, max_v.z - 2):
		if (i % 2) == 0:
			_brush.set_vox(Vector3i(min_v.x + 1, y, i), VoxelMaterial.CROSSWALK)
			_brush.set_vox(Vector3i(max_v.x - 2, y, i), VoxelMaterial.CROSSWALK)


func _paint_plaza_cell(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, plaza: PlazaComposer
) -> void:
	# Only the "anchor" cell of a contiguous plaza blob runs the full composer;
	# other plaza cells just pave (composer already covers multi-cell if we expand).
	# Simpler: each plaza cell gets paving; fountain only on cells near footprint center.
	var in_grand := _planner.grand_plaza.has_point(Vector2i(cx, cz))
	if in_grand:
		# Expand compose once per grand plaza using full rect in voxel space.
		if cx == _planner.grand_plaza.position.x and cz == _planner.grand_plaza.position.y:
			var g := _planner.grand_plaza
			var gmin := Vector3i(g.position.x * cell_size, ground_thickness, g.position.y * cell_size)
			var gmax := Vector3i(g.end.x * cell_size, ground_thickness + 1, g.end.y * cell_size)
			plaza.compose_grand(gmin, gmax)
		return
	for s in _planner.satellite_plazas:
		if s.has_point(Vector2i(cx, cz)):
			if cx == s.position.x and cz == s.position.y:
				var smin := Vector3i(s.position.x * cell_size, ground_thickness, s.position.y * cell_size)
				var smax := Vector3i(s.end.x * cell_size, ground_thickness + 1, s.end.y * cell_size)
				plaza.compose_satellite(smin, smax)
			return
	# Fallback single cell
	plaza.compose_satellite(min_v, max_v)


func _paint_park_cell(
	min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, park: ParkComposer
) -> void:
	var lp := _planner.large_park
	if lp.size.x > 0 and lp.has_point(Vector2i(cx, cz)):
		if cx == lp.position.x and cz == lp.position.y:
			var pmin := Vector3i(lp.position.x * cell_size, ground_thickness, lp.position.y * cell_size)
			var pmax := Vector3i(lp.end.x * cell_size, ground_thickness + 1, lp.end.y * cell_size)
			park.compose_large(pmin, pmax)
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
	_brush.fill_box(min_v, max_v, VoxelMaterial.SIDEWALK)
	var bmin := min_v + Vector3i(1, 0, 1)
	var bmax := max_v - Vector3i(1, 0, 1)
	if bmax.x - bmin.x < 3 or bmax.z - bmin.z < 3:
		return
	var facing := _planner.street_facing(cx, cz)
	var corner := _planner.is_corner_lot(cx, cz)
	var on_plaza := _planner.faces_plaza(cx, cz)
	var on_park := _planner.faces_park(cx, cz)
	grammar.build_for_zone(bmin, bmax, zone, facing, corner, on_plaza, on_park)
