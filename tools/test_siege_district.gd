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

	var planner := _plan_for(coord)
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
	if (
		layout.breach_count() < SiegeComposer.BREACH_MIN
		or layout.breach_count() > SiegeComposer.BREACH_MAX
	):
		_fail(
			"FAIL expected %d..%d barricade breaches, got %d"
			% [SiegeComposer.BREACH_MIN, SiegeComposer.BREACH_MAX, layout.breach_count()]
		)
		_quit()
		return
	if layout.breach_dirs.size() != layout.breach_count():
		_fail("FAIL breach_dirs desynced from breaches")
		_quit()
		return
	## Five stones and eight mouths, or the run has no shield and no direction to come from.
	if layout.outer_stone_count() != SiegeComposer.OUTER_STONE_COUNT:
		_fail(
			"FAIL expected %d outer stones, got %d"
			% [SiegeComposer.OUTER_STONE_COUNT, layout.outer_stone_count()]
		)
		_quit()
		return
	if layout.hell_gate_count() != SiegeComposer.HELL_GATE_COUNT:
		_fail(
			"FAIL expected %d hell gates, got %d"
			% [SiegeComposer.HELL_GATE_COUNT, layout.hell_gate_count()]
		)
		_quit()
		return
	## Build sites are permissive by design: every position with room for a tower that will not
	## block a lane becomes one. A quarter this size yields a couple of hundred, so a handful means
	## a throttle crept back into the sweep — caps and cell strides are what used to hold it to 18.
	if layout.pad_count() < 120:
		_fail(
			"FAIL only %d build sites — the sweep is throttled, not permissive"
			% layout.pad_count()
		)
		_quit()
		return
	if layout.pad_kinds.size() != layout.pad_count():
		_fail("FAIL pad_kinds desynced from pads")
		_quit()
		return
	if layout.count_of_kind(SiegeLayout.PadKind.STREET) < 100:
		_fail(
			"FAIL only %d street sites — the defence has to be mountable from the ground"
			% layout.count_of_kind(SiegeLayout.PadKind.STREET)
		)
		_quit()
		return
	## The seed is fixed, so this tile is deterministic: a thin roof tier means the roof probe
	## broke, not that the city happened to come out flat. It has broken twice — once on the
	## same-surface spacing rule, once on a voxel probe that assumed solid buildings.
	var roof_pads := (
		layout.count_of_kind(SiegeLayout.PadKind.ROOF_JUMP)
		+ layout.count_of_kind(SiegeLayout.PadKind.ROOF_HIGH)
	)
	if roof_pads < 4:
		_fail("FAIL only %d roof sites — the elevated tier went missing" % roof_pads)
		_quit()
		return

	var qv := layout.quarter_vox
	if not qv.has_point(layout.lodestone_xz):
		_fail("FAIL Lodestone %s is outside the quarter %s" % [layout.lodestone_xz, qv])
		_quit()
		return
	for i in range(layout.pad_count()):
		var pad := layout.pads[i]
		## Sites live in the quarter or in a build ring around an outer stone. Anywhere else is a
		## site the player has no reason to be at and no stone to defend from it.
		if not qv.has_point(Vector2i(pad.x, pad.z)) and not _near_an_outer_stone(layout, pad):
			_fail(
				"FAIL pad %d at %s is neither in the quarter %s nor on an outer stone ring"
				% [i, pad, qv]
			)
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
		## Spacing is a same-surface rule. A roof pad and the sidewalk pad under it are not two
		## towers in one firing position, and enforcing the gap across levels would delete the
		## roof edges — a sidewalk runs along every facade.
		for j in range(i + 1, layout.pad_count()):
			var other := layout.pads[j]
			if absi(other.y - pad.y) > SiegeComposer.SAME_LEVEL_VOX:
				continue
			var d := Vector2(float(pad.x - other.x), float(pad.z - other.z)).length()
			if d < float(SiegeComposer.PAD_SPACING):
				_fail(
					"FAIL pads %d and %d share a surface but are only %.1f voxels apart"
					% [i, j, d]
				)
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

	if not _check_outer_stones(layout, blocks, deck, planner):
		_quit()
		return
	if not _check_hell_gates(layout, blocks, deck, planner):
		_quit()
		return
	if not _check_editable_bounds(gen, layout, deck):
		_quit()
		return
	if not _check_offcentre_tile():
		_quit()
		return

	print("RESULT: OK")
	_quit()


func _plan_for(coord: Vector2i) -> DistrictPlanner:
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.SIEGE)
	planner.build(
		DistrictCoord.SIZE_X_VOX,
		DistrictCoord.SIZE_Z_VOX,
		DistrictCoord.district_seed(WORLD_SEED, coord),
		DistrictCoord.CELL_SIZE,
		coord
	)
	return planner


## Everything above ran on whichever Siege tile the theme search returns first, and on this seed that
## one's grand plaza sits 14 voxels from the middle of the tile — so it says nothing about a tile
## where it does not.
##
## That gap shipped a bug: the stone ring and the gate ring were laid out around the *tile centre*
## while the Lodestone stands in the plaza, so on an off-centre tile the geometry was lopsided around
## the thing it is supposed to shield, and the mouths on the near side ended up beside the objective.
## This phase bakes the worst-offset Siege tile the seed has and re-runs the outer checks on it.
func _check_offcentre_tile() -> bool:
	var tile_mid := Vector2i(
		DistrictCoord.SIZE_X_VOX / 2, DistrictCoord.SIZE_Z_VOX / 2
	)
	var worst := Vector2i.ZERO
	var worst_off := -1.0
	var worst_planner: DistrictPlanner = null
	for ring in range(MAX_RING + 1):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if maxi(absi(cx), absi(cz)) != ring:
					continue
				var c := Vector2i(cx, cz)
				if DistrictTheme.for_district(WORLD_SEED, c).id != DistrictTheme.SIEGE:
					continue
				var p := _plan_for(c)
				if p.siege_quarter.size.x <= 0 or p.grand_plaza.size.x <= 0:
					continue
				var plaza_mid := p.grand_plaza.position + p.grand_plaza.size / 2
				var mid_vox := Vector2i(
					plaza_mid.x * DistrictCoord.CELL_SIZE + DistrictCoord.CELL_SIZE / 2,
					plaza_mid.y * DistrictCoord.CELL_SIZE + DistrictCoord.CELL_SIZE / 2
				)
				var off := Vector2(mid_vox - tile_mid).length()
				if off > worst_off:
					worst_off = off
					worst = c
					worst_planner = p
	if worst_planner == null:
		_fail("FAIL no Siege tile at all in ring 0..%d — the first phase should have caught that" % MAX_RING)
		return false
	print(
		"most off-centre Siege tile is %s, plaza %.0f voxels (%.0f m) off the tile middle"
		% [worst, worst_off, worst_off * 0.5]
	)

	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": worst,
		"world_seed": WORLD_SEED,
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL bake of %s: %s" % [worst, res.get("error", "?")])
		return false
	var gen: DistrictGenerator = res["generator"]
	var layout: SiegeLayout = gen.get_siege_layout()
	if layout == null or not layout.is_valid():
		_fail("FAIL the off-centre tile %s produced no runnable siege layout" % worst)
		return false
	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	if not _check_outer_stones(layout, blocks, deck, worst_planner):
		return false
	if not _check_hell_gates(layout, blocks, deck, worst_planner):
		return false
	return _check_editable_bounds(gen, layout, deck)


func _near_an_outer_stone(layout: SiegeLayout, pad: Vector3i) -> bool:
	for stone: SiegeLayout.Stone in layout.outer_stones:
		var d := Vector2(float(pad.x - stone.xz.x), float(pad.z - stone.xz.y)).length()
		if d <= float(SiegeComposer.OUTER_PAD_RING + SiegeComposer.PAD_HALF):
			return true
	return false


## The four stones that shield the centre. They stand in ordinary city well outside the barricade —
## a stone inside the wall would shield nothing — and they are the same lit glass as the Lodestone so
## they read as the same kind of thing, without being minable.
func _check_outer_stones(
	layout: SiegeLayout, blocks: Dictionary, deck: int, planner: DistrictPlanner
) -> bool:
	var qv := layout.quarter_vox
	var tile := Rect2i(0, 0, planner.cells_x * DistrictCoord.CELL_SIZE, planner.cells_z * DistrictCoord.CELL_SIZE)
	for i in range(layout.outer_stone_count()):
		var stone := layout.outer_stone_at(i)
		if qv.has_point(stone.xz):
			_fail("FAIL outer stone %d at %s stands inside the quarter it shields" % [i, stone.xz])
			return false
		if not tile.has_point(stone.xz):
			_fail("FAIL outer stone %d at %s is off the tile %s" % [i, stone.xz, tile])
			return false
		var gap := Vector2(
			float(stone.xz.x - layout.lodestone_xz.x), float(stone.xz.y - layout.lodestone_xz.y)
		).length()
		if gap < float(SiegeComposer.OUTER_RING_Z - SiegeComposer.SITE_SEARCH_MAX):
			_fail("FAIL outer stone %d is only %.0f voxels from the centre" % [i, gap])
			return false
		## Two stones on one flank is one flank with two crystals on it. Only reachable when the tile
		## edge forced their ideal points together, which is exactly the case worth catching.
		for j in range(i + 1, layout.outer_stone_count()):
			var other := layout.outer_stone_at(j)
			var apart := Vector2(
				float(stone.xz.x - other.xz.x), float(stone.xz.y - other.xz.y)
			).length()
			if apart < float(SiegeComposer.OUTER_STONE_MIN_GAP):
				_fail(
					"FAIL outer stones %d and %d are only %.0f voxels apart" % [i, j, apart]
				)
				return false
		var core := _probe(blocks, stone.xz.x, deck + 4, stone.xz.y)
		if core != VoxelMaterial.GLASS_LIT:
			_fail(
				"FAIL outer stone %d core at (%d,%d,%d) is %d not GLASS_LIT"
				% [i, stone.xz.x, deck + 4, stone.xz.y, core]
			)
			return false
		if not _check_obelisk(i, stone, layout, blocks, deck):
			return false
		var r := stone.radius_vox + 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				for y in range(deck, deck + stone.height_vox + 3):
					var m := _probe(blocks, stone.xz.x + dx, y, stone.xz.y + dz)
					if m >= VoxelMaterial.GEM_QUARTZ and m <= VoxelMaterial.GEM_DIAMOND:
						_fail(
							"FAIL outer stone %d has collectible gem %d at (%d,%d,%d)"
							% [i, m, stone.xz.x + dx, y, stone.xz.y + dz]
						)
						return false
	print("outer stones: %d obelisks outside the wall" % layout.outer_stone_count())
	return true


## The shape rule, which is a usability rule rather than a cosmetic one: these have to be tellable
## from the Lodestone at a glance. A player who cannot tell them apart walks to a stone, finds no
## staking console, and has no way to start the mode at all — that is how this was reported.
##
## So: a slender needle, not a scaled-down copy of the crystal. The shaft is checked narrow at
## mid-height where the Lodestone is at its widest, and taller than the Lodestone overall.
func _check_obelisk(
	i: int, stone: SiegeLayout.Stone, layout: SiegeLayout, blocks: Dictionary, deck: int
) -> bool:
	if stone.height_vox <= 0:
		_fail("FAIL outer stone %d has no height" % i)
		return false
	var mid := deck + 2 + stone.height_vox / 2
	var edge := SiegeComposer.OBELISK_SHAFT_HALF + 1
	var beside := _probe(blocks, stone.xz.x + edge, mid, stone.xz.y)
	if beside != VoxelMaterial.AIR:
		_fail(
			"FAIL outer stone %d is %d voxels wide at mid-height — that is a crystal, not an obelisk"
			% [i, edge * 2 + 1]
		)
		return false
	if _probe(blocks, stone.xz.x, mid, stone.xz.y) != VoxelMaterial.GLASS_LIT:
		_fail("FAIL outer stone %d has no shaft at mid-height" % i)
		return false
	if stone.height_vox <= layout.lodestone_height_vox:
		_fail(
			"FAIL outer stone %d is %d voxels tall, no taller than the Lodestone's %d"
			% [i, stone.height_vox, layout.lodestone_height_vox]
		)
		return false
	## And the Lodestone must still be the broad one, or the two silhouettes have simply swapped.
	var lode_flank := _probe(
		blocks,
		layout.lodestone_xz.x + SiegeComposer.OBELISK_SHAFT_HALF + 1,
		deck + 4,
		layout.lodestone_xz.y
	)
	if lode_flank != VoxelMaterial.GLASS_LIT:
		_fail("FAIL the Lodestone is as narrow as an obelisk — the two read the same")
		return false
	return true


## The mouths the horde comes out of. Two things have to hold or the portal is decoration: the frame
## is containment-kit material (which is `Hardness.NEVER`, so it cannot be dismantled) and the mouth
## is `LOS_VEIL` (walk-through, but opaque to shots — the anti-spawn-camp rule, mechanically).
func _check_hell_gates(
	layout: SiegeLayout, blocks: Dictionary, deck: int, planner: DistrictPlanner
) -> bool:
	var qv := layout.quarter_vox
	var tile := Rect2i(0, 0, planner.cells_x * DistrictCoord.CELL_SIZE, planner.cells_z * DistrictCoord.CELL_SIZE)
	var veiled := 0
	for i in range(layout.hell_gate_count()):
		var gate := layout.hell_gate_at(i)
		var mouth := Vector2i(gate.mouth.x, gate.mouth.z)
		if qv.has_point(mouth):
			_fail("FAIL hell gate %d opens inside the barricaded quarter at %s" % [i, mouth])
			return false
		if not tile.has_point(mouth):
			_fail("FAIL hell gate %d at %s is off the tile %s" % [i, mouth, tile])
			return false
		## Standoff from every stone. A mouth beside the thing it besieges means the wave is already
		## on the objective when it appears, with no ground for the player to hold — which is how
		## this shipped the first time, with one gate of each pair ~25 m from its own stone.
		if not _check_gate_standoff(i, mouth, layout):
			return false
		var veil := _probe(blocks, gate.mouth.x, deck + 4, gate.mouth.z)
		if veil != VoxelMaterial.LOS_VEIL:
			_fail(
				"FAIL hell gate %d mouth at (%d,%d,%d) is %d not LOS_VEIL — shootable spawn"
				% [i, gate.mouth.x, deck + 4, gate.mouth.z, veil]
			)
			return false
		veiled += 1
		var along := Vector2i(-gate.outward.y, gate.outward.x)
		var post := SiegeComposer.HELL_GATE_HALF_W + 1
		var frame := _probe(
			blocks,
			gate.mouth.x + along.x * post,
			deck + 4,
			gate.mouth.z + along.y * post
		)
		if not VoxelMaterial.is_zoo_fence(frame):
			_fail(
				"FAIL hell gate %d pillar is %d, not containment-kit fence — a breakable portal"
				% [i, frame]
			)
			return false
		## The step the horde takes out of the mouth has to be standable, or bodies spawn in a wall.
		var step := _probe(
			blocks,
			gate.mouth.x - gate.outward.x * 3,
			deck + 1,
			gate.mouth.z - gate.outward.y * 3
		)
		if step != VoxelMaterial.AIR:
			_fail(
				"FAIL hell gate %d has %d blocking the step out of its mouth" % [i, step]
			)
			return false
	print("hell gates: %d veiled, unbreakable mouths outboard of the stones" % veiled)
	return true


func _check_gate_standoff(i: int, mouth: Vector2i, layout: SiegeLayout) -> bool:
	var want := float(SiegeComposer.GATE_STONE_CLEAR)
	var to_lode := Vector2(
		float(mouth.x - layout.lodestone_xz.x), float(mouth.y - layout.lodestone_xz.y)
	).length()
	if to_lode < want:
		_fail(
			"FAIL hell gate %d is %.0f voxels from the Lodestone, inside the %.0f standoff"
			% [i, to_lode, want]
		)
		return false
	for s in range(layout.outer_stone_count()):
		var stone := layout.outer_stone_at(s)
		var d := Vector2(float(mouth.x - stone.xz.x), float(mouth.y - stone.xz.y)).length()
		if d < want:
			_fail(
				"FAIL hell gate %d is %.0f voxels from outer stone %d, inside the %.0f standoff"
				% [i, d, s, want]
			)
			return false
	return true


## The one check the bake path cannot fail but play can. A baked tile writes into a fresh block map
## and takes everything; the *streamed* path routes decoration through `open_space_bounds` and
## silently drops any write outside it. Siege is the only theme whose writes leave its reserve, so
## every outer stone apex, every gate lintel and every pad on an outer ring has to be inside a
## declared box — otherwise the stones exist in the layout, the controller registers beacons at them,
## and the player sees nothing there.
func _check_editable_bounds(gen: DistrictGenerator, layout: SiegeLayout, deck: int) -> bool:
	var bounds := gen.open_space_bounds()
	if bounds.is_empty():
		_fail("FAIL a Siege tile declared no editable bounds — every outer write would be dropped")
		return false
	var origin := gen.origin_vox
	for i in range(layout.outer_stone_count()):
		var stone := layout.outer_stone_at(i)
		var apex := Vector3i(stone.xz.x, stone.base_y + 2 + stone.height_vox, stone.xz.y)
		if not _inside_any(bounds, apex + origin):
			_fail("FAIL outer stone %d apex %s is outside every editable box" % [i, apex])
			return false
	for i in range(layout.hell_gate_count()):
		var gate := layout.hell_gate_at(i)
		var lintel := Vector3i(gate.mouth.x, deck + 2 + SiegeComposer.HELL_GATE_H, gate.mouth.z)
		if not _inside_any(bounds, lintel + origin):
			_fail("FAIL hell gate %d lintel %s is outside every editable box" % [i, lintel])
			return false
	var outer_pads := 0
	for i in range(layout.pad_count()):
		var pad := layout.pads[i]
		if layout.quarter_vox.has_point(Vector2i(pad.x, pad.z)):
			continue
		outer_pads += 1
		## Pads are plated at their own level and studded a little above it.
		if not _inside_any(bounds, Vector3i(pad.x, pad.y + 2, pad.z) + origin):
			_fail("FAIL outer-ring pad %d at %s is outside every editable box" % [i, pad])
			return false
	if outer_pads <= 0:
		_fail("FAIL no build sites outside the quarter — the outer stones have no defence")
		return false
	print(
		"editable bounds: %d boxes cover 4 stone apexes, 8 lintels and %d outer-ring pads"
		% [bounds.size(), outer_pads]
	)
	return true


## Inclusive on both faces, unlike `AABB.has_point`: these boxes are voxel extents, and a write at
## the top course of a box is inside it.
func _inside_any(bounds: Array[AABB], p: Vector3i) -> bool:
	var v := Vector3(float(p.x), float(p.y), float(p.z))
	for b: AABB in bounds:
		var hi := b.position + b.size
		if (
			v.x >= b.position.x and v.x <= hi.x
			and v.y >= b.position.y and v.y <= hi.y
			and v.z >= b.position.z and v.z <= hi.z
		):
			return true
	return false


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
		return _u16(data, 0)
	## Column order is x-fastest within a z row; voxels are y-fastest inside a column.
	var col := lx + lz * BLOCK
	var idx := (col * BLOCK + ly) * 2
	if idx < 0 or idx + 1 >= data.size():
		return -1
	return _u16(data, idx)


## The containment-kit materials the hell gates are built from live above 255, so the low byte alone
## is a different material entirely — `ZOO_FENCE_FRAME` (257) reads back as `BEDROCK` (1).
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
