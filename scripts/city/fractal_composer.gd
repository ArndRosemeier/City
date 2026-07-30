## Fractal-theme district: square glowing uni-voxel deck; grass fills the rest of the
## open reserve (edge street stubs stay as roads from the planner).
class_name FractalComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28

## Local-district voxel AABB of the last compose (full reserve).
var last_min: Vector3i = Vector3i.ZERO
var last_max: Vector3i = Vector3i.ZERO
## Centered square deck painted with FRACTAL_GLOW (min inclusive, max exclusive on xz/y).
var last_glow_min: Vector3i = Vector3i.ZERO
var last_glow_max: Vector3i = Vector3i.ZERO

## One planner cell of meadow between road stubs and the glowing square.
const GRASS_MARGIN_CELLS := 1


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	last_min = min_v
	last_max = max_v
	last_glow_min = Vector3i.ZERO
	last_glow_max = Vector3i.ZERO
	if brush == null or planner == null:
		push_error("FractalComposer.compose: brush/planner missing")
		return
	var lf: Rect2i = planner.large_fractal
	if lf.size.x <= 0 or lf.size.y <= 0:
		push_error("FractalComposer.compose: empty large_fractal")
		return
	var x0 := lf.position.x * cell_size
	var z0 := lf.position.y * cell_size
	var x1 := lf.end.x * cell_size
	var z1 := lf.end.y * cell_size
	var width := x1 - x0
	var depth := z1 - z0
	var margin := GRASS_MARGIN_CELLS * cell_size
	var inner_w := width - 2 * margin
	var inner_d := depth - 2 * margin
	if inner_w < cell_size or inner_d < cell_size:
		margin = 0
		inner_w = width
		inner_d = depth
	var side := mini(inner_w, inner_d)
	## Largest centered square inside the grass-inset reserve.
	var gx0 := x0 + (width - side) / 2
	var gz0 := z0 + (depth - side) / 2
	var gx1 := gx0 + side
	var gz1 := gz0 + side
	var y0 := ground_y
	var y1 := ground_y + 1
	brush.fill_box(
		Vector3i(gx0, y0, gz0),
		Vector3i(gx1, y1, gz1),
		VoxelMaterial.FRACTAL_GLOW
	)
	last_glow_min = Vector3i(gx0, y0, gz0)
	last_glow_max = Vector3i(gx1, y1, gz1)
	print(
		"FractalComposer: glow square %dx%d at %s .. %s (reserve %dx%d margin=%d)"
		% [side, side, str(last_glow_min), str(last_glow_max), width, depth, margin]
	)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	compose(min_v, max_v)
