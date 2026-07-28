## Bake a real district through DistrictBakeJob with the nav pass on, and assert the span
## field that comes back is sane.
##
## Run: Godot --headless --path . res://tools/test_nav_bake.tscn
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const NavSolidityScript := preload("res://scripts/city/nav_solidity.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const WORLD_SEED := 42
const DISTRICT := Vector2i(0, 0)

## NavSolidity.Kind, spelled out because nav_solidity.gd is not in the global class cache
## while it is new.
const KIND_PASSABLE := 0
const KIND_WATER := 1
const KIND_SOLID := 2
const KIND_PARTIAL := 3

## A column can stack a cave floor, a street, every building floor and a roof. Anything
## past this means the extractor is emitting spans for sub-voxel noise.
const MAX_PLAUSIBLE_SPANS_PER_COLUMN := 120

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CityVoxelNativeScript.require_loaded()
	var solidity = NavSolidityScript.build()
	_check_tables(solidity)
	if _failed:
		_quit()
		return

	var theme := DistrictTheme.for_district(WORLD_SEED, DISTRICT)
	print("baking district %s (%s) with nav" % [DISTRICT, theme.display_name])
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": DISTRICT,
		"world_seed": WORLD_SEED,
		"bake_nav": true,
		"nav_solidity": solidity.export_tables(),
	})
	var bake_msec := Time.get_ticks_msec() - t0
	if not bool(res.get("ok", false)):
		_fail("FAIL bake: %s" % res.get("error", "?"))
		_quit()
		return

	var nav_bake = res["nav_bake"]
	if nav_bake == null:
		_fail("FAIL bake returned no nav_bake handle")
		_quit()
		return
	if not bool(nav_bake.is_ready()):
		_fail("FAIL nav_bake holds no field")
		_quit()
		return

	var stats: Dictionary = res["nav_stats"]
	if not bool(stats.get("ok", false)):
		_fail("FAIL nav stats not ok: %s" % stats)
		_quit()
		return
	## The handle must answer the same numbers the result dictionary carries.
	var direct: Dictionary = nav_bake.stats()
	if int(direct["spans"]) != int(stats["spans"]):
		_fail(
			"FAIL nav_stats spans=%d disagrees with nav_bake.stats() spans=%d"
			% [int(stats["spans"]), int(direct["spans"])]
		)

	var columns := int(stats["columns"])
	var spans := int(stats["spans"])
	var max_per_col := int(stats["max_spans_per_column"])
	print(
		(
			"nav columns=%d spans=%d (%.2f/column, max %d) sectors=%d nodes=%d"
			+ " portals=%d links=%d bytes=%.2f MiB"
		)
		% [
			columns,
			spans,
			float(spans) / maxf(float(columns), 1.0),
			max_per_col,
			int(stats["sectors"]),
			int(stats["nodes"]),
			int(stats["portals"]),
			int(stats["links"]),
			float(int(stats["bytes"])) / (1024.0 * 1024.0),
		]
	)

	var expect_columns := int(res["size_x"]) * int(res["size_z"])
	if columns != expect_columns:
		_fail("FAIL nav covers %d columns, district has %d" % [columns, expect_columns])
	if spans <= columns:
		_fail("FAIL only %d spans for %d columns — the field is not 3D" % [spans, columns])
	if max_per_col < 2:
		_fail("FAIL max_spans_per_column=%d — no column stacks levels" % max_per_col)
	if max_per_col > MAX_PLAUSIBLE_SPANS_PER_COLUMN:
		_fail(
			"FAIL max_spans_per_column=%d exceeds the plausible %d"
			% [max_per_col, MAX_PLAUSIBLE_SPANS_PER_COLUMN]
		)
	var sectors := int(stats["sectors"])
	if sectors != int(res["cells_total"]):
		_fail("FAIL %d nav sectors for %d planner cells" % [sectors, int(res["cells_total"])])
	if int(stats["nodes"]) < sectors:
		_fail(
			"FAIL %d nodes for %d sectors — sectors with no walkable space"
			% [int(stats["nodes"]), sectors]
		)
	if int(stats["portals"]) < sectors:
		_fail(
			"FAIL only %d portals for %d sectors — the street grid is not connected"
			% [int(stats["portals"]), sectors]
		)
	if int(stats["links"]) <= 0:
		_fail("FAIL no traversal links baked")
	if int(stats["bytes"]) <= 0:
		_fail("FAIL field reports %d bytes" % int(stats["bytes"]))

	## A bake without the nav pass must stay exactly as it was, and the difference in wall
	## clock is what the nav pass costs a bake worker.
	var t1 := Time.get_ticks_msec()
	var plain: Dictionary = DistrictBakeJobScript.bake({
		"coord": DISTRICT,
		"world_seed": WORLD_SEED,
	})
	var plain_msec := Time.get_ticks_msec() - t1
	print("bake %d ms with nav, %d ms without" % [bake_msec, plain_msec])
	if not bool(plain.get("ok", false)):
		_fail("FAIL plain bake: %s" % plain.get("error", "?"))
	else:
		var plain_stats: Dictionary = plain["nav_stats"]
		if plain["nav_bake"] != null or not plain_stats.is_empty():
			_fail("FAIL bake without bake_nav still produced a nav field")

	_quit()


## The four Rust tables must be full length and agree with the collision data they came
## from, because a short or shifted table silently turns walls into open space.
func _check_tables(solidity) -> void:
	var counts: PackedInt32Array = solidity.count_by_kind()
	print(
		"solidity passable=%d water=%d solid=%d partial=%d"
		% [counts[0], counts[1], counts[2], counts[3]]
	)
	var solid_class: PackedByteArray = solidity.export_class()
	var solid_top: PackedFloat32Array = solidity.export_top()
	var destructible: PackedByteArray = solidity.export_destructible()
	var climbable: PackedByteArray = solidity.export_climbable()
	var table_size := int(NavSolidityScript.TABLE_SIZE)
	if (
		solid_class.size() != table_size
		or solid_top.size() != table_size
		or destructible.size() != table_size
		or climbable.size() != table_size
	):
		_fail(
			"FAIL table sizes %d/%d/%d/%d, expected %d"
			% [
				solid_class.size(),
				solid_top.size(),
				destructible.size(),
				climbable.size(),
				table_size,
			]
		)
		return

	if solid_class[VoxelMaterial.AIR] != KIND_PASSABLE:
		_fail("FAIL air is not passable (class=%d)" % solid_class[VoxelMaterial.AIR])
	if solid_class[VoxelMaterial.LEAVES] != KIND_PASSABLE:
		_fail("FAIL leaves are not passable (class=%d)" % solid_class[VoxelMaterial.LEAVES])
	if solid_class[VoxelMaterial.WATER] != KIND_WATER:
		_fail("FAIL water is not the water class (class=%d)" % solid_class[VoxelMaterial.WATER])
	if solid_class[VoxelMaterial.BRICK] != KIND_SOLID:
		_fail("FAIL brick is not solid (class=%d)" % solid_class[VoxelMaterial.BRICK])
	if solid_class[VoxelMaterial.CURB] != KIND_PARTIAL:
		_fail("FAIL curb is not partial (class=%d)" % solid_class[VoxelMaterial.CURB])
	if not is_equal_approx(solid_top[VoxelMaterial.CURB], 0.4):
		_fail("FAIL curb top is %.3f, expected 0.4" % solid_top[VoxelMaterial.CURB])
	## Ids past the palette are the Rust "unknown" case and must read as walls.
	if solid_class[VoxelMaterial.COUNT] != KIND_SOLID:
		_fail("FAIL padding id %d is not solid" % VoxelMaterial.COUNT)

	if destructible[VoxelMaterial.BRICK] != 1:
		_fail("FAIL brick is not marked destructible")
	if destructible[VoxelMaterial.BEDROCK] != 0:
		_fail("FAIL bedrock is marked destructible")
	if destructible[VoxelMaterial.AIR] != 0:
		_fail("FAIL air is marked destructible")

	if climbable[VoxelMaterial.BRICK] != 1:
		_fail("FAIL a brick facade is not climbable")
	if climbable[VoxelMaterial.CURB] != 0:
		_fail("FAIL a curb lip is climbable")
	if climbable[VoxelMaterial.WATER] != 0:
		_fail("FAIL water is climbable")
	if climbable[VoxelMaterial.LEAVES] != 0:
		_fail("FAIL foliage is climbable")


func _quit() -> void:
	print("RESULT: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)
