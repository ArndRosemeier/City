## Seeded land-use grid: avenues, streets, plazas, parks, building zones.
class_name DistrictPlanner
extends RefCounted

var cell_size: int = 10
var cells: int = 0
## grid[z][x] = LandUse tag
var grid: Array = []
var grand_plaza: Rect2i = Rect2i()
var satellite_plazas: Array[Rect2i] = []
var large_park: Rect2i = Rect2i()
var pocket_parks: Array[Vector2i] = []
var civic_lot: Vector2i = Vector2i(-1, -1)

var _rng := RandomNumberGenerator.new()


func build(size_xz: int, seed_value: int, p_cell_size: int = 10) -> void:
	cell_size = p_cell_size
	cells = size_xz / cell_size
	_rng.seed = seed_value
	grid.clear()
	grid.resize(cells)
	for z in range(cells):
		var row: Array = []
		row.resize(cells)
		row.fill(LandUse.LOT)
		grid[z] = row
	satellite_plazas.clear()
	pocket_parks.clear()
	civic_lot = Vector2i(-1, -1)

	_stamp_avenues_and_roads()
	_stamp_grand_plaza()
	_stamp_satellite_plazas()
	_stamp_large_park()
	_stamp_pocket_parks()
	_assign_zones()
	_place_civic()


func tag_at(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= cells or cz >= cells:
		return LandUse.ROAD
	return int(grid[cz][cx])


func is_corner_lot(cx: int, cz: int) -> bool:
	var road_n := 0
	if cz + 1 < cells and LandUse.is_road(tag_at(cx, cz + 1)):
		road_n += 1
	if cz - 1 >= 0 and LandUse.is_road(tag_at(cx, cz - 1)):
		road_n += 1
	if cx + 1 < cells and LandUse.is_road(tag_at(cx + 1, cz)):
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
	if cz + 1 < cells and LandUse.is_road(tag_at(cx, cz + 1)):
		return 0
	if cz - 1 >= 0 and LandUse.is_road(tag_at(cx, cz - 1)):
		return 1
	if cx + 1 < cells and LandUse.is_road(tag_at(cx + 1, cz)):
		return 2
	if cx - 1 >= 0 and LandUse.is_road(tag_at(cx - 1, cz)):
		return 3
	return _rng.randi() % 4


func _stamp_avenues_and_roads() -> void:
	# Primary avenues every 8 cells (wider corridors = double cell later at paint).
	for i in range(0, cells, 8):
		for j in range(cells):
			grid[i][j] = LandUse.AVENUE
			grid[j][i] = LandUse.AVENUE
	# Secondary streets every 4 cells (skip avenues).
	for i in range(0, cells, 4):
		if i % 8 == 0:
			continue
		for j in range(cells):
			if grid[i][j] != LandUse.AVENUE:
				grid[i][j] = LandUse.ROAD
			if grid[j][i] != LandUse.AVENUE:
				grid[j][i] = LandUse.ROAD
	# A few irregular streets.
	for _k in range(3):
		var extra := _rng.randi_range(2, cells - 3)
		if extra % 4 == 0:
			continue
		if _rng.randf() < 0.5:
			for j in range(cells):
				if not LandUse.is_road(grid[extra][j]):
					grid[extra][j] = LandUse.ROAD
		else:
			for j in range(cells):
				if not LandUse.is_road(grid[j][extra]):
					grid[j][extra] = LandUse.ROAD


func _stamp_grand_plaza() -> void:
	var px := cells / 2 - 2
	var pz := cells / 2 - 2
	var w := 5
	var h := 5
	grand_plaza = Rect2i(px, pz, w, h)
	_fill_rect(grand_plaza, LandUse.PLAZA, true)


func _stamp_satellite_plazas() -> void:
	var candidates: Array[Vector2i] = [
		Vector2i(cells / 4, cells / 4),
		Vector2i(3 * cells / 4, cells / 4),
		Vector2i(cells / 4, 3 * cells / 4),
		Vector2i(3 * cells / 4, 3 * cells / 4),
	]
	candidates.shuffle()
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
	# Off-center park so the map is not perfectly symmetric.
	var ox := 3 + _rng.randi() % maxi(1, cells / 3)
	var oz := cells / 2 + _rng.randi_range(-2, 4)
	if _rng.randf() < 0.5:
		ox = cells - ox - 6
	var r := Rect2i(ox, oz, 6, 5)
	r = _clamp_rect(r)
	# Nudge away from grand plaza if overlapping.
	if r.intersects(grand_plaza):
		r.position.x = mini(r.position.x + 8, cells - r.size.x - 1)
	r = _clamp_rect(r)
	_fill_rect(r, LandUse.PARK, true)
	large_park = r


func _stamp_pocket_parks() -> void:
	var tries := 0
	while pocket_parks.size() < 5 and tries < 40:
		tries += 1
		var cx := _rng.randi_range(2, cells - 3)
		var cz := _rng.randi_range(2, cells - 3)
		if LandUse.is_road(tag_at(cx, cz)):
			continue
		if tag_at(cx, cz) == LandUse.PLAZA or tag_at(cx, cz) == LandUse.PARK:
			continue
		# Prefer mid/edge, not core center.
		var dist := absi(cx - cells / 2) + absi(cz - cells / 2)
		if dist < cells / 5:
			continue
		grid[cz][cx] = LandUse.PARK
		pocket_parks.append(Vector2i(cx, cz))


func _assign_zones() -> void:
	var cx0 := cells / 2
	var cz0 := cells / 2
	for z in range(cells):
		for x in range(cells):
			var t: int = grid[z][x]
			if t != LandUse.LOT:
				continue
			var d := maxi(absi(x - cx0), absi(z - cz0))
			if d <= 3:
				grid[z][x] = LandUse.CORE_LOT
			elif d <= 7:
				grid[z][x] = LandUse.MID_LOT if _rng.randf() < 0.7 else LandUse.COURTYARD_LOT
			elif d <= 12:
				grid[z][x] = LandUse.MID_LOT if _rng.randf() < 0.45 else LandUse.TOWN_LOT
			else:
				grid[z][x] = LandUse.TOWN_LOT if _rng.randf() < 0.75 else LandUse.COURTYARD_LOT


func _place_civic() -> void:
	# Civic lot on grand plaza edge.
	var edges: Array[Vector2i] = []
	for z in range(grand_plaza.position.y - 1, grand_plaza.end.y + 1):
		for x in range(grand_plaza.position.x - 1, grand_plaza.end.x + 1):
			if x < 1 or z < 1 or x >= cells - 1 or z >= cells - 1:
				continue
			if not LandUse.is_lot(tag_at(x, z)):
				continue
			if faces_plaza(x, z):
				edges.append(Vector2i(x, z))
	if edges.is_empty():
		return
	civic_lot = edges[_rng.randi() % edges.size()]
	grid[civic_lot.y][civic_lot.x] = LandUse.CIVIC_LOT


func _fill_rect(r: Rect2i, tag: int, skip_roads: bool) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or z < 0 or x >= cells or z >= cells:
				continue
			if skip_roads and LandUse.is_road(grid[z][x]):
				continue
			grid[z][x] = tag


func _clamp_rect(r: Rect2i) -> Rect2i:
	var x := clampi(r.position.x, 1, cells - 2)
	var z := clampi(r.position.y, 1, cells - 2)
	var w := mini(r.size.x, cells - 1 - x)
	var h := mini(r.size.y, cells - 1 - z)
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
