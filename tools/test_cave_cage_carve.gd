## Headless: cave-cage voxels must be blastable (ROCK, destructible) and not zoo-fence immune.
extends Node


func _ready() -> void:
	var failed := false
	for id in [
		VoxelMaterial.CAVE_CAGE_FRAME,
		VoxelMaterial.CAVE_CAGE_LINE,
		VoxelMaterial.CAVE_CAGE_GLASS,
	]:
		if not VoxelMaterial.is_cave_cage(id):
			push_error("FAIL %d is_cave_cage false" % id)
			failed = true
		if VoxelMaterial.is_zoo_fence(id):
			push_error("FAIL %d wrongly is_zoo_fence" % id)
			failed = true
		if not VoxelMaterial.is_destructible(id):
			push_error("FAIL %d not destructible" % id)
			failed = true
		if not VoxelMaterial.is_explosive(id):
			push_error("FAIL %d not explosive" % id)
			failed = true
		if VoxelMaterial.explosive_radius_m(id) < 5.0:
			push_error(
				"FAIL %d explosive radius %f too small for whole cage"
				% [id, VoxelMaterial.explosive_radius_m(id)]
			)
			failed = true
		var h := VoxelMaterial.hardness(id)
		if h != VoxelMaterial.Hardness.ROCK and h != VoxelMaterial.Hardness.SOFT:
			push_error("FAIL %d hardness %d want ROCK/SOFT" % [id, h])
			failed = true
		if h == VoxelMaterial.Hardness.NEVER:
			push_error("FAIL %d hardness NEVER" % id)
			failed = true
	for id in [
		VoxelMaterial.ZOO_FENCE_FRAME,
		VoxelMaterial.ZOO_FENCE_LINE,
		VoxelMaterial.ZOO_FENCE_GLASS,
	]:
		if VoxelMaterial.is_destructible(id):
			push_error("FAIL zoo fence %d is destructible" % id)
			failed = true
		if VoxelMaterial.hardness(id) != VoxelMaterial.Hardness.NEVER:
			push_error("FAIL zoo fence %d not NEVER" % id)
			failed = true
		if VoxelMaterial.is_explosive(id):
			push_error("FAIL zoo fence %d wrongly explosive" % id)
			failed = true
	if VoxelMaterial.is_explosive(VoxelMaterial.STONE):
		push_error("FAIL STONE wrongly explosive")
		failed = true
	if VoxelMaterial.COUNT <= VoxelMaterial.CAVE_CAGE_GLASS:
		push_error(
			"FAIL COUNT %d <= CAVE_CAGE_GLASS %d"
			% [VoxelMaterial.COUNT, VoxelMaterial.CAVE_CAGE_GLASS]
		)
		failed = true
	print(
		"cave cage hardness frame=%d line=%d glass=%d COUNT=%d"
		% [
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_FRAME),
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_LINE),
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_GLASS),
			VoxelMaterial.COUNT,
		]
	)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)
