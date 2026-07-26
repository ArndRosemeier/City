## Bake a Lake-theme district and assert houseless middle, a deep natural basin,
## dry road stubs, wooded islands and an intact world floor slab.
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")

const WORLD_SEED := 42
const BLOCK := 16

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.LAKE, 8)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.LAKE:
		_fail("FAIL no Lake theme within ring 8 for seed %d" % WORLD_SEED)
		_quit()
		return
	print("baking Lake district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.LAKE)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_lake.size.x <= 0:
		_fail("FAIL planner produced no large_lake")
		_quit()
		return
	var lots := 0
	var lakes := 0
	var roads := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.LAKE:
				lakes += 1
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
		"layout lots=%d lake_cells=%d roads=%d mid_roads=%d lake_rect=%s"
		% [lots, lakes, roads, mid_roads, planner.large_lake]
	)
	if lots > 0:
		_fail("FAIL Lake layout still has %d lots" % lots)
		_quit()
		return
	if lakes < 100:
		_fail("FAIL Lake layout only has %d lake cells" % lakes)
		_quit()
		return
	if roads < 8:
		_fail("FAIL Lake layout has too few road cells (%d) — edge connectors missing?" % roads)
		_quit()
		return
	if mid_roads > 0:
		_fail("FAIL Lake middle still has %d road cells — expected edge stubs only" % mid_roads)
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
	if int(res["theme_id"]) != DistrictTheme.LAKE:
		_fail("FAIL baked theme is %s not Lake" % res["theme_name"])
		_quit()
		return

	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	var surface := _count_at_y(blocks, deck)
	var deep := _count_at_y(blocks, deck - 4)
	var floor_slab := _count_at_y(blocks, 0)
	var above := _count_above_y(blocks, deck)
	var water_surface := int(surface.get(VoxelMaterial.WATER, 0))
	var water_deep := int(deep.get(VoxelMaterial.WATER, 0))
	print(
		"voxels water_surface=%d water_deep=%d shore_gravel=%d shore_dirt=%d"
		% [
			water_surface,
			water_deep,
			int(surface.get(VoxelMaterial.GRAVEL, 0)),
			int(surface.get(VoxelMaterial.DIRT, 0)),
		]
	)
	print(
		"above deck: island_grass=%d island_fill=%d leaves=%d bark=%d water=%d"
		% [
			int(above.get(VoxelMaterial.PARK, 0)),
			int(above.get(VoxelMaterial.DIRT, 0)),
			int(above.get(VoxelMaterial.LEAVES, 0)),
			int(above.get(VoxelMaterial.BARK, 0)),
			int(above.get(VoxelMaterial.WATER, 0)),
		]
	)
	## A district tile is 784×560 voxels; a lake worth swimming in covers a good
	## chunk of the streetless middle.
	if water_surface < 40000:
		_fail("FAIL lake surface is only %d voxels — basin far too small" % water_surface)
		_quit()
		return
	## Swimming needs real depth, not a puddle skin over the deck.
	if water_deep < 5000:
		_fail("FAIL only %d water voxels 2 m down — basin is too shallow" % water_deep)
		_quit()
		return
	if int(above.get(VoxelMaterial.WATER, 0)) > 0:
		_fail(
			"FAIL %d water voxels above the deck — the lake is spilling upward"
			% int(above.get(VoxelMaterial.WATER, 0))
		)
		_quit()
		return
	## The world floor slab must survive the carve or the district leaks into the void.
	if int(floor_slab.get(VoxelMaterial.WATER, 0)) > 0:
		_fail("FAIL basin cut into the y=0 floor slab")
		_quit()
		return
	if int(above.get(VoxelMaterial.PARK, 0)) < 400:
		_fail(
			"FAIL only %d grass voxels above the deck — islands missing"
			% int(above.get(VoxelMaterial.PARK, 0))
		)
		_quit()
		return
	if int(above.get(VoxelMaterial.LEAVES, 0)) < 200:
		_fail("FAIL no tree canopy around the lake")
		_quit()
		return
	## Shingle beach so the waterline reads as a shore, not a cut.
	if int(surface.get(VoxelMaterial.GRAVEL, 0)) < 1000:
		_fail("FAIL beach missing (gravel=%d)" % int(surface.get(VoxelMaterial.GRAVEL, 0)))
		_quit()
		return
	## Every road stub has to stay dry, or the district cannot be walked into.
	var wet_roads := _count_wet_roads(blocks, res["planner"], deck, int(res["cell_size"]))
	print("water voxels on road cells = %d" % wet_roads)
	if wet_roads > 0:
		_fail("FAIL %d water voxels sit on road cells" % wet_roads)
		_quit()
		return

	var res2: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
	})
	var p2: DistrictPlanner = res2["planner"]
	if p2.large_lake != planner.large_lake:
		_fail("FAIL lake rect not deterministic")
		_quit()
		return
	var surface2 := _count_at_y(res2["blocks"], deck)
	if int(surface2.get(VoxelMaterial.WATER, 0)) != water_surface:
		_fail(
			"FAIL lake surface not deterministic (%d vs %d)"
			% [int(surface2.get(VoxelMaterial.WATER, 0)), water_surface]
		)
		_quit()
		return

	print("RESULT: OK")
	_quit()


## Material histogram of one world-Y slice. Voxels are stored y-fastest, two bytes each.
func _count_at_y(blocks: Dictionary, y: int) -> Dictionary:
	var counts: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if y < block_y0 or y >= block_y0 + BLOCK:
			continue
		var data: PackedByteArray = blocks[key]
		var local_y := y - block_y0
		if data.size() <= 2:
			var uid := int(data[0])
			if uid == VoxelMaterial.AIR:
				continue
			counts[uid] = int(counts.get(uid, 0)) + BLOCK * BLOCK
			continue
		var columns := (data.size() / 2) / BLOCK
		for c in range(columns):
			var vid := int(data[(c * BLOCK + local_y) * 2])
			if vid == VoxelMaterial.AIR:
				continue
			counts[vid] = int(counts.get(vid, 0)) + 1
	return counts


func _count_above_y(blocks: Dictionary, y: int) -> Dictionary:
	var counts: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if block_y0 + BLOCK <= y + 1:
			continue
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			var uid := int(data[0])
			if uid == VoxelMaterial.AIR:
				continue
			var layers := mini(BLOCK, block_y0 + BLOCK - (y + 1))
			counts[uid] = int(counts.get(uid, 0)) + layers * BLOCK * BLOCK
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			if block_y0 + (i % BLOCK) <= y:
				continue
			var vid := int(data[i * 2])
			if vid == VoxelMaterial.AIR:
				continue
			counts[vid] = int(counts.get(vid, 0)) + 1
	return counts


## Water sitting on a planning cell tagged as road / avenue — a drowned connector.
func _count_wet_roads(
	blocks: Dictionary, planner: DistrictPlanner, deck: int, cell: int
) -> int:
	var wet := 0
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var block_y0 := bp.y * BLOCK
		if deck < block_y0 or deck >= block_y0 + BLOCK:
			continue
		var data: PackedByteArray = blocks[key]
		var local_y := deck - block_y0
		if data.size() <= 2:
			if int(data[0]) != VoxelMaterial.WATER:
				continue
			for lz in range(BLOCK):
				for lx in range(BLOCK):
					if LandUse.is_road(
						planner.tag_at((bp.x * BLOCK + lx) / cell, (bp.z * BLOCK + lz) / cell)
					):
						wet += 1
			continue
		var columns := (data.size() / 2) / BLOCK
		if columns != BLOCK * BLOCK:
			_fail("FAIL unexpected block layout: %d columns" % columns)
			return wet
		for c in range(columns):
			if int(data[(c * BLOCK + local_y) * 2]) != VoxelMaterial.WATER:
				continue
			## Column order is x-fastest within a z row.
			var lx := c % BLOCK
			var lz := c / BLOCK
			if LandUse.is_road(
				planner.tag_at((bp.x * BLOCK + lx) / cell, (bp.z * BLOCK + lz) / cell)
			):
				wet += 1
	return wet


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
