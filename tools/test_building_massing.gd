## Ground area has to carry the height — no needles.
##
## Runs as a scene (not --script) because the city scripts reference the CityProfiler
## autoload, which only exists in a normal project run.
##
## Two rules, both taken from how real cities size tall buildings:
##
## • Usable floor plate. An occupiable tower runs 500–700 m² (economy residential) to
##   1,500–2,500 m² (prime office), and core-to-glass is capped at 12–15 m for daylight, so
##   a tower needs ~24 m across before a core plus usable depth fits at all. A lone 14 m
##   planner cell is 144 m² — row-house scale — which is why downtown amalgamates plots,
##   exactly as Manhattan's average plot grew from 257 m² to 805 m².
## • Slenderness λ = height ÷ shortest base side. The structural optimum is 5–7 and both
##   original WTC towers sat at 7. λ ≥ 10 is the super-slender luxury outlier.
##
## The intensity field alone used to grant a 12 m lot the full 100 m ceiling: λ ≈ 8.6 on the
## lot and 10:1 on the shaft plate. This test bakes downtown and measures the painted
## voxels, so a regression in either the planner, the height cap or the grammar shows up.
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const WORLD_SEED := 42
## The world origin is always the high-rise core (see test_district_themes) — the only
## place that reaches the height ceiling. Its origin voxel is (0,0,0), so baked block
## coordinates and the generator's district-local lot bounds are the same space.
const CORE_COORD := Vector2i(0, 0)
## Voxels per block edge, and the block index layout used by the native volume.
const BLOCK := 16
## Roof clutter, plant rooms, chimneys and antennae sit above the massing cap, so the
## measured silhouette runs a few metres over what the cap allowed.
const CLUTTER_SLACK_M := 8.0
## Downtown must still have a skyline. Capping height by footprint without amalgamating
## plots would trade the needles for a uniformly flat core, which is the other failure.
const TALL_M := 60.0
const MIN_TALL_BUILDINGS := 8
## Sanity floor on the share of CORE cells in a merged parcel. Not a target: the real check
## below is that nothing mergeable was left behind. Downtown never reaches 100% because
## single CORE cells stranded between streets and MID lots cannot form a parcel at all —
## they stay small infill buildings, which is what real blocks look like between towers.
const MIN_AMALGAMATED := 0.5

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var res: Dictionary = DistrictBakeJobScript.bake({
		"coord": CORE_COORD,
		"world_seed": WORLD_SEED,
	})
	if not bool(res.get("ok", false)):
		_fail("FAIL bake %s: %s" % [CORE_COORD, res.get("error", "?")])
	else:
		_check_amalgamation(res)
		_check_massing(res)
	print("RESULT: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check_amalgamation(res: Dictionary) -> void:
	var planner: DistrictPlanner = res["planner"]
	var core_cells := 0
	var merged_cells := 0
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if planner.tag_at(cx, cz) != LandUse.CORE_LOT:
				continue
			core_cells += 1
			if planner.tower_parcel_at(cx, cz).size.x > 0:
				merged_cells += 1
	if core_cells <= 0:
		_fail("FAIL downtown tile has no CORE cells to amalgamate")
		return
	var sizes: Dictionary = {}
	for rect: Rect2i in planner.tower_parcels:
		if rect.size.x < 2 or rect.size.x > 4 or rect.size.y < 2 or rect.size.y > 4:
			_fail("FAIL parcel %s is outside the 2 … 4 cell range" % rect)
			return
		var key := "%d×%d" % [rect.size.x, rect.size.y]
		sizes[key] = int(sizes.get(key, 0)) + 1
		## A landlocked parcel gets no building at all, so it would leave a hole the size
		## of the whole parcel.
		if planner.rect_is_landlocked(rect):
			_fail("FAIL parcel %s has no street frontage" % rect)
			return
		if not planner.is_tower_parcel_anchor(rect.position.x, rect.position.y):
			_fail("FAIL parcel %s has no anchor cell to paint it" % rect)
			return
	var share := float(merged_cells) / float(core_cells)
	if share < MIN_AMALGAMATED:
		_fail(
			"FAIL only %.0f%% of %d CORE cells amalgamated — lone 14 m cells cannot host towers"
			% [share * 100.0, core_cells]
		)
		return
	_check_nothing_left_to_merge(planner)
	var parts: Array[String] = []
	for key: Variant in sizes.keys():
		parts.append("%s=%d" % [String(key), int(sizes[key])])
	parts.sort()
	print(
		"OK amalgamation: %d parcels (%s), %.0f%% of %d CORE cells merged"
		% [planner.tower_parcels.size(), ", ".join(parts), share * 100.0, core_cells]
	)


## Downtown amalgamates every block it can: after packing there must be no placeable parcel
## left whose cells are all still unmerged. This is what "merge nearly all of CORE" means
## operationally — a reintroduced parcel cap or a lost rectangle shape shows up here.
func _check_nothing_left_to_merge(planner: DistrictPlanner) -> void:
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			for size: Vector2i in DistrictPlanner.PARCEL_SIZES:
				var rect := Rect2i(Vector2i(cx, cz), size)
				if not planner._tower_parcel_cells_ok(rect):
					continue
				var free := true
				for z in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						if planner.tower_parcel_at(x, z).size.x > 0:
							free = false
				if free:
					_fail("FAIL parcel %s was placeable but left unmerged" % rect)
					return


func _check_massing(res: Dictionary) -> void:
	var planner: DistrictPlanner = res["planner"]
	var gen: DistrictGenerator = res["generator"]
	var ground := int(res["ground_thickness"])
	var vs := gen.voxel_size
	var top := _build_heightmap(res)
	var size_x := int(res["size_x"])
	var buildings := 0
	var tall := 0
	var tallest_m := 0.0
	var worst_slenderness := 0.0
	var worst_desc := ""
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_lot(planner.tag_at(cx, cz)):
				continue
			## Only the anchor of a merged parcel paints, and landlocked lots are courtyard.
			if planner.is_tower_parcel_secondary(cx, cz):
				continue
			if planner.rect_is_landlocked(gen._lot_rect(cx, cz)):
				continue
			var paint := gen._lot_paint_bounds(cx, cz)
			var inner := gen._buildable_bounds(paint[0], paint[1], cx, cz)
			var bmin: Vector3i = inner[0]
			var bmax: Vector3i = inner[1]
			var w := bmax.x - bmin.x
			var d := bmax.z - bmin.z
			if w < 6 or d < 6:
				continue
			var peak := -1
			for z in range(bmin.z, bmax.z):
				for x in range(bmin.x, bmax.x):
					peak = maxi(peak, top[z * size_x + x])
			if peak < ground:
				continue
			var height_m := float(peak + 1 - ground) * vs
			if height_m <= 0.0:
				continue
			buildings += 1
			tallest_m = maxf(tallest_m, height_m)
			var short_m := float(mini(w, d)) * vs
			var area_m2 := float(w) * float(d) * vs * vs
			var slenderness := height_m / short_m
			if slenderness > worst_slenderness:
				worst_slenderness = slenderness
				worst_desc = (
					"cell (%d,%d) %.0f m on %.0f×%.0f m (%.0f m²)"
					% [cx, cz, height_m, float(w) * vs, float(d) * vs, area_m2]
				)
			if height_m >= TALL_M:
				tall += 1
			## Anything above the fabric ceiling is a tower and needs a tower's plate.
			if height_m > DistrictGenerator.FABRIC_HEIGHT_M + CLUTTER_SLACK_M:
				if area_m2 < DistrictGenerator.MIN_TOWER_PLATE_M2:
					_fail(
						"FAIL cell (%d,%d) built %.0f m on a %.0f m² plate (needs %.0f m²)"
						% [cx, cz, height_m, area_m2, DistrictGenerator.MIN_TOWER_PLATE_M2]
					)
					return
				if short_m < DistrictGenerator.MIN_TOWER_SIDE_M:
					_fail(
						"FAIL cell (%d,%d) built %.0f m on a %.0f m side (needs %.0f m)"
						% [cx, cz, height_m, short_m, DistrictGenerator.MIN_TOWER_SIDE_M]
					)
					return
	if buildings <= 0:
		_fail("FAIL downtown tile painted no buildings")
		return
	## The cap is lot-relative; the grammar insets shafts inside it, and clutter rides on
	## top, so the measured silhouette is allowed a little over MAX_SLENDERNESS.
	var limit := DistrictGenerator.MAX_SLENDERNESS + 1.0
	if worst_slenderness > limit:
		_fail(
			"FAIL needle at %s — slenderness %.1f exceeds %.1f"
			% [worst_desc, worst_slenderness, limit]
		)
		return
	if tall < MIN_TALL_BUILDINGS:
		_fail(
			"FAIL downtown flattened: only %d buildings over %.0f m (tallest %.0f m)"
			% [tall, TALL_M, tallest_m]
		)
		return
	print(
		"OK massing: %d buildings, %d over %.0f m, tallest %.0f m, worst slenderness %.1f (%s)"
		% [buildings, tall, TALL_M, tallest_m, worst_slenderness, worst_desc]
	)


## Topmost solid voxel per district-local column, from the baked blocks.
func _build_heightmap(res: Dictionary) -> PackedInt32Array:
	var size_x := int(res["size_x"])
	var size_z := int(res["size_z"])
	var blocks: Dictionary = res["blocks"]
	var top := PackedInt32Array()
	top.resize(size_x * size_z)
	top.fill(-1)
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var base := bp * BLOCK
		var data: PackedByteArray = blocks[key]
		if data.size() <= 2:
			## Uniform block — one material id for all 16³ voxels.
			if int(data[0]) == VoxelMaterial.AIR:
				continue
			_raise_column_rect(top, size_x, size_z, base, BLOCK, BLOCK, base.y + BLOCK - 1)
			continue
		var voxels := data.size() / 2
		for i in range(voxels):
			if int(data[i * 2]) == VoxelMaterial.AIR:
				continue
			## Layout is y + x * BLOCK + z * BLOCK².
			var wx := base.x + (i / BLOCK) % BLOCK
			var wz := base.z + i / (BLOCK * BLOCK)
			if wx < 0 or wx >= size_x or wz < 0 or wz >= size_z:
				continue
			var wy := base.y + i % BLOCK
			var idx := wz * size_x + wx
			if top[idx] < wy:
				top[idx] = wy
	return top


func _raise_column_rect(
	top: PackedInt32Array, size_x: int, size_z: int, base: Vector3i, w: int, d: int, y: int
) -> void:
	for lz in range(d):
		var wz := base.z + lz
		if wz < 0 or wz >= size_z:
			continue
		for lx in range(w):
			var wx := base.x + lx
			if wx < 0 or wx >= size_x:
				continue
			var idx := wz * size_x + wx
			if top[idx] < y:
				top[idx] = y
