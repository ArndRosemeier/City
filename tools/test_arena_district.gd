## Bake an Arena-theme district and assert the colosseum shell: open reserve, sand pit,
## indestructible ARENA_SHELL mass, and a layout with four board mounts + four lift pads.
##
## Run: powershell -File tools\run_test.ps1 test_arena_district
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
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.ARENA, MAX_RING)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.ARENA:
		_fail("FAIL no Arena theme in ring 0..%d for seed %d" % [MAX_RING, WORLD_SEED])
		_quit()
		return
	print("baking Arena district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.ARENA)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_arena.size.x <= 0:
		_fail("FAIL planner produced no large_arena")
		_quit()
		return
	var lots := 0
	var arena_cells := 0
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
			elif tag == LandUse.ARENA:
				arena_cells += 1
			elif LandUse.is_road(tag):
				roads += 1
				if x >= x0 and x < x1 and z >= z0 and z < z1:
					mid_roads += 1
	print(
		"layout lots=%d arena_cells=%d roads=%d mid_roads=%d arena_rect=%s"
		% [lots, arena_cells, roads, mid_roads, planner.large_arena]
	)
	if lots > 0:
		_fail("FAIL Arena layout still has %d lots" % lots)
		_quit()
		return
	if arena_cells < 100:
		_fail("FAIL Arena layout only has %d arena cells" % arena_cells)
		_quit()
		return
	if roads < 8:
		_fail("FAIL Arena layout has too few road cells (%d)" % roads)
		_quit()
		return
	if mid_roads > 0:
		_fail("FAIL Arena middle still has %d road cells — expected edge stubs only" % mid_roads)
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
	if int(res["theme_id"]) != DistrictTheme.ARENA:
		_fail("FAIL baked theme is %s not Arena" % res["theme_name"])
		_quit()
		return

	var gen: DistrictGenerator = res["generator"]
	var layout: ArenaLayout = gen.get_arena_layout()
	if layout == null:
		_fail("FAIL generator has no arena layout after bake")
		_quit()
		return
	print("layout: %s (bake %d ms)" % [layout.describe(), bake_ms])
	if layout.board_mounts.size() != 4:
		_fail("FAIL expected 4 board mounts, got %d" % layout.board_mounts.size())
		_quit()
		return
	if layout.lift_pads.size() != 4:
		_fail("FAIL expected 4 lift pads, got %d" % layout.lift_pads.size())
		_quit()
		return
	if layout.gate_rects.size() != 4:
		_fail("FAIL expected 4 gates, got %d" % layout.gate_rects.size())
		_quit()
		return
	if layout.outer_rect.size.x != 100 or layout.outer_rect.size.y != 100:
		_fail("FAIL outer should be 100×100 voxels (50 m), got %s" % layout.outer_rect.size)
		_quit()
		return
	if layout.pit_rect.size.x < 40 or layout.pit_rect.size.y < 40:
		_fail("FAIL pit too small: %s" % layout.pit_rect)
		_quit()
		return
	if layout.seating_y <= layout.pit_wall_top_y:
		_fail(
			"FAIL seating_y=%d must sit above pit_wall_top_y=%d"
			% [layout.seating_y, layout.pit_wall_top_y]
		)
		_quit()
		return
	if not layout.outer_rect.encloses(layout.pit_rect):
		_fail("FAIL pit not inside outer mass")
		_quit()
		return
	if RoomDecorator.purpose_name(RoomDecorator.Purpose.ARENA_PIT) != "arena_pit":
		_fail("FAIL ARENA_PIT purpose name")
		_quit()
		return
	if RoomDecorator.purpose_name(RoomDecorator.Purpose.ARENA) != "arena":
		_fail("FAIL ARENA purpose name")
		_quit()
		return
	if RoomDecorator.purpose_from_name("arena") != RoomDecorator.Purpose.ARENA:
		_fail("FAIL purpose_from_name arena")
		_quit()
		return
	if RoomDecorator.purpose_from_name("arena_pit") != RoomDecorator.Purpose.ARENA_PIT:
		_fail("FAIL purpose_from_name arena_pit")
		_quit()
		return
	if VoxelMaterial.is_destructible(VoxelMaterial.ARENA_SHELL):
		_fail("FAIL ARENA_SHELL must not be destructible")
		_quit()
		return
	## Live brush is world-voxel space — decorate/clear must shift the pit by district origin.
	var origin := Vector3i(480, 0, -960)
	var world_vol := layout.pit_volume_world(origin)
	var local_vol := layout.pit_volume()
	if world_vol.rect.position != local_vol.rect.position + Vector2i(origin.x, origin.z):
		_fail(
			"FAIL pit_volume_world XZ %s want local+origin %s"
			% [world_vol.rect.position, local_vol.rect.position + Vector2i(origin.x, origin.z)]
		)
		_quit()
		return
	if world_vol.floor_y != local_vol.floor_y + origin.y:
		_fail("FAIL pit_volume_world floor_y %d" % world_vol.floor_y)
		_quit()
		return
	if world_vol.keep_clear.size() != local_vol.keep_clear.size():
		_fail("FAIL pit_volume_world keep_clear count")
		_quit()
		return
	print("pit_volume_world: ok offset=%s" % origin)

	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	var above := _count_above_y(blocks, deck)
	var surface := _count_at_y(blocks, deck)
	var shell_n := int(above.get(VoxelMaterial.ARENA_SHELL, 0)) + int(
		surface.get(VoxelMaterial.ARENA_SHELL, 0)
	)
	var dirt_n := int(surface.get(VoxelMaterial.DIRT, 0))
	var gravel_n := int(surface.get(VoxelMaterial.GRAVEL, 0))
	print("voxels shell=%d dirt@deck=%d gravel@deck=%d" % [shell_n, dirt_n, gravel_n])
	if shell_n < 8000:
		_fail("FAIL ARENA_SHELL mass too small (%d)" % shell_n)
		_quit()
		return
	if dirt_n < 2000:
		_fail("FAIL sand pit floor missing (dirt@deck=%d)" % dirt_n)
		_quit()
		return

	## North pit wall off the gate centre (gates punch the mid-face).
	var pit := layout.pit_rect
	var wx := pit.position.x + pit.size.x / 2 + 18
	var wz := pit.position.y - 1
	var wall_mat := _probe(blocks, wx, deck + 4, wz)
	if wall_mat != VoxelMaterial.ARENA_SHELL:
		_fail(
			"FAIL pit wall at (%d,%d,%d) is %d not ARENA_SHELL"
			% [wx, deck + 4, wz, wall_mat]
		)
		_quit()
		return
	var sand_mat := _probe(blocks, wx, deck, pit.position.y + 8)
	if sand_mat != VoxelMaterial.DIRT:
		_fail("FAIL pit sand is %d not DIRT" % sand_mat)
		_quit()
		return
	if VoxelMaterial.is_destructible(VoxelMaterial.LOS_VEIL):
		_fail("FAIL LOS_VEIL must not be destructible")
		_quit()
		return
	## Seating lip outside the pit wall — invisible walk-through LOS blocker.
	## Offset from the face mid so we are not on the gate clear or the board parapet.
	var lip_x := pit.position.x + pit.size.x / 2 + 22
	var lip_z := pit.position.y - 4
	var veil_mat := _probe(blocks, lip_x, layout.seating_y + 2, lip_z)
	if veil_mat != VoxelMaterial.LOS_VEIL:
		_fail(
			"FAIL tribune lip at (%d,%d,%d) is %d not LOS_VEIL"
			% [lip_x, layout.seating_y + 2, lip_z, veil_mat]
		)
		_quit()
		return
	## Gate mouth must keep a full-height LOS curtain (stair tunnel used to leave a
	## shoot-through hole at the summon UI).
	var gate_mid_x := pit.position.x + pit.size.x / 2
	var gate_lip_z := pit.position.y - 4
	var gate_veil_low := _probe(blocks, gate_mid_x, deck + 4, gate_lip_z)
	if gate_veil_low != VoxelMaterial.LOS_VEIL:
		_fail(
			"FAIL gate LOS curtain at (%d,%d,%d) is %d not LOS_VEIL"
			% [gate_mid_x, deck + 4, gate_lip_z, gate_veil_low]
		)
		_quit()
		return
	## Board parapet is restored after the gate carve — no hole where stairs meet UI.
	var board_z := pit.position.y - 5
	var board_mat := _probe(blocks, gate_mid_x, layout.seating_y + 2, board_z)
	if board_mat != VoxelMaterial.ARENA_SHELL:
		_fail(
			"FAIL board parapet at gate mid (%d,%d,%d) is %d not ARENA_SHELL"
			% [gate_mid_x, layout.seating_y + 2, board_z, board_mat]
		)
		_quit()
		return
	var veil_n := int(above.get(VoxelMaterial.LOS_VEIL, 0))
	if veil_n < 200:
		_fail("FAIL LOS_VEIL mass too small (%d)" % veil_n)
		_quit()
		return

	print("RESULT: OK")
	_quit()


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
