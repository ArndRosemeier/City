## Bake real districts and measure nav span-field size at 0.5 m vs 1 m columns.
##
## Locks nav resolution / height ceiling before the Rust baker (plan todo `measure`).
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/measure_nav_spans.tscn
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const NavSolidity := preload("res://scripts/city/nav_solidity.gd")
const NavSpanMeasure := preload("res://scripts/city/nav_span_measure.gd")

const WORLD_SEED := 42
## Representative tiles: dense core (many floors), caves, catacombs, water, midrise.
## CORE_HIGHRISE, OLD_TOWN, HILL, GRAVEYARD, LAKE
const THEMES := [0, 1, 5, 6, 7]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var solidity: NavSolidity = NavSolidity.build()
	_assert_solidity(solidity)
	if _failed:
		_quit()
		return

	var counts := solidity.count_by_kind()
	print(
		"NavSolidity COUNT=%d PASSABLE=%d WATER=%d SOLID=%d PARTIAL=%d"
		% [VoxelMaterial.COUNT, counts[0], counts[1], counts[2], counts[3]]
	)
	for id in range(VoxelMaterial.COUNT):
		if int(solidity.kind[id]) == NavSolidity.Kind.PARTIAL:
			print(
				"  PARTIAL id=%d top_frac=%.3f"
				% [id, solidity.top_frac[id]]
			)
		elif int(solidity.kind[id]) == NavSolidity.Kind.WATER:
			print("  WATER id=%d" % id)
		elif int(solidity.kind[id]) == NavSolidity.Kind.PASSABLE and id != VoxelMaterial.AIR:
			print("  PASSABLE id=%d" % id)

	print("")
	print("=== District span measurements (seed %d) ===" % WORLD_SEED)

	var results: Array[Dictionary] = []
	for theme_id in THEMES:
		var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, theme_id, 12)
		var theme := DistrictTheme.for_district(WORLD_SEED, coord)
		if theme.id != theme_id:
			_fail("FAIL theme lookup returned %s for requested %d" % [theme.display_name, theme_id])
			_quit()
			return
		print("")
		print("--- baking %s at %s ---" % [theme.display_name, coord])
		var t0 := Time.get_ticks_msec()
		var res: Dictionary = DistrictBakeJobScript.bake({
			"coord": coord,
			"world_seed": WORLD_SEED,
		})
		var bake_ms := Time.get_ticks_msec() - t0
		if not bool(res.get("ok", false)):
			_fail("FAIL bake %s: %s" % [theme.display_name, res.get("error", "?")])
			_quit()
			return
		var blocks: Dictionary = res["blocks"]
		var size_x: int = int(res["size_x"])
		var size_z: int = int(res["size_z"])
		print("bake ok in %d ms, blocks=%d size=%dx%d" % [bake_ms, blocks.size(), size_x, size_z])

		var fine: NavSpanMeasure = NavSpanMeasure.new(solidity)
		fine.measure(blocks, size_x, size_z, 1)
		for line in fine.summary_lines("0.5m columns"):
			print(line)

		var coarse: NavSpanMeasure = NavSpanMeasure.new(solidity)
		coarse.measure(blocks, size_x, size_z, 2)
		for line in coarse.summary_lines("1.0m cells (2-voxel)"):
			print(line)

		results.append({
			"theme": theme.display_name,
			"coord": coord,
			"fine": fine,
			"coarse": coarse,
		})

	print("")
	print("=== Recommendation inputs ===")
	var worst_fine_mem := 0
	var worst_coarse_mem := 0
	var worst_fine_spans := 0
	var worst_name := ""
	for row: Dictionary in results:
		var f: NavSpanMeasure = row["fine"]
		var c: NavSpanMeasure = row["coarse"]
		var name: String = row["theme"]
		print(
			(
				"%-22s  0.5m: spans=%7d avg=%.3f mem~%5.2f MiB | "
				+ "1.0m: spans=%7d avg=%.3f mem~%5.2f MiB"
			)
			% [
				name,
				f.span_count,
				f.spans_per_column_avg(),
				float(f.estimated_memory_bytes()) / (1024.0 * 1024.0),
				c.span_count,
				c.spans_per_column_avg(),
				float(c.estimated_memory_bytes()) / (1024.0 * 1024.0),
			]
		)
		if f.estimated_memory_bytes() > worst_fine_mem:
			worst_fine_mem = f.estimated_memory_bytes()
			worst_fine_spans = f.span_count
			worst_name = name
		worst_coarse_mem = maxi(worst_coarse_mem, c.estimated_memory_bytes())

	## Nine streamed districts is the live working set upper bound called out in the plan.
	var live_fine := worst_fine_mem * 9
	var live_coarse := worst_coarse_mem * 9
	print("")
	print(
		"worst tile (%s): %.2f MiB @ 0.5m (%d spans); x9 districts ~ %.2f MiB"
		% [
			worst_name,
			float(worst_fine_mem) / (1024.0 * 1024.0),
			worst_fine_spans,
			float(live_fine) / (1024.0 * 1024.0),
		]
	)
	print(
		"same x9 @ 1.0m cells ~ %.2f MiB"
		% (float(live_coarse) / (1024.0 * 1024.0))
	)
	print("RESULT: OK")
	_quit()


func _assert_solidity(s: NavSolidity) -> void:
	_expect_kind(s, VoxelMaterial.AIR, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.LEAVES, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.YEW, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.BARK, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.PLANTER, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.PAINT, NavSolidity.Kind.PASSABLE)
	_expect_kind(s, VoxelMaterial.WATER, NavSolidity.Kind.WATER)
	_expect_kind(s, VoxelMaterial.STONE, NavSolidity.Kind.SOLID)
	_expect_kind(s, VoxelMaterial.GLASS, NavSolidity.Kind.SOLID)
	_expect_kind(s, VoxelMaterial.CURB, NavSolidity.Kind.PARTIAL)
	_expect_kind(s, VoxelMaterial.ROOF_SLOPE_POS_X, NavSolidity.Kind.PARTIAL)
	if absf(s.top_frac[VoxelMaterial.CURB] - 0.4) > 0.001:
		_fail(
			"FAIL CURB top_frac=%.4f expected 0.4" % s.top_frac[VoxelMaterial.CURB]
		)


func _expect_kind(s: NavSolidity, id: int, want: int) -> void:
	var got := int(s.kind[id])
	if got != want:
		_fail("FAIL material %d kind=%s want=%s" % [id, s.kind_name(id), _kind_label(want)])


func _kind_label(k: int) -> String:
	match k:
		NavSolidity.Kind.PASSABLE:
			return "PASSABLE"
		NavSolidity.Kind.WATER:
			return "WATER"
		NavSolidity.Kind.SOLID:
			return "SOLID"
		NavSolidity.Kind.PARTIAL:
			return "PARTIAL"
		_:
			return "?"


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
