## Bake a Graveyard-theme district and assert edge stubs, elevated yard, chapel, crypts.
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")

const WORLD_SEED := 42
const BLOCK := 16
const ROCK_IDS: Array[int] = [
	VoxelMaterial.BEDROCK,
	VoxelMaterial.STONE,
	VoxelMaterial.BRICK,
	VoxelMaterial.BRICK_DARK,
	VoxelMaterial.DIRT,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.CAVE_WALL,
	VoxelMaterial.CAVE_FLOOR,
	VoxelMaterial.GRAVE_STONE,
	VoxelMaterial.GRAVE_MARBLE,
	VoxelMaterial.GRAVE_SOIL,
	VoxelMaterial.GRAVE_PATH,
]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var coord := _find_graveyard_coord()
	if coord == Vector2i(999, 999):
		_fail("FAIL no Graveyard theme in ring 1..8 for seed %d" % WORLD_SEED)
		_quit()
		return
	print("baking Graveyard district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.GRAVEYARD)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_graveyard.size.x <= 0:
		_fail("FAIL planner produced no large_graveyard")
		_quit()
		return
	var lots := 0
	var yards := 0
	var roads := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.GRAVEYARD:
				yards += 1
			elif LandUse.is_road(tag):
				roads += 1
	var mid_roads := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z2 in range(z0, z1):
		for x2 in range(x0, x1):
			if LandUse.is_road(planner.tag_at(x2, z2)):
				mid_roads += 1
	print(
		"layout lots=%d yards=%d roads=%d mid_roads=%d gy_rect=%s"
		% [lots, yards, roads, mid_roads, planner.large_graveyard]
	)
	if lots > 0:
		_fail("FAIL Graveyard layout still has %d lots" % lots)
		_quit()
		return
	if yards < 100:
		_fail("FAIL Graveyard layout only has %d yard cells" % yards)
		_quit()
		return
	if roads < 8:
		_fail("FAIL Graveyard layout has too few road cells (%d)" % roads)
		_quit()
		return
	if mid_roads > 0:
		_fail("FAIL Graveyard middle still has %d road cells" % mid_roads)
		_quit()
		return

	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL bake: %s" % res.get("error", "?"))
		_quit()
		return
	if int(res["theme_id"]) != DistrictTheme.GRAVEYARD:
		_fail("FAIL baked theme is %s not Graveyard" % res["theme_name"])
		_quit()
		return

	var counts := _count_above_deck(res["blocks"], int(res["ground_thickness"]))
	print(
		(
			"voxels stone=%d grave_stone=%d marble=%d soil=%d path=%d yew=%d"
			+ " iron=%d bark=%d roof=%d"
		)
		% [
			int(counts.get(VoxelMaterial.STONE, 0)),
			int(counts.get(VoxelMaterial.GRAVE_STONE, 0)),
			int(counts.get(VoxelMaterial.GRAVE_MARBLE, 0)),
			int(counts.get(VoxelMaterial.GRAVE_SOIL, 0)),
			int(counts.get(VoxelMaterial.GRAVE_PATH, 0)),
			int(counts.get(VoxelMaterial.YEW, 0)),
			int(counts.get(VoxelMaterial.WROUGHT_IRON, 0)),
			int(counts.get(VoxelMaterial.BARK, 0)),
			int(counts.get(VoxelMaterial.ROOF, 0)),
		]
	)
	if int(counts.get(VoxelMaterial.STONE, 0)) < 5000:
		_fail("FAIL chapel / mound stone too thin (stone=%d)" % int(counts.get(VoxelMaterial.STONE, 0)))
		_quit()
		return
	## Kerbs, headstones, mausoleums and crypt lining are all dressed grave stone.
	if int(counts.get(VoxelMaterial.GRAVE_STONE, 0)) < 8000:
		_fail(
			"FAIL monuments / kerbs too sparse (grave_stone=%d)"
			% int(counts.get(VoxelMaterial.GRAVE_STONE, 0))
		)
		_quit()
		return
	if int(counts.get(VoxelMaterial.GRAVE_PATH, 0)) < 2000:
		_fail(
			"FAIL aisle lattice missing (grave_path=%d)"
			% int(counts.get(VoxelMaterial.GRAVE_PATH, 0))
		)
		_quit()
		return
	if int(counts.get(VoxelMaterial.GRAVE_SOIL, 0)) < 5000:
		_fail(
			"FAIL grave plots missing (grave_soil=%d)"
			% int(counts.get(VoxelMaterial.GRAVE_SOIL, 0))
		)
		_quit()
		return
	if int(counts.get(VoxelMaterial.YEW, 0)) < 2000:
		_fail("FAIL hedge / cypresses missing (yew=%d)" % int(counts.get(VoxelMaterial.YEW, 0)))
		_quit()
		return
	if int(counts.get(VoxelMaterial.WROUGHT_IRON, 0)) < 100:
		_fail(
			"FAIL ironwork missing (iron=%d)" % int(counts.get(VoxelMaterial.WROUGHT_IRON, 0))
		)
		_quit()
		return
	if int(counts.get(VoxelMaterial.ROOF, 0)) < 50:
		_fail("FAIL chapel roof missing (roof=%d)" % int(counts.get(VoxelMaterial.ROOF, 0)))
		_quit()
		return
	## Crypt floors and monument marble.
	if int(counts.get(VoxelMaterial.GRAVE_MARBLE, 0)) < 500:
		_fail(
			"FAIL crypt flagstones / marble missing (marble=%d)"
			% int(counts.get(VoxelMaterial.GRAVE_MARBLE, 0))
		)
		_quit()
		return
	var roofed := _count_roofed_air(res["blocks"], int(res["ground_thickness"]))
	print("roofed air voxels (crypt volume) = %d" % roofed)
	if roofed < 400:
		_fail("FAIL only %d roofed air voxels — crypts too small" % roofed)
		_quit()
		return
	## Elevated fill must exist above the street deck.
	var elevated := _count_elevated_fill(res["blocks"], int(res["ground_thickness"]))
	print("elevated fill voxels above deck+4 = %d" % elevated)
	if elevated < 20000:
		_fail("FAIL yard not elevated enough (fill=%d)" % elevated)
		_quit()
		return

	print("RESULT: OK")
	_quit()


func _find_graveyard_coord() -> Vector2i:
	for ring in range(1, 10):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if maxi(absi(cx), absi(cz)) != ring:
					continue
				var t := DistrictTheme.for_district(WORLD_SEED, Vector2i(cx, cz))
				if t.id == DistrictTheme.GRAVEYARD:
					return Vector2i(cx, cz)
	return Vector2i(999, 999)


func _count_above_deck(blocks: Dictionary, ground_thickness: int) -> Dictionary:
	var counts: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= ground_thickness + 1:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			var uid := int(data[0])
			if uid == VoxelMaterial.AIR:
				continue
			var layers := mini(BLOCK, block_y0 + BLOCK - (ground_thickness + 1))
			if layers > 0:
				counts[uid] = int(counts.get(uid, 0)) + layers * BLOCK * BLOCK
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			var local_y := i % BLOCK
			var world_y := block_y0 + local_y
			if world_y <= ground_thickness:
				continue
			var vid := int(data[i * 2])
			if vid == VoxelMaterial.AIR:
				continue
			counts[vid] = int(counts.get(vid, 0)) + 1
	return counts


func _count_elevated_fill(blocks: Dictionary, ground_thickness: int) -> int:
	var total := 0
	var min_y := ground_thickness + 4
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= min_y:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			var uid := int(data[0])
			if _is_foliage(uid):
				continue
			var layers := mini(BLOCK, block_y0 + BLOCK - min_y)
			if layers > 0:
				total += layers * BLOCK * BLOCK
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			var world_y := block_y0 + (i % BLOCK)
			if world_y < min_y:
				continue
			var vid := int(data[i * 2])
			if _is_foliage(vid):
				continue
			total += 1
	return total


## Planting is not structural fill — the yard has to be earth and masonry.
func _is_foliage(id: int) -> bool:
	return (
		id == VoxelMaterial.AIR
		or id == VoxelMaterial.LEAVES
		or id == VoxelMaterial.YEW
		or id == VoxelMaterial.BARK
	)


func _count_roofed_air(blocks: Dictionary, ground_thickness: int) -> int:
	var total := 0
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= ground_thickness + 1:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			continue
		var columns := (data.size() / 2) / BLOCK
		for c in range(columns):
			var base := c * BLOCK
			var roof := VoxelMaterial.AIR
			for local_y in range(BLOCK - 1, -1, -1):
				var vid := int(data[(base + local_y) * 2])
				if vid != VoxelMaterial.AIR:
					roof = vid
					continue
				if roof in ROCK_IDS and block_y0 + local_y > ground_thickness:
					total += 1
	return total


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
