## Offline span-field measurement over a baked district block map.
## Used to lock nav column resolution and any height ceiling before the Rust baker.
class_name NavSpanMeasure
extends RefCounted

const NavSolidityScript := preload("res://scripts/city/nav_solidity.gd")
const BLOCK := 16
## Planned Rust span struct size (i16 + 5×u8, padded to 8).
const BYTES_PER_SPAN := 8
## Dense column → first-span index (u32).
const BYTES_PER_COLUMN_OFFSET := 4

var solidity: NavSolidityScript

## Column count at the measured resolution.
var columns: int = 0
var columns_with_spans: int = 0
var span_count: int = 0
var max_spans_in_column: int = 0
## Histogram: index = spans in column (capped), value = number of columns.
var spans_per_column_hist: PackedInt32Array = PackedInt32Array()
## floor_y histogram buckets of width `floor_hist_step`.
var floor_y_min: int = 0
var floor_y_max: int = 0
var floor_hist_step: int = 8
var floor_y_hist: PackedInt32Array = PackedInt32Array()
## Spans whose floor_y is strictly above each listed Y (for ceiling tradeoffs).
var ceiling_cutoffs: PackedInt32Array = PackedInt32Array()
var spans_above_ceiling: PackedInt32Array = PackedInt32Array()
var elapsed_msec: int = 0


func _init(p_solidity: NavSolidityScript) -> void:
	if p_solidity == null:
		push_error("NavSpanMeasure: solidity is null")
	solidity = p_solidity


## `cell_voxels` = 1 for native 0.5 m columns, 2 for 1 m coarse cells.
## Coarse cells union-block: any SOLID/PARTIAL in the cell footprint blocks that Y.
func measure(
	blocks: Dictionary,
	size_x: int,
	size_z: int,
	cell_voxels: int = 1,
	p_ceiling_cutoffs: PackedInt32Array = PackedInt32Array([32, 48, 64, 96, 128])
) -> void:
	if cell_voxels != 1 and cell_voxels != 2:
		push_error("NavSpanMeasure.measure: cell_voxels must be 1 or 2, got %d" % cell_voxels)
	var t0 := Time.get_ticks_msec()
	ceiling_cutoffs = p_ceiling_cutoffs.duplicate()
	spans_above_ceiling.resize(ceiling_cutoffs.size())
	spans_above_ceiling.fill(0)
	spans_per_column_hist.resize(33)
	spans_per_column_hist.fill(0)
	floor_y_hist = PackedInt32Array()
	floor_y_min = 2147483647
	floor_y_max = -2147483648
	span_count = 0
	columns_with_spans = 0
	max_spans_in_column = 0

	var cols_x := size_x / cell_voxels
	var cols_z := size_z / cell_voxels
	if cols_x * cell_voxels != size_x or cols_z * cell_voxels != size_z:
		push_error(
			"NavSpanMeasure.measure: size %dx%d not divisible by cell_voxels=%d"
			% [size_x, size_z, cell_voxels]
		)
	columns = cols_x * cols_z

	var stacks := _index_xz_stacks(blocks)
	var y_bounds := _y_bounds(blocks)
	var y_min: int = y_bounds[0]
	var y_max: int = y_bounds[1]
	if y_max < y_min:
		spans_per_column_hist[0] = columns
		elapsed_msec = Time.get_ticks_msec() - t0
		return

	var height := y_max - y_min + 1
	## One column profile reused across the stack.
	var profile := PackedByteArray()
	profile.resize(height)
	var columns_visited := 0

	var stack_bx := (size_x + BLOCK - 1) / BLOCK
	var stack_bz := (size_z + BLOCK - 1) / BLOCK
	for bz in range(stack_bz):
		for bx in range(stack_bx):
			var key := Vector2i(bx, bz)
			if not stacks.has(key):
				## Empty stack: all air — no floors, no spans.
				continue
			var stack: Array = stacks[key]
			var x0 := bx * BLOCK
			var z0 := bz * BLOCK
			var x1 := mini(x0 + BLOCK, size_x)
			var z1 := mini(z0 + BLOCK, size_z)
			## Walk coarse cells that touch this block (or fine columns when cell=1).
			var cx0 := x0 / cell_voxels
			var cz0 := z0 / cell_voxels
			var cx1 := (x1 - 1) / cell_voxels
			var cz1 := (z1 - 1) / cell_voxels
			for cz in range(cz0, cz1 + 1):
				for cx in range(cx0, cx1 + 1):
					## Only own the coarse cell from the block that contains its origin voxel.
					var ox := cx * cell_voxels
					var oz := cz * cell_voxels
					if ox < x0 or ox >= x1 or oz < z0 or oz >= z1:
						continue
					if cell_voxels == 1:
						_fill_profile_fine(profile, stack, y_min, height, ox, oz)
					else:
						_fill_profile_coarse(profile, blocks, y_min, height, ox, oz, cell_voxels, size_x, size_z)
					var col_spans := _extract_spans(profile, y_min)
					_accumulate_column(col_spans)
					columns_visited += 1

	## Columns with no blocks at all never visited — they contribute zero spans.
	var untouched := columns - columns_visited
	if untouched < 0:
		push_error("NavSpanMeasure: visited %d columns but district has %d" % [columns_visited, columns])
	elif untouched > 0:
		spans_per_column_hist[0] += untouched

	elapsed_msec = Time.get_ticks_msec() - t0


func spans_per_column_avg() -> float:
	if columns <= 0:
		return 0.0
	return float(span_count) / float(columns)


func estimated_memory_bytes() -> int:
	return columns * BYTES_PER_COLUMN_OFFSET + span_count * BYTES_PER_SPAN


func summary_lines(label: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		(
			"%s: columns=%d with_spans=%d spans=%d avg=%.3f max/col=%d mem~%.2f MiB (%d ms)"
			% [
				label,
				columns,
				columns_with_spans,
				span_count,
				spans_per_column_avg(),
				max_spans_in_column,
				float(estimated_memory_bytes()) / (1024.0 * 1024.0),
				elapsed_msec,
			]
		)
	)
	var hist_bits: PackedStringArray = PackedStringArray()
	for n in range(spans_per_column_hist.size()):
		var c := spans_per_column_hist[n]
		if c <= 0:
			continue
		var tag := "%d" % n
		if n == spans_per_column_hist.size() - 1:
			tag = "%d+" % n
		hist_bits.append("%s:%d" % [tag, c])
	lines.append("  spans/column hist: %s" % ", ".join(hist_bits))
	if floor_y_max >= floor_y_min:
		lines.append("  floor_y range: [%d, %d]" % [floor_y_min, floor_y_max])
		var floor_bits: PackedStringArray = PackedStringArray()
		for i in range(floor_y_hist.size()):
			if floor_y_hist[i] <= 0:
				continue
			var lo := i * floor_hist_step
			floor_bits.append("[%d..%d):%d" % [lo, lo + floor_hist_step, floor_y_hist[i]])
		lines.append("  floor_y hist: %s" % ", ".join(floor_bits))
	for i in range(ceiling_cutoffs.size()):
		var cut := ceiling_cutoffs[i]
		var above := spans_above_ceiling[i]
		var pct := 0.0 if span_count <= 0 else 100.0 * float(above) / float(span_count)
		lines.append(
			"  ceiling y<%d keeps %d spans (drops %d = %.1f%%)"
			% [cut, span_count - above, above, pct]
		)
	return lines


func _accumulate_column(col_spans: Array) -> void:
	var n: int = col_spans.size()
	if n > 0:
		columns_with_spans += 1
	span_count += n
	max_spans_in_column = maxi(max_spans_in_column, n)
	var bucket := mini(n, spans_per_column_hist.size() - 1)
	spans_per_column_hist[bucket] += 1
	for item: Variant in col_spans:
		var floor_y: int = int(item)
		floor_y_min = mini(floor_y_min, floor_y)
		floor_y_max = maxi(floor_y_max, floor_y)
		var fi := floor_y / floor_hist_step
		if fi < 0:
			fi = 0
		if fi >= floor_y_hist.size():
			floor_y_hist.resize(fi + 1)
		floor_y_hist[fi] += 1
		for i in range(ceiling_cutoffs.size()):
			if floor_y >= ceiling_cutoffs[i]:
				spans_above_ceiling[i] += 1


## Returns Array[int] of floor_y for each walkable span in the column.
func _extract_spans(profile: PackedByteArray, y_min: int) -> Array:
	var spans: Array = []
	var y := 0
	var n := profile.size()
	while y < n:
		var mat := int(profile[y])
		if not solidity.is_blocker(mat):
			y += 1
			continue
		## Floor at this cell; walkable span is the run of traversable cells above it.
		var floor_y := y_min + y
		y += 1
		var headroom := 0
		while y < n:
			var above := int(profile[y])
			if solidity.is_blocker(above):
				break
			headroom += 1
			y += 1
		if headroom > 0:
			spans.append(floor_y)
	return spans


## Fast path: one voxel column, materials come from this xz stack only.
func _fill_profile_fine(
	profile: PackedByteArray,
	stack: Array,
	y_min: int,
	height: int,
	ox: int,
	oz: int
) -> void:
	profile.fill(VoxelMaterial.AIR)
	var lx := ox & (BLOCK - 1)
	var lz := oz & (BLOCK - 1)
	for by_entry: Variant in stack:
		var entry: Dictionary = by_entry
		var by: int = int(entry["by"])
		var base_y := by * BLOCK
		var data: PackedByteArray = entry["data"]
		var uniform: bool = bool(entry["uniform"])
		var umaterial: int = int(entry["mat"])
		for ly in range(BLOCK):
			var pi := base_y + ly - y_min
			if pi < 0 or pi >= height:
				continue
			if uniform:
				profile[pi] = umaterial
			else:
				var idx := ly + lx * BLOCK + lz * BLOCK * BLOCK
				profile[pi] = int(data[idx * 2])


## Coarse cell: union-block over the cell_voxels² footprint (crosses 16³ block borders).
func _fill_profile_coarse(
	profile: PackedByteArray,
	blocks: Dictionary,
	y_min: int,
	height: int,
	ox: int,
	oz: int,
	cell_voxels: int,
	size_x: int,
	size_z: int
) -> void:
	profile.fill(VoxelMaterial.AIR)
	for pi in range(height):
		var wy := y_min + pi
		var blocked := false
		var any_water := false
		for dz in range(cell_voxels):
			for dx in range(cell_voxels):
				var wx := ox + dx
				var wz := oz + dz
				if wx >= size_x or wz >= size_z:
					continue
				var mat := _mat_at(blocks, wx, wy, wz)
				if solidity.is_blocker(mat):
					profile[pi] = mat
					blocked = true
					break
				if int(solidity.kind[mat]) == NavSolidityScript.Kind.WATER:
					any_water = true
			if blocked:
				break
		if blocked:
			continue
		if any_water:
			profile[pi] = VoxelMaterial.WATER


func _mat_at(blocks: Dictionary, wx: int, wy: int, wz: int) -> int:
	var bp := Vector3i(wx / BLOCK, wy / BLOCK, wz / BLOCK)
	if not blocks.has(bp):
		return VoxelMaterial.AIR
	var data: PackedByteArray = blocks[bp]
	if data.size() <= 2:
		return int(data[0])
	var lx := wx - bp.x * BLOCK
	var ly := wy - bp.y * BLOCK
	var lz := wz - bp.z * BLOCK
	var idx := ly + lx * BLOCK + lz * BLOCK * BLOCK
	return int(data[idx * 2])

func _index_xz_stacks(blocks: Dictionary) -> Dictionary:
	var stacks: Dictionary = {}
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		var xz := Vector2i(bp.x, bp.z)
		if not stacks.has(xz):
			stacks[xz] = []
		var data: PackedByteArray = blocks[key]
		var uniform := data.size() <= 2
		var mat := int(data[0]) if data.size() >= 1 else VoxelMaterial.AIR
		if not uniform and data.size() != BLOCK * BLOCK * BLOCK * 2:
			push_error(
				"NavSpanMeasure: unexpected block byte size %d at %s" % [data.size(), bp]
			)
		(stacks[xz] as Array).append(
			{"by": bp.y, "data": data, "uniform": uniform, "mat": mat}
		)
	for xz2: Variant in stacks.keys():
		var arr: Array = stacks[xz2]
		arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["by"]) < int(b["by"]))
	return stacks


func _y_bounds(blocks: Dictionary) -> PackedInt32Array:
	var y_min := 2147483647
	var y_max := -2147483648
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		y_min = mini(y_min, bp.y * BLOCK)
		y_max = maxi(y_max, bp.y * BLOCK + BLOCK - 1)
	return PackedInt32Array([y_min, y_max])
