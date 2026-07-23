## Composes park voxels: lawns, paths, ponds, groves, hedges.
class_name ParkComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1


func compose_large(min_v: Vector3i, max_v: Vector3i) -> void:
	_lawn(min_v, max_v)
	_cross_paths(min_v, max_v)
	_pond(min_v, max_v)
	_grove(min_v, max_v, 8 + rng.randi() % 6)
	_hedge_beds(min_v, max_v)


func compose_pocket(min_v: Vector3i, max_v: Vector3i) -> void:
	_lawn(min_v, max_v)
	_simple_path(min_v, max_v)
	_grove(min_v, max_v, 2 + rng.randi() % 2)
	# Bench
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	brush.fill_box(
		Vector3i(cx - 1, ground_y + 1, cz),
		Vector3i(cx + 2, ground_y + 2, cz + 1),
		VoxelMaterial.PLANTER
	)


func compose_courtyard_garden(hole_min: Vector3i, hole_max: Vector3i) -> void:
	## hole spans building height in y; garden only on ground slab.
	var gmin := Vector3i(hole_min.x, ground_y, hole_min.z)
	var gmax := Vector3i(hole_max.x, ground_y + 1, hole_max.z)
	if gmax.x - gmin.x < 3 or gmax.z - gmin.z < 3:
		brush.fill_box(gmin, gmax, VoxelMaterial.PARK)
		return
	brush.fill_box(
		Vector3i(gmin.x, ground_y, gmin.z),
		Vector3i(gmax.x, ground_y + 1, gmax.z),
		VoxelMaterial.DIRT
	)
	brush.fill_box(
		Vector3i(gmin.x, ground_y, gmin.z),
		Vector3i(gmax.x, ground_y + 1, gmax.z),
		VoxelMaterial.PARK
	)
	var cx := (gmin.x + gmax.x) / 2
	var cz := (gmin.z + gmax.z) / 2
	# Path cross
	brush.fill_box(
		Vector3i(cx, ground_y, gmin.z),
		Vector3i(cx + 1, ground_y + 1, gmax.z),
		VoxelMaterial.GRAVEL
	)
	brush.fill_box(
		Vector3i(gmin.x, ground_y, cz),
		Vector3i(gmax.x, ground_y + 1, cz + 1),
		VoxelMaterial.GRAVEL
	)
	brush.set_vox(Vector3i(cx, ground_y + 1, cz), VoxelMaterial.PLANTER)
	brush.set_vox(Vector3i(cx, ground_y + 2, cz), VoxelMaterial.PARK)
	_tree(cx - 2, ground_y, cz - 2)


func _lawn(min_v: Vector3i, max_v: Vector3i) -> void:
	brush.fill_box(min_v, max_v, VoxelMaterial.DIRT)
	brush.fill_box(min_v, max_v, VoxelMaterial.PARK)


func _cross_paths(min_v: Vector3i, max_v: Vector3i) -> void:
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	brush.fill_box(
		Vector3i(cx - 1, ground_y, min_v.z),
		Vector3i(cx + 2, ground_y + 1, max_v.z),
		VoxelMaterial.GRAVEL
	)
	brush.fill_box(
		Vector3i(min_v.x, ground_y, cz - 1),
		Vector3i(max_v.x, ground_y + 1, cz + 2),
		VoxelMaterial.GRAVEL
	)
	# Diagonal meander accents
	for t in range(min_v.x + 2, max_v.x - 2, 3):
		var z := min_v.z + 2 + ((t - min_v.x) % maxi(1, max_v.z - min_v.z - 4))
		if z >= max_v.z - 1:
			continue
		brush.set_vox(Vector3i(t, ground_y, z), VoxelMaterial.GRAVEL)
		brush.set_vox(Vector3i(t + 1, ground_y, z), VoxelMaterial.GRAVEL)


func _simple_path(min_v: Vector3i, max_v: Vector3i) -> void:
	var cz := (min_v.z + max_v.z) / 2
	brush.fill_box(
		Vector3i(min_v.x, ground_y, cz),
		Vector3i(max_v.x, ground_y + 1, cz + 1),
		VoxelMaterial.GRAVEL
	)


func _pond(min_v: Vector3i, max_v: Vector3i) -> void:
	var cx := (min_v.x + max_v.x) / 2 + rng.randi_range(-3, 3)
	var cz := (min_v.z + max_v.z) / 2 + rng.randi_range(-2, 2)
	var rx := 4 + rng.randi() % 3
	var rz := 3 + rng.randi() % 2
	for z in range(cz - rz, cz + rz + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < min_v.x + 2 or z < min_v.z + 2 or x >= max_v.x - 2 or z >= max_v.z - 2:
				continue
			var nx := float(x - cx) / float(rx)
			var nz := float(z - cz) / float(rz)
			if nx * nx + nz * nz > 1.0:
				continue
			var edge := nx * nx + nz * nz > 0.72
			if edge:
				brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.STONE)
			else:
				brush.set_vox(Vector3i(x, ground_y, z), VoxelMaterial.WATER)


func _grove(min_v: Vector3i, max_v: Vector3i, count: int) -> void:
	for _i in range(count):
		var x := rng.randi_range(min_v.x + 2, max_v.x - 3)
		var z := rng.randi_range(min_v.z + 2, max_v.z - 3)
		if brush.get_vox(Vector3i(x, ground_y, z)) == VoxelMaterial.WATER:
			continue
		_tree(x, ground_y, z)


func _hedge_beds(min_v: Vector3i, max_v: Vector3i) -> void:
	## Sparse flower boxes / short hedges along a loose grid — not a field of pillars.
	var y0 := ground_y
	for z in range(min_v.z + 4, max_v.z - 4, 11):
		for x in range(min_v.x + 4, max_v.x - 4, 9):
			if brush.get_vox(Vector3i(x, y0, z)) != VoxelMaterial.PARK:
				continue
			if rng.randf() < 0.35:
				continue
			# 2×1 planter box with leaf hedge on top.
			var x1 := x + 1
			if brush.get_vox(Vector3i(x1, y0, z)) != VoxelMaterial.PARK:
				x1 = x
			brush.fill_box(
				Vector3i(x, y0 + 1, z),
				Vector3i(x1 + 1, y0 + 2, z + 1),
				VoxelMaterial.PLANTER
			)
			brush.fill_box(
				Vector3i(x, y0 + 2, z),
				Vector3i(x1 + 1, y0 + 3, z + 1),
				VoxelMaterial.LEAVES
			)
			if rng.randf() < 0.4:
				brush.set_vox(Vector3i(x, y0 + 3, z), VoxelMaterial.PAINT)


func _tree(x: int, y0: int, z: int) -> void:
	var recipe := rng.randi() % 3
	match recipe:
		0:
			_tree_round(x, y0, z)
		1:
			_tree_tall(x, y0, z)
		_:
			_tree_wide(x, y0, z)


func _tree_round(x: int, y0: int, z: int) -> void:
	var trunk_h := 3 + rng.randi() % 4
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) == 2 and absi(dz) == 2:
				continue
			brush.set_vox(Vector3i(x + dx, canopy_y, z + dz), VoxelMaterial.LEAVES)
			if absi(dx) + absi(dz) <= 2:
				brush.set_vox(Vector3i(x + dx, canopy_y + 1, z + dz), VoxelMaterial.LEAVES)


func _tree_tall(x: int, y0: int, z: int) -> void:
	## Narrower, taller canopy — street / grove accent.
	var trunk_h := 5 + rng.randi() % 3
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for layer in range(3):
		var r := 1 if layer == 2 else 2
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and r > 1:
					continue
				if absi(dx) + absi(dz) > r + 1:
					continue
				brush.set_vox(Vector3i(x + dx, canopy_y + layer, z + dz), VoxelMaterial.LEAVES)


func _tree_wide(x: int, y0: int, z: int) -> void:
	## Broader, lower leaf mass.
	var trunk_h := 2 + rng.randi() % 3
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if absi(dx) == 3 and absi(dz) == 3:
				continue
			if absi(dx) * absi(dx) + absi(dz) * absi(dz) > 10:
				continue
			brush.set_vox(Vector3i(x + dx, canopy_y, z + dz), VoxelMaterial.LEAVES)
			if absi(dx) <= 2 and absi(dz) <= 2:
				brush.set_vox(Vector3i(x + dx, canopy_y + 1, z + dz), VoxelMaterial.LEAVES)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Cheap far-tile greens: lawn already painted; drop a few canopy blobs only.
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 8 or d < 8:
		return
	var count := clampi((w * d) / 220, 2, 7)
	for _i in range(count):
		var x := rng.randi_range(min_v.x + 2, max_v.x - 3)
		var z := rng.randi_range(min_v.z + 2, max_v.z - 3)
		_tree_round(x, ground_y, z)
