## Bake a Siege-theme district and assert the besieged quarter: an ordinary street grid that kept
## its lots and mid-tile roads, plus a Lodestone, a barricade ring and foundation pads on top.
##
## The load-bearing difference from every spectacle theme is that this one is *additive*. Arena,
## Zoo and friends replace the tile with one landmark and assert zero lots; a Siege tile has to
## still be a city, because the streets are the lanes the horde walks.
##
## Run: powershell -File tools\run_test.ps1 test_siege_district
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")

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
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.SIEGE, MAX_RING)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.SIEGE:
		_fail("FAIL no Siege theme in ring 0..%d for seed %d" % [MAX_RING, WORLD_SEED])
		_quit()
		return
	print("baking Siege district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.SIEGE)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	var quarter := planner.siege_quarter
	if quarter.size.x <= 0 or quarter.size.y <= 0:
		_fail("FAIL planner produced no siege_quarter")
		_quit()
		return
	if quarter.size.x != DistrictPlanner.SIEGE_QUARTER_CELLS:
		_fail(
			"FAIL quarter should be %d cells wide, got %d"
			% [DistrictPlanner.SIEGE_QUARTER_CELLS, quarter.size.x]
		)
		_quit()
		return
	if not Rect2i(0, 0, planner.cells_x, planner.cells_z).encloses(quarter):
		_fail("FAIL quarter %s is not inside the tile" % quarter)
		_quit()
		return
	if not quarter.intersects(planner.grand_plaza):
		_fail(
			"FAIL quarter %s does not contain the grand plaza %s"
			% [quarter, planner.grand_plaza]
		)
		_quit()
		return

	## Still a city: an additive theme that lost its lots or its inner streets is broken.
	var lots := 0
	var roads := 0
	var mid_roads := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif LandUse.is_road(tag):
				roads += 1
				if x >= x0 and x < x1 and z >= z0 and z < z1:
					mid_roads += 1
	print(
		"layout lots=%d roads=%d mid_roads=%d quarter=%s plaza=%s"
		% [lots, roads, mid_roads, quarter, planner.grand_plaza]
	)
	if lots < 50:
		_fail("FAIL Siege tile only has %d lots — it stopped being a city" % lots)
		_quit()
		return
	if mid_roads < 4:
		_fail("FAIL Siege tile has %d mid-tile roads — the lanes went missing" % mid_roads)
		_quit()
		return
	if planner.teleport_lot.x < 0:
		_fail("FAIL Siege tile has no teleport chamber, but it is a normal urban tile")
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
	if int(res["theme_id"]) != DistrictTheme.SIEGE:
		_fail("FAIL baked theme is %s not Siege" % res["theme_name"])
		_quit()
		return

	var gen: DistrictGenerator = res["generator"]
	var layout: SiegeLayout = gen.get_siege_layout()
	if layout == null:
		_fail("FAIL generator has no siege layout after bake")
		_quit()
		return
	print("layout: %s (bake %d ms)" % [layout.describe(), bake_ms])
	if not layout.is_valid():
		_fail("FAIL siege layout is not runnable: %s" % layout.describe())
		_quit()
		return
	if layout.gate_count() < SiegeComposer.GATE_MIN or layout.gate_count() > SiegeComposer.GATE_MAX:
		_fail(
			"FAIL expected %d..%d gates, got %d"
			% [SiegeComposer.GATE_MIN, SiegeComposer.GATE_MAX, layout.gate_count()]
		)
		_quit()
		return
	if layout.gate_dirs.size() != layout.gate_count():
		_fail("FAIL gate_dirs desynced from gates")
		_quit()
		return
	if layout.pad_count() < 4:
		_fail("FAIL only %d foundation pads — nowhere to mount a defence" % layout.pad_count())
		_quit()
		return
	if layout.pad_kinds.size() != layout.pad_count():
		_fail("FAIL pad_kinds desynced from pads")
		_quit()
		return
	if layout.count_of_kind(SiegeLayout.PadKind.STREET) < 4:
		_fail(
			"FAIL only %d street pads — the defence has to be mountable from the ground"
			% layout.count_of_kind(SiegeLayout.PadKind.STREET)
		)
		_quit()
		return
	## The seed is fixed, so this tile is deterministic: losing the roof tier entirely means the
	## roof probe broke, not that the city happened to come out flat.
	var roof_pads := (
		layout.count_of_kind(SiegeLayout.PadKind.ROOF_JUMP)
		+ layout.count_of_kind(SiegeLayout.PadKind.ROOF_HIGH)
	)
	if roof_pads < 1:
		_fail("FAIL no roof pads at all — the elevated tier went missing")
		_quit()
		return

	var qv := layout.quarter_vox
	if not qv.has_point(layout.lodestone_xz):
		_fail("FAIL Lodestone %s is outside the quarter %s" % [layout.lodestone_xz, qv])
		_quit()
		return
	for i in range(layout.pad_count()):
		var pad := layout.pads[i]
		if not qv.has_point(Vector2i(pad.x, pad.z)):
			_fail("FAIL pad %d at %s is outside the quarter %s" % [i, pad, qv])
			_quit()
			return
		var kind := layout.pad_kind_at(i)
		if kind == SiegeLayout.PadKind.STREET:
			if pad.y != layout.deck_y:
				_fail("FAIL street pad %d sits at y=%d, deck is %d" % [i, pad.y, layout.deck_y])
				_quit()
				return
		elif pad.y <= layout.deck_y:
			_fail("FAIL roof pad %d sits at y=%d, not above the deck %d" % [i, pad.y, layout.deck_y])
			_quit()
			return
		var rise := pad.y - layout.deck_y
		var reach := int(SiegeComposer.PLAYER_JUMP_M / 0.5)
		if kind == SiegeLayout.PadKind.ROOF_JUMP and rise > reach:
			_fail("FAIL pad %d is ROOF_JUMP but %d voxels up, past the %d reach" % [i, rise, reach])
			_quit()
			return
		if kind == SiegeLayout.PadKind.ROOF_HIGH and rise <= reach:
			_fail("FAIL pad %d is ROOF_HIGH but only %d voxels up, inside jump reach" % [i, rise])
			_quit()
			return
		if rise > SiegeComposer.ROOF_PAD_MAX_VOX:
			_fail(
				"FAIL pad %d is %d voxels up, past the %d cap the editable box is sized for"
				% [i, rise, SiegeComposer.ROOF_PAD_MAX_VOX]
			)
			_quit()
			return
		for j in range(i + 1, layout.pad_count()):
			var other := layout.pads[j]
			var d := Vector2(float(pad.x - other.x), float(pad.z - other.z)).length()
			if d < float(SiegeComposer.PAD_SPACING):
				_fail("FAIL pads %d and %d are only %.1f voxels apart" % [i, j, d])
				_quit()
				return

	## World-space helpers must offset by the district origin — the live brush has origin 0.
	var origin := Vector3i(480, 0, -960)
	var lode_world := layout.lodestone_world(origin)
	var want_lode := Vector3i(
		layout.lodestone_xz.x + origin.x,
		layout.lodestone_base_y + origin.y,
		layout.lodestone_xz.y + origin.z
	)
	if lode_world != want_lode:
		_fail("FAIL lodestone_world %s want %s" % [lode_world, want_lode])
		_quit()
		return
	if layout.pad_world(0, origin) != layout.pads[0] + origin:
		_fail("FAIL pad_world 0 did not offset by the district origin")
		_quit()
		return

	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	if deck != layout.deck_y:
		_fail("FAIL layout deck_y=%d but bake ground_thickness=%d" % [layout.deck_y, deck])
		_quit()
		return
	var above := _count_above_y(blocks, deck)
	var surface := _count_at_y(blocks, deck)
	var crystal_n := int(above.get(VoxelMaterial.GLASS_LIT, 0))
	var plate_n := int(surface.get(VoxelMaterial.METAL_PLATE, 0))
	var asphalt_n := int(surface.get(VoxelMaterial.ASPHALT, 0))
	print(
		"voxels crystal=%d pad_plate@deck=%d asphalt@deck=%d"
		% [crystal_n, plate_n, asphalt_n]
	)
	if crystal_n < 200:
		_fail("FAIL Lodestone crystal mass too small (%d GLASS_LIT above deck)" % crystal_n)
		_quit()
		return
	## 5 × 5 per pad, minus whatever the studs and overlaps eat.
	var want_plate := layout.pad_count() * 20
	if plate_n < want_plate:
		_fail(
			"FAIL pad plating too small: %d METAL_PLATE at deck, want >= %d for %d pads"
			% [plate_n, want_plate, layout.pad_count()]
		)
		_quit()
		return
	## The barricades and pads must not have paved over the carriageway the horde walks down.
	if asphalt_n < 20000:
		_fail("FAIL only %d ASPHALT at deck — the lanes got built over" % asphalt_n)
		_quit()
		return

	## Lodestone centre column is crystal all the way up from the plinth.
	var lode_mat := _probe(blocks, layout.lodestone_xz.x, deck + 4, layout.lodestone_xz.y)
	if lode_mat != VoxelMaterial.GLASS_LIT:
		_fail(
			"FAIL Lodestone core at (%d,%d,%d) is %d not GLASS_LIT"
			% [layout.lodestone_xz.x, deck + 4, layout.lodestone_xz.y, lode_mat]
		)
		_quit()
		return
	## Nothing in the Lodestone may be a GEM_* material, or the player could mine the objective
	## they are defending. Scoped to its own footprint on purpose: an ordinary urban tile carries a
	## gem chest or two elsewhere, and those are supposed to be minable.
	var lode_r := layout.lodestone_radius_vox + 1
	for dz in range(-lode_r, lode_r + 1):
		for dx in range(-lode_r, lode_r + 1):
			for y in range(deck, deck + layout.lodestone_height_vox + 3):
				var m := _probe(
					blocks, layout.lodestone_xz.x + dx, y, layout.lodestone_xz.y + dz
				)
				if m >= VoxelMaterial.GEM_QUARTZ and m <= VoxelMaterial.GEM_DIAMOND:
					_fail(
						"FAIL Lodestone voxel at (%d,%d,%d) is collectible gem %d — minable objective"
						% [layout.lodestone_xz.x + dx, y, layout.lodestone_xz.y + dz, m]
					)
					_quit()
					return

	## Barricade ring: sample the quarter edges and require the wall on most open columns.
	var walled := 0
	var probes := 0
	var ex0 := qv.position.x
	var ez0 := qv.position.y
	var ex1 := qv.position.x + qv.size.x - 1
	var ez1 := qv.position.y + qv.size.y - 1
	for x in range(ex0, ex1 + 1, 4):
		for ez in [ez0, ez1]:
			probes += 1
			if _probe(blocks, x, deck + 2, int(ez)) != VoxelMaterial.AIR:
				walled += 1
	for z in range(ez0, ez1 + 1, 4):
		for ex in [ex0, ex1]:
			probes += 1
			if _probe(blocks, int(ex), deck + 2, z) != VoxelMaterial.AIR:
				walled += 1
	print("barricade ring: %d of %d perimeter probes blocked" % [walled, probes])
	if probes <= 0:
		_fail("FAIL no perimeter probes taken")
		_quit()
		return
	if float(walled) / float(probes) < 0.6:
		_fail(
			"FAIL barricade ring too leaky: only %d of %d perimeter probes blocked"
			% [walled, probes]
		)
		_quit()
		return

	print("RESULT: OK")
	_quit()


## Everything a new theme has to be plumbed into before a tile of it can exist: the enum, the
## `--spawn-theme` parser, the specialness rule and its gamedata gem budget.
func _check_theme_wiring() -> bool:
	if DistrictTheme.SIEGE < 0 or DistrictTheme.SIEGE >= DistrictTheme.COUNT:
		_fail(
			"FAIL DistrictTheme.SIEGE is %d, outside 0..%d"
			% [DistrictTheme.SIEGE, DistrictTheme.COUNT - 1]
		)
		return false
	for alias in ["siege", "siege_quarter", "bulwark", "lodestone", "tower_defense"]:
		if DistrictTheme.parse_theme_id(alias) != DistrictTheme.SIEGE:
			_fail("FAIL --spawn-theme=%s does not resolve to the Siege theme" % alias)
			return false
	if DistrictTheme.parse_theme_id("Siege Quarter") != DistrictTheme.SIEGE:
		_fail("FAIL the Siege display name does not parse back to its own id")
		return false
	## The whole point of the theme: it keeps the street grid, so signposts and lots still apply.
	if DistrictTheme.is_special_id(DistrictTheme.SIEGE):
		_fail("FAIL Siege must not be a special theme — it keeps roads, lots and signposts")
		return false
	if GameData.theme_gem_total(DistrictTheme.SIEGE) <= 0:
		_fail("FAIL Siege has no district_gems.theme_totals budget")
		return false
	## The composer mirrors the player's jump to split ROOF_JUMP from ROOF_HIGH. If the walker is
	## retuned and this is not, every roof pad silently becomes cloudstone-only.
	var walker := CityWalkerScript.new()
	var jump_m: float = walker.jump_height_max_m
	walker.free()
	if not is_equal_approx(jump_m, SiegeComposer.PLAYER_JUMP_M):
		_fail(
			"FAIL SiegeComposer.PLAYER_JUMP_M is %.2f but CityWalker jumps %.2f m"
			% [SiegeComposer.PLAYER_JUMP_M, jump_m]
		)
		return false
	return true


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
		return int(data[0])
	## Column order is x-fastest within a z row; voxels are y-fastest inside a column.
	var col := lx + lz * BLOCK
	var idx := (col * BLOCK + ly) * 2
	if idx < 0 or idx + 1 >= data.size():
		return -1
	return int(data[idx])


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


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
