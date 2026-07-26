## Composes plaza voxels: paving hierarchy, fountain, trees, seating.
class_name PlazaComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 1
var stamper: TreeStamper
## Paving palette — set from the district theme.
var pave_mat: int = VoxelMaterial.PLAZA
var pave_inner_mat: int = VoxelMaterial.TILES


func _stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper


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
	brush.fill_box(min_v, max_v, pave_mat)
	if not grand:
		return
	var inset := 3
	var inner_min := Vector3i(min_v.x + inset, min_v.y, min_v.z + inset)
	var inner_max := Vector3i(max_v.x - inset, max_v.y, max_v.z - inset)
	if inner_max.x > inner_min.x and inner_max.z > inner_min.z:
		brush.fill_box(inner_min, inner_max, pave_inner_mat)


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
			brush.set_vox(Vector3i(x, y0 + 2, z), VoxelMaterial.LEAVES)


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
			_stamper().plant_random(x, y0, z)
	for x in [min_v.x + margin, max_v.x - margin - 1]:
		for z in range(min_v.z + margin + 4, max_v.z - margin, 4):
			_stamper().plant_random(x, y0, z)


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


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	## Cheap far plaza: a couple of trees + one bench stub.
	var w := max_v.x - min_v.x
	var d := max_v.z - min_v.z
	if w < 8 or d < 8:
		return
	var cx := (min_v.x + max_v.x) / 2
	var cz := (min_v.z + max_v.z) / 2
	_stamper().round_tree(cx - 3, ground_y, cz - 2)
	if w > 14:
		_stamper().tall_tree(cx + 4, ground_y, cz + 3)
	brush.fill_box(
		Vector3i(cx, ground_y + 1, cz),
		Vector3i(cx + 2, ground_y + 2, cz + 1),
		VoxelMaterial.PLANTER
	)
