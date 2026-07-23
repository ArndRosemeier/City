## Composes plaza voxels: paving hierarchy, fountain, trees, seating.
class_name PlazaComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1


func compose_grand(min_v: Vector3i, max_v: Vector3i) -> void:
	_pave(min_v, max_v, true)
	_edge_planters(min_v, max_v)
	_tree_allee(min_v, max_v)
	_fountain(min_v, max_v, true)
	_benches(min_v, max_v, 4)


func compose_satellite(min_v: Vector3i, max_v: Vector3i) -> void:
	_pave(min_v, max_v, false)
	_edge_planters(min_v, max_v)
	if rng.randf() < 0.6:
		_fountain(min_v, max_v, false)
	else:
		_monument(min_v, max_v)
	_benches(min_v, max_v, 2)


func _pave(min_v: Vector3i, max_v: Vector3i, grand: bool) -> void:
	brush.fill_box(min_v, max_v, VoxelMaterial.PLAZA)
	if not grand:
		return
	var inset := 3
	var inner_min := Vector3i(min_v.x + inset, min_v.y, min_v.z + inset)
	var inner_max := Vector3i(max_v.x - inset, max_v.y, max_v.z - inset)
	if inner_max.x > inner_min.x and inner_max.z > inner_min.z:
		brush.fill_box(inner_min, inner_max, VoxelMaterial.TILES)


func _edge_planters(min_v: Vector3i, max_v: Vector3i) -> void:
	var inset := 1
	var y0 := ground_y
	for z in range(min_v.z + inset, max_v.z - inset):
		for x in range(min_v.x + inset, max_v.x - inset):
			var on_ring := (
				x == min_v.x + inset
				or x == max_v.x - inset - 1
				or z == min_v.z + inset
				or z == max_v.z - inset - 1
			)
			if not on_ring:
				continue
			if (x + z) % 3 != 0:
				continue
			brush.set_vox(Vector3i(x, y0 + 1, z), VoxelMaterial.PLANTER)
			brush.set_vox(Vector3i(x, y0 + 2, z), VoxelMaterial.PARK)


func _fountain(min_v: Vector3i, max_v: Vector3i, grand: bool) -> void:
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	var rad := 3 if grand else 2
	var y0 := ground_y
	# Stone rim
	for z in range(cz - rad, cz + rad + 1):
		for x in range(cx - rad, cx + rad + 1):
			var d := maxi(absi(x - cx), absi(z - cz))
			if d == rad:
				brush.set_vox(Vector3i(x, y0, z), VoxelMaterial.STONE)
				brush.set_vox(Vector3i(x, y0 + 1, z), VoxelMaterial.STONE)
			elif d < rad:
				brush.set_vox(Vector3i(x, y0, z), VoxelMaterial.STONE)
				brush.set_vox(Vector3i(x, y0 + 1, z), VoxelMaterial.WATER)
	if grand:
		brush.fill_box(
			Vector3i(cx, y0 + 1, cz),
			Vector3i(cx + 1, y0 + 4, cz + 1),
			VoxelMaterial.STONE
		)


func _monument(min_v: Vector3i, max_v: Vector3i) -> void:
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	var y0 := ground_y
	brush.fill_box(
		Vector3i(cx - 1, y0, cz - 1),
		Vector3i(cx + 2, y0 + 1, cz + 2),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(cx, y0 + 1, cz),
		Vector3i(cx + 1, y0 + 1 + rng.randi_range(5, 9), cz + 1),
		VoxelMaterial.STONE
	)


func _tree_allee(min_v: Vector3i, max_v: Vector3i) -> void:
	var y0 := ground_y
	var margin := 4
	for z in [min_v.z + margin, max_v.z - margin - 1]:
		for x in range(min_v.x + margin, max_v.x - margin, 4):
			_tree(x, y0, z)
	for x in [min_v.x + margin, max_v.x - margin - 1]:
		for z in range(min_v.z + margin + 4, max_v.z - margin, 4):
			_tree(x, y0, z)


func _benches(min_v: Vector3i, max_v: Vector3i, count: int) -> void:
	var y0 := ground_y
	for _i in range(count):
		var x := rng.randi_range(min_v.x + 3, max_v.x - 4)
		var z := rng.randi_range(min_v.z + 3, max_v.z - 4)
		brush.fill_box(
			Vector3i(x, y0 + 1, z),
			Vector3i(x + 2, y0 + 2, z + 1),
			VoxelMaterial.PLANTER
		)


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
	var trunk_h := 4 + rng.randi() % 3
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) + absi(dz) > 3:
				continue
			brush.set_vox(Vector3i(x + dx, canopy_y, z + dz), VoxelMaterial.LEAVES)
			if absi(dx) <= 1 and absi(dz) <= 1:
				brush.set_vox(Vector3i(x + dx, canopy_y + 1, z + dz), VoxelMaterial.LEAVES)


func _tree_tall(x: int, y0: int, z: int) -> void:
	var trunk_h := 6 + rng.randi() % 3
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for layer in range(3):
		var r := 1 if layer == 2 else 2
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dz) > r + 1:
					continue
				brush.set_vox(Vector3i(x + dx, canopy_y + layer, z + dz), VoxelMaterial.LEAVES)


func _tree_wide(x: int, y0: int, z: int) -> void:
	var trunk_h := 3 + rng.randi() % 2
	brush.column(x, z, y0 + 1, y0 + 1 + trunk_h, VoxelMaterial.BARK)
	var canopy_y := y0 + trunk_h
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if absi(dx) * absi(dx) + absi(dz) * absi(dz) > 10:
				continue
			brush.set_vox(Vector3i(x + dx, canopy_y, z + dz), VoxelMaterial.LEAVES)
			if absi(dx) <= 1 and absi(dz) <= 1:
				brush.set_vox(Vector3i(x + dx, canopy_y + 1, z + dz), VoxelMaterial.LEAVES)


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Cheap far plaza: a couple of trees + one bench stub.
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 8 or d < 8:
		return
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	_tree_round(cx - 3, ground_y, cz - 2)
	if w > 14:
		_tree_tall(cx + 4, ground_y, cz + 3)
	brush.fill_box(
		Vector3i(cx, ground_y + 1, cz),
		Vector3i(cx + 2, ground_y + 2, cz + 1),
		VoxelMaterial.PLANTER
	)
