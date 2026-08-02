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
## How far inland from a daylit column to look for roofed cave. Must exceed the rock shell the
## carve leaves between a cavern and the hillside face (`HillComposer.CAVE_SHELL`, 6 voxels).
const INLAND_REACH_VOX := 14
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

	var res: Dictionary = DistrictBakeJobScript.bake(_bake_params(coord, dseed))
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
	var quota := _hill_gem_quota(dseed).size()
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
	var gen: DistrictGenerator = res.get("generator") as DistrictGenerator
	var gems_payload: Dictionary = gen.get_hill_gems()
	var gem_list: PackedVector3Array = gems_payload.get("positions", PackedVector3Array())
	## Quota is painted after the cheese carve into remaining host, so every budgeted gem
	## must still be standing — a registry miss is ore the player can never dig.
	if gem_list.size() != quota:
		_fail("FAIL hill gem registry lists %d of its %d budgeted voxels" % [gem_list.size(), quota])
		_quit()
		return
	var lost := _count_lost_gems(gen, gems_payload)
	if lost > 0:
		_fail("FAIL %d of %d budgeted gems did not survive the bake" % [lost, quota])
		_quit()
		return
	if gem_total != quota:
		_fail("FAIL hill holds %d gem voxels above the deck, budgeted %d" % [gem_total, quota])
		_quit()
		return
	var mouths := gen.get_hill_cave_mouths()
	if mouths.is_empty():
		_fail("FAIL no daylight cave mouths registered for spawn")
		_quit()
		return
	var lit := _count_daylight_mouths(gen, mouths)
	print("cave mouths=%d daylight=%d" % [mouths.size(), lit])
	if lit <= 0:
		_fail("FAIL cave mouths registered but none break daylight (sealed under shell)")
		_quit()
		return
	var spawn := gen.find_spawn_world(null)
	if not is_finite(spawn.x):
		_fail("FAIL hill cave-mouth spawn not found")
		_quit()
		return
	if not is_finite(float(gen.last_spawn_yaw)):
		_fail("FAIL hill spawn yaw missing (should face the entrance)")
		_quit()
		return
	print(
		"spawn=(%.1f, %.1f, %.1f) yaw=%.2f"
		% [spawn.x, spawn.y, spawn.z, float(gen.last_spawn_yaw)]
	)

	## Determinism: two bakes match theme + hill rect.
	var res2: Dictionary = DistrictBakeJobScript.bake(_bake_params(coord, dseed))
	var p2: DistrictPlanner = res2["planner"]
	if p2.large_hill != planner.large_hill:
		_fail("FAIL hill rect not deterministic")
		_quit()
		return

	print("RESULT: OK")
	_quit()


## What a caller without a live `CityRoot` hands the bake, copied from `district_instance.gd`:
## a hill paints exactly the gems its ledger still owes, so a bake given no quota paints none.
## Passing it here is what keeps the ore assertions below about the scatter rather than about
## whether anyone remembered to ask for ore.
func _hill_gem_quota(dseed: int) -> PackedInt32Array:
	return DistrictEconomy.flat_gem_list(DistrictEconomy.roll_budgets(DistrictTheme.HILL, dseed))


func _bake_params(coord: Vector2i, dseed: int) -> Dictionary:
	return {
		"coord": coord,
		"world_seed": WORLD_SEED,
		"hill_gem_mats_to_place": _hill_gem_quota(dseed),
	}


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


## Walk the gem registry against the finished voxels and report what took the place of any gem
## that is no longer there — the replacement material names the pass that ate it.
func _count_lost_gems(gen: DistrictGenerator, gems_payload: Dictionary) -> int:
	var vol: NativeOfflineVoxelVolume = gen.get_offline_volume()
	if vol == null:
		_fail("FAIL offline volume missing for the gem survival check")
		return 0
	var positions: PackedVector3Array = gems_payload.get("positions", PackedVector3Array())
	var mats: PackedInt32Array = gems_payload.get("mats", PackedInt32Array())
	if positions.size() != mats.size():
		_fail("FAIL gem registry has %d positions and %d mats" % [positions.size(), mats.size()])
		return 0
	var lost := 0
	var replaced: Dictionary = {}
	## The registry speaks world voxels (it feeds ore lights); the offline volume is tile-local.
	var origin := gen.origin_vox
	for i in range(positions.size()):
		var at := Vector3i(positions[i]) - origin
		var found := int(vol.get_vox(at))
		if found == int(mats[i]):
			continue
		lost += 1
		replaced[found] = int(replaced.get(found, 0)) + 1
		if lost <= 4:
			print("lost gem %d at %s — now %d" % [int(mats[i]), str(at), found])
	if lost > 0:
		print("gems lost after painting: %d, replaced by %s" % [lost, str(replaced)])
	return lost


## A mouth "daylights" when a nearby column is open from the walk deck through the
## turf into sky — i.e. the hillside face actually has a hole, not a sealed tube.
func _count_daylight_mouths(gen: DistrictGenerator, mouths: PackedVector2Array) -> int:
	var vol: NativeOfflineVoxelVolume = gen.get_offline_volume()
	if vol == null:
		_fail("FAIL offline volume missing for mouth daylight check")
		return 0
	var deck := gen.ground_thickness
	var lit := 0
	for mi in range(mouths.size()):
		var mouth: Vector2 = mouths[mi]
		var mx := int(round(mouth.x))
		var mz := int(round(mouth.y))
		var ok := false
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if _column_daylights_into_cave(vol, mx + dx, mz + dz, deck):
					ok = true
					break
			if ok:
				break
		if ok:
			lit += 1
	return lit


## Cardinal offsets from a daylit column, ordered nearest-first, reaching well past the shell.
func _inland_probes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for step in range(1, INLAND_REACH_VOX + 1):
		out.append(Vector2i(step, 0))
		out.append(Vector2i(-step, 0))
		out.append(Vector2i(0, step))
		out.append(Vector2i(0, -step))
	return out


func _column_daylights_into_cave(
	vol: NativeOfflineVoxelVolume, lx: int, lz: int, deck: int
) -> bool:
	## Walk deck must be air (tunnel floor / approach).
	if int(vol.get_vox(Vector3i(lx, deck + 1, lz))) != VoxelMaterial.AIR:
		return false
	## Unbroken air up past where turf would sit, into open sky.
	var air_run := 0
	for y in range(deck + 1, deck + 40):
		if int(vol.get_vox(Vector3i(lx, y, lz))) != VoxelMaterial.AIR:
			return false
		air_run += 1
		## Once we have walker headroom + a bit, treat as open sky column.
		if air_run >= 10:
			break
	if air_run < 10:
		return false
	## And somewhere further in, rock still roofs air (the cave continues inland and goes dark).
	## The reach has to clear `HillComposer.CAVE_SHELL`: the carve deliberately leaves that much
	## rock between a cavern and the hillside face, so anything roofed is at least that far in.
	## Probing only a couple of voxels past the opening finds nothing but the daylit throat.
	for side: Vector2i in _inland_probes():
		var x := lx + side.x
		var z := lz + side.y
		if int(vol.get_vox(Vector3i(x, deck + 4, z))) != VoxelMaterial.AIR:
			continue
		for y in range(deck + 8, deck + 28):
			var id := int(vol.get_vox(Vector3i(x, y, z)))
			if id in ROCK_IDS:
				return true
	return false


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
