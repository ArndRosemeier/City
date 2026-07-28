## Dumps per-material collision data from VoxelBlockLibrary models.
## Used to derive the navigation solidity table from real collision truth.
extends SceneTree

const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lib: VoxelBlockyLibrary = VoxelBlockLibraryScript.build()
	print("model_count=%d" % lib.models.size())
	var probe := VoxelBlockyModelCube.new()
	print("cube props: ", probe.get_property_list().map(func(p): return p.name))
	for id in range(lib.models.size()):
		var m: VoxelBlockyModel = lib.models[id]
		var cls := m.get_class()
		var mask: int = m.collision_mask
		var aabbs = m.collision_aabbs
		print(
			"id=%d cls=%s mask=%d aabbs=%s"
			% [id, cls, mask, str(aabbs)]
		)
	quit(0)
