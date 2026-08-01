## District identity check.
##
## Runs as a scene (not --script) because the city scripts reference the CityProfiler
## autoload, which only exists in a normal project run.
##
## Part 1 bakes nine district tiles off the world seed and reports theme, zoning,
## skyline height, park count and wall-material histogram per tile, asserting the
## themes are deterministic and actually produce different cities.
## Part 2 boots the live city, prints pedestrian / vehicle spawn counts so the new
## zoning cannot silently starve the nav graph, and saves street + skyline shots.
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")

const WORLD_SEED := 42
const COORDS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(2, 0),
	Vector2i(0, 2),
	Vector2i(2, 2),
	Vector2i(3, 1),
	Vector2i(1, 3),
]
## Count every voxel: ground surfaces like paths and ponds occupy a single y layer, and
## a strided scan walked right past it (y is the fastest-varying axis in a block).
const SAMPLE_STRIDE := 1
## Materials that carry a district's architectural look.
const WALL_IDS: Array[int] = [
	VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK, VoxelMaterial.PLASTER,
	VoxelMaterial.CONCRETE, VoxelMaterial.STONE, VoxelMaterial.METAL,
	VoxelMaterial.METAL_PLATE, VoxelMaterial.ROOF, VoxelMaterial.ROOF_CLAY,
]
## Park content: paths, planting, pond. All-lawn parks used to slip through unnoticed.
const PARK_IDS: Array[int] = [
	VoxelMaterial.GRAVEL, VoxelMaterial.LEAVES, VoxelMaterial.WATER, VoxelMaterial.PAINT,
]
## Hill massing: rock strata + planting. Counted separately from park furniture.
const HILL_IDS: Array[int] = [
	VoxelMaterial.STONE, VoxelMaterial.DIRT, VoxelMaterial.BRICK, VoxelMaterial.BRICK_DARK,
	VoxelMaterial.CONCRETE, VoxelMaterial.GRAVEL, VoxelMaterial.LEAVES,
]
## Graveyard kit: monuments, plots, aisles, yew. Its palette shares nothing with
## the urban themes, so it needs its own bucket in the histogram.
const GRAVEYARD_IDS: Array[int] = [
	VoxelMaterial.GRAVE_STONE, VoxelMaterial.GRAVE_MARBLE, VoxelMaterial.GRAVE_SOIL,
	VoxelMaterial.GRAVE_PATH, VoxelMaterial.WROUGHT_IRON, VoxelMaterial.YEW,
]
## Castle kit: the plinth, curtain and towers are all dressed ashlar.
const CASTLE_IDS: Array[int] = [
	VoxelMaterial.CASTLE_BLOCK, VoxelMaterial.CASTLE_BLOCK_MOSSY,
]
const ARENA_IDS: Array[int] = [
	VoxelMaterial.ARENA_SHELL,
]
const STREET_PNG := "res://tools/city_theme_street.png"
const SKYLINE_PNG := "res://tools/city_theme_skyline.png"
const NEIGHBOUR_PNG := "res://tools/city_theme_neighbour.png"

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_determinism()
	_check_spread()
	var stats := await _bake_all()
	_check_bake_differences(stats)
	_check_parks(stats)
	await _live_city_report()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _check_determinism() -> void:
	for coord in COORDS:
		var a := DistrictTheme.for_district(WORLD_SEED, coord)
		var b := DistrictTheme.for_district(WORLD_SEED, coord)
		if a.id != b.id:
			_fail("FAIL theme not deterministic at %s: %d vs %d" % [coord, a.id, b.id])
			return
	## Zoning must also be reproducible: two planners, same seed, same grid.
	var coord0 := Vector2i(2, 1)
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord0)
	var p1: DistrictPlanner = DistrictPlannerScript.new()
	p1.theme = DistrictTheme.for_district(WORLD_SEED, coord0)
	p1.build(DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord0)
	var p2: DistrictPlanner = DistrictPlannerScript.new()
	p2.theme = DistrictTheme.for_district(WORLD_SEED, coord0)
	p2.build(DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord0)
	for z in range(p1.cells_z):
		for x in range(p1.cells_x):
			if p1.tag_at(x, z) != p2.tag_at(x, z):
				_fail("FAIL zoning not deterministic at cell (%d,%d)" % [x, z])
				return
			if not is_equal_approx(p1.intensity_at(x, z), p2.intensity_at(x, z)):
				_fail("FAIL intensity not deterministic at cell (%d,%d)" % [x, z])
				return
	print("OK deterministic themes + zoning")


func _check_spread() -> void:
	## Across a 7x7 block of tiles every theme should show up, and the world origin
	## must always be the high-rise core.
	var seen: Dictionary = {}
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var t := DistrictTheme.for_district(WORLD_SEED, Vector2i(cx, cz))
			seen[t.id] = int(seen.get(t.id, 0)) + 1
	if DistrictTheme.for_district(WORLD_SEED, Vector2i.ZERO).id != DistrictTheme.CORE_HIGHRISE:
		_fail("FAIL world origin is not the core district")
		return
	if seen.size() < 4:
		_fail("FAIL only %d themes across 49 tiles" % seen.size())
		return
	var parts: Array[String] = []
	for id: Variant in seen.keys():
		parts.append("%s=%d" % [DistrictTheme.make(int(id)).display_name, int(seen[id])])
	parts.sort()
	print("OK theme spread over 49 tiles: %s" % ", ".join(parts))


func _bake_all() -> Array:
	var out: Array = []
	for coord in COORDS:
		var t0 := Time.get_ticks_msec()
		var res: Dictionary = DistrictBakeJobScript.bake({
			"coord": coord,
			"world_seed": WORLD_SEED,
		})
		if not bool(res.get("ok", false)):
			_fail("FAIL bake %s: %s" % [coord, res.get("error", "?")])
			return out
		var stat := _summarize(coord, res)
		stat["bake_ms"] = Time.get_ticks_msec() - t0
		out.append(stat)
		_print_stat(stat)
		await get_tree().process_frame
	return out


func _summarize(coord: Vector2i, res: Dictionary) -> Dictionary:
	var planner: DistrictPlanner = res["planner"]
	var gen: DistrictGenerator = res["generator"]
	var tags: Dictionary = {}
	var intensity_sum := 0.0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			tags[tag] = int(tags.get(tag, 0)) + 1
			intensity_sum += planner.intensity_at(x, z)
	var cells := float(planner.cells_x * planner.cells_z)

	var top_m := 0.0
	for imp: Variant in gen.building_impostors:
		var d: Dictionary = imp
		var center: Vector3 = d["center"]
		var size: Vector3 = d["size"]
		top_m = maxf(top_m, center.y + size.y * 0.5)

	return {
		"coord": coord,
		"theme_id": int(res["theme_id"]),
		"theme": String(res["theme_name"]),
		"core_cells": int(tags.get(LandUse.CORE_LOT, 0)),
		"mid_cells": int(tags.get(LandUse.MID_LOT, 0)),
		"town_cells": int(tags.get(LandUse.TOWN_LOT, 0)),
		"court_cells": int(tags.get(LandUse.COURTYARD_LOT, 0)),
		"park_cells": int(tags.get(LandUse.PARK, 0)),
		"hill_cells": int(tags.get(LandUse.HILL, 0)),
		"graveyard_cells": int(tags.get(LandUse.GRAVEYARD, 0)),
		"lake_cells": int(tags.get(LandUse.LAKE, 0)),
		"castle_cells": int(tags.get(LandUse.CASTLE, 0)),
		"arena_cells": int(tags.get(LandUse.ARENA, 0)),
		"zoo_cells": int(tags.get(LandUse.ZOO, 0)),
		"road_cells": int(tags.get(LandUse.ROAD, 0)) + int(tags.get(LandUse.AVENUE, 0)),
		"lot_cells": (
			int(tags.get(LandUse.CORE_LOT, 0))
			+ int(tags.get(LandUse.MID_LOT, 0))
			+ int(tags.get(LandUse.TOWN_LOT, 0))
			+ int(tags.get(LandUse.COURTYARD_LOT, 0))
			+ int(tags.get(LandUse.CIVIC_LOT, 0))
		),
		"mean_intensity": intensity_sum / cells,
		"top_m": top_m,
		"walls": _material_histogram(res["blocks"], int(res["ground_thickness"])),
	}


## Voxels per 16³ block edge, and the block index layout used by the native volume.
const BLOCK := 16


func _material_histogram(blocks: Dictionary, ground_thickness: int) -> Dictionary:
	## One stride-sampled pass over the baked voxels for both wall and park materials.
	##
	## Everything below the street deck is skipped. The substrate under the deck is
	## STONE, which is also a legitimate wall material — counting it made STONE the
	## "dominant wall" of every district by two orders of magnitude and hid the real
	## per-theme palette completely.
	var counts: Dictionary = {}
	for id: int in WALL_IDS:
		counts[id] = 0
	for id2: int in PARK_IDS:
		counts[id2] = 0
	for id3: int in HILL_IDS:
		if not counts.has(id3):
			counts[id3] = 0
	for id4: int in GRAVEYARD_IDS:
		if not counts.has(id4):
			counts[id4] = 0
	for id5: int in CASTLE_IDS:
		if not counts.has(id5):
			counts[id5] = 0
	for id6: int in ARENA_IDS:
		if not counts.has(id6):
			counts[id6] = 0
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= ground_thickness:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			var uid := int(data[0])
			if counts.has(uid):
				## Only the layers of this block that sit at or above the deck.
				var layers := mini(BLOCK, block_y0 + BLOCK - ground_thickness)
				counts[uid] = int(counts[uid]) + layers * BLOCK * BLOCK / SAMPLE_STRIDE
			continue
		var voxels := data.size() / 2
		var i := 0
		while i < voxels:
			## Layout is y + x * BLOCK + z * BLOCK², so the low nibble is the local Y.
			if block_y0 + (i % BLOCK) >= ground_thickness:
				var vid := int(data[i * 2])
				if counts.has(vid):
					counts[vid] = int(counts[vid]) + 1
			i += SAMPLE_STRIDE
	return counts


func _dominant_wall(counts: Dictionary) -> int:
	var best := -1
	var best_n := -1
	for id: int in WALL_IDS:
		var n := int(counts[id])
		if n > best_n:
			best_n = n
			best = id
	return best


func _print_stat(s: Dictionary) -> void:
	var walls: Dictionary = s["walls"]
	var wall_parts: Array[String] = []
	for id: int in WALL_IDS:
		if int(walls[id]) > 0:
			wall_parts.append("%d:%d" % [int(id), int(walls[id])])
	print(
		(
			"%s %-22s core=%-3d mid=%-3d town=%-3d court=%-3d park=%-2d hill=%-3d"
			+ " gy=%-3d lots=%-3d road=%-3d int=%.2f top=%.0fm %dms"
		)
		% [
			s["coord"], s["theme"], s["core_cells"], s["mid_cells"], s["town_cells"],
			s["court_cells"], s["park_cells"], s["hill_cells"], s["graveyard_cells"],
			s["lot_cells"], s["road_cells"], s["mean_intensity"], s["top_m"], s["bake_ms"],
		]
	)
	print("    walls %s dominant=%d" % [" ".join(wall_parts), _dominant_wall(walls)])
	print(
		"    park paths=%d leaves=%d water=%d flowers=%d"
		% [
			int(walls[VoxelMaterial.GRAVEL]), int(walls[VoxelMaterial.LEAVES]),
			int(walls[VoxelMaterial.WATER]), int(walls[VoxelMaterial.PAINT]),
		]
	)


func _check_parks(stats: Array) -> void:
	## Parks have to be composed, not left as lawn: the streamed bake path once skipped
	## pocket parks entirely and every square came out an empty green rectangle.
	## Hill / Graveyard tiles are different open-space recipes (no urban parks).
	var ponds := 0
	var urban := 0
	var hills := 0
	var graveyards := 0
	var basins := 0
	var castles := 0
	var fractals := 0
	var arenas := 0
	var zoos := 0
	for s: Variant in stats:
		var d: Dictionary = s
		var m: Dictionary = d["walls"]
		if int(d["theme_id"]) == DistrictTheme.HILL:
			hills += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Hill district still has housing lots" % d["coord"])
				return
			if int(d["hill_cells"]) <= 0:
				_fail("FAIL %s Hill district has no hill cells" % d["coord"])
				return
			if int(m[VoxelMaterial.STONE]) <= 0 and int(m[VoxelMaterial.BRICK]) <= 0:
				_fail("FAIL %s Hill district has no rock mass" % d["coord"])
				return
			if int(m[VoxelMaterial.LEAVES]) <= 0:
				_fail("FAIL %s Hill district has no planting" % d["coord"])
				return
			continue
		if int(d["theme_id"]) == DistrictTheme.GRAVEYARD:
			graveyards += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Graveyard district still has housing lots" % d["coord"])
				return
			if int(d["graveyard_cells"]) <= 0:
				_fail("FAIL %s Graveyard district has no graveyard cells" % d["coord"])
				return
			if int(m[VoxelMaterial.STONE]) <= 0:
				_fail("FAIL %s Graveyard district has no stone mass" % d["coord"])
				return
			if int(m[VoxelMaterial.GRAVE_STONE]) <= 0:
				_fail("FAIL %s Graveyard district has no monuments / kerbs" % d["coord"])
				return
			if int(m[VoxelMaterial.GRAVE_PATH]) <= 0:
				_fail("FAIL %s Graveyard district has no plot aisles" % d["coord"])
				return
			if int(m[VoxelMaterial.GRAVE_SOIL]) <= 0:
				_fail("FAIL %s Graveyard district has no grave plots" % d["coord"])
				return
			if int(m[VoxelMaterial.YEW]) <= 0:
				_fail("FAIL %s Graveyard district has no hedge / trees" % d["coord"])
				return
			continue
		if int(d["theme_id"]) == DistrictTheme.LAKE:
			basins += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Lake district still has housing lots" % d["coord"])
				return
			if int(d["lake_cells"]) <= 0:
				_fail("FAIL %s Lake district has no lake cells" % d["coord"])
				return
			if int(m[VoxelMaterial.WATER]) <= 0:
				_fail("FAIL %s Lake district has no open water" % d["coord"])
				return
			if int(m[VoxelMaterial.LEAVES]) <= 0:
				_fail("FAIL %s Lake district has no shore / island planting" % d["coord"])
				return
			continue
		if int(d["theme_id"]) == DistrictTheme.CASTLE:
			castles += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Castle district still has housing lots" % d["coord"])
				return
			if int(d["castle_cells"]) <= 0:
				_fail("FAIL %s Castle district has no castle cells" % d["coord"])
				return
			if int(m[VoxelMaterial.CASTLE_BLOCK]) <= 0:
				_fail("FAIL %s Castle district has no masonry" % d["coord"])
				return
			if int(m[VoxelMaterial.CASTLE_BLOCK_MOSSY]) <= 0:
				_fail("FAIL %s Castle district has no weathering" % d["coord"])
				return
			if int(m[VoxelMaterial.GRAVEL]) <= 0:
				_fail("FAIL %s Castle district has no approach track" % d["coord"])
				return
			continue
		if int(d["theme_id"]) == DistrictTheme.FRACTAL:
			## A glowing deck with Mandelbrot walls — no buildings and no urban parks, so
			## the park recipe below does not apply. An empty fractal reserve already
			## push_errors in DistrictPlanner._build_fractal_layout.
			fractals += 1
			continue
		if int(d["theme_id"]) == DistrictTheme.ARENA:
			arenas += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Arena district still has housing lots" % d["coord"])
				return
			if int(d["arena_cells"]) <= 0:
				_fail("FAIL %s Arena district has no arena cells" % d["coord"])
				return
			if int(m[VoxelMaterial.ARENA_SHELL]) <= 0:
				_fail("FAIL %s Arena district has no ARENA_SHELL mass" % d["coord"])
				return
			continue
		if int(d["theme_id"]) == DistrictTheme.ZOO:
			zoos += 1
			if int(d["lot_cells"]) > 0:
				_fail("FAIL %s Zoo district still has housing lots" % d["coord"])
				return
			if int(d["zoo_cells"]) <= 0:
				_fail("FAIL %s Zoo district has no zoo cells" % d["coord"])
				return
			## The containment ring is the whole point — an unfenced zoo is a meadow.
			if int(m[VoxelMaterial.ZOO_FENCE_LINE]) <= 0:
				_fail("FAIL %s Zoo district has no energy line" % d["coord"])
				return
			continue
		urban += 1
		if int(m[VoxelMaterial.GRAVEL]) <= 0:
			_fail("FAIL %s (%s) has no park paths" % [d["coord"], d["theme"]])
			return
		if int(m[VoxelMaterial.LEAVES]) <= 0:
			_fail("FAIL %s (%s) has no planting" % [d["coord"], d["theme"]])
			return
		if int(m[VoxelMaterial.WATER]) > 0:
			ponds += 1
	if urban > 0 and ponds < urban - 2:
		_fail("FAIL only %d of %d urban tiles got a pond" % [ponds, urban])
		return
	print(
		(
			"OK open space: parks on %d tiles (ponds %d), hills on %d, graveyards on %d,"
			+ " lakes on %d, castles on %d, fractals on %d, arenas on %d, zoos on %d"
		)
		% [urban, ponds, hills, graveyards, basins, castles, fractals, arenas, zoos]
	)


func _check_bake_differences(stats: Array) -> void:
	if stats.size() != COORDS.size():
		_fail("FAIL only %d of %d districts baked" % [stats.size(), COORDS.size()])
		return
	var by_theme: Dictionary = {}
	for s: Variant in stats:
		var d: Dictionary = s
		by_theme[int(d["theme_id"])] = d
	if by_theme.size() < 3:
		_fail("FAIL the 9 baked tiles only produced %d themes" % by_theme.size())
		return

	var tallest: Dictionary = stats[0]
	var lowest: Dictionary = stats[0]
	var most_green: Dictionary = stats[0]
	var least_green: Dictionary = stats[0]
	for s2: Variant in stats:
		var d2: Dictionary = s2
		if float(d2["top_m"]) > float(tallest["top_m"]):
			tallest = d2
		if float(d2["top_m"]) < float(lowest["top_m"]):
			lowest = d2
		if int(d2["park_cells"]) > int(most_green["park_cells"]):
			most_green = d2
		if int(d2["park_cells"]) < int(least_green["park_cells"]):
			least_green = d2

	if float(tallest["top_m"]) < float(lowest["top_m"]) * 1.5:
		_fail(
			"FAIL skyline is flat: tallest %.0fm (%s) vs lowest %.0fm (%s)"
			% [tallest["top_m"], tallest["theme"], lowest["top_m"], lowest["theme"]]
		)
		return
	if int(most_green["park_cells"]) <= int(least_green["park_cells"]):
		_fail("FAIL park counts identical across themes")
		return

	var dominants: Dictionary = {}
	for id: Variant in by_theme.keys():
		var d3: Dictionary = by_theme[id]
		dominants[_dominant_wall(d3["walls"])] = true
	if dominants.size() < 2:
		_fail("FAIL every theme has the same dominant wall material")
		return

	print(
		"OK differences: tallest %s %.0fm, lowest %s %.0fm, parks %d..%d, %d distinct dominant walls"
		% [
			tallest["theme"], tallest["top_m"], lowest["theme"], lowest["top_m"],
			least_green["park_cells"], most_green["park_cells"], dominants.size(),
		]
	)


func _live_city_report() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	## Wall-clock, not frame count: the district bakes on worker threads while the main
	## loop spins at hundreds of FPS, so a 2400-frame budget expired after ~3 s and the
	## walker had not spawned yet.
	var deadline := Time.get_ticks_msec() + 90_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			_fail("FAIL live city produced no walker after 90 s")
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	## Let districts stream in around the spawn point.
	await _settle(8.0)

	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	var peds := 0
	var vehicles := 0
	var theme_names: Array[String] = []
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.crowd != null:
			peds += di.crowd.agent_count()
		if di.vehicles != null:
			var tiers: Vector3i = di.vehicles.count_lod_tiers()
			vehicles += tiers.x + tiers.y + tiers.z
		theme_names.append(DistrictTheme.for_district(WORLD_SEED, di.coord).display_name)
	print(
		"live city: %d districts [%s], %d pedestrians, %d vehicles"
		% [districts.size(), ", ".join(theme_names), peds, vehicles]
	)
	if districts.is_empty():
		_fail("FAIL no districts streamed")
		return
	if peds <= 0:
		_fail("FAIL zoning starved the pedestrian crowd")
		return
	if vehicles <= 0:
		_fail("FAIL zoning starved traffic")
		return

	await _shoot(walker.global_position, Vector3(0.0, 3.0, 0.0), Vector3(-0.05, 0.0, 0.0), STREET_PNG)
	await _shoot(walker.global_position, Vector3(-60.0, 120.0, 90.0), Vector3(-0.5, -0.6, 0.0), SKYLINE_PNG)
	## Voxels only mesh around the player, so walk over to the next tile — a different
	## theme — before shooting it.
	var coord := Vector2i(0, 1)
	var target := DistrictCoord.center_world(coord, CityRoot.VOXEL_SIZE)
	print("neighbour tile %s is %s" % [coord, DistrictTheme.for_district(WORLD_SEED, coord).display_name])
	walker.global_position = Vector3(target.x, 40.0, target.z)
	await _settle(10.0)
	await _shoot(walker.global_position, Vector3(0.0, 22.0, 40.0), Vector3(-0.3, 0.0, 0.0), NEIGHBOUR_PNG)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(anchor: Vector3, offset: Vector3, rot: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = anchor + offset
	cam.rotation = rot
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	## Settle, then sample the frame rate from this viewpoint: the new surface shaders
	## add texture samples per pixel, so the cost has to stay visible in the log.
	await _settle(3.0)
	var fps := 0.0
	for _f in range(60):
		await get_tree().process_frame
		fps += Engine.get_frames_per_second()
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s (avg %.0f fps)" % [path, fps / 60.0])
	cam.queue_free()
