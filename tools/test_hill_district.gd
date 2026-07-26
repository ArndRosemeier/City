## Bake a Hill-theme district and assert houseless middle, rock strata, caves, planting.
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")

const WORLD_SEED := 42
const BLOCK := 16
const ROCK_IDS: Array[int] = [
	VoxelMaterial.BEDROCK,
	VoxelMaterial.STONE,
	VoxelMaterial.BRICK,
	VoxelMaterial.DIRT,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.CAVE_WALL,
	VoxelMaterial.CAVE_FLOOR,
]
const GEM_IDS: Array[int] = [
	VoxelMaterial.GEM_QUARTZ,
	VoxelMaterial.GEM_AMBER,
	VoxelMaterial.GEM_TOPAZ,
	VoxelMaterial.GEM_SAPPHIRE,
	VoxelMaterial.GEM_EMERALD,
	VoxelMaterial.GEM_DIAMOND,
]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var coord := _find_hill_coord()
	if coord == Vector2i(999, 999):
		_fail("FAIL no Hill theme in ring 1..4 for seed %d" % WORLD_SEED)
		_quit()
		return
	print("baking Hill district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.HILL)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_hill.size.x <= 0:
		_fail("FAIL planner produced no large_hill")
		_quit()
		return
	var lots := 0
	var hills := 0
	var roads := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.HILL:
				hills += 1
			elif LandUse.is_road(tag):
				roads += 1
	var mid_roads := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z in range(z0, z1):
		for x in range(x0, x1):
			if LandUse.is_road(planner.tag_at(x, z)):
				mid_roads += 1
	print(
		"layout lots=%d hills=%d roads=%d mid_roads=%d hill_rect=%s"
		% [lots, hills, roads, mid_roads, planner.large_hill]
	)
	if lots > 0:
		_fail("FAIL Hill layout still has %d lots" % lots)
		_quit()
		return
	if hills < 100:
		_fail("FAIL Hill layout only has %d hill cells" % hills)
		_quit()
		return
	if roads < 8:
		_fail("FAIL Hill layout has too few road cells (%d) — edge connectors missing?" % roads)
		_quit()
		return
	if mid_roads > 0:
		_fail("FAIL Hill middle still has %d road cells — expected edge stubs only" % mid_roads)
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
	if int(res["theme_id"]) != DistrictTheme.HILL:
		_fail("FAIL baked theme is %s not Hill" % res["theme_name"])
		_quit()
		return

	var counts := _count_above_deck(res["blocks"], int(res["ground_thickness"]))
	var gem_total := 0
	var gem_parts: PackedStringArray = PackedStringArray()
	for gid: int in GEM_IDS:
		var n := int(counts.get(gid, 0))
		gem_total += n
		gem_parts.append("%d" % n)
	print(
		(
			"voxels rock=%d stone=%d brick=%d dirt=%d gravel=%d grass=%d leaves=%d"
			+ " cave_wall=%d cave_floor=%d gems=%d [%s]"
		)
		% [
			int(counts.get(VoxelMaterial.BEDROCK, 0)),
			int(counts.get(VoxelMaterial.STONE, 0)),
			int(counts.get(VoxelMaterial.BRICK, 0)),
			int(counts.get(VoxelMaterial.DIRT, 0)),
			int(counts.get(VoxelMaterial.GRAVEL, 0)),
			int(counts.get(VoxelMaterial.PARK, 0)),
			int(counts.get(VoxelMaterial.LEAVES, 0)),
			int(counts.get(VoxelMaterial.CAVE_WALL, 0)),
			int(counts.get(VoxelMaterial.CAVE_FLOOR, 0)),
			gem_total,
			", ".join(gem_parts),
		]
	)
	if int(counts.get(VoxelMaterial.CAVE_FLOOR, 0)) < 100:
		_fail("FAIL cave floor missing (cave_floor=%d)" % int(counts.get(VoxelMaterial.CAVE_FLOOR, 0)))
		_quit()
		return
	## Hillside must stay diggable — BEDROCK belongs only on the world floor slab.
	if int(counts.get(VoxelMaterial.BEDROCK, 0)) > 0:
		_fail(
			"FAIL hillside contains %d BEDROCK voxels above the deck (must be diggable)"
			% int(counts.get(VoxelMaterial.BEDROCK, 0))
		)
		_quit()
		return
	var strata_kinds := 0
	for id: int in [
		VoxelMaterial.STONE, VoxelMaterial.BRICK, VoxelMaterial.DIRT, VoxelMaterial.GRAVEL,
	]:
		if int(counts.get(id, 0)) > 200:
			strata_kinds += 1
	if strata_kinds < 3:
		_fail("FAIL only %d distinct strata materials with volume" % strata_kinds)
		_quit()
		return
	if int(counts.get(VoxelMaterial.LEAVES, 0)) <= 0:
		_fail("FAIL no tree canopy on hill")
		_quit()
		return
	var roofed := _count_roofed_air(res["blocks"], int(res["ground_thickness"]))
	print("roofed air voxels (cave volume) = %d" % roofed)
	if roofed < 2000:
		_fail("FAIL only %d roofed air voxels — dungeon cave too small" % roofed)
		_quit()
		return
	if int(counts.get(VoxelMaterial.CAVE_WALL, 0)) < 1000:
		_fail(
			"FAIL cave lining too thin for a branched dungeon (cave_wall=%d)"
			% int(counts.get(VoxelMaterial.CAVE_WALL, 0))
		)
		_quit()
		return
	if gem_total < 40:
		_fail("FAIL gem ore missing or too sparse (gems=%d)" % gem_total)
		_quit()
		return
	var quartz := int(counts.get(VoxelMaterial.GEM_QUARTZ, 0))
	var diamond := int(counts.get(VoxelMaterial.GEM_DIAMOND, 0))
	if quartz <= 0:
		_fail("FAIL common quartz missing (quartz=%d)" % quartz)
		_quit()
		return
	if diamond > quartz:
		_fail("FAIL diamond (%d) more common than quartz (%d)" % [diamond, quartz])
		_quit()
		return
	var gems_payload: Dictionary = (res.get("generator") as DistrictGenerator).get_hill_gems()
	var gem_list: PackedVector3Array = gems_payload.get("positions", PackedVector3Array())
	if gem_list.size() < 40:
		_fail("FAIL hill gem registry empty (listed=%d)" % gem_list.size())
		_quit()
		return

	## Determinism: two bakes match theme + hill rect.
	var res2: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
	})
	var p2: DistrictPlanner = res2["planner"]
	if p2.large_hill != planner.large_hill:
		_fail("FAIL hill rect not deterministic")
		_quit()
		return

	print("RESULT: OK")
	_quit()


func _find_hill_coord() -> Vector2i:
	for ring in range(1, 8):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if maxi(absi(cx), absi(cz)) != ring:
					continue
				var t := DistrictTheme.for_district(WORLD_SEED, Vector2i(cx, cz))
				if t.id == DistrictTheme.HILL:
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


## Air above the street deck that still has rock over it — i.e. cave, not sky. Voxels
## are stored y-fastest, so one block column is a contiguous run of BLOCK entries.
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
				## Only rock overhead counts — canopy air is not a cave.
				if roof in ROCK_IDS and block_y0 + local_y > ground_thickness:
					total += 1
	return total


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
