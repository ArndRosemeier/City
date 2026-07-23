## Procedural district: planner → plazas/parks → building grammars → VoxelTool.
class_name DistrictGenerator
extends RefCounted

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CarRoadMapScript := preload("res://scripts/city/car_roadmap.gd")
const StreetNavLayersScript := preload("res://scripts/city/street_nav_layers.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const PlazaComposerScript := preload("res://scripts/city/plaza_composer.gd")
const ParkComposerScript := preload("res://scripts/city/park_composer.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

@export var city_seed: int = 42
## Rectangular district in voxels (0.5 m each). Default 784×560 → 392×280 m.
@export var size_x: int = 784
@export var size_z: int = 560
## Kept for older callers; equals max(size_x, size_z).
@export var size_xz: int = 784
@export var ground_thickness: int = 1
## 200 voxels * 0.5 m = 100 m ceiling.
@export var max_building_height_vox: int = 200
## Typical residential floor-to-floor ≈ 3.0 m.
@export var floor_height_vox: int = 6
@export var voxel_size: float = 0.5
## Planner cell ≈ 14 m — mid-size city lot / street ROW (euro mid-rise depth).
@export var cell_size: int = 28

var _rng := RandomNumberGenerator.new()
var _brush: CityBrush
var _planner: DistrictPlanner
var _plaza: PlazaComposer
var _park: ParkComposer
var _grammar: BuildingGrammar
## World-space building massing for far LOD: {center, size, color}.
var building_impostors: Array = []


func generate(tool: VoxelTool, seed_value: int = -1) -> void:
	## One-shot stamp — requires the full district AABB to already be editable.
	begin_generate(tool, seed_value)
	paint_tile(0, 0, size_x, size_z)
	## Multi-cell plazas/parks must decorate *after* the cell loop: each paint_tile
	## cell clears its AABB to air first, which would wipe a compose done mid-loop.
	decorate_open_spaces()
	end_generate()


func begin_generate(tool: VoxelTool, seed_value: int = -1) -> void:
	if seed_value >= 0:
		city_seed = seed_value
	_rng.seed = city_seed
	size_xz = maxi(size_x, size_z)
	building_impostors.clear()
	_brush = CityBrushScript.new(tool)
	_planner = DistrictPlannerScript.new()
	_planner.build(size_x, size_z, city_seed, cell_size)

	_plaza = PlazaComposerScript.new()
	_plaza.brush = _brush
	_plaza.rng = _rng
	_plaza.ground_y = ground_thickness

	_park = ParkComposerScript.new()
	_park.brush = _brush
	_park.rng = _rng
	_park.ground_y = ground_thickness

	_grammar = BuildingGrammarScript.new()
	_grammar.brush = _brush
	_grammar.rng = _rng
	_grammar.floor_height = maxi(floor_height_vox, 6)
	_grammar.ground_floor_height = 8  # ~4.0 m retail / lobby
	_grammar.max_height = max_building_height_vox
	_grammar.park = _park


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
	var top := max_building_height_vox + 8
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var cmin := Vector3i(cx * cell_size, 0, cz * cell_size)
			var cmax := Vector3i((cx + 1) * cell_size, top, (cz + 1) * cell_size)
			_brush.fill_box(cmin, cmax, VoxelMaterial.AIR)
			_brush.fill_box(
				Vector3i(cmin.x, 0, cmin.z),
				Vector3i(cmax.x, ground_thickness, cmax.z),
				VoxelMaterial.BEDROCK
			)
			_paint_cell(cx, cz)


func decorate_open_spaces() -> void:
	## Fancy plaza/park pass — call only once the full feature AABBs are editable.
	if _brush == null or _planner == null or _plaza == null or _park == null:
		return
	var g := _planner.grand_plaza
	if g.size.x > 0:
		var gmin := Vector3i(g.position.x * cell_size, ground_thickness, g.position.y * cell_size)
		var gmax := Vector3i(g.end.x * cell_size, ground_thickness + 1, g.end.y * cell_size)
		_plaza.compose_grand(gmin, gmax)
	for s in _planner.satellite_plazas:
		var smin := Vector3i(s.position.x * cell_size, ground_thickness, s.position.y * cell_size)
		var smax := Vector3i(s.end.x * cell_size, ground_thickness + 1, s.end.y * cell_size)
		_plaza.compose_satellite(smin, smax)
	var lp := _planner.large_park
	if lp.size.x > 0:
		var pmin := Vector3i(lp.position.x * cell_size, ground_thickness, lp.position.y * cell_size)
		var pmax := Vector3i(lp.end.x * cell_size, ground_thickness + 1, lp.end.y * cell_size)
		_park.compose_large(pmin, pmax)


func open_space_bounds() -> Array[AABB]:
	## Voxel-space AABBs that decorate_open_spaces() will write (for streaming waits).
	var out: Array[AABB] = []
	if _planner == null:
		return out
	var y0 := float(ground_thickness)
	var yh := 12.0
	var g := _planner.grand_plaza
	if g.size.x > 0:
		out.append(
			AABB(
				Vector3(g.position.x * cell_size, y0, g.position.y * cell_size),
				Vector3(g.size.x * cell_size, yh, g.size.y * cell_size)
			)
		)
	for s in _planner.satellite_plazas:
		out.append(
			AABB(
				Vector3(s.position.x * cell_size, y0, s.position.y * cell_size),
				Vector3(s.size.x * cell_size, yh, s.size.y * cell_size)
			)
		)
	var lp := _planner.large_park
	if lp.size.x > 0:
		out.append(
			AABB(
				Vector3(lp.position.x * cell_size, y0, lp.position.y * cell_size),
				Vector3(lp.size.x * cell_size, yh, lp.size.y * cell_size)
			)
		)
	return out


func end_generate() -> void:
	_brush = null
	_plaza = null
	_park = null
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
		_:
			_paint_lot(min_v, max_v, cx, cz, tag, _grammar)


func get_planner() -> DistrictPlanner:
	return _planner


func build_street_nav(tool: VoxelTool) -> StreetNavLayers:
	if _planner == null:
		push_error("DistrictGenerator.build_street_nav: planner missing — call generate() first")
		return null
	var layers: StreetNavLayers = StreetNavLayersScript.new()
	layers.build(_planner, tool, cell_size, ground_thickness, voxel_size)
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
	_brush.fill_box(min_v, max_v, VoxelMaterial.SIDEWALK)

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
	_brush.fill_box(min_v, max_v, VoxelMaterial.PLAZA)
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
	_brush.fill_box(min_v, max_v, VoxelMaterial.SIDEWALK)
	# Small private setback (~0.5–1.0 m) — footprint stays ~12–13 m on a 14 m lot.
	var ring := 1 if cell_size < 20 else 2
	var bmin := min_v + Vector3i(ring, 0, ring)
	var bmax := max_v - Vector3i(ring, 0, ring)
	if bmax.x - bmin.x < 6 or bmax.z - bmin.z < 6:
		return
	# Zone-based height caps (meters → vox via grammar.max_height). 100 m ceiling in core.
	var saved := grammar.max_height
	match zone:
		LandUse.CORE_LOT, LandUse.CIVIC_LOT:
			grammar.max_height = max_building_height_vox
		LandUse.MID_LOT:
			grammar.max_height = mini(saved, 120)  # 60 m
		LandUse.TOWN_LOT:
			grammar.max_height = mini(saved, 80)  # 40 m
		LandUse.COURTYARD_LOT:
			grammar.max_height = mini(saved, 72)  # 36 m
		_:
			pass
	var facing := _planner.street_facing(cx, cz)
	var corner := _planner.is_corner_lot(cx, cz)
	var on_plaza := _planner.faces_plaza(cx, cz)
	var on_park := _planner.faces_park(cx, cz)
	grammar.build_for_zone(bmin, bmax, zone, facing, corner, on_plaza, on_park)
	# Approximate massing height for far LOD (zone caps overshoot actual floors a bit — fine for shells).
	var mass_h := grammar.max_height
	match zone:
		LandUse.CORE_LOT:
			mass_h = grammar.max_height
		LandUse.CIVIC_LOT:
			mass_h = mini(grammar.max_height, 48)
		LandUse.MID_LOT:
			mass_h = int(float(grammar.max_height) * 0.55)
		LandUse.TOWN_LOT:
			mass_h = 28
		LandUse.COURTYARD_LOT:
			mass_h = 40
		_:
			mass_h = mini(grammar.max_height, 48)
	_record_building_impostor(bmin, bmax, mass_h, zone)
	grammar.max_height = saved


func _record_building_impostor(bmin: Vector3i, bmax: Vector3i, height_vox: int, zone: int) -> void:
	var vs := voxel_size
	var w := float(bmax.x - bmin.x) * vs
	var d := float(bmax.z - bmin.z) * vs
	var h := float(maxi(height_vox, 8)) * vs
	var center := Vector3(
		(float(bmin.x) + float(bmax.x)) * 0.5 * vs,
		float(bmin.y) * vs + h * 0.5,
		(float(bmin.z) + float(bmax.z)) * 0.5 * vs
	)
	var color := Color(0.62, 0.58, 0.52)
	match zone:
		LandUse.CORE_LOT:
			color = Color(0.55, 0.58, 0.62)
		LandUse.CIVIC_LOT:
			color = Color(0.72, 0.70, 0.66)
		LandUse.MID_LOT:
			color = Color(0.66, 0.48, 0.40)
		LandUse.TOWN_LOT:
			color = Color(0.70, 0.55, 0.42)
		LandUse.COURTYARD_LOT:
			color = Color(0.58, 0.52, 0.46)
		_:
			pass
	building_impostors.append({
		"center": center,
		"size": Vector3(w, h, d),
		"color": color,
	})
