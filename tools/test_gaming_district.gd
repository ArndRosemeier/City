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

	if _failed:
		_quit()
		return
	print("RESULT: OK")
	_quit()


func _quit() -> void:
	get_tree().quit(1 if _failed else 0)
