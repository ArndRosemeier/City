## Assert window glass fills its cell for collision (no seam gaps into hollow interiors).
extends SceneTree


func _initialize() -> void:
	var lib: VoxelBlockyLibrary = VoxelBlockLibrary.build()
	var failed := false
	for id in [VoxelMaterial.GLASS, VoxelMaterial.GLASS_LIT]:
		var model: VoxelBlockyModel = lib.get_model(id)
		if model == null:
			push_error("FAIL no model for id %d" % id)
			failed = true
			continue
		var mesh_model := model as VoxelBlockyModelMesh
		if mesh_model == null:
			push_error("FAIL glass id %d is not a mesh model" % id)
			failed = true
			continue
		var boxes: Array = mesh_model.collision_aabbs
		if boxes.is_empty():
			push_error("FAIL glass id %d has no collision aabbs" % id)
			failed = true
			continue
		var box: AABB = boxes[0]
		if not box.position.is_equal_approx(Vector3.ZERO) or not box.size.is_equal_approx(Vector3.ONE):
			push_error(
				"FAIL glass id %d collision aabb is %s — expected full cell [0,1]^3"
				% [id, box]
			)
			failed = true
			continue
		print("OK glass id %d collision fills cell" % id)
	quit(1 if failed else 0)
