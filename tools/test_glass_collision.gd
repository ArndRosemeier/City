## Assert window glass is an opaque full-cell model (no transparent-pass air holes).
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
		## Engine cubes are the reliable solid pane; custom meshes were culled invisible.
		var cube := model as VoxelBlockyModelCube
		if cube == null:
			push_error("FAIL glass id %d is not VoxelBlockyModelCube (got %s)" % [id, model.get_class()])
			failed = true
			continue
		if int(model.transparency_index) != 0:
			push_error(
				"FAIL glass id %d transparency_index=%d — must stay opaque"
				% [id, model.transparency_index]
			)
			failed = true
			continue
		print("OK glass id %d opaque cube" % id)
	quit(1 if failed else 0)
