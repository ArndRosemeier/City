## Dump the Hill heightfield without baking voxels — fast loop for tuning terrain shape.
##
## Run: Godot --headless --path . --script res://tools/probe_hill_height.gd
extends SceneTree

const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const HillComposerScript := preload("res://scripts/city/hill_composer.gd")

const WORLD_SEED := 42


func _initialize() -> void:
	var coord := _find_hill_coord()
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.HILL)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)

	var hill: HillComposer = HillComposerScript.new()
	hill.planner = planner
	hill.cell_size = DistrictCoord.CELL_SIZE
	hill.ground_y = 6
	hill.rng = RandomNumberGenerator.new()
	hill.rng.seed = dseed
	var lh := planner.large_hill
	var cell := DistrictCoord.CELL_SIZE
	var min_v := Vector3i(lh.position.x * cell, 0, lh.position.y * cell)
	var max_v := Vector3i(
		(lh.position.x + lh.size.x) * cell, 0, (lh.position.y + lh.size.y) * cell
	)
	hill.probe_heightfield(min_v, max_v)

	var w: int = hill.probe_width()
	var d: int = hill.probe_depth()
	var heights: PackedInt32Array = hill.probe_heights()

	## Step histogram: how much of the surface is flat, gently sloped or scarp.
	var hist := PackedInt32Array()
	hist.resize(16)
	hist.fill(0)
	for z in range(1, d - 1):
		for x in range(1, w - 1):
			var h := heights[z * w + x]
			if h <= 0:
				continue
			var s := 0
			s = maxi(s, absi(h - heights[z * w + x - 1]))
			s = maxi(s, absi(h - heights[z * w + x + 1]))
			s = maxi(s, absi(h - heights[(z - 1) * w + x]))
			s = maxi(s, absi(h - heights[(z + 1) * w + x]))
			hist[mini(s, 15)] += 1
	var total := 0
	for v in hist:
		total += v
	print("raised columns: %d" % total)
	for i in range(hist.size()):
		if hist[i] > 0:
			print("  step %2d: %6d (%2d%%)" % [i, hist[i], hist[i] * 100 / maxi(1, total)])

	## Vertical slice through the tallest column so terrace runs are visible.
	var best := 0
	var best_z := d / 2
	for z2 in range(d):
		for x2 in range(w):
			if heights[z2 * w + x2] > best:
				best = heights[z2 * w + x2]
				best_z = z2
	print("tallest column %d vox on row z=%d — profile every 4 voxels:" % [best, best_z])
	var line := ""
	var x3 := 0
	while x3 < w:
		line += "%3d " % heights[best_z * w + x3]
		x3 += 4
	print(line)
	quit(0)


func _find_hill_coord() -> Vector2i:
	for ring in range(1, 8):
		for cz in range(-ring, ring + 1):
			for cx in range(-ring, ring + 1):
				if maxi(absi(cx), absi(cz)) != ring:
					continue
				if DistrictTheme.for_district(WORLD_SEED, Vector2i(cx, cz)).id == DistrictTheme.HILL:
					return Vector2i(cx, cz)
	push_error("no hill district found")
	quit(1)
	return Vector2i.ZERO
