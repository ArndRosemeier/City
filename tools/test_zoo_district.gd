## Bake a Monster Zoo district and assert the forever-war shell: an open reserve, a glowing
## containment ring with exactly one opening, ~40 dice-rolled territories with a capped
## faction spread, home-turf plates on the ground, and a field that arrives already cratered.
##
## Run: powershell -File tools\run_test.ps1 test_zoo_district
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const WORLD_SEED := 42
const MAX_RING := 8
const BLOCK := 16

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	if not _check_theme_wiring():
		_quit()
		return
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.ZOO, MAX_RING)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.ZOO:
		_fail("FAIL no Zoo theme in ring 0..%d for seed %d" % [MAX_RING, WORLD_SEED])
		_quit()
		return
	print("baking Zoo district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.ZOO)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_zoo.size.x <= 0:
		_fail("FAIL planner produced no large_zoo")
		_quit()
		return
	var lots := 0
	var zoo_cells := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.ZOO:
				zoo_cells += 1
	print("layout lots=%d zoo_cells=%d zoo_rect=%s" % [lots, zoo_cells, planner.large_zoo])
	if lots > 0:
		_fail("FAIL Zoo layout still has %d lots" % lots)
		_quit()
		return
	if zoo_cells < 100:
		_fail("FAIL Zoo layout only has %d zoo cells" % zoo_cells)
		_quit()
		return

	var t0 := Time.get_ticks_msec()
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": coord,
		"world_seed": WORLD_SEED,
	})
	var bake_ms := Time.get_ticks_msec() - t0
	if not bool(res.get("ok", false)):
		_fail("FAIL bake: %s" % res.get("error", "?"))
		_quit()
		return
	if int(res["theme_id"]) != DistrictTheme.ZOO:
		_fail("FAIL baked theme is %s not Zoo" % res["theme_name"])
		_quit()
		return

	var gen: DistrictGenerator = res["generator"]
	var layout: ZooLayout = gen.get_zoo_layout()
	if layout == null:
		_fail("FAIL generator has no zoo layout after bake")
		_quit()
		return
	print("layout: %s (bake %d ms)" % [layout.describe(), bake_ms])
	if not _check_layout(layout):
		_quit()
		return

	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	if not _check_voxels(blocks, layout, deck):
		_quit()
		return

	print("RESULT: OK")
	_quit()


func _check_theme_wiring() -> bool:
	## Zoo has to be a real id in the enum. Asserting an absolute COUNT instead just breaks every
	## time a theme is added, which says nothing about whether the Zoo is wired up.
	if DistrictTheme.ZOO < 0 or DistrictTheme.ZOO >= DistrictTheme.COUNT:
		_fail(
			"FAIL DistrictTheme.ZOO is %d, outside 0..%d"
			% [DistrictTheme.ZOO, DistrictTheme.COUNT - 1]
		)
		return false
	if DistrictTheme.parse_theme_id("zoo") != DistrictTheme.ZOO:
		_fail("FAIL --spawn-theme=zoo does not resolve to the Zoo theme")
		return false
	if DistrictTheme.parse_theme_id("monster_zoo") != DistrictTheme.ZOO:
		_fail("FAIL alias monster_zoo does not resolve to the Zoo theme")
		return false
	if not DistrictTheme.is_special_id(DistrictTheme.ZOO):
		_fail("FAIL Zoo must be a special theme")
		return false
	if GameData.theme_gem_total(DistrictTheme.ZOO) <= 0:
		_fail("FAIL Zoo has no district_gems.theme_totals budget")
		return false
	## Plates need six readable faction materials that are all walkable ground.
	for f in range(6):
		var mat := VoxelMaterial.zoo_turf_for_faction_index(f)
		if not VoxelMaterial.is_zoo_turf(mat):
			_fail("FAIL turf material %d for faction %d is not zoo turf" % [mat, f])
			return false
		if not VoxelMaterial.is_walkable_surface(mat):
			_fail("FAIL zoo turf %d must be walkable" % mat)
			return false
		if VoxelMaterial.zoo_turf_faction_index(mat) != f:
			_fail("FAIL zoo turf %d does not map back to faction %d" % [mat, f])
			return false
	if VoxelMaterial.is_destructible(VoxelMaterial.ZOO_FENCE_FRAME):
		_fail("FAIL the containment ring must not be destructible")
		return false
	if VoxelMaterial.is_destructible(VoxelMaterial.ZOO_FENCE_LINE):
		_fail("FAIL the energy line must not be destructible")
		return false
	return true


func _check_layout(layout: ZooLayout) -> bool:
	if layout.field_rect.size.x < 80 or layout.field_rect.size.y < 80:
		_fail("FAIL battlefield too small: %s" % layout.field_rect)
		return false
	if not layout.fence_rect.encloses(layout.field_rect):
		_fail("FAIL field is not inside the containment ring")
		return false
	if layout.gate_rect.size.x <= 0 or layout.gate_rect.size.y <= 0:
		_fail("FAIL zoo has no gate opening")
		return false
	if layout.gate_dir == Vector2i.ZERO:
		_fail("FAIL gate has no inward direction")
		return false
	if layout.cloak_gate_vox.x < 0:
		_fail("FAIL no cloak gate mount planned")
		return false
	if layout.territory_count() < 30:
		_fail("FAIL only %d territories, expected ~40" % layout.territory_count())
		return false
	if layout.spawner_vox.size() != layout.territory_count():
		_fail(
			"FAIL %d spawn pads for %d territories"
			% [layout.spawner_vox.size(), layout.territory_count()]
		)
		return false
	## Faction roll must be capped, or one faction owns half the war.
	var per_faction := PackedInt32Array()
	per_faction.resize(6)
	per_faction.fill(0)
	for f in layout.seed_faction:
		if f < 0 or f >= 6:
			_fail("FAIL seed rolled faction %d, outside the six monster factions" % f)
			return false
		per_faction[f] += 1
	var cap := int(ceil(float(layout.territory_count()) / 6.0)) + 2
	for f2 in range(6):
		if per_faction[f2] > cap:
			_fail(
				"FAIL faction %d holds %d territories, cap is %d"
				% [f2, per_faction[f2], cap]
			)
			return false
	print("faction spread: %s (cap %d)" % [per_faction, cap])
	## Every field column must resolve to an owner, or plates and census have holes.
	var unowned := 0
	for i in layout.ownership:
		if i < 0 or i >= layout.territory_count():
			unowned += 1
	if unowned > 0:
		_fail("FAIL %d ownership cells resolve to no territory" % unowned)
		return false
	return true


func _check_voxels(blocks: Dictionary, layout: ZooLayout, deck: int) -> bool:
	var above := _count_above_y(blocks, deck)
	var surface := _count_at_y(blocks, deck)
	var frame_n := int(above.get(VoxelMaterial.ZOO_FENCE_FRAME, 0))
	var line_n := int(above.get(VoxelMaterial.ZOO_FENCE_LINE, 0))
	var glass_n := int(above.get(VoxelMaterial.ZOO_FENCE_GLASS, 0))
	var rim_n := int(surface.get(VoxelMaterial.ZOO_PLATE_RIM, 0))
	## Short pads live on the deck cell; summon gazebos also stamp turf there.
	var plate_n := 0
	for f in range(6):
		plate_n += int(surface.get(VoxelMaterial.zoo_turf_for_faction_index(f), 0))
	print(
		"voxels frame=%d line=%d glass=%d plate_rim=%d turf=%d"
		% [frame_n, line_n, glass_n, rim_n, plate_n]
	)
	if frame_n < 2000:
		_fail("FAIL containment ring frame too thin (%d)" % frame_n)
		return false
	if line_n < 500:
		_fail("FAIL not enough red energy line voxels (%d)" % line_n)
		return false
	if glass_n < 500:
		_fail("FAIL not enough fence glass (%d)" % glass_n)
		return false
	if rim_n < 400:
		_fail("FAIL short plates have almost no rim (%d)" % rim_n)
		return false
	if plate_n < 160:
		_fail("FAIL home-turf pads barely stamped (%d turf voxels)" % plate_n)
		return false
	## Recipe sites need recorded peaks for summon stations + battlefield bandstands.
	if layout.gazebo_roof_vox.size() < layout.spawner_vox.size():
		_fail(
			"FAIL gazebo roof list %d shorter than summon stations %d"
			% [layout.gazebo_roof_vox.size(), layout.spawner_vox.size()]
		)
		return false
	print("gazebo roof peaks recorded: %d" % layout.gazebo_roof_vox.size())
	## Faction pads may hide gems in the air cell above the glowing 2×2.
	var gem_n := 0
	for mat_id in range(VoxelMaterial.GEM_QUARTZ, VoxelMaterial.GEM_DIAMOND + 1):
		gem_n += int(above.get(mat_id, 0))
	print("gems above the deck (pad toppers + any other): %d" % gem_n)

	## The gate is the one hole: air all the way up through the ring line.
	var gate_mid_x := layout.gate_rect.position.x + layout.gate_rect.size.x / 2
	var gate_mid_z := layout.gate_rect.position.y + layout.gate_rect.size.y / 2
	var gate_air := _probe(blocks, gate_mid_x, deck + 4, gate_mid_z)
	if gate_air != VoxelMaterial.AIR:
		_fail(
			"FAIL gate mouth at (%d,%d,%d) is %d, expected open air"
			% [gate_mid_x, deck + 4, gate_mid_z, gate_air]
		)
		return false

	## The apron is a viewing box: panes on its lip, but the way in stays shootable.
	var veil_n := int(above.get(VoxelMaterial.LOS_VEIL, 0))
	if veil_n < 50:
		_fail("FAIL plaza has no viewing panes (%d veil voxels)" % veil_n)
		return false
	for step in range(1, 48):
		var walk := Vector2i(gate_mid_x, gate_mid_z) + layout.gate_dir * step
		if _probe(blocks, walk.x, deck + 2, walk.y) == VoxelMaterial.LOS_VEIL:
			_fail("FAIL the walk out of the plaza is veiled shut at %s" % walk)
			return false
	print("plaza viewing panes: %d veil voxels" % veil_n)

	## Arriving on a battlefield means holes in the deck, not a poured lawn.
	var holes := _count_deck_holes(blocks, layout, deck)
	print("deck holes punched by the scar pass: %d" % holes)
	if holes < 300:
		_fail("FAIL field reads unfought — only %d cratered deck columns" % holes)
		return false
	## Ruins have to survive the blasts, or there is nothing to fight in.
	var wall_n := (
		int(above.get(VoxelMaterial.BRICK, 0))
		+ int(above.get(VoxelMaterial.PLASTER, 0))
		+ int(above.get(VoxelMaterial.BRICK_DARK, 0))
	)
	if wall_n < 2000:
		_fail("FAIL scattered houses left only %d wall voxels standing" % wall_n)
		return false
	print("ruined house fabric standing: %d voxels" % wall_n)

	## Summon stations are open gazebos: a roof, lit posts, and a mid-face doorway wide
	## enough that a spawned body is not trapped under the roof.
	var pad := layout.spawner_vox[0]
	var roof := _probe(blocks, pad.x, deck + 9, pad.z)
	if roof != VoxelMaterial.ROOF_CLAY and roof != VoxelMaterial.ZOO_FENCE_LINE:
		roof = _probe(blocks, pad.x + 3, deck + 8, pad.z)
	if roof != VoxelMaterial.ROOF_CLAY and roof != VoxelMaterial.ZOO_FENCE_LINE:
		_fail(
			"FAIL summon station at %s has no gazebo roof (found %d)"
			% [pad, roof]
		)
		return false
	## South face middle must be air at body height — that is the walk-out.
	var door := _probe(blocks, pad.x, deck + 3, pad.z + 5)
	if door != VoxelMaterial.AIR:
		_fail("FAIL summon gazebo south door is blocked by mat %d" % door)
		return false
	var post := _probe(blocks, pad.x + 3, deck + 3, pad.z + 5)
	if post != VoxelMaterial.ZOO_FENCE_FRAME:
		_fail("FAIL summon gazebo has no end-of-face post (found %d)" % post)
		return false
	print("summon gazebo ok: roof mat %d, south door open, end posts standing" % roof)
	return true


## Field columns whose deck voxel is gone — craters, blast bowls and house cellars.
func _count_deck_holes(blocks: Dictionary, layout: ZooLayout, deck: int) -> int:
	var field := layout.field_rect
	var holes := 0
	for z in range(field.position.y, field.end.y, 2):
		for x in range(field.position.x, field.end.x, 2):
			if _probe(blocks, x, deck, z) == VoxelMaterial.AIR:
				holes += 1
	return holes


func _probe(blocks: Dictionary, x: int, y: int, z: int) -> int:
	var bp := Vector3i(
		int(floor(float(x) / float(BLOCK))),
		int(floor(float(y) / float(BLOCK))),
		int(floor(float(z) / float(BLOCK)))
	)
	if not blocks.has(bp):
		return -1
	var data: PackedByteArray = blocks[bp]
	var lx := x - bp.x * BLOCK
	var ly := y - bp.y * BLOCK
	var lz := z - bp.z * BLOCK
	if data.size() <= 2:
		return _u16(data, 0)
	## Column order is x-fastest within a z row; voxels are y-fastest inside a column.
	var col := lx + lz * BLOCK
	var idx := (col * BLOCK + ly) * 2
	if idx < 0 or idx + 1 >= data.size():
		return -1
	return _u16(data, idx)


## Zoo materials live above 255, so the low byte alone is a different material entirely.
func _u16(data: PackedByteArray, byte_index: int) -> int:
	return int(data[byte_index]) | (int(data[byte_index + 1]) << 8)


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
			var uid := _u16(data, 0)
			if uid == VoxelMaterial.AIR:
				continue
			counts[uid] = int(counts.get(uid, 0)) + BLOCK * BLOCK
			continue
		var columns := (data.size() / 2) / BLOCK
		for c in range(columns):
			var vid := _u16(data, (c * BLOCK + local_y) * 2)
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
			var uid := _u16(data, 0)
			if uid == VoxelMaterial.AIR:
				continue
			var layers := mini(BLOCK, block_y0 + BLOCK - (y + 1))
			counts[uid] = int(counts.get(uid, 0)) + layers * BLOCK * BLOCK
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			if block_y0 + (i % BLOCK) <= y:
				continue
			var vid := _u16(data, i * 2)
			if vid == VoxelMaterial.AIR:
				continue
			counts[vid] = int(counts.get(vid, 0)) + 1
	return counts


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
