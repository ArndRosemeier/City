## Stamp each TreeStamper recipe into an offline brush and assert bark / foliage mats.
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const TreeStamperScript := preload("res://scripts/city/tree_stamper.gd")

const SCAN_MIN := Vector3i(-8, 0, -8)
const SCAN_MAX := Vector3i(9, 32, 9)


func _initialize() -> void:
	var failed := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	failed = _check_deciduous("round_tree", rng, failed)
	failed = _check_deciduous("tall_tree", rng, failed)
	failed = _check_deciduous("wide_tree", rng, failed)
	failed = _check_deciduous("plant_random", rng, failed)
	failed = _check_cypress(rng, failed)
	failed = _check_dead(rng, failed)

	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	quit(1 if failed else 0)


func _make_stamper(rng: RandomNumberGenerator) -> TreeStamper:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var stamper: TreeStamper = TreeStamperScript.new()
	stamper.brush = brush
	stamper.rng = rng
	return stamper


func _count_mats(brush: CityBrush) -> Dictionary:
	var bark := 0
	var leaves := 0
	var yew := 0
	for y in range(SCAN_MIN.y, SCAN_MAX.y):
		for z in range(SCAN_MIN.z, SCAN_MAX.z):
			for x in range(SCAN_MIN.x, SCAN_MAX.x):
				var id := brush.get_vox(Vector3i(x, y, z))
				match id:
					VoxelMaterial.BARK:
						bark += 1
					VoxelMaterial.LEAVES:
						leaves += 1
					VoxelMaterial.YEW:
						yew += 1
	return {"bark": bark, "leaves": leaves, "yew": yew}


func _check_deciduous(recipe: String, rng: RandomNumberGenerator, failed: bool) -> bool:
	var stamper := _make_stamper(rng)
	match recipe:
		"round_tree":
			stamper.round_tree(0, 1, 0)
		"tall_tree":
			stamper.tall_tree(0, 1, 0)
		"wide_tree":
			stamper.wide_tree(0, 1, 0)
		"plant_random":
			stamper.plant_random(0, 1, 0)
		_:
			push_error("unknown recipe %s" % recipe)
			return true
	var c := _count_mats(stamper.brush)
	## Canopy ellipsoid can overwrite the top trunk voxels — require both mats present.
	var bad := false
	if c.bark < 1:
		push_error("FAIL %s: expected BARK trunk, got %d" % [recipe, c.bark])
		bad = true
	if c.leaves < 8:
		push_error("FAIL %s: expected LEAVES canopy, got %d" % [recipe, c.leaves])
		bad = true
	if c.yew != 0:
		push_error("FAIL %s: unexpected YEW %d" % [recipe, c.yew])
		bad = true
	if bad:
		return true
	print("OK %s bark=%d leaves=%d" % [recipe, c.bark, c.leaves])
	return failed


func _check_cypress(rng: RandomNumberGenerator, failed: bool) -> bool:
	var stamper := _make_stamper(rng)
	stamper.cypress(0, 1, 0)
	var c := _count_mats(stamper.brush)
	var bad := false
	if c.bark < 1:
		push_error("FAIL cypress: expected BARK trunk, got %d" % c.bark)
		bad = true
	if c.yew < 8:
		push_error("FAIL cypress: expected YEW spindle, got %d" % c.yew)
		bad = true
	if c.leaves != 0:
		push_error("FAIL cypress: unexpected LEAVES %d" % c.leaves)
		bad = true
	if bad:
		return true
	print("OK cypress bark=%d yew=%d" % [c.bark, c.yew])
	return failed


func _check_dead(rng: RandomNumberGenerator, failed: bool) -> bool:
	var stamper := _make_stamper(rng)
	stamper.dead_tree(0, 1, 0)
	var c := _count_mats(stamper.brush)
	var bad := false
	if c.bark < 8:
		push_error("FAIL dead_tree: expected BARK skeleton, got %d" % c.bark)
		bad = true
	if c.leaves != 0:
		push_error("FAIL dead_tree: unexpected LEAVES %d" % c.leaves)
		bad = true
	if c.yew != 0:
		push_error("FAIL dead_tree: unexpected YEW %d" % c.yew)
		bad = true
	if bad:
		return true
	print("OK dead_tree bark=%d" % c.bark)
	return failed
