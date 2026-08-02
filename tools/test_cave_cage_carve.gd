## Headless: cave-cage voxels dissolve (not explode), stay blastable ROCK, and are not zoo-fence.
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
		if not VoxelMaterial.is_dissolve(id):
			push_error("FAIL %d not dissolve" % id)
			failed = true
		if VoxelMaterial.is_explosive(id):
			push_error("FAIL %d still explosive — cage must dissolve, not crater" % id)
			failed = true
		if VoxelMaterial.explosive_radius_m(id) != 0.0:
			push_error("FAIL %d explosive radius %f want 0" % [id, VoxelMaterial.explosive_radius_m(id)])
			failed = true
		var h := VoxelMaterial.hardness(id)
		if h != VoxelMaterial.Hardness.ROCK and h != VoxelMaterial.Hardness.SOFT:
			push_error("FAIL %d hardness %d want ROCK/SOFT" % [id, h])
			failed = true
		if h == VoxelMaterial.Hardness.NEVER:
			push_error("FAIL %d hardness NEVER" % id)
			failed = true
	## Frame, line and glass share one dissolve cluster so a single hit opens the whole cage.
	if not VoxelMaterial.dissolves_with(
		VoxelMaterial.CAVE_CAGE_GLASS, VoxelMaterial.CAVE_CAGE_FRAME
	):
		push_error("FAIL cage glass does not dissolve with frame")
		failed = true
	if not VoxelMaterial.dissolves_with(
		VoxelMaterial.CAVE_CAGE_FRAME, VoxelMaterial.CAVE_CAGE_LINE
	):
		push_error("FAIL cage frame does not dissolve with line")
		failed = true
	if VoxelMaterial.dissolves_with(VoxelMaterial.CAVE_CAGE_FRAME, VoxelMaterial.STONE):
		push_error("FAIL cage wrongly dissolves with STONE")
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
		if VoxelMaterial.is_dissolve(id):
			push_error("FAIL zoo fence %d wrongly dissolve" % id)
			failed = true
	if VoxelMaterial.is_explosive(VoxelMaterial.STONE):
		push_error("FAIL STONE wrongly explosive")
		failed = true
	if VoxelMaterial.is_dissolve(VoxelMaterial.STONE):
		push_error("FAIL STONE wrongly dissolve")
		failed = true
	if VoxelMaterial.COUNT <= VoxelMaterial.CAVE_CAGE_GLASS:
		push_error(
			"FAIL COUNT %d <= CAVE_CAGE_GLASS %d"
			% [VoxelMaterial.COUNT, VoxelMaterial.CAVE_CAGE_GLASS]
		)
		failed = true
	print(
		"cave cage dissolve frame=%d line=%d glass=%d cluster=%d COUNT=%d"
		% [
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_FRAME),
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_LINE),
			VoxelMaterial.hardness(VoxelMaterial.CAVE_CAGE_GLASS),
			VoxelMaterial.dissolve_cluster(VoxelMaterial.CAVE_CAGE_GLASS),
			VoxelMaterial.COUNT,
		]
	)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)
