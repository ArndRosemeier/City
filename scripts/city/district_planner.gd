## Seeded land-use grid: organic avenues/streets, plazas, parks, zones (rectangular).
class_name DistrictPlanner
extends RefCounted

const WorldArterialsScript := preload("res://scripts/city/world_arterials.gd")

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
var civic_lot: Vector2i = Vector2i(-1, -1)
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

	_stamp_world_arterials(district_coord)
	_stamp_organic_interior_roads()
	_stamp_grand_plaza()
	_stamp_satellite_plazas()
	_stamp_large_park()
	_stamp_pocket_parks()
	_assign_zones()
	_place_civic()
	_collect_avenue_lights()


## Backward-compatible alias used by older call sites.
func build_square(size_xz: int, seed_value: int, p_cell_size: int = 28) -> void:
	build(size_xz, size_xz, seed_value, p_cell_size)


func tag_at(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return LandUse.ROAD
	return int(grid[cz][cx])


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
			if tag_at(cx + dx, cz + dz) == LandUse.PARK:
				return true
	return false


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
