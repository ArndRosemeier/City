## Procedural district: planner → plazas/parks → building grammars → VoxelTool.
class_name DistrictGenerator
extends RefCounted

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CarRoadMapScript := preload("res://scripts/city/car_roadmap.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const PlazaComposerScript := preload("res://scripts/city/plaza_composer.gd")
const ParkComposerScript := preload("res://scripts/city/park_composer.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

@export var city_seed: int = 42
## Rectangular district in voxels (0.5 m each). Default 640×448 → 320×224 m.
@export var size_x: int = 640
@export var size_z: int = 448
## Kept for older callers; equals max(size_x, size_z).
@export var size_xz: int = 640
@export var ground_thickness: int = 1
## 200 voxels * 0.5 m = 100 m.
@export var max_building_height_vox: int = 200
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
	size_xz = maxi(size_x, size_z)
	_brush = CityBrushScript.new(tool)

	_brush.fill_box(
		Vector3i(0, 0, 0),
		Vector3i(size_x, max_building_height_vox + 8, size_z),
		VoxelMaterial.AIR
	)
	_brush.fill_box(
		Vector3i(0, 0, 0),
		Vector3i(size_x, ground_thickness, size_z),
		VoxelMaterial.BEDROCK
	)

	_planner = DistrictPlannerScript.new()
	_planner.build(size_x, size_z, city_seed, cell_size)

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

	for cz in range(_planner.cells_z):
		for cx in range(_planner.cells_x):
			var tag := _planner.tag_at(cx, cz)
			var min_v := Vector3i(cx * cell_size, ground_thickness, cz * cell_size)
			var max_v := Vector3i((cx + 1) * cell_size, ground_thickness + 1, (cz + 1) * cell_size)
			match tag:
				LandUse.AVENUE:
					_paint_street_cell(min_v, max_v, cx, cz, true)
				LandUse.ROAD:
					_paint_street_cell(min_v, max_v, cx, cz, false)
				LandUse.PLAZA:
					_paint_plaza_cell(min_v, max_v, cx, cz, plaza)
				LandUse.PARK:
					_paint_park_cell(min_v, max_v, cx, cz, park)
				_:
					_paint_lot(min_v, max_v, cx, cz, tag, grammar)

	_brush = null


func get_planner() -> DistrictPlanner:
	return _planner


func build_ped_roadmap(tool: VoxelTool, stride: int = 2) -> PedRoadMap:
	var map: PedRoadMap = PedRoadMapScript.new()
	map.build_from_district(tool, size_x, size_z, ground_thickness, voxel_size, stride)
	return map


func build_car_roadmap(tool: VoxelTool, stride: int = 2) -> CarRoadMap:
	var map: CarRoadMap = CarRoadMapScript.new()
	map.build_from_district(tool, size_x, size_z, ground_thickness, voxel_size, stride)
	return map


func collect_walkable_world_positions(tool: VoxelTool, stride: int = 2) -> PackedVector3Array:
	return build_ped_roadmap(tool, stride).positions


func find_spawn_world(tool: VoxelTool) -> Vector3:
	## Feet slightly above the top of the ground voxel so we don't clip/tunnel.
	_brush = CityBrushScript.new(tool)
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
				if VoxelMaterial.is_walkable_surface(mat):
					if (
						_brush.get_vox(Vector3i(x, ground_thickness + 1, z)) == VoxelMaterial.AIR
						and _brush.get_vox(Vector3i(x, ground_thickness + 2, z)) == VoxelMaterial.AIR
						and _brush.get_vox(Vector3i(x, ground_thickness + 3, z)) == VoxelMaterial.AIR
					):
						_brush = null
						return Vector3((float(x) + 0.5) * vs, spawn_y, (float(z) + 0.5) * vs)
	_brush = null
	return Vector3(float(cx) * vs, spawn_y, float(cz) * vs)


func _paint_street_cell(min_v: Vector3i, max_v: Vector3i, cx: int, cz: int, avenue: bool) -> void:
	## Sidewalk corridors on both sides, curb step, asphalt carriageway.
	var y := ground_thickness
	var horiz := LandUse.is_road(_planner.tag_at(cx - 1, cz)) or LandUse.is_road(_planner.tag_at(cx + 1, cz))
	var vert := LandUse.is_road(_planner.tag_at(cx, cz - 1)) or LandUse.is_road(_planner.tag_at(cx, cz + 1))
	var intersection := horiz and vert

	# Base fill sidewalk so edges connect to lots.
	_brush.fill_box(min_v, max_v, VoxelMaterial.SIDEWALK)

	var sw := 2  # sidewalk depth
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

	if avenue and not intersection:
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
			_brush.set_vox(Vector3i(x, y + 1, mz), VoxelMaterial.PARK)
	else:
		var mx := (min_v.x + max_v.x) / 2
		for z in range(min_v.z + 3, max_v.z - 3, 4):
			_brush.set_vox(Vector3i(mx, y, z), VoxelMaterial.PLANTER)
			_brush.set_vox(Vector3i(mx, y + 1, z), VoxelMaterial.PARK)


func _should_crosswalk(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := _planner.tag_at(cx + dx, cz + dz)
			if t == LandUse.PLAZA or t == LandUse.PARK:
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
	var sw := 2
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
	var in_grand := _planner.grand_plaza.has_point(Vector2i(cx, cz))
	if in_grand:
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
	# Zone-based height caps (meters → vox via grammar.max_height).
	var saved := grammar.max_height
	match zone:
		LandUse.CORE_LOT, LandUse.CIVIC_LOT:
			grammar.max_height = max_building_height_vox
		LandUse.MID_LOT:
			grammar.max_height = mini(saved, 120)  # 60 m
		LandUse.TOWN_LOT:
			grammar.max_height = mini(saved, 80)  # 40 m
		LandUse.COURTYARD_LOT:
			grammar.max_height = mini(saved, 72)
		_:
			pass
	var facing := _planner.street_facing(cx, cz)
	var corner := _planner.is_corner_lot(cx, cz)
	var on_plaza := _planner.faces_plaza(cx, cz)
	var on_park := _planner.faces_park(cx, cz)
	grammar.build_for_zone(bmin, bmax, zone, facing, corner, on_plaza, on_park)
	grammar.max_height = saved
