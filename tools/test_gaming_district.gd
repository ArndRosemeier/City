## Bake a Gaming-theme district and assert plaza layout + dual-board hooks.
##
## Run: powershell -File tools\run_test.ps1 test_gaming_district -TimeoutSec 300
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const WORLD_SEED := 42
const MAX_RING := 10

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	if DistrictTheme.parse_theme_id("gaming") != DistrictTheme.GAMING:
		_fail("FAIL parse_theme_id gaming")
		_quit()
		return
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.GAMING, MAX_RING)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.GAMING:
		_fail("FAIL no Gaming theme in ring 0..%d for seed %d" % [MAX_RING, WORLD_SEED])
		_quit()
		return
	print("baking Gaming district at %s" % coord)

	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.GAMING)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_gaming.size.x <= 0:
		_fail("FAIL planner produced no large_gaming")
		_quit()
		return
	var gaming_cells := 0
	var lots := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if tag == LandUse.GAMING:
				gaming_cells += 1
			elif LandUse.is_lot(tag):
				lots += 1
	print("layout gaming_cells=%d lots=%d rect=%s" % [gaming_cells, lots, planner.large_gaming])
	if lots > 0:
		_fail("FAIL Gaming layout still has %d lots" % lots)
		_quit()
		return
	if gaming_cells < 100:
		_fail("FAIL Gaming layout only has %d gaming cells" % gaming_cells)
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
	if int(res["theme_id"]) != DistrictTheme.GAMING:
		_fail("FAIL baked theme is %s not Gaming" % res["theme_name"])
		_quit()
		return

	var gen: DistrictGenerator = res["generator"]
	var layout: GamingLayout = gen.get_gaming_layout()
	if layout == null:
		_fail("FAIL generator has no gaming layout after bake")
		_quit()
		return
	print("layout: %s (bake %d ms)" % [layout.describe(), bake_ms])
	if layout.board_n != 19:
		_fail("FAIL board_n %d" % layout.board_n)
		_quit()
		return
	if layout.main_table_origin == Vector3i.ZERO and layout.pad_min == Vector3i.ZERO:
		_fail("FAIL empty main table / pad")
		_quit()
		return
	if layout.field_span_vox != (19 - 1) * layout.giant_cell_vox:
		_fail("FAIL field_span_vox %d" % layout.field_span_vox)
		_quit()
		return
	if layout.giant_span_vox() != (19 - 1) * layout.giant_cell_vox:
		_fail("FAIL giant span mismatch")
		_quit()
		return
	if layout.cell_vox_for(9) < layout.giant_cell_vox:
		_fail("FAIL 9x9 cell should be >= bake cell")
		_quit()
		return
	if GamingComposer.hoshi_points(9) != PackedInt32Array([2, 4, 6]):
		_fail("FAIL 9x9 hoshi")
		_quit()
		return
	if GamingComposer.TABLE_W < 16:
		_fail("FAIL table too narrow for board+settings (%d)" % GamingComposer.TABLE_W)
		_quit()
		return

	## Dual-view board state smoke (no runtime arena — bake has no tree).
	var board := GoBoardState.new()
	board.setup(19)
	assert(board.try_play(GoBoardState.BLACK, "D4"))
	assert(board.try_play(GoBoardState.WHITE, "Q16"))
	var board9 := GoBoardState.new()
	board9.setup(9)
	assert(board9.try_play(GoBoardState.BLACK, "E5"))
	assert(board9.try_play(GoBoardState.WHITE, "C3"))

	var blocks: Dictionary = res["blocks"]
	var deck := int(res["ground_thickness"])
	var maze_y := deck + 1
	if layout.fence_rect.size.x <= 0 or layout.gate_rects.size() != 4:
		_fail(
			"FAIL fence %s gates=%d" % [layout.fence_rect, layout.gate_rects.size()]
		)
		_quit()
		return
	if layout.wall_rect.size.x <= 0 or layout.wall_gate_rects.size() != 4:
		_fail(
			"FAIL wall %s gates=%d" % [layout.wall_rect, layout.wall_gate_rects.size()]
		)
		_quit()
		return
	## Maze band between festive wall and zoo fence.
	var fence := layout.fence_rect
	var wall := layout.wall_rect
	var maze_x := (fence.position.x + wall.position.x) / 2
	var maze_z := fence.position.y + fence.size.y / 2
	var found_maze := false
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			if VoxelMaterial.is_fractal_band(_probe(blocks, maze_x + dx, maze_y, maze_z + dz)):
				found_maze = true
				break
		if found_maze:
			break
	if not found_maze:
		_fail("FAIL no fractal maze walls in band near (%d,%d)" % [maze_x, maze_z])
		_quit()
		return
	## Attraction ring face (not a gate) should be zoo fence material.
	var ring_x := fence.position.x
	var ring_z := fence.position.y + GATE_PROBE_OFF
	if layout.gate_rects[2].has_point(Vector2i(ring_x, ring_z)):
		ring_z = fence.end.y - GATE_PROBE_OFF
	var ring_mat := _probe(blocks, ring_x, deck + 3, ring_z)
	if not VoxelMaterial.is_zoo_fence(ring_mat):
		_fail(
			"FAIL fence at (%d,%d) is %d not zoo fence" % [ring_x, ring_z, ring_mat]
		)
		_quit()
		return
	## Festive outer wall — colourful body mat, not maze / zoo fence / air.
	var wall_x := wall.position.x
	var wall_z := wall.position.y + GATE_PROBE_OFF
	if layout.wall_gate_rects[2].has_point(Vector2i(wall_x, wall_z)):
		wall_z = wall.end.y - GATE_PROBE_OFF
	var wall_mat := _probe(blocks, wall_x, deck + 4, wall_z)
	if (
		VoxelMaterial.is_fractal_band(wall_mat)
		or VoxelMaterial.is_zoo_fence(wall_mat)
		or wall_mat == VoxelMaterial.AIR
		or wall_mat < 0
	):
		_fail(
			"FAIL district wall at (%d,%d) is %d (want festive body)"
			% [wall_x, wall_z, wall_mat]
		)
		_quit()
		return
	## Inside the court must not still be solid maze at the pad centre.
	var pad_cx := (layout.pad_min.x + layout.pad_max.x) / 2
	var pad_cz := (layout.pad_min.z + layout.pad_max.z) / 2
	var pad_mat := _probe(blocks, pad_cx, maze_y + 2, pad_cz)
	if VoxelMaterial.is_fractal_band(pad_mat):
		_fail("FAIL Go pad still has maze wall at (%d,%d)" % [pad_cx, pad_cz])
		_quit()
		return
	print(
		"gaming court: wall=%s/%d fence=%s/%d maze ok, pad clear"
		% [wall, layout.wall_gate_rects.size(), fence, layout.gate_rects.size()]
	)

	if _failed:
		_quit()
		return
	print("RESULT: OK")
	_quit()


const BLOCK := 16
## Offset along a fence face that stays clear of the mid-edge gate opening.
const GATE_PROBE_OFF := 18


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
	var col := lx + lz * BLOCK
	var idx := (col * BLOCK + ly) * 2
	if idx < 0 or idx + 1 >= data.size():
		return -1
	return _u16(data, idx)


## Zoo fence ids live above 255 — the low byte alone is a different material entirely.
func _u16(data: PackedByteArray, byte_index: int) -> int:
	return int(data[byte_index]) | (int(data[byte_index + 1]) << 8)


func _quit() -> void:
	get_tree().quit(1 if _failed else 0)
