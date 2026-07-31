## Fills an XZ area with landmark evergreens on a park lawn.
## Caller supplies density and a height range; this owns placement + spacing.
##
##     var forest := ForestComposer.new()
##     forest.brush = brush
##     forest.rng = rng
##     forest.ground_y = deck_y
##     forest.density = 0.55
##     forest.min_height_m = 12.0
##     forest.max_height_m = 18.0
##     forest.compose(min_v, max_v)
class_name ForestComposer
extends RefCounted

## At density 1.0, about one tree per this many ground cells (~6 m × 6 m at 0.5 m).
const CELLS_PER_TREE_AT_FULL := 144
## Litter rocks — denser than trees; ~1 cluster per ~12 m² at full.
const CELLS_PER_ROCK_AT_FULL := 48
## Keep crowns inside the submitted box (landmark limbs reach ~4–9 cells out).
const EDGE_MARGIN := 10
## Hard cap so a dense 100 m patch cannot stall a bake/shot.
const MAX_TREES := 220
const MAX_ROCKS := 400
## Stay clear of trunk flare / thick bark at the foot.
const ROCK_TREE_CLEARANCE := 3

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1
var stamper: TreeStamper

## 0..1 canopy fill. 1.0 ≈ closed stand (~1 tree / 36 m²).
var density: float = 0.5
## Tree height range in metres (converted at CityRoot.VOXEL_SIZE = 0.5).
var min_height_m: float = 12.0
var max_height_m: float = 18.0


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper


## Paint lawn and plant the stand inside `[min_v, max_v)`. Y uses `ground_y`.
func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	_lawn(min_v, max_v)
	var trunks := _plant(min_v, max_v, density)
	_scatter_rocks(min_v, max_v, trunks, density)


## Far-tile silhouette: same lawn, thinned stand + a few rocks.
func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	_lawn(min_v, max_v)
	var trunks := _plant(min_v, max_v, density * 0.18)
	_scatter_rocks(min_v, max_v, trunks, density * 0.18)


func _lawn(min_v: Vector3i, max_v: Vector3i) -> void:
	if min_v.x >= max_v.x or min_v.z >= max_v.z:
		return
	brush.fill_box(
		Vector3i(min_v.x, ground_y, min_v.z),
		Vector3i(max_v.x, ground_y + 1, max_v.z),
		VoxelMaterial.PARK
	)
	brush.fill_box(
		Vector3i(min_v.x, ground_y - 1, min_v.z),
		Vector3i(max_v.x, ground_y, max_v.z),
		VoxelMaterial.DIRT
	)


func _plant(min_v: Vector3i, max_v: Vector3i, dens: float) -> Array[Vector2i]:
	var planted: Array[Vector2i] = []
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < EDGE_MARGIN * 2 + 4 or d < EDGE_MARGIN * 2 + 4:
		return planted
	var dens_clamped := clampf(dens, 0.0, 1.0)
	if dens_clamped <= 0.0:
		return planted
	var area := w * d
	var target := clampi(
		int(round(float(area) / float(CELLS_PER_TREE_AT_FULL) * dens_clamped)),
		0,
		MAX_TREES
	)
	if target < 1:
		return planted
	## Minimum separation shrinks as density rises (sparse → roomy, dense → packed).
	var min_sep := maxi(6, int(round(lerpf(18.0, 7.0, dens_clamped))))
	var min_sep2 := min_sep * min_sep
	var h0 := minf(min_height_m, max_height_m)
	var h1 := maxf(min_height_m, max_height_m)
	var made := 0
	var tries := 0
	var try_cap := target * 12
	var x0 := min_v.x + EDGE_MARGIN
	var x1 := max_v.x - EDGE_MARGIN - 1
	var z0 := min_v.z + EDGE_MARGIN
	var z1 := max_v.z - EDGE_MARGIN - 1
	if x0 > x1 or z0 > z1:
		return planted
	var stamp := _stamper()
	while made < target and tries < try_cap:
		tries += 1
		var x := rng.randi_range(x0, x1)
		var z := rng.randi_range(z0, z1)
		if not _is_plantable(x, z):
			continue
		if _too_close(x, z, planted, min_sep2):
			continue
		var height_m := h0 if h1 <= h0 else rng.randf_range(h0, h1)
		stamp.landmark_tree(x, ground_y, z, height_m)
		planted.append(Vector2i(x, z))
		made += 1
	return planted


## Small STONE / GRAVEL litter on the lawn — singles and tiny 2–3 cell clumps.
func _scatter_rocks(
	min_v: Vector3i, max_v: Vector3i, trunks: Array[Vector2i], dens: float
) -> void:
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 6 or d < 6:
		return
	## Rocks track stand density lightly; even a sparse wood gets floor litter.
	var dens_clamped := clampf(dens, 0.15, 1.0)
	var target := clampi(
		int(round(float(w * d) / float(CELLS_PER_ROCK_AT_FULL) * dens_clamped)),
		4,
		MAX_ROCKS
	)
	var clear2 := ROCK_TREE_CLEARANCE * ROCK_TREE_CLEARANCE
	var made := 0
	var tries := 0
	var try_cap := target * 10
	var x0 := min_v.x + 2
	var x1 := max_v.x - 3
	var z0 := min_v.z + 2
	var z1 := max_v.z - 3
	if x0 > x1 or z0 > z1:
		return
	var rock_y := ground_y + 1
	while made < target and tries < try_cap:
		tries += 1
		var x := rng.randi_range(x0, x1)
		var z := rng.randi_range(z0, z1)
		if not _is_plantable(x, z):
			continue
		if _too_close(x, z, trunks, clear2):
			continue
		## Only on open air above lawn — skip bark flare / existing litter.
		if brush.get_vox(Vector3i(x, rock_y, z)) != VoxelMaterial.AIR:
			continue
		var mat := (
			VoxelMaterial.STONE if rng.randf() < 0.7 else VoxelMaterial.GRAVEL
		)
		_place_rock_clump(x, rock_y, z, mat)
		made += 1


func _place_rock_clump(x: int, y: int, z: int, mat: int) -> void:
	brush.set_vox(Vector3i(x, y, z), mat)
	var roll := rng.randf()
	if roll < 0.55:
		## Single pebble.
		return
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	## Shuffle-ish: pick 1–2 neighbour cells.
	var extras := 1 if roll < 0.88 else 2
	for _i in range(extras):
		var dir := dirs[rng.randi() % dirs.size()]
		var nx := x + dir.x
		var nz := z + dir.y
		var ground := brush.get_vox(Vector3i(nx, ground_y, nz))
		if ground != VoxelMaterial.PARK and ground != VoxelMaterial.DIRT:
			continue
		if brush.get_vox(Vector3i(nx, y, nz)) != VoxelMaterial.AIR:
			continue
		brush.set_vox(Vector3i(nx, y, nz), mat)
	## Occasional low stack — still "a few" voxels, not a boulder.
	if rng.randf() < 0.18 and brush.get_vox(Vector3i(x, y + 1, z)) == VoxelMaterial.AIR:
		brush.set_vox(Vector3i(x, y + 1, z), mat)


func _is_plantable(x: int, z: int) -> bool:
	var id := brush.get_vox(Vector3i(x, ground_y, z))
	return id == VoxelMaterial.PARK or id == VoxelMaterial.DIRT


func _too_close(x: int, z: int, planted: Array[Vector2i], min_sep2: int) -> bool:
	for p in planted:
		var dx := x - p.x
		var dz := z - p.y
		if dx * dx + dz * dz < min_sep2:
			return true
	return false
